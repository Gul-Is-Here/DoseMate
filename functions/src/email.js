'use strict';

const escape = (s) =>
  String(s).replace(/[&<>"']/g, (c) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  })[c]);

/**
 * The invitation email. It names only the sender: no profile, medicine or
 * health details, since mail is often read on shared or lock screens.
 */
function inviteEmail({ inviterName, email, link }) {
  const name = escape(inviterName);
  const subject = `${inviterName} invited you to a DoseMate care circle`;
  const text = [
    `${inviterName} invited you to help with care reminders in DoseMate.`,
    '',
    `Accept the invitation: ${link}`,
    '',
    `The link works once and expires in 7 days. Sign in as ${email} to`,
    "accept. If you weren't expecting this, ignore this email.",
  ].join('\n');
  const html = `<!doctype html>
<html><body style="margin:0;background:#f9f9ff;font-family:'Plus Jakarta Sans',Arial,sans-serif;color:#0c1c32">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="padding:24px 12px">
<tr><td align="center">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:480px;background:#ffffff;border-radius:32px;padding:32px">
<tr><td>
<p style="margin:0 0 8px;font-size:12px;font-weight:700;letter-spacing:1px;color:#005c55;text-transform:uppercase">DoseMate · Privacy-first care circles</p>
<h1 style="margin:0 0 12px;font-size:24px;line-height:32px">You're invited to a care circle</h1>
<p style="margin:0 0 24px;font-size:16px;line-height:24px;color:#3e4947"><strong style="color:#0c1c32">${name}</strong> invited you to help with care reminders in DoseMate. You'll only see what they chose to share.</p>
<a href="${escape(link)}" style="display:inline-block;background:#005c55;color:#ffffff;text-decoration:none;font-weight:700;font-size:16px;padding:16px 28px;border-radius:999px">Accept Invitation</a>
<p style="margin:24px 0 0;font-size:13px;line-height:20px;color:#6e7977">The link works once and expires in 7 days. Sign in as <strong>${escape(email)}</strong> to accept. If you weren't expecting this, you can ignore this email.</p>
</td></tr></table>
</td></tr></table>
</body></html>`;
  return { subject, text, html };
}

const card = (body) => `<!doctype html>
<html><body style="margin:0;background:#f9f9ff;font-family:'Plus Jakarta Sans',Arial,sans-serif;color:#0c1c32">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="padding:24px 12px">
<tr><td align="center">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:480px;background:#ffffff;border-radius:32px;padding:32px">
<tr><td>
${body}
</td></tr></table>
</td></tr></table>
</body></html>`;

const button = (href, label) =>
  `<a href="${escape(href)}" style="display:inline-block;background:#005c55;color:#ffffff;text-decoration:none;font-weight:700;font-size:16px;padding:16px 28px;border-radius:999px">${escape(label)}</a>`;

const METHOD_LABELS = {
  password: 'your email address and password',
  'google.com': '"Continue with Google"',
  'apple.com': '"Sign in with Apple"',
};

/**
 * Sent to a caretaker after they accept. It explains how to sign in and
 * never carries a password: an account that has no sign-in method yet gets
 * a single-use, Firebase-generated [setupLink] instead.
 */
function acceptedEmail({
  inviterName, profileName, email, appUrl, methods = [], setupLink,
}) {
  const labels = methods.map((m) => METHOD_LABELS[m]).filter(Boolean);
  const how = setupLink
    ? 'First set a password with the secure link below (it expires soon and works once), then sign in with your email address and that password.'
    : labels.length
      ? `Sign in with ${labels.join(' or ')}, the same way you signed in to accept. You don't need a new account or password.`
      : "Sign in the same way you signed in to accept. You don't need a new account or password.";
  const subject = `You're in ${inviterName}'s DoseMate care circle`;
  const text = [
    `${inviterName} added you to their DoseMate care circle.`,
    '',
    `Shared profile: ${profileName}`,
    `Your DoseMate login: ${email}`,
    '',
    'How to sign in:',
    `1. Open the DoseMate app (${appUrl}).`,
    `2. ${how}`,
    `3. Tap the profile switcher and choose ${profileName}.`,
    ...(setupLink ? ['', `Set your password: ${setupLink}`] : []),
    '',
    `You'll only see what ${inviterName} chose to share. DoseMate will`,
    "never email you a password. If you didn't accept this invitation,",
    'you can ignore this email.',
  ].join('\n');
  const html = card(`<p style="margin:0 0 8px;font-size:12px;font-weight:700;letter-spacing:1px;color:#005c55;text-transform:uppercase">DoseMate · Privacy-first care circles</p>
<h1 style="margin:0 0 12px;font-size:24px;line-height:32px">You're in the care circle</h1>
<p style="margin:0 0 16px;font-size:16px;line-height:24px;color:#3e4947"><strong style="color:#0c1c32">${escape(inviterName)}</strong> added you to their DoseMate care circle.</p>
<table role="presentation" cellpadding="0" cellspacing="0" style="width:100%;background:#f0f3ff;border-radius:16px;margin:0 0 16px"><tr><td style="padding:12px 16px;font-size:14px;line-height:22px;color:#3e4947">
Shared profile: <strong style="color:#0c1c32">${escape(profileName)}</strong><br>
Your DoseMate login: <strong style="color:#0c1c32">${escape(email)}</strong>
</td></tr></table>
<p style="margin:0 0 8px;font-size:16px;font-weight:700">How to sign in</p>
<ol style="margin:0 0 24px;padding-left:20px;font-size:15px;line-height:24px;color:#3e4947">
<li>Open the DoseMate app.</li>
<li>${escape(how)}</li>
<li>Tap the profile switcher and choose <strong>${escape(profileName)}</strong>.</li>
</ol>
${setupLink ? button(setupLink, 'Set your password') : button(appUrl, 'Open DoseMate')}
<p style="margin:24px 0 0;font-size:13px;line-height:20px;color:#6e7977">You'll only see what ${escape(inviterName)} chose to share. DoseMate will never email you a password. If you didn't accept this invitation, you can ignore this email.</p>`);
  return { subject, text, html };
}

module.exports = { inviteEmail, acceptedEmail };
