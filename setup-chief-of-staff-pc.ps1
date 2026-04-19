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

# --- Strict error handling for native commands ---
# Without these, try/catch silently swallows external command failures (e.g., npx, claude)
# and the script reports success even when steps fail. PS 7.3+ supports both settings.
$ErrorActionPreference = "Stop"
if ($PSVersionTable.PSVersion.Major -ge 7 -and $PSVersionTable.PSVersion.Minor -ge 3) {
    $PSNativeCommandUseErrorActionPreference = $true
}

# --- Force TLS 1.2 for all web requests ---
# Windows PowerShell 5.1 defaults to TLS 1.0/1.1, which Google (and most modern APIs)
# rejected years ago. Without this, Invoke-RestMethod calls to oauth2.googleapis.com
# fail with "Could not create SSL/TLS secure channel" on unpatched Windows 10.
# No-op on PS 7+, which defaults to TLS 1.2+.
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {
    # Old .NET may not have Tls12 enum member; fall back to common value
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072
}

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

# --- Helpers: find claude.exe broadly, persist PATH, locate OAuth JSON ---

function Find-ClaudeExe {
    # Fast path: already on PATH in current session
    $cmd = Get-Command claude -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    # Known install locations across different Windows install patterns
    $knownPaths = @(
        "$env:USERPROFILE\.local\bin\claude.exe",
        "$env:LOCALAPPDATA\Programs\claude\claude.exe",
        "$env:LOCALAPPDATA\Programs\anthropic\claude\claude.exe",
        "$env:APPDATA\npm\claude.cmd",
        "$env:ProgramFiles\Claude\claude.exe",
        "${env:ProgramFiles(x86)}\Claude\claude.exe",
        "$env:USERPROFILE\AppData\Roaming\claude\claude.exe"
    )
    foreach ($p in $knownPaths) {
        if (Test-Path $p) { return $p }
    }

    # Last resort: targeted deep scan (user folders only, depth-limited)
    $found = Get-ChildItem -Path $env:USERPROFILE, $env:LOCALAPPDATA, $env:APPDATA `
        -Recurse -Filter "claude.exe" -Depth 5 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { return $found.FullName }
    return $null
}

function Register-ClaudeInPath {
    param([string]$claudeExe)
    $claudeDir = Split-Path $claudeExe -Parent

    # Permanent User PATH (survives new PowerShell windows and reboots)
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -notlike "*$claudeDir*") {
        [Environment]::SetEnvironmentVariable("Path", "$userPath;$claudeDir", "User")
        Write-Host "  Added $claudeDir to permanent User PATH" -ForegroundColor Green
    }

    # Current session PATH so the rest of this script can find claude
    if ($env:Path -notlike "*$claudeDir*") {
        $env:Path = "$env:Path;$claudeDir"
    }
}

function Find-OAuthJson {
    param([string[]]$searchDirs = @("$env:USERPROFILE\Downloads", "$env:USERPROFILE\Desktop"))

    foreach ($dir in $searchDirs) {
        if (-not (Test-Path $dir)) { continue }

        # Pass 1: Google's default filename pattern
        $byPattern = Get-ChildItem -Path "$dir\client_secret_*.json" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($byPattern) { return $byPattern }

        # Pass 2: content-sniff any .json (catches renamed files)
        $allJson = Get-ChildItem -Path "$dir\*.json" -ErrorAction SilentlyContinue
        foreach ($f in $allJson) {
            try {
                $c = Get-Content $f.FullName -Raw | ConvertFrom-Json
                if ($c.installed -and $c.installed.client_id -and $c.installed.client_secret) {
                    return $f
                }
            } catch { continue }
        }
    }
    return $null
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

$claudeExe = Find-ClaudeExe
if ($claudeExe) {
    if (Step-Done 1) {
        Write-Host "  Claude Code is installed at $claudeExe (skipped)" -ForegroundColor Green
    } else {
        Write-Host "  Claude Code is installed at $claudeExe" -ForegroundColor Green
        Mark-Done 1
    }
    Register-ClaudeInPath $claudeExe
} else {
    Write-Host "  Claude Code not found. Installing..."
    try {
        irm https://claude.ai/install.ps1 | iex
    } catch {
        Write-Host "  Claude Code install failed: $_" -ForegroundColor Red
        Step-Failed 1
    }

    # After install, search broadly for the binary (installer doesn't always patch session PATH)
    $claudeExe = Find-ClaudeExe
    if (-not $claudeExe) {
        Write-Host "  Installed, but can't locate claude.exe in any known location." -ForegroundColor Red
        Write-Host "  Close PowerShell, reopen, and re-run this script." -ForegroundColor Yellow
        Step-Failed 1
    }

    Register-ClaudeInPath $claudeExe
    Write-Host "  Claude Code installed at $claudeExe" -ForegroundColor Green
    Mark-Done 1
}
Write-Host ""

# =========================================================================
# Step 2: Download google-mcp-server
# =========================================================================
Write-Host "[2/7] Setting up Google MCP server..." -ForegroundColor Yellow

# Determine install location — matches the PC setup guide ($env:USERPROFILE\Tools)
$toolsDir = Join-Path $env:USERPROFILE "Tools"
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
# Step 4: Authenticate Google (Calendar, Drive, Gmail, Slides)
# =========================================================================
Write-Host "[4/7] Authenticating with Google (Calendar, Drive, Slides)..." -ForegroundColor Yellow
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
Write-Host "[5/7] Adding Google connection to Claude Code..." -ForegroundColor Yellow
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
        claude mcp add --scope user google "$serverPath"
        Write-Host "  Google connection added (Calendar, Drive, Gmail, Slides)" -ForegroundColor Green
    } catch {
        Write-Host "  Failed to add Google MCP: $_" -ForegroundColor Red
        Step-Failed 5
    }

    Mark-Done 5
}
Write-Host ""

# =========================================================================
# Step 6: Gmail (send) MCP — separate server with its own auth
# =========================================================================
# The ngs google-mcp-server in Step 5 is READ-ONLY for Gmail (list + get).
# To send email from Claude Code, we need @gongrzhe/server-gmail-autoauth-mcp.
# It uses the same OAuth client (your client_secret_*.json) but a separate token.
Write-Host "[6/7] Setting up Gmail send capability..." -ForegroundColor Yellow
$gmailMcpDir = Join-Path $env:USERPROFILE ".gmail-mcp"
$gmailKeysFile = Join-Path $gmailMcpDir "gcp-oauth.keys.json"
$gmailCredsFile = Join-Path $gmailMcpDir "credentials.json"

if (Step-Done 6) {
    Write-Host "  Gmail MCP already set up (skipped)" -ForegroundColor Green
} else {
    # Verify npx is available — Gmail MCP requires Node.js
    if (-not (Get-Command npx -ErrorAction SilentlyContinue)) {
        Write-Host "  npx not found. The Gmail MCP requires Node.js." -ForegroundColor Yellow
        # Try auto-installing via winget if available
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-Host "  winget detected — installing Node.js automatically..." -ForegroundColor White
            try {
                winget install OpenJS.NodeJS --accept-source-agreements --accept-package-agreements
                # Refresh PATH in current session so npx is available immediately
                $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
                if (Get-Command npx -ErrorAction SilentlyContinue) {
                    Write-Host "  Node.js installed via winget" -ForegroundColor Green
                } else {
                    Write-Host "  Node.js installed but npx not yet on PATH." -ForegroundColor Yellow
                    Write-Host "  Close PowerShell, reopen it, and re-run this script." -ForegroundColor Yellow
                    Step-Failed 6
                }
            } catch {
                Write-Host "  ERROR: Failed to install Node.js via winget." -ForegroundColor Red
                Write-Host "  Install it manually from https://nodejs.org/en/download" -ForegroundColor Yellow
                Write-Host "  After installing, close PowerShell, reopen it, and re-run this script." -ForegroundColor Yellow
                Step-Failed 6
            }
        } else {
            Write-Host "  ERROR: npx not found and winget is not available." -ForegroundColor Red
            Write-Host "  Install Node.js from https://nodejs.org/en/download" -ForegroundColor Yellow
            Write-Host "  After installing, close PowerShell, reopen it, and re-run this script." -ForegroundColor Yellow
            Step-Failed 6
        }
    }

    if (-not (Test-Path $gmailMcpDir)) {
        New-Item -Path $gmailMcpDir -ItemType Directory -Force | Out-Null
    }

    # Locate the OAuth JSON
    if (Test-Path $gmailKeysFile) {
        Write-Host "  Found existing OAuth keys at $gmailKeysFile" -ForegroundColor Green
    } else {
        $foundJson = Find-OAuthJson

        if ($foundJson) {
            Write-Host "  Found OAuth file: $($foundJson.Name)" -ForegroundColor Green
            Copy-Item $foundJson.FullName $gmailKeysFile -Force
            Write-Host "  Copied to $gmailKeysFile" -ForegroundColor Green
        } else {
            Write-Host "  No OAuth JSON file found in Downloads or Desktop." -ForegroundColor Yellow
            Write-Host "  Opening your Downloads folder." -ForegroundColor White
            Write-Host "  Drop your JSON file in there (exact name doesn't matter), then press Enter." -ForegroundColor White
            Start-Process explorer.exe -ArgumentList "$env:USERPROFILE\Downloads"
            Read-Host "  Press Enter once the file is in Downloads"

            # Re-scan
            $foundJson = Find-OAuthJson
            if ($foundJson) {
                Write-Host "  Found: $($foundJson.Name)" -ForegroundColor Green
                Copy-Item $foundJson.FullName $gmailKeysFile -Force
                Write-Host "  Copied to $gmailKeysFile" -ForegroundColor Green
            } else {
                Write-Host "  Still no valid OAuth JSON found. Paste the full path manually:" -ForegroundColor Yellow
                Write-Host "  (Right-click the file in File Explorer, 'Copy as path', then right-click to paste)"
                $manualPath = Read-Host "  Path to JSON file"
                $manualPath = $manualPath.Trim('"').Trim("'")
                if (-not (Test-Path $manualPath)) {
                    Write-Host "  File not found at: $manualPath" -ForegroundColor Red
                    Step-Failed 6
                }
                Copy-Item $manualPath $gmailKeysFile -Force
                Write-Host "  Copied to $gmailKeysFile" -ForegroundColor Green
            }
        }
    }

    Write-Host ""
    Write-Host "  Your browser will open for Gmail authentication." -ForegroundColor White
    Write-Host ""
    Write-Host "  IMPORTANT: On the Google permission screen, make sure EVERY checkbox" -ForegroundColor Yellow
    Write-Host "  is checked - especially 'Send email on your behalf'. If you skip it," -ForegroundColor Yellow
    Write-Host "  Claude won't be able to send mail." -ForegroundColor Yellow
    Write-Host ""
    Read-Host "  Press Enter to open the browser"
    try {
        npx -y "@gongrzhe/server-gmail-autoauth-mcp" auth
        Write-Host "  Gmail browser auth completed" -ForegroundColor Green
    } catch {
        Write-Host "  Gmail auth did not complete cleanly: $_" -ForegroundColor Red
        Step-Failed 6
    }

    # Verify credentials.json was written and has a valid refresh token
    if (-not (Test-Path $gmailCredsFile)) {
        Write-Host "  ERROR: Auth completed but no token was written at $gmailCredsFile" -ForegroundColor Red
        Write-Host "  The browser flow may have closed too early. Re-run the script." -ForegroundColor Yellow
        Step-Failed 6
    }

    try {
        $creds = Get-Content $gmailCredsFile -Raw | ConvertFrom-Json
    } catch {
        Write-Host "  ERROR: credentials.json is malformed." -ForegroundColor Red
        Remove-Item $gmailCredsFile -Force
        Step-Failed 6
    }

    if (-not $creds.refresh_token) {
        Write-Host "  ERROR: Token file missing refresh_token. Re-auth required." -ForegroundColor Red
        Remove-Item $gmailCredsFile -Force
        Step-Failed 6
    }

    # Confirm Gmail send scope was granted (modify covers send)
    $grantedScope = "$($creds.scope) $($creds.granted_scopes)"
    if ($grantedScope -notmatch "gmail\.(send|modify)|mail\.google\.com") {
        Write-Host "  ERROR: Gmail SEND permission was NOT granted." -ForegroundColor Red
        Write-Host "  On the Google consent screen, the 'Send email on your behalf' box was unchecked." -ForegroundColor Yellow
        Write-Host "  Deleting token and asking you to re-auth..." -ForegroundColor Yellow
        Remove-Item $gmailCredsFile -Force
        Step-Failed 6
    }
    Write-Host "  Token verified (send scope granted)" -ForegroundColor Green

    # Actually send a test email to confirm end-to-end that Gmail send works
    Write-Host "  Sending a test email to confirm Gmail send is working..." -ForegroundColor White
    try {
        $tokenResp = Invoke-RestMethod -Uri "https://oauth2.googleapis.com/token" -Method Post -Body @{
            client_id = $CLIENT_ID
            client_secret = $CLIENT_SECRET
            refresh_token = $creds.refresh_token
            grant_type = "refresh_token"
        }
        $accessToken = $tokenResp.access_token

        # Use Gmail's own profile endpoint (works with gmail.modify scope; oauth2/userinfo requires a separate scope)
        $gmailProfile = Invoke-RestMethod -Uri "https://gmail.googleapis.com/gmail/v1/users/me/profile" `
            -Headers @{Authorization = "Bearer $accessToken"}
        $userEmail = $gmailProfile.emailAddress

        $raw = "From: $userEmail`r`nTo: $userEmail`r`nSubject: LBL Setup - Gmail send verified`r`n`r`nYour Chief of Staff can now send email on your behalf. You can delete this message."
        $encoded = ([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($raw))) -replace '\+','-' -replace '/','_' -replace '=',''

        Invoke-RestMethod -Uri "https://gmail.googleapis.com/gmail/v1/users/me/messages/send" -Method Post `
            -Headers @{Authorization = "Bearer $accessToken"} `
            -ContentType "application/json" -Body (@{raw = $encoded} | ConvertTo-Json) | Out-Null
        Write-Host "  Gmail send CONFIRMED — check $userEmail for a test message" -ForegroundColor Green
    } catch {
        Write-Host "  Test email FAILED: $_" -ForegroundColor Red
        Write-Host "  Auth looked right, but Gmail send is not working." -ForegroundColor Yellow
        Write-Host "  Most likely: Gmail API is not enabled in your Google Cloud project," -ForegroundColor Yellow
        Write-Host "  OR your OAuth consent screen is still in Testing mode without your email added as a test user." -ForegroundColor Yellow
        Step-Failed 6
    }

    # Add the MCP to Claude Code
    try { claude mcp remove gmail 2>$null } catch {}
    try {
        claude mcp add --scope user gmail -- npx -y "@gongrzhe/server-gmail-autoauth-mcp"
        Write-Host "  Gmail MCP added to Claude Code (send + read)" -ForegroundColor Green
        Mark-Done 6
    } catch {
        Write-Host "  Failed to add Gmail MCP to Claude Code: $_" -ForegroundColor Red
        Step-Failed 6
    }
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
        "$chiefPath\Skills",
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

# Check 4: gmail credentials.json exists AND has a usable refresh token
if (Test-Path $gmailCredsFile) {
    try {
        $credsCheck = Get-Content $gmailCredsFile -Raw | ConvertFrom-Json
        if ($credsCheck.refresh_token -and "$($credsCheck.scope) $($credsCheck.granted_scopes)" -match "gmail\.(send|modify)|mail\.google\.com") {
            Write-Host "  Gmail OAuth token verified (send scope granted)" -ForegroundColor Green
        } else {
            Write-Host "  WARNING: Gmail token present but missing send scope or refresh_token." -ForegroundColor Yellow
            $sanityPassed = $false
        }
    } catch {
        Write-Host "  WARNING: Gmail token file is malformed." -ForegroundColor Yellow
        $sanityPassed = $false
    }
} else {
    Write-Host "  WARNING: No Gmail OAuth token found. Re-run the auth step." -ForegroundColor Yellow
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

    # Check 3: gmail MCP is registered (needed for sending email)
    if ($mcpList -match "gmail") {
        Write-Host "  Gmail MCP is registered in Claude Code (send + read)" -ForegroundColor Green
    } else {
        Write-Host "  WARNING: Gmail MCP not found - you won't be able to send email." -ForegroundColor Yellow
        $sanityPassed = $false
    }
} catch {
    Write-Host "  Could not check Claude Code config - restart PowerShell if needed." -ForegroundColor Yellow
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
Write-Host '    "Draft an email to myself saying hello"'
Write-Host ""
Write-Host "  If something isn't working, raise your hand — we're here to help!"
Write-Host ""
Write-Host "  NOTE: If 'claude' is not recognized in a new PowerShell window," -ForegroundColor Yellow
Write-Host "  close PowerShell completely and reopen it. The PATH update" -ForegroundColor Yellow
Write-Host "  takes effect in new windows only." -ForegroundColor Yellow
Write-Host ""

# Clean up checkpoints only on a fully successful run.
# If sanity failed, keep checkpoints so the user can re-run and resume.
if ($sanityPassed) {
    Write-Host "  (Cleaning up setup checkpoints...)"
    Remove-Item -Path $CheckpointDir -Recurse -Force -ErrorAction SilentlyContinue
} else {
    Write-Host "  (Leaving checkpoints in place so you can re-run to fix remaining issues.)" -ForegroundColor Yellow
}
Write-Host ""
