# LBL Trainer Application Confirmation

Google Apps Script that automatically sends the Stage 1 confirmation email to any candidate who submits the LBL trainer application Google Form.

## What it does

- Trigger: `onFormSubmit` on the Trainer Candidate Tracker Google Sheet
- Pulls Full Name + Email from the submitted row
- Sends personalized HTML email with LBL signature
- Instant delivery (fires within seconds of form submit)

## Linked sheet

Trainer Candidate Tracker: `1kWHDT7aMOdkqb3adXWeU6PRYNCx4iEvyoyYDUM0r4CU`

## Install (5 minutes, one-time)

1. Open the sheet: https://docs.google.com/spreadsheets/d/1kWHDT7aMOdkqb3adXWeU6PRYNCx4iEvyoyYDUM0r4CU/edit
2. Extensions → Apps Script (opens in new tab)
3. Paste contents of `Code.gs` into the script editor
4. Save (`Cmd+S`). Name the project "LBL Trainer Application Confirmation"
5. Click the function dropdown → select `testEmail` → click Run
   - First run prompts you to authorize Gmail access. Click through the consent screen (yours, ignore the "unverified app" warning since you're the owner).
   - Check ariel.l.galipeau@gmail.com — you should see a test email from ariel@launchbylunch.co
6. Function dropdown → select `installTrigger` → click Run
   - This attaches the `onFormSubmit` trigger to the sheet's linked form
7. Done. Submit a test form entry to verify end-to-end.

## Maintenance

- **Edit the email template:** update `Code.gs` locally, then copy-paste back into Apps Script and Save
- **Change sender name or reply-to:** update the `GmailApp.sendEmail` options in `onFormSubmit`
- **Remove the trigger:** in Apps Script, click the clock icon (Triggers) in the left sidebar, delete the entry

## Who owns what

- **Script owner:** Ariel (the email comes from whoever owns the Apps Script project = whoever ran `testEmail` and authorized Gmail)
- **Sends as:** ariel@launchbylunch.co
- **Reply-to:** ariel@launchbylunch.co

## Known limitations

- Only fires for **Google Form submissions**. Manual row additions to the sheet won't trigger it. If you need manual-add to also trigger, switch to an installable `onEdit` trigger with row-change detection.
- Gmail daily send limit for free Google accounts = 100/day; for Workspace = 1,500/day. Not a concern at current application volume.
- If the form's column headers ever change (rename "Full Name" or "Email"), update `onFormSubmit` accordingly.

## History

- **April 24, 2026:** Created. Template is Stage 1 from `lbl/lbl-trainer-email-templates.md`.
