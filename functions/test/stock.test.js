'use strict';

// Runs against the Firestore emulator: `npm test` in functions/.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const {
  doc, setDoc, serverTimestamp, Timestamp: ClientTimestamp,
} = require('firebase/firestore');

const { applyDoseStock } = require('../src/stock');

const PROJECT = 'demo-dosemate';
if (!getApps().length) initializeApp({ projectId: PROJECT });
const db = getFirestore();

const P = 'users/u1/profiles/self';
const LOG = 'm1_2026-10-24_480';

const medicine = (quantity) => ({
  name: 'Lisinopril', frequency: 'onceDaily', doseMinutes: [480],
  startDay: '2026-10-01', endDay: '2026-12-31', quantity, status: 'active',
});

async function reset(quantity = 5) {
  await db.recursiveDelete(db.doc(P));
  await db.doc(P).set({ type: 'self', fullName: 'Eleanor' });
  await db.doc(`${P}/medicines/m1`).set(medicine(quantity));
}

const qty = async () => (await db.doc(`${P}/medicines/m1`).get()).get('quantity');
const write = (fields) => db.doc(`${P}/doseLogs/${LOG}`).set(
  { medicineId: 'm1', day: '2026-10-24', minutes: 480, ...fields },
  { merge: true },
);
const run = async (before = null) =>
  (await applyDoseStock(db, { uid: 'u1', pid: 'self', id: LOG, before })).result;

test('stock: a dose counts once however often the trigger runs', async () => {
  await reset(5);
  await write({ status: 'taken', rev: 1 });
  assert.equal(await run(), 'applied');
  assert.equal(await run(), 'unchanged');
  await Promise.all([run(), run(), run()]);
  assert.equal(await qty(), 4);

  await write({ status: 'skipped', rev: 2 });
  await Promise.all([run(), run()]);
  assert.equal(await qty(), 5);

  await write({ status: 'cleared', rev: 3 });
  await run();
  await write({ status: 'taken', rev: 4 });
  await Promise.all([run(), run()]);
  assert.equal(await qty(), 4);
});

test('stock: never below zero, and undo returns only what was taken', async () => {
  await reset(0);
  await write({ status: 'taken', rev: 1 });
  await run();
  assert.equal(await qty(), 0);
  await write({ status: 'cleared', rev: 2 });
  await run();
  assert.equal(await qty(), 0);
});

test('stock: logs from older apps are left alone, then migrated once', async () => {
  // An older app wrote this log and took the dose from the supply itself.
  await reset(4);
  await write({ status: 'taken' });
  assert.equal(await run(), 'legacy');
  assert.equal(await qty(), 4);
  // A new app undoes it: the dose goes back exactly once.
  const before = (await db.doc(`${P}/doseLogs/${LOG}`).get()).data();
  await write({ status: 'cleared', rev: 10 });
  await run(before);
  await run(before);
  assert.equal(await qty(), 5);
});

test('stock: a legacy Taken is migrated once, whatever order events run in', async () => {
  // Older app: taken, supply already 5 -> 4.
  await reset(4);
  await write({ status: 'taken' });
  // New app: Taken (rev 1, marked as replacing the legacy log), then
  // quickly Skipped (rev 2). The rev 2 event runs first, with a
  // versioned [before].
  await write({ status: 'taken', rev: 1, legacyBase: 'taken' });
  await write({ status: 'skipped', rev: 2 });
  const rev1 = { status: 'taken', rev: 1, legacyBase: 'taken' };
  await run(rev1);
  await run(null); // the rev 1 event, late
  // Skipped: the legacy dose is given back.
  assert.equal(await qty(), 5);
});

test('stock: a log of a deleted medicine is recorded, nothing else', async () => {
  await reset(5);
  await db.doc(`${P}/medicines/m1`).delete();
  await write({ status: 'taken', rev: 1 });
  assert.equal(await run(), 'unchanged');
});

test('rules: versioned dose writes', async (t) => {
  const env = await initializeTestEnvironment({
    projectId: PROJECT,
    firestore: {
      rules: fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8'),
    },
  });
  t.after(() => env.cleanup());
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), P), { type: 'self', fullName: 'Eleanor' });
  });
  const owner = env
    .authenticatedContext('u1', { email: 'e@example.com', email_verified: true })
    .firestore();
  const ref = doc(owner, `${P}/doseLogs/${LOG}`);
  const now = Date.now();
  const tap = (status, rev, actionId, extra = {}) => setDoc(ref, {
    medicineId: 'm1', day: '2026-10-24', minutes: 480, status,
    rev, actionId, actedAt: ClientTimestamp.fromMillis(rev),
    utcOffset: 300, loggedAt: serverTimestamp(), ...extra,
  }, { merge: true });

  // Revisions are required; an undone log can't be created.
  await assertFails(setDoc(ref, {
    medicineId: 'm1', day: '2026-10-24', minutes: 480, status: 'taken',
    loggedAt: serverTimestamp(),
  }));
  await assertFails(tap('cleared', now, 'a0'));
  // The device can't claim the supply was already adjusted.
  await assertFails(tap('taken', now, 'a0', { stockApplied: -1 }));
  await assertFails(tap('taken', now, 'a0', { legacyBase: 'taken' }));
  // Far-future revisions would lock other devices out.
  await assertFails(tap('taken', now + 3_600_000, 'a0'));

  await assertSucceeds(tap('taken', now, 'a1'));
  // Retry of the same tap: accepted.
  await assertSucceeds(tap('taken', now, 'a1'));
  // Same revision, different tap; or older: refused.
  await assertFails(tap('skipped', now, 'a2'));
  await assertFails(tap('skipped', now - 60_000, 'a3'));
  // Newer: accepted, including undo.
  await assertSucceeds(tap('cleared', now + 1, 'a4'));
  // An older Taken arriving late can't bring it back.
  await assertFails(tap('taken', now, 'a1'));

  // Server-recorded stock can't be changed by the device.
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), `${P}/doseLogs/${LOG}`),
      { stockApplied: -1 }, { merge: true });
  });
  await assertFails(tap('taken', now + 2, 'a5', { stockApplied: 0 }));
  await assertSucceeds(tap('taken', now + 2, 'a5'));
});

test('rules: the legacy marker only over a legacy Taken, once', async (t) => {
  const env = await initializeTestEnvironment({
    projectId: PROJECT,
    firestore: {
      rules: fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8'),
    },
  });
  t.after(() => env.cleanup());
  await env.clearFirestore();
  const legacy = { medicineId: 'm1', day: '2026-10-24', minutes: 480, status: 'taken' };
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), P), { type: 'self', fullName: 'Eleanor' });
    await setDoc(doc(ctx.firestore(), `${P}/doseLogs/${LOG}`), legacy);
    await setDoc(doc(ctx.firestore(), `${P}/doseLogs/m1_2026-10-24_1200`),
      { ...legacy, minutes: 1200, status: 'skipped' });
  });
  const owner = env
    .authenticatedContext('u1', { email: 'e@example.com', email_verified: true })
    .firestore();
  const now = Date.now();
  const tap = (id, minutes, status, rev, extra = {}) => setDoc(doc(owner, `${P}/doseLogs/${id}`), {
    medicineId: 'm1', day: '2026-10-24', minutes, status,
    rev, actionId: `a${rev}`, actedAt: ClientTimestamp.fromMillis(now),
    utcOffset: 300, loggedAt: serverTimestamp(), ...extra,
  }, { merge: true });
  // Not over a legacy Skipped.
  await assertFails(tap('m1_2026-10-24_1200', 1200, 'cleared', now, { legacyBase: 'taken' }));
  // Over the legacy Taken: yes; later writes keep it and can't change it.
  await assertSucceeds(tap(LOG, 480, 'cleared', now, { legacyBase: 'taken' }));
  await assertSucceeds(tap(LOG, 480, 'taken', now + 1));
  await assertFails(tap(LOG, 480, 'skipped', now + 2, { legacyBase: 'other' }));
});
