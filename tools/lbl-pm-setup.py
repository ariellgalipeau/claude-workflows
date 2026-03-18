#!/usr/bin/env python3
"""
LBL Project Manager — One-time setup script
Creates the Google Sheet with both tabs, headers, dropdowns, and formatting.

Run once:
  python3 ~/tools/lbl-pm-setup.py

Then copy the printed SHEET_ID into:
  ~/tools/lbl-pm.py  (line: SHEET_ID = '...')
  ~/.claude/commands/pm.md  (line: SHEET_ID: ...)
"""

import json, urllib.request, urllib.parse
from datetime import datetime

import os
TOKEN_FILE = os.path.expanduser('~/.config/google-drive-mcp/tokens.json')
CREDS_FILE = os.path.expanduser('~/.gmail-mcp/gcp-oauth.keys.json')

# ── Auth ──────────────────────────────────────────────────────────────────────

def get_token():
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
    return tokens['access_token']

def api(url, data=None, method=None, token=None):
    headers = {'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'}
    body = json.dumps(data).encode() if data else None
    m = method or ('POST' if body else 'GET')
    req = urllib.request.Request(url, data=body, method=m, headers=headers)
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read())

# ── Sheet creation ─────────────────────────────────────────────────────────────

def create_spreadsheet(token):
    result = api(
        'https://sheets.googleapis.com/v4/spreadsheets',
        data={
            'properties': {'title': 'LBL Project Management — Ariel & Karen'},
            'sheets': [
                {'properties': {'title': 'Strategic Priorities', 'index': 0,
                                'gridProperties': {'frozenRowCount': 1}}},
                {'properties': {'title': 'Tasks', 'index': 1,
                                'gridProperties': {'frozenRowCount': 1}}}
            ]
        },
        token=token
    )
    sheet_id = result['spreadsheetId']
    # Get sheetIds for each tab
    tab_ids = {s['properties']['title']: s['properties']['sheetId']
               for s in result['sheets']}
    return sheet_id, tab_ids

def write_headers(sheet_id, token):
    priorities_headers = [
        ['Priority ID', 'Priority Name', 'Description', 'Quarter',
         'Owner', 'Status', 'Date Created', 'Last Updated']
    ]
    tasks_headers = [
        ['Task ID', 'Task Name', 'Strategic Priority', 'Owner', 'Due Date',
         'Priority', 'Status', 'Context / Description', 'Links',
         'Notes', 'Date Created', 'Last Updated']
    ]
    def put_values(range_str, values):
        body = json.dumps({
            'range': range_str,
            'majorDimension': 'ROWS',
            'values': values
        }).encode()
        url = (f'https://sheets.googleapis.com/v4/spreadsheets/{sheet_id}'
               f'/values/{urllib.parse.quote(range_str)}?valueInputOption=RAW')
        req = urllib.request.Request(url, data=body, method='PUT',
            headers={'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'})
        with urllib.request.urlopen(req) as r:
            return json.loads(r.read())

    put_values("Strategic Priorities!A1:H1", priorities_headers)
    put_values("Tasks!A1:L1", tasks_headers)

def format_sheet(sheet_id, tab_ids, token):
    priorities_id = tab_ids['Strategic Priorities']
    tasks_id = tab_ids['Tasks']

    # Colors
    HEADER_BG   = {'red': 0.259, 'green': 0.122, 'blue': 0.322}   # LBL dark purple
    HEADER_FG   = {'red': 1.0,   'green': 1.0,   'blue': 1.0}     # white
    HIGH_BG     = {'red': 0.957, 'green': 0.800, 'blue': 0.800}   # soft red
    MED_BG      = {'red': 1.0,   'green': 0.953, 'blue': 0.804}   # soft yellow
    LOW_BG      = {'red': 0.851, 'green': 0.918, 'blue': 0.827}   # soft green
    DONE_BG     = {'red': 0.878, 'green': 0.878, 'blue': 0.878}   # gray
    INPROG_BG   = {'red': 0.812, 'green': 0.886, 'blue': 0.953}   # soft blue
    ACTIVE_BG   = {'red': 0.851, 'green': 0.918, 'blue': 0.827}   # soft green
    PAUSED_BG   = {'red': 1.0,   'green': 0.953, 'blue': 0.804}   # soft yellow

    requests = []

    # ── Header row formatting (both tabs) ────────────────────────────────────
    for sid, ncols in [(priorities_id, 8), (tasks_id, 12)]:
        requests.append({'repeatCell': {
            'range': {'sheetId': sid, 'startRowIndex': 0, 'endRowIndex': 1,
                      'startColumnIndex': 0, 'endColumnIndex': ncols},
            'cell': {'userEnteredFormat': {
                'backgroundColor': HEADER_BG,
                'textFormat': {'bold': True,
                               'foregroundColor': HEADER_FG,
                               'fontSize': 10},
                'verticalAlignment': 'MIDDLE',
                'horizontalAlignment': 'CENTER',
                'wrapStrategy': 'WRAP'
            }},
            'fields': 'userEnteredFormat(backgroundColor,textFormat,verticalAlignment,horizontalAlignment,wrapStrategy)'
        }})

    # ── Data row formatting (both tabs) ─────────────────────────────────────
    for sid, ncols in [(priorities_id, 8), (tasks_id, 12)]:
        requests.append({'repeatCell': {
            'range': {'sheetId': sid, 'startRowIndex': 1, 'endRowIndex': 1000,
                      'startColumnIndex': 0, 'endColumnIndex': ncols},
            'cell': {'userEnteredFormat': {
                'wrapStrategy': 'WRAP',
                'verticalAlignment': 'TOP'
            }},
            'fields': 'userEnteredFormat(wrapStrategy,verticalAlignment)'
        }})

    # ── Column widths — Tasks tab ────────────────────────────────────────────
    task_widths = [60, 200, 180, 90, 90, 80, 100, 250, 150, 200, 100, 100]
    for i, w in enumerate(task_widths):
        requests.append({'updateDimensionProperties': {
            'range': {'sheetId': tasks_id, 'dimension': 'COLUMNS',
                      'startIndex': i, 'endIndex': i + 1},
            'properties': {'pixelSize': w},
            'fields': 'pixelSize'
        }})

    # ── Column widths — Priorities tab ──────────────────────────────────────
    priority_widths = [80, 200, 280, 90, 100, 100, 100, 100]
    for i, w in enumerate(priority_widths):
        requests.append({'updateDimensionProperties': {
            'range': {'sheetId': priorities_id, 'dimension': 'COLUMNS',
                      'startIndex': i, 'endIndex': i + 1},
            'properties': {'pixelSize': w},
            'fields': 'pixelSize'
        }})

    # ── Data validation — Tasks tab ─────────────────────────────────────────

    def one_of_list(*values):
        return {'condition': {'type': 'ONE_OF_LIST',
                              'values': [{'userEnteredValue': v} for v in values]},
                'showCustomUi': True, 'strict': True}

    # Strategic Priority → cross-tab range
    requests.append({'setDataValidation': {
        'range': {'sheetId': tasks_id, 'startRowIndex': 1, 'endRowIndex': 1000,
                  'startColumnIndex': 2, 'endColumnIndex': 3},
        'rule': {
            'condition': {
                'type': 'ONE_OF_RANGE',
                'values': [{'userEnteredValue': "='Strategic Priorities'!$B$2:$B"}]
            },
            'showCustomUi': True, 'strict': False
        }
    }})
    # Owner (Tasks)
    requests.append({'setDataValidation': {
        'range': {'sheetId': tasks_id, 'startRowIndex': 1, 'endRowIndex': 1000,
                  'startColumnIndex': 3, 'endColumnIndex': 4},
        'rule': one_of_list('Ariel', 'Karen')
    }})
    # Priority
    requests.append({'setDataValidation': {
        'range': {'sheetId': tasks_id, 'startRowIndex': 1, 'endRowIndex': 1000,
                  'startColumnIndex': 5, 'endColumnIndex': 6},
        'rule': one_of_list('High', 'Medium', 'Low')
    }})
    # Status (Tasks)
    requests.append({'setDataValidation': {
        'range': {'sheetId': tasks_id, 'startRowIndex': 1, 'endRowIndex': 1000,
                  'startColumnIndex': 6, 'endColumnIndex': 7},
        'rule': one_of_list('Not Started', 'In Progress', 'Done')
    }})

    # ── Data validation — Priorities tab ────────────────────────────────────
    # Owner
    requests.append({'setDataValidation': {
        'range': {'sheetId': priorities_id, 'startRowIndex': 1, 'endRowIndex': 200,
                  'startColumnIndex': 4, 'endColumnIndex': 5},
        'rule': one_of_list('Ariel', 'Karen', 'Both')
    }})
    # Quarter
    requests.append({'setDataValidation': {
        'range': {'sheetId': priorities_id, 'startRowIndex': 1, 'endRowIndex': 200,
                  'startColumnIndex': 3, 'endColumnIndex': 4},
        'rule': one_of_list('Q1 2026', 'Q2 2026', 'Q3 2026', 'Q4 2026',
                             'Q1 2027', 'Q2 2027', 'Q3 2027', 'Q4 2027')
    }})
    # Status (Priorities)
    requests.append({'setDataValidation': {
        'range': {'sheetId': priorities_id, 'startRowIndex': 1, 'endRowIndex': 200,
                  'startColumnIndex': 5, 'endColumnIndex': 6},
        'rule': one_of_list('Active', 'Complete', 'Paused')
    }})

    # ── Conditional formatting — Tasks: Priority column (F = index 5) ────────
    for text, bg in [('High', HIGH_BG), ('Medium', MED_BG), ('Low', LOW_BG)]:
        requests.append({'addConditionalFormatRule': {
            'rule': {
                'ranges': [{'sheetId': tasks_id, 'startRowIndex': 1, 'endRowIndex': 1000,
                             'startColumnIndex': 5, 'endColumnIndex': 6}],
                'booleanRule': {
                    'condition': {'type': 'TEXT_EQ',
                                  'values': [{'userEnteredValue': text}]},
                    'format': {'backgroundColor': bg}
                }
            }, 'index': 0
        }})

    # ── Conditional formatting — Tasks: Status column (G = index 6) ─────────
    for text, bg in [('Done', DONE_BG), ('In Progress', INPROG_BG)]:
        requests.append({'addConditionalFormatRule': {
            'rule': {
                'ranges': [{'sheetId': tasks_id, 'startRowIndex': 1, 'endRowIndex': 1000,
                             'startColumnIndex': 6, 'endColumnIndex': 7}],
                'booleanRule': {
                    'condition': {'type': 'TEXT_EQ',
                                  'values': [{'userEnteredValue': text}]},
                    'format': {'backgroundColor': bg}
                }
            }, 'index': 0
        }})

    # ── Conditional formatting — Priorities: Status column (F = index 5) ────
    for text, bg in [('Active', ACTIVE_BG), ('Paused', PAUSED_BG), ('Complete', DONE_BG)]:
        requests.append({'addConditionalFormatRule': {
            'rule': {
                'ranges': [{'sheetId': priorities_id, 'startRowIndex': 1, 'endRowIndex': 200,
                             'startColumnIndex': 5, 'endColumnIndex': 6}],
                'booleanRule': {
                    'condition': {'type': 'TEXT_EQ',
                                  'values': [{'userEnteredValue': text}]},
                    'format': {'backgroundColor': bg}
                }
            }, 'index': 0
        }})

    # ── Send all requests ────────────────────────────────────────────────────
    url = f'https://sheets.googleapis.com/v4/spreadsheets/{sheet_id}:batchUpdate'
    body = json.dumps({'requests': requests}).encode()
    req = urllib.request.Request(url, data=body, method='POST',
        headers={'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'})
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read())


def main():
    print("Refreshing token...")
    token = get_token()

    print("Creating spreadsheet...")
    sheet_id, tab_ids = create_spreadsheet(token)
    print(f"  Created: https://docs.google.com/spreadsheets/d/{sheet_id}/edit")

    print("Writing headers...")
    write_headers(sheet_id, token)

    print("Applying formatting, dropdowns, conditional rules...")
    format_sheet(sheet_id, tab_ids, token)

    print("\n✓ Setup complete!\n")
    print("=" * 60)
    print(f"SHEET_ID = '{sheet_id}'")
    print("=" * 60)
    print("\nNext steps:")
    print(f"  1. Copy the SHEET_ID above into ~/tools/lbl-pm.py")
    print(f"  2. Copy it into ~/.claude/commands/pm.md")
    print(f"  3. Share the sheet with Karen")
    print(f"  4. Add your first strategic priorities: /pm → 'add priority'")

if __name__ == '__main__':
    main()
