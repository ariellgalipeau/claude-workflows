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
# Step 5: Authenticate Google (Calendar + Drive)
# =========================================================================
echo "[5/8] Authenticating with Google for Calendar + Drive..."
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
echo "[6/8] Adding Google connections to Claude Code..."
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

    # Add Calendar + Drive
    if [ "$GOOGLE_MCP_PATH" = "npx" ]; then
        claude mcp add --scope user google -- npx -y @anthropic-ai/google-mcp-server
    else
        claude mcp add --scope user google "$GOOGLE_MCP_PATH"
    fi
    echo "  ✓ Calendar + Drive connection added"

    # Add Gmail
    claude mcp add --scope user gmail -- npx -y @gongrzhe/server-gmail-autoauth-mcp
    echo "  ✓ Gmail connection added"
    mark_done 6
fi
echo ""

# =========================================================================
# Step 7: Gmail authentication
# =========================================================================
echo "[7/8] Setting up Gmail authentication..."
if step_done 7; then
    echo "  ✓ Gmail auth already completed (skipped)"
    read -p "  Re-run Gmail authentication anyway? (y/n): " REAUTH_GMAIL
    if [ "$REAUTH_GMAIL" = "y" ] || [ "$REAUTH_GMAIL" = "Y" ]; then
        echo ""
        echo "  Your browser will open again. Sign in and click Allow for Gmail access."
        echo ""
        echo "  ⚠ IMPORTANT: You may see a warning that says 'Google hasn't verified this app'."
        echo "  Click 'Advanced' at the bottom left, then click 'Go to [app name] (unsafe)'."
        echo ""
        read -p "  Press Enter to open the browser..." _dummy
        npx @gongrzhe/server-gmail-autoauth-mcp auth || true
        echo ""
        echo "  ✓ Gmail re-authenticated"
    fi
else
    echo ""
    echo "  We need your Google credentials JSON file."
    echo "  (This is the file you downloaded from Google Cloud Console. It starts with 'client_secret_')"
    echo ""

    if [ -f ~/.gmail-mcp/gcp-oauth.keys.json ]; then
        echo "  Found existing Gmail credentials file."
        read -p "  Use existing credentials? (y/n): " USE_EXISTING
        if [ "$USE_EXISTING" != "y" ] && [ "$USE_EXISTING" != "Y" ]; then
            read -p "  Drag and drop the client_secret JSON file here (or type the full path): " CRED_PATH
            CRED_PATH=$(echo "$CRED_PATH" | sed "s/^'//" | sed "s/'$//" | xargs)
            mkdir -p ~/.gmail-mcp
            if cp "$CRED_PATH" ~/.gmail-mcp/gcp-oauth.keys.json; then
                echo "  ✓ Credentials file saved"
            else
                echo "  ✗ Could not copy credentials file. Check the path and try again."
                step_failed 7
            fi
        fi
    else
        read -p "  Drag and drop the client_secret JSON file here (or type the full path): " CRED_PATH
        CRED_PATH=$(echo "$CRED_PATH" | sed "s/^'//" | sed "s/'$//" | xargs)
        if [ -z "$CRED_PATH" ]; then
            echo "  WARNING: No credentials file provided. Gmail auth will need to be set up manually."
            echo "  You can run this later: npx @gongrzhe/server-gmail-autoauth-mcp auth"
        else
            mkdir -p ~/.gmail-mcp
            if cp "$CRED_PATH" ~/.gmail-mcp/gcp-oauth.keys.json; then
                echo "  ✓ Credentials file saved"
            else
                echo "  ✗ Could not copy credentials file. Check the path and try again."
                step_failed 7
            fi
        fi
    fi

    if [ -f ~/.gmail-mcp/gcp-oauth.keys.json ]; then
        echo ""
        echo "  Your browser will open again. Sign in and click Allow for Gmail access."
        echo ""
        echo "  ⚠ IMPORTANT: You may see a warning that says 'Google hasn't verified this app'."
        echo "  Click 'Advanced' at the bottom left, then click 'Go to [app name] (unsafe)'."
        echo ""
        read -p "  Press Enter to open the browser..." _dummy
        npx @gongrzhe/server-gmail-autoauth-mcp auth || true
        echo ""
        echo "  ✓ Gmail authenticated"
    fi
    mark_done 7
fi
echo ""

# =========================================================================
# Step 8: Folder structure
# =========================================================================
echo "[8/8] Creating your Chief of Staff folder structure..."
if step_done 8; then
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
    mark_done 8
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
echo ""
echo "  If something isn't working, raise your hand — we're here to help!"
echo ""

# Clean up checkpoints on successful completion
echo "  (Cleaning up setup checkpoints...)"
rm -rf "$CHECKPOINT_DIR"
echo ""
