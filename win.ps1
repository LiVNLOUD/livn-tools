#Requires -Version 5.1
<#
.SYNOPSIS
    Livn Tools v3.5 - Remote Installer
    Usage: irm livn.tr/win | iex

.DESCRIPTION
    Downloads and launches Livn Tools from GitHub.
    Requires administrator privileges.
#>

# ─── ADMIN CHECK ───────────────────────────────────────────────────────────────
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host ""
    Write-Host "  [!] Administrator privileges required." -ForegroundColor Red
    Write-Host "  [!] Please run PowerShell as Administrator and try again." -ForegroundColor Red
    Write-Host ""
    Write-Host "  Run this command in an elevated PowerShell:" -ForegroundColor Yellow
    Write-Host "  irm livn.tr/win | iex" -ForegroundColor Cyan
    Write-Host ""
    pause
    exit 1
}

# ─── BANNER ────────────────────────────────────────────────────────────────────
Clear-Host
Write-Host ""
Write-Host "  ██╗     ██╗██╗   ██╗███╗   ██╗    ████████╗ ██████╗  ██████╗ ██╗     ███████╗" -ForegroundColor Magenta
Write-Host "  ██║     ██║██║   ██║████╗  ██║    ╚══██╔══╝██╔═══██╗██╔═══██╗██║     ██╔════╝" -ForegroundColor Magenta
Write-Host "  ██║     ██║██║   ██║██╔██╗ ██║       ██║   ██║   ██║██║   ██║██║     ███████╗" -ForegroundColor Magenta
Write-Host "  ██║     ██║╚██╗ ██╔╝██║╚██╗██║       ██║   ██║   ██║██║   ██║██║     ╚════██║" -ForegroundColor Magenta
Write-Host "  ███████╗██║ ╚████╔╝ ██║ ╚████║       ██║   ╚██████╔╝╚██████╔╝███████╗███████║" -ForegroundColor Magenta
Write-Host "  ╚══════╝╚═╝  ╚═══╝  ╚═╝  ╚═══╝       ╚═╝    ╚═════╝  ╚═════╝ ╚══════╝╚══════╝" -ForegroundColor Magenta
Write-Host ""
Write-Host "  v3.5  |  Windows Optimization Suite  |  livn.tr" -ForegroundColor DarkMagenta
Write-Host "  github.com/LiVNLOUD/livn-tools" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  ─────────────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# ─── CONFIG ────────────────────────────────────────────────────────────────────
$RepoBase   = "https://raw.githubusercontent.com/LiVNLOUD/livn-tools/main"
$InstallDir = Join-Path $env:USERPROFILE "Documents\LivnTools"

$FilesToDownload = @(
    @{ Url = "$RepoBase/Main.ps1";                                  Dest = "Main.ps1" },
    @{ Url = "$RepoBase/LivnTools.bat";                             Dest = "LivnTools.bat" },
    @{ Url = "$RepoBase/_Files/Bitsum-Highest-Performance.pow";     Dest = "_Files\Bitsum-Highest-Performance.pow" },
    @{ Url = "$RepoBase/_Files/Win32Prio_Balanced_TheHybred.reg";   Dest = "_Files\Win32Prio_Balanced_TheHybred.reg" },
    @{ Url = "$RepoBase/_Files/Win32Prio_BestFPS_TheHybred.reg";    Dest = "_Files\Win32Prio_BestFPS_TheHybred.reg" },
    @{ Url = "$RepoBase/_Files/Win32Prio_Default_TheHybred.reg";    Dest = "_Files\Win32Prio_Default_TheHybred.reg" }
)

# ─── INSTALL DIR ───────────────────────────────────────────────────────────────
Write-Host "  [*] Install location: $InstallDir" -ForegroundColor Cyan
Write-Host ""

foreach ($sub in @("_Files", "_Files\Backups", "_Files\Logs")) {
    $path = Join-Path $InstallDir $sub
    if (-not (Test-Path $path)) {
        New-Item -Path $path -ItemType Directory -Force | Out-Null
    }
}

# ─── DOWNLOAD FILES ────────────────────────────────────────────────────────────
Write-Host "  [*] Downloading files..." -ForegroundColor Cyan
Write-Host ""

$wc = [System.Net.WebClient]::new()
$wc.Encoding = [System.Text.Encoding]::UTF8
$errors = 0

foreach ($file in $FilesToDownload) {
    $destPath = Join-Path $InstallDir $file.Dest
    try {
        $wc.DownloadFile($file.Url, $destPath)
        Write-Host "  [ OK ] $($file.Dest)" -ForegroundColor Green
    } catch {
        # Optional files (like .reg) may not exist yet - warn but continue
        if ($file.Dest -match '\.(reg|pow)$') {
            Write-Host "  [SKIP] $($file.Dest) (optional)" -ForegroundColor DarkYellow
        } else {
            Write-Host "  [ERR ] $($file.Dest) - $_" -ForegroundColor Red
            $errors++
        }
    }
}

$wc.Dispose()

# ─── CHECK ERRORS ──────────────────────────────────────────────────────────────
Write-Host ""
if ($errors -gt 0) {
    Write-Host "  [!] $errors file(s) failed to download." -ForegroundColor Red
    Write-Host "  [!] Check your internet connection and try again." -ForegroundColor Red
    Write-Host ""
    pause
    exit 1
}

# ─── LAUNCH ────────────────────────────────────────────────────────────────────
Write-Host "  ─────────────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  [ OK ] Download complete." -ForegroundColor Green
Write-Host ""
Write-Host "  Livn Tools is launching..." -ForegroundColor Magenta
Write-Host ""
Start-Sleep -Milliseconds 800

$mainScript = Join-Path $InstallDir "Main.ps1"
Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$mainScript`"" -Verb RunAs

exit 0
