#!/bin/bash
# ============================================================================
# Build Your AI Chief of Staff — Mac Setup Script
# Launch by Lunch | launchbylunch.co
#
# This script automates the terminal setup after you've completed:
#   1. Claude Pro subscription
#   2. Claude Code installed
#   3. Google Cloud Project created with OAuth credentials
#
# Features:
#   - Resumable: re-run the script and it skips completed steps
#   - Non-admin fallback: works without sudo (uses npx instead of Homebrew)
#
# Usage: bash setup-chief-of-staff-mac.sh
# ============================================================================

# --- Checkpoint system ---
CHECKPOINT_DIR="$HOME/.chief-setup"
mkdir -p "$CHECKPOINT_DIR"

step_done() {
    [ -f "$CHECKPOINT_DIR/step_$1" ]
}

mark_done() {
    touch "$CHECKPOINT_DIR/step_$1"
}

step_failed() {
    echo ""
    echo "  ✗ Step $1 failed."
    echo "  Fix the issue above, then re-run this script."
    echo "  Completed steps will be skipped automatically."
    exit 1
}

echo ""
echo "=========================================="
echo "  Build Your AI Chief of Staff — Mac"
echo "  Launch by Lunch"
echo "=========================================="
echo ""
echo "This script will set up your Google connections and folder structure."
echo "You'll need your Google OAuth Client ID and Client Secret ready."
echo "(You got these from your Google Cloud Console in the previous step.)"
echo ""

# --- Collect credentials (always needed for the session) ---
if step_done "credentials_saved" && grep -q 'GOOGLE_CLIENT_ID' ~/.zshrc 2>/dev/null; then
    echo "Found saved Google credentials from a previous run."
    read -p "Use existing credentials? (y/n): " USE_SAVED
    if [ "$USE_SAVED" = "y" ] || [ "$USE_SAVED" = "Y" ]; then
        CLIENT_ID=$(grep 'GOOGLE_CLIENT_ID' ~/.zshrc | head -1 | sed 's/.*="//' | sed 's/"//')
        CLIENT_SECRET=$(grep 'GOOGLE_CLIENT_SECRET' ~/.zshrc | head -1 | sed 's/.*="//' | sed 's/"//')
        echo "  ✓ Using saved credentials"
    else
        read -p "Paste your Google Client ID: " CLIENT_ID
        echo ""
        read -p "Paste your Google Client Secret: " CLIENT_SECRET
    fi
else
    read -p "Paste your Google Client ID: " CLIENT_ID
    echo ""
    read -p "Paste your Google Client Secret: " CLIENT_SECRET
fi
echo ""

if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ]; then
    echo "ERROR: Both Client ID and Client Secret are required."
    echo "Go back to your Google Cloud Console to find them."
    exit 1
fi

# Export for this session
export GOOGLE_CLIENT_ID="$CLIENT_ID"
export GOOGLE_CLIENT_SECRET="$CLIENT_SECRET"

echo "Got it. Starting setup..."
echo ""

# --- Check admin status ---
IS_ADMIN=false
if groups | grep -q -w admin 2>/dev/null; then
    IS_ADMIN=true
fi

# =========================================================================
# Step 1: Claude Code
# =========================================================================
echo "[1/8] Checking Claude Code..."
if step_done 1 && command -v claude &> /dev/null; then
    echo "  ✓ Claude Code is installed (skipped)"
elif command -v claude &> /dev/null; then
    echo "  ✓ Claude Code is installed"
    mark_done 1
else
    echo "  Claude Code not found. Installing..."
    if curl -fsSL https://claude.ai/install.sh | bash; then
        export PATH="$HOME/.local/bin:$PATH"
        if ! grep -q '.local/bin' ~/.zshrc 2>/dev/null; then
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
        fi
        echo "  ✓ Claude Code installed"
        mark_done 1
    else
        step_failed 1
    fi
fi
echo ""

# =========================================================================
# Step 2: Install Homebrew (or skip if not admin)
# =========================================================================
echo "[2/8] Checking Homebrew..."
if step_done 2; then
    echo "  ✓ Homebrew step already completed (skipped)"
elif command -v brew &> /dev/null; then
    echo "  ✓ Homebrew is installed"
    mark_done 2
elif [ "$IS_ADMIN" = true ]; then
    echo "  Homebrew not found. Installing (this may take a few minutes)..."
    echo "  You may be asked for your Mac password."
    if /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
        # Add Homebrew to PATH for Apple Silicon
        if [ -f /opt/homebrew/bin/brew ]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
            if ! grep -q 'homebrew' ~/.zshrc 2>/dev/null; then
                echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zshrc
            fi
        fi
        echo "  ✓ Homebrew installed"
        mark_done 2
    else
        echo "  ⚠ Homebrew install failed. Continuing without it (will use npx instead)."
        mark_done 2
    fi
else
    echo "  ⚠ You're not an admin user, so we'll skip Homebrew."
    echo "  No worries! We'll use an alternate method for the Google connection."
    mark_done 2
fi
echo ""

# =========================================================================
# Step 3: Install google-mcp-server
# =========================================================================
echo "[3/8] Installing Google MCP server..."

# Determine install method and path
GOOGLE_MCP_PATH=""

if step_done 3; then
    # Recover the path from the checkpoint
    if [ -f "$CHECKPOINT_DIR/google_mcp_path" ]; then
        GOOGLE_MCP_PATH=$(cat "$CHECKPOINT_DIR/google_mcp_path")
        echo "  ✓ google-mcp-server already set up (skipped)"
    elif command -v google-mcp-server &> /dev/null; then
        GOOGLE_MCP_PATH=$(which google-mcp-server)
        echo "  ✓ google-mcp-server found at $GOOGLE_MCP_PATH (skipped)"
    fi
elif command -v brew &> /dev/null; then
    # Homebrew path
    brew tap ngs/tap 2>/dev/null || true
    if brew list ngs/tap/google-mcp-server &>/dev/null; then
        echo "  ✓ google-mcp-server already installed via Homebrew"
    else
        if brew install google-mcp-server; then
            echo "  ✓ google-mcp-server installed via Homebrew"
        else
            step_failed 3
        fi
    fi
    # Find the binary
    if [ -f /opt/homebrew/bin/google-mcp-server ]; then
        GOOGLE_MCP_PATH="/opt/homebrew/bin/google-mcp-server"
    elif [ -f /usr/local/bin/google-mcp-server ]; then
        GOOGLE_MCP_PATH="/usr/local/bin/google-mcp-server"
    else
        GOOGLE_MCP_PATH="google-mcp-server"
    fi
    echo "$GOOGLE_MCP_PATH" > "$CHECKPOINT_DIR/google_mcp_path"
    mark_done 3
else
    # Non-admin fallback: use npx
    echo "  Using npx to run google-mcp-server (no Homebrew needed)..."
    # Verify npx/node is available
    if command -v npx &> /dev/null; then
        GOOGLE_MCP_PATH="npx"
        echo "npx" > "$CHECKPOINT_DIR/google_mcp_path"
        echo "  ✓ Will use npx for google-mcp-server"
        mark_done 3
    else
        echo "  ⚠ npx not found. Checking for Node.js..."
        if command -v node &> /dev/null; then
            GOOGLE_MCP_PATH="npx"
            echo "npx" > "$CHECKPOINT_DIR/google_mcp_path"
            echo "  ✓ Node.js found, will use npx"
            mark_done 3
        else
            echo ""
            echo "  Neither Homebrew nor Node.js is available."
            echo "  Please ask a facilitator for help, or install Node.js from https://nodejs.org"
            step_failed 3
        fi
    fi
fi
echo ""

# =========================================================================
# Step 4: Save credentials
# =========================================================================
echo "[4/8] Saving your Google credentials..."
if step_done "credentials_saved"; then
    # Still update in case user provided new credentials this run
    if [ -f ~/.zshrc ]; then
        sed -i '' '/GOOGLE_CLIENT_ID/d' ~/.zshrc 2>/dev/null || true
        sed -i '' '/GOOGLE_CLIENT_SECRET/d' ~/.zshrc 2>/dev/null || true
    fi
fi

# Always write current credentials
if [ -f ~/.zshrc ]; then
    sed -i '' '/GOOGLE_CLIENT_ID/d' ~/.zshrc 2>/dev/null || true
    sed -i '' '/GOOGLE_CLIENT_SECRET/d' ~/.zshrc 2>/dev/null || true
fi

echo "export GOOGLE_CLIENT_ID=\"$CLIENT_ID\"" >> ~/.zshrc
echo "export GOOGLE_CLIENT_SECRET=\"$CLIENT_SECRET\"" >> ~/.zshrc

echo "  ✓ Credentials saved"
mark_done "credentials_saved"
echo ""

# =========================================================================
# Step 5: Authenticate Google (Calendar, Drive, Gmail, Slides)
# =========================================================================
echo "[5/8] Authenticating with Google (Calendar, Drive, Slides)..."
if step_done 5; then
    echo "  ✓ Google auth already completed (skipped)"
    read -p "  Re-run authentication anyway? (y/n): " REAUTH
    if [ "$REAUTH" != "y" ] && [ "$REAUTH" != "Y" ]; then
        echo ""
        echo "  Skipping."
    else
        echo ""
        echo "  Your browser will open. Sign in with your Google account."
        echo ""
        echo "  ⚠ IMPORTANT: You may see a warning that says 'Google hasn't verified this app'."
        echo "  Click 'Advanced' at the bottom left, then click 'Go to [app name] (unsafe)'."
        echo "  This is normal for your own Google Cloud project. Click 'Continue' to allow access."
        echo ""
        echo "  After you see the success message, come back here and press Control + C."
        echo ""
        read -p "  Press Enter to open the browser..." _dummy
        if [ "$GOOGLE_MCP_PATH" = "npx" ]; then
            npx -y @anthropic-ai/google-mcp-server || true
        else
            $GOOGLE_MCP_PATH || true
        fi
        echo ""
        echo "  ✓ Google Calendar + Drive authenticated"
    fi
else
    echo ""
    echo "  Your browser will open. Sign in with your Google account."
    echo ""
    echo "  ⚠ IMPORTANT: You may see a warning that says 'Google hasn't verified this app'."
    echo "  Click 'Advanced' at the bottom left, then click 'Go to [app name] (unsafe)'."
    echo "  This is normal for your own Google Cloud project. Click 'Continue' to allow access."
    echo ""
    echo "  After you see the success message, come back here and press Control + C."
    echo ""
    read -p "  Press Enter to open the browser..." _dummy
    if [ "$GOOGLE_MCP_PATH" = "npx" ]; then
        npx -y @anthropic-ai/google-mcp-server || true
    else
        $GOOGLE_MCP_PATH || true
    fi
    echo ""
    echo "  ✓ Google Calendar + Drive authenticated"
    mark_done 5
fi
echo ""

# =========================================================================
# Step 6: Add MCP servers to Claude Code
# =========================================================================
echo "[6/8] Adding Google connection to Claude Code..."
if step_done 6; then
    echo "  ✓ MCP connections already added (skipped)"
else
    # Make sure claude is on PATH
    export PATH="$HOME/.local/bin:$PATH"

    if ! command -v claude &> /dev/null; then
        echo "  ⚠ Claude Code not found on PATH. Trying to locate it..."
        if [ -f "$HOME/.local/bin/claude" ]; then
            export PATH="$HOME/.local/bin:$PATH"
        else
            echo "  ✗ Could not find Claude Code. Please restart your terminal and re-run this script."
            step_failed 6
        fi
    fi

    # Remove old entries if they exist (clean slate)
    claude mcp remove google 2>/dev/null || true
    claude mcp remove gmail 2>/dev/null || true

    # Add Google (covers Calendar, Drive, Gmail, Slides with one auth)
    if [ "$GOOGLE_MCP_PATH" = "npx" ]; then
        claude mcp add --scope user google -- npx -y @anthropic-ai/google-mcp-server
    else
        claude mcp add --scope user google "$GOOGLE_MCP_PATH"
    fi
    echo "  ✓ Google connection added (Calendar, Drive, Gmail, Slides)"
    mark_done 6
fi
echo ""

# =========================================================================
# Step 7: Gmail (send) MCP — separate server with its own auth
# =========================================================================
# The ngs google-mcp-server in Step 6 is READ-ONLY for Gmail (list + get).
# To send email from Claude Code, we need @gongrzhe/server-gmail-autoauth-mcp.
# It uses the same OAuth client (your client_secret_*.json) but a separate token.
echo "[7/8] Setting up Gmail send capability..."
if step_done 7; then
    echo "  ✓ Gmail MCP already set up (skipped)"
else
    # Locate the OAuth JSON (auto-search Downloads, then Desktop)
    GMAIL_JSON=""
    if [ -f ~/.gmail-mcp/gcp-oauth.keys.json ]; then
        echo "  ✓ Found existing OAuth keys at ~/.gmail-mcp/gcp-oauth.keys.json"
    else
        mkdir -p ~/.gmail-mcp
        FOUND_JSON=$(ls ~/Downloads/client_secret_*.json 2>/dev/null | head -1)
        if [ -z "$FOUND_JSON" ]; then
            FOUND_JSON=$(ls ~/Desktop/client_secret_*.json 2>/dev/null | head -1)
        fi

        if [ -n "$FOUND_JSON" ]; then
            echo "  Found OAuth file: $(basename "$FOUND_JSON")"
            read -p "  Use this file? (y/n): " USE_FOUND
            if [ "$USE_FOUND" = "y" ] || [ "$USE_FOUND" = "Y" ]; then
                cp "$FOUND_JSON" ~/.gmail-mcp/gcp-oauth.keys.json
                echo "  ✓ Copied to ~/.gmail-mcp/gcp-oauth.keys.json"
            else
                echo "  Drag the JSON file from Finder into this terminal window, then press Enter:"
                read -p "  > " DRAGGED_PATH
                DRAGGED_PATH=$(echo "$DRAGGED_PATH" | sed "s/^['\"]//;s/['\"]$//")
                cp "$DRAGGED_PATH" ~/.gmail-mcp/gcp-oauth.keys.json
                echo "  ✓ Copied to ~/.gmail-mcp/gcp-oauth.keys.json"
            fi
        else
            echo "  No client_secret_*.json found in Downloads or Desktop."
            echo "  Drag the JSON file from Finder into this terminal window, then press Enter:"
            read -p "  > " DRAGGED_PATH
            DRAGGED_PATH=$(echo "$DRAGGED_PATH" | sed "s/^['\"]//;s/['\"]$//")
            cp "$DRAGGED_PATH" ~/.gmail-mcp/gcp-oauth.keys.json
            echo "  ✓ Copied to ~/.gmail-mcp/gcp-oauth.keys.json"
        fi
    fi

    echo ""
    echo "  Your browser will open for Gmail authentication."
    echo ""
    echo "  ⚠ IMPORTANT: On the Google permission screen, make sure EVERY checkbox"
    echo "  is checked — especially 'Send email on your behalf'. If you skip it,"
    echo "  Claude won't be able to send mail."
    echo ""
    read -p "  Press Enter to open the browser..." _dummy
    if npx -y @gongrzhe/server-gmail-autoauth-mcp auth; then
        echo "  ✓ Gmail authenticated"
    else
        echo "  ⚠ Gmail auth did not complete cleanly. You can re-run this script to retry."
        step_failed 7
    fi

    # Add the MCP to Claude Code
    claude mcp remove gmail 2>/dev/null || true
    if claude mcp add --scope user gmail -- npx -y @gongrzhe/server-gmail-autoauth-mcp; then
        echo "  ✓ Gmail MCP added to Claude Code (send + read)"
        mark_done 7
    else
        echo "  ✗ Failed to add Gmail MCP to Claude Code."
        step_failed 7
    fi
fi
echo ""

# =========================================================================
# Step 8: Folder structure
# =========================================================================
echo "[8/8] Creating your Chief of Staff folder structure..."
if step_done 7; then
    echo "  ✓ Folder structure already created (skipped)"
else
    mkdir -p ~/chief/about-me
    mkdir -p ~/chief/memory/conversations
    mkdir -p ~/chief/Tools
    mkdir -p ~/chief/Notes
    touch ~/chief/memory/memory.md
    touch ~/chief/memory/context.txt

    if [ -f ~/chief/CLAUDE.md ]; then
        echo "  ✓ CLAUDE.md found"
    else
        echo "  NOTE: No CLAUDE.md found in ~/chief/ — make sure to add it before the event"
    fi

    echo "  ✓ Folder structure created"
    mark_done 7
fi
echo ""

# =========================================================================
# Post-install sanity check
# =========================================================================
echo "[check] Verifying your setup is working..."
SANITY_PASSED=true

# Check 1: google-mcp-server binary responds with expected startup output
SANITY_LOG=$(mktemp)
if [ "$GOOGLE_MCP_PATH" = "npx" ]; then
    (npx -y @anthropic-ai/google-mcp-server > "$SANITY_LOG" 2>&1) &
else
    ("$GOOGLE_MCP_PATH" > "$SANITY_LOG" 2>&1) &
fi
SANITY_PID=$!
sleep 3
kill "$SANITY_PID" 2>/dev/null || true
wait "$SANITY_PID" 2>/dev/null || true

if grep -q "registered successfully" "$SANITY_LOG" 2>/dev/null; then
    echo "  ✓ google-mcp-server is responsive"
else
    echo "  ⚠ WARNING: google-mcp-server did not produce expected startup output."
    SANITY_PASSED=false
fi
rm -f "$SANITY_LOG"

# Check 2: google MCP is registered in Claude Code config
export PATH="$HOME/.local/bin:$PATH"
MCP_LIST=$(claude mcp list 2>/dev/null)
if echo "$MCP_LIST" | grep -q "google"; then
    echo "  ✓ Google MCP is registered in Claude Code"
else
    echo "  ⚠ WARNING: Google MCP not found in Claude Code config."
    SANITY_PASSED=false
fi

# Check 3: gmail MCP is registered (needed for sending email)
if echo "$MCP_LIST" | grep -q "gmail"; then
    echo "  ✓ Gmail MCP is registered in Claude Code (send + read)"
else
    echo "  ⚠ WARNING: Gmail MCP not found — you won't be able to send email."
    SANITY_PASSED=false
fi

# Check 4: gmail credentials.json exists (proves auth completed)
if [ -f ~/.gmail-mcp/credentials.json ]; then
    echo "  ✓ Gmail OAuth token found at ~/.gmail-mcp/credentials.json"
else
    echo "  ⚠ WARNING: No Gmail OAuth token found. Re-run the auth step."
    SANITY_PASSED=false
fi

if [ "$SANITY_PASSED" = false ]; then
    echo ""
    echo "  Setup finished, but one or more checks did not pass."
    echo "  This doesn't necessarily mean something is broken — raise your hand"
    echo "  at the event and we'll verify it's working end-to-end."
fi
echo ""

# =========================================================================
# Done!
# =========================================================================
echo "=========================================="
echo "  Setup Complete!"
echo "=========================================="
echo ""
echo "  Your connections:"
export PATH="$HOME/.local/bin:$PATH"
claude mcp list 2>/dev/null || echo "  (restart your terminal to see connections)"
echo ""
echo "  To start your Chief of Staff:"
echo "    cd ~/chief"
echo "    claude"
echo ""
echo "  Try asking:"
echo '    "What'\''s on my calendar this week?"'
echo '    "Show me my latest unread emails"'
echo '    "Draft an email to myself saying hello"'
echo ""
echo "  If something isn't working, raise your hand — we're here to help!"
echo ""

# Clean up checkpoints on successful completion
echo "  (Cleaning up setup checkpoints...)"
rm -rf "$CHECKPOINT_DIR"
echo ""
