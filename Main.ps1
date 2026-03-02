# Livn Tools v3.5 — Installer
# irm livn.tr/win | iex

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

$repo    = "https://raw.githubusercontent.com/LiVNLOUD/livn-tools/main"
$install = "$env:USERPROFILE\Documents\LivnTools"

$banner = @"

  v3.5 | Windows Optimization Suite | livn.tr   github.com/LiVNLOUD/livn-tools
  ─────────────────────────────────────────────────────────────────────────────
"@
Write-Host $banner -ForegroundColor Cyan

# Klasor
if (-not (Test-Path $install)) { New-Item -ItemType Directory -Path $install -Force | Out-Null }
Write-Host "  [] Kurulum klasoru: $install" -ForegroundColor DarkGray

# Indirme fonksiyonu - WebClient yerine Invoke-WebRequest + curl fallback
function Get-File {
    param([string]$Url, [string]$Dest, [bool]$Optional=$false)

    $label = Split-Path $Dest -Leaf
    $dir   = Split-Path $Dest -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $ok = $false

    # 1. Invoke-WebRequest (TLS 1.2)
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing -TimeoutSec 30
        $ok = $true
    } catch {}

    # 2. curl.exe fallback (Windows 10+ built-in)
    if (-not $ok) {
        try {
            & curl.exe -sS -L --tlsv1.2 -o $Dest $Url 2>$null
            if (Test-Path $Dest) { $ok = $true }
        } catch {}
    }

    # 3. BitsTransfer fallback
    if (-not $ok) {
        try {
            Import-Module BitsTransfer -EA Stop
            Start-BitsTransfer -Source $Url -Destination $Dest -EA Stop
            $ok = $true
        } catch {}
    }

    if ($ok) {
        Write-Host "  [OK]  $label" -ForegroundColor Green
    } elseif ($Optional) {
        Write-Host "  [SKIP] $label (optional)" -ForegroundColor DarkGray
    } else {
        Write-Host "  [ERR] $label — indirilemedi" -ForegroundColor Red
        return $false
    }
    return $true
}

Write-Host "  [] Dosyalar indiriliyor..." -ForegroundColor DarkGray

$errors = 0

# Zorunlu dosyalar
if (-not (Get-File "$repo/Main.ps1"      "$install\Main.ps1"))      { $errors++ }
if (-not (Get-File "$repo/LivnTools.bat" "$install\LivnTools.bat")) { $errors++ }

# Opsiyonel dosyalar
Get-File "$repo/_Files/Bitsum-Highest-Performance.pow"                         "$install\_Files\Bitsum-Highest-Performance.pow"                         $true
Get-File "$repo/_Files/HybredPowerPlans/HybredLowLatencyHighPerf.pow"          "$install\_Files\HybredPowerPlans\HybredLowLatencyHighPerf.pow"          $true
Get-File "$repo/_Files/HybredPowerPlans/HybredLowLatencyBalanced.pow"          "$install\_Files\HybredPowerPlans\HybredLowLatencyBalanced.pow"          $true
Get-File "$repo/_Files/Win32Prio_Balanced_TheHybred.reg"                       "$install\_Files\Win32Prio_Balanced_TheHybred.reg"                       $true
Get-File "$repo/_Files/Win32Prio_BestFPS_TheHybred.reg"                        "$install\_Files\Win32Prio_BestFPS_TheHybred.reg"                        $true
Get-File "$repo/_Files/Win32Prio_Default_TheHybred.reg"                        "$install\_Files\Win32Prio_Default_TheHybred.reg"                        $true
Get-File "$repo/_Files/ISLC/Intelligent standby list cleaner ISLC.exe"         "$install\_Files\ISLC\Intelligent standby list cleaner ISLC.exe"         $true
Get-File "$repo/_Files/ISLC/Intelligent standby list cleaner ISLC.pdb"         "$install\_Files\ISLC\Intelligent standby list cleaner ISLC.pdb"         $true
Get-File "$repo/_Files/ISLC/ReadMe_ISLC.txt"                                   "$install\_Files\ISLC\ReadMe_ISLC.txt"                                   $true

if ($errors -gt 0) {
    Write-Host ""
    Write-Host "  [!] $errors zorunlu dosya indirilemedi." -ForegroundColor Red
    Write-Host "      Lutfen internet baglantinizi kontrol edip tekrar deneyin." -ForegroundColor DarkGray
    Write-Host ""
    Read-Host "  Devam etmek icin Enter'a basin"
    exit 1
}

Write-Host ""
Write-Host "  [] Baslatiliyor..." -ForegroundColor DarkGray
Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$install\Main.ps1`"" -Verb RunAs
