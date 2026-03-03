# Livn Tools v3.5 — Installer
# irm livn.tr/win | iex

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

# TLS 1.2 — try ile; bazı sistemlerde .NET sürüm uyumsuzluğu çıkabilir
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$repo    = "https://raw.githubusercontent.com/LiVNLOUD/livn-tools/main"
$install = "$env:USERPROFILE\Documents\LivnTools"

# ── Renk yardımcısı ───────────────────────────────────────────────────────────
function C([string]$txt,[string]$fg='White',[switch]$NoNewLine) {
    if ($NoNewLine) { Write-Host $txt -ForegroundColor $fg -NoNewline }
    else            { Write-Host $txt -ForegroundColor $fg }
}

# ── Banner ────────────────────────────────────────────────────────────────────
Clear-Host
C ""
C "    ██╗     ██╗██╗   ██╗███╗   ██╗    ████████╗ ██████╗  ██████╗ ██╗     ███████╗" 'Cyan'
C "    ██║     ██║██║   ██║████╗  ██║    ╚══██╔══╝██╔═══██╗██╔═══██╗██║     ██╔════╝" 'Cyan'
C "    ██║     ██║██║   ██║██╔██╗ ██║       ██║   ██║   ██║██║   ██║██║     ███████╗" 'Cyan'
C "    ██║     ██║╚██╗ ██╔╝██║╚██╗██║       ██║   ██║   ██║██║   ██║██║     ╚════██║" 'Cyan'
C "    ███████╗██║ ╚████╔╝ ██║ ╚████║       ██║   ╚██████╔╝╚██████╔╝███████╗███████║" 'Cyan'
C "    ╚══════╝╚═╝  ╚═══╝  ╚═╝  ╚═══╝       ╚═╝    ╚═════╝  ╚═════╝ ╚══════╝╚══════╝" 'Cyan'
C ""
C "    ─────────────────────────────────────────────────────────────────────────────" 'DarkGray'
C "      Windows Optimization Suite  •  v3.5  •  livn.tr  •  github.com/LiVNLOUD" 'Gray'
C "    ─────────────────────────────────────────────────────────────────────────────" 'DarkGray'
C ""

# ── Kurulum klasörü ───────────────────────────────────────────────────────────
if (-not (Test-Path $install)) { New-Item -ItemType Directory -Path $install -Force | Out-Null }
C "  ► Kurulum klasörü : " 'DarkGray' -NoNewLine; C $install 'White'
C ""

# ── İndirme fonksiyonu ────────────────────────────────────────────────────────
$script:dlOK   = 0
$script:dlFail = 0
$script:dlSkip = 0

function Get-File {
    param([string]$Url, [string]$Dest, [bool]$Optional=$false)

    $label = Split-Path $Dest -Leaf
    $dir   = Split-Path $Dest -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $ok = $false

    try {
        Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
        $ok = $true
    } catch {}

    if (-not $ok) {
        try {
            & curl.exe -sS -L --tlsv1.2 -o $Dest $Url 2>$null
            if (Test-Path $Dest) { $ok = $true }
        } catch {}
    }

    if (-not $ok) {
        try {
            Import-Module BitsTransfer -ErrorAction Stop
            Start-BitsTransfer -Source $Url -Destination $Dest -ErrorAction Stop
            $ok = $true
        } catch {}
    }

    if ($ok) {
        C "    [+] $label" 'Green'
        $script:dlOK++
        return $true
    } elseif ($Optional) {
        C "    [-] $label  (atlandı)" 'DarkGray'
        $script:dlSkip++
        return $true
    } else {
        C "    [!] $label  — indirilemedi" 'Red'
        $script:dlFail++
        return $false
    }
}

# ── Dosyaları indir ───────────────────────────────────────────────────────────
C "  ► Dosyalar indiriliyor..." 'DarkGray'
C ""

$ok1 = Get-File "$repo/Main.ps1"      "$install\Main.ps1"
$ok2 = Get-File "$repo/LivnTools.bat" "$install\LivnTools.bat"

C ""
C "    Güç planları ve araçlar:" 'DarkGray'
$null = Get-File "$repo/_Files/Bitsum-Highest-Performance.pow"                "$install\_Files\Bitsum-Highest-Performance.pow"                $true
$null = Get-File "$repo/_Files/HybredPowerPlans/HybredLowLatencyHighPerf.pow" "$install\_Files\HybredPowerPlans\HybredLowLatencyHighPerf.pow" $true
$null = Get-File "$repo/_Files/HybredPowerPlans/HybredLowLatencyBalanced.pow" "$install\_Files\HybredPowerPlans\HybredLowLatencyBalanced.pow" $true
$null = Get-File "$repo/_Files/Win32Prio_Balanced_TheHybred.reg"               "$install\_Files\Win32Prio_Balanced_TheHybred.reg"               $true
$null = Get-File "$repo/_Files/Win32Prio_BestFPS_TheHybred.reg"                "$install\_Files\Win32Prio_BestFPS_TheHybred.reg"                $true
$null = Get-File "$repo/_Files/Win32Prio_Default_TheHybred.reg"                "$install\_Files\Win32Prio_Default_TheHybred.reg"                $true

C ""
C "    ISLC (Intelligent Standby List Cleaner):" 'DarkGray'
$null = Get-File "$repo/_Files/ISLC/Intelligent standby list cleaner ISLC.exe" "$install\_Files\ISLC\Intelligent standby list cleaner ISLC.exe" $true
$null = Get-File "$repo/_Files/ISLC/Intelligent standby list cleaner ISLC.pdb" "$install\_Files\ISLC\Intelligent standby list cleaner ISLC.pdb" $true
$null = Get-File "$repo/_Files/ISLC/ReadMe_ISLC.txt"                           "$install\_Files\ISLC\ReadMe_ISLC.txt"                           $true

# ── Özet ──────────────────────────────────────────────────────────────────────
C ""
C "    ─────────────────────────────────────────────────────────────────────────" 'DarkGray'
C "      İndirme : " 'DarkGray' -NoNewLine
C "+$($script:dlOK) başarılı" 'Green' -NoNewLine
if ($script:dlSkip -gt 0) { C "  •  -$($script:dlSkip) atlandı" 'DarkGray' -NoNewLine }
if ($script:dlFail -gt 0) { C "  •  !$($script:dlFail) hata"   'Red'      -NoNewLine }
C ""
C "    ─────────────────────────────────────────────────────────────────────────" 'DarkGray'
C ""

if (-not $ok1 -or -not $ok2) {
    C "  [!] Zorunlu dosyalar indirilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin." 'Red'
    C ""
    Read-Host "  Çıkmak için Enter"
    exit 1
}

# ── Başlat (non-blocking → installer konsolu hemen kapanır) ──────────────────
C "  ► Livn Tools başlatılıyor..." 'Cyan'
C ""

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

if ($isAdmin) {
    # Admin → yeni pencerede başlat, bu konsol kapanır
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$install\Main.ps1`""
} else {
    # Admin değil → UAC ile yükselt, bu konsol kapanır
    Start-Process powershell.exe `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$install\Main.ps1`"" `
        -Verb RunAs
}

# Installer konsolunu kapat — Main.ps1 kendi penceresinde açılacak
Start-Sleep -Milliseconds 800
exit 0
