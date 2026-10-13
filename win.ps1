<#
.SYNOPSIS
    Livn Tools - kurulum ve guncelleme.
.DESCRIPTION
    Kullanim (PowerShell):   irm livn.tr/win | iex
    Parametreli kullanim:    & ([scriptblock]::Create((irm livn.tr/win))) -NoLaunch
                             & ([scriptblock]::Create((irm livn.tr/win))) -Rollback

    Guvenlik ve butunluk:
    - Dosyalar SURUME SABITLENMIS git etiketinden indirilir (main dalindan degil).
    - Her dosyanin boyutu ve SHA-256 ozeti bu betikteki bildirimle karsilastirilir.
      Bu, kesilmis/bozuk indirmeleri ve etiketteki icerigin beklenenden farkli olmasini
      yakalar. YAYINCI KIMLIGINI KANITLAMAZ: bu betik de ayni kaynaktan (GitHub/HTTPS)
      geldigi icin imza (Authenticode) yerine gecmez; projede imza altyapisi yoktur.
    - Dosyalar once gecici bir klasore indirilir; hepsi dogrulanmadan mevcut kurulum
      degistirilmez. Degistirme klasor yeniden adlandirma ile yapilir; hata olursa
      onceki surum geri konur. Onceki surum app.prev klasorunde saklanir (-Rollback).
    - Kullanici verileri (<kok>\data: gunluk, journal, ozgun deger defteri, yedekler)
      guncellemede hicbir zaman silinmez veya uzerine yazilmaz.
#>
[CmdletBinding()]
param(
    [string]$InstallRoot = '',
    [switch]$Rollback,
    [switch]$NoLaunch,
    [string]$SourceOverride = ''   # yalnizca test/yerel dagitim: http(s) kok URL'si veya yerel klasor
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest ilerleme cubugu PS 5.1'de indirmeyi cok yavaslatir

# === SURUM BILDIRIMI ========================================================
# tools\Build-Release.ps1 tarafindan uretilir; elle duzenlemeyin.
# BEGIN RELEASE MANIFEST
$LtRelease = @{
    Version = '4.0.0'
    Tag     = 'v4.0.0'
    BaseUrl = 'https://raw.githubusercontent.com/LiVNLOUD/livn-tools/v4.0.0'
    Files   = @(
        @{ Path = 'CHANGELOG.md'; Size = 38708; Sha256 = '2DD01036D3F6772286A65719AD2E6EAAF11C697BF759C10D8C816316574C3F59' }
        @{ Path = 'docs/ARCHITECTURE.md'; Size = 9663; Sha256 = '6A3AAC3CF18019DA33F4F5CA528BAF38DB5C11DCFAAB21C8B803E34F892C0901' }
        @{ Path = 'docs/DEVELOPMENT_STATUS.md'; Size = 2745; Sha256 = '0768D7121DD95244C9492D870D827A54051E0D0F5D41415A342178A32A850B68' }
        @{ Path = 'docs/KESKE_LISTESI.md'; Size = 8255; Sha256 = 'B742C4BCFE912668E6FE45C93CD9DC5FEAC0D2701038C4D32C86C20AA956C26E' }
        @{ Path = 'docs/REVIEW_PAGEFILE.md'; Size = 4012; Sha256 = '4EB0829CBFB8C286A061CB82CAB1D6B45EA96EF79DE53F98526B66E64B40C57C' }
        @{ Path = 'docs/REVIEW_R3.md'; Size = 11431; Sha256 = 'D1E4543B9167E5FA2C2C72F717F75C4433EDF6EEFBC14D77B88599A4853DD652' }
        @{ Path = 'docs/SUPPORT_MATRIX.md'; Size = 8878; Sha256 = '0E38161E78D1EDDB9C0A3284189F52966D0CA382C6616A40D1A7C272B438E966' }
        @{ Path = 'docs/THIRD_PARTY.md'; Size = 7476; Sha256 = '59EDA4CB2BCB7914DC806983A5BB94BF992AD48AD4A5B9DED86D8C8CC1E49225' }
        @{ Path = 'docs/TWEAK_AUDIT.md'; Size = 22169; Sha256 = '1236C6108B2CF19E6E47A8668FBA0E4D65752188409B8AD2E4775F3727C247F9' }
        @{ Path = 'docs/USAGE.md'; Size = 19866; Sha256 = '87FE0FC3228367737AB1676B422D708328B125A42C94081A9D6E2F12BA3A580A' }
        @{ Path = 'docs/WINDOWS_TEST_CHECKLIST.md'; Size = 33414; Sha256 = '3890F95F6C62EDBE94F9D768DCF160C8ECC74647019F4364EBE42375DC6A0914' }
        @{ Path = 'LivnTools.bat'; Size = 2278; Sha256 = '20B28E1486B88D28873CA368779A40ECE05D6E61698876C38834FCE19F53581B' }
        @{ Path = 'Main.ps1'; Size = 6363; Sha256 = '4790E81D08E153FD6D1D295ABEAACF048DE158A4D67FEFEAB192AD2DC75D7D65' }
        @{ Path = 'README.md'; Size = 8048; Sha256 = 'A4DFEDD017A2F9408C60FD174352200FBB99FD1479D33E16B46AB260E5675D70' }
        @{ Path = 'src/Catalog/Helpers.ps1'; Size = 10267; Sha256 = 'F320CF42A45B89717B0795DABF89A5844E5F093D7924EA09FDB71A2E13E2125E' }
        @{ Path = 'src/Catalog/Tweaks.ps1'; Size = 74397; Sha256 = 'D4C8F119E58D6EC1F01AF5F2B86518C3E9507C70A6D8643B5E79DE0510A4B44F' }
        @{ Path = 'src/Cleanup.ps1'; Size = 65290; Sha256 = '6D535FED84825E6E7D57B7170D5845CDE9FB5EE6AEF1C6B6149E94F6D090D453' }
        @{ Path = 'src/Core/Backend.ps1'; Size = 60834; Sha256 = 'DEF81078807CC1BA599C9311244F35CD8F77000D0B4F4E77B9137738387D14D2' }
        @{ Path = 'src/Core/Common.ps1'; Size = 21413; Sha256 = '7DE8A71B467EC4BA9FA477B400A4F69A171446FDC6E5D8D85913167A5E21E9C6' }
        @{ Path = 'src/Core/Demo.ps1'; Size = 7086; Sha256 = 'ACF8D3836D5A5F36D59973CE7C0AD4320D5047CA6B3CE8A8384898650BE502E0' }
        @{ Path = 'src/Core/Journal.ps1'; Size = 7595; Sha256 = '390695D2985120336138EA85E694F0E28D3F8E41B08CE8A8936B80E916906EF5' }
        @{ Path = 'src/Core/Providers.ps1'; Size = 24526; Sha256 = 'A7468FCBFDECA04B5BF6EDB5173C3EC80D608CF83E359BE5F03290BC08D52CF7' }
        @{ Path = 'src/Core/SideEffects.ps1'; Size = 26731; Sha256 = 'AA6EFC0CCC721464AA6EEB6A8DDECD24253525247BC64E1CCA2C67B75EC17301' }
        @{ Path = 'src/Core/SystemInfo.ps1'; Size = 24463; Sha256 = 'B59C43D6F8506051812570AFD6778F72D52D2345DC83D479CB992EF09D30FDC6' }
        @{ Path = 'src/Engine.ps1'; Size = 36641; Sha256 = 'EA51AF416BC166B9B980145D8EBC892A46CA30E6586DE784C93D7BF1256CA203' }
        @{ Path = 'src/Health.ps1'; Size = 35221; Sha256 = 'EA5A0360F42690DC001529CD6F052418B38D3463CAA46196558DD9B98D9F23F1' }
        @{ Path = 'src/LivnTools.psm1'; Size = 1469; Sha256 = 'A3A7FA27E1BEE9B68B4ED38C3A8256678B497549D926D60BD9D1B947299FDAB3' }
        @{ Path = 'src/Network.ps1'; Size = 22840; Sha256 = '934296C6006455F0DEA3346C4362AACB4B2DB6744FA4A3E6A4B7364823F813E1' }
        @{ Path = 'src/RecoveryKit.ps1'; Size = 38718; Sha256 = '328FDD3918A033B6999E33A955B7199425C9C0C187C742D270115DC718FF64A3' }
        @{ Path = 'src/Setup.ps1'; Size = 20484; Sha256 = '378C91987B43029639A81B6A2D6EC9F27BFF024DD28A1DB7182766585F711D64' }
        @{ Path = 'src/Startup.ps1'; Size = 5093; Sha256 = 'AA2E7983F7D58DE6E826BFCD26A41F0E86D0DC1564E67973026C64758338CEBC' }
        @{ Path = 'src/UI/App.ps1'; Size = 118215; Sha256 = 'A4376A832FC6C5333CE70538683E8D2D9E73C36872B85689D38D2C88DAAD42E1' }
        @{ Path = 'src/UI/Dialogs.ps1'; Size = 10114; Sha256 = 'C1BAA7762A4E665A86B719AA5815F0C65C4D597E4F8C374EA743F1394DB09501' }
        @{ Path = 'src/UI/MainWindow.xaml'; Size = 91382; Sha256 = '39F5B966E52C1C90353F8B0A399CE8A2E3855D409D19B78C4E4C3C56F3B9CB0D' }
        @{ Path = 'src/UI/ViewModels.ps1'; Size = 5796; Sha256 = '6B27FA22F1253B317E66D6BE557DF1A0CBA84814A13655A8F4B3555AFF45642C' }
    )
}
# END RELEASE MANIFEST
# ============================================================================

function Write-LtInstall([string]$Text, [string]$Color = 'Gray') { Write-Host "  $Text" -ForegroundColor $Color }

function Get-LtInstallRoot {
    param([string]$Requested, [string]$Documents = [Environment]::GetFolderPath('MyDocuments'), [string]$LocalAppData = [Environment]::GetFolderPath('LocalApplicationData'))
    if ($Requested) { return $Requested }
    # Onceki surumler Belgeler altina kuruyordu: mevcut kurulum (v4 veya v3.5) yerinde
    # guncellenir, boylece gecmis kayitlari ve yedekler ayni veri klasorunde kalir.
    $legacy = Join-Path $Documents 'LivnTools'
    if ((Test-Path -LiteralPath (Join-Path $legacy '.livntools-root')) -or (Test-Path -LiteralPath (Join-Path $legacy 'Main.ps1'))) { return $legacy }
    # Yeni kurulum: Belgeler degil (Denetimli klasor erisimi / OneDrive esitlemesi yazmayi engelleyebilir)
    return (Join-Path $LocalAppData 'LivnTools')
}

function Get-LtWindowsPowerShellPath {
    <# Her zaman 64-bit Windows PowerShell 5.1 (32-bit, PowerShell 7 veya ISE degil). #>
    $sys = if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { 'Sysnative' } else { 'System32' }
    return (Join-Path $env:SystemRoot "$sys\WindowsPowerShell\v1.0\powershell.exe")
}

function Test-LtFileIntegrity {
    <# Boyut ve SHA-256 esitligi. Dosyanin var olmasi TEK BASINA basari sayilmaz. #>
    param([string]$Path, [long]$Size, [string]$Sha256)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    if ((Get-Item -LiteralPath $Path).Length -ne $Size) { return $false }
    return ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -eq $Sha256.ToUpperInvariant())
}

# Indirici tek bir yerde; testler bunu yerel kopyalayici ile degistirir.
$script:LtDownloader = {
    param([string]$Url, [string]$Destination)
    if ($Url -notmatch '^https?://') {
        Copy-Item -LiteralPath $Url -Destination $Destination -Force
        return
    }
    try {
        Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
    } catch {
        $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
        if (-not $curl) { throw }
        & $curl.Source --fail --silent --show-error --location --proto '=https' --tlsv1.2 --max-time 120 -o $Destination $Url
        if ($LASTEXITCODE -ne 0) { throw "curl.exe $([char]0x00E7)$([char]0x0131)k$([char]0x0131)$([char]0x015F) kodu $LASTEXITCODE" }
    }
}

function Save-LtReleaseFile {
    <# Dosyayi indirir ve dogrular (3 deneme). Basarisizlikta istisna. #>
    param([string]$BaseUrl, [hashtable]$File, [string]$StagingRoot)
    $rel = $File.Path -replace '/', '\'
    $dest = Join-Path $StagingRoot $rel
    $dir = Split-Path -Parent $dest
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    if ($BaseUrl -match '^https?://') {
        $encoded = (($File.Path -split '/') | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
        $url = $BaseUrl.TrimEnd('/') + '/' + $encoded
    } else {
        $url = Join-Path $BaseUrl $rel
    }
    $downloader = Get-Variable -Name LtDownloaderOverride -ValueOnly -ErrorAction SilentlyContinue   # yalnizca testler
    if (-not $downloader) { $downloader = $script:LtDownloader }
    $last = ''
    for ($i = 1; $i -le 3; $i++) {
        try {
            if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Force }
            & $downloader $url $dest
            if (Test-LtFileIntegrity -Path $dest -Size $File.Size -Sha256 $File.Sha256) { return $dest }
            $got = if (Test-Path -LiteralPath $dest) { (Get-Item -LiteralPath $dest).Length } else { 0 }
            $last = "b$([char]0x00FC)t$([char]0x00FC)nl$([char]0x00FC)k do$([char]0x011F)rulanamad$([char]0x0131) (beklenen $($File.Size) bayt, al$([char]0x0131)nan $got bayt)"
        } catch {
            $last = $_.Exception.Message
        }
        Start-Sleep -Milliseconds (400 * $i)
    }
    throw "$($File.Path): $last"
}

function Move-LtLegacyLayout {
    <# v3.5 duzeni (<kok>\Main.ps1, <kok>\_Files\...) -> yedekleri data'ya, eski dosyalari legacy klasorune tasir. SILMEZ. #>
    param([string]$Root)
    $oldMain = Join-Path $Root 'Main.ps1'
    if (-not (Test-Path -LiteralPath $oldMain)) { return }
    $legacyData = Join-Path $Root 'data\legacy-v3.5'
    $legacyApp = Join-Path $Root ('legacy-v3.5-app-' + (Get-Date -Format 'yyyyMMddHHmmss'))
    New-Item -ItemType Directory -Path $legacyData -Force | Out-Null
    New-Item -ItemType Directory -Path $legacyApp -Force | Out-Null
    foreach ($sub in @('Backups', 'Logs')) {
        $src = Join-Path $Root "_Files\$sub"
        if (Test-Path -LiteralPath $src) { Move-Item -LiteralPath $src -Destination (Join-Path $legacyData $sub) -Force }
    }
    foreach ($item in @('Main.ps1', 'LivnTools.bat', 'win.ps1', 'README.md', '_Files')) {
        $p = Join-Path $Root $item
        if (Test-Path -LiteralPath $p) { Move-Item -LiteralPath $p -Destination (Join-Path $legacyApp $item) -Force }
    }
    Write-LtInstall "v3.5 kurulumu ta$([char]0x015F)$([char]0x0131)nd$([char]0x0131): yedekler -> $legacyData, eski dosyalar -> $legacyApp" 'DarkYellow'
}

function Write-LtLauncher([string]$Root) {
    # Uygulamanin kendi baslaticisi (64-bit PowerShell secimi ve ilke on kontrolu) koke kopyalanir
    $appBat = Join-Path $Root 'app\LivnTools.bat'
    if (Test-Path -LiteralPath $appBat) {
        Copy-Item -LiteralPath $appBat -Destination (Join-Path $Root 'LivnTools.bat') -Force
    } else {
        $bat = @(
            '@echo off',
            ':: Livn Tools baslatici (win.ps1 tarafindan olusturuldu)',
            'set "LT_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"',
            'if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "LT_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"',
            'start "" "%LT_PS%" -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0app\Main.ps1" %*'
        ) -join "`r`n"
        [IO.File]::WriteAllText((Join-Path $Root 'LivnTools.bat'), $bat + "`r`n", [Text.Encoding]::ASCII)
    }
    [IO.File]::WriteAllText((Join-Path $Root '.livntools-root'), "Livn Tools kurulum k$([char]0x00F6)k$([char]0x00FC). Bu dosyay$([char]0x0131) silmeyin.`r`n", (New-Object Text.UTF8Encoding($false)))
}

function Write-LtStartMenuShortcut([string]$Root) {
    <# Baslat menusu kisayolu (kullanici kapsami). Basarisizlik kurulumu bozmaz. #>
    if ($env:LIVNTOOLS_INSTALLER_NOSHORTCUT -or -not ($env:OS -eq 'Windows_NT')) { return $null }
    try {
        $programs = [Environment]::GetFolderPath('Programs')
        if (-not $programs) { return $null }
        $lnk = Join-Path $programs 'Livn Tools.lnk'
        $shell = New-Object -ComObject WScript.Shell
        $sc = $shell.CreateShortcut($lnk)
        $sc.TargetPath = Join-Path $Root 'LivnTools.bat'
        $sc.WorkingDirectory = $Root
        $sc.WindowStyle = 7
        $sc.Description = 'Livn Tools'
        $sc.Save()
        return $lnk
    } catch {
        Write-LtInstall "Ba$([char]0x015F)lat men$([char]0x00FC)s$([char]0x00FC) k$([char]0x0131)sayolu olu$([char]0x015F)turulamad$([char]0x0131): $($_.Exception.Message)" 'DarkYellow'
        return $null
    }
}

function Invoke-LtInstall {
    [CmdletBinding()]
    param([string]$InstallRoot = '', [switch]$Rollback, [switch]$NoLaunch, [string]$SourceOverride = '')
    $root = Get-LtInstallRoot $InstallRoot
    $app = Join-Path $root 'app'
    $prev = Join-Path $root 'app.prev'
    if (-not (Test-Path -LiteralPath $root)) { New-Item -ItemType Directory -Path $root -Force | Out-Null }
    New-Item -ItemType Directory -Path (Join-Path $root 'data') -Force | Out-Null

    if ($Rollback) {
        if (-not (Test-Path -LiteralPath $prev)) { throw "Geri d$([char]0x00F6)n$([char]0x00FC)lecek $([char]0x00F6)nceki s$([char]0x00FC)r$([char]0x00FC)m (app.prev) yok." }
        $tmp = Join-Path $root ('app.rollback-' + [guid]::NewGuid().ToString('N'))
        if (Test-Path -LiteralPath $app) { Rename-Item -LiteralPath $app -NewName (Split-Path -Leaf $tmp) }
        try { Rename-Item -LiteralPath $prev -NewName 'app' }
        catch { if (Test-Path -LiteralPath $tmp) { Rename-Item -LiteralPath $tmp -NewName 'app' }; throw }
        if (Test-Path -LiteralPath $tmp) { Rename-Item -LiteralPath $tmp -NewName 'app.prev' }
        Write-LtInstall "$([char]0x00D6)nceki s$([char]0x00FC)r$([char]0x00FC)me d$([char]0x00F6)n$([char]0x00FC)ld$([char]0x00FC)." 'Green'
        return @{ Status = 'RolledBack'; Root = $root }
    }

    if (@($LtRelease.Files).Count -eq 0) { throw "S$([char]0x00FC)r$([char]0x00FC)m bildirimi bo$([char]0x015F): bu win.ps1 bir s$([char]0x00FC)r$([char]0x00FC)m i$([char]0x00E7)in olu$([char]0x015F)turulmam$([char]0x0131)$([char]0x015F) (tools\Build-Release.ps1)." }
    $base = if ($SourceOverride) { $SourceOverride } else { $LtRelease.BaseUrl }
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { $null = $_ }

    $staging = Join-Path $root ('.staging-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $staging -Force | Out-Null
    Write-LtInstall "Livn Tools $($LtRelease.Version) indiriliyor ($(@($LtRelease.Files).Count) dosya)..." 'Cyan'
    try {
        $n = 0
        foreach ($f in $LtRelease.Files) {
            [void](Save-LtReleaseFile -BaseUrl $base -File $f -StagingRoot $staging)
            $n++
            Write-LtInstall ("[{0,2}/{1}] {2}" -f $n, @($LtRelease.Files).Count, $f.Path) 'DarkGray'
        }
        $meta = @{ version = $LtRelease.Version; tag = $LtRelease.Tag; installedAt = (Get-Date).ToString('o'); files = @($LtRelease.Files | ForEach-Object { $_.Path }) }
        [IO.File]::WriteAllText((Join-Path $staging 'VERSION.json'), (ConvertTo-Json $meta -Depth 4), (New-Object Text.UTF8Encoding($false)))
    } catch {
        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
        Write-LtInstall "$([char]0x0130)ndirme/do$([char]0x011F)rulama ba$([char]0x015F)ar$([char]0x0131)s$([char]0x0131)z: $($_.Exception.Message)" 'Red'
        Write-LtInstall "Mevcut kurulum DE$([char]0x011E)$([char]0x0130)$([char]0x015E)T$([char]0x0130)R$([char]0x0130)LMED$([char]0x0130)." 'Yellow'
        throw
    }

    Move-LtLegacyLayout -Root $root

    # Atomik degistirme: app -> app.prev, staging -> app (hata olursa geri al)
    $oldPrev = $null
    if (Test-Path -LiteralPath $prev) {
        $oldPrev = Join-Path $root ('app.prev-old-' + [guid]::NewGuid().ToString('N'))
        Rename-Item -LiteralPath $prev -NewName (Split-Path -Leaf $oldPrev)
    }
    $movedOld = $false
    try {
        if (Test-Path -LiteralPath $app) { Rename-Item -LiteralPath $app -NewName 'app.prev'; $movedOld = $true }
        Rename-Item -LiteralPath $staging -NewName 'app'
    } catch {
        $err = $_.Exception.Message
        if ($movedOld -and -not (Test-Path -LiteralPath $app)) { Rename-Item -LiteralPath $prev -NewName 'app' }
        if ($oldPrev -and -not (Test-Path -LiteralPath $prev)) { Rename-Item -LiteralPath $oldPrev -NewName 'app.prev'; $oldPrev = $null }
        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
        Write-LtInstall "Dosyalar yerine konamad$([char]0x0131) (uygulama a$([char]0x00E7)$([char]0x0131)k olabilir): $err. $([char]0x00D6)nceki s$([char]0x00FC)r$([char]0x00FC)m korundu." 'Red'
        throw
    }
    if ($oldPrev) { Remove-Item -LiteralPath $oldPrev -Recurse -Force -ErrorAction SilentlyContinue }
    Write-LtLauncher -Root $root
    $shortcut = Write-LtStartMenuShortcut -Root $root
    Write-LtInstall "Kuruldu: $app" 'Green'
    if ($shortcut) { Write-LtInstall "Ba$([char]0x015F)lat men$([char]0x00FC)s$([char]0x00FC): Livn Tools" 'DarkGray' }
    Write-LtInstall "Kullan$([char]0x0131)c$([char]0x0131) verileri korunur: $(Join-Path $root 'data')" 'DarkGray'

    if (-not $NoLaunch) {
        # pwsh 7, ISE veya 32-bit kabuktan cagrilsa da uygulama 64-bit Windows PowerShell 5.1 ile acilir
        $exe = Get-LtWindowsPowerShellPath
        # Main.ps1 yonetici yetkisini kendisi ister (UAC)
        Start-Process -FilePath $exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden', '-File', "`"$(Join-Path $app 'Main.ps1')`"")
        Write-LtInstall "Livn Tools ba$([char]0x015F)lat$([char]0x0131)l$([char]0x0131)yor..." 'Cyan'
    }
    return @{ Status = 'Installed'; Root = $root; Version = $LtRelease.Version }
}

if (-not $env:LIVNTOOLS_INSTALLER_NOAUTORUN) {
    try {
        [void](Invoke-LtInstall -InstallRoot $InstallRoot -Rollback:$Rollback -NoLaunch:$NoLaunch -SourceOverride $SourceOverride)
    } catch {
        Write-LtInstall "Kurulum tamamlanamad$([char]0x0131): $($_.Exception.Message)" 'Red'
        if ($Host.Name -eq 'ConsoleHost') { Write-LtInstall "$([char]0x00C7)$([char]0x0131)kmak i$([char]0x00E7)in Enter'a bas$([char]0x0131)n." 'DarkGray'; [void](Read-Host) }
    }
}
