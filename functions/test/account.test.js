'use strict';

// Runs against the Firestore emulator: `npm test` in functions/.
const test = require('node:test');
const assert = require('node:assert/strict');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

const { createAccountDeletion, SWEEP_AFTER_MS } = require('../src/account');

const PROJECT = 'demo-dosemate';
if (!getApps().length) initializeApp({ projectId: PROJECT });
const db = getFirestore();

const A = 'ownerA'; // deletes their account
const B = 'ownerB'; // shared a profile with A
const C = 'carerC'; // cares for A's parent

/** Admin Auth stand-in: users that exist, and the ones deleted. */
function fakeAuth(uids) {
  const users = new Set(uids);
  return {
    deleted: [],
    async deleteUser(uid) {
      if (!users.has(uid)) {
        throw Object.assign(new Error('gone'), { code: 'auth/user-not-found' });
      }
      users.delete(uid);
      this.deleted.push(uid);
    },
    async getUser(uid) {
      if (!users.has(uid)) {
        throw Object.assign(new Error('gone'), { code: 'auth/user-not-found' });
      }
      return { uid };
    },
  };
}

/** Storage stand-in; [failTimes] makes the first calls fail. */
function fakeBucket(failTimes = 0) {
  return {
    prefixes: [],
    async deleteFiles({ prefix }) {
      if (failTimes-- > 0) throw Object.assign(new Error('503'), { code: 503 });
      this.prefixes.push(prefix);
    },
  };
}

async function clear() {
  for (const c of await db.listCollections()) await db.recursiveDelete(c);
}

async function seed() {
  const a = db.doc(`users/${A}`);
  await a.set({ setupCompleted: true });
  await a.collection('devices').doc('tokA').set({ token: 'tokA', platform: 'android' });
  for (const pid of ['self', 'parent1']) {
    const p = a.collection('profiles').doc(pid);
    await p.set({ type: pid === 'self' ? 'self' : 'parent', fullName: pid });
    await p.collection('medicines').doc('m1').set({ name: 'Lisinopril' });
    await p.collection('doseLogs').doc('m1_2026-10-25_480').set({ status: 'taken' });
    await p.collection('visits').doc('v1').set({ title: 'Checkup' });
    await p.collection('doseSnoozes').doc('m1_2026-10-25_480').set({ until: new Date() });
    await p.collection('doseAlerts').doc('m1_2026-10-25_480').set({ type: 'missed' });
  }
  // A shared their parent with C.
  const parent = a.collection('profiles').doc('parent1');
  await parent.collection('members').doc(C).set({ email: 'c@x.org', permissions: { checklist: true } });
  await parent.collection('shareChecklist').doc('m1').set({ name: 'Lisinopril' });
  await db.doc(`users/${C}/sharedProfiles/${A}_parent1`).set({ ownerUid: A, profileId: 'parent1' });
  await db.doc(`users/${C}/profiles/self`).set({ type: 'self', fullName: 'C' });
  await db.doc('invitations/inv-by-a').set({ ownerUid: A, email: 'c@x.org', status: 'accepted' });
  await db.doc('invitations/inv-pending-a').set({ ownerUid: A, email: 'd@x.org', status: 'pending' });
  await db.doc(`rateLimits/${A}`).set({ count: 1 });

  // B shared their profile with A (A is the caretaker there).
  const bp = db.doc(`users/${B}/profiles/bp`);
  await bp.set({ type: 'spouse', fullName: 'B spouse' });
  await bp.collection('medicines').doc('bm').set({ name: 'Metformin' });
  await bp.collection('members').doc(A).set({ email: 'a@x.org', permissions: { checklist: true } });
  await bp.collection('members').doc('other').set({ email: 'o@x.org', permissions: { checklist: true } });
  await db.doc(`users/${A}/sharedProfiles/${B}_bp`).set({ ownerUid: B, profileId: 'bp' });
  await db.doc('invitations/inv-by-b').set({ ownerUid: B, email: 'a@x.org', status: 'accepted', acceptedBy: A });
}

const exists = async (path) => (await db.doc(path).get()).exists;
const fresh = (t) => ({ uid: A, token: { auth_time: Math.floor(t / 1000) - 30 } });

test.beforeEach(async () => {
  await clear();
  await seed();
});

test('requires a recent sign in, and deletes nothing without one', async () => {
  let t = Date.now();
  const auth = fakeAuth([A, B, C]);
  const svc = createAccountDeletion({ db, auth, bucket: fakeBucket(), now: () => t });
  await assert.rejects(
    svc.run({ uid: A, token: { auth_time: Math.floor(t / 1000) - 6 * 60 } }),
    (e) => e.code === 'failed-precondition' && e.details.reason === 'requires-recent-login',
  );
  await assert.rejects(svc.run(null), (e) => e.code === 'unauthenticated');
  assert.ok(await exists(`users/${A}/profiles/self/medicines/m1`));
  assert.deepEqual(auth.deleted, []);
});

test('removes everything the account owns, and only its access to others', async () => {
  const t = Date.now();
  const auth = fakeAuth([A, B, C]);
  const bucket = fakeBucket();
  const svc = createAccountDeletion({ db, auth, bucket, now: () => t });
  assert.deepEqual(await svc.run(fresh(t)), { status: 'deleted' });

  // Whole tree, nested subcollections included.
  const left = await db.doc(`users/${A}`).listCollections();
  assert.equal(left.length, 0);
  assert.equal(await exists(`users/${A}`), false);
  for (const pid of ['self', 'parent1']) {
    for (const sub of ['medicines/m1', 'doseLogs/m1_2026-10-25_480', 'visits/v1',
      'doseSnoozes/m1_2026-10-25_480', 'doseAlerts/m1_2026-10-25_480']) {
      assert.equal(await exists(`users/${A}/profiles/${pid}/${sub}`), false, `${pid}/${sub}`);
    }
  }
  assert.equal(await exists(`users/${A}/devices/tokA`), false);
  assert.equal(await exists(`rateLimits/${A}`), false);
  assert.deepEqual(bucket.prefixes, [`users/${A}/`]);
  assert.deepEqual(auth.deleted, [A]);

  // C loses access to A's parent; C's own data stays.
  assert.equal(await exists(`users/${C}/sharedProfiles/${A}_parent1`), false);
  assert.ok(await exists(`users/${C}/profiles/self`));
  // A's invitations are gone, so their links stop working.
  assert.equal(await exists('invitations/inv-by-a'), false);
  assert.equal(await exists('invitations/inv-pending-a'), false);

  // A was B's caretaker: only that membership goes.
  assert.equal(await exists(`users/${B}/profiles/bp/members/${A}`), false);
  assert.ok(await exists(`users/${B}/profiles/bp`));
  assert.ok(await exists(`users/${B}/profiles/bp/medicines/bm`));
  assert.ok(await exists(`users/${B}/profiles/bp/members/other`));
  assert.ok(await exists('invitations/inv-by-b'));

  const rec = await db.doc(`accountDeletions/${A}`).get();
  assert.equal(rec.get('status'), 'deleted');
  assert.deepEqual(Object.keys(rec.data()).sort(), [
    'attempts', 'deletedAt', 'leaseUntil', 'startedAt', 'status', 'step',
    'sweepAfter', 'updatedAt',
  ]);
});

test('a partial failure is reported, keeps the Auth user, and a retry finishes', async () => {
  const t = Date.now();
  const auth = fakeAuth([A, B, C]);
  const bucket = fakeBucket(1);
  const svc = createAccountDeletion({ db, auth, bucket, now: () => t });
  await assert.rejects(
    svc.run(fresh(t)),
    (e) => e.code === 'internal' && e.details.reason === 'incomplete' && e.details.step === 'files',
  );
  // Never reported deleted; the account can still sign in and retry.
  assert.deepEqual(auth.deleted, []);
  const rec = await db.doc(`accountDeletions/${A}`).get();
  assert.equal(rec.get('status'), 'failed');
  assert.equal(rec.get('failedStep'), 'files');
  // Steps before the failure ran (devices first, so no alerts go out).
  assert.equal(await exists(`users/${A}/devices/tokA`), false);

  assert.deepEqual(await svc.run(fresh(t)), { status: 'deleted' });
  assert.deepEqual(auth.deleted, [A]);
  assert.equal(await exists(`users/${A}/profiles/self`), false);
  assert.equal((await db.doc(`accountDeletions/${A}`).get()).get('attempts'), 2);
});

test('a second run while one is in progress is refused', async () => {
  const t = Date.now();
  await db.doc(`accountDeletions/${A}`).set({
    status: 'running',
    leaseUntil: new Date(t + 60_000),
  });
  const svc = createAccountDeletion({ db, auth: fakeAuth([A]), bucket: fakeBucket(), now: () => t });
  await assert.rejects(svc.run(fresh(t)), (e) => e.code === 'aborted' && e.details.reason === 'in-progress');
  assert.ok(await exists(`users/${A}/profiles/self`));
});

test('the sweep removes writes made after deletion, then the record', async () => {
  let t = Date.now();
  const auth = fakeAuth([A, B, C]);
  const svc = createAccountDeletion({ db, auth, bucket: fakeBucket(), now: () => t });
  await svc.run(fresh(t));
  // Another device, still holding a valid ID token, writes after deletion.
  await db.doc(`users/${A}/profiles/self`).set({ type: 'self', fullName: 'Me' });
  await db.doc(`users/${A}/profiles/self/doseLogs/x`).set({ status: 'taken' });

  // Too early: tokens may still be valid.
  assert.equal(await svc.sweep(), 0);
  assert.ok(await exists(`users/${A}/profiles/self`));

  t += SWEEP_AFTER_MS + 1000;
  assert.equal(await svc.sweep(), 1);
  assert.equal(await exists(`users/${A}/profiles/self`), false);
  assert.equal(await exists(`users/${A}/profiles/self/doseLogs/x`), false);
  assert.equal(await exists(`accountDeletions/${A}`), false);
});

test('the sweep never deletes a live account', async () => {
  let t = Date.now();
  const auth = fakeAuth([A, B, C]);
  const svc = createAccountDeletion({ db, auth, bucket: fakeBucket(1), now: () => t });
  await assert.rejects(svc.run(fresh(t)));
  t += SWEEP_AFTER_MS + 1000;
  assert.equal(await svc.sweep(), 0);
  assert.deepEqual(auth.deleted, []);
  assert.ok(await exists(`users/${A}/profiles/self`));
  assert.ok(await exists(`accountDeletions/${A}`));
});
