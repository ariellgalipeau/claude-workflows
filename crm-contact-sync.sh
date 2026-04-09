#!/bin/bash
# ─────────────────────────────────────────────────────────────
# Weekly CRM Contact Sync + Dossier Refresh
# Runs every Sunday at 10am via launchd
#
# PURPOSE:
# 1. Scan the past 7 days of email, find new contacts and add them.
# 2. Pull new Luma event registrants and add them with dossiers.
# 3. Refresh dossiers for existing contacts with new email/meeting context.
# 4. Update relationship stages and last contact dates.
# Sends Ariel a short summary of what was added and what was refreshed.
# ─────────────────────────────────────────────────────────────

CLAUDE="/Users/arielgalipeau/.local/bin/claude"
LOG_DIR="/Users/arielgalipeau/.claude/projects/-Users-arielgalipeau/logs"
MEMORY_DIR="/Users/arielgalipeau/.claude/projects/-Users-arielgalipeau/memory"
CRM_SHEET_ID="1REI5cu0oxB4-qFnz0l7bbmGQyKDe5Zg0ZIrF8gQeaI0"
LUMA_API_KEY="secret-eaaTCCLtJQV1f2nLsqqZaBx4H"
LUMA_CALENDAR_ID="cal-O1hRL5ZGZcE1jcj"
mkdir -p "$LOG_DIR"

echo "──────────────────────────────────" >> "$LOG_DIR/crm-contact-sync.log"
echo "CRM contact sync started: $(date)" >> "$LOG_DIR/crm-contact-sync.log"

$CLAUDE -p "You are Ariel Galipeau's weekly CRM sync agent. Today is $(date '+%A, %B %d, %Y').

YOUR JOB: Three things — (1) find new contacts from the past 7 days of email and add them to the CRM, (2) pull new Luma event registrants and add them with dossiers, and (3) refresh dossiers for existing contacts who had activity this week.

## CRM Sheet
- Sheet ID: $CRM_SHEET_ID
- Sheet URL: https://docs.google.com/spreadsheets/d/$CRM_SHEET_ID/edit
- Column schema (A–N): Full Name | Company | Title / Role | Email | Phone | LinkedIn | Website | How We Met | Context | Tags | Relationship Stage | Last Contact Date | Dossier | In-Person Events

Dossier format (multi-line text in column M):
NEEDS: ...
PROBLEMS: ...
WHAT THEY CARE ABOUT: ...
RELATIONSHIP NOTES: ...

Relationship Stage values: New / Warm / Active / Client / Past Client

## STEP 1: Read the existing CRM

Use mcp__google-drive__getGoogleSheetContent to read the full CRM sheet (Sheet1!A:M).
For each existing contact, note their row number, email (col D), name (col A), current dossier (col M), relationship stage (col K), and last contact date (col L).

## STEP 2: Scan BOTH Gmail accounts for the past 7 days

You MUST scan BOTH inboxes. Ariel uses two email accounts:
- **Personal Gmail** (ariel.l.galipeau@gmail.com) — use mcp__gmail__search_emails / mcp__gmail__read_email
- **LBL Gmail** (ariel@launchbylunch.co) — use mcp__lbl-gmail__search_emails / mcp__lbl-gmail__read_email

For EACH account, search for:
a) -category:promotions -category:social -unsubscribe -in:spam -in:trash newer_than:7d
b) in:sent newer_than:7d

For each email, extract the From, To, CC, and Reply-To addresses.

IMPORTANT — Cast a wide net for real human contacts. Add anyone who is:
- Replying to Ariel's outbound emails (trainer candidates, partnership outreach, proposals, etc.)
- Emailing Ariel directly about business, events, partnerships, collaborations
- CC'd on threads with substantive involvement
- Responding to invitations, scheduling calls, or following up on meetings

SKIP these — they are NOT real contacts:
- ariel.l.galipeau@gmail.com, ariel@launchbylunch.co, agalipea@grad.bryant.edu (Ariel herself)
- karen@builtbykaren.com (Karen is already in CRM, skip for new contact detection but still refresh her dossier)
- Any noreply, no-reply, notify, support, info, automated, or mailer addresses
- Any @luma-mail.com, @mail.notion.so, @resend.dev, @accounts.google.com, @fathom.video addresses
- Automated tool/service marketing emails (SaaS product announcements, tool ads, cold sales pitches for software)
- Newsletters and bulk marketing

DO NOT skip:
- Replies to Ariel's outbound recruiting/hiring emails
- Partnership or sponsorship conversations
- People Ariel is actively emailing about events, workshops, or business
- Recruiters reaching out about real job opportunities
- Anyone Ariel initiated contact with (outbound threads where someone replied)

Sort contacts into two buckets:
a) NEW contacts (not in the CRM by email match) — read the thread to gather context
b) EXISTING contacts (email matches a CRM row) — read the thread to find new context for dossier refresh

## STEP 3: Pull Luma event registrants

Use Bash to call the Luma API to list events on the calendar:
curl -s 'https://api.lu.ma/public/v1/calendar/list-events?calendar_api_id=$LUMA_CALENDAR_ID' -H 'x-luma-api-key: $LUMA_API_KEY' -H 'accept: application/json'

Filter to events that are upcoming OR happened within the last 14 days.

For each qualifying event, pull the guest list:
curl -s 'https://api.lu.ma/public/v1/event/get-guests?event_api_id=EVENT_ID' -H 'x-luma-api-key: $LUMA_API_KEY' -H 'accept: application/json'

If there are more results (has_more=true), use pagination with cursor parameter: &pagination_cursor=CURSOR_VALUE

For each registrant NOT already in the CRM (by email match), add them to the new contacts list with:
- Name from guest.name
- Email from guest.email
- Company, Title, LinkedIn from registration_answers (questions about company/org, title, LinkedIn profile)
- How We Met: 'Event'
- Context: Event name + date (e.g., 'LBL Chief of Staff Workshop, March 11 2026')
- Tags: 'AI, LBL' + inferred from answers (Founder if title contains founder, etc.)
- Dossier built from registration answers:
  - NEEDS: from 'why does this interest you' answer
  - PROBLEMS: inferred from their interest/context answers
  - WHAT THEY CARE ABOUT: inferred from answers
  - RELATIONSHIP NOTES: event name, how they found the event, AI-friendliness rating, AI tools they use, any additional notes
- If LinkedIn answer is just '/in/handle', prepend https://linkedin.com

For registrants who ARE already in the CRM but have blank fields (company, title, LinkedIn, dossier), fill in the gaps from registration data. Append new event to their Context field (column I).

## STEP 4: Add new contacts to the CRM (from email + Luma)

Combine new contacts from both email scanning (Step 2) and Luma (Step 3). Deduplicate by email.

For each new contact, add a row with:
- A: Full Name (first + last if available from signature or email)
- B: Company (from email domain, signature, or context)
- C: Title / Role (from signature if available)
- D: Email address
- E: Phone (from signature if available)
- F: LinkedIn (from signature if available)
- G: Website (from signature if available)
- H: How We Met — infer from context: Event, Email, Referral, LinkedIn, In-Person, Work, etc.
- I: Context — brief description: what the email was about, when, any relevant detail
- J: Tags — 2-4 relevant tags from: Investor, Founder, Client, AI, HR, LBL, VC, Women, Networking, Coach, Tech, Finance, Nonprofit, etc.
- K: Relationship Stage — New (if just introduced), Warm (if back-and-forth), Active (if working together)
- L: Last Contact Date — date of the most recent email (YYYY-MM-DD)
- M: Dossier — use the structured format. Fill in what you can infer from the email. Leave TBD for anything unknown.
- N: In-Person Events — if the contact was met at a physical event, enter 'Event Name, YYYY-MM-DD'. Leave blank if met virtually or online. For Luma registrants, populate only if the event has a physical venue.

After adding rows, apply wrap + top-alignment formatting to the new rows using mcp__google-drive__formatGoogleSheetCells.

## STEP 5: Refresh dossiers for existing contacts

This is the key step. For each existing CRM contact who appeared in this week's email:

**4a. Read their email threads from this week.**
Look for new information:
- New role, title, or company (did they change jobs, launch something, get promoted?)
- New projects or initiatives they mentioned
- Evolving needs or problems
- New context about what they care about
- Relationship milestones (first real conversation, started collaborating, became a client)

**4b. Check Fathom meeting recaps.**
Search BOTH Gmail accounts for: from:no-reply@fathom.video newer_than:7d (use mcp__gmail__search_emails AND mcp__lbl-gmail__search_emails).
If any Fathom recaps mention an existing CRM contact by name, extract relevant context about that person (what was discussed, decisions made, action items involving them).

**4c. Update the dossier.**
Read the contact's current dossier (column M). APPEND new information, do not rewrite or remove existing content. Follow these rules:
- Add new context under the appropriate section (NEEDS, PROBLEMS, WHAT THEY CARE ABOUT, RELATIONSHIP NOTES)
- Prefix new additions with the date in parentheses, e.g., '(Mar 2026) Started exploring AI workshops for her team'
- If existing info is clearly outdated and contradicted by new info, update it but keep a record, e.g., 'Title: VP Marketing (prev: Director)'
- Keep the dossier concise. If a section is getting long, summarize older entries.

**4d. Update Last Contact Date (column L)** to the most recent email date this week.

**4e. Update Relationship Stage (column K)** if warranted:
- New → Warm: after a real back-and-forth exchange (not just one cold email)
- Warm → Active: when actively collaborating, scheduling calls, or working together
- Active → Client: when they start paying
- Any stage → Past Client: when engagement ends
Only upgrade stages. Never downgrade automatically (a quiet week doesn't mean the relationship cooled).

**4f. Fill in blanks.** If their row has empty fields (company, title, LinkedIn, phone) and the email signature or thread reveals that info, fill it in.

Use mcp__google-drive__updateGoogleSheet to update the specific cells for each refreshed contact. Only update cells that actually changed.

## STEP 6: Email Ariel

Send ONE email to ariel.l.galipeau@gmail.com with subject: CRM Sync — $(date '+%B %d, %Y')

The email should have ONLY these sections:

**New Contacts Added (X)**
For each new contact: Name — Company/context — source (Email or Luma event name) — why they're worth noting (one line each).
If none were added: 'No new contacts this week.'

**Dossiers Refreshed (X)**
For each contact whose dossier was updated: Name — what changed (one line each).
Example: 'Karen Kelly — updated partnership status, added April event planning context'
Example: 'Rebecca Moore — filled in company (InANutshell Consulting) from email signature'
If none were refreshed: 'No dossier updates this week.'

**Stage Changes (X)**
For each contact whose relationship stage changed: Name — Old Stage → New Stage — why.
If none changed: omit this section entirely.

**Needs Your Input**
Contacts where you couldn't determine key info or where the dossier update needs Ariel's judgment:
- Name — what's unclear and why it matters
Keep this list short. Only flag if the gap is significant.

That's it. Short, scannable, actionable." \
  --dangerously-skip-permissions \
  --allowedTools "Bash,mcp__gmail__search_emails,mcp__gmail__read_email,mcp__gmail__send_email,mcp__lbl-gmail__search_emails,mcp__lbl-gmail__read_email,mcp__google-drive__getGoogleSheetContent,mcp__google-drive__updateGoogleSheet,mcp__google-drive__appendSpreadsheetRows,mcp__google-drive__formatGoogleSheetCells,Read" \
  >> "$LOG_DIR/crm-contact-sync.log" 2>&1

if [ $? -eq 0 ]; then
  echo "CRM contact sync completed successfully: $(date)" >> "$LOG_DIR/crm-contact-sync.log"
else
  echo "CRM contact sync FAILED: $(date)" >> "$LOG_DIR/crm-contact-sync.log"
fi
