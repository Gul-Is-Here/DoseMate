'use strict';

const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getAuth } = require('firebase-admin/auth');
const { getStorage } = require('firebase-admin/storage');
const { onCall } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { getMessaging } = require('firebase-admin/messaging');
const {
  onDocumentWritten,
  onDocumentUpdated,
  onDocumentCreated,
} = require('firebase-functions/v2/firestore');
const { defineSecret, defineString } = require('firebase-functions/params');
const nodemailer = require('nodemailer');
const { createInviteService, checklistCopy, logCopy } = require('./src/invites');
const { syncCopy, backfill } = require('./src/share');
const { applyDoseStock } = require('./src/stock');
const { createAlerts } = require('./src/alerts');
const { createAccountDeletion } = require('./src/account');

initializeApp();
const db = getFirestore();

// Set with: firebase functions:secrets:set SMTP_USER / SMTP_PASS
const SMTP_USER = defineSecret('SMTP_USER');
const SMTP_PASS = defineSecret('SMTP_PASS');
const APP_URL = defineString('APP_URL', {
  default: 'https://dosemate-70150.web.app',
});

let transport;
const mailer = {
  async send({ to, subject, html, text, fromName = 'DoseMate' }) {
    transport ??= nodemailer.createTransport({
      service: 'gmail',
      auth: {
        user: SMTP_USER.value().trim(),
        pass: SMTP_PASS.value().replace(/\s+/g, ''),
      },
      // Fail fast so a stalled server is recorded (and retried) well
      // within the function timeout.
      connectionTimeout: 10_000,
      greetingTimeout: 10_000,
      socketTimeout: 20_000,
    });
    await transport.sendMail({
      from: { name: fromName, address: SMTP_USER.value().trim() },
      to,
      subject,
      text,
      html,
    });
  },
};

let alertService;
const alerts = () =>
  (alertService ??= createAlerts({ db, messaging: getMessaging() }));

let service;
const invites = () =>
  (service ??= createInviteService({
    db,
    auth: getAuth(),
    mailer,
    appUrl: APP_URL.value(),
  }));

const callable = (fn, { mail = false } = {}) =>
  onCall(
    {
      // Callables verify the Firebase ID token themselves; Cloud Run must let
      // the request through to reach that check.
      invoker: 'public',
      secrets: mail ? [SMTP_USER, SMTP_PASS] : [],
      maxInstances: 10,
    },
    (request) => fn(request),
  );

exports.sendInvitation = callable(
  (r) => invites().send(r.auth, r.data),
  { mail: true },
);
exports.resendInvitation = callable(
  (r) => invites().resend(r.auth, r.data),
  { mail: true },
);
exports.revokeInvitation = callable((r) => invites().revoke(r.auth, r.data));
exports.removeCareMember = callable((r) =>
  invites().removeMember(r.auth, r.data),
);
exports.updateCarePermissions = callable((r) =>
  invites().updatePermissions(r.auth, r.data),
);
exports.checkInvitation = callable((r) => invites().check(r.data, r.auth));
exports.acceptInvitation = callable((r) => invites().accept(r.auth, r.data));

// The caretaker's confirmation email, sent once acceptance has committed.
// Failures are retried by Eventarc; sendConfirmation makes each retry safe
// and stops after a few attempts.
exports.confirmAcceptedInvitation = onDocumentUpdated(
  {
    document: 'invitations/{id}',
    secrets: [SMTP_USER, SMTP_PASS],
    retry: true,
    maxInstances: 10,
  },
  async (event) => {
    const before = event.data?.before?.get('status');
    const after = event.data?.after?.get('status');
    if (before === 'accepted' || after !== 'accepted') return;
    const result = await invites().sendConfirmation(event.params.id);
    if (result === 'failed' || result === 'busy') {
      throw new Error('Confirmation email not sent yet');
    }
  },
);

// Caregiver-safe copies, kept in step with the owner's data, only for
// profiles shared with someone (see src/share.js).
exports.shareMedicine = onDocumentWritten(
  'users/{uid}/profiles/{pid}/medicines/{id}',
  async (event) => {
    const { uid, pid, id } = event.params;
    const after = event.data?.after;
    return syncCopy(db, {
      uid, pid,
      target: `shareChecklist/${id}`,
      after: after?.exists ? after.data() : null,
      copy: checklistCopy,
    });
  },
);

exports.shareDoseLog = onDocumentWritten(
  'users/{uid}/profiles/{pid}/doseLogs/{id}',
  async (event) => {
    const { uid, pid, id } = event.params;
    const after = event.data?.after;
    // Undone logs are kept for their revision but aren't shared.
    const live = after?.exists && after.get('status') !== 'cleared';
    return syncCopy(db, {
      uid, pid,
      target: `shareLogs/${id}`,
      after: live ? after.data() : null,
      copy: logCopy,
    });
  },
);

// A caregiver joined: build the profile's copies (none are kept while a
// profile isn't shared). Retried on failure; rebuilding is harmless.
exports.backfillShares = onDocumentCreated(
  { document: 'users/{uid}/profiles/{pid}/members/{memberUid}', retry: true },
  async (event) => backfill(db, event.params.uid, event.params.pid),
);

// The supply follows the dose logs. Retries are safe (see applyDoseStock),
// and its own write to the log runs this again as a no-op.
exports.applyDoseStock = onDocumentWritten(
  {
    document: 'users/{uid}/profiles/{pid}/doseLogs/{id}',
    retry: true,
    maxInstances: 10,
  },
  async (event) => {
    const after = event.data?.after;
    if (!after?.exists) return;
    const { uid, pid, id } = event.params;
    const before = event.data.before?.exists ? event.data.before.data() : null;
    const stock = await applyDoseStock(db, { uid, pid, id, before });
    // Only the run that moved the supply can send, so retries don't repeat it.
    if (stock.med) {
      await alerts()
        .lowSupply(uid, pid, stock.med, stock.before, stock.after)
        .catch((e) => console.error('Low supply alert not sent', e.code ?? e.message));
    }
    // A new tap (not this function's own stock write): clear the dose's
    // alert on the owner's other devices.
    if (after.get('rev') !== before?.rev && typeof after.get('rev') === 'number') {
      await alerts()
        .doseLogged(uid, pid, id)
        .catch((e) => console.error('Dose sync not sent', e.code ?? e.message));
    }
  },
);

// Owner alert for doses still unlogged 30 minutes after their time.
exports.checkMissedDoses = onSchedule(
  { schedule: 'every 15 minutes', timeoutSeconds: 300, maxInstances: 1 },
  async () => {
    const sent = await alerts().checkMissedDoses();
    console.log(`Missed dose alerts sent: ${sent}`);
  },
);

let deletion;
const accounts = () =>
  (deletion ??= createAccountDeletion({
    db,
    auth: getAuth(),
    bucket: getStorage().bucket(),
  }));

// Deletes the caller's account and everything it owns (see src/account.js).
// Needs a sign in from the last few minutes; safe to retry.
exports.deleteAccount = onCall(
  { invoker: 'public', timeoutSeconds: 300, memory: '512MiB', maxInstances: 10 },
  (request) => accounts().run(request.auth),
);

// Finishes deletions once their last ID tokens have expired.
exports.sweepAccountDeletions = onSchedule(
  { schedule: 'every 30 minutes', timeoutSeconds: 540, maxInstances: 1 },
  async () => {
    const closed = await accounts().sweep();
    console.log(`Account deletions closed: ${closed}`);
  },
);
