#!/usr/bin/env python3
"""
LBL Project Manager — Claude Code operations script

Commands:
  list-priorities
  add-priority --json '{"name":"...","description":"...","quarter":"Q2 2026","owner":"Ariel","status":"Active"}'
  list-tasks [--owner Ariel|Karen] [--priority High|Medium|Low] [--status "Not Started"|"In Progress"|Done] [--strategic-priority "..."]
  add-task --json '{"name":"...","strategic_priority":"...","owner":"...","due_date":"YYYY-MM-DD","priority":"...","status":"Not Started","context":"...","links":"...","notes":"..."}'
  batch-add-tasks --json '[{...}, {...}]'
  update-task --id 5 --fields '{"status":"Done","notes":"..."}'
  update-task --name "Task name" --fields '{"status":"Done"}'
"""

import sys, json, argparse, urllib.request, urllib.parse
from datetime import datetime

# ── Configuration — fill in SHEET_ID after running lbl-pm-setup.py ──────────
SHEET_ID = '1yQ_TnZRQ8IHh-FIzXdrBcaNPOfNatYt2WlUh-g6mnRA'

import os
TOKEN_FILE = os.path.expanduser('~/.config/google-drive-mcp/tokens.json')
CREDS_FILE = os.path.expanduser('~/.gmail-mcp/gcp-oauth.keys.json')

PRIORITIES_TAB = 'Strategic Priorities'
TASKS_TAB = 'Tasks'

# Column indices (0-based)
PRI_COLS = {'id': 0, 'name': 1, 'description': 2, 'quarter': 3,
            'owner': 4, 'created': 5, 'updated': 6}
# Cols H-K (indices 7-10) are formula-only: Total Tasks, Done, % Complete, Auto Status
TASK_COLS = {'id': 0, 'name': 1, 'strategic_priority': 2, 'owner': 3,
             'due_date': 4, 'priority': 5, 'status': 6, 'context': 7,
             'links': 8, 'notes': 9, 'created': 10, 'updated': 11}

# ── Auth ──────────────────────────────────────────────────────────────────────

_token = None

def get_token():
    global _token
    if _token:
        return _token
    with open(TOKEN_FILE) as f:
        tokens = json.load(f)
    with open(CREDS_FILE) as f:
        creds = json.load(f)
    data = urllib.parse.urlencode({
        'client_id': creds['installed']['client_id'],
        'client_secret': creds['installed']['client_secret'],
        'refresh_token': tokens['refresh_token'],
        'grant_type': 'refresh_token'
    }).encode()
    req = urllib.request.Request(
        'https://oauth2.googleapis.com/token', data=data, method='POST')
    with urllib.request.urlopen(req) as r:
        new_tokens = json.loads(r.read())
    tokens['access_token'] = new_tokens['access_token']
    with open(TOKEN_FILE, 'w') as f:
        json.dump(tokens, f, indent=2)
    _token = tokens['access_token']
    return _token

# ── Sheets API helpers ────────────────────────────────────────────────────────

def sheets_get(range_str):
    token = get_token()
    url = (f'https://sheets.googleapis.com/v4/spreadsheets/{SHEET_ID}'
           f'/values/{urllib.parse.quote(range_str)}')
    req = urllib.request.Request(url,
        headers={'Authorization': f'Bearer {token}'})
    with urllib.request.urlopen(req) as r:
        result = json.loads(r.read())
    return result.get('values', [])

def sheets_append(tab_name, row_values):
    token = get_token()
    range_str = f'{tab_name}!A:A'
    body = json.dumps({
        'range': range_str,
        'majorDimension': 'ROWS',
        'values': [row_values]
    }).encode()
    url = (f'https://sheets.googleapis.com/v4/spreadsheets/{SHEET_ID}'
           f'/values/{urllib.parse.quote(range_str)}:append'
           f'?valueInputOption=USER_ENTERED&insertDataOption=INSERT_ROWS')
    req = urllib.request.Request(url, data=body, method='POST',
        headers={'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'})
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read())

def sheets_put(range_str, row_values):
    token = get_token()
    body = json.dumps({
        'range': range_str,
        'majorDimension': 'ROWS',
        'values': [row_values]
    }).encode()
    url = (f'https://sheets.googleapis.com/v4/spreadsheets/{SHEET_ID}'
           f'/values/{urllib.parse.quote(range_str)}?valueInputOption=USER_ENTERED')
    req = urllib.request.Request(url, data=body, method='PUT',
        headers={'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'})
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read())

# ── Data helpers ─────────────────────────────────────────────────────────────

def now():
    return datetime.now().strftime('%Y-%m-%d')

def pad_row(row, length):
    """Ensure row has at least `length` cells."""
    return row + [''] * (length - len(row))

def get_all_priorities():
    rows = sheets_get(f'{PRIORITIES_TAB}!A2:H')
    return [pad_row(r, 8) for r in rows if r]

def get_all_tasks():
    rows = sheets_get(f'{TASKS_TAB}!A2:L')
    return [pad_row(r, 12) for r in rows if r]

def get_priority_names():
    rows = get_all_priorities()
    return [r[PRI_COLS['name']] for r in rows
            if r[PRI_COLS['name']]]

def next_priority_id():
    rows = get_all_priorities()
    if not rows:
        return 1
    ids = [int(r[0]) for r in rows if r[0].isdigit()]
    return max(ids) + 1 if ids else 1

def next_task_id():
    rows = get_all_tasks()
    if not rows:
        return 1
    ids = [int(r[0]) for r in rows if r[0].isdigit()]
    return max(ids) + 1 if ids else 1

def find_task(id_or_name):
    """Returns (row_index_1based, row_data) or (None, None)."""
    rows = get_all_tasks()
    for i, row in enumerate(rows):
        if str(id_or_name).isdigit() and row[TASK_COLS['id']] == str(id_or_name):
            return i + 2, row   # +2: 1-based + header row
        if not str(id_or_name).isdigit():
            if row[TASK_COLS['name']].lower() == str(id_or_name).lower():
                return i + 2, row
    return None, None

# ── Commands ─────────────────────────────────────────────────────────────────

def cmd_list_priorities():
    rows = get_all_priorities()
    if not rows:
        print("No strategic priorities found. Add one with: add-priority")
        return
    print(f"\n{'ID':<5} {'Auto Status':<14} {'Quarter':<10} {'Owner':<8} {'Priority Name'}")
    print("─" * 75)
    for r in rows:
        auto_status = r[10] if len(r) > 10 else 'Active'
        print(f"{r[0]:<5} {auto_status:<14} {r[PRI_COLS['quarter']]:<10} "
              f"{r[PRI_COLS['owner']]:<8} {r[PRI_COLS['name']]}")
        if r[PRI_COLS['description']]:
            print(f"      {r[PRI_COLS['description']][:65]}")
    print()

def cmd_add_priority(data):
    required = ['name', 'quarter', 'owner']
    missing = [f for f in required if not data.get(f)]
    if missing:
        print(f"Missing required fields: {', '.join(missing)}")
        sys.exit(1)
    pid = next_priority_id()
    row = [
        pid,
        data['name'],
        data.get('description', ''),
        data['quarter'],
        data['owner'],
        now(),
        now()
    ]  # Cols H-K (Auto Status, metrics) are formula-driven — not written here
    sheets_append(PRIORITIES_TAB, [str(v) for v in row])
    print(f"✓ Priority #{pid} added: {data['name']}")

def cmd_list_tasks(filters=None):
    filters = filters or {}
    rows = get_all_tasks()
    if not rows:
        print("No tasks found. Add one with: add-task")
        return

    # Apply filters
    def matches(row):
        if filters.get('owner') and row[TASK_COLS['owner']].lower() != filters['owner'].lower():
            return False
        if filters.get('priority') and row[TASK_COLS['priority']].lower() != filters['priority'].lower():
            return False
        if filters.get('status') and row[TASK_COLS['status']].lower() != filters['status'].lower():
            return False
        if filters.get('strategic_priority'):
            if filters['strategic_priority'].lower() not in row[TASK_COLS['strategic_priority']].lower():
                return False
        return True

    visible = [r for r in rows if matches(r)]
    if not visible:
        print("No tasks match the given filters.")
        return

    # Sort by: status priority (Not Started, In Progress, Done), then due date
    status_order = {'not started': 0, 'in progress': 1, 'done': 2}
    visible.sort(key=lambda r: (
        status_order.get(r[TASK_COLS['status']].lower(), 9),
        r[TASK_COLS['due_date']] or 'zzzz'
    ))

    print(f"\n{'ID':<5} {'Pri':<7} {'Status':<13} {'Owner':<7} {'Due':<12} {'Task Name'}")
    print("─" * 80)
    for r in visible:
        name = r[TASK_COLS['name']][:40]
        print(f"{r[0]:<5} {r[TASK_COLS['priority']]:<7} {r[TASK_COLS['status']]:<13} "
              f"{r[TASK_COLS['owner']]:<7} {r[TASK_COLS['due_date']]:<12} {name}")
        if r[TASK_COLS['strategic_priority']]:
            print(f"      → {r[TASK_COLS['strategic_priority']]}")
        if r[TASK_COLS['context']]:
            print(f"      {r[TASK_COLS['context']][:65]}")
    print(f"\n{len(visible)} task(s) shown\n")

def cmd_add_task(data):
    required = ['name', 'owner', 'priority']
    missing = [f for f in required if not data.get(f)]
    if missing:
        print(f"Missing required fields: {', '.join(missing)}")
        sys.exit(1)

    # Validate strategic priority if provided
    sp = data.get('strategic_priority', '')
    if sp:
        known = get_priority_names()
        if sp not in known:
            print(f"Warning: '{sp}' not found in Strategic Priorities.")
            print(f"Known priorities: {', '.join(known) or 'none yet'}")
            print("Writing anyway — fix in the sheet if needed.")

    tid = next_task_id()
    row = [
        tid,
        data['name'],
        sp,
        data['owner'],
        data.get('due_date', ''),
        data['priority'],
        data.get('status', 'Not Started'),
        data.get('context', ''),
        data.get('links', ''),
        data.get('notes', ''),
        now(),
        now()
    ]
    sheets_append(TASKS_TAB, [str(v) for v in row])
    print(f"✓ Task #{tid} added: {data['name']}")

def cmd_batch_add_tasks(tasks):
    print(f"Adding {len(tasks)} task(s)...")
    for task in tasks:
        cmd_add_task(task)

def cmd_update_task(id_or_name, fields):
    row_num, row = find_task(id_or_name)
    if row is None:
        print(f"Task not found: {id_or_name}")
        sys.exit(1)

    field_map = {
        'name': TASK_COLS['name'], 'strategic_priority': TASK_COLS['strategic_priority'],
        'owner': TASK_COLS['owner'], 'due_date': TASK_COLS['due_date'],
        'priority': TASK_COLS['priority'], 'status': TASK_COLS['status'],
        'context': TASK_COLS['context'], 'links': TASK_COLS['links'],
        'notes': TASK_COLS['notes']
    }
    updated = list(row)
    for key, val in fields.items():
        if key in field_map:
            updated[field_map[key]] = str(val)
    updated[TASK_COLS['updated']] = now()

    range_str = f'{TASKS_TAB}!A{row_num}:L{row_num}'
    sheets_put(range_str, [str(v) for v in updated])
    print(f"✓ Task #{row[0]} updated: {', '.join(f'{k}={v}' for k, v in fields.items())}")

# ── CLI ───────────────────────────────────────────────────────────────────────

def main():
    if SHEET_ID == 'SHEET_ID_HERE':
        print("ERROR: SHEET_ID not set. Run lbl-pm-setup.py first, then paste the ID into this file.")
        sys.exit(1)

    parser = argparse.ArgumentParser(description='LBL Project Manager')
    subparsers = parser.add_subparsers(dest='command')

    # list-priorities
    subparsers.add_parser('list-priorities')

    # add-priority
    p = subparsers.add_parser('add-priority')
    p.add_argument('--json', dest='data', required=True)

    # list-tasks
    p = subparsers.add_parser('list-tasks')
    p.add_argument('--owner')
    p.add_argument('--priority')
    p.add_argument('--status')
    p.add_argument('--strategic-priority', dest='strategic_priority')

    # add-task
    p = subparsers.add_parser('add-task')
    p.add_argument('--json', dest='data', required=True)

    # batch-add-tasks
    p = subparsers.add_parser('batch-add-tasks')
    p.add_argument('--json', dest='data', required=True)

    # update-task
    p = subparsers.add_parser('update-task')
    p.add_argument('--id')
    p.add_argument('--name')
    p.add_argument('--fields', required=True)

    args = parser.parse_args()

    if args.command == 'list-priorities':
        cmd_list_priorities()

    elif args.command == 'add-priority':
        cmd_add_priority(json.loads(args.data))

    elif args.command == 'list-tasks':
        filters = {}
        if args.owner: filters['owner'] = args.owner
        if args.priority: filters['priority'] = args.priority
        if args.status: filters['status'] = args.status
        if args.strategic_priority: filters['strategic_priority'] = args.strategic_priority
        cmd_list_tasks(filters)

    elif args.command == 'add-task':
        cmd_add_task(json.loads(args.data))

    elif args.command == 'batch-add-tasks':
        cmd_batch_add_tasks(json.loads(args.data))

    elif args.command == 'update-task':
        id_or_name = args.id or args.name
        if not id_or_name:
            print("Provide --id or --name")
            sys.exit(1)
        cmd_update_task(id_or_name, json.loads(args.fields))

    else:
        parser.print_help()

if __name__ == '__main__':
    main()
