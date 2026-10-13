# Portable desired choices only. Never import journals, SIDs, paths or scripts.
Set-StrictMode -Version 2.0

function Get-LtSetupApps {
    @(
        @{ Id='Mozilla.Firefox'; Title='Firefox'; Category='Tarayıcı'; Description='Web tarayıcısı' },
        @{ Id='Google.Chrome'; Title='Google Chrome'; Category='Tarayıcı'; Description='Web tarayıcısı' },
        @{ Id='Brave.Brave'; Title='Brave'; Category='Tarayıcı'; Description='Web tarayıcısı' },
        @{ Id='Vivaldi.Vivaldi'; Title='Vivaldi'; Category='Tarayıcı'; Description='Web tarayıcısı' },
        @{ Id='Valve.Steam'; Title='Steam'; Category='Oyun'; Description='Oyun mağazası ve kütüphane' },
        @{ Id='EpicGames.EpicGamesLauncher'; Title='Epic Games Launcher'; Category='Oyun'; Description='Oyun mağazası ve kütüphane' },
        @{ Id='GOG.Galaxy'; Title='GOG Galaxy'; Category='Oyun'; Description='Oyun kütüphanesi' },
        @{ Id='Ubisoft.Connect'; Title='Ubisoft Connect'; Category='Oyun'; Description='Ubisoft oyun istemcisi' },
        @{ Id='ElectronicArts.EADesktop'; Title='EA app'; Category='Oyun'; Description='EA oyun istemcisi' },
        @{ Id='Blizzard.BattleNet'; Title='Battle.net'; Category='Oyun'; Description='Blizzard oyun istemcisi' },
        @{ Id='PrismLauncher.PrismLauncher'; Title='Prism Launcher'; Category='Oyun'; Description='Minecraft için alternatif; geçerli oyun hesabı gerekir' },
        @{ Id='Microsoft.VCRedist.2015+.x64'; Title='Visual C++ 2015–2022 (x64)'; Category='Oyun bileşenleri'; Description='Çoğu oyunun istediği çalışma zamanı (MSVCP140.dll / VCRUNTIME140.dll)' },
        @{ Id='Microsoft.VCRedist.2015+.x86'; Title='Visual C++ 2015–2022 (x86)'; Category='Oyun bileşenleri'; Description='32-bit oyunlar ve başlatıcılar için aynı çalışma zamanı' },
        @{ Id='Microsoft.DirectX'; Title='DirectX çalışma zamanı (eski bileşenler)'; Category='Oyun bileşenleri'; Description='Eski oyunların istediği D3DX9/10/11, XAudio 2.7, XInput 1.3 dosyaları (d3dx9_43.dll vb.)' },
        @{ Id='Microsoft.DotNet.DesktopRuntime.8'; Title='.NET Masaüstü Çalışma Zamanı 8'; Category='Oyun bileşenleri'; Description='Bazı başlatıcı, mod yöneticisi ve araçların istediği .NET 8' },
        @{ Id='Discord.Discord'; Title='Discord'; Category='İletişim'; Description='Sesli ve yazılı sohbet' },
        @{ Id='Telegram.TelegramDesktop'; Title='Telegram Desktop'; Category='İletişim'; Description='Mesajlaşma' },
        @{ Id='Mozilla.Thunderbird'; Title='Thunderbird'; Category='İletişim'; Description='E-posta istemcisi' },
        @{ Id='VideoLAN.VLC'; Title='VLC'; Category='Medya'; Description='Video ve ses oynatıcı' },
        @{ Id='OBSProject.OBSStudio'; Title='OBS Studio'; Category='Medya'; Description='Ekran kaydı ve yayın' },
        @{ Id='Audacity.Audacity'; Title='Audacity'; Category='Medya'; Description='Ses düzenleme' },
        @{ Id='HandBrake.HandBrake'; Title='HandBrake'; Category='Medya'; Description='Video dönüştürme' },
        @{ Id='ShareX.ShareX'; Title='ShareX'; Category='Medya'; Description='Ekran görüntüsü ve paylaşım' },
        @{ Id='TheDocumentFoundation.LibreOffice'; Title='LibreOffice'; Category='Ofis ve PDF'; Description='Ofis uygulamaları' },
        @{ Id='SumatraPDF.SumatraPDF'; Title='SumatraPDF'; Category='Ofis ve PDF'; Description='PDF ve e-kitap okuyucu' },
        @{ Id='Obsidian.Obsidian'; Title='Obsidian'; Category='Ofis ve PDF'; Description='Yerel not ve bilgi yönetimi' },
        @{ Id='7zip.7zip'; Title='7-Zip'; Category='Dosya ve güvenlik'; Description='Arşiv açma ve sıkıştırma' },
        @{ Id='voidtools.Everything'; Title='Everything'; Category='Dosya ve güvenlik'; Description='Dosya adıyla hızlı arama; indeksleme kullanır' },
        @{ Id='WinDirStat.WinDirStat'; Title='WinDirStat'; Category='Dosya ve güvenlik'; Description='Disk alanı analizi' },
        @{ Id='Bitwarden.Bitwarden'; Title='Bitwarden'; Category='Dosya ve güvenlik'; Description='Parola yöneticisi' },
        @{ Id='KeePassXCTeam.KeePassXC'; Title='KeePassXC'; Category='Dosya ve güvenlik'; Description='Yerel parola kasası' },
        @{ Id='Microsoft.VisualStudioCode'; Title='Visual Studio Code'; Category='Geliştirme'; Description='Kod düzenleyici' },
        @{ Id='Notepad++.Notepad++'; Title='Notepad++'; Category='Geliştirme'; Description='Metin ve kod düzenleyici' },
        @{ Id='Git.Git'; Title='Git'; Category='Geliştirme'; Description='Sürüm kontrol araçları' },
        @{ Id='WinSCP.WinSCP'; Title='WinSCP'; Category='Geliştirme'; Description='SFTP ve SCP dosya aktarımı' },
        @{ Id='Microsoft.PowerToys'; Title='PowerToys'; Category='Sistem araçları'; Description='İsteğe bağlı masaüstü araçları; arka planda çalışır' },
        @{ Id='CPUID.CPU-Z'; Title='CPU-Z'; Category='Sistem araçları'; Description='İşlemci ve bellek bilgisi' },
        @{ Id='TechPowerUp.GPU-Z'; Title='GPU-Z'; Category='Sistem araçları'; Description='Ekran kartı bilgisi' },
        @{ Id='CrystalDewWorld.CrystalDiskInfo'; Title='CrystalDiskInfo'; Category='Sistem araçları'; Description='Disk sağlık bilgisi' },
        @{ Id='REALiX.HWiNFO'; Title='HWiNFO'; Category='Sistem araçları'; Description='Donanım ve sensör izleme; lisans koşulları geçerlidir' }
    ) | ForEach-Object {
        $_.Arp = if ($script:LtSetupArpPattern.ContainsKey($_.Id)) { $script:LtSetupArpPattern[$_.Id] } else { '' }
        [pscustomobject]$_
    }
}

# Windows "Yüklü uygulamalar" (Uninstall kayıtları) DisplayName desenleri. WinGet'in
# eşleştiremediği kurulumlar (üreticinin kendi yükleyicisi, kullanıcı başına kurulum)
# için yalnız "kurulu" bilgisini tamamlar; asla "kurulu değil" kararı vermez.
# Desenler büyük/küçük harf duyarsızdır ve tam ad başlangıcına bağlıdır.
$script:LtSetupArpPattern = @{
    'Mozilla.Firefox' = '^Mozilla Firefox( |$)'; 'Google.Chrome' = '^Google Chrome$'; 'Brave.Brave' = '^Brave$'; 'Vivaldi.Vivaldi' = '^Vivaldi$'
    'Valve.Steam' = '^Steam$'; 'EpicGames.EpicGamesLauncher' = '^Epic Games Launcher$'; 'GOG.Galaxy' = '^GOG Galaxy( |$)'
    'Ubisoft.Connect' = '^Ubisoft Connect$'; 'ElectronicArts.EADesktop' = '^EA app$'; 'Blizzard.BattleNet' = '^Battle\.net$'
    'PrismLauncher.PrismLauncher' = '^Prism Launcher( |$)'; 'Discord.Discord' = '^Discord$'; 'Telegram.TelegramDesktop' = '^Telegram Desktop( |$)'
    'Mozilla.Thunderbird' = '^Mozilla Thunderbird( |$)'; 'VideoLAN.VLC' = '^VLC media player$'; 'OBSProject.OBSStudio' = '^OBS Studio$'
    'Audacity.Audacity' = '^Audacity( |$)'; 'HandBrake.HandBrake' = '^HandBrake( |$)'; 'ShareX.ShareX' = '^ShareX$'
    'TheDocumentFoundation.LibreOffice' = '^LibreOffice [0-9]'; 'SumatraPDF.SumatraPDF' = '^SumatraPDF$'; 'Obsidian.Obsidian' = '^Obsidian( |$)'
    '7zip.7zip' = '^7-Zip( |$)'; 'voidtools.Everything' = '^Everything( |$)'; 'WinDirStat.WinDirStat' = '^WinDirStat( |$)'
    'Bitwarden.Bitwarden' = '^Bitwarden( |$)'; 'KeePassXCTeam.KeePassXC' = '^KeePassXC$'
    'Microsoft.VisualStudioCode' = '^Microsoft Visual Studio Code( \(User\))?$'; 'Notepad++.Notepad++' = '^Notepad\+\+( |$)'
    'Git.Git' = '^Git( version [0-9.]+)?$'; 'WinSCP.WinSCP' = '^WinSCP( |$)'; 'Microsoft.PowerToys' = '^PowerToys( |$)'
    'CPUID.CPU-Z' = '^CPUID CPU-Z( |$)'; 'TechPowerUp.GPU-Z' = '^TechPowerUp GPU-Z$'; 'CrystalDewWorld.CrystalDiskInfo' = '^CrystalDiskInfo( |$)'
    'REALiX.HWiNFO' = '^HWiNFO(32|64)?( |$)'
    'Microsoft.VCRedist.2015+.x64' = '^Microsoft Visual C\+\+ (2015-20\d\d|v14) Redistributable \(x64\)'
    'Microsoft.VCRedist.2015+.x86' = '^Microsoft Visual C\+\+ (2015-20\d\d|v14) Redistributable \(x86\)'
    'Microsoft.DotNet.DesktopRuntime.8' = '^Microsoft Windows Desktop Runtime - 8\.'
}

# Windows uygulama listesinde gorunmeyen bilesenler: sistem klasorundeki imza dosyasi
$script:LtSetupFilePattern = @{
    'Microsoft.DirectX' = 'System32\d3dx9_43.dll'
}

function Get-LtSetupFileMatches {
    <# Dosya ile algilanan bilesenler. Bellek arka ucunda Mem.Setup.Files listesi kullanilir. #>
    $found = New-Object System.Collections.ArrayList
    foreach ($id in $script:LtSetupFilePattern.Keys) {
        $rel = $script:LtSetupFilePattern[$id]
        $present = $false
        if (-not (Test-LtLiveSystem)) {
            $m = Get-LtMemoryState
            $setup = Get-LtProp $m 'Setup'
            $present = @(Get-LtProp $setup 'Files' @()) -contains $rel
        } elseif ($env:SystemRoot) {
            $present = Test-Path -LiteralPath (Join-Path $env:SystemRoot $rel)
        }
        if ($present) { [void]$found.Add($id) }
    }
    return @($found)
}

function Get-LtSetupArpMatches {
    <# Verilen DisplayName listesinde deseni eşleşen katalog kimlikleri. #>
    param([string[]]$DisplayNames = @())
    $names = @($DisplayNames | Where-Object { $_ } | ForEach-Object { ([string]$_).Trim() })
    @(Get-LtSetupApps | Where-Object { $app = $_; $app.Arp -and @($names | Where-Object { $_ -match $app.Arp }).Count -gt 0 } | ForEach-Object { $_.Id })
}

function Find-LtSetupApps {
    param([object[]]$Apps, [string]$Query='', [string]$Category='Tümü', [string[]]$SelectedIds=@(), [switch]$SelectedOnly)
    $queryText = ConvertTo-LtSetupSearchText $Query
    @($Apps | Where-Object {
        ($Category -eq 'Tümü' -or $_.Category -eq $Category) -and
        (-not $SelectedOnly -or $SelectedIds -contains $_.Id) -and
        ((ConvertTo-LtSetupSearchText ("{0} {1} {2} {3}" -f $_.Title,$_.Id,$_.Category,$_.Description)).Contains($queryText))
    })
}
function ConvertTo-LtSetupSearchText {
    param([AllowEmptyString()][string]$Text)
    # Make Turkish searches work with or without dotted/undotted and accented letters.
    $textValue = $Text.ToLowerInvariant().Replace('ı','i').Normalize([Text.NormalizationForm]::FormD)
    return ([regex]::Replace($textValue, '\p{Mn}', '')).Normalize([Text.NormalizationForm]::FormC).ToLowerInvariant()
}
function Get-LtRemovableApps {
    @(
        @{ Id='Clipchamp.Clipchamp'; Title='Clipchamp — video düzenleyici' },
        @{ Id='Microsoft.BingNews'; Title='Microsoft Haberler' },
        @{ Id='Microsoft.BingWeather'; Title='Microsoft Hava Durumu' },
        @{ Id='Microsoft.MicrosoftSolitaireCollection'; Title='Microsoft Solitaire Collection' },
        @{ Id='Microsoft.YourPhone'; Title='Telefon Bağlantısı' }
    ) | ForEach-Object { [pscustomobject]$_ }
}
function Get-LtPortableTweakIds {
    @(Get-LtCatalog | Where-Object {
        $_.Risk -eq 'Low' -and ($_.Id -like 'ui.*' -or $_.Id -in @('input.mouse-accel-off','game.mode','priv.adid-off','priv.tailored-off'))
    } | ForEach-Object { $_.Id })
}
function Test-LtSetupProfile {
    param([Parameter(Mandatory)]$Value)
    $v = ConvertTo-LtHashtable $Value
    if ($v -isnot [System.Collections.IDictionary]) { throw 'Profil bir JSON nesnesi olmalı.' }
    foreach ($key in $v.Keys) { if ($key -notin @('SchemaVersion','TweakIds','PackageIds','MenuDelayMs')) { throw "Profilde tanınmayan alan: $key" } }
    if ((Get-LtProp $v 'SchemaVersion') -isnot [ValueType] -or (Get-LtProp $v 'SchemaVersion') -ne 1) { throw 'Desteklenmeyen profil sürümü.' }
    $allowed = @(Get-LtPortableTweakIds); $apps = @((Get-LtSetupApps).Id)
    foreach ($field in @('TweakIds','PackageIds')) {
        if (-not $v.ContainsKey($field) -or $null -eq $v[$field] -or $v[$field] -is [string] -or $v[$field] -isnot [System.Collections.IEnumerable]) { throw "$field bir dizi olmalı." }
        if (@($v[$field]).Count -gt 100) { throw 'Profil seçim sınırını aşıyor.' }
        foreach ($id in $v[$field]) {
            if ($id -isnot [string] -or (($field -eq 'TweakIds' -and $allowed -notcontains $id) -or ($field -eq 'PackageIds' -and $apps -notcontains $id))) { throw "Taşınamayan veya bilinmeyen seçim: $id" }
        }
    }
    if ($v.ContainsKey('MenuDelayMs') -and $v.MenuDelayMs -notin @(0,100,200,400,800)) { throw 'Geçersiz menü süresi.' }
    if ($v.TweakIds -contains 'ui.menu-delay' -and -not $v.ContainsKey('MenuDelayMs')) { throw 'Menü süresi seçilmemiş.' }
    return $v
}
function New-LtSetupProfile {
    param([string[]]$TweakIds=@(), [string[]]$PackageIds=@(), $Context=@{})
    $v = @{ SchemaVersion=1; TweakIds=@($TweakIds | Select-Object -Unique); PackageIds=@($PackageIds | Select-Object -Unique) }
    if ($TweakIds -contains 'ui.menu-delay') { $v.MenuDelayMs = Get-LtMenuDelayChoice $Context }
    return Test-LtSetupProfile $v
}
function Read-LtSetupProfile {
    param([Parameter(Mandatory)][string]$Path)
    $f = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($f.Length -gt 1MB) { throw 'Profil 1 MB sınırını aşıyor.' }
    return Test-LtSetupProfile ([IO.File]::ReadAllText($f.FullName) | ConvertFrom-Json -ErrorAction Stop)
}
function Save-LtSetupProfile {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Value)
    if ([IO.Path]::GetExtension($Path) -ine '.json') { throw 'Profil uzantısı .json olmalı.' }
    $v = Test-LtSetupProfile $Value
    Write-LtFileAtomic -Path $Path -Content ($v | ConvertTo-Json -Depth 5)
}
function Get-LtSetupAppInventory {
    $installed = @(Get-LtOptionalAppNames)
    @(Get-LtRemovableApps | ForEach-Object {
        [pscustomobject]@{ Id=$_.Id; Title=$_.Title; Installed=($installed -contains $_.Id); Label=("{0} — {1}" -f $_.Title, $(if ($installed -contains $_.Id) {'Kurulu'} else {'Kurulu değil'})) }
    })
}
function Invoke-LtSetupBatch {
    param([ValidateSet('Install','Remove')][string]$Mode, [string[]]$Ids, [switch]$Accepted, $Progress=$null, $Cancel=$null)
    if (-not $Accepted) { throw 'Uygulama listesi ve işlem onayı gerekli.' }
    $catalog = if ($Mode -eq 'Install') { @(Get-LtSetupApps) } else { @(Get-LtRemovableApps) }
    foreach ($id in $Ids) { if ($catalog.Id -notcontains $id) { throw "İzin verilen listede olmayan uygulama: $id" } }
    $results = @(); $idsOnce = @($Ids | Select-Object -Unique)
    $snapshot = $null
    if ($Mode -eq 'Install' -and (Test-LtLiveSystem) -and $idsOnce.Count -gt 1) {
        if ($Progress) { $Progress.Text = 'Kurulu uygulamalar okunuyor…' }
        $snapshot = Get-LtSetupInstallSnapshot
    }
    if ($Progress) { $Progress.Total=$idsOnce.Count }
    foreach ($id in $idsOnce) {
        $title = ($catalog | Where-Object Id -eq $id).Title
        if ($Cancel -and $Cancel.Requested) { $results += New-LtResult -Id $id -Title $title -Status Skipped -Message 'İptal istendi; işleme başlanmadı.'; continue }
        if ($Progress) { $Progress.Text=$title }
        try {
            if (-not (Test-LtLiveSystem)) {
                $result = New-LtResult -Id $id -Title $title -Status Skipped -Simulated $true -Message 'Kuru çalışma: uygulama işlemi simüle edildi.'
            } elseif ($Mode -eq 'Install') { $result = Install-LtSetupPackage -Id $id -KnownInstalledIds $snapshot }
            else { $result = Remove-LtOptionalApp -Id $id }
        } catch { $result = New-LtResult -Id $id -Title $title -Status Failed -Message $_.Exception.Message }
        $results += $result
        Write-LtLog ("{0}: {1} — {2}" -f $title,$result.Status,$result.Message) 'INFO'
        if ($Progress) { $Progress.Done++ }
    }
    [pscustomobject]@{ Results=$results }
}

# ---------------------------------------------------------------------------
# Kurulu uygulama envanteri (salt okunur, WinGet)
# ---------------------------------------------------------------------------
# Durumlar: Installed | NotInstalled | Unknown. WinGet yoklugu veya sorgu hatasi
# ASLA "kurulu degil" sayilmaz; tum katalog "durum okunamadi" (Unknown) olur.
# Envanter yalnizca bilgi icindir: kurulum aninda motor yeniden denetler ve
# kurulu uygulamayi yukseltmeden atlar (--no-upgrade, exact ID, winget kaynagi).
$script:LtSetupInventoryMinIntervalSec = 30
$script:LtSetupInventoryMaxAgeMinutes  = 10
$script:LtSetupStateText = @{
    Installed    = 'Kurulu'
    InstalledExternal = 'Kurulu (WinGet dışı)'
    NotInstalled = 'Kurulu değil'
    Unknown      = 'Durum okunamadı'
    Loading      = 'Okunuyor…'
    NotRead      = 'Durum henüz okunmadı'
}

function Get-LtSetupInventory {
    <#
      Donus: @{ Status = Ok|WingetMissing|WingetOutdated|Error; Message; Time; InstalledIds; ExternalIds; Simulated }
      InstalledIds = WinGet envanteri + Windows uygulama listesi (Uninstall) eslesmeleri.
      ExternalIds  = yalniz Windows uygulama listesinde bulunanlar (WinGet eslestiremedi).
      Status WinGet'in durumudur: WinGet okunamazsa listede bulunmayanlar "kurulu degil" sayilmaz.
    #>
    $now = Get-Date
    $simulated = -not (Test-LtLiveSystem)
    $arpIds = @()
    $arpNote = ''
    try { $arpIds = @(@(Get-LtSetupArpMatches -DisplayNames @(Get-LtInstalledDisplayNames -Fresh)) + @(Get-LtSetupFileMatches) | Select-Object -Unique) }
    catch { $arpNote = " Windows uygulama listesi okunamadı: $($_.Exception.Message)" }
    $catalogIds = @(Get-LtSetupApps | ForEach-Object { $_.Id })
    $status = 'Ok'; $wingetIds = @(); $msg = ''
    try {
        $raw = Read-LtWingetInventory
        if (-not $raw.Available) {
            $status = 'WingetMissing'; $msg = 'WinGet (Uygulama Yükleyici) bulunamadı; kurulum yapılamaz. Kurulu durumu yalnız Windows uygulama listesinden okundu.'
        } elseif ([bool](Get-LtProp $raw 'Outdated' $false)) {
            $status = 'WingetOutdated'; $msg = "WinGet sürümü ($(Get-LtProp $raw 'Version')) çok eski; Uygulama Yükleyici'yi güncelleyin. Kurulu durumu yalnız Windows uygulama listesinden okundu."
        } else {
            # Yalniz katalogdaki kimlikler; karsilastirma WinGet gibi buyuk/kucuk harf duyarsiz
            $wingetIds = @(@($raw.Ids) | Where-Object { $_ -and ($catalogIds -contains [string]$_) } | ForEach-Object { $id = [string]$_; @($catalogIds | Where-Object { $_ -eq $id })[0] } | Select-Object -Unique)
            $msg = if ($simulated) { 'Deneme envanteri (gerçek WinGet çalıştırılmadı).' } else { 'WinGet envanteri ve Windows uygulama listesi okundu.' }
        }
    } catch {
        $status = 'Error'; $msg = "WinGet envanteri okunamadı: $($_.Exception.Message)"
    }
    $external = @($arpIds | Where-Object { $wingetIds -notcontains $_ })
    $installed = @(@($wingetIds) + @($external) | Select-Object -Unique)
    return [pscustomobject]@{ Status = $status; Message = ($msg + $arpNote); Time = $now; InstalledIds = $installed; ExternalIds = $external; Simulated = $simulated }
}

function Get-LtSetupAppState {
    param($Inventory, [Parameter(Mandatory)][string]$Id)
    if ($null -eq $Inventory) { return 'NotRead' }
    if (@(Get-LtProp $Inventory 'InstalledIds' @()) -contains $Id) {
        if (@(Get-LtProp $Inventory 'ExternalIds' @()) -contains $Id) { return 'InstalledExternal' }
        return 'Installed'
    }
    if ([string](Get-LtProp $Inventory 'Status') -ne 'Ok') { return 'Unknown' }
    return 'NotInstalled'
}

function Get-LtSetupStateText([string]$State) {
    if ($script:LtSetupStateText.ContainsKey($State)) { return $script:LtSetupStateText[$State] }
    return $State
}

function Test-LtSetupInventoryRefresh {
    <#
      Sinirli siklik. Otomatik yenileme: hic okunmadiysa veya sonuc 10 dakikadan eskiyse.
      Kullanici yenilemesi (-Force): son denemeden en az 30 sn sonra. Okuma surerken hayir.
      Donus: @{ Allowed; Reason; WaitSeconds }
    #>
    param($LastAttempt = $null, [datetime]$Now = (Get-Date), [switch]$Force, [switch]$Running)
    if ($Running) { return [pscustomobject]@{ Allowed = $false; Reason = 'Envanter zaten okunuyor.'; WaitSeconds = 0 } }
    if ($null -eq $LastAttempt) { return [pscustomobject]@{ Allowed = $true; Reason = ''; WaitSeconds = 0 } }
    $age = ($Now - [datetime]$LastAttempt).TotalSeconds
    if ($Force) {
        if ($age -lt $script:LtSetupInventoryMinIntervalSec) {
            $wait = [int][math]::Ceiling($script:LtSetupInventoryMinIntervalSec - $age)
            return [pscustomobject]@{ Allowed = $false; Reason = "Envanter az önce okundu; $wait sn sonra yeniden deneyin."; WaitSeconds = $wait }
        }
        return [pscustomobject]@{ Allowed = $true; Reason = ''; WaitSeconds = 0 }
    }
    if ($age -ge ($script:LtSetupInventoryMaxAgeMinutes * 60)) { return [pscustomobject]@{ Allowed = $true; Reason = ''; WaitSeconds = 0 } }
    return [pscustomobject]@{ Allowed = $false; Reason = 'Envanter güncel; gerekirse elle yenileyin.'; WaitSeconds = 0 }
}
