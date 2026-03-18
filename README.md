# LBL Claude Code Workflows

Claude Code automations for Launch by Lunch — shared between Ariel and Karen.

## What's in here

| File | What it does |
|------|-------------|
| `commands/pm.md` | `/pm` slash command — project tracker operations |
| `tools/lbl-pm.py` | Script that reads/writes the shared Google Sheet |
| `tools/lbl-pm-setup.py` | One-time setup to create the Google Sheet (already run) |

---

## Setup (Karen)

### Prerequisites
- Claude Code installed and running
- Google OAuth configured (you already have this)

### Step 1 — Copy the command file
```bash
cp commands/pm.md ~/.claude/commands/pm.md
```

### Step 2 — Copy the tools
```bash
mkdir -p ~/tools
cp tools/lbl-pm.py ~/tools/lbl-pm.py
cp tools/lbl-pm-setup.py ~/tools/lbl-pm-setup.py
```

### Step 3 — Verify token paths
The script expects your Google tokens at:
- `~/.config/google-drive-mcp/tokens.json`
- `~/.gmail-mcp/gcp-oauth.keys.json`

If yours are in different locations, update the `TOKEN_FILE` and `CREDS_FILE` lines at the top of `lbl-pm.py`.

### Step 4 — Test it
In Claude Code, type `/pm` and ask to list priorities. You should see the shared Q2 priorities.

---

## Usage

Type `/pm` in any Claude Code session to access the project tracker.

**Common commands:**
- "list priorities" — see Q2 strategic priorities
- "list my tasks" — see tasks assigned to you
- "add task" — Claude will walk you through it with full enrichment
- "check my inbox for Fathom emails" — import tasks from meeting notes

---

## The Sheet

[LBL Project Management — Ariel & Karen](https://docs.google.com/spreadsheets/d/1yQ_TnZRQ8IHh-FIzXdrBcaNPOfNatYt2WlUh-g6mnRA/edit)
