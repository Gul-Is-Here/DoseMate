'use strict';

const { checklistCopy, logCopy } = require('./invites');

/**
 * Caregiver-safe copies (shareChecklist, shareLogs) exist only for
 * profiles shared with someone: the owner's writes aren't copied
 * otherwise, and a caregiver joining gets the profile's copies built then
 * ([backfill]).
 */

const profilePath = (uid, pid) => `users/${uid}/profiles/${pid}`;

async function hasMembers(db, uid, pid) {
  const m = await db.collection(`${profilePath(uid, pid)}/members`).limit(1).get();
  return !m.empty;
}

/** Keeps one copy in step with its source document. */
async function syncCopy(db, { uid, pid, source, target, after, copy }) {
  const ref = db.doc(`${profilePath(uid, pid)}/${target}`);
  // Removed (or an undone log): always drop the copy, even if unshared now.
  if (!after) return ref.delete();
  if (!(await hasMembers(db, uid, pid))) return null;
  return ref.set(copy(after));
}

/** All copies of a profile, built when a caregiver joins. Idempotent. */
async function backfill(db, uid, pid) {
  const base = db.doc(profilePath(uid, pid));
  const writer = db.bulkWriter();
  const meds = await base.collection('medicines').get();
  for (const d of meds.docs) {
    writer.set(base.collection('shareChecklist').doc(d.id), checklistCopy(d.data()));
  }
  // Logs in pages, so a long history isn't held in memory at once.
  let last = null;
  for (;;) {
    let q = base.collection('doseLogs').orderBy('__name__').limit(500);
    if (last) q = q.startAfter(last);
    const page = await q.get();
    for (const d of page.docs) {
      if (d.get('status') === 'cleared') continue;
      writer.set(base.collection('shareLogs').doc(d.id), logCopy(d.data()));
    }
    if (page.size < 500) break;
    last = page.docs[page.size - 1];
  }
  await writer.close();
}

module.exports = { hasMembers, syncCopy, backfill };
