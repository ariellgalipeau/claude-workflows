/**
 * LBL Trainer Application — Stage 1 Confirmation Email
 *
 * Automatically sends a confirmation email when a candidate submits
 * the LBL Trainer Application Google Form. Runs on form submit, so
 * candidates get their confirmation within seconds of applying.
 *
 * Sheet: Trainer candidate tracker
 *   https://docs.google.com/spreadsheets/d/1kWHDT7aMOdkqb3adXWeU6PRYNCx4iEvyoyYDUM0r4CU
 *
 * Install:
 *   1. In the sheet: Extensions → Apps Script
 *   2. Paste this file's contents
 *   3. Save (Cmd+S), name the project "LBL Trainer Application Confirmation"
 *   4. Run `testEmail` once to authorize Gmail access (prompt sends to Ariel)
 *   5. Run `installTrigger` once to attach the onFormSubmit trigger
 *   6. Done — every new form submission triggers a confirmation email
 *
 * Source of truth: ~/claude-workflows/google-apps-script/lbl-trainer-application-confirmation/
 */

const EMAIL_SUBJECT = "We Got Your Application!";

const SIGNATURE_HTML = `
<br><br>
<strong>Ariel Galipeau</strong><br>
<br>
Director of AI Programming · <a href="https://launchbylunch.co/">Launch by Lunch</a><br>
<em>Practical AI adoption for people-first teams.</em><br>
<br>
📅 <a href="https://calendly.com/d/cxt3-zb6-t3d/meet-the-lbl-team">Schedule a meeting with the LBL team</a><br>
<a href="https://linkedin.com/in/arielgalipeau">Connect on LinkedIn</a>
`;

const SIGNATURE_TEXT = `

Ariel Galipeau
Director of AI Programming · Launch by Lunch
https://launchbylunch.co/
Schedule: https://calendly.com/d/cxt3-zb6-t3d/meet-the-lbl-team
LinkedIn: https://linkedin.com/in/arielgalipeau`;

function onFormSubmit(e) {
  let fullName = '';
  let email = '';

  if (e.namedValues) {
    fullName = (e.namedValues['Full Name'] || [''])[0];
    email = (e.namedValues['Email'] || [''])[0];
  } else if (e.values) {
    fullName = e.values[1] || '';
    email = e.values[2] || '';
  }

  if (!email || !fullName) {
    Logger.log('Skipping: missing name or email. Name=' + fullName + ', Email=' + email);
    return;
  }

  const firstName = fullName.trim().split(/\s+/)[0];

  const htmlBody = `
<p>Hi ${firstName},</p>

<p>Thank you so much for applying to join the Launch by Lunch trainer team! We received your application and are genuinely excited to dig in.</p>

<p>We review every submission thoughtfully (the Looms are our favorite part), so please allow us a few business days to get back to you with next steps.</p>

<p>In the meantime, if you have any questions, don't hesitate to reach out.</p>

<p>We appreciate you and can't wait to learn more about what you bring to the table!</p>
${SIGNATURE_HTML}
`;

  const textBody = `Hi ${firstName},

Thank you so much for applying to join the Launch by Lunch trainer team! We received your application and are genuinely excited to dig in.

We review every submission thoughtfully (the Looms are our favorite part), so please allow us a few business days to get back to you with next steps.

In the meantime, if you have any questions, don't hesitate to reach out.

We appreciate you and can't wait to learn more about what you bring to the table!${SIGNATURE_TEXT}`;

  GmailApp.sendEmail(email, EMAIL_SUBJECT, textBody, {
    htmlBody: htmlBody,
    name: 'Ariel Galipeau',
    replyTo: 'ariel@launchbylunch.co'
  });

  Logger.log('Sent Stage 1 confirmation to ' + email + ' (' + firstName + ')');
}

/**
 * Install the onFormSubmit trigger. Run once after pasting the script.
 * Safe to run repeatedly — removes existing triggers of this name first.
 */
function installTrigger() {
  const existing = ScriptApp.getProjectTriggers();
  existing.forEach(t => {
    if (t.getHandlerFunction() === 'onFormSubmit') {
      ScriptApp.deleteTrigger(t);
    }
  });

  const ss = SpreadsheetApp.getActiveSpreadsheet();
  ScriptApp.newTrigger('onFormSubmit')
    .forSpreadsheet(ss)
    .onFormSubmit()
    .create();

  Logger.log('onFormSubmit trigger installed successfully.');
}

/**
 * Send a test email to verify setup. Run once, check your inbox.
 * Sends to ariel.l.galipeau@gmail.com so it doesn't touch a real candidate.
 */
function testEmail() {
  const mockEvent = {
    namedValues: {
      'Full Name': ['Test Candidate'],
      'Email': ['ariel.l.galipeau@gmail.com']
    }
  };
  onFormSubmit(mockEvent);
  Logger.log('Test email sent — check ariel.l.galipeau@gmail.com inbox.');
}
