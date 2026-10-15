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
    Version = '4.0.1'
    Tag     = 'v4.0.1'
    BaseUrl = 'https://raw.githubusercontent.com/LiVNLOUD/livn-tools/v4.0.1'
    Files   = @(
        @{ Path = 'CHANGELOG.md'; Size = 39149; Sha256 = '4557FC79FDEF9E665577584D982C196987800B4A5B52B6524BC92A4AC48B8B3E' }
        @{ Path = 'docs/ARCHITECTURE.md'; Size = 9663; Sha256 = '6A3AAC3CF18019DA33F4F5CA528BAF38DB5C11DCFAAB21C8B803E34F892C0901' }
        @{ Path = 'docs/DEVELOPMENT_STATUS.md'; Size = 3653; Sha256 = '5FAF8D2656193B295FF148913BAB02238B5B5FEFC7B6B58F611ACA4F8C7813F3' }
        @{ Path = 'docs/KESKE_LISTESI.md'; Size = 8255; Sha256 = 'B742C4BCFE912668E6FE45C93CD9DC5FEAC0D2701038C4D32C86C20AA956C26E' }
        @{ Path = 'docs/REVIEW_PAGEFILE.md'; Size = 4012; Sha256 = '4EB0829CBFB8C286A061CB82CAB1D6B45EA96EF79DE53F98526B66E64B40C57C' }
        @{ Path = 'docs/REVIEW_R3.md'; Size = 11431; Sha256 = 'D1E4543B9167E5FA2C2C72F717F75C4433EDF6EEFBC14D77B88599A4853DD652' }
        @{ Path = 'docs/SUPPORT_MATRIX.md'; Size = 9386; Sha256 = '4F2F148CB1CF7A0F42C7FB0ED640442011EA242450FE2DBCA62E378939E87303' }
        @{ Path = 'docs/THIRD_PARTY.md'; Size = 8916; Sha256 = '62879F8DD7CB515DB8563CFC0B324856A85EBB4FC594091BB77A1FE66BBA4A21' }
        @{ Path = 'docs/TWEAK_AUDIT.md'; Size = 22169; Sha256 = '1236C6108B2CF19E6E47A8668FBA0E4D65752188409B8AD2E4775F3727C247F9' }
        @{ Path = 'docs/USAGE.md'; Size = 19798; Sha256 = '4179C7769D43893E096D5047E0C0E76F00175E39C6FFB07F98D8F9BB1BF3EEDF' }
        @{ Path = 'docs/WINDOWS_TEST_CHECKLIST.md'; Size = 33414; Sha256 = '3890F95F6C62EDBE94F9D768DCF160C8ECC74647019F4364EBE42375DC6A0914' }
        @{ Path = 'LivnTools.bat'; Size = 2278; Sha256 = '20B28E1486B88D28873CA368779A40ECE05D6E61698876C38834FCE19F53581B' }
        @{ Path = 'Main.ps1'; Size = 6363; Sha256 = '4790E81D08E153FD6D1D295ABEAACF048DE158A4D67FEFEAB192AD2DC75D7D65' }
        @{ Path = 'README.md'; Size = 8393; Sha256 = '82DE73176B41A8771F82510B73C86AC84BF550F84A8AB8F857202A9E0D5DA4C2' }
        @{ Path = 'src/Catalog/Helpers.ps1'; Size = 10267; Sha256 = 'F320CF42A45B89717B0795DABF89A5844E5F093D7924EA09FDB71A2E13E2125E' }
        @{ Path = 'src/Catalog/Tweaks.ps1'; Size = 74397; Sha256 = 'D4C8F119E58D6EC1F01AF5F2B86518C3E9507C70A6D8643B5E79DE0510A4B44F' }
        @{ Path = 'src/Cleanup.ps1'; Size = 65290; Sha256 = '6D535FED84825E6E7D57B7170D5845CDE9FB5EE6AEF1C6B6149E94F6D090D453' }
        @{ Path = 'src/Core/Backend.ps1'; Size = 60879; Sha256 = '5B149C5D82087DDA8738AF7EB9DF7341E50767A7343DE5EC75EBBD924B38895E' }
        @{ Path = 'src/Core/Common.ps1'; Size = 21413; Sha256 = '7DE8A71B467EC4BA9FA477B400A4F69A171446FDC6E5D8D85913167A5E21E9C6' }
        @{ Path = 'src/Core/Demo.ps1'; Size = 7086; Sha256 = 'ACF8D3836D5A5F36D59973CE7C0AD4320D5047CA6B3CE8A8384898650BE502E0' }
        @{ Path = 'src/Core/Journal.ps1'; Size = 7595; Sha256 = '390695D2985120336138EA85E694F0E28D3F8E41B08CE8A8936B80E916906EF5' }
        @{ Path = 'src/Core/Providers.ps1'; Size = 24526; Sha256 = 'A7468FCBFDECA04B5BF6EDB5173C3EC80D608CF83E359BE5F03290BC08D52CF7' }
        @{ Path = 'src/Core/SideEffects.ps1'; Size = 26731; Sha256 = 'AA6EFC0CCC721464AA6EEB6A8DDECD24253525247BC64E1CCA2C67B75EC17301' }
        @{ Path = 'src/Core/SystemInfo.ps1'; Size = 24463; Sha256 = 'B59C43D6F8506051812570AFD6778F72D52D2345DC83D479CB992EF09D30FDC6' }
        @{ Path = 'src/Engine.ps1'; Size = 36641; Sha256 = 'EA51AF416BC166B9B980145D8EBC892A46CA30E6586DE784C93D7BF1256CA203' }
        @{ Path = 'src/Health.ps1'; Size = 35221; Sha256 = 'EA5A0360F42690DC001529CD6F052418B38D3463CAA46196558DD9B98D9F23F1' }
        @{ Path = 'src/LivnTools.psm1'; Size = 1469; Sha256 = '4757C38D83111EDD5BAB57CD73EB29065DE2D0C6BDC18DEA50C6739E33BA93F1' }
        @{ Path = 'src/Network.ps1'; Size = 23007; Sha256 = '30590E8E9B9A2E24B12F991994091DC9666AF03B8FC8F4605849101FC8EA992A' }
        @{ Path = 'src/RecoveryKit.ps1'; Size = 38718; Sha256 = '328FDD3918A033B6999E33A955B7199425C9C0C187C742D270115DC718FF64A3' }
        @{ Path = 'src/Setup.ps1'; Size = 20484; Sha256 = '378C91987B43029639A81B6A2D6EC9F27BFF024DD28A1DB7182766585F711D64' }
        @{ Path = 'src/Startup.ps1'; Size = 5093; Sha256 = 'AA2E7983F7D58DE6E826BFCD26A41F0E86D0DC1564E67973026C64758338CEBC' }
        @{ Path = 'src/UI/App.ps1'; Size = 118215; Sha256 = 'A4376A832FC6C5333CE70538683E8D2D9E73C36872B85689D38D2C88DAAD42E1' }
        @{ Path = 'src/UI/Dialogs.ps1'; Size = 10114; Sha256 = 'C1BAA7762A4E665A86B719AA5815F0C65C4D597E4F8C374EA743F1394DB09501' }
        @{ Path = 'src/UI/MainWindow.xaml'; Size = 91404; Sha256 = 'B8BA22AF6584DD4042762E72E3EF2B1C12F58E5E1032C2F4EAF9A88718FC3B42' }
        @{ Path = 'src/UI/ViewModels.ps1'; Size = 5796; Sha256 = '6B27FA22F1253B317E66D6BE557DF1A0CBA84814A13655A8F4B3555AFF45642C' }
        @{ Path = '_Files/Bitsum-Highest-Performance.pow'; Size = 8192; Sha256 = 'F8BDD77720170E6521FA0FF533CDA9E4DA8342D16F858159E74E8216BC22A306' }
        @{ Path = '_Files/HybredPowerPlans/HybredLowLatencyBalanced.pow'; Size = 16384; Sha256 = '1F0C1B3C17CB60A038486E02A849759106547169A4BD42F905BA7B6C639E16AD' }
        @{ Path = '_Files/HybredPowerPlans/HybredLowLatencyHighPerf.pow'; Size = 16384; Sha256 = '5FA32B2853AA59140133C64458D112EAB4EB3EDDF31FE6E73C802CBDC8AF7FC3' }
        @{ Path = '_Files/ISLC/ar/Intelligent standby list cleaner ISLC.resources.dll'; Size = 25360; Sha256 = 'D060968A5BBFF7A8CE6752371C01DBC340F524937BC62FAF7C82DCD92AC81A92' }
        @{ Path = '_Files/ISLC/cs/Intelligent standby list cleaner ISLC.resources.dll'; Size = 23824; Sha256 = '710AC98E39C675C1AC5EE5C6DF2DE638637E71DA0B1734A9E344CE938B8DC370' }
        @{ Path = '_Files/ISLC/da/Intelligent standby list cleaner ISLC.resources.dll'; Size = 23312; Sha256 = '863E6D484A7DCFA5EEAB7B4E915FC71C69D8AF4F8AAE964F3146BC08C4E2CA4B' }
        @{ Path = '_Files/ISLC/de/Intelligent standby list cleaner ISLC.resources.dll'; Size = 23824; Sha256 = '1BDDDEBF8587E26A1AADDFEA77522C439E12FBE9218A9F4BD094A7C3F6C10E80' }
        @{ Path = '_Files/ISLC/el/Intelligent standby list cleaner ISLC.resources.dll'; Size = 27920; Sha256 = '7CADC0376149657516541F83D8ED588C5DFF030FF7B6875D4334D56FB85ED92D' }
        @{ Path = '_Files/ISLC/es/Intelligent standby list cleaner ISLC.resources.dll'; Size = 23824; Sha256 = '07EE99C930FD91547A9C24CE17AC8C480A2F6868E5BDAC523ACDC123F5CE5520' }
        @{ Path = '_Files/ISLC/fi/Intelligent standby list cleaner ISLC.resources.dll'; Size = 23824; Sha256 = 'A5CE1AAE6F30E66562F59B0957B6DA2E88D98CD05853BF267253AE1B5B2F28A8' }
        @{ Path = '_Files/ISLC/fr/Intelligent standby list cleaner ISLC.resources.dll'; Size = 23824; Sha256 = '1A33D962781137802B4E2B62FAAF2642EF78C1C456A1AEE7821DA5B7E0992459' }
        @{ Path = '_Files/ISLC/Intelligent standby list cleaner ISLC.exe'; Size = 1189136; Sha256 = '11E4ED0B322ADCED3214C5A73CA1E807140341BE6327B2A47A4C52434E73322F' }
        @{ Path = '_Files/ISLC/Intelligent standby list cleaner ISLC.pdb'; Size = 189952; Sha256 = '7B7EA246DC8A7A1CC5D9E26166012217F55E40B6FFC2D0BB0CC5404AF04D1EBA' }
        @{ Path = '_Files/ISLC/ISLC-v1.0.4.8-original.exe'; Size = 706056; Sha256 = '599315A1852B951E0ADAE2BE46FCE30BB32AAB7F8A4C9112471A5A88320E3085' }
        @{ Path = '_Files/ISLC/ISLC.Core.dll'; Size = 49424; Sha256 = '11DC5458940033634E40B855EC117A07EDADF78D3C3FE2ACA989098A46C590AC' }
        @{ Path = '_Files/ISLC/ISLC.Core.pdb'; Size = 97792; Sha256 = '908409CAD227F1B5D2EB369FEAF2B53B192B986D9BAB468ADB19FB3240E696E0' }
        @{ Path = '_Files/ISLC/it/Intelligent standby list cleaner ISLC.resources.dll'; Size = 23824; Sha256 = '3B927FE08BCA984D321419F04E874938FDCA9BC0569A62F57D959716319BC7E6' }
        @{ Path = '_Files/ISLC/ja/Intelligent standby list cleaner ISLC.resources.dll'; Size = 24848; Sha256 = '28F90816523BBEDE7BCD928BD2C35EA58660EF02FF0073681BA3B2BD64B7019B' }
        @{ Path = '_Files/ISLC/ko/Intelligent standby list cleaner ISLC.resources.dll'; Size = 24336; Sha256 = '6A71FBF7CB9A62AC71E3AD747B90064222599BBDFA3E02F984C9D65A0190D729' }
        @{ Path = '_Files/ISLC/LICENSE.txt'; Size = 3082; Sha256 = '31DEB37929508CB318B95C586850B45AFF999A1E155FBF76465457B893B364CF' }
        @{ Path = '_Files/ISLC/nl/Intelligent standby list cleaner ISLC.resources.dll'; Size = 23312; Sha256 = '829C3B81CC95E769BEE0FB14F0268777BA38C03C011A44C60A033D626AAD871A' }
        @{ Path = '_Files/ISLC/no/Intelligent standby list cleaner ISLC.resources.dll'; Size = 23312; Sha256 = '706A011FEBE991AEAAE03989BE6DC9DF93F08BBF8B2B0C478331E00F1F898399' }
        @{ Path = '_Files/ISLC/pl/Intelligent standby list cleaner ISLC.resources.dll'; Size = 23824; Sha256 = '36BB9DEDA73252DC94311083510E4FF6702A5D5926F92D54DBFD7F5D1E6E6072' }
        @{ Path = '_Files/ISLC/pt/Intelligent standby list cleaner ISLC.resources.dll'; Size = 23824; Sha256 = 'E5BF1BADEC6C81F64ED3130BFD71C150D6E84F1D6FFE01C9E03E31499DE30A17' }
        @{ Path = '_Files/ISLC/ReadMe.txt'; Size = 1623; Sha256 = '6E8557E10A26BB94BC042A281463B78D0DA8A810C69C6BC4F88BBB0359C52D97' }
        @{ Path = '_Files/ISLC/ru/Intelligent standby list cleaner ISLC.resources.dll'; Size = 27408; Sha256 = '1863C70E9E4FA2971DD89FAAAE8421CBC2E01B6A6099C38A74BFCE6776266885' }
        @{ Path = '_Files/ISLC/sv/Intelligent standby list cleaner ISLC.resources.dll'; Size = 23312; Sha256 = '147FEBAB64CD1C39905361224C469B88087793678104B01047D2C4DD9C0D4D22' }
        @{ Path = '_Files/ISLC/THIRD-PARTY-NOTICES.txt'; Size = 1587; Sha256 = 'DCB134E849F7ED0E2842C25C5A1A38403C197CDA4A7E554BEDBAA823F0C97411' }
        @{ Path = '_Files/ISLC/tr/Intelligent standby list cleaner ISLC.resources.dll'; Size = 23824; Sha256 = 'CC336AD26A75BCA9AB13F414A2315F75FE6ACF6B98EB170AF549A80462E83D1E' }
        @{ Path = '_Files/ISLC/zh-Hans/Intelligent standby list cleaner ISLC.resources.dll'; Size = 22800; Sha256 = 'D1BF70238D5049EB218067665F14ED429D9358C2B2338C329973BE81E4BF7DBC' }
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
