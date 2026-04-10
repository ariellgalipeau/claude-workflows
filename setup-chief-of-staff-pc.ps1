# ============================================================================
# Build Your AI Chief of Staff — PC Setup Script
# Launch by Lunch | launchbylunch.co
#
# This script automates the terminal setup after you've completed:
#   1. Claude Pro subscription
#   2. Claude Code installed
#   3. Google Cloud Project created with OAuth credentials
#
# Features:
#   - Resumable: re-run the script and it skips completed steps
#   - Non-admin fallback: works without admin rights (uses AppData instead of C:\Tools)
#
# Usage: Open PowerShell and run:
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
#   irm https://raw.githubusercontent.com/ariellgalipeau/claude-workflows/main/setup-chief-of-staff-pc.ps1 | iex
# ============================================================================

# --- Checkpoint system ---
$CheckpointDir = Join-Path $env:USERPROFILE ".chief-setup"
if (-not (Test-Path $CheckpointDir)) {
    New-Item -Path $CheckpointDir -ItemType Directory -Force | Out-Null
}

function Step-Done($step) {
    return (Test-Path (Join-Path $CheckpointDir "step_$step"))
}

function Mark-Done($step) {
    New-Item -Path (Join-Path $CheckpointDir "step_$step") -ItemType File -Force | Out-Null
}

function Step-Failed($step) {
    Write-Host ""
    Write-Host "  X Step $step failed." -ForegroundColor Red
    Write-Host "  Fix the issue above, then re-run this script." -ForegroundColor Red
    Write-Host "  Completed steps will be skipped automatically." -ForegroundColor Yellow
    exit 1
}

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
$savedIdFile = Join-Path $CheckpointDir "client_id"
$savedSecretFile = Join-Path $CheckpointDir "client_secret"

if ((Step-Done "credentials_saved") -and (Test-Path $savedIdFile) -and (Test-Path $savedSecretFile)) {
    Write-Host "Found saved Google credentials from a previous run."
    $useSaved = Read-Host "Use existing credentials? (y/n)"
    if ($useSaved -eq "y" -or $useSaved -eq "Y") {
        $CLIENT_ID = Get-Content $savedIdFile
        $CLIENT_SECRET = Get-Content $savedSecretFile
        Write-Host "  Using saved credentials" -ForegroundColor Green
    } else {
        $CLIENT_ID = Read-Host "Paste your Google Client ID"
        Write-Host ""
        $CLIENT_SECRET = Read-Host "Paste your Google Client Secret"
    }
} else {
    $CLIENT_ID = Read-Host "Paste your Google Client ID"
    Write-Host ""
    $CLIENT_SECRET = Read-Host "Paste your Google Client Secret"
}
Write-Host ""

if ([string]::IsNullOrWhiteSpace($CLIENT_ID) -or [string]::IsNullOrWhiteSpace($CLIENT_SECRET)) {
    Write-Host "ERROR: Both Client ID and Client Secret are required." -ForegroundColor Red
    Write-Host "Go back to your Google Cloud Console to find them."
    exit 1
}

# Save credentials for resume
$CLIENT_ID | Out-File -FilePath $savedIdFile -NoNewline
$CLIENT_SECRET | Out-File -FilePath $savedSecretFile -NoNewline

# Set for current session
$env:GOOGLE_CLIENT_ID = $CLIENT_ID
$env:GOOGLE_CLIENT_SECRET = $CLIENT_SECRET

Write-Host "Got it. Starting setup..."
Write-Host ""

# --- Check admin status ---
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# =========================================================================
# Step 1: Check Claude Code
# =========================================================================
Write-Host "[1/7] Checking Claude Code..." -ForegroundColor Yellow
if ((Step-Done 1) -and (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Host "  Claude Code is installed (skipped)" -ForegroundColor Green
} elseif (Get-Command claude -ErrorAction SilentlyContinue) {
    Write-Host "  Claude Code is installed" -ForegroundColor Green
    Mark-Done 1
} else {
    Write-Host "  Claude Code not found. Installing..."
    try {
        irm https://claude.ai/install.ps1 | iex
        Write-Host "  Claude Code installed" -ForegroundColor Green
        Write-Host "  NOTE: You may need to close and reopen PowerShell, then run this script again." -ForegroundColor Yellow
        Mark-Done 1
        Write-Host ""
        Read-Host "  Press Enter to continue (or close PowerShell and reopen if claude isn't found)"
    } catch {
        Write-Host "  Claude Code install failed: $_" -ForegroundColor Red
        Step-Failed 1
    }
}
Write-Host ""

# =========================================================================
# Step 2: Download google-mcp-server
# =========================================================================
Write-Host "[2/7] Setting up Google MCP server..." -ForegroundColor Yellow

# Determine install location based on permissions
$toolsDirAdmin = "C:\Tools"
$toolsDirUser = Join-Path $env:LOCALAPPDATA "Programs\google-mcp-server"
$serverPath = $null

if (Step-Done 2) {
    # Recover path from checkpoint
    $savedPath = Join-Path $CheckpointDir "server_path"
    if (Test-Path $savedPath) {
        $serverPath = Get-Content $savedPath
        if (Test-Path $serverPath) {
            Write-Host "  google-mcp-server already set up (skipped)" -ForegroundColor Green
        } else {
            # Path saved but file gone, redo
            Remove-Item (Join-Path $CheckpointDir "step_2") -Force
            Write-Host "  Previous install not found, re-downloading..."
        }
    }
}

if (-not (Step-Done 2)) {
    # Try C:\Tools first if admin, otherwise use AppData
    if ($isAdmin) {
        $toolsDir = $toolsDirAdmin
    } else {
        # Try C:\Tools anyway (might be writable), fall back to AppData
        try {
            if (-not (Test-Path $toolsDirAdmin)) {
                New-Item -Path $toolsDirAdmin -ItemType Directory -Force -ErrorAction Stop | Out-Null
            }
            # Test write access
            $testFile = Join-Path $toolsDirAdmin ".write_test"
            "test" | Out-File -FilePath $testFile -ErrorAction Stop
            Remove-Item $testFile -Force
            $toolsDir = $toolsDirAdmin
        } catch {
            Write-Host "  No admin access to C:\Tools. Using your AppData folder instead." -ForegroundColor Yellow
            $toolsDir = $toolsDirUser
        }
    }

    $serverPath = Join-Path $toolsDir "google-mcp-server.exe"

    if (Test-Path $serverPath) {
        Write-Host "  google-mcp-server.exe already exists at $serverPath" -ForegroundColor Green
    } else {
        Write-Host "  Downloading google-mcp-server..."

        if (-not (Test-Path $toolsDir)) {
            New-Item -Path $toolsDir -ItemType Directory -Force | Out-Null
        }

        try {
            $releaseUrl = "https://api.github.com/repos/ngs/google-mcp-server/releases/latest"
            $release = Invoke-RestMethod -Uri $releaseUrl
            $asset = $release.assets | Where-Object { $_.name -like "*windows-amd64*" } | Select-Object -First 1

            if ($asset) {
                Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $serverPath
                Write-Host "  google-mcp-server.exe downloaded to $serverPath" -ForegroundColor Green
            } else {
                Write-Host "  Could not find Windows download automatically." -ForegroundColor Red
                Write-Host "  Please download manually from: https://github.com/ngs/google-mcp-server/releases" -ForegroundColor Yellow
                Write-Host "  Save as: $serverPath"
                Read-Host "  Press Enter after downloading"
                if (-not (Test-Path $serverPath)) {
                    Step-Failed 2
                }
            }
        } catch {
            Write-Host "  Download failed: $_" -ForegroundColor Red
            Write-Host "  Please download manually from: https://github.com/ngs/google-mcp-server/releases" -ForegroundColor Yellow
            Write-Host "  Save as: $serverPath"
            Read-Host "  Press Enter after downloading"
            if (-not (Test-Path $serverPath)) {
                Step-Failed 2
            }
        }
    }

    # Save path for resume
    $serverPath | Out-File -FilePath (Join-Path $CheckpointDir "server_path") -NoNewline
    Mark-Done 2
}
Write-Host ""

# =========================================================================
# Step 3: Save credentials to environment
# =========================================================================
Write-Host "[3/7] Saving your Google credentials..." -ForegroundColor Yellow
if (Step-Done 3) {
    Write-Host "  Credentials already saved (skipped)" -ForegroundColor Green
} else {
    try {
        [System.Environment]::SetEnvironmentVariable("GOOGLE_CLIENT_ID", $CLIENT_ID, "User")
        [System.Environment]::SetEnvironmentVariable("GOOGLE_CLIENT_SECRET", $CLIENT_SECRET, "User")
        Write-Host "  Credentials saved" -ForegroundColor Green
        Mark-Done 3
    } catch {
        Write-Host "  Failed to save credentials: $_" -ForegroundColor Red
        Step-Failed 3
    }
}
Mark-Done "credentials_saved"
Write-Host ""

# =========================================================================
# Step 4: Authenticate Google (Calendar + Drive)
# =========================================================================
Write-Host "[4/7] Authenticating with Google for Calendar + Drive..." -ForegroundColor Yellow
if (Step-Done 4) {
    Write-Host "  Google auth already completed (skipped)" -ForegroundColor Green
    $reauth = Read-Host "  Re-run authentication anyway? (y/n)"
    if ($reauth -eq "y" -or $reauth -eq "Y") {
        Write-Host ""
        Write-Host "  Your browser will open. Sign in with your Google account." -ForegroundColor White
        Write-Host ""
        Write-Host "  IMPORTANT: You may see a warning that says 'Google hasn't verified this app'." -ForegroundColor Yellow
        Write-Host "  Click 'Advanced' at the bottom left, then click 'Go to [app name] (unsafe)'." -ForegroundColor Yellow
        Write-Host "  This is normal for your own Google Cloud project. Click 'Continue' to allow access." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  After you see the success message, come back here and press Ctrl + C."
        Write-Host ""
        Read-Host "  Press Enter to open the browser"
        try { & $serverPath } catch { }
        Write-Host ""
        Write-Host "  Google Calendar + Drive re-authenticated" -ForegroundColor Green
    }
} else {
    Write-Host ""
    Write-Host "  Your browser will open. Sign in with your Google account." -ForegroundColor White
    Write-Host ""
    Write-Host "  IMPORTANT: You may see a warning that says 'Google hasn't verified this app'." -ForegroundColor Yellow
    Write-Host "  Click 'Advanced' at the bottom left, then click 'Go to [app name] (unsafe)'." -ForegroundColor Yellow
    Write-Host "  This is normal for your own Google Cloud project. Click 'Continue' to allow access." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  After you see the success message, come back here and press Ctrl + C."
    Write-Host ""
    Read-Host "  Press Enter to open the browser"
    try { & $serverPath } catch { }
    Write-Host ""
    Write-Host "  Google Calendar + Drive authenticated" -ForegroundColor Green
    Mark-Done 4
}
Write-Host ""

# =========================================================================
# Step 5: Add MCP servers to Claude Code
# =========================================================================
Write-Host "[5/7] Adding Google connections to Claude Code..." -ForegroundColor Yellow
if (Step-Done 5) {
    Write-Host "  MCP connections already added (skipped)" -ForegroundColor Green
} else {
    $claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
    if (-not $claudeCmd) {
        Write-Host "  Claude Code not found on PATH." -ForegroundColor Red
        Write-Host "  Please close PowerShell, reopen it, and re-run this script." -ForegroundColor Yellow
        Step-Failed 5
    }

    # Remove old entries if they exist
    try { claude mcp remove google 2>$null } catch {}
    try { claude mcp remove gmail 2>$null } catch {}

    # Add Calendar + Drive
    try {
        claude mcp add --scope user google $serverPath
        Write-Host "  Calendar + Drive connection added" -ForegroundColor Green
    } catch {
        Write-Host "  Failed to add Google MCP: $_" -ForegroundColor Red
        Step-Failed 5
    }

    # Add Gmail
    try {
        claude mcp add --scope user gmail -- npx -y @gongrzhe/server-gmail-autoauth-mcp
        Write-Host "  Gmail connection added" -ForegroundColor Green
    } catch {
        Write-Host "  Failed to add Gmail MCP: $_" -ForegroundColor Red
        Step-Failed 5
    }

    Mark-Done 5
}
Write-Host ""

# =========================================================================
# Step 6: Authenticate Gmail
# =========================================================================
Write-Host "[6/7] Setting up Gmail authentication..." -ForegroundColor Yellow
if (Step-Done 6) {
    Write-Host "  Gmail auth already completed (skipped)" -ForegroundColor Green
    $reauthGmail = Read-Host "  Re-run Gmail authentication anyway? (y/n)"
    if ($reauthGmail -eq "y" -or $reauthGmail -eq "Y") {
        Write-Host ""
        Write-Host "  Starting Claude Code. Type: 'Check my latest emails'" -ForegroundColor White
        Write-Host "  Your browser will open. Sign in and click Allow." -ForegroundColor White
        Write-Host ""
        Write-Host "  IMPORTANT: You may see a warning that says 'Google hasn't verified this app'." -ForegroundColor Yellow
        Write-Host "  Click 'Advanced' at the bottom left, then click 'Go to [app name] (unsafe)'." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Then type /exit to continue."
        Write-Host ""
        Read-Host "  Press Enter to start Claude Code"
        claude
        Write-Host ""
        Write-Host "  Gmail re-authenticated" -ForegroundColor Green
    }
} else {
    Write-Host ""
    Write-Host "  We need your Google credentials JSON file."
    Write-Host "  (This is the file you downloaded from Google Cloud Console. It starts with 'client_secret_')"
    Write-Host ""

    $gmailCredDir = Join-Path $env:USERPROFILE ".gmail-mcp"
    $gmailCredFile = Join-Path $gmailCredDir "gcp-oauth.keys.json"
    $credPath = $null

    if (Test-Path $gmailCredFile) {
        Write-Host "  Found existing Gmail credentials file." -ForegroundColor Green
        $useExisting = Read-Host "  Use existing credentials? (y/n)"
        if ($useExisting -eq "y" -or $useExisting -eq "Y") {
            $credPath = "SKIP"
        }
    }

    # Auto-search Downloads and Desktop if we need a file
    if (-not $credPath) {
        $foundFile = $null
        foreach ($searchDir in @(
            (Join-Path $env:USERPROFILE "Downloads"),
            (Join-Path $env:USERPROFILE "Desktop")
        )) {
            if (Test-Path $searchDir) {
                $match = Get-ChildItem -Path $searchDir -Filter "client_secret_*.json" -File -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($match) {
                    $foundFile = $match.FullName
                    break
                }
            }
        }

        if ($foundFile) {
            Write-Host "  Found credentials file:" -ForegroundColor Green
            Write-Host "    $(Split-Path $foundFile -Leaf)"
            Write-Host ""
            $useFound = Read-Host "  Use this file? (y/n)"
            if ($useFound -eq "y" -or $useFound -eq "Y") {
                $credPath = $foundFile
            }
        }

        # If still no file, ask for path
        if (-not $credPath) {
            Write-Host ""
            Write-Host "  Paste the full path to your client_secret JSON file:"
            Write-Host "  (Right-click the file in File Explorer, click 'Copy as path', then right-click here to paste)"
            $credPath = Read-Host "  "
            $credPath = $credPath.Trim('"').Trim("'").Trim()
        }
    }

    # Copy the file into place
    if ($credPath -ne "SKIP") {
        if ([string]::IsNullOrWhiteSpace($credPath)) {
            Write-Host "  WARNING: No credentials file provided. Gmail auth will need to be set up manually." -ForegroundColor Yellow
        } else {
            if (-not (Test-Path $gmailCredDir)) {
                New-Item -Path $gmailCredDir -ItemType Directory -Force | Out-Null
            }
            try {
                Copy-Item -Path $credPath -Destination $gmailCredFile -Force
                Write-Host "  Credentials file saved" -ForegroundColor Green
            } catch {
                Write-Host "  Could not copy credentials file. Check the path and try again." -ForegroundColor Red
                Step-Failed 6
            }
        }
    }

    if (Test-Path $gmailCredFile) {
        Write-Host ""
        Write-Host "  Starting Claude Code. Type: 'Check my latest emails'" -ForegroundColor White
        Write-Host "  Your browser will open. Sign in and click Allow." -ForegroundColor White
        Write-Host ""
        Write-Host "  IMPORTANT: You may see a warning that says 'Google hasn't verified this app'." -ForegroundColor Yellow
        Write-Host "  Click 'Advanced' at the bottom left, then click 'Go to [app name] (unsafe)'." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Then type /exit to continue."
        Write-Host ""
        Read-Host "  Press Enter to start Claude Code"
        claude
        Write-Host ""
        Write-Host "  Gmail authenticated" -ForegroundColor Green
    } else {
        Write-Host "  Skipping Gmail auth (no credentials file). You can set this up later." -ForegroundColor Yellow
    }
    Mark-Done 6
}
Write-Host ""

# =========================================================================
# Step 7: Create folder structure
# =========================================================================
Write-Host "[7/7] Creating your Chief of Staff folder structure..." -ForegroundColor Yellow
if (Step-Done 7) {
    Write-Host "  Folder structure already created (skipped)" -ForegroundColor Green
} else {
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
        Write-Host "  CLAUDE.md found" -ForegroundColor Green
    } else {
        Write-Host "  NOTE: No CLAUDE.md found in $chiefPath — make sure to add it before the event" -ForegroundColor Yellow
    }

    Write-Host "  Folder structure created" -ForegroundColor Green
    Mark-Done 7
}
Write-Host ""

# =========================================================================
# Done!
# =========================================================================
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Setup Complete!" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Your connections:"
try { claude mcp list } catch { Write-Host "  (restart PowerShell to see connections)" }
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

# Clean up checkpoints on successful completion
Write-Host "  (Cleaning up setup checkpoints...)"
Remove-Item -Path $CheckpointDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ""
