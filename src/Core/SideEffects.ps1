# Livn Tools - Core/SideEffects.ps1
# Arka uc saglayicilari (Backend.ps1) DISINDA kalan ve gercek sisteme yan etkisi
# olan TUM ilkel islemler: surec kapatma, dosya silme, Geri Donusum Kutusu,
# Teslim Iyilestirme onbellegi, harici arac baslatma, Explorer yeniden baslatma,
# kullanici betigi ve .reg ice aktarma.
#
# KURAL (tests/Static.Tests.ps1 ile zorunlu): src/ altinda bu tur cagrilar
# yalnizca bu dosyadaki veya Memory dali olan Backend.ps1 fonksiyonlarindan
# yapilir. Buradaki her fonksiyon ISLEMDEN ONCE Assert-LtLiveSystem veya
# Assert-LtDeletePermitted cagirir; bellek arka ucunda (kuru calisma / test)
# gercek sisteme hicbir sey yapilmaz.

Set-StrictMode -Version 2.0

# ---------------------------------------------------------------------------
# Surecler
# ---------------------------------------------------------------------------
function Get-LtProcessesByName {
    <#
      Ada gore surecleri dondurur. -WithWindow: yalnizca gorunur ana penceresi olanlar.
      Bellek arka ucunda GERCEK surec listesi okunmaz; sahte sistemdeki
      Mem.Processes (@(@{ Name; HasWindow })) kullanilir.
    #>
    param([Parameter(Mandatory)][string[]]$Names, [switch]$WithWindow)
    if (-not (Test-LtLiveSystem)) {
        $m = Get-LtMemoryState
        $list = @()
        if ($m -and $m.ContainsKey('Processes')) { $list = @($m.Processes) }
        return @($list | Where-Object { ($Names -contains $_.Name) -and (-not $WithWindow -or $_.HasWindow) } |
            ForEach-Object { [pscustomobject]@{ ProcessName = $_.Name; Id = 0; Simulated = $true } })
    }
    # Yalniz bu oturumun surecleri: yukseltilmis surec diger kullanicilarin (hizli kullanici
    # degistirme / RDP) sureclerini de gorur; onlara dokunulmaz.
    $session = [Diagnostics.Process]::GetCurrentProcess().SessionId
    $p = @(Get-Process -Name $Names -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $session })
    if ($WithWindow) { $p = @($p | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero }) }
    return $p
}

function Stop-LtProcessSafe {
    <#
      Ada gore surecleri zorla kapatir.
      Bellek arka ucu: gercek surece DOKUNULMAZ; yalnizca sahte listeden cikarilir
      ve Mem.Calls'a 'Process.Stop|<ad>' yazilir (hata enjeksiyonu desteklenir).
    #>
    param([Parameter(Mandatory)][string[]]$Names, [switch]$WithWindowOnly)
    if (-not (Test-LtLiveSystem)) {
        $m = Get-LtMemoryState
        if ($null -eq $m) { Assert-LtLiveSystem -Operation "Süreç kapatma: $($Names -join ', ')" }
        foreach ($n in $Names) { [void](Invoke-LtMemFault 'Process.Stop' $n) }
        if ($m.ContainsKey('Processes')) { $m.Processes = @($m.Processes | Where-Object { $Names -notcontains $_.Name }) }
        return
    }
    $procs = @(Get-LtProcessesByName -Names $Names -WithWindow:$WithWindowOnly)
    if ($procs.Count -gt 0) { $procs | Stop-Process -Force -ErrorAction SilentlyContinue }
}

# ---------------------------------------------------------------------------
# Dosyalar
# ---------------------------------------------------------------------------
function Remove-LtFileSafe {
    <# Tek dosyayi siler; silinen bayt sayisini dondurur (yoksa 0). #>
    param([Parameter(Mandatory)][string]$Path)
    Assert-LtDeletePermitted -Path $Path
    if (-not [System.IO.File]::Exists($Path)) { return [long]0 }
    $fi = New-Object System.IO.FileInfo($Path)
    $len = [long]$fi.Length
    if ($fi.IsReadOnly) { $fi.IsReadOnly = $false }
    $fi.Delete()
    return $len
}

function New-LtShellApplication { New-Object -ComObject Shell.Application }

function Clear-LtRecycleBin {
    <# Tum surucelerdeki Geri Donusum Kutusunu bosaltir; bosaltmadan onceki boyutu dondurur. #>
    Assert-LtLiveSystem -Operation 'Geri Dönüşüm Kutusunu boşalt'
    $before = [long]0; $count = -1
    try {
        $sh = New-LtShellApplication
        $items = @($sh.NameSpace(10).Items()); $count = $items.Count
        foreach ($i in $items) { $before += [long]$i.Size }
    } catch { $null = $_ }
    if ($count -eq 0) { return [long]0 }   # zaten bos: Clear-RecycleBin bos kutuda hata verebilir
    try { Clear-RecycleBin -Force -ErrorAction Stop }
    catch {
        # Hata sonrasi kutu bossa islem amacina ulasmistir
        $after = -1
        try { $after = @((New-LtShellApplication).NameSpace(10).Items()).Count } catch { $null = $_ }
        if ($after -ne 0) { throw }
    }
    return $before
}

function Invoke-LtDeliveryOptimizationCleanup {
    <# Delete-DeliveryOptimizationCache (Windows 10 1809+). Yoksa NOTSUPPORTED. Donus: onceki boyut. #>
    Assert-LtLiveSystem -Operation 'Teslim İyileştirme önbelleğini sil'
    $cmd = Get-Command -Name 'Delete-DeliveryOptimizationCache' -ErrorAction SilentlyContinue
    if (-not $cmd) { throw 'NOTSUPPORTED:Delete-DeliveryOptimizationCache bu sistemde yok.' }
    $before = [long]0
    $st = Get-Command -Name 'Get-DeliveryOptimizationStatus' -ErrorAction SilentlyContinue
    if ($st) { try { $before = [long](& $st -ErrorAction Stop | Measure-Object -Property FileSize -Sum).Sum } catch { $null = $_ } }
    & $cmd -Force -ErrorAction Stop
    return $before
}

# ---------------------------------------------------------------------------
# Harici araclar ve kabuk
# ---------------------------------------------------------------------------
function Start-LtProcessAndWait {
    <#
      Ciktisi yakalanmayan GUI araclari icin (ornek: cleanmgr /sagerun).
      Donus: @{ Exited; ExitCode }. Iptal istenirse beklemeyi birakir.
    #>
    param([Parameter(Mandatory)][string]$FilePath, [string]$Arguments = '', [int]$TimeoutMinutes = 30, $Cancel = $null)
    Assert-LtLiveSystem -Operation "Araç başlatma: $FilePath $Arguments"
    $p = Start-Process -FilePath $FilePath -ArgumentList $Arguments -PassThru -WindowStyle Hidden
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    while (-not $p.HasExited -and (Get-Date) -lt $deadline) {
        if ($null -ne $Cancel -and $Cancel.Requested) { break }
        Start-Sleep -Seconds 2
    }
    $code = $null
    if ($p.HasExited) { $code = $p.ExitCode }
    return @{ Exited = [bool]$p.HasExited; ExitCode = $code }
}

function Get-LtGhostUsbStorage {
    <# Su an takili OLMAYAN USBSTOR aygitlari (salt okunur). Bellek arka ucunda gercek aygit listesi okunmaz. #>
    if (-not (Test-LtLiveSystem)) { return @() }
    return @(Get-PnpDevice -ErrorAction Stop | Where-Object { $_.InstanceId -like 'USBSTOR\*' -and -not $_.Present })
}

function Restart-LtExplorerShell {
    <#
      Explorer'i yeniden baslatir (klasik sag tik menusu vb. icin). Yalniz bu oturumun
      Explorer'i kapatilir. Kabugu Winlogon yeniden baslatir (AutoRestartShell); gelmezse
      yukseltilmemis olarak baslatilmaya calisilir (yonetici Explorer'i istenmez).
    #>
    Assert-LtLiveSystem -Operation 'Explorer yeniden başlatma'
    $session = [Diagnostics.Process]::GetCurrentProcess().SessionId
    $mine = { @(Get-Process -Name explorer -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $session }) }
    $ids = @(& $mine | ForEach-Object { $_.Id })
    if ($ids.Count -gt 0) { Stop-Process -Id $ids -Force -ErrorAction Stop }
    for ($i = 0; $i -lt 20; $i++) { Start-Sleep -Milliseconds 500; if (@(& $mine).Count -gt 0) { return } }
    try { Start-Process -FilePath "$env:SystemRoot\System32\runas.exe" -ArgumentList @('/trustlevel:0x20000', "`"$env:SystemRoot\explorer.exe`"") -WindowStyle Hidden -ErrorAction Stop } catch { $null = $_ }
    for ($i = 0; $i -lt 6; $i++) { Start-Sleep -Milliseconds 500; if (@(& $mine).Count -gt 0) { return } }
    Write-LtLog 'Explorer kendiliğinden başlamadı; yönetici yetkisiyle başlatılıyor. Oturumu kapatıp açmanız önerilir.' 'WARN'
    Start-Process -FilePath "$env:SystemRoot\explorer.exe"
}

function Open-LtFolder {
    <#
      Klasoru Dosya Gezgini'nde acar. Sistem ayari DEGISTIRMEZ; kuru calismada da
      izinlidir (kuru calismanin veri klasoru ayridir: data\dryrun).
    #>
    param([Parameter(Mandatory)][string]$Path)
    if (-not [System.IO.Directory]::Exists($Path)) { throw "Klasör yok: $Path" }
    Start-Process -FilePath 'explorer.exe' -ArgumentList @($Path)
}

# ---------------------------------------------------------------------------
# Kullanici betikleri ve .reg ice aktarma (geri alma sistemi DISINDA)
# ---------------------------------------------------------------------------
function Invoke-LtUserScript {
    <#
      Kullanicinin yapistirdigi/ice aktardigi betigi calistirir. Geri alinamaz.
      Kuru calismada HIC calistirilmaz (ne PowerShell ne batch).
      Donus: @{ Kind; ExitCode; Errors }
    #>
    param([Parameter(Mandatory)][string]$Code, [ValidateSet('PowerShell', 'Batch')][string]$Kind = 'PowerShell', $Cancel = $null)
    Assert-LtLiveSystem -Operation "Kullanıcı betiği ($Kind)"
    if ($Kind -eq 'Batch') {
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ('livn_' + [guid]::NewGuid().ToString('N') + '.cmd')
        # cmd.exe betigi konsol kod sayfasiyla okur; BOM yazilmaz
        $enc = Get-LtConsoleEncoding
        if ($enc.CodePage -eq 65001) { $enc = New-Object Text.UTF8Encoding($false) }
        [IO.File]::WriteAllText($tmp, $Code, $enc)
        try {
            $r = Invoke-LtNative -FilePath "$env:SystemRoot\System32\cmd.exe" -Arguments @('/d', '/c', $tmp) -TimeoutSec 3600 -Cancel $Cancel
            if (Get-LtProp $r 'Cancelled' $false) { Write-LtLog 'Betik kullanıcı isteğiyle durduruldu.' 'WARN' }
            foreach ($l in ($r.StdOut -split "`r?`n")) { if ($l.Trim()) { Write-LtLog "  $l" 'INFO' } }
            foreach ($l in ($r.StdErr -split "`r?`n")) { if ($l.Trim()) { Write-LtLog "  $l" 'WARN' } }
            Write-LtLog "Betik bitti (çıkış kodu $($r.ExitCode))." $(if ($r.ExitCode -eq 0) { 'OK' } else { 'ERROR' })
            return @{ Kind = $Kind; ExitCode = $r.ExitCode; Errors = 0 }
        } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
    $sb = [scriptblock]::Create($Code)
    $ErrorActionPreference = 'Continue'
    $errCount = 0
    & $sb 2>&1 | ForEach-Object {
        if ($_ -is [System.Management.Automation.ErrorRecord]) { $errCount++; Write-LtLog "  $($_.ToString())" 'ERROR' }
        else { Write-LtLog "  $([string]$_)" 'INFO' }
    }
    Write-LtLog ("Betik bitti ({0} hata)." -f $errCount) $(if ($errCount -eq 0) { 'OK' } else { 'WARN' })
    return @{ Kind = $Kind; ExitCode = $null; Errors = $errCount }
}

function Import-LtRegFile {
    <# v3.5 .reg yedegini reg.exe ile ice aktarir. Livn Tools gunlugune KAYDEDILMEZ. Donus: cikis kodu. #>
    param([Parameter(Mandatory)][string]$Path)
    Assert-LtLiveSystem -Operation "reg import: $Path"
    $r = Invoke-LtNative -FilePath "$env:SystemRoot\System32\reg.exe" -Arguments @('import', $Path) -TimeoutSec 120
    if ($r.ExitCode -eq 0) { Write-LtLog "reg import başarılı: $Path" 'OK' } else { Write-LtLog "reg import başarısız (çıkış kodu $($r.ExitCode)): $($r.StdErr.Trim())" 'ERROR' }
    return $r.ExitCode
}

function Open-LtGraphicsSettings {
    # Fixed URI, no arbitrary command/URI input. Memory mode must not launch apps.
    Assert-LtLiveSystem -Operation 'Windows Grafik Ayarları aç'
    # explorer.exe uzerinden: Ayarlar/tarayici yonetici yetkisiyle degil, kullanicinin kabugunda acilir
    Start-Process -FilePath "$env:SystemRoot\explorer.exe" -ArgumentList '"ms-settings:display-advancedgraphics"' -ErrorAction Stop
}


function Open-LtPerformanceResource {
    param([Parameter(Mandatory)][ValidateSet('ISLC','ParkControl','ProcessLasso','PresentMon','WindowsPower')][string]$Id)
    Assert-LtLiveSystem -Operation 'Performans aracı resmî sayfasını aç'
    $urls = @{
        ISLC = 'https://www.wagnardsoft.com/content/Download-Intelligent-standby-list-cleaner-ISLC-1048'
        ParkControl = 'https://bitsum.com/parkcontrol/'
        ProcessLasso = 'https://bitsum.com/'
        PresentMon = 'https://github.com/GameTechDev/PresentMon'
        WindowsPower = 'ms-settings:powersleep'
    }
    Start-Process -FilePath "$env:SystemRoot\explorer.exe" -ArgumentList ('"' + $urls[$Id] + '"') -ErrorAction Stop
}

# Optional setup actions. No automatic downloads or installs during module import.
# WinGet: kullanilan bayraklar (--disable-interactivity, --no-upgrade) icin muhafazakar alt surum
$script:LtWingetMinVersion = [version]'1.6.0'

function Get-LtWingetPath {
    <#
      winget.exe yolu: PATH, kullanicinin WindowsApps takma adi, sonra App Installer paket klasoru.
      Yukseltilmis oturumda PATH'te WindowsApps eksik olabilir; ikinci ve ucuncu yol bunu karsilar.
    #>
    Assert-LtLiveSystem -Operation 'WinGet erişimi'
    [void](Get-LtInteractiveUserSid)
    $cmd = Get-Command winget.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    if ($env:LOCALAPPDATA) {
        $alias = $env:LOCALAPPDATA.TrimEnd('\') + '\Microsoft\WindowsApps\winget.exe'
        if (Test-Path -LiteralPath $alias) { return $alias }
    }
    try {
        $pkg = @(Get-AppxPackage -Name 'Microsoft.DesktopAppInstaller' -ErrorAction Stop | Sort-Object Version -Descending)[0]
        if ($pkg -and $pkg.InstallLocation) {
            $exe = Join-Path $pkg.InstallLocation 'winget.exe'
            if (Test-Path -LiteralPath $exe) { return $exe }
        }
    } catch { $null = $_ }
    throw 'WINGET_MISSING:WinGet (Uygulama Yükleyici) bulunamadı.'
}

function ConvertFrom-LtWingetVersion([string]$Text) {
    <# 'v1.9.25200' -> [version]1.9.25200; taninmazsa $null #>
    $m = [regex]::Match([string]$Text, 'v?(\d+)\.(\d+)(?:\.(\d+))?')
    if (-not $m.Success) { return $null }
    $build = if ($m.Groups[3].Success) { [int]$m.Groups[3].Value } else { 0 }
    return New-Object version ([int]$m.Groups[1].Value), ([int]$m.Groups[2].Value), $build
}

function Get-LtWingetVersion {
    param([Parameter(Mandatory)][string]$Path)
    $r = Invoke-LtNative -FilePath $Path -Arguments @('--version') -TimeoutSec 60
    if ($r.TimedOut -or $r.ExitCode -ne 0) { return $null }
    return ConvertFrom-LtWingetVersion $r.StdOut
}

function Get-LtWingetErrorInfo {
    <#
      WinGet HRESULT cikis kodlarini anlasilir duruma cevirir.
      Kaynak: https://github.com/microsoft/winget-cli/blob/master/doc/windows/package-manager/winget/returnCodes.md
      Donus: @{ Kind = Installed|RebootToFinish|Failed; Text }
    #>
    param([Parameter(Mandatory)][long]$Code)
    $hex = '0x{0:X8}' -f ([long]$Code -band 0xFFFFFFFFL)
    $known = @{
        '0x8A150061' = @('Installed', 'Paket zaten kurulu (sürümü yükseltilmedi).')
        '0x8A15010D' = @('Installed', 'Paket zaten kurulu.')
        '0x8A15002B' = @('Installed', 'Kurulu sürüm için uygulanacak güncelleme yok.')
        '0x8A150109' = @('RebootToFinish', 'Kurulumun tamamlanması için bilgisayarı yeniden başlatın.')
        '0x8A15010A' = @('Failed', 'Kurulum için önce bilgisayarı yeniden başlatıp tekrar deneyin.')
        '0x8A15010B' = @('RebootToFinish', 'Yükleyici yeniden başlatma başlattı.')
        '0x8A150101' = @('Failed', 'Uygulama açık; kapatıp tekrar deneyin.')
        '0x8A150111' = @('Failed', 'Uygulama başka bir program tarafından kullanılıyor; kapatıp tekrar deneyin.')
        '0x8A150102' = @('Failed', 'Başka bir kurulum sürüyor; bitince tekrar deneyin.')
        '0x8A150103' = @('Failed', 'Bir dosya kullanımda; ilgili uygulamaları kapatıp tekrar deneyin.')
        '0x8A150104' = @('Failed', 'Gerekli bir bağımlılık eksik.')
        '0x8A150110' = @('Failed', 'Bağımlılıklar kurulamadı.')
        '0x8A150105' = @('Failed', 'Disk dolu.')
        '0x8A150106' = @('Failed', 'Yetersiz bellek.')
        '0x8A150107' = @('Failed', 'İnternet bağlantısı gerekli.')
        '0x8A150045' = @('Failed', 'WinGet kaynağı açılamadı (ağ, proxy veya kaynak hatası).')
        '0x8A15003A' = @('Failed', 'İşlem Grup İlkesi tarafından engelleniyor.')
        '0x8A15010F' = @('Failed', 'Kurulum kuruluş ilkesi tarafından engellendi.')
        '0x8A15001B' = @('Failed', 'Microsoft Store istemcisi ilkeyle engellenmiş.')
        '0x8A150010' = @('Failed', 'Bu sistem için uygun yükleyici yok (mimari veya Windows sürümü).')
        '0x8A150014' = @('Failed', 'Paket WinGet kaynağında bulunamadı.')
        '0x8A150016' = @('Failed', 'Birden fazla paket eşleşti; kurulum yapılmadı.')
        '0x8A150011' = @('Failed', 'Yükleyici dosyasının özeti bildirimle eşleşmiyor; güvenlik nedeniyle kurulmadı.')
        '0x8A15010C' = @('Failed', 'Kurulum kullanıcı tarafından iptal edildi.')
        '0x8A15010E' = @('Failed', 'Daha yeni bir sürüm kurulu; eski sürüm kurulmadı.')
        '0x8A150046' = @('Failed', 'WinGet kaynak sözleşmesi kabul edilmedi.')
        '0x8A150041' = @('Failed', 'Paket sözleşmesi kabul edilmedi.')
        '0x8A150002' = @('Failed', 'WinGet bu komut seçeneklerini tanımıyor; Uygulama Yükleyici''yi güncelleyin.')
        '0x8A150108' = @('Failed', 'Yükleyici hata verdi; uygulama üreticisinin destek sayfasına bakın.')
    }
    if ($known.ContainsKey($hex)) { return @{ Kind = $known[$hex][0]; Text = "$($known[$hex][1]) ($hex)"; Hex = $hex } }
    return @{ Kind = 'Failed'; Text = "WinGet/yükleyici çıkış kodu $Code ($hex)."; Hex = $hex }
}

function Get-LtWingetInstalledIds {
    <#
      -AcceptSourceAgreements yalniz kullanicinin onayladigi kurulum akisinda verilir.
      Arka plan envanteri sozlesme kabul etmez; sozlesme gerekiyorsa okuma basarisiz olur
      ve durum "okunamadi" gosterilir.
    #>
    param([switch]$AcceptSourceAgreements, [string]$WingetPath = '')
    Assert-LtLiveSystem -Operation 'WinGet kurulu uygulama listesi'
    $exe = if ($WingetPath) { $WingetPath } else { Get-LtWingetPath }
    $path = Join-Path (Get-LtDataRoot) ('winget-inventory-' + [guid]::NewGuid().ToString('N') + '.json')
    try {
        $wingetArgs = @('export','--output',$path,'--source','winget')
        if ($AcceptSourceAgreements) { $wingetArgs += '--accept-source-agreements' }
        $wingetArgs += '--disable-interactivity'
        $r = Invoke-LtNative -FilePath $exe -Arguments $wingetArgs -TimeoutSec 180
        if ($r.TimedOut) { throw 'WinGet envanteri 180 saniyede tamamlanmadı (ağ veya kaynak güncellemesi takılmış olabilir).' }
        if ($r.ExitCode -ne 0) { throw (Get-LtWingetErrorInfo $r.ExitCode).Text }
        $data = [IO.File]::ReadAllText($path) | ConvertFrom-Json -ErrorAction Stop
        if (-not $data.PSObject.Properties['Sources']) { throw 'WinGet envanter biçimi tanınmadı.' }
        @($data.Sources | ForEach-Object { $_.Packages } | ForEach-Object { $_.PackageIdentifier })
    } finally { if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force } }
}
function Read-LtWingetInventory {
    <#
      SALT OKUNUR WinGet envanteri. Donus: @{ Available = [bool]; Ids = [string[]]; Version; Outdated = [bool] }.
      Kurulum veya yukseltme yapmaz. WinGet yoksa Available=$false (bu "kurulu degil" DEMEK DEGILDIR).
      Surum alt sinirin altindaysa Outdated=$true ve envanter okunmaz.
      Sorgu hatasi istisna olarak yukari iletilir. Bellek arka ucunda gercek winget calistirilmaz;
      sahte sistemdeki Mem.Setup kullanilir (hata enjeksiyonu: Faults['Winget.Inventory:export']).
    #>
    if (-not (Test-LtLiveSystem)) {
        $m = Get-LtMemoryState
        [void](Invoke-LtMemFault 'Winget.Inventory' 'export')
        $setup = Get-LtProp $m 'Setup'
        $ver = ConvertFrom-LtWingetVersion ([string](Get-LtProp $setup 'WingetVersion' 'v1.9.25200'))
        $outdated = ($null -ne $ver -and $ver -lt $script:LtWingetMinVersion)
        $ids = if ($outdated) { @() } else { @(Get-LtProp $setup 'InstalledIds' @()) }
        return @{ Available = [bool](Get-LtProp $setup 'WingetAvailable' $true); Ids = $ids; Version = $ver; Outdated = $outdated }
    }
    [void](Get-LtInteractiveUserSid)
    try { $exe = Get-LtWingetPath } catch {
        if ($_.Exception.Message -like 'WINGET_MISSING:*') { return @{ Available = $false; Ids = @(); Version = $null; Outdated = $false } }
        throw
    }
    $ver = Get-LtWingetVersion -Path $exe
    if ($null -ne $ver -and $ver -lt $script:LtWingetMinVersion) { return @{ Available = $true; Ids = @(); Version = $ver; Outdated = $true } }
    return @{ Available = $true; Ids = @(Get-LtWingetInstalledIds -WingetPath $exe); Version = $ver; Outdated = $false }
}
function Get-LtSetupInstallSnapshot {
    <# Toplu kurulum oncesi tek envanter: WinGet (sozlesme kabulu kurulum onayina dahil) + Windows listesi. Okunamazsa $null. #>
    Assert-LtLiveSystem -Operation 'Kurulum öncesi envanter'
    try {
        $exe = Get-LtWingetPath
        $ids = @(Get-LtWingetInstalledIds -AcceptSourceAgreements -WingetPath $exe)
        return @($ids + @(Get-LtSetupArpMatches -DisplayNames @(Get-LtInstalledDisplayNames -Fresh)) + @(Get-LtSetupFileMatches) | Select-Object -Unique)
    } catch { return $null }
}

function Install-LtSetupPackage {
    <# -KnownInstalledIds: toplu kurulumda bir kez alinan envanter (her paket icin ayri export yapilmaz). #>
    param([Parameter(Mandatory)][string]$Id, [string[]]$KnownInstalledIds = $null)
    Assert-LtLiveSystem -Operation 'WinGet uygulama kurulumu'
    $item = Get-LtSetupApps | Where-Object Id -eq $Id
    if (-not $item) { throw 'Uygulama izin verilen kurulum listesinde değil.' }
    try { $exe = Get-LtWingetPath } catch {
        if ($_.Exception.Message -like 'WINGET_MISSING:*') { throw 'WinGet (Uygulama Yükleyici) bulunamadı. Format Sonrası sayfasındaki "WinGet''i edinin" bağlantısını kullanın.' }
        throw
    }
    $ver = Get-LtWingetVersion -Path $exe
    if ($null -ne $ver -and $ver -lt $script:LtWingetMinVersion) { throw "WinGet $ver çok eski (en az $($script:LtWingetMinVersion) gerekir). Uygulama Yükleyici'yi güncelleyin." }
    if ($null -ne $KnownInstalledIds) {
        if (@($KnownInstalledIds) -contains $Id) { return New-LtResult -Id $Id -Title $item.Title -Status AlreadyApplied -Message 'Kurulu (işlem başındaki envanter); yükseltilmedi.' }
    } elseif (@(Get-LtWingetInstalledIds -AcceptSourceAgreements -WingetPath $exe) -contains $Id) { return New-LtResult -Id $Id -Title $item.Title -Status AlreadyApplied -Message 'WinGet envanterinde kurulu; yükseltilmedi.' }
    if ($null -eq $KnownInstalledIds -and @(@(Get-LtSetupArpMatches -DisplayNames @(Get-LtInstalledDisplayNames -Fresh)) + @(Get-LtSetupFileMatches)) -contains $Id) { return New-LtResult -Id $Id -Title $item.Title -Status AlreadyApplied -Message 'Windows uygulama listesinde kurulu (WinGet dışı kurulum); yeniden kurulmadı veya yükseltilmedi.' }
    $r = Invoke-LtNative -FilePath $exe -Arguments @('install','--id',$item.Id,'--exact','--source','winget','--no-upgrade','--disable-interactivity','--accept-source-agreements','--accept-package-agreements') -TimeoutSec 1800
    if ($r.TimedOut) { throw 'Kurulum zaman aşımına uğradı; yükleyici durumunu Windows üzerinden kontrol edin.' }
    $reboot = $false
    if ($r.ExitCode -ne 0) {
        $info = Get-LtWingetErrorInfo $r.ExitCode
        switch ($info.Kind) {
            'Installed' { return New-LtResult -Id $Id -Title $item.Title -Status AlreadyApplied -Message $info.Text }
            'RebootToFinish' { $reboot = $true }
            default { throw $info.Text }
        }
    }
    $verified = (@(Get-LtWingetInstalledIds -AcceptSourceAgreements -WingetPath $exe) -contains $Id) -or (@(@(Get-LtSetupArpMatches -DisplayNames @(Get-LtInstalledDisplayNames -Fresh)) + @(Get-LtSetupFileMatches)) -contains $Id)
    if ($reboot) {
        $note = if ($verified) { 'Kurulum doğrulandı; tamamlanması için yeniden başlatın.' } else { 'Yükleyici yeniden başlatma istedi; kurulum yeniden başlatmadan sonra doğrulanabilir.' }
        return New-LtResult -Id $Id -Title $item.Title -Status Success -RestartRequired $true -RestartKind 'Reboot' -Message $note
    }
    if (-not $verified) { throw 'Kurulum tamamlandı bildirildi fakat WinGet envanterinden veya Windows uygulama listesinden doğrulanamadı.' }
    return New-LtResult -Id $Id -Title $item.Title -Status Success -Message 'Kurulum doğrulandı. Uygulama Windows üzerinden kaldırılabilir; Livn geri alma kaydı oluşturulmadı.'
}

function Open-LtWingetHelp {
    <# Sabit resmi adresler; Store varsa Uygulama Yukleyici sayfasi, yoksa Microsoft Learn kurulum yonergesi. #>
    param([ValidateSet('Store','Docs')][string]$Target = 'Store')
    Assert-LtLiveSystem -Operation 'WinGet kaynağını aç'
    if ($Target -eq 'Store') {
        # LTSC/Server: Store yok; Microsoft Learn yonergesi acilir
        $store = $null
        try { $store = Get-AppxPackage -Name 'Microsoft.WindowsStore' -ErrorAction Stop | Select-Object -First 1 } catch { $null = $_ }
        if (-not $store) { $Target = 'Docs' }
    }
    $uri = if ($Target -eq 'Store') { 'ms-windows-store://pdp/?productid=9NBLGGH4NNS1' } else { 'https://learn.microsoft.com/windows/package-manager/winget/#install-winget' }
    Start-Process -FilePath "$env:SystemRoot\explorer.exe" -ArgumentList ('"' + $uri + '"') -ErrorAction Stop
    return $Target
}

function Get-LtOptionalAppNames {
    if (-not (Test-LtLiveSystem)) { return @() }
    [void](Get-LtInteractiveUserSid)
    @(Get-AppxPackage -ErrorAction Stop | Where-Object { -not $_.IsFramework -and -not $_.IsResourcePackage -and -not $_.NonRemovable } | ForEach-Object { $_.Name })
}
function Remove-LtOptionalApp {
    param([Parameter(Mandatory)][string]$Id)
    Assert-LtLiveSystem -Operation 'Seçili kullanıcı uygulamasını kaldır'
    [void](Get-LtInteractiveUserSid)
    $item = Get-LtRemovableApps | Where-Object Id -eq $Id
    if (-not $item) { throw 'Uygulama kaldırma izin listesinde değil.' }
    $packages = @(Get-AppxPackage -Name $item.Id -ErrorAction Stop | Where-Object { $_.Name -ceq $item.Id })
    if ($packages.Count -eq 0) { return New-LtResult -Id $Id -Title $item.Title -Status AlreadyApplied -Message 'Bu kullanıcı için kurulu değil.' }
    foreach ($package in $packages) {
        if ($package.IsFramework -or $package.IsResourcePackage -or $package.NonRemovable) { throw 'Korunan paket kaldırılmaz.' }
    }
    foreach ($package in $packages) { Remove-AppxPackage -Package $package.PackageFullName -ErrorAction Stop }
    if (@(Get-AppxPackage -Name $item.Id -ErrorAction Stop).Count -gt 0) { throw 'Uygulamanın kaldırıldığı doğrulanamadı.' }
    return New-LtResult -Id $Id -Title $item.Title -Status Success -Message 'Yalnız mevcut kullanıcıdan kaldırıldı. Uygulama verileri kaybolabilir; Store üzerinden yeniden kurulum veri kurtarma değildir.'
}
