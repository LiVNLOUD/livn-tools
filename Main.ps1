#Requires -Version 5.1
<#
.SYNOPSIS
    Livn Tools v4 — Windows temizlik, optimizasyon ve sistem yönetimi aracı.
.DESCRIPTION
    Giriş noktası: yetki ve STA denetimi, veri klasörünün belirlenmesi, modüllerin
    yüklenmesi ve WPF arayüzünün başlatılması. Tüm işlem mantığı src\ altındadır.
.PARAMETER DataRoot
    Günlük, journal, özgün değer defteri ve yedeklerin tutulduğu klasör.
    Varsayılan: kurulum düzeninde <kök>\data, taşınabilir kullanımda <uygulama>\data.
.PARAMETER DryRun
    KURU ÇALIŞMA: bellek içi sahte bir sistemle açılır; gerçek registry/servis/BCD/ağ
    ayarlarına DOKUNULMAZ. Arayüzü güvenle denemek içindir; yönetici yetkisi gerekmez.
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Main.ps1
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Main.ps1 -DryRun
#>
[CmdletBinding()]
param(
    [string]$DataRoot = '',
    [switch]$DryRun,
    [switch]$NoElevate
)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'
$AppRoot = $PSScriptRoot

function Show-LtFatal([string]$Text) {
    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
        [void][System.Windows.MessageBox]::Show($Text, 'Livn Tools', 'OK', 'Error')
    } catch { Write-Host $Text -ForegroundColor Red }
}

# --- Platform --------------------------------------------------------------
if ($PSVersionTable.PSEdition -eq 'Core' -and -not $IsWindows) {
    Write-Error 'Livn Tools yalnızca Windows üzerinde çalışır (WPF).'
    exit 1
}
if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
    Write-Host 'Livn Tools kısıtlı dil modunda (AppLocker/WDAC) çalışamaz.' -ForegroundColor Red
    exit 1
}

function Get-LtHostPath {
    <# Her zaman 64-bit Windows PowerShell 5.1 (32-bit, PowerShell 7 veya ISE degil). #>
    $sys = if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { 'Sysnative' } else { 'System32' }
    return (Join-Path $env:SystemRoot "$sys\WindowsPowerShell\v1.0\powershell.exe")
}
function ConvertTo-LtArgument([string]$Value) {
    # Windows komut satiri: tirnaktan once gelen ters egik cizgiler ikiye katlanir ("D:\x\" -> "D:\x\\")
    return '"' + ($Value -replace '(\\+)$', '$1$1') + '"'
}

# --- Yonetici yetkisi (kuru calismada gerekmez) ----------------------------
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$exe = Get-LtHostPath
# Kabuk secenekleri -File'dan ONCE gelmeli; -File sonrasindakiler betik parametresidir.
$hostArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden')
$passArgs = @('-File', (ConvertTo-LtArgument $PSCommandPath))
if ($DataRoot) { $passArgs += @('-DataRoot', (ConvertTo-LtArgument $DataRoot)) }
if ($DryRun) { $passArgs += '-DryRun' }

# Yanlis kabuk (32-bit PowerShell, PowerShell 7, ISE): dogru kabukla bastan baslat (bir kez)
$wrongHost = ($PSVersionTable.PSEdition -eq 'Core') -or ($Host.Name -ne 'ConsoleHost') -or
    ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess)
if ($wrongHost) {
    if ($env:LIVNTOOLS_HOSTFIX -eq '1') { Show-LtFatal "Livn Tools 64-bit Windows PowerShell 5.1 ile başlatılamadı (kabuk: $($Host.Name), $($PSVersionTable.PSVersion))."; exit 1 }
    if (-not (Test-Path -LiteralPath $exe)) { Show-LtFatal "Windows PowerShell 5.1 bulunamadı: $exe"; exit 1 }
    $env:LIVNTOOLS_HOSTFIX = '1'
    $fixArgs = $passArgs
    if ($NoElevate) { $fixArgs += '-NoElevate' }
    Start-Process -FilePath $exe -ArgumentList ($hostArgs + $fixArgs) -WindowStyle Hidden
    exit 0
}

if (-not $isAdmin -and -not $DryRun) {
    if ($NoElevate) { Show-LtFatal 'Livn Tools yönetici yetkisi gerektirir. PowerShell''i "Yönetici olarak çalıştır" ile açın.'; exit 1 }
    try {
        Start-Process -FilePath $exe -ArgumentList ($hostArgs + $passArgs + '-NoElevate') -Verb RunAs -WindowStyle Hidden -ErrorAction Stop
    } catch {
        Show-LtFatal "Yönetici yetkisi alınamadı (UAC reddedildi veya engellendi):`n$($_.Exception.Message)"
        exit 1
    }
    exit 0
}

# --- WPF icin STA -----------------------------------------------------------
if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    Start-Process -FilePath $exe -ArgumentList ($hostArgs + $passArgs + '-NoElevate') -WindowStyle Hidden
    exit 0
}

# --- Veri klasoru -----------------------------------------------------------
# Kurulum duzeni (win.ps1):  <kok>\app\Main.ps1  +  <kok>\data  +  <kok>\.livntools-root
# Tasinabilir (ZIP/git):     <uygulama>\Main.ps1 +  <uygulama>\data
if (-not $DataRoot) {
    if ($env:LIVNTOOLS_DATA) { $DataRoot = $env:LIVNTOOLS_DATA }
    else {
        $parent = Split-Path -Parent $AppRoot
        if ($parent -and (Test-Path -LiteralPath (Join-Path $parent '.livntools-root'))) { $DataRoot = Join-Path $parent 'data' }
        else { $DataRoot = Join-Path $AppRoot 'data' }
    }
}
if ($DryRun) { $DataRoot = Join-Path $DataRoot 'dryrun' }

# --- Moduller ve arayuz -----------------------------------------------------
try {
    Import-Module (Join-Path $AppRoot 'src\LivnTools.psm1') -DisableNameChecking -Force
    . (Join-Path $AppRoot 'src\UI\ViewModels.ps1')
    . (Join-Path $AppRoot 'src\UI\Dialogs.ps1')
    . (Join-Path $AppRoot 'src\UI\App.ps1')
} catch {
    Show-LtFatal "Livn Tools dosyaları yüklenemedi. Kurulum eksik veya bozuk olabilir; win.ps1 ile yeniden kurun.`n`n$($_.Exception.Message)"
    exit 1
}

try {
    if ($DryRun) {
        Initialize-LivnTools -DataRoot $DataRoot -Backend Memory
        [void](Initialize-LtMemoryDemo)
        Start-LtApp -AppRoot $AppRoot -DataRoot $DataRoot -Backend Memory
    } else {
        Start-LtApp -AppRoot $AppRoot -DataRoot $DataRoot -Backend Windows
    }
} catch {
    $msg = "Beklenmeyen hata: $($_.Exception.Message)`n`n$($_.ScriptStackTrace)"
    try {
        $log = Join-Path $DataRoot 'logs'
        if (-not (Test-Path -LiteralPath $log)) { New-Item -ItemType Directory -Path $log -Force | Out-Null }
        Add-Content -LiteralPath (Join-Path $log 'crash.log') -Value ("[{0}] {1}" -f (Get-Date -Format 's'), $msg) -Encoding UTF8
    } catch { $null = $_ }
    Show-LtFatal $msg
    exit 1
}
