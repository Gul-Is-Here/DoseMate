'use strict';

const { HttpsError } = require('firebase-functions/v2/https');
const { Timestamp } = require('firebase-admin/firestore');

/** Deleting needs a sign in (or reauthentication) this recent. */
const RECENT_LOGIN_SEC = 5 * 60;
/** A run that started longer ago than this is presumed dead. */
const LEASE_MS = 6 * 60 * 1000; // Longer than the function's timeout.
/**
 * An ID token stays valid for up to an hour after the account is gone, so
 * another signed-in device could still write. The data is swept once more
 * after that, then the deletion record goes too.
 */
const SWEEP_AFTER_MS = 65 * 60 * 1000;
/** An unfinished deletion of an account that still exists: kept this long. */
const ABANDONED_AFTER_MS = 30 * 24 * 60 * 60 * 1000;

const STEPS = ['devices', 'sharing', 'memberships', 'files', 'records', 'auth'];

/**
 * Account deletion. [run] is called by the signed-in user after a recent
 * sign in; every step is safe to repeat, so a retry after a partial failure
 * simply runs them all again. The `accountDeletions/{uid}` record (no data
 * but the uid, step and times) guards against parallel runs and lets
 * [sweep] finish what a run left.
 *
 * Removed, in this order:
 * 1. devices: the push tokens, so no server alert can reach the account.
 * 2. sharing: other accounts' access to this account's profiles, and every
 *    invitation this account sent (their links stop working).
 * 3. memberships: this account's access to profiles others shared with it.
 *    Only the membership goes; their profiles are untouched.
 * 4. files: everything in Storage under users/{uid}/.
 * 5. records: users/{uid} with every subcollection at any depth (profiles,
 *    medicines, visits, dose logs, snoozes, alerts, members, shared copies,
 *    devices), and the account's rate limit counter.
 * 6. auth: the Firebase Auth user, last, once the rest is gone.
 */
function createAccountDeletion({ db, auth, bucket, now = () => Date.now() }) {
  const record = (uid) => db.doc(`accountDeletions/${uid}`);
  const userDoc = (uid) => db.doc(`users/${uid}`);

  async function deleteDocs(query) {
    const writer = db.bulkWriter();
    for (;;) {
      const page = await query.limit(400).get();
      if (page.empty) break;
      for (const d of page.docs) writer.delete(d.ref);
      await writer.flush();
      if (page.size < 400) break;
    }
    await writer.close();
  }

  const steps = {
    devices: (uid) => deleteDocs(userDoc(uid).collection('devices')),

    async sharing(uid) {
      const profiles = await userDoc(uid).collection('profiles').get();
      const writer = db.bulkWriter();
      for (const profile of profiles.docs) {
        const members = await profile.ref.collection('members').get();
        for (const m of members.docs) {
          // Their pointer to this profile, and the membership itself.
          writer.delete(db.doc(`users/${m.id}/sharedProfiles/${uid}_${profile.id}`));
          writer.delete(m.ref);
        }
      }
      await writer.close();
      await deleteDocs(db.collection('invitations').where('ownerUid', '==', uid));
    },

    async memberships(uid) {
      const shared = await userDoc(uid).collection('sharedProfiles').get();
      const writer = db.bulkWriter();
      for (const s of shared.docs) {
        const ownerUid = s.get('ownerUid');
        const pid = s.get('profileId');
        if (typeof ownerUid === 'string' && typeof pid === 'string' &&
            ownerUid && pid && !ownerUid.includes('/') && !pid.includes('/')) {
          writer.delete(db.doc(`users/${ownerUid}/profiles/${pid}/members/${uid}`));
        }
        writer.delete(s.ref);
      }
      await writer.close();
    },

    async files(uid) {
      if (!bucket) return;
      await bucket.deleteFiles({ prefix: `users/${uid}/`, force: true });
    },

    async records(uid) {
      await db.recursiveDelete(userDoc(uid));
      await db.doc(`rateLimits/${uid}`).delete();
    },

    async auth(uid) {
      try {
        await auth.deleteUser(uid);
      } catch (e) {
        if (e?.code !== 'auth/user-not-found') throw e;
      }
    },
  };

  /** Runs [names] in order, recording progress; throws on the first failure. */
  async function runSteps(uid, names) {
    for (const step of names) {
      await record(uid).set(
        { step, updatedAt: Timestamp.fromMillis(now()) },
        { merge: true },
      );
      try {
        await steps[step](uid);
      } catch (e) {
        e.step = step;
        throw e;
      }
    }
  }

  /** Claims the run, or refuses while another is still going. */
  async function claim(uid) {
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(record(uid));
      const t = now();
      if (snap.exists && snap.get('status') === 'running' &&
          (snap.get('leaseUntil')?.toMillis() ?? 0) > t) {
        throw new HttpsError(
          'aborted',
          'Your account is already being deleted. Wait a minute, then try again.',
          { reason: 'in-progress' },
        );
      }
      tx.set(record(uid), {
        status: 'running',
        attempts: (snap.exists ? snap.get('attempts') || 0 : 0) + 1,
        startedAt: Timestamp.fromMillis(t),
        updatedAt: Timestamp.fromMillis(t),
        leaseUntil: Timestamp.fromMillis(t + LEASE_MS),
        // Checked by the sweep if this run never finishes.
        sweepAfter: Timestamp.fromMillis(t + SWEEP_AFTER_MS),
      });
    });
  }

  return {
    /** Deletes the caller's account. Resolves only once everything is gone. */
    async run(authCtx) {
      if (!authCtx?.uid) {
        throw new HttpsError('unauthenticated', 'Please sign in first.');
      }
      const uid = authCtx.uid;
      const signedInAt = Number(authCtx.token?.auth_time) || 0;
      if (now() / 1000 - signedInAt > RECENT_LOGIN_SEC) {
        throw new HttpsError(
          'failed-precondition',
          'For your security, confirm it’s you again before deleting your account.',
          { reason: 'requires-recent-login' },
        );
      }
      await claim(uid);
      try {
        await runSteps(uid, STEPS);
      } catch (e) {
        // Codes only: errors can hold paths or server details.
        console.error('Account deletion failed', e.step, e.code ?? e.name);
        await record(uid).set({
          status: 'failed',
          failedStep: e.step || 'unknown',
          leaseUntil: Timestamp.fromMillis(0),
          updatedAt: Timestamp.fromMillis(now()),
        }, { merge: true }).catch(() => {});
        throw new HttpsError(
          'internal',
          'Your account wasn’t fully deleted. Some of your data may already ' +
            'be removed. Try again to finish.',
          { reason: 'incomplete', step: e.step || 'unknown' },
        );
      }
      const t = now();
      await record(uid).set({
        status: 'deleted',
        deletedAt: Timestamp.fromMillis(t),
        leaseUntil: Timestamp.fromMillis(0),
        updatedAt: Timestamp.fromMillis(t),
        sweepAfter: Timestamp.fromMillis(t + SWEEP_AFTER_MS),
      }, { merge: true });
      return { status: 'deleted' };
    },

    /**
     * Finishes deletions: once an account's last ID token has expired,
     * removes anything written since (from another device) and the record.
     * Unfinished runs whose Auth user is already gone are completed; ones
     * for accounts that still exist wait for the user to retry, and their
     * record is dropped after [ABANDONED_AFTER_MS]. Returns how many
     * records were closed.
     */
    async sweep() {
      const due = await db.collection('accountDeletions')
        .where('sweepAfter', '<=', Timestamp.fromMillis(now()))
        .limit(100)
        .get();
      let closed = 0;
      for (const d of due.docs) {
        const uid = d.id;
        try {
          let exists = true;
          try {
            await auth.getUser(uid);
          } catch (e) {
            if (e?.code !== 'auth/user-not-found') throw e;
            exists = false;
          }
          // A live account is never deleted here: its owner retries from
          // the app (a finished deletion can't have a live user: uids
          // aren't reused).
          if (exists) {
            const started = d.get('startedAt')?.toMillis() ?? 0;
            if (now() - started > ABANDONED_AFTER_MS) {
              await d.ref.delete();
              closed++;
            } else {
              await d.ref.update({
                sweepAfter: Timestamp.fromMillis(now() + 24 * 60 * 60 * 1000),
              });
            }
            continue;
          }
          // The Auth user is gone: remove anything written since, then
          // the record.
          await runSteps(uid, STEPS);
          await d.ref.delete();
          closed++;
        } catch (e) {
          console.error('Deletion sweep failed', e.step, e.code ?? e.name);
        }
      }
      return closed;
    },
  };
}

module.exports = {
  createAccountDeletion, RECENT_LOGIN_SEC, LEASE_MS, SWEEP_AFTER_MS,
  ABANDONED_AFTER_MS, STEPS,
};
