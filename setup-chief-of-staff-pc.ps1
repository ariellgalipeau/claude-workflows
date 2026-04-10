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
Write-Host "[1/6] Checking Claude Code..." -ForegroundColor Yellow
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
Write-Host "[2/6] Setting up Google MCP server..." -ForegroundColor Yellow

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
Write-Host "[3/6] Saving your Google credentials..." -ForegroundColor Yellow
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
# Step 4: Authenticate Google (Calendar, Drive, Gmail, Slides)
# =========================================================================
Write-Host "[4/6] Authenticating with Google (Calendar, Drive, Gmail, Slides)..." -ForegroundColor Yellow
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
        Write-Host "  Google services re-authenticated (Calendar, Drive, Gmail, Slides)" -ForegroundColor Green
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
    Write-Host "  Google services authenticated (Calendar, Drive, Gmail, Slides)" -ForegroundColor Green
    Mark-Done 4
}
Write-Host ""

# =========================================================================
# Step 5: Add MCP server to Claude Code
# =========================================================================
Write-Host "[5/6] Adding Google connection to Claude Code..." -ForegroundColor Yellow
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

    # Add Google (covers Calendar, Drive, Gmail, Slides with one auth)
    try {
        claude mcp add --scope user google $serverPath
        Write-Host "  Google connection added (Calendar, Drive, Gmail, Slides)" -ForegroundColor Green
    } catch {
        Write-Host "  Failed to add Google MCP: $_" -ForegroundColor Red
        Step-Failed 5
    }

    Mark-Done 5
}
Write-Host ""

# =========================================================================
# Step 6: Create folder structure
# =========================================================================
Write-Host "[6/6] Creating your Chief of Staff folder structure..." -ForegroundColor Yellow
if (Step-Done 6) {
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
    Mark-Done 6
}
Write-Host ""

# =========================================================================
# Post-install sanity check
# =========================================================================
Write-Host "[check] Verifying your setup is working..." -ForegroundColor Yellow

# Check 1: google-mcp-server binary responds with expected startup output
$sanityPassed = $true
try {
    $job = Start-Job -ScriptBlock {
        param($path)
        & $path 2>&1
    } -ArgumentList $serverPath
    Start-Sleep -Seconds 3
    Stop-Job $job -ErrorAction SilentlyContinue
    $serverOutput = Receive-Job $job 2>&1 | Out-String
    Remove-Job $job -Force -ErrorAction SilentlyContinue

    if ($serverOutput -match "registered successfully") {
        Write-Host "  google-mcp-server is responsive" -ForegroundColor Green
    } else {
        Write-Host "  WARNING: google-mcp-server did not produce expected startup output." -ForegroundColor Yellow
        $sanityPassed = $false
    }
} catch {
    Write-Host "  WARNING: Could not verify google-mcp-server: $_" -ForegroundColor Yellow
    $sanityPassed = $false
}

# Check 2: google MCP is registered in Claude Code config
try {
    $mcpList = (claude mcp list 2>$null) | Out-String
    if ($mcpList -match "google") {
        Write-Host "  Google MCP is registered in Claude Code" -ForegroundColor Green
    } else {
        Write-Host "  WARNING: Google MCP not found in Claude Code config." -ForegroundColor Yellow
        $sanityPassed = $false
    }
} catch {
    Write-Host "  Could not check Claude Code config — restart PowerShell if needed." -ForegroundColor Yellow
    $sanityPassed = $false
}

if (-not $sanityPassed) {
    Write-Host ""
    Write-Host "  Setup finished, but one or more checks did not pass." -ForegroundColor Yellow
    Write-Host "  This doesn't necessarily mean something is broken — raise your hand" -ForegroundColor Yellow
    Write-Host "  at the event and we'll verify it's working end-to-end." -ForegroundColor Yellow
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
