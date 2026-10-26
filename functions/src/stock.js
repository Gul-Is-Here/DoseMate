'use strict';

const { FieldValue } = require('firebase-admin/firestore');

/**
 * Keeps a medicine's supply in step with one of its dose logs.
 *
 * The log records what it has taken from the supply (`stockApplied`: -1 or
 * 0), and each run moves the supply by the difference to what its current
 * status needs, in one transaction. A retried or duplicate event, or a run
 * for an older write, therefore changes nothing, and the order of writes
 * from different devices doesn't matter.
 *
 * Logs written by app versions without revisions adjusted the supply
 * themselves: the write replacing one carries `legacyBase: 'taken'`, so
 * its dose counts as already applied. [before] (the log before the
 * triggering write) is the fallback for apps that don't send it.
 */
async function applyDoseStock(db, { uid, pid, id, before }) {
  const profile = db.doc(`users/${uid}/profiles/${pid}`);
  const logRef = profile.collection('doseLogs').doc(id);
  let lastApplied = null;
  const result = await db.runTransaction(async (tx) => {
    lastApplied = null;
    const log = await tx.get(logRef);
    if (!log.exists) return 'gone';
    const d = log.data();
    // Written by an older app, which already adjusted the supply.
    if (typeof d.rev !== 'number') return 'legacy';
    let applied = d.stockApplied;
    if (applied !== -1 && applied !== 0) {
      // First run for this log. A Taken from before revisions was already
      // counted: the app marks the write that replaced it (legacyBase),
      // which holds whichever event runs first. [before] covers apps
      // without the marker, when events run in order.
      const legacy = d.legacyBase === 'taken' ||
        (before && typeof before.rev !== 'number' && before.status === 'taken');
      applied = legacy ? -1 : 0;
    }
    const medRef = profile.collection('medicines').doc(String(d.medicineId));
    const med = await tx.get(medRef);
    const quantity = med.exists ? Number(med.get('quantity') ?? 0) : 0;
    // A dose already counted stays counted; a new one never takes the
    // supply below zero.
    const want =
      d.status === 'taken' ? (applied === -1 || quantity > 0 ? -1 : 0) : 0;
    if (want === applied) {
      if (d.stockApplied !== applied) tx.update(logRef, { stockApplied: applied });
      return 'unchanged';
    }
    if (med.exists) {
      tx.update(medRef, {
        quantity: FieldValue.increment(want - applied),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    tx.update(logRef, { stockApplied: want });
    // Committed exactly once, so a low supply alert sent from this is too.
    lastApplied = med.exists
      ? { med: { id: med.id, ...med.data() }, before: quantity, after: quantity + want - applied }
      : null;
    return 'applied';
  });
  return result === 'applied' && lastApplied
    ? { result, ...lastApplied }
    : { result };
}

module.exports = { applyDoseStock };
