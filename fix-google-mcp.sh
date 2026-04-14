#!/bin/bash
# ============================================================================
# Fix: Google MCP crash after setup (credentials not visible to server)
# Launch by Lunch | launchbylunch.co
#
# Symptom: after running the main setup script, `claude mcp list` shows
#   google: ... - ✗ Failed to connect
# The google-mcp-server binary crashes because it can't find OAuth credentials
# in the shell environment (this affects bash users whose shell doesn't read
# ~/.zshrc by default).
#
# This script writes a shell-independent config file at
#   ~/.google-mcp-server/config.json
# which the server reads directly.
#
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/ariellgalipeau/claude-workflows/main/fix-google-mcp.sh)
# ============================================================================

set -e

echo ""
echo "=========================================="
echo "  Fix: Google MCP Credentials Config"
echo "  Launch by Lunch"
echo "=========================================="
echo ""

# Try to recover credentials from ~/.zshrc (our setup script wrote them there)
CLIENT_ID=""
CLIENT_SECRET=""
if [ -f ~/.zshrc ]; then
    CLIENT_ID=$(grep 'GOOGLE_CLIENT_ID' ~/.zshrc 2>/dev/null | head -1 | sed 's/.*="//' | sed 's/"$//')
    CLIENT_SECRET=$(grep 'GOOGLE_CLIENT_SECRET' ~/.zshrc 2>/dev/null | head -1 | sed 's/.*="//' | sed 's/"$//')
fi

if [ -n "$CLIENT_ID" ] && [ -n "$CLIENT_SECRET" ]; then
    echo "Found your Google credentials in ~/.zshrc"
else
    echo "Couldn't find credentials automatically."
    echo "Paste them below (you got these from Google Cloud Console)."
    echo ""
    read -p "Paste your Google Client ID: " CLIENT_ID
    echo ""
    read -p "Paste your Google Client Secret: " CLIENT_SECRET
fi

if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ]; then
    echo ""
    echo "ERROR: Both Client ID and Client Secret are required."
    echo "Find them at: https://console.cloud.google.com/apis/credentials"
    exit 1
fi

# Write the config file
mkdir -p ~/.google-mcp-server
cat > ~/.google-mcp-server/config.json <<ENDOFCONFIG
{
  "oauth": {
    "client_id": "$CLIENT_ID",
    "client_secret": "$CLIENT_SECRET",
    "redirect_uri": "http://localhost:8080/callback"
  },
  "services": {
    "calendar": {"enabled": true},
    "drive": {"enabled": true},
    "gmail": {"enabled": true},
    "sheets": {"enabled": true},
    "docs": {"enabled": true}
  }
}
ENDOFCONFIG

echo ""
echo "  ✓ Config written to ~/.google-mcp-server/config.json"
echo ""
echo "=========================================="
echo "  Next steps"
echo "=========================================="
echo ""
echo "  1. Close Terminal COMPLETELY (Command + Q, not just the window)"
echo "  2. Reopen Terminal"
echo "  3. Run:  claude mcp list"
echo ""
echo "  You should now see:"
echo "    google: ... - ✓ Connected"
echo "    gmail:  ... - ✓ Connected"
echo ""
