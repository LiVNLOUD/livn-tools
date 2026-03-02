#Requires -Version 5.1
<#
.SYNOPSIS
    Livn Tools v3.5 - Remote Installer
    Usage: irm livn.tr/win | iex
.DESCRIPTION
    GitHub'dan Livn Tools dosyalarini indirir ve baslatir.
    Yonetici yetkisi gerektirir.
    ISLC kurulumu (parametreler + Gorev Zamanlayici) uygulamadan
    Performance > Uygula butonuna tiklandiginda otomatik yapilir.
#>

# ─── ADMIN CHECK ───────────────────────────────────────────────────────────────
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host ""
    Write-Host "  [!] Yonetici yetkisi gerekli." -ForegroundColor Red
    Write-Host "  [!] PowerShell'i Yonetici olarak acin ve tekrar deneyin." -ForegroundColor Red
    Write-Host ""
    Write-Host "  Komut:" -ForegroundColor Yellow
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
    # Ana scriptler (zorunlu)
    @{ Url = "$RepoBase/Main.ps1";      Dest = "Main.ps1";      Optional = $false },
    @{ Url = "$RepoBase/LivnTools.bat"; Dest = "LivnTools.bat"; Optional = $false },

    # Guc planlari
    @{ Url = "$RepoBase/_Files/Bitsum-Highest-Performance.pow";                 Dest = "_Files\Bitsum-Highest-Performance.pow";                Optional = $true },
    @{ Url = "$RepoBase/_Files/HybredPowerPlans/HybredLowLatencyHighPerf.pow"; Dest = "_Files\HybredPowerPlans\HybredLowLatencyHighPerf.pow"; Optional = $true },
    @{ Url = "$RepoBase/_Files/HybredPowerPlans/HybredLowLatencyBalanced.pow"; Dest = "_Files\HybredPowerPlans\HybredLowLatencyBalanced.pow"; Optional = $true },

    # Win32 Priority registry dosyalari
    @{ Url = "$RepoBase/_Files/Win32Prio_Balanced_TheHybred.reg"; Dest = "_Files\Win32Prio_Balanced_TheHybred.reg"; Optional = $true },
    @{ Url = "$RepoBase/_Files/Win32Prio_BestFPS_TheHybred.reg";  Dest = "_Files\Win32Prio_BestFPS_TheHybred.reg";  Optional = $true },
    @{ Url = "$RepoBase/_Files/Win32Prio_Default_TheHybred.reg";  Dest = "_Files\Win32Prio_Default_TheHybred.reg";  Optional = $true },

    # ISLC - Intelligent Standby List Cleaner (Wagnardsoft)
    @{ Url = "$RepoBase/_Files/ISLC/Intelligent standby list cleaner ISLC.exe"; Dest = "_Files\ISLC\Intelligent standby list cleaner ISLC.exe"; Optional = $true },
    @{ Url = "$RepoBase/_Files/ISLC/Intelligent standby list cleaner ISLC.pdb"; Dest = "_Files\ISLC\Intelligent standby list cleaner ISLC.pdb"; Optional = $true },
    @{ Url = "$RepoBase/_Files/ISLC/ReadMe_ISLC.txt";                            Dest = "_Files\ISLC\ReadMe_ISLC.txt";                            Optional = $true }
)

# ─── KLASORLER ─────────────────────────────────────────────────────────────────
Write-Host "  [*] Kurulum klasoru: $InstallDir" -ForegroundColor Cyan
Write-Host ""

foreach ($sub in @("_Files", "_Files\Backups", "_Files\Logs", "_Files\HybredPowerPlans", "_Files\ISLC")) {
    $path = Join-Path $InstallDir $sub
    if (-not (Test-Path $path)) { New-Item -Path $path -ItemType Directory -Force | Out-Null }
}

# ─── DOSYALARI INDIR ───────────────────────────────────────────────────────────
Write-Host "  [*] Dosyalar indiriliyor..." -ForegroundColor Cyan
Write-Host ""

$wc = [System.Net.WebClient]::new()
$wc.Encoding = [System.Text.Encoding]::UTF8
$errors = 0

foreach ($file in $FilesToDownload) {
    $destPath = Join-Path $InstallDir $file.Dest
    $destDir  = Split-Path $destPath -Parent
    if (-not (Test-Path $destDir)) { New-Item -Path $destDir -ItemType Directory -Force | Out-Null }
    try {
        $wc.DownloadFile($file.Url, $destPath)
        Write-Host "  [ OK ] $($file.Dest)" -ForegroundColor Green
    } catch {
        if ($file.Optional) {
            Write-Host "  [SKIP] $($file.Dest) (optional)" -ForegroundColor DarkYellow
        } else {
            Write-Host "  [ERR ] $($file.Dest) — $_" -ForegroundColor Red
            $errors++
        }
    }
}

$wc.Dispose()

# ─── HATA KONTROLU ─────────────────────────────────────────────────────────────
Write-Host ""
if ($errors -gt 0) {
    Write-Host "  [!] $errors dosya indirilemedi. Internet baglantinizi kontrol edip tekrar deneyin." -ForegroundColor Red
    Write-Host ""
    pause
    exit 1
}

# ─── BASLATMA ──────────────────────────────────────────────────────────────────
Write-Host "  ─────────────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  [ OK ] Kurulum tamamlandi!" -ForegroundColor Green
Write-Host ""
Write-Host "  ISLC (RAM Optimizasyonu) kurulumu ucin:" -ForegroundColor DarkGray
Write-Host "  Performance > Standby / Modified List seceneklerini isaretleyip Uygula'ya tiklayin." -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Livn Tools baslatiliyor..." -ForegroundColor Magenta
Write-Host ""
Start-Sleep -Milliseconds 800

$mainScript = Join-Path $InstallDir "Main.ps1"
Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$mainScript`"" -Verb RunAs

exit 0
