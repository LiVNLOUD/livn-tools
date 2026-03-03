# Livn Tools v3.5 — Installer
# irm livn.tr/win | iex

# Tum hata ve uyari stream'lerini sustur — kirmizi flash onleme
$ErrorActionPreference = 'SilentlyContinue'
$WarningPreference     = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'
$VerbosePreference     = 'SilentlyContinue'

# TLS 1.2
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$repo    = "https://raw.githubusercontent.com/LiVNLOUD/livn-tools/main"
$install = "$env:USERPROFILE\Documents\LivnTools"

# ── Renk yardımcısı ───────────────────────────────────────────────────────────
function C([string]$txt,[string]$fg='White',[switch]$nl) {
    if ($nl) { Write-Host $txt -ForegroundColor $fg -NoNewline }
    else      { Write-Host $txt -ForegroundColor $fg }
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
if (-not (Test-Path $install)) {
    New-Item -ItemType Directory -Path $install -Force 2>$null | Out-Null
}
C "  ► " 'DarkGray' -nl; C "Kurulum klasörü: " 'DarkGray' -nl; C $install 'White'
C ""

# ── İndirme sayaçları ─────────────────────────────────────────────────────────
$script:dlOK   = 0
$script:dlFail = 0
$script:dlSkip = 0

# ── İndirme fonksiyonu ────────────────────────────────────────────────────────
function Get-File([string]$Url, [string]$Dest, [bool]$Optional=$false) {
    $label = Split-Path $Dest -Leaf
    $dir   = Split-Path $Dest -Parent

    # Alt klasör yoksa oluştur
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force 2>$null | Out-Null
    }

    $ok = $false

    # Yöntem 1: Invoke-WebRequest
    if (-not $ok) {
        try {
            Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing `
                -TimeoutSec 30 -ErrorAction Stop 2>$null
            $ok = (Test-Path $Dest)
        } catch {}
    }

    # Yöntem 2: curl.exe (sadece mevcutsa çalıştır)
    if (-not $ok) {
        $curlExe = Get-Command 'curl.exe' -ErrorAction SilentlyContinue
        if ($curlExe) {
            try {
                $null = & $curlExe.Source -sS -L --tlsv1.2 -o $Dest $Url 2>$null
                $ok = (Test-Path $Dest)
            } catch {}
        }
    }

    # Yöntem 3: BitsTransfer
    if (-not $ok) {
        try {
            $null = Import-Module BitsTransfer -ErrorAction Stop 2>$null 3>$null
            Start-BitsTransfer -Source $Url -Destination $Dest -ErrorAction Stop 2>$null
            $ok = (Test-Path $Dest)
        } catch {}
    }

    if ($ok) {
        C "    [+] " 'Green' -nl; C $label 'White'
        $script:dlOK++
        return $true
    } elseif ($Optional) {
        C "    [-] " 'DarkGray' -nl; C "$label  (atlandı)" 'DarkGray'
        $script:dlSkip++
        return $true
    } else {
        C "    [!] " 'Red' -nl; C "$label  — indirilemedi" 'Yellow'
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
C "    Güç planları:" 'DarkGray'
$null = Get-File "$repo/_Files/Bitsum-Highest-Performance.pow"                "$install\_Files\Bitsum-Highest-Performance.pow"                $true
$null = Get-File "$repo/_Files/HybredPowerPlans/HybredLowLatencyHighPerf.pow" "$install\_Files\HybredPowerPlans\HybredLowLatencyHighPerf.pow" $true
$null = Get-File "$repo/_Files/HybredPowerPlans/HybredLowLatencyBalanced.pow" "$install\_Files\HybredPowerPlans\HybredLowLatencyBalanced.pow" $true
$null = Get-File "$repo/_Files/Win32Prio_Balanced_TheHybred.reg"               "$install\_Files\Win32Prio_Balanced_TheHybred.reg"               $true
$null = Get-File "$repo/_Files/Win32Prio_BestFPS_TheHybred.reg"                "$install\_Files\Win32Prio_BestFPS_TheHybred.reg"                $true
$null = Get-File "$repo/_Files/Win32Prio_Default_TheHybred.reg"                "$install\_Files\Win32Prio_Default_TheHybred.reg"                $true

C ""
C "    ISLC:" 'DarkGray'
$null = Get-File "$repo/_Files/ISLC/Intelligent standby list cleaner ISLC.exe" "$install\_Files\ISLC\Intelligent standby list cleaner ISLC.exe" $true
$null = Get-File "$repo/_Files/ISLC/Intelligent standby list cleaner ISLC.pdb" "$install\_Files\ISLC\Intelligent standby list cleaner ISLC.pdb" $true
$null = Get-File "$repo/_Files/ISLC/ReadMe_ISLC.txt"                           "$install\_Files\ISLC\ReadMe_ISLC.txt"                           $true

# ── Özet ──────────────────────────────────────────────────────────────────────
C ""
C "    ─────────────────────────────────────────────────────────────────────────" 'DarkGray'
C "      İndirme: " 'DarkGray' -nl
C "+$($script:dlOK) başarılı" 'Green' -nl
if ($script:dlSkip -gt 0) { C "  •  -$($script:dlSkip) atlandı" 'DarkGray' -nl }
if ($script:dlFail -gt 0) { C "  •  !$($script:dlFail) hata"   'Red'      -nl }
C ""
C "    ─────────────────────────────────────────────────────────────────────────" 'DarkGray'
C ""

if (-not $ok1 -or -not $ok2) {
    C "  [!] Zorunlu dosyalar indirilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin." 'Red'
    C ""
    Read-Host "  Çıkmak için Enter" | Out-Null
    exit 1
}

# ── Başlat ────────────────────────────────────────────────────────────────────
C "  ► " 'Cyan' -nl; C "Livn Tools başlatılıyor..." 'White'
C ""

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

# WindowStyle Hidden: Main.ps1'in boş konsol penceresi görünmez, sadece WPF açılır
if ($isAdmin) {
    Start-Process powershell.exe `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$install\Main.ps1`"" `
        -WindowStyle Hidden
} else {
    Start-Process powershell.exe `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$install\Main.ps1`"" `
        -WindowStyle Hidden -Verb RunAs
}

# Kısa bekleme, ardından bu installer konsolu açık kalır
Start-Sleep -Milliseconds 1200
C "  ✓ " 'Green' -nl; C "Uygulama başlatıldı." 'White'
C ""
