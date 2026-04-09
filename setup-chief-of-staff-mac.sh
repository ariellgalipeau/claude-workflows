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
# Usage: bash setup-chief-of-staff-mac.sh
# ============================================================================

set -e

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

# --- Collect credentials ---
read -p "Paste your Google Client ID: " CLIENT_ID
echo ""
read -p "Paste your Google Client Secret: " CLIENT_SECRET
echo ""

if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ]; then
    echo "ERROR: Both Client ID and Client Secret are required."
    echo "Go back to your Google Cloud Console to find them."
    exit 1
fi

echo "Got it. Starting setup..."
echo ""

# --- Step 1: Check Claude Code ---
echo "[1/8] Checking Claude Code..."
if command -v claude &> /dev/null; then
    echo "  ✓ Claude Code is installed"
else
    echo "  Claude Code not found. Installing..."
    curl -fsSL https://claude.ai/install.sh | bash
    export PATH="$HOME/.local/bin:$PATH"
    # Add to .zshrc if not already there
    if ! grep -q '.local/bin' ~/.zshrc 2>/dev/null; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
    fi
    echo "  ✓ Claude Code installed"
fi
echo ""

# --- Step 2: Install Homebrew ---
echo "[2/8] Checking Homebrew..."
if command -v brew &> /dev/null; then
    echo "  ✓ Homebrew is installed"
else
    echo "  Homebrew not found. Installing (this may take a few minutes)..."
    echo "  You may be asked for your Mac password."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Add Homebrew to PATH for Apple Silicon
    if [ -f /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
        if ! grep -q 'homebrew' ~/.zshrc 2>/dev/null; then
            echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zshrc
        fi
    fi
    echo "  ✓ Homebrew installed"
fi
echo ""

# --- Step 3: Install google-mcp-server ---
echo "[3/8] Installing Google MCP server..."
brew tap ngs/tap 2>/dev/null || true
if brew list ngs/tap/google-mcp-server &>/dev/null; then
    echo "  ✓ google-mcp-server already installed"
else
    brew install google-mcp-server
    echo "  ✓ google-mcp-server installed"
fi
echo ""

# --- Step 4: Save credentials ---
echo "[4/8] Saving your Google credentials..."

# Remove any old entries first
if [ -f ~/.zshrc ]; then
    sed -i '' '/GOOGLE_CLIENT_ID/d' ~/.zshrc 2>/dev/null || true
    sed -i '' '/GOOGLE_CLIENT_SECRET/d' ~/.zshrc 2>/dev/null || true
fi

echo "export GOOGLE_CLIENT_ID=\"$CLIENT_ID\"" >> ~/.zshrc
echo "export GOOGLE_CLIENT_SECRET=\"$CLIENT_SECRET\"" >> ~/.zshrc

# Load them for this session
export GOOGLE_CLIENT_ID="$CLIENT_ID"
export GOOGLE_CLIENT_SECRET="$CLIENT_SECRET"

echo "  ✓ Credentials saved"
echo ""

# --- Step 5: Authenticate Google (Calendar + Drive) ---
echo "[5/8] Authenticating with Google for Calendar + Drive..."
echo ""
echo "  Your browser will open. Sign in with your Google account and click Allow."
echo "  After you see the success message, come back here and press Control + C."
echo ""
read -p "  Press Enter to open the browser..." _dummy

# Determine the correct path
if [ -f /opt/homebrew/bin/google-mcp-server ]; then
    GOOGLE_MCP_PATH="/opt/homebrew/bin/google-mcp-server"
elif [ -f /usr/local/bin/google-mcp-server ]; then
    GOOGLE_MCP_PATH="/usr/local/bin/google-mcp-server"
else
    GOOGLE_MCP_PATH="google-mcp-server"
fi

# Run auth — user will Control+C after approving
$GOOGLE_MCP_PATH || true

echo ""
echo "  ✓ Google Calendar + Drive authenticated"
echo ""

# --- Step 6: Add MCP servers to Claude Code ---
echo "[6/8] Adding Google connections to Claude Code..."

# Remove old entries if they exist (clean slate)
claude mcp remove google 2>/dev/null || true
claude mcp remove gmail 2>/dev/null || true

# Add Calendar + Drive
claude mcp add --scope user google "$GOOGLE_MCP_PATH"
echo "  ✓ Calendar + Drive connection added"

# Add Gmail
claude mcp add --scope user gmail -- npx -y @gongrzhe/server-gmail-autoauth-mcp
echo "  ✓ Gmail connection added"
echo ""

# --- Step 7: Set up Gmail authentication ---
echo "[7/8] Setting up Gmail authentication..."
echo ""
echo "  We need your Google credentials JSON file."
echo "  (This is the file you downloaded from Google Cloud Console — it starts with 'client_secret_')"
echo ""

# Check if credentials file already exists
if [ -f ~/.gmail-mcp/gcp-oauth.keys.json ]; then
    echo "  Found existing Gmail credentials file."
    read -p "  Use existing credentials? (y/n): " USE_EXISTING
    if [ "$USE_EXISTING" != "y" ] && [ "$USE_EXISTING" != "Y" ]; then
        read -p "  Drag and drop the client_secret JSON file here (or type the full path): " CRED_PATH
        CRED_PATH=$(echo "$CRED_PATH" | sed "s/^'//" | sed "s/'$//" | xargs)
        mkdir -p ~/.gmail-mcp
        cp "$CRED_PATH" ~/.gmail-mcp/gcp-oauth.keys.json
    fi
else
    read -p "  Drag and drop the client_secret JSON file here (or type the full path): " CRED_PATH
    CRED_PATH=$(echo "$CRED_PATH" | sed "s/^'//" | sed "s/'$//" | xargs)
    if [ -z "$CRED_PATH" ]; then
        echo "  WARNING: No credentials file provided. Gmail auth will need to be set up manually."
        echo "  You can run this later: npx @gongrzhe/server-gmail-autoauth-mcp auth"
    else
        mkdir -p ~/.gmail-mcp
        cp "$CRED_PATH" ~/.gmail-mcp/gcp-oauth.keys.json
        echo "  ✓ Credentials file saved"
    fi
fi

if [ -f ~/.gmail-mcp/gcp-oauth.keys.json ]; then
    echo ""
    echo "  Your browser will open again. Sign in and click Allow for Gmail access."
    echo ""
    read -p "  Press Enter to open the browser..." _dummy
    npx @gongrzhe/server-gmail-autoauth-mcp auth || true
    echo ""
    echo "  ✓ Gmail authenticated"
fi
echo ""

# --- Step 8: Create folder structure ---
echo "[8/8] Creating your Chief of Staff folder structure..."

mkdir -p ~/chief/about-me
mkdir -p ~/chief/memory/conversations
mkdir -p ~/chief/Tools
mkdir -p ~/chief/Notes
touch ~/chief/memory/memory.md
touch ~/chief/memory/context.txt

# Check for CLAUDE.md
if [ -f ~/chief/CLAUDE.md ]; then
    echo "  ✓ CLAUDE.md found"
else
    echo "  NOTE: No CLAUDE.md found in ~/chief/ — make sure to add it before the event"
fi

echo "  ✓ Folder structure created"
echo ""

# --- Done! ---
echo "=========================================="
echo "  Setup Complete!"
echo "=========================================="
echo ""
echo "  Your connections:"
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
