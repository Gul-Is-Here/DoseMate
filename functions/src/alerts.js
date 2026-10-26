'use strict';

/**
 * Account-owner alerts sent through FCM: "dose not logged yet", low
 * supply, and the silent "dose logged" message that clears an alert on
 * the owner's other devices. Caretakers get nothing here (not in this
 * version).
 */

const MISSED_AFTER_MIN = 30; // Alert once a dose is this late...
const MISSED_UNTIL_MIN = 90; // ...if the check runs before this.
const USER_CONCURRENCY = 10; // Accounts checked at once.

// FCM errors meaning the token will never work again.
const DEAD_TOKEN = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
  'messaging/invalid-argument',
]);

/** Alert tag for one dose: also the id the devices clear it by. */
const doseTag = (pid, logId) => `dose:${pid}:${logId}`;

// Server alerts' Android channel and bundled sound (the app's
// NotificationService.serverChannel; res/raw and the iOS bundle). Local
// alarms use their own channel and the alarm sound.
const CHANNEL = 'server_alerts';
const SOUND_ANDROID = 'notificationsound';
const SOUND_IOS = 'notificationsound.aiff';

/** Local day key and minutes after midnight of [date] in [timeZone]. */
function localParts(date, timeZone) {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat('en-CA', {
      timeZone, year: 'numeric', month: '2-digit', day: '2-digit',
      hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
    }).formatToParts(date).map((p) => [p.type, p.value]),
  );
  return {
    day: `${parts.year}-${parts.month}-${parts.day}`,
    minutes: Number(parts.hour) * 60 + Number(parts.minute),
  };
}

function isZone(tz) {
  try {
    new Intl.DateTimeFormat('en', { timeZone: tz });
    return true;
  } catch {
    return false;
  }
}

/** ISO weekday (1 = Monday) of a yyyy-MM-dd key. */
const weekday = (day) => ((new Date(`${day}T12:00:00Z`).getUTCDay() + 6) % 7) + 1;

/**
 * Dose minutes [m] has on local [day], following the app's
 * Medicine.isScheduledOn: course dates, pauses, past schedules, weekdays.
 */
function doseMinutesOn(m, day) {
  if (m.status === 'draft') return [];
  if (!m.startDay || !m.endDay || day < m.startDay || day > m.endDay) return [];
  const pauses = Array.isArray(m.pauses) ? m.pauses : [];
  if (pauses.some((p) => p && p.from <= day && (!p.until || day < p.until))) {
    return [];
  }
  if (m.status !== 'active') return [];
  const past = (Array.isArray(m.pastSchedules) ? m.pastSchedules : [])
    .filter((v) => v && typeof v.until === 'string')
    .sort((a, b) => (a.until < b.until ? -1 : 1));
  const s = past.find((v) => day < v.until) ?? m;
  if (s.frequency === 'asNeeded') return [];
  if (s.frequency === 'specificDays' &&
      !(Array.isArray(s.days) && s.days.includes(weekday(day)))) return [];
  return (Array.isArray(s.doseMinutes) ? s.doseMinutes : [])
    .filter((x) => Number.isInteger(x) && x >= 0 && x < 1440);
}

/** Doses per day for the low supply threshold, as in the app. */
function lowSupplyThreshold(m) {
  const perDay = m.frequency === 'asNeeded'
    ? 0
    : (Array.isArray(m.doseMinutes) ? m.doseMinutes.length : 0);
  return perDay === 0 ? 4 : perDay * 2;
}

function clock(minutes) {
  const h = Math.floor(minutes / 60), mm = minutes % 60;
  const hour = h % 12 === 0 ? 12 : h % 12;
  return `${hour}:${String(mm).padStart(2, '0')} ${h < 12 ? 'AM' : 'PM'}`;
}

function createAlerts({ db, messaging, now = () => new Date() }) {
  const devices = (uid) => db.collection(`users/${uid}/devices`);

  /** Sends [message] to every device of [uid]; drops dead tokens. */
  async function sendToUser(uid, message) {
    const snap = await devices(uid).get();
    const tokens = snap.docs.map((d) => d.get('token')).filter((t) => typeof t === 'string');
    if (!tokens.length) return 0;
    const res = await messaging.sendEachForMulticast({ ...message, tokens });
    const dead = [];
    res.responses.forEach((r, i) => {
      if (!r.success && DEAD_TOKEN.has(r.error?.code)) dead.push(snap.docs[i].ref);
    });
    await Promise.all(dead.map((ref) => ref.delete()));
    return res.successCount;
  }

  const visible = ({ title, body, tag, data }) => ({
    notification: { title, body },
    data: { ...data, tag },
    android: {
      priority: 'high',
      notification: { tag, channelId: CHANNEL, sound: SOUND_ANDROID },
    },
    apns: {
      headers: { 'apns-collapse-id': tag.slice(0, 64) },
      payload: { aps: { sound: SOUND_IOS, 'thread-id': 'alerts' } },
    },
  });

  async function profileName(uid, pid) {
    const p = await db.doc(`users/${uid}/profiles/${pid}`).get();
    if (!p.exists) return null;
    return p.get('type') === 'self' ? null : (p.get('fullName') || null);
  }

  /** Silent message: the dose was logged, so devices clear its alert. */
  function doseLogged(uid, pid, logId) {
    return sendToUser(uid, {
      data: { type: 'dose-logged', tag: doseTag(pid, logId) },
      android: { priority: 'high' },
      apns: {
        headers: { 'apns-push-type': 'background', 'apns-priority': '5' },
        payload: { aps: { 'content-available': 1 } },
      },
    });
  }

  /** Sent once when a taken dose brings the supply down to the threshold. */
  async function lowSupply(uid, pid, med, before, after) {
    if (med.lowSupplyWarning !== true || med.status === 'archived' ||
        med.status === 'draft') return 0;
    const t = lowSupplyThreshold(med);
    if (!(before > t && after <= t)) return 0;
    const who = await profileName(uid, pid);
    return sendToUser(uid, visible({
      title: `Running low: ${med.name}`,
      body: `${after} ${after === 1 ? 'dose' : 'doses'} left${who ? ` for ${who}` : ''}. Time to refill.`,
      tag: `supply:${pid}:${med.id}`,
      data: { type: 'low-supply', profileId: pid, medicineId: med.id },
    }));
  }

  /**
   * Alerts each owner about doses still unlogged [MISSED_AFTER_MIN] after
   * their time, in the zone of their most recent device. Each dose is
   * alerted at most once (the doseAlerts record is created first).
   *
   * Users run [USER_CONCURRENCY] at a time; a profile's candidate logs and
   * snoozes are read in one batch, so cost follows due doses, not the
   * number of users times their whole history.
   */
  async function checkMissedDoses() {
    const at = now();
    const byUser = new Map();
    const devs = await db.collectionGroup('devices').select('timezone', 'updatedAt').get();
    for (const d of devs.docs) {
      const uid = d.ref.parent.parent.id;
      const tz = d.get('timezone');
      const seen = d.get('updatedAt')?.toMillis?.() ?? 0;
      const prev = byUser.get(uid);
      if (isZone(tz) && (!prev || seen > prev.seen)) byUser.set(uid, { tz, seen });
    }
    const users = [...byUser];
    let sent = 0;
    const worker = async () => {
      for (let next = users.shift(); next; next = users.shift()) {
        const [uid, { tz }] = next;
        try {
          const n = await checkUser(uid, tz, at);
          sent += n; // After the await: other users' counts aren't lost.
        } catch (e) {
          // One account's failure doesn't stop the others.
          console.error('Missed dose check failed', e.code ?? e.message);
        }
      }
    };
    await Promise.all(Array.from({ length: USER_CONCURRENCY }, worker));
    return sent;
  }

  async function checkUser(uid, tz, at) {
    // Doses due between UNTIL and AFTER minutes ago, today or yesterday.
    const windows = new Map();
    for (let back = MISSED_AFTER_MIN; back <= MISSED_UNTIL_MIN; back++) {
      const { day, minutes } = localParts(new Date(at - back * 60_000), tz);
      if (!windows.has(day)) windows.set(day, new Set());
      windows.get(day).add(minutes);
    }
    const profiles = await db.collection(`users/${uid}/profiles`).get();
    const counts = await Promise.all(profiles.docs.map(async (profile) => {
      const meds = await profile.ref.collection('medicines')
        .where('status', '==', 'active').get();
      const due = [];
      for (const doc of meds.docs) {
        const m = doc.data();
        for (const [day, mins] of windows) {
          for (const minutes of doseMinutesOn(m, day)) {
            if (mins.has(minutes)) due.push({ logId: `${doc.id}_${day}_${minutes}`, m, minutes });
          }
        }
      }
      if (!due.length) return 0;
      const refs = due.flatMap(({ logId }) => [
        profile.ref.collection('doseLogs').doc(logId),
        profile.ref.collection('doseSnoozes').doc(logId),
      ]);
      const snaps = await db.getAll(...refs);
      let n = 0;
      for (let i = 0; i < due.length; i++) {
        const { logId, m, minutes } = due[i];
        const log = snaps[2 * i], snooze = snaps[2 * i + 1];
        if (log.exists && log.get('status') !== 'cleared') continue;
        // Snoozed from its alarm: wait (a later run alerts if still
        // unlogged within the window).
        if (snooze.exists && snooze.get('until')?.toMillis?.() > at.getTime()) continue;
        try {
          await profile.ref.collection('doseAlerts').doc(logId)
            .create({ type: 'missed', sentAt: new Date() });
        } catch (e) {
          if (e.code === 6) continue; // Already alerted.
          throw e;
        }
        const who = profile.get('type') === 'self' ? null : profile.get('fullName');
        n += await sendToUser(uid, visible({
          title: `${who ? `${who} · ` : ''}${m.name}`,
          body: `Not logged yet: due at ${clock(minutes)}. Open DoseMate to mark it taken or skipped.`,
          tag: doseTag(profile.id, logId),
          data: { type: 'missed-dose', profileId: profile.id, logId },
        }));
      }
      return n;
    }));
    return counts.reduce((a, b) => a + b, 0);
  }

  return { sendToUser, doseLogged, lowSupply, checkMissedDoses };
}

module.exports = {
  createAlerts, doseMinutesOn, CHANNEL, SOUND_ANDROID, SOUND_IOS, lowSupplyThreshold, localParts, doseTag,
  MISSED_AFTER_MIN, MISSED_UNTIL_MIN,
};
