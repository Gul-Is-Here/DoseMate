'use strict';

// Runs against the Firestore emulator: `npm test` in functions/.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, Timestamp } = require('firebase-admin/firestore');
const { getAuth } = require('firebase-admin/auth');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const {
  doc, getDoc, getDocs, setDoc, deleteDoc, collection, serverTimestamp,
  Timestamp: ClientTimestamp,
} = require('firebase/firestore');

const {
  createInviteService,
  checklistCopy,
  logCopy,
  INVITE_TTL_MS,
  RESEND_COOLDOWN_MS,
  SENDS_PER_HOUR,
  CONFIRM_MAX_ATTEMPTS,
  CONFIRM_LEASE_MS,
} = require('../src/invites');

const PROJECT = 'demo-dosemate';
initializeApp({ projectId: PROJECT });
const db = getFirestore();
const adminAuth = getAuth();

const sha = (s) => crypto.createHash('sha256').update(s).digest('hex');

const user = (uid, email, { verified = true, name } = {}) => ({
  uid,
  token: { email, email_verified: verified, name: name ?? uid },
});
const OWNER = user('owner1', 'eleanor@example.com', { name: 'Eleanor Vance' });
const ROBERT = user('robert1', 'robert@example.com', { name: 'Robert Vance' });
const MALLORY = user('mallory1', 'mallory@example.com');

let clock;
let mail;
let svc;

function fakeMailer() {
  const sent = [];
  return {
    sent,
    fail: false,
    async send(m) {
      if (this.fail) throw Object.assign(new Error('SMTP down'), { code: 'ECONNECTION' });
      sent.push(m);
    },
  };
}

const tokenFrom = (message) => /#t=([A-Za-z0-9_-]{43})/.exec(message.text)[1];
const inviteOf = async (id) => (await db.doc(`invitations/${id}`).get()).data();

async function clear() {
  await fetch(
    `http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${PROJECT}/databases/(default)/documents`,
    { method: 'DELETE' },
  );
  await fetch(
    `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/emulator/v1/projects/${PROJECT}/accounts`,
    { method: 'DELETE' },
  );
}

/** Auth accounts behind the test users, with real sign-in methods. */
async function seedAccounts() {
  await adminAuth.createUser({
    uid: 'robert1', email: 'robert@example.com', password: 'correct-horse-9',
    emailVerified: true,
  });
}

async function seedProfile(uid = OWNER.uid, pid = 'self', fullName = 'Eleanor Vance') {
  await db.doc(`users/${uid}/profiles/${pid}`).set({ type: 'self', fullName });
}

async function expectCode(promise, code) {
  await assert.rejects(promise, (e) => {
    assert.equal(e.code, code, e.message);
    return true;
  });
}

const perms = { checklist: true, alerts: true, appointments: false };

test.beforeEach(async () => {
  await clear();
  clock = Date.UTC(2026, 9, 24, 14);
  mail = fakeMailer();
  svc = createInviteService({
    db,
    mailer: mail,
    appUrl: 'https://dosemate-70150.web.app',
    auth: adminAuth,
    now: () => clock,
  });
  await seedProfile();
  await seedAccounts();
});

/** Sends and accepts an invitation for ROBERT; returns its id. */
async function acceptedInvite() {
  const r = await svc.send(OWNER, { profileId: 'self', email: 'robert@example.com', permissions: perms });
  await svc.accept(ROBERT, { token: tokenFrom(mail.sent[0]) });
  mail.sent.length = 0;
  return r.inviteId;
}

test('send: pending invite with hashed token; email has the link only', async () => {
  const r = await svc.send(OWNER, {
    profileId: 'self',
    email: ' Robert@Example.com ',
    permissions: perms,
  });
  assert.equal(r.emailSent, true);
  assert.equal(mail.sent.length, 1);
  const m = mail.sent[0];
  assert.equal(m.to, 'robert@example.com');
  const token = tokenFrom(m);
  const inv = await inviteOf(r.inviteId);
  assert.equal(inv.status, 'pending');
  assert.equal(inv.delivery, 'sent');
  assert.equal(inv.tokenHash, sha(token));
  assert.ok(!JSON.stringify(inv).includes(token), 'raw token is not stored');
  assert.equal(inv.expiresAt.toMillis(), clock + INVITE_TTL_MS);
  assert.deepEqual(inv.permissions, perms);
  // The link carries the token in the fragment and nothing about the profile.
  assert.match(m.text, /https:\/\/dosemate-70150\.web\.app\/invite\/#t=/);
  // It names the address to sign in with, so the right account is used.
  assert.match(m.text, /Sign in as robert@example\.com/);
  assert.ok(!m.html.includes('self') || !m.html.includes('profileId'));
  assert.ok(!/profile=|pid=|uid=|owner/i.test(m.text.split('\n')[2]));
});

test('send: refuses self, unowned profiles, unverified and bad input', async () => {
  await expectCode(
    svc.send(OWNER, { profileId: 'self', email: 'ELEANOR@example.com', permissions: perms }),
    'invalid-argument',
  );
  await expectCode(
    svc.send(MALLORY, { profileId: 'self', email: 'x@example.com', permissions: perms }),
    'permission-denied',
  );
  await expectCode(
    svc.send(user('owner1', 'eleanor@example.com', { verified: false }), {
      profileId: 'self', email: 'x@example.com', permissions: perms,
    }),
    'failed-precondition',
  );
  await expectCode(svc.send(null, {}), 'unauthenticated');
  await expectCode(
    svc.send(OWNER, { profileId: 'self', email: 'not-an-email', permissions: perms }),
    'invalid-argument',
  );
  await expectCode(
    svc.send(OWNER, { profileId: 'self', email: 'x@example.com', permissions: {} }),
    'invalid-argument',
  );
  assert.equal(mail.sent.length, 0);
});

test('send: no duplicate pending invitations, even concurrently', async () => {
  const results = await Promise.allSettled([
    svc.send(OWNER, { profileId: 'self', email: 'robert@example.com', permissions: perms }),
    svc.send(OWNER, { profileId: 'self', email: 'robert@example.com', permissions: perms }),
  ]);
  const ok = results.filter((r) => r.status === 'fulfilled');
  const dup = results.filter((r) => r.status === 'rejected');
  assert.equal(ok.length, 1);
  assert.equal(dup.length, 1);
  assert.equal(dup[0].reason.code, 'already-exists');
  assert.equal(dup[0].reason.details.inviteId, ok[0].value.inviteId);
  assert.equal((await db.collection('invitations').get()).size, 1);
});

test('delivery failure: invitation kept, retry resends without duplicates', async () => {
  mail.fail = true;
  const r = await svc.send(OWNER, { profileId: 'self', email: 'robert@example.com', permissions: perms });
  assert.equal(r.emailSent, false);
  let inv = await inviteOf(r.inviteId);
  assert.equal(inv.status, 'pending');
  assert.equal(inv.delivery, 'failed');
  assert.equal(inv.deliveryError, 'The email could not be delivered.');

  mail.fail = false;
  await expectCode(svc.resend(OWNER, { inviteId: r.inviteId }), 'resource-exhausted'); // cooldown
  clock += RESEND_COOLDOWN_MS;
  const again = await svc.resend(OWNER, { inviteId: r.inviteId });
  assert.equal(again.emailSent, true);
  assert.equal(again.inviteId, r.inviteId);
  inv = await inviteOf(r.inviteId);
  assert.equal(inv.delivery, 'sent');
  assert.equal(inv.deliveryError, undefined);
  assert.equal((await db.collection('invitations').get()).size, 1);
});

test('resend rotates the link: the old one stops working', async () => {
  const r = await svc.send(OWNER, { profileId: 'self', email: 'robert@example.com', permissions: perms });
  const oldToken = tokenFrom(mail.sent[0]);
  clock += RESEND_COOLDOWN_MS;
  await svc.resend(OWNER, { inviteId: r.inviteId });
  const newToken = tokenFrom(mail.sent[1]);
  assert.notEqual(oldToken, newToken);
  assert.equal((await svc.check({ token: oldToken })).status, 'invalid');
  await expectCode(svc.accept(ROBERT, { token: oldToken }), 'not-found');
  await svc.accept(ROBERT, { token: newToken });
});

test('rate limit: at most SENDS_PER_HOUR emails per sender per hour', async () => {
  for (let i = 0; i < SENDS_PER_HOUR; i++) {
    await svc.send(OWNER, { profileId: 'self', email: `p${i}@example.com`, permissions: perms });
  }
  await expectCode(
    svc.send(OWNER, { profileId: 'self', email: 'late@example.com', permissions: perms }),
    'resource-exhausted',
  );
  assert.equal((await db.collection('invitations').get()).size, SENDS_PER_HOUR);
  clock += 60 * 60 * 1000;
  await svc.send(OWNER, { profileId: 'self', email: 'late@example.com', permissions: perms });
});

test('accept: only the invited, verified email; atomic and repeatable', async () => {
  const r = await svc.send(OWNER, { profileId: 'self', email: 'robert@example.com', permissions: perms });
  const token = tokenFrom(mail.sent[0]);

  const preview = await svc.check({ token });
  assert.deepEqual(preview, {
    status: 'pending',
    inviterName: 'Eleanor Vance',
    profileName: 'Eleanor Vance',
    permissions: perms,
    emailHint: 'r•••@example.com',
  });
  // Checking (e.g. a mail client previewing the link) never accepts.
  assert.equal((await inviteOf(r.inviteId)).status, 'pending');

  await expectCode(svc.accept(MALLORY, { token }), 'permission-denied');
  await expectCode(
    svc.accept(user('robert1', 'robert@example.com', { verified: false }), { token }),
    'failed-precondition',
  );
  await expectCode(svc.accept(null, { token }), 'unauthenticated');
  assert.equal((await db.collection('users/owner1/profiles/self/members').get()).size, 0);

  const a = await svc.accept(ROBERT, { token });
  assert.deepEqual(a, {
    ownerUid: 'owner1',
    profileId: 'self',
    profileName: 'Eleanor Vance',
    inviterName: 'Eleanor Vance',
  });
  const member = (await db.doc('users/owner1/profiles/self/members/robert1').get()).data();
  assert.equal(member.email, 'robert@example.com');
  assert.deepEqual(member.permissions, perms);
  const shared = (await db.doc('users/robert1/sharedProfiles/owner1_self').get()).data();
  assert.equal(shared.ownerUid, 'owner1');
  assert.equal(shared.profileName, 'Eleanor Vance');
  // The owner's profile is untouched (not copied, owner unchanged).
  assert.deepEqual(
    (await db.doc('users/owner1/profiles/self').get()).data(),
    { type: 'self', fullName: 'Eleanor Vance' },
  );
  assert.equal((await inviteOf(r.inviteId)).status, 'accepted');

  // Clicking again is harmless; someone else can't reuse it.
  const again = await svc.accept(ROBERT, { token });
  assert.equal(again.already, true);
  assert.equal((await db.collection('users/owner1/profiles/self/members').get()).size, 1);
  await expectCode(
    svc.accept(user('other', 'robert@example.com'), { token }),
    'already-exists',
  );
  assert.equal((await svc.check({ token })).status, 'accepted');

  // Already a member: a new invitation is refused.
  await expectCode(
    svc.send(OWNER, { profileId: 'self', email: 'robert@example.com', permissions: perms }),
    'already-exists',
  );
});

test('expired, revoked and invalid links fail with clear errors', async () => {
  const r = await svc.send(OWNER, { profileId: 'self', email: 'robert@example.com', permissions: perms });
  const token = tokenFrom(mail.sent[0]);
  clock += INVITE_TTL_MS;
  assert.equal((await svc.check({ token })).status, 'expired');
  await expectCode(svc.accept(ROBERT, { token }), 'deadline-exceeded');

  // An expired invitation no longer blocks a fresh one.
  const fresh = await svc.send(OWNER, { profileId: 'self', email: 'robert@example.com', permissions: perms });
  assert.equal(fresh.inviteId, r.inviteId);
  const token2 = tokenFrom(mail.sent[1]);
  await svc.revoke(OWNER, { inviteId: r.inviteId });
  assert.equal((await svc.check({ token: token2 })).status, 'revoked');
  await expectCode(svc.accept(ROBERT, { token: token2 }), 'failed-precondition');
  await expectCode(svc.resend(OWNER, { inviteId: r.inviteId }), 'failed-precondition');

  assert.equal((await svc.check({ token: 'x' })).status, 'invalid');
  assert.equal((await svc.check({ token: 'A'.repeat(43) })).status, 'invalid');
  await expectCode(svc.accept(ROBERT, { token: 'A'.repeat(43) }), 'not-found');
  // Others can't revoke or resend someone else's invitation.
  await expectCode(svc.revoke(MALLORY, { inviteId: r.inviteId }), 'not-found');
});

test('check tells a signed-in visitor whether this account may accept', async () => {
  const r = await svc.send(OWNER, { profileId: 'self', email: 'robert@example.com', permissions: perms });
  const token = tokenFrom(mail.sent[0]);
  assert.equal((await svc.check({ token }, ROBERT)).recipient, 'match');
  assert.equal((await svc.check({ token }, MALLORY)).recipient, 'other');
  assert.equal(
    (await svc.check({ token }, user('robert1', 'Robert@Example.com', { verified: false }))).recipient,
    'unverified',
  );
  assert.equal((await svc.check({ token })).recipient, undefined);

  await expectCode(svc.accept(MALLORY, { token }), 'permission-denied');
  await assert.rejects(svc.accept(MALLORY, { token }), (e) => {
    assert.equal(e.details.reason, 'wrong-account');
    assert.equal(e.details.emailHint, 'r•••@example.com');
    assert.match(e.message, /signed in as mallory@example\.com/);
    return true;
  });

  await svc.accept(ROBERT, { token });
  const after = await svc.check({ token }, ROBERT);
  assert.equal(after.status, 'accepted');
  assert.equal(after.acceptedByYou, true);
  assert.equal((await svc.check({ token }, MALLORY)).acceptedByYou, false);
  assert.equal((await inviteOf(r.inviteId)).confirmation.status, 'pending');
});

test('concurrent accepts grant access once', async () => {
  const r = await svc.send(OWNER, { profileId: 'self', email: 'robert@example.com', permissions: perms });
  const token = tokenFrom(mail.sent[0]);
  const results = await Promise.all([
    svc.accept(ROBERT, { token }),
    svc.accept(ROBERT, { token }),
    svc.accept(ROBERT, { token }),
  ]);
  assert.equal(results.filter((x) => !x.already).length, 1);
  assert.equal((await db.collection('users/owner1/profiles/self/members').get()).size, 1);
  assert.equal((await db.collection('users/robert1/sharedProfiles').get()).size, 1);
  assert.equal((await inviteOf(r.inviteId)).acceptedBy, 'robert1');
});

test('an old link does not restore access the owner removed', async () => {
  await svc.send(OWNER, { profileId: 'self', email: 'robert@example.com', permissions: perms });
  const token = tokenFrom(mail.sent[0]);
  await svc.accept(ROBERT, { token });
  await svc.removeMember(OWNER, { profileId: 'self', memberUid: 'robert1' });
  await expectCode(svc.accept(ROBERT, { token }), 'failed-precondition');
  assert.equal((await db.doc('users/owner1/profiles/self/members/robert1').get()).exists, false);
  // A fresh invitation works again.
  await svc.send(OWNER, { profileId: 'self', email: 'robert@example.com', permissions: perms });
  const again = await svc.accept(ROBERT, { token: tokenFrom(mail.sent[1]) });
  assert.equal(again.already, undefined);
});

test('confirmation: one email with login details, never a password', async () => {
  const id = await acceptedInvite();
  assert.equal(await svc.sendConfirmation(id), 'sent');
  assert.equal(mail.sent.length, 1);
  const m = mail.sent[0];
  assert.equal(m.to, 'robert@example.com');
  assert.equal(m.fromName, 'Eleanor Vance via DoseMate');
  assert.match(m.subject, /Eleanor Vance's DoseMate care circle/);
  assert.match(m.text, /Shared profile: Eleanor Vance/);
  assert.match(m.text, /Your DoseMate login: robert@example\.com/);
  assert.match(m.text, /https:\/\/dosemate-70150\.web\.app/);
  assert.match(m.text, /your email address and password/);
  assert.ok(!m.text.includes('correct-horse-9') && !m.html.includes('correct-horse-9'));
  assert.ok(!/oobCode|Set your password/.test(m.text), 'no reset link for an existing password');
  const c = (await inviteOf(id)).confirmation;
  assert.equal(c.status, 'sent');
  assert.equal(c.attempts, 1);

  // Repeats (trigger retries, repeated clicks) never send it again.
  assert.equal(await svc.sendConfirmation(id), 'skipped');
  await svc.accept(ROBERT, { token: 'unused'.padEnd(43, 'x') }).catch(() => {});
  assert.equal(mail.sent.length, 1);
});

test('confirmation: concurrent attempts send one email', async () => {
  const id = await acceptedInvite();
  const results = await Promise.all([1, 2, 3].map(() => svc.sendConfirmation(id)));
  assert.equal(results.filter((x) => x === 'sent').length, 1);
  assert.equal(mail.sent.length, 1);
});

test('confirmation: failures are recorded, retried, and never undo access', async () => {
  const id = await acceptedInvite();
  mail.fail = true;
  assert.equal(await svc.sendConfirmation(id), 'failed');
  let inv = await inviteOf(id);
  assert.equal(inv.status, 'accepted');
  assert.equal(inv.confirmation.status, 'retrying');
  assert.equal(inv.confirmation.attempts, 1);
  assert.equal(inv.confirmation.error, 'The email could not be delivered.');
  assert.equal((await db.doc('users/owner1/profiles/self/members/robert1').get()).exists, true);

  mail.fail = false;
  assert.equal(await svc.sendConfirmation(id), 'sent');
  inv = await inviteOf(id);
  assert.equal(inv.confirmation.status, 'sent');
  assert.equal(inv.confirmation.attempts, 2);
  assert.equal((await db.collection('users/owner1/profiles/self/members').get()).size, 1);
});

test('confirmation: gives up after the attempt limit; respects an in-flight attempt', async () => {
  const id = await acceptedInvite();
  mail.fail = true;
  for (let i = 0; i < CONFIRM_MAX_ATTEMPTS; i++) {
    assert.equal(await svc.sendConfirmation(id), 'failed');
  }
  assert.equal((await inviteOf(id)).confirmation.status, 'failed');
  assert.equal(await svc.sendConfirmation(id), 'skipped');

  const id2 = sha('other');
  await db.doc(`invitations/${id2}`).set({
    ...(await inviteOf(id)),
    confirmation: { status: 'sending', attempts: 1, lastAttemptAt: Timestamp.fromMillis(clock) },
  });
  mail.fail = false;
  assert.equal(await svc.sendConfirmation(id2), 'busy');
  clock += CONFIRM_LEASE_MS;
  assert.equal(await svc.sendConfirmation(id2), 'sent');
});

test('confirmation: Google accounts are told to use Google, not a password', async () => {
  await adminAuth.deleteUser('robert1');
  await adminAuth.importUsers([{
    uid: 'robert1',
    email: 'robert@example.com',
    emailVerified: true,
    providerData: [{ uid: 'g-robert', providerId: 'google.com', email: 'robert@example.com' }],
  }]);
  const id = await acceptedInvite();
  await svc.sendConfirmation(id);
  const m = mail.sent[0];
  assert.match(m.text, /"Continue with Google"/);
  assert.ok(!/password and that|Set your password/.test(m.text));
});

test('confirmation: an account without a sign-in method gets a setup link', async () => {
  await adminAuth.deleteUser('robert1');
  await adminAuth.createUser({ uid: 'robert1', email: 'robert@example.com', emailVerified: true });
  const id = await acceptedInvite();
  assert.equal(await svc.sendConfirmation(id), 'sent');
  const m = mail.sent[0];
  assert.match(m.text, /Set your password: http\S*oobCode=/);
  assert.match(m.html, /Set your password/);
  // The link is only in the email, never stored.
  assert.ok(!JSON.stringify(await inviteOf(id)).includes('oobCode'));
  // The account itself is unchanged: no password set on our side.
  assert.equal((await adminAuth.getUser('robert1')).providerData.length, 0);
});

test('confirmation: skipped when not accepted or the account is gone', async () => {
  const pending = await svc.send(OWNER, { profileId: 'self', email: 'p@example.com', permissions: perms });
  assert.equal(await svc.sendConfirmation(pending.inviteId), 'skipped');

  mail.sent.length = 0;
  const id = await acceptedInvite();
  await adminAuth.deleteUser('robert1');
  assert.equal(await svc.sendConfirmation(id), 'skipped');
  assert.equal((await inviteOf(id)).confirmation.status, 'skipped');
  assert.equal(mail.sent.length, 0);
});

test('permissions: bad member ids refused; a missing copy is rebuilt', async () => {
  await svc.send(OWNER, { profileId: 'self', email: 'robert@example.com', permissions: perms });
  await svc.accept(ROBERT, { token: tokenFrom(mail.sent[0]) });
  const next = { checklist: true, alerts: false, appointments: true };
  for (const memberUid of ['', 'a/b', 'x'.repeat(129)]) {
    await expectCode(
      svc.updatePermissions(OWNER, { profileId: 'self', memberUid, permissions: next }),
      'invalid-argument',
    );
  }
  const copy = db.doc('users/robert1/sharedProfiles/owner1_self');
  const before = (await copy.get()).data();
  await copy.delete();
  await svc.updatePermissions(OWNER, { profileId: 'self', memberUid: 'robert1', permissions: next });
  const after = (await copy.get()).data();
  assert.deepEqual(after.permissions, next);
  assert.equal(after.profileName, before.profileName);
  assert.equal(after.ownerName, before.ownerName);
  assert.equal(after.ownerUid, 'owner1');
});

test('owner can change permissions and remove a member', async () => {
  await svc.send(OWNER, { profileId: 'self', email: 'robert@example.com', permissions: perms });
  await svc.accept(ROBERT, { token: tokenFrom(mail.sent[0]) });
  const next = { checklist: false, alerts: false, appointments: true };
  await expectCode(
    svc.updatePermissions(ROBERT, { profileId: 'self', memberUid: 'robert1', permissions: next }),
    'permission-denied',
  );
  await svc.updatePermissions(OWNER, { profileId: 'self', memberUid: 'robert1', permissions: next });
  assert.deepEqual(
    (await db.doc('users/robert1/sharedProfiles/owner1_self').get()).get('permissions'),
    next,
  );
  await svc.removeMember(OWNER, { profileId: 'self', memberUid: 'robert1' });
  assert.equal((await db.doc('users/owner1/profiles/self/members/robert1').get()).exists, false);
  assert.equal((await db.doc('users/robert1/sharedProfiles/owner1_self').get()).exists, false);
});

test('caregiver copies drop dosage, notes and photos', () => {
  const med = {
    name: 'Amoxicillin', dosage: '500mg', notes: 'with food', photoUrl: 'u',
    photoPath: 'p', frequency: 'onceDaily', doseMinutes: [480], startDay: '2026-10-24',
    endDay: '2026-10-30', status: 'active', quantity: 12,
  };
  assert.deepEqual(checklistCopy(med), {
    name: 'Amoxicillin', frequency: 'onceDaily', doseMinutes: [480],
    startDay: '2026-10-24', endDay: '2026-10-30', status: 'active', quantity: 0,
  });
  const log = {
    medicineId: 'amox', day: '2026-10-24', minutes: 480, status: 'taken',
    note: 'felt sick', dosage: '500mg', medicineName: 'Amoxicillin', loggedAt: 1,
  };
  assert.deepEqual(logCopy(log), {
    medicineId: 'amox', day: '2026-10-24', minutes: 480, status: 'taken',
    loggedAt: 1, medicineName: 'Amoxicillin',
  });
});

// Security rules, as clients see them.
test('rules: members see only what they were granted', async (t) => {
  const env = await initializeTestEnvironment({
    projectId: PROJECT,
    firestore: {
      rules: fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8'),
    },
  });
  t.after(() => env.cleanup());
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const d = ctx.firestore();
    await setDoc(doc(d, 'users/owner1/profiles/self'), { type: 'self', fullName: 'Eleanor' });
    await setDoc(doc(d, 'users/owner1/profiles/self/medicines/amox'), { name: 'Amoxicillin', dosage: '500mg' });
    await setDoc(doc(d, 'users/owner1/profiles/self/shareChecklist/amox'), { name: 'Amoxicillin' });
    await setDoc(doc(d, 'users/owner1/profiles/self/doseLogs/l1'), { note: 'private' });
    await setDoc(doc(d, 'users/owner1/profiles/self/shareLogs/l1'), { status: 'taken' });
    await setDoc(doc(d, 'users/owner1/profiles/self/visits/v1'), { title: 'Dentist' });
    await setDoc(doc(d, 'users/owner1/profiles/self/members/robert1'), {
      email: 'robert@example.com',
      permissions: { checklist: true, alerts: true, appointments: false },
    });
    await setDoc(doc(d, 'users/owner1/profiles/self/members/sarah1'), {
      email: 'sarah@example.com',
      permissions: { checklist: false, alerts: false, appointments: true },
    });
    await setDoc(doc(d, 'users/robert1/sharedProfiles/owner1_self'), { ownerUid: 'owner1' });
    await setDoc(doc(d, 'invitations/i1'), { ownerUid: 'owner1', tokenHash: 'h' });
  });
  const as = (uid, email, verified = true) =>
    env.authenticatedContext(uid, { email, email_verified: verified }).firestore();
  const robert = as('robert1', 'robert@example.com');
  const sarah = as('sarah1', 'sarah@example.com');
  const stranger = as('x1', 'x@example.com');
  const owner = as('owner1', 'eleanor@example.com');

  // Checklist members: the safe copies only.
  await assertSucceeds(getDoc(doc(robert, 'users/owner1/profiles/self/shareChecklist/amox')));
  await assertSucceeds(getDocs(collection(robert, 'users/owner1/profiles/self/shareLogs')));
  await assertFails(getDoc(doc(robert, 'users/owner1/profiles/self/medicines/amox')));
  await assertFails(getDoc(doc(robert, 'users/owner1/profiles/self/doseLogs/l1')));
  await assertFails(getDoc(doc(robert, 'users/owner1/profiles/self')));
  await assertFails(getDoc(doc(robert, 'users/owner1/profiles/self/visits/v1')));
  // Unverified email: nothing.
  await assertFails(
    getDoc(doc(as('robert1', 'robert@example.com', false), 'users/owner1/profiles/self/shareChecklist/amox')),
  );

  // Appointment members: visits, add and reschedule, not delete.
  await assertSucceeds(getDocs(collection(sarah, 'users/owner1/profiles/self/visits')));
  await assertFails(getDoc(doc(sarah, 'users/owner1/profiles/self/shareChecklist/amox')));
  const visit = {
    title: 'Physio', category: 'Specialist', startsAt: ClientTimestamp.fromMillis(Date.UTC(2026, 9, 30)),
    status: 'scheduled', createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
  };
  await assertSucceeds(setDoc(doc(sarah, 'users/owner1/profiles/self/visits/v2'), visit));
  await assertFails(deleteDoc(doc(sarah, 'users/owner1/profiles/self/visits/v1')));

  // Nobody grants themselves access.
  const grant = { email: 'x@example.com', permissions: { checklist: true, alerts: true, appointments: true } };
  await assertFails(setDoc(doc(stranger, 'users/owner1/profiles/self/members/x1'), grant));
  await assertFails(setDoc(doc(robert, 'users/owner1/profiles/self/members/robert1'), grant));
  await assertFails(setDoc(doc(owner, 'users/owner1/profiles/self/members/robert1'), grant));
  await assertFails(setDoc(doc(robert, 'users/robert1/sharedProfiles/owner1_x'), { ownerUid: 'owner1' }));
  await assertFails(getDoc(doc(stranger, 'users/owner1/profiles/self/shareChecklist/amox')));

  // Members read their own membership and shared index.
  await assertSucceeds(getDoc(doc(robert, 'users/owner1/profiles/self/members/robert1')));
  await assertFails(getDoc(doc(robert, 'users/owner1/profiles/self/members/sarah1')));
  await assertSucceeds(getDocs(collection(robert, 'users/robert1/sharedProfiles')));
  await assertFails(getDocs(collection(sarah, 'users/robert1/sharedProfiles')));

  // Invitations: the sender reads them; no client writes at all.
  await assertSucceeds(getDoc(doc(owner, 'invitations/i1')));
  await assertFails(getDoc(doc(robert, 'invitations/i1')));
  await assertFails(setDoc(doc(owner, 'invitations/i2'), { ownerUid: 'owner1' }));
  await assertFails(setDoc(doc(owner, 'invitations/i1'), { ownerUid: 'owner1', status: 'accepted' }));
});

test('share copies: none while unshared, built when a caregiver joins', async () => {
  const { syncCopy, backfill } = require('../src/share');
  const { checklistCopy, logCopy } = require('../src/invites');
  const base = 'users/sh1/profiles/self';
  await db.recursiveDelete(db.doc('users/sh1'));
  await db.doc(base).set({ type: 'self', fullName: 'Sam' });
  const med = { name: 'Lisinopril', dosage: '10mg', notes: 'private', status: 'active' };
  await db.doc(`${base}/medicines/m1`).set(med);
  await syncCopy(db, { uid: 'sh1', pid: 'self', target: 'shareChecklist/m1', after: med, copy: checklistCopy });
  assert.equal((await db.doc(`${base}/shareChecklist/m1`).get()).exists, false);

  await db.doc(`${base}/doseLogs/m1_2026-10-24_480`).set({ medicineId: 'm1', day: '2026-10-24', minutes: 480, status: 'taken' });
  await db.doc(`${base}/doseLogs/m1_2026-10-24_1200`).set({ medicineId: 'm1', day: '2026-10-24', minutes: 1200, status: 'cleared' });
  await db.doc(`${base}/members/c1`).set({ permissions: { checklist: true } });
  await backfill(db, 'sh1', 'self');
  const copy = (await db.doc(`${base}/shareChecklist/m1`).get()).data();
  assert.equal(copy.name, 'Lisinopril');
  assert.equal(copy.dosage, undefined);
  assert.equal((await db.doc(`${base}/shareLogs/m1_2026-10-24_480`).get()).exists, true);
  assert.equal((await db.doc(`${base}/shareLogs/m1_2026-10-24_1200`).get()).exists, false);

  // Shared now: later writes are copied; removals always drop the copy.
  await syncCopy(db, { uid: 'sh1', pid: 'self', target: 'shareChecklist/m1', after: { ...med, name: 'Lisinopril XR' }, copy: checklistCopy });
  assert.equal((await db.doc(`${base}/shareChecklist/m1`).get()).get('name'), 'Lisinopril XR');
  await syncCopy(db, { uid: 'sh1', pid: 'self', target: 'shareLogs/m1_2026-10-24_480', after: null, copy: logCopy });
  assert.equal((await db.doc(`${base}/shareLogs/m1_2026-10-24_480`).get()).exists, false);
  await db.recursiveDelete(db.doc('users/sh1'));
});
