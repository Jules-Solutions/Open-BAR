# TotallyLegal Widget Installer
# Self-contained installer for Beyond All Reason widgets
# Usage: irm https://raw.githubusercontent.com/Jules-Solutions/Open-BAR/main/install/Install-TotallyLegal.ps1 | iex
# Or run directly: powershell -ExecutionPolicy Bypass -File Install-TotallyLegal.ps1

$ErrorActionPreference = 'Continue'

# ============================================================================
# CONFIG
# ============================================================================
$RepoOwner = "Jules-Solutions"
$RepoName  = "Open-BAR"
$Branch    = "main"
$WidgetSubPath = "lua/LuaUI/Widgets"
$AppName   = "TotallyLegal"

# ============================================================================
# UI HELPERS
# ============================================================================
function Write-Banner {
    Write-Host ""
    Write-Host "  ============================================" -ForegroundColor Cyan
    Write-Host "      TotallyLegal Widget Installer" -ForegroundColor Cyan
    Write-Host "      Beyond All Reason Widget Suite" -ForegroundColor DarkCyan
    Write-Host "  ============================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step {
    param([string]$msg)
    Write-Host "  $msg" -ForegroundColor Gray
}

function Write-OK {
    param([string]$msg)
    Write-Host "  [OK] $msg" -ForegroundColor Green
}

function Write-Err {
    param([string]$msg)
    Write-Host "  [ERROR] $msg" -ForegroundColor Red
}

function Write-Warn {
    param([string]$msg)
    Write-Host "  [!] $msg" -ForegroundColor Yellow
}

function Write-Info {
    param([string]$msg)
    Write-Host "  $msg" -ForegroundColor DarkGray
}

# ============================================================================
# BAR DETECTION
# ============================================================================
function Find-BARDataDirectory {
    <#
    .SYNOPSIS
        Auto-detect Beyond All Reason data directory
    .OUTPUTS
        Path to BAR data directory, or $null if not found
    #>
    
    $candidates = @(
        # BAR launcher (most common)
        "$env:LOCALAPPDATA\Programs\Beyond-All-Reason\data",
        # Alternative locations
        "$env:PROGRAMFILES\Beyond-All-Reason\data",
        "$env:USERPROFILE\Beyond All Reason\data",
        # Portable / custom installs
        "C:\Games\Beyond-All-Reason\data",
        "D:\Games\Beyond-All-Reason\data",
        # Spring engine paths (legacy)
        "$env:LOCALAPPDATA\Spring\data",
        "$env:APPDATA\Spring\data"
    )
    
    foreach ($path in $candidates) {
        if (Test-Path (Join-Path $path "LuaUI\Widgets")) {
            return $path
        }
    }
    
    # Try to find via registry (BAR launcher may register itself)
    try {
        $regPaths = @(
            "HKCU:\Software\Beyond All Reason",
            "HKLM:\Software\Beyond All Reason"
        )
        foreach ($regPath in $regPaths) {
            if (Test-Path $regPath) {
                $installDir = (Get-ItemProperty $regPath -ErrorAction SilentlyContinue).InstallPath
                if ($installDir) {
                    $dataPath = Join-Path $installDir "data"
                    if (Test-Path (Join-Path $dataPath "LuaUI\Widgets")) {
                        return $dataPath
                    }
                }
            }
        }
    } catch { }
    
    return $null
}

function Select-FolderDialog {
    <#
    .SYNOPSIS
        Open a folder browser dialog
    .OUTPUTS
        Selected folder path, or $null if cancelled
    #>
    param([string]$Description = "Select your Beyond All Reason data folder")
    
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Description
    $dialog.ShowNewFolderButton = $false
    
    # Start in a sensible location
    if (Test-Path "$env:LOCALAPPDATA\Programs") {
        $dialog.SelectedPath = "$env:LOCALAPPDATA\Programs"
    }
    
    $result = $dialog.ShowDialog()
    
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.SelectedPath
    }
    
    return $null
}

# ============================================================================
# DOWNLOAD
# ============================================================================
function Get-WidgetFilesFromGitHub {
    <#
    .SYNOPSIS
        Download widget .lua files from the public GitHub repo
    .PARAMETER TempDir
        Directory to save downloaded files
    .OUTPUTS
        Array of downloaded file paths
    #>
    param([string]$TempDir)
    
    # Use GitHub API to list files in the widgets directory
    $apiUrl = "https://api.github.com/repos/$RepoOwner/$RepoName/contents/$WidgetSubPath`?ref=$Branch"
    
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    } catch { }
    
    $headers = @{ 'User-Agent' = 'TotallyLegal-Installer' }
    
    Write-Step "Fetching widget list from GitHub..."
    
    try {
        $files = Invoke-RestMethod -Uri $apiUrl -Headers $headers -ErrorAction Stop
    } catch {
        throw "Failed to fetch widget list from GitHub: $_"
    }
    
    $luaFiles = $files | Where-Object { $_.name -match '\.lua$' }
    
    if ($luaFiles.Count -eq 0) {
        throw "No .lua widget files found in the repository"
    }
    
    Write-OK "Found $($luaFiles.Count) widgets"
    
    # Download each file
    $downloaded = @()
    $count = 0
    
    foreach ($file in $luaFiles) {
        $count++
        $pct = [int](($count / $luaFiles.Count) * 100)
        Write-Host "`r  Downloading... $count/$($luaFiles.Count) ($pct%)" -NoNewline -ForegroundColor Gray
        
        $downloadUrl = $file.download_url
        $localPath = Join-Path $TempDir $file.name
        
        try {
            Invoke-WebRequest -Uri $downloadUrl -OutFile $localPath -Headers $headers -UseBasicParsing -ErrorAction Stop
            $downloaded += $localPath
        } catch {
            Write-Host ""
            Write-Warn "Failed to download $($file.name): $_"
        }
    }
    
    Write-Host ""  # newline after progress
    
    if ($downloaded.Count -eq 0) {
        throw "Failed to download any widget files"
    }
    
    Write-OK "Downloaded $($downloaded.Count)/$($luaFiles.Count) widgets"
    
    return $downloaded
}

# ============================================================================
# INSTALL
# ============================================================================
function Install-Widgets {
    param(
        [string[]]$WidgetFiles,
        [string]$BARDataPath
    )
    
    $targetDir = Join-Path $BARDataPath "LuaUI\Widgets\TotallyLegal"
    
    # Create target directory
    if (-not (Test-Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }
    
    # Copy files
    $copied = 0
    foreach ($file in $WidgetFiles) {
        $dest = Join-Path $targetDir (Split-Path $file -Leaf)
        Copy-Item -Path $file -Destination $dest -Force
        $copied++
    }
    
    Write-OK "Installed $copied widgets to:"
    Write-Info "  $targetDir"
    
    return $targetDir
}

# ============================================================================
# UNINSTALL
# ============================================================================
function Uninstall-Widgets {
    param([string]$BARDataPath)
    
    $targetDir = Join-Path $BARDataPath "LuaUI\Widgets\TotallyLegal"
    
    if (Test-Path $targetDir) {
        # Check if it's a junction/symlink
        $item = Get-Item $targetDir -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            # It's a junction - just remove the junction, not the source
            cmd /c rmdir "$targetDir" 2>$null
        } else {
            Remove-Item $targetDir -Recurse -Force
        }
        Write-OK "Removed TotallyLegal widgets"
    } else {
        Write-Warn "TotallyLegal widgets not found at: $targetDir"
    }
}

# ============================================================================
# MAIN
# ============================================================================
Write-Banner

# Check for uninstall flag
if ($args -contains '--uninstall' -or $args -contains '-Uninstall') {
    Write-Host "  Uninstalling TotallyLegal widgets..." -ForegroundColor Yellow
    Write-Host ""
    
    $barData = Find-BARDataDirectory
    if ($barData) {
        Uninstall-Widgets -BARDataPath $barData
    } else {
        Write-Err "Could not find BAR installation"
        Write-Host "  Specify path manually: .\Install-TotallyLegal.ps1 --uninstall --path `"C:\path\to\BAR\data`""
    }
    
    Write-Host ""
    Write-Host "  Press any key to exit..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit 0
}

# --- Step 1: Find BAR ---
Write-Host "  Looking for Beyond All Reason..." -ForegroundColor Gray

$barData = Find-BARDataDirectory

if ($barData) {
    Write-OK "Found BAR at: $barData"
} else {
    Write-Warn "Could not auto-detect BAR installation"
    Write-Host ""
    Write-Host "  Please select your Beyond All Reason data folder." -ForegroundColor Yellow
    Write-Host "  It should contain a LuaUI\Widgets subfolder." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Press Enter to open folder picker..." -ForegroundColor Cyan
    $null = Read-Host
    
    $barData = Select-FolderDialog -Description "Select your Beyond All Reason 'data' folder (contains LuaUI\Widgets)"
    
    if (-not $barData) {
        Write-Err "No folder selected. Installation cancelled."
        Write-Host ""
        Write-Host "  Press any key to exit..." -ForegroundColor Gray
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        exit 1
    }
    
    # Validate the selected folder
    if (-not (Test-Path (Join-Path $barData "LuaUI\Widgets"))) {
        # Maybe they selected the parent? Check for data subfolder
        $dataSubDir = Join-Path $barData "data"
        if (Test-Path (Join-Path $dataSubDir "LuaUI\Widgets")) {
            $barData = $dataSubDir
        } else {
            Write-Err "Selected folder doesn't contain LuaUI\Widgets"
            Write-Host "  Expected: $barData\LuaUI\Widgets" -ForegroundColor DarkGray
            Write-Host ""
            Write-Host "  Press any key to exit..." -ForegroundColor Gray
            $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            exit 1
        }
    }
    
    Write-OK "Using: $barData"
}

# --- Step 2: Check for existing installation ---
$existingDir = Join-Path $barData "LuaUI\Widgets\TotallyLegal"
if (Test-Path $existingDir) {
    Write-Host ""
    Write-Warn "TotallyLegal is already installed!"
    Write-Host ""
    Write-Host "  [U] Update to latest version" -ForegroundColor Cyan
    Write-Host "  [R] Reinstall (clean)" -ForegroundColor Cyan
    Write-Host "  [X] Uninstall and exit" -ForegroundColor Cyan
    Write-Host "  [C] Cancel" -ForegroundColor Gray
    Write-Host ""
    $choice = Read-Host "  Choose [U/R/X/C]"
    
    switch ($choice.ToUpper()) {
        'U' {
            Write-Host ""
            Write-Step "Updating widgets..."
        }
        'R' {
            Write-Host ""
            Write-Step "Removing existing installation..."
            Uninstall-Widgets -BARDataPath $barData
            Write-Host ""
        }
        'X' {
            Uninstall-Widgets -BARDataPath $barData
            Write-Host ""
            Write-Host "  Press any key to exit..." -ForegroundColor Gray
            $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            exit 0
        }
        default {
            Write-Host "  Cancelled." -ForegroundColor Gray
            exit 0
        }
    }
}

# --- Step 3: Download widgets ---
Write-Host ""

$tempDir = Join-Path $env:TEMP "TotallyLegal-Install-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

try {
    $widgetFiles = Get-WidgetFilesFromGitHub -TempDir $tempDir
} catch {
    Write-Err "$_"
    Write-Host ""
    Write-Host "  Check your internet connection and try again." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Press any key to exit..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    
    # Cleanup
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}

# --- Step 4: Install ---
Write-Host ""

try {
    $installDir = Install-Widgets -WidgetFiles $widgetFiles -BARDataPath $barData
} catch {
    Write-Err "Installation failed: $_"
    Write-Host ""
    Write-Host "  Press any key to exit..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    
    # Cleanup
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}

# Cleanup temp files
Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue

# --- Done! ---
Write-Host ""
Write-Host "  ============================================" -ForegroundColor Green
Write-Host "      Installation Complete!" -ForegroundColor Green
Write-Host "  ============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor White
Write-Host "    1. Launch Beyond All Reason" -ForegroundColor Gray
Write-Host "    2. Open the widget list (F11)" -ForegroundColor Gray
Write-Host "    3. Enable TotallyLegal widgets" -ForegroundColor Gray
Write-Host "    4. Use Ctrl+F3 to open the config panel" -ForegroundColor Gray
Write-Host ""
Write-Host "  Widget types:" -ForegroundColor White
Write-Host "    gui_*   = Overlays (PvP safe, info only)" -ForegroundColor DarkGray
Write-Host "    auto_*  = Micro automation (dodge, kite)" -ForegroundColor DarkGray
Write-Host "    engine_* = Macro automation (eco, build)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  To uninstall later, run:" -ForegroundColor DarkGray
Write-Host "    rmdir `"$installDir`"" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Press any key to exit..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
