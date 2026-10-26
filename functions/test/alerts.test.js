'use strict';

// Runs against the Firestore emulator: `npm test` in functions/.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const {
  initializeTestEnvironment, assertFails, assertSucceeds,
} = require('@firebase/rules-unit-testing');
const { doc, setDoc, deleteDoc, serverTimestamp, Timestamp } = require('firebase/firestore');

const { createAlerts, doseMinutesOn, localParts } = require('../src/alerts');

const PROJECT = 'demo-dosemate';
if (!getApps().length) initializeApp({ projectId: PROJECT });
const db = getFirestore();

/** Records messages; tokens starting "dead" fail as unregistered. */
function fakeMessaging() {
  const sent = [];
  return {
    sent,
    async sendEachForMulticast(m) {
      sent.push(m);
      const responses = m.tokens.map((t) => t.startsWith('dead')
        ? { success: false, error: { code: 'messaging/registration-token-not-registered' } }
        : { success: true });
      return { responses, successCount: responses.filter((r) => r.success).length };
    },
  };
}

const med = (over = {}) => ({
  name: 'Lisinopril', dosage: '10mg', frequency: 'onceDaily', doseMinutes: [480],
  days: [], startDay: '2026-10-01', endDay: '2026-12-31', quantity: 10,
  lowSupplyWarning: true, status: 'active', ...over,
});

async function seed() {
  await db.recursiveDelete(db.doc('users/u1'));
  await db.doc('users/u1/profiles/self').set({ type: 'self', fullName: 'Eleanor' });
  await db.doc('users/u1/profiles/p1').set({ type: 'parent', fullName: 'Ruth Vance' });
  await db.doc('users/u1/devices/tokA').set({
    token: 'tokA', platform: 'android', timezone: 'Asia/Karachi', updatedAt: new Date(),
  });
  await db.doc('users/u1/devices/dead1').set({
    token: 'dead1', platform: 'ios', timezone: 'Asia/Karachi', updatedAt: new Date(0),
  });
}

test('alerts: schedule rules match the app', () => {
  assert.deepEqual(doseMinutesOn(med(), '2026-10-24'), [480]);
  assert.deepEqual(doseMinutesOn(med({ status: 'paused' }), '2026-10-24'), []);
  assert.deepEqual(doseMinutesOn(med({ pauses: [{ from: '2026-10-20', until: '2026-10-25' }] }), '2026-10-24'), []);
  assert.deepEqual(doseMinutesOn(med({ pastSchedules: [{ until: '2026-10-25', frequency: 'onceDaily', doseMinutes: [600], days: [] }] }), '2026-10-24'), [600]);
  // 24 Oct 2026 is a Saturday (6).
  assert.deepEqual(doseMinutesOn(med({ frequency: 'specificDays', days: [1, 3] }), '2026-10-24'), []);
  assert.deepEqual(doseMinutesOn(med({ frequency: 'specificDays', days: [6] }), '2026-10-24'), [480]);
  assert.deepEqual(doseMinutesOn(med({ frequency: 'asNeeded' }), '2026-10-24'), []);
  assert.deepEqual(localParts(new Date('2026-10-24T03:40:00Z'), 'Asia/Karachi'), { day: '2026-10-24', minutes: 520 });
});

test('alerts: a late unlogged dose is alerted once, to live tokens only', async () => {
  await seed();
  await db.doc('users/u1/profiles/p1/medicines/m1').set(med());
  await db.doc('users/u1/profiles/self/medicines/m2').set(med({ name: 'Vitamin D', doseMinutes: [490] }));
  // Vitamin D was logged: no alert.
  await db.doc('users/u1/profiles/self/doseLogs/m2_2026-10-24_490').set({ status: 'taken', rev: 1 });
  const messaging = fakeMessaging();
  // 8:40 in Karachi: the 8:00 dose is 40 minutes late.
  const alerts = createAlerts({ db, messaging, now: () => new Date('2026-10-24T03:40:00Z') });
  assert.equal(await alerts.checkMissedDoses(), 1);
  assert.equal(messaging.sent.length, 1);
  const m = messaging.sent[0];
  assert.equal(m.notification.title, 'Ruth Vance · Lisinopril');
  assert.match(m.notification.body, /due at 8:00 AM/);
  assert.equal(m.android.notification.tag, 'dose:p1:m1_2026-10-24_480');
  // The server alert sound and channel, not the local alarm's.
  assert.equal(m.android.notification.channelId, 'server_alerts');
  assert.equal(m.android.notification.sound, 'notificationsound');
  assert.equal(m.apns.payload.aps.sound, 'notificationsound.aiff');
  assert.deepEqual(m.tokens.sort(), ['dead1', 'tokA']);
  // The dead token is removed.
  assert.equal((await db.doc('users/u1/devices/dead1').get()).exists, false);
  // The next runs (15 and 30 minutes later) don't repeat it.
  for (const t of ['2026-10-24T03:55:00Z', '2026-10-24T04:10:00Z']) {
    const again = createAlerts({ db, messaging, now: () => new Date(t) });
    assert.equal(await again.checkMissedDoses(), 0);
  }
  assert.equal(messaging.sent.length, 1);
});

test('alerts: too early, too late, or undone', async () => {
  await seed();
  await db.doc('users/u1/profiles/self/medicines/m1').set(med());
  const messaging = fakeMessaging();
  const at = (iso) => createAlerts({ db, messaging, now: () => new Date(iso) }).checkMissedDoses();
  assert.equal(await at('2026-10-24T03:20:00Z'), 0); // 20 min late
  assert.equal(await at('2026-10-24T05:00:00Z'), 0); // 2 hours late: window passed
  // Undone dose counts as unlogged.
  await db.doc('users/u1/profiles/self/doseLogs/m1_2026-10-24_480').set({ status: 'cleared', rev: 2 });
  assert.equal(await at('2026-10-24T03:45:00Z'), 1);
  assert.equal(messaging.sent[0].notification.title, 'Lisinopril');
});

test('alerts: a dose just before midnight is checked after midnight', async () => {
  await seed();
  await db.doc('users/u1/profiles/self/medicines/m1').set(med({ doseMinutes: [23 * 60 + 45] }));
  const messaging = fakeMessaging();
  // 00:20 on 25 Oct in Karachi = 19:20Z on 24 Oct.
  const alerts = createAlerts({ db, messaging, now: () => new Date('2026-10-24T19:20:00Z') });
  assert.equal(await alerts.checkMissedDoses(), 1);
  assert.equal(messaging.sent[0].data.logId, 'm1_2026-10-24_1425');
});

test('alerts: low supply only when crossing the threshold', async () => {
  await seed();
  const messaging = fakeMessaging();
  const alerts = createAlerts({ db, messaging });
  const m = { id: 'm1', ...med() }; // threshold 2 (1 dose a day)
  assert.equal(await alerts.lowSupply('u1', 'p1', m, 4, 3), 0);
  assert.equal(await alerts.lowSupply('u1', 'p1', m, 3, 2), 1);
  assert.equal(await alerts.lowSupply('u1', 'p1', m, 2, 1), 0);
  assert.equal(await alerts.lowSupply('u1', 'p1', { ...m, lowSupplyWarning: false }, 3, 2), 0);
  assert.equal(messaging.sent[0].notification.title, 'Running low: Lisinopril');
  assert.equal(messaging.sent[0].notification.body, '2 doses left for Ruth Vance. Time to refill.');
});

test('alerts: dose logged is a silent message with the alert tag', async () => {
  await seed();
  const messaging = fakeMessaging();
  await createAlerts({ db, messaging }).doseLogged('u1', 'self', 'm1_2026-10-24_480');
  const m = messaging.sent[0];
  assert.equal(m.notification, undefined);
  assert.deepEqual(m.data, { type: 'dose-logged', tag: 'dose:self:m1_2026-10-24_480' });
  assert.equal(m.apns.payload.aps['content-available'], 1);
});

test('rules: only the owner registers their devices', async (t) => {
  const env = await initializeTestEnvironment({
    projectId: PROJECT,
    firestore: { rules: fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8') },
  });
  t.after(() => env.cleanup());
  await env.clearFirestore();
  const as = (uid) => env.authenticatedContext(uid, { email: `${uid}@x.com`, email_verified: true }).firestore();
  const reg = (d, uid, token, extra = {}) => setDoc(doc(d, `users/${uid}/devices/${token}`), {
    token, platform: 'android', timezone: 'Asia/Karachi', updatedAt: serverTimestamp(), ...extra,
  });
  await assertSucceeds(reg(as('u1'), 'u1', 'tok1'));
  await assertFails(reg(as('u2'), 'u1', 'tok2'));
  await assertFails(reg(as('u1'), 'u1', 'tok3', { token: 'other' }));
  await assertFails(reg(as('u1'), 'u1', 'tok4', { extra: true }));
  await assertSucceeds(deleteDoc(doc(as('u1'), 'users/u1/devices/tok1')));
  // Alert records are server-only.
  await assertFails(setDoc(doc(as('u1'), 'users/u1/profiles/self/doseAlerts/x'), { a: 1 }));
});

test('alerts: a dose snoozed from its alarm waits for the snooze', async () => {
  await seed();
  await db.doc('users/u1/profiles/p1/medicines/m1').set(med());
  // Snoozed until 8:45 in Karachi.
  await db.doc('users/u1/profiles/p1/doseSnoozes/m1_2026-10-24_480')
    .set({ until: new Date('2026-10-24T03:45:00Z') });
  const messaging = fakeMessaging();
  const at = (iso) => createAlerts({ db, messaging, now: () => new Date(iso) }).checkMissedDoses();
  assert.equal(await at('2026-10-24T03:40:00Z'), 0);
  // Snooze over, still unlogged: alerted.
  assert.equal(await at('2026-10-24T03:50:00Z'), 1);
});

test('rules: only the owner snoozes, briefly', async (t) => {
  const env = await initializeTestEnvironment({
    projectId: PROJECT,
    firestore: { rules: fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8') },
  });
  t.after(() => env.cleanup());
  await env.clearFirestore();
  const as = (uid) => env.authenticatedContext(uid, { email: `${uid}@x.com`, email_verified: true }).firestore();
  const ref = (d) => doc(d, 'users/u1/profiles/self/doseSnoozes/m1_2026-10-24_480');
  const inMin = (m) => Timestamp.fromMillis(Date.now() + m * 60_000);
  await assertSucceeds(setDoc(ref(as('u1')), { until: inMin(10) }));
  await assertFails(setDoc(ref(as('u2')), { until: inMin(10) }));
  await assertFails(setDoc(ref(as('u1')), { until: inMin(600) }));
  await assertFails(setDoc(ref(as('u1')), { until: inMin(10), extra: 1 }));
});

test('alerts: many accounts are checked together and every alert counts', async () => {
  const uids = ['u1', 'u2', 'u3', 'u4', 'u5', 'u6', 'u7', 'u8', 'u9', 'u10', 'u11', 'u12'];
  for (const uid of uids) {
    await db.recursiveDelete(db.doc(`users/${uid}`));
    await db.doc(`users/${uid}/profiles/self`).set({ type: 'self', fullName: uid });
    await db.doc(`users/${uid}/profiles/self/medicines/m1`).set(med());
    await db.doc(`users/${uid}/devices/tok-${uid}`).set({
      token: `tok-${uid}`, platform: 'android', timezone: 'Asia/Karachi', updatedAt: new Date(),
    });
  }
  const messaging = fakeMessaging();
  const alerts = createAlerts({ db, messaging, now: () => new Date('2026-10-24T03:40:00Z') });
  assert.equal(await alerts.checkMissedDoses(), uids.length);
  assert.equal(messaging.sent.length, uids.length);
  for (const uid of uids) await db.recursiveDelete(db.doc(`users/${uid}`));
});
