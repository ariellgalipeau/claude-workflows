# ============================================================================
# Build Your AI Chief of Staff — PC Setup Script
# Launch by Lunch | launchbylunch.co
#
# This script automates the terminal setup after you've completed:
#   1. Claude Pro subscription
#   2. Claude Code installed
#   3. Google Cloud Project created with OAuth credentials
#
# Usage: Open PowerShell and run:
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
#   .\setup-chief-of-staff-pc.ps1
# ============================================================================

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Build Your AI Chief of Staff - PC" -ForegroundColor Cyan
Write-Host "  Launch by Lunch" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This script will set up your Google connections and folder structure."
Write-Host "You'll need your Google OAuth Client ID and Client Secret ready."
Write-Host "(You got these from your Google Cloud Console in the previous step.)"
Write-Host ""

# --- Collect credentials ---
$CLIENT_ID = Read-Host "Paste your Google Client ID"
Write-Host ""
$CLIENT_SECRET = Read-Host "Paste your Google Client Secret"
Write-Host ""

if ([string]::IsNullOrWhiteSpace($CLIENT_ID) -or [string]::IsNullOrWhiteSpace($CLIENT_SECRET)) {
    Write-Host "ERROR: Both Client ID and Client Secret are required." -ForegroundColor Red
    Write-Host "Go back to your Google Cloud Console to find them."
    exit 1
}

Write-Host "Got it. Starting setup..."
Write-Host ""

# --- Step 1: Check Claude Code ---
Write-Host "[1/7] Checking Claude Code..." -ForegroundColor Yellow
$claudeCheck = Get-Command claude -ErrorAction SilentlyContinue
if ($claudeCheck) {
    Write-Host "  ✓ Claude Code is installed" -ForegroundColor Green
} else {
    Write-Host "  Claude Code not found. Installing..."
    irm https://claude.ai/install.ps1 | iex
    Write-Host "  ✓ Claude Code installed" -ForegroundColor Green
    Write-Host "  NOTE: You may need to close and reopen PowerShell, then run this script again."
    Write-Host ""
    Read-Host "  Press Enter to continue (or close PowerShell and reopen if claude isn't found)"
}
Write-Host ""

# --- Step 2: Download google-mcp-server ---
Write-Host "[2/7] Setting up Google MCP server..." -ForegroundColor Yellow

$toolsDir = "C:\Tools"
$serverPath = "$toolsDir\google-mcp-server.exe"

if (Test-Path $serverPath) {
    Write-Host "  ✓ google-mcp-server.exe already exists at $serverPath" -ForegroundColor Green
} else {
    Write-Host "  Downloading google-mcp-server..."

    # Create C:\Tools if needed
    if (-not (Test-Path $toolsDir)) {
        New-Item -Path $toolsDir -ItemType Directory -Force | Out-Null
    }

    # Get the latest release download URL
    $releaseUrl = "https://api.github.com/repos/ngs/google-mcp-server/releases/latest"
    $release = Invoke-RestMethod -Uri $releaseUrl
    $asset = $release.assets | Where-Object { $_.name -like "*windows-amd64*" } | Select-Object -First 1

    if ($asset) {
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $serverPath
        Write-Host "  ✓ google-mcp-server.exe downloaded to $serverPath" -ForegroundColor Green
    } else {
        Write-Host "  ERROR: Could not find Windows download. Please download manually from:" -ForegroundColor Red
        Write-Host "  https://github.com/ngs/google-mcp-server/releases"
        Write-Host "  Save as: $serverPath"
        Read-Host "  Press Enter after downloading"
    }
}
Write-Host ""

# --- Step 3: Save credentials ---
Write-Host "[3/7] Saving your Google credentials..." -ForegroundColor Yellow

[System.Environment]::SetEnvironmentVariable("GOOGLE_CLIENT_ID", $CLIENT_ID, "User")
[System.Environment]::SetEnvironmentVariable("GOOGLE_CLIENT_SECRET", $CLIENT_SECRET, "User")

# Also set for current session
$env:GOOGLE_CLIENT_ID = $CLIENT_ID
$env:GOOGLE_CLIENT_SECRET = $CLIENT_SECRET

Write-Host "  ✓ Credentials saved" -ForegroundColor Green
Write-Host ""

# --- Step 4: Authenticate Google (Calendar + Drive) ---
Write-Host "[4/7] Authenticating with Google for Calendar + Drive..." -ForegroundColor Yellow
Write-Host ""
Write-Host "  Your browser will open. Sign in with your Google account and click Allow."
Write-Host "  After you see the success message, come back here and press Ctrl + C."
Write-Host ""
Read-Host "  Press Enter to open the browser"

try {
    & $serverPath
} catch {
    # User pressed Ctrl+C, that's expected
}

Write-Host ""
Write-Host "  ✓ Google Calendar + Drive authenticated" -ForegroundColor Green
Write-Host ""

# --- Step 5: Add MCP servers to Claude Code ---
Write-Host "[5/7] Adding Google connections to Claude Code..." -ForegroundColor Yellow

# Remove old entries if they exist
try { claude mcp remove google 2>$null } catch {}
try { claude mcp remove gmail 2>$null } catch {}

# Add Calendar + Drive
claude mcp add --scope user google $serverPath
Write-Host "  ✓ Calendar + Drive connection added" -ForegroundColor Green

# Add Gmail
claude mcp add --scope user gmail -- npx -y @gongrzhe/server-gmail-autoauth-mcp
Write-Host "  ✓ Gmail connection added" -ForegroundColor Green
Write-Host ""

# --- Step 6: Authenticate Gmail ---
Write-Host "[6/7] Setting up Gmail authentication..." -ForegroundColor Yellow
Write-Host ""
Write-Host "  Starting Claude Code. Type: 'Check my latest emails'"
Write-Host "  Your browser will open — sign in and click Allow."
Write-Host "  Then type /exit to continue."
Write-Host ""
Read-Host "  Press Enter to start Claude Code"

claude

Write-Host ""
Write-Host "  ✓ Gmail authenticated" -ForegroundColor Green
Write-Host ""

# --- Step 7: Create folder structure ---
Write-Host "[7/7] Creating your Chief of Staff folder structure..." -ForegroundColor Yellow

$chiefPath = Join-Path $env:USERPROFILE "chief"

$folders = @(
    "$chiefPath\about-me",
    "$chiefPath\memory\conversations",
    "$chiefPath\Tools",
    "$chiefPath\Notes"
)

foreach ($folder in $folders) {
    if (-not (Test-Path $folder)) {
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
    }
}

# Seed memory files
$memoryFile = "$chiefPath\memory\memory.md"
$contextFile = "$chiefPath\memory\context.txt"

if (-not (Test-Path $memoryFile)) {
    New-Item -Path $memoryFile -ItemType File -Force | Out-Null
}
if (-not (Test-Path $contextFile)) {
    New-Item -Path $contextFile -ItemType File -Force | Out-Null
}

# Check for CLAUDE.md
if (Test-Path "$chiefPath\CLAUDE.md") {
    Write-Host "  ✓ CLAUDE.md found" -ForegroundColor Green
} else {
    Write-Host "  NOTE: No CLAUDE.md found in $chiefPath — make sure to add it before the event" -ForegroundColor Yellow
}

Write-Host "  ✓ Folder structure created" -ForegroundColor Green
Write-Host ""

# --- Done! ---
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Setup Complete!" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Your connections:"
claude mcp list
Write-Host ""
Write-Host "  To start your Chief of Staff:"
Write-Host "    cd ~\chief"
Write-Host "    claude"
Write-Host ""
Write-Host "  Try asking:"
Write-Host '    "What''s on my calendar this week?"'
Write-Host '    "Show me my latest unread emails"'
Write-Host ""
Write-Host "  If something isn't working, raise your hand — we're here to help!"
Write-Host ""
