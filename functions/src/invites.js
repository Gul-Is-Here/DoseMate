'use strict';

const crypto = require('node:crypto');
const { HttpsError } = require('firebase-functions/v2/https');
const { FieldValue, Timestamp } = require('firebase-admin/firestore');
const { inviteEmail, acceptedEmail } = require('./email');

/** How long an emailed link stays valid. */
const INVITE_TTL_MS = 7 * 24 * 60 * 60 * 1000;
/** Minimum time between two emails for the same invitation. */
const RESEND_COOLDOWN_MS = 60 * 1000;
/** Emails one account may trigger per hour (sends and resends). */
const SENDS_PER_HOUR = 10;
/** Tries at the post-acceptance email before it is left as failed. */
const CONFIRM_MAX_ATTEMPTS = 8;
/** A confirmation claimed longer ago than this is presumed abandoned. */
const CONFIRM_LEASE_MS = 2 * 60 * 1000;

const PERMISSIONS = ['checklist', 'alerts', 'appointments'];
const EMAIL_RE = /^[^\s@]{1,64}@[^\s@]{1,190}\.[^\s@]{2,63}$/;

const sha256 = (s) => crypto.createHash('sha256').update(s).digest('hex');
const newToken = () => crypto.randomBytes(32).toString('base64url');

/** "m•••@family.org": enough to pick the right account, no more. */
function maskEmail(email) {
  const [user, domain] = email.split('@');
  return `${user.slice(0, 1)}•••@${domain}`;
}

function requireUser(auth) {
  if (!auth) throw new HttpsError('unauthenticated', 'Please sign in first.');
  if (auth.token.email_verified !== true || !auth.token.email) {
    throw new HttpsError(
      'failed-precondition',
      'Verify your email address before continuing.',
    );
  }
  return {
    uid: auth.uid,
    email: String(auth.token.email).toLowerCase(),
    name: auth.token.name || '',
  };
}

function cleanPermissions(input) {
  const out = {};
  for (const p of PERMISSIONS) out[p] = input?.[p] === true;
  if (!PERMISSIONS.some((p) => out[p])) {
    throw new HttpsError('invalid-argument', 'Choose at least one permission.');
  }
  return out;
}

function cleanProfileId(id) {
  if (typeof id !== 'string' || !/^[A-Za-z0-9_-]{1,40}$/.test(id)) {
    throw new HttpsError('invalid-argument', 'Choose a profile to share.');
  }
  return id;
}

function cleanEmail(email) {
  const e = typeof email === 'string' ? email.trim().toLowerCase() : '';
  if (!EMAIL_RE.test(e) || e.length > 254) {
    throw new HttpsError('invalid-argument', 'Enter a valid email address.');
  }
  return e;
}

/** A display name safe for a From header. */
const headerName = (s) => String(s).replace(/[\r\n"<>]/g, ' ').trim().slice(0, 80);

/**
 * Invitation service over Firestore. [mailer.send({to, subject, html,
 * text, fromName})] delivers mail; [appUrl] hosts the acceptance page;
 * [auth] is the Admin Auth client (sign-in methods, password-setup links).
 */
function createInviteService({
  db, auth: adminAuth, mailer, appUrl, now = () => Date.now(),
}) {
  const invitations = db.collection('invitations');
  const profileRef = (uid, pid) => db.doc(`users/${uid}/profiles/${pid}`);
  const memberRef = (uid, pid, memberUid) =>
    db.doc(`users/${uid}/profiles/${pid}/members/${memberUid}`);
  const sharedRef = (memberUid, ownerUid, pid) =>
    db.doc(`users/${memberUid}/sharedProfiles/${ownerUid}_${pid}`);

  /** Counts an email against the sender's hourly budget. */
  async function spendRateLimit(uid) {
    const ref = db.doc(`rateLimits/${uid}`);
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const t = now();
      let { windowStart = 0, count = 0 } = snap.exists ? snap.data() : {};
      if (t - windowStart >= 60 * 60 * 1000) {
        windowStart = t;
        count = 0;
      }
      if (count >= SENDS_PER_HOUR) {
        throw new HttpsError(
          'resource-exhausted',
          'Too many invitations sent. Try again in an hour.',
        );
      }
      tx.set(ref, { windowStart, count: count + 1 });
    });
  }

  /** Emails a fresh link; records delivery without throwing. */
  async function deliver(ref, invite, token) {
    const link = `${appUrl}/invite/#t=${token}`;
    const message = inviteEmail({
      inviterName: invite.inviterName,
      email: invite.email,
      link,
    });
    try {
      await mailer.send({ to: invite.email, ...message });
      await ref.update({
        delivery: 'sent',
        deliveryError: FieldValue.delete(),
        lastSentAt: Timestamp.fromMillis(now()),
        sendCount: FieldValue.increment(1),
        updatedAt: Timestamp.fromMillis(now()),
      });
      return true;
    } catch (e) {
      // The SMTP error may hold server details; log it, store a generic one.
      console.error('Invitation email failed', ref.id, e && e.code);
      await ref.update({
        delivery: 'failed',
        deliveryError: 'The email could not be delivered.',
        updatedAt: Timestamp.fromMillis(now()),
      });
      return false;
    }
  }

  async function ownedInvite(uid, inviteId) {
    if (typeof inviteId !== 'string' || !/^[a-f0-9]{64}$/.test(inviteId)) {
      throw new HttpsError('invalid-argument', 'Unknown invitation.');
    }
    const ref = invitations.doc(inviteId);
    const snap = await ref.get();
    if (!snap.exists || snap.get('ownerUid') !== uid) {
      throw new HttpsError('not-found', 'This invitation no longer exists.');
    }
    return { ref, data: snap.data() };
  }

  /** A Firebase uid, never a path. */
  function cleanMemberUid(value) {
    const uid = String(value || '');
    if (!/^[A-Za-z0-9]{1,128}$/.test(uid)) {
      throw new HttpsError('invalid-argument', 'Unknown member.');
    }
    return uid;
  }

  async function requireOwnedProfile(uid, pid) {
    const profile = await profileRef(uid, pid).get();
    if (!profile.exists) {
      throw new HttpsError(
        'permission-denied',
        'You can only share profiles you manage.',
      );
    }
    return profile;
  }

  async function findByToken(data) {
    const token = typeof data?.token === 'string' ? data.token : '';
    if (!/^[A-Za-z0-9_-]{43}$/.test(token)) return null;
    const found = await invitations
      .where('tokenHash', '==', sha256(token))
      .limit(1)
      .get();
    return found.empty ? null : { token, doc: found.docs[0] };
  }

  /** How the caretaker signs in, for the confirmation email. */
  async function signInHelp(uid, email) {
    let record;
    try {
      record = await adminAuth.getUser(uid);
    } catch (e) {
      if (e?.code === 'auth/user-not-found') return null;
      throw e;
    }
    const methods = [...new Set(record.providerData.map((p) => p.providerId))];
    if (methods.length) return { methods };
    // No password and no linked provider (e.g. created by an admin): a
    // Firebase-generated, single-use link lets them choose a password.
    // Existing sign-in methods are never reset.
    const setupLink = await adminAuth.generatePasswordResetLink(email, {
      url: appUrl,
    });
    return { methods, setupLink };
  }

  return {
    maskEmail,

    /** Creates a pending invitation and emails it. */
    async send(auth, data) {
      const me = requireUser(auth);
      const pid = cleanProfileId(data?.profileId);
      const email = cleanEmail(data?.email);
      const permissions = cleanPermissions(data?.permissions);
      if (email === me.email) {
        throw new HttpsError('invalid-argument', "You can't invite yourself.");
      }
      const profile = await requireOwnedProfile(me.uid, pid);
      const existing = await db
        .collection(`users/${me.uid}/profiles/${pid}/members`)
        .where('email', '==', email)
        .limit(1)
        .get();
      if (!existing.empty) {
        throw new HttpsError(
          'already-exists',
          'This person already has access to this profile.',
        );
      }

      await spendRateLimit(me.uid);
      // One invitation document per (owner, profile, email): a second
      // pending invite is impossible, even with simultaneous requests.
      const id = sha256(`${me.uid}|${pid}|${email}`);
      const ref = invitations.doc(id);
      const token = newToken();
      const t = now();
      const invite = {
        ownerUid: me.uid,
        profileId: pid,
        profileName: String(profile.get('fullName') || ''),
        inviterName: me.name || me.email,
        email,
        permissions,
        status: 'pending',
        tokenHash: sha256(token),
        expiresAt: Timestamp.fromMillis(t + INVITE_TTL_MS),
        delivery: 'sending',
        sendCount: 0,
        lastAttemptAt: Timestamp.fromMillis(t),
        createdAt: Timestamp.fromMillis(t),
        updatedAt: Timestamp.fromMillis(t),
      };
      await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        if (
          snap.exists &&
          snap.get('status') === 'pending' &&
          snap.get('expiresAt').toMillis() > t
        ) {
          throw new HttpsError(
            'already-exists',
            'An invitation to this email is already pending. Resend it instead.',
            { inviteId: id },
          );
        }
        tx.set(ref, invite);
      });
      const emailSent = await deliver(ref, invite, token);
      return { inviteId: id, emailSent };
    },

    /** Emails a new link (the old one stops working). */
    async resend(auth, data) {
      const me = requireUser(auth);
      const { ref, data: invite } = await ownedInvite(me.uid, data?.inviteId);
      if (invite.status !== 'pending') {
        throw new HttpsError(
          'failed-precondition',
          'Only pending invitations can be resent.',
        );
      }
      const t = now();
      const last = invite.lastAttemptAt ? invite.lastAttemptAt.toMillis() : 0;
      const wait = RESEND_COOLDOWN_MS - (t - last);
      if (wait > 0) {
        throw new HttpsError(
          'resource-exhausted',
          `Please wait ${Math.ceil(wait / 1000)} seconds before resending.`,
          { retryAfterSeconds: Math.ceil(wait / 1000) },
        );
      }
      await spendRateLimit(me.uid);
      const token = newToken();
      await ref.update({
        tokenHash: sha256(token),
        expiresAt: Timestamp.fromMillis(t + INVITE_TTL_MS),
        delivery: 'sending',
        lastAttemptAt: Timestamp.fromMillis(t),
        updatedAt: Timestamp.fromMillis(t),
      });
      const emailSent = await deliver(ref, invite, token);
      return { inviteId: ref.id, emailSent };
    },

    /** Cancels a pending invitation; its link stops working. */
    async revoke(auth, data) {
      const me = requireUser(auth);
      const { ref, data: invite } = await ownedInvite(me.uid, data?.inviteId);
      if (invite.status === 'pending') {
        await ref.update({
          status: 'revoked',
          revokedAt: Timestamp.fromMillis(now()),
          updatedAt: Timestamp.fromMillis(now()),
        });
      }
      return { ok: true };
    },

    /** Removes a caregiver's access to one of the caller's profiles. */
    async removeMember(auth, data) {
      const me = requireUser(auth);
      const pid = cleanProfileId(data?.profileId);
      const memberUid = cleanMemberUid(data?.memberUid);
      await requireOwnedProfile(me.uid, pid);
      const batch = db.batch();
      batch.delete(memberRef(me.uid, pid, memberUid));
      batch.delete(sharedRef(memberUid, me.uid, pid));
      await batch.commit();
      return { ok: true };
    },

    /** Changes what an existing caregiver may see or do. */
    async updatePermissions(auth, data) {
      const me = requireUser(auth);
      const pid = cleanProfileId(data?.profileId);
      const memberUid = cleanMemberUid(data?.memberUid);
      const permissions = cleanPermissions(data?.permissions);
      const profile = await requireOwnedProfile(me.uid, pid);
      const ref = memberRef(me.uid, pid, memberUid);
      const shared = sharedRef(memberUid, me.uid, pid);
      await db.runTransaction(async (tx) => {
        const [member, mirror] = await Promise.all([tx.get(ref), tx.get(shared)]);
        if (!member.exists) {
          throw new HttpsError('not-found', 'This person no longer has access.');
        }
        if (mirror.exists) {
          tx.update(ref, { permissions });
          tx.update(shared, { permissions });
          return;
        }
        // The caregiver's copy went missing: rebuild it from the
        // invitation that granted access, so the change reaches them.
        const inviteId = member.get('inviteId');
        const invite = typeof inviteId === 'string' && inviteId
          ? await tx.get(db.doc(`invitations/${inviteId}`))
          : null;
        tx.update(ref, { permissions });
        tx.set(shared, {
          ownerUid: me.uid,
          profileId: pid,
          profileName: invite?.get('profileName') || profile.get('fullName') || '',
          ownerName: invite?.get('inviterName') || me.name || me.email || '',
          permissions,
          grantedAt: member.get('grantedAt') ?? Timestamp.fromMillis(now()),
        });
      });
      return { ok: true };
    },

    /**
     * What the acceptance page may show to whoever holds the link. Read
     * only: opening or previewing a link never accepts it. When signed in,
     * [recipient] says whether this account may accept.
     */
    async check(data, auth) {
      const found = await findByToken(data);
      if (!found) return { status: 'invalid' };
      const invite = found.doc.data();
      let status = invite.status;
      if (status === 'pending' && invite.expiresAt.toMillis() <= now()) {
        status = 'expired';
      }
      const result = {
        status,
        inviterName: invite.inviterName,
        profileName: invite.profileName,
        permissions: invite.permissions,
        emailHint: maskEmail(invite.email),
      };
      if (auth?.token?.email) {
        const email = String(auth.token.email).toLowerCase();
        result.recipient =
          email !== invite.email
            ? 'other'
            : auth.token.email_verified === true
              ? 'match'
              : 'unverified';
        if (status === 'accepted') {
          result.acceptedByYou = invite.acceptedBy === auth.uid;
        }
      }
      return result;
    },

    /** Grants access once; repeating it is harmless. */
    async accept(auth, data) {
      const me = requireUser(auth);
      const found = await findByToken(data);
      if (!found) {
        throw new HttpsError(
          'not-found',
          'This invitation link is invalid or was replaced by a newer one.',
        );
      }
      const { token } = found;
      const ref = found.doc.ref;
      return db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        const invite = snap.data();
        if (invite.tokenHash !== sha256(token)) {
          throw new HttpsError('not-found', 'This invitation link was replaced.');
        }
        const member = memberRef(invite.ownerUid, invite.profileId, me.uid);
        const result = {
          ownerUid: invite.ownerUid,
          profileId: invite.profileId,
          profileName: invite.profileName,
          inviterName: invite.inviterName,
        };
        if (invite.status === 'accepted') {
          if (invite.acceptedBy !== me.uid) {
            throw new HttpsError(
              'already-exists',
              'This invitation has already been accepted.',
            );
          }
          // Repeated clicks change nothing. Access removed since then is
          // not quietly restored by an old link.
          if (!(await tx.get(member)).exists) {
            throw new HttpsError(
              'failed-precondition',
              `${invite.inviterName} removed your access since you accepted. ` +
                'Ask them for a new invitation.',
            );
          }
          return { ...result, already: true };
        }
        if (invite.status === 'revoked') {
          throw new HttpsError(
            'failed-precondition',
            'This invitation was cancelled by the sender.',
          );
        }
        if (invite.expiresAt.toMillis() <= now()) {
          throw new HttpsError(
            'deadline-exceeded',
            'This invitation has expired. Ask the sender for a new one.',
          );
        }
        if (me.uid === invite.ownerUid) {
          throw new HttpsError(
            'invalid-argument',
            "You can't accept your own invitation.",
          );
        }
        if (me.email !== invite.email) {
          throw new HttpsError(
            'permission-denied',
            `You're signed in as ${me.email}, but this invitation was sent ` +
              `to ${maskEmail(invite.email)}. Switch to that account to ` +
              'accept it.',
            { reason: 'wrong-account', emailHint: maskEmail(invite.email) },
          );
        }
        const t = Timestamp.fromMillis(now());
        tx.set(member, {
          email: me.email,
          name: me.name || me.email,
          permissions: invite.permissions,
          inviteId: ref.id,
          grantedAt: t,
        });
        tx.set(sharedRef(me.uid, invite.ownerUid, invite.profileId), {
          ownerUid: invite.ownerUid,
          profileId: invite.profileId,
          profileName: invite.profileName,
          ownerName: invite.inviterName,
          permissions: invite.permissions,
          grantedAt: t,
        });
        tx.update(ref, {
          status: 'accepted',
          acceptedBy: me.uid,
          acceptedAt: t,
          updatedAt: t,
          // Sent by [sendConfirmation] once this commits.
          confirmation: { status: 'pending', attempts: 0 },
        });
        return result;
      });
    },

    /**
     * Emails the caretaker after acceptance, on the inviter's behalf. Safe
     * to call repeatedly or concurrently: each attempt is claimed in a
     * transaction, so a sent email is never sent again and access is never
     * touched. Returns 'sent'; 'failed' or 'busy' (another attempt is in
     * flight), both worth retrying later; or 'skipped' (nothing to do).
     */
    async sendConfirmation(inviteId) {
      const ref = invitations.doc(inviteId);
      const claimed = await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        if (!snap.exists || snap.get('status') !== 'accepted') return null;
        const c = snap.get('confirmation') || { attempts: 0 };
        const t = now();
        const leased =
          c.status === 'sending' &&
          t - (c.lastAttemptAt?.toMillis() ?? 0) < CONFIRM_LEASE_MS;
        if (
          c.status === 'sent' ||
          c.status === 'skipped' ||
          c.attempts >= CONFIRM_MAX_ATTEMPTS
        ) {
          return null;
        }
        if (leased) return { busy: true };
        const attempts = (c.attempts || 0) + 1;
        tx.update(ref, {
          confirmation: {
            status: 'sending',
            attempts,
            lastAttemptAt: Timestamp.fromMillis(t),
          },
        });
        return { invite: snap.data(), attempts };
      });
      if (!claimed) return 'skipped';
      if (claimed.busy) return 'busy';
      const { invite, attempts } = claimed;
      const record = (status, extra = {}) =>
        ref.update({
          confirmation: {
            status,
            attempts,
            lastAttemptAt: Timestamp.fromMillis(now()),
            ...extra,
          },
        });
      try {
        const help = await signInHelp(invite.acceptedBy, invite.email);
        if (!help) {
          // The account was deleted after accepting.
          await record('skipped');
          return 'skipped';
        }
        await mailer.send({
          to: invite.email,
          fromName: `${headerName(invite.inviterName)} via DoseMate`,
          ...acceptedEmail({
            inviterName: invite.inviterName,
            profileName: invite.profileName,
            email: invite.email,
            appUrl,
            ...help,
          }),
        });
        await record('sent', { sentAt: Timestamp.fromMillis(now()) });
        return 'sent';
      } catch (e) {
        // Error details may hold server or link data; keep only the code.
        console.error('Confirmation email failed', inviteId, e && e.code);
        await record(attempts >= CONFIRM_MAX_ATTEMPTS ? 'failed' : 'retrying', {
          error: 'The email could not be delivered.',
        });
        return 'failed';
      }
    },
  };
}

/** Caregiver-safe copy of a medicine: schedule only, no dosage or notes. */
function checklistCopy(m) {
  const keep = ['name', 'frequency', 'doseMinutes', 'days', 'startDay',
    'endDay', 'status', 'pastSchedules', 'pauses'];
  const out = {};
  for (const k of keep) if (k in m) out[k] = m[k];
  out.quantity = 0;
  return out;
}

/** Caregiver-safe copy of a dose log: when and whether, no note. */
function logCopy(l) {
  const keep = ['medicineId', 'day', 'minutes', 'status', 'loggedAt'];
  const out = {};
  for (const k of keep) if (k in l) out[k] = l[k];
  if (typeof l.medicineName === 'string') out.medicineName = l.medicineName;
  return out;
}

module.exports = {
  createInviteService,
  checklistCopy,
  logCopy,
  maskEmail,
  INVITE_TTL_MS,
  RESEND_COOLDOWN_MS,
  SENDS_PER_HOUR,
  CONFIRM_MAX_ATTEMPTS,
  CONFIRM_LEASE_MS,
};
