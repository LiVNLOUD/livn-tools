# Livn Tools - Cleanup.ps1
# GERI ALINAMAZ temizlik ve bakim islemleri. Bunlar "geri alma" vaadine DAHIL
# DEGILDIR; UI bunu acikca gosterir. Silinen bayt, silmeden once tahmin edilmez;
# yalnizca GERCEKTEN silinen dosyalarin boyutu toplanir. Kilitli dosyalar
# "Kismen" olarak raporlanir.
#
# KURU CALISMA YALITIMI: Bellek arka ucunda (-DryRun, testler) Invoke-LtCleanupItem
# ogeyi SIMULE eder: Paths/Run/Processes hic degerlendirilmez. Ayrica her yan etki
# (dosya silme, surec kapatma, harici komut...) Core/SideEffects.ps1 ve
# Invoke-LtNative icindeki kapidan gecer; katalogdaki Run bloklari bu ilkelleri
# kullanmak ZORUNDADIR (tests/Static.Tests.ps1).

Set-StrictMode -Version 2.0

# ---------------------------------------------------------------------------
# Dosya silme cekirdegi
# ---------------------------------------------------------------------------
function Remove-LtFolderContents {
    <#
      Klasorun ICERIGINI siler (klasorun kendisini degil).
      - Yeniden ayristirma noktalarina (junction/symlink) inmez.
      - Salt okunur ozniteligini kaldirip dener.
      Donus: @{ Bytes; Files; Failed; Exists }
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [string]$Filter = '*', [bool]$Recurse = $true, $Cancel = $null, [ValidateRange(0,3650)][int]$OlderThanDays = 0)
    $res = @{ Bytes = [long]0; Files = 0; Failed = 0; Exists = $false; Cancelled = $false }
    # Kuru calismada yalnizca acikca ayrilmis test kokunde; aksi halde reddedilir
    Assert-LtDeletePermitted -Path $Path
    if (-not [System.IO.Directory]::Exists($Path)) { return $res }
    $res.Exists = $true
    $root = New-Object System.IO.DirectoryInfo($Path)
    $stack = New-Object System.Collections.Stack
    $stack.Push($root)
    $dirs = New-Object System.Collections.ArrayList
    $n = 0
    while ($stack.Count -gt 0) {
        $d = $stack.Pop()
        # Kok disindaki bir alt klasor kurallara uymuyorsa (baglanti, gecersiz ad) yalniz o klasor atlanir
        if ($d.FullName -ne $root.FullName) { try { Assert-LtDeletePermitted -Path $d.FullName } catch { $res.Failed++; continue } }
        else { Assert-LtDeletePermitted -Path $d.FullName }
        try { $files = $d.GetFiles($Filter) } catch { $res.Failed++; continue }
        foreach ($f in $files) {
            if ($OlderThanDays -gt 0 -and $f.LastWriteTimeUtc -ge [DateTime]::UtcNow.AddDays(-$OlderThanDays)) { continue }
            $n++
            if (($n % 200) -eq 0 -and $null -ne $Cancel -and $Cancel.Requested) { $res.Cancelled = $true; return $res }
            try {
                Assert-LtDeletePermitted -Path $f.FullName
                $len = $f.Length
                if ($f.IsReadOnly) { $f.IsReadOnly = $false }
                $f.Delete()
                $res.Bytes += $len; $res.Files++
            } catch { $res.Failed++ }
        }
        if (-not $Recurse) { continue }
        try { $subs = $d.GetDirectories() } catch { $res.Failed++; continue }
        foreach ($s in $subs) {
            if (($s.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
            [void]$dirs.Add($s)
            $stack.Push($s)
        }
    }
    # Bos kalan alt klasorleri en derinden baslayarak sil
    $sorted = @($dirs | Sort-Object { $_.FullName.Length } -Descending)
    foreach ($s in $sorted) {
        try { Assert-LtDeletePermitted -Path $s.FullName; if (@($s.GetFileSystemInfos()).Count -eq 0) { $s.Delete() } } catch { $null = $_ }
    }
    return $res
}

function Get-LtChromiumCacheDirs {
    param([string]$UserData)
    if (-not $UserData -or -not [System.IO.Directory]::Exists($UserData)) { return @() }
    $out = New-Object System.Collections.ArrayList
    foreach ($p in @(Get-ChildItem -LiteralPath $UserData -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^(Default|Profile \d+|Guest Profile)$' })) {
        foreach ($sub in @('Cache', 'Code Cache', 'GPUCache')) {
            [void]$out.Add(@{ Path = (Join-Path $p.FullName $sub); Label = "$($p.Name)\$sub" })
        }
    }
    foreach ($sub in @('ShaderCache', 'GrShaderCache')) { [void]$out.Add(@{ Path = (Join-Path $UserData $sub); Label = $sub }) }
    return @($out)
}

function Get-LtSteamPath {
    $v = $null
    try { $v = Get-LtRegValue 'HKCU\Software\Valve\Steam' 'SteamPath' } catch { return $null }
    if ($v -and $v.Exists) { return ([string]$v.Data -replace '/', '\') }
    return $null
}

function Get-LtUbisoftInstallPath {
    $candidates = @()
    foreach ($key in @('HKLM\SOFTWARE\Ubisoft\Launcher','HKLM\SOFTWARE\WOW6432Node\Ubisoft\Launcher')) {
        $v = Get-LtRegValue $key 'InstallDir'
        if ($v.Exists -and $v.Data) { $candidates += [string]$v.Data }
    }
    $candidates += "${env:ProgramFiles(x86)}\Ubisoft\Ubisoft Game Launcher"
    foreach ($path in $candidates) {
        if ([IO.Path]::IsPathRooted($path) -and (Test-Path -LiteralPath (Join-Path $path 'upc.exe') -PathType Leaf)) { return $path }
    }
    throw 'NOTSUPPORTED:Ubisoft kurulum yolu upc.exe ile doğrulanamadı; tahmini klasör temizlenmedi.'
}

# ---------------------------------------------------------------------------
# Uygulama tespiti (onbellek temizligi yalnizca kurulu uygulamalar icin etkin)
# ---------------------------------------------------------------------------
$script:LtUninstallCache = $null
function Reset-LtAppDetection { $script:LtUninstallCache = $null }
function Get-LtInstalledDisplayNames {
    # Onbellek yalnizca gercek sistemde (bellek arka ucundaki sahte registry testte degisebilir).
    # -Fresh: kurulum envanteri gibi guncel liste gereken okumalar onbellegi atlar.
    param([switch]$Fresh)
    if (-not $Fresh -and (Test-LtLiveSystem) -and $null -ne $script:LtUninstallCache) { return $script:LtUninstallCache }
    $names = New-Object System.Collections.ArrayList
    foreach ($root in @('HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall', 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')) {
        try {
            foreach ($k in @(Get-LtRegSubKeyNames $root)) {
                $v = Get-LtRegValue "$root\$k" 'DisplayName'
                if ($v.Exists -and $v.Data) { [void]$names.Add([string]$v.Data) }
            }
        } catch { $null = $_ }
    }
    if (Test-LtLiveSystem) { $script:LtUninstallCache = @($names) }
    return @($names)
}

function Test-LtAppPresent {
    param([string[]]$DisplayNames = @(), [string[]]$Paths = @())
    # Bellek arka ucunda gercek dosya sistemi yoklanmaz; yalnizca sahte registry'deki kurulu uygulamalar
    if (Test-LtLiveSystem) {
        foreach ($p in $Paths) { if ($p -and (Test-Path -LiteralPath $p)) { return $true } }
    }
    $installed = Get-LtInstalledDisplayNames
    foreach ($n in $DisplayNames) {
        foreach ($i in $installed) { if ($i -eq $n -or $i -like "$n *" -or $i -like "$n (*") { return $true } }
    }
    return $false
}

# ---------------------------------------------------------------------------
# Tanimlar
# ---------------------------------------------------------------------------
function Get-LtDesktopPath {
    <# Gercek Masaustu (OneDrive'a / baska surucuye yonlendirilmis olabilir); okunamazsa profil altindaki varsayilan. #>
    $d = ''
    try { $d = [Environment]::GetFolderPath('Desktop') } catch { $null = $_ }
    if (-not $d) { $d = "$env:USERPROFILE\Desktop" }
    return $d.TrimEnd('\')
}

function Get-LtCleanupDefinitions {
    @(
        # ----------------------------- Windows ------------------------------
        @{ Id = 'clean.temp-user'; Page = 'QuickClean'; Group = 'Windows geçici dosyalar'; Title = '%TEMP% klasörü'
           Description = 'Kullanıcının geçici dosyaları. Kullanımdaki dosyalar atlanır.'; Default = $true
           Paths = { @(@{ Path = $env:TEMP; Label = '%TEMP%' }) } }
        @{ Id = 'clean.temp-system'; Page = 'QuickClean'; Group = 'Windows geçici dosyalar'; Title = 'Windows\Temp'
           Description = 'Sistem geçici klasörü.'; Default = $true
           Paths = { @(@{ Path = "$env:SystemRoot\Temp"; Label = 'Windows\Temp' }) } }
        @{ Id = 'clean.prefetch'; Page = 'QuickClean'; Group = 'Windows geçici dosyalar'; Title = 'Prefetch'
           Description = 'Uygulama ön yükleme izleri. İlk açılışlar bir süre yavaşlar; Windows yeniden oluşturur. Performans kazancı sağlamaz.'; Default = $false
           Paths = { @(@{ Path = "$env:SystemRoot\Prefetch"; Label = 'Prefetch'; Filter = '*.pf'; Recurse = $false }) } }
        @{ Id = 'clean.recyclebin'; Page = 'QuickClean'; Group = 'Windows geçici dosyalar'; Title = 'Geri Dönüşüm Kutusu'
           Description = 'Tüm sürücülerdeki Geri Dönüşüm Kutusu kalıcı olarak boşaltılır.'; Default = $true
           Run = { param($ctx, $cancel) @{ Bytes = (Clear-LtRecycleBin); Measured = $true; Message = 'Boşaltıldı.' } } }
        @{ Id = 'clean.thumbcache'; Page = 'QuickClean'; Group = 'Windows geçici dosyalar'; Title = 'Küçük resim önbelleği'
           Description = 'thumbcache_*.db / iconcache_*.db. Explorer açıkken bazıları kilitli olabilir (Kısmen).'; Default = $false
           Paths = { @(
               @{ Path = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"; Label = 'thumbcache'; Filter = 'thumbcache_*.db'; Recurse = $false },
               @{ Path = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"; Label = 'iconcache'; Filter = 'iconcache_*.db'; Recurse = $false }) } }
        @{ Id = 'clean.fontcache'; Page = 'QuickClean'; Group = 'Windows geçici dosyalar'; Title = 'Yazı tipi önbelleği'
           Description = 'FontCache servisi durdurulur, önbellek silinir ve servis önceki durumuna döndürülür.'; Default = $false
           PreviewPaths = { @(@{ Path = "$env:SystemRoot\ServiceProfiles\LocalService\AppData\Local\FontCache"; Label = 'FontCache' }) }
           Run = {
               param($ctx, $cancel)
               $wasRunning = ((Get-LtServiceInfo -Name 'FontCache').Status -eq 'Running')
               Stop-LtServiceSafe -Name 'FontCache'
               try {
                   $r = Remove-LtFolderContents -Path "$env:SystemRoot\ServiceProfiles\LocalService\AppData\Local\FontCache" -Cancel $cancel
               } finally {
                   if ($wasRunning) { Start-LtServiceSafe -Name 'FontCache' }
               }
               @{ Bytes = $r.Bytes; Measured = $true; Failed = $r.Failed; Message = "$($r.Files) dosya silindi." }
           } }

        # ----------------------------- Tarayicilar --------------------------
        @{ Id = 'clean.chrome'; Keeps = 'Çerezler, oturumlar, geçmiş, parolalar, yer imleri ve uzantılar'; Page = 'QuickClean'; Group = 'Tarayıcı önbellekleri'; Title = 'Chrome'; Processes = @('chrome'); Default = $true
           Detect = @{ Names = @('Google Chrome'); Paths = @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe") }
           Description = 'Profil önbellekleri (Cache, Code Cache, GPUCache). Çerezler/geçmiş silinmez.'
           Paths = { @(Get-LtChromiumCacheDirs "$env:LOCALAPPDATA\Google\Chrome\User Data") } }
        @{ Id = 'clean.edge'; Keeps = 'Çerezler, oturumlar, geçmiş, parolalar, yer imleri ve uzantılar'; Page = 'QuickClean'; Group = 'Tarayıcı önbellekleri'; Title = 'Edge'; Processes = @('msedge'); Default = $true
           Detect = @{ Names = @('Microsoft Edge'); Paths = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") }
           Description = 'Profil önbellekleri. Çerezler/geçmiş silinmez.'
           Paths = { @(Get-LtChromiumCacheDirs "$env:LOCALAPPDATA\Microsoft\Edge\User Data") } }
        @{ Id = 'clean.brave'; Keeps = 'Çerezler, oturumlar, geçmiş, parolalar, yer imleri ve uzantılar'; Page = 'QuickClean'; Group = 'Tarayıcı önbellekleri'; Title = 'Brave'; Processes = @('brave'); Default = $true
           Detect = @{ Names = @('Brave'); Paths = @("$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data") }
           Description = 'Profil önbellekleri.'
           Paths = { @(Get-LtChromiumCacheDirs "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data") } }
        @{ Id = 'clean.vivaldi'; Keeps = 'Çerezler, oturumlar, geçmiş, parolalar, yer imleri ve uzantılar'; Page = 'QuickClean'; Group = 'Tarayıcı önbellekleri'; Title = 'Vivaldi'; Processes = @('vivaldi'); Default = $true
           Detect = @{ Names = @('Vivaldi'); Paths = @("$env:LOCALAPPDATA\Vivaldi\User Data") }
           Description = 'Profil önbellekleri.'
           Paths = { @(Get-LtChromiumCacheDirs "$env:LOCALAPPDATA\Vivaldi\User Data") } }
        @{ Id = 'clean.opera'; Page = 'QuickClean'; Group = 'Tarayıcı önbellekleri'; Title = 'Opera / Opera GX'; Processes = @('opera'); Default = $true
           Detect = @{ Names = @('Opera Stable', 'Opera GX Stable', 'Opera GX', 'Opera'); Paths = @("$env:APPDATA\Opera Software") }
           Description = 'Opera Stable ve Opera GX Stable önbellekleri.'
           Paths = { @(
               @{ Path = "$env:LOCALAPPDATA\Opera Software\Opera Stable\Cache"; Label = 'Opera Cache' },
               @{ Path = "$env:APPDATA\Opera Software\Opera Stable\Code Cache"; Label = 'Opera Code Cache' },
               @{ Path = "$env:LOCALAPPDATA\Opera Software\Opera GX Stable\Cache"; Label = 'Opera GX Cache' },
               @{ Path = "$env:APPDATA\Opera Software\Opera GX Stable\Code Cache"; Label = 'Opera GX Code Cache' }) } }
        @{ Id = 'clean.firefox'; Keeps = 'Profil verileri (çerezler, oturumlar, geçmiş, parolalar, yer imleri)'; Page = 'QuickClean'; Group = 'Tarayıcı önbellekleri'; Title = 'Firefox'; Processes = @('firefox'); Default = $true
           Detect = @{ Names = @('Mozilla Firefox'); Paths = @("$env:ProgramFiles\Mozilla Firefox\firefox.exe") }
           Description = 'Profillerin cache2/startupCache klasörleri (%LOCALAPPDATA% altında; eski sürüm yanlış klasöre bakıyordu).'
           Paths = {
               $base = "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"
               @(Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                   @{ Path = (Join-Path $_.FullName 'cache2'); Label = "$($_.Name)\cache2" }
                   @{ Path = (Join-Path $_.FullName 'startupCache'); Label = "$($_.Name)\startupCache" }
               }) } }

        @{ Id = 'clean.tor'; Page = 'QuickClean'; Group = 'Tarayıcı önbellekleri'; Title = 'Tor Browser'; Processes = @('firefox', 'tor'); Default = $true
           Detect = @{ Names = @('Tor Browser'); Paths = @("$env:LOCALAPPDATA\Tor Browser", "$(Get-LtDesktopPath)\Tor Browser") }
           Description = 'Tor Browser profil önbelleği (cache2).'
           Paths = { @(
               @{ Path = "$env:LOCALAPPDATA\Tor Browser\Browser\TorBrowser\Data\Browser\profile.default\cache2"; Label = 'Tor cache2' },
               @{ Path = "$(Get-LtDesktopPath)\Tor Browser\Browser\TorBrowser\Data\Browser\profile.default\cache2"; Label = 'Tor cache2 (Masaüstü)' }) } }

        # ----------------------------- Iletisim -----------------------------
        @{ Id = 'clean.discord'; Keeps = 'Oturum, ayarlar ve yerel depolama'; Page = 'QuickClean'; Group = 'İletişim uygulamaları'; Title = 'Discord'; Processes = @('Discord'); Default = $true
           Detect = @{ Names = @('Discord'); Paths = @("$env:APPDATA\discord") }
           Description = 'Cache, Code Cache, GPUCache. Oturum bilgisi silinmez.'
           Paths = { @('Cache', 'Code Cache', 'GPUCache') | ForEach-Object { @{ Path = "$env:APPDATA\discord\$_"; Label = "Discord $_" } } } }
        @{ Id = 'clean.slack'; Page = 'QuickClean'; Group = 'İletişim uygulamaları'; Title = 'Slack'; Processes = @('slack'); Default = $true
           Detect = @{ Names = @('Slack'); Paths = @("$env:APPDATA\Slack") }
           Description = 'Cache, Code Cache, GPUCache.'
           Paths = { @('Cache', 'Code Cache', 'GPUCache') | ForEach-Object { @{ Path = "$env:APPDATA\Slack\$_"; Label = "Slack $_" } } } }
        @{ Id = 'clean.teams'; Page = 'QuickClean'; Group = 'İletişim uygulamaları'; Title = 'Microsoft Teams'; Processes = @('ms-teams', 'Teams'); Default = $false
           Detect = @{ Names = @('Microsoft Teams'); Paths = @("$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe", "$env:APPDATA\Microsoft\Teams") }
           Description = 'Yeni Teams için Microsoft''un önerdiği MSTeams önbellek klasörü ve klasik Teams önbellekleri. Teams yeniden oturum açmanızı isteyebilir.'
           Paths = { @(
               @{ Path = "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams"; Label = 'Teams (yeni)' },
               @{ Path = "$env:APPDATA\Microsoft\Teams\Cache"; Label = 'Teams (klasik) Cache' },
               @{ Path = "$env:APPDATA\Microsoft\Teams\Code Cache"; Label = 'Teams (klasik) Code Cache' },
               @{ Path = "$env:APPDATA\Microsoft\Teams\GPUCache"; Label = 'Teams (klasik) GPUCache' }) } }
        @{ Id = 'clean.whatsapp'; Keeps = 'Oturum, mesaj ve medya verileri'; Page = 'QuickClean'; Group = 'İletişim uygulamaları'; Title = 'WhatsApp (masaüstü)'; Processes = @('WhatsApp'); Default = $true
           Detect = @{ Names = @('WhatsApp'); Paths = @("$env:LOCALAPPDATA\WhatsApp") }
           Description = 'Yalnızca Cache ve Code Cache. Eski sürüm Store paketinin LocalCache kökünü (oturum/mesaj verisi içerebilir) siliyordu; kaldırıldı.'
           Paths = { @('Cache', 'Code Cache') | ForEach-Object { @{ Path = "$env:LOCALAPPDATA\WhatsApp\$_"; Label = "WhatsApp $_" } } } }
        @{ Id = 'clean.zoom'; Page = 'QuickClean'; Group = 'İletişim uygulamaları'; Title = 'Zoom'; Processes = @('Zoom'); Default = $true
           Detect = @{ Names = @('Zoom', 'Zoom Workplace'); Paths = @("$env:APPDATA\Zoom") }
           Description = 'Zoom log klasörü. Toplantı kayıtları silinmez.'
           Paths = { @(@{ Path = "$env:APPDATA\Zoom\logs"; Label = 'Zoom logs' }) } }
        @{ Id = 'clean.telegram'; Keeps = 'Mesaj ve medya önbelleği, oturum'; Page = 'QuickClean'; Group = 'İletişim uygulamaları'; Title = 'Telegram (loglar)'; Processes = @('Telegram'); Default = $true
           Detect = @{ Names = @('Telegram Desktop', 'Telegram'); Paths = @("$env:APPDATA\Telegram Desktop") }
           Description = 'Yalnızca *.log dosyaları; mesaj/medya önbelleği silinmez.'
           Paths = { @(@{ Path = "$env:APPDATA\Telegram Desktop"; Label = 'Telegram log'; Filter = '*.log'; Recurse = $false }) } }
        @{ Id = 'clean.spotify'; Keeps = 'Çevrimdışı indirilen şarkılar (Data) ve hesap'; Page = 'QuickClean'; Group = 'İletişim uygulamaları'; Title = 'Spotify (akış önbelleği)'; Processes = @('Spotify'); Default = $true
           Detect = @{ Names = @('Spotify'); Paths = @("$env:APPDATA\Spotify", "$env:LOCALAPPDATA\Spotify") }
           Description = 'Yalnızca Storage (akış önbelleği). Çevrimdışı indirilen şarkılar (Data) SİLİNMEZ — eski sürüm bunları da siliyordu.'
           Paths = { @(@{ Path = "$env:LOCALAPPDATA\Spotify\Storage"; Label = 'Spotify Storage' }) } }

        # ----------------------------- Oyun baslaticilari -------------------
        @{ Id = 'clean.steam'; Keeps = 'Hesap verileri, steamapps, userdata, Workshop, shadercache ve kayıtlı oyunlar'; Page = 'QuickClean'; Group = 'Oyun başlatıcıları'; Title = 'Steam'; Processes = @('steam', 'steamwebhelper'); Default = $false; RequireClosed = $true
           Detect = @{ Names = @('Steam'); Paths = @("${env:ProgramFiles(x86)}\Steam\steam.exe") }
           Description = 'Steam web önbelleğinin Cache/Code Cache/GPUCache alt klasörleri ve appcache\httpcache. Hesap verileri, steamapps, userdata, Workshop ve shadercache korunur.'
           Paths = {
               $list = @(foreach ($part in @('Cache','Code Cache','GPUCache')) { @{ Path = "$env:LOCALAPPDATA\Steam\htmlcache\$part"; Label = "Steam $part" } })
               $sp = Get-LtSteamPath
               if ($sp) { $list += @{ Path = (Join-Path $sp 'appcache\httpcache'); Label = 'Steam httpcache' } }
               $list } }
        @{ Id = 'clean.epic'; Keeps = 'Cookies, Local Storage, oturum ve oyun dosyaları'; Page = 'QuickClean'; Group = 'Oyun başlatıcıları'; Title = 'Epic Games'; Processes = @('EpicGamesLauncher','EpicWebHelper'); Default = $false; RequireClosed = $true
           Detect = @{ Names = @('Epic Games Launcher'); Paths = @("$env:LOCALAPPDATA\EpicGamesLauncher") }
           Description = 'webcache ve numaralı webcache klasörlerindeki yalnız Cache/Code Cache/GPUCache. Cookies, Local Storage, oturum ve oyun dosyaları korunur; tam hesap sıfırlaması değildir.'
           Paths = {
               $b = "$env:LOCALAPPDATA\EpicGamesLauncher\Saved"
               @(Get-ChildItem -LiteralPath $b -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^webcache(?:_\d+)?$' } | ForEach-Object {
                   foreach ($part in @('Cache','Code Cache','GPUCache')) { @{ Path = (Join-Path $_.FullName $part); Label = "Epic $($_.Name) $part" } }
               }) } }
        @{ Id = 'clean.gog'; Keeps = 'Galaxy veritabanı, oturum, oyunlar ve 7 günden yeni loglar'; Page = 'QuickClean'; Group = 'Oyun başlatıcıları'; Title = 'GOG Galaxy'; Processes = @('GalaxyClient','GalaxyClientService','GalaxyCommunication'); Default = $false; RequireClosed = $true
           Detect = @{ Names = @('GOG GALAXY', 'GOG Galaxy'); Paths = @("$env:ProgramData\GOG.com\Galaxy") }
           Description = 'Yalnız webcache içindeki Cache/Code Cache/GPUCache ve 7 günden eski loglar. Galaxy veritabanı, oturum ve oyun dosyaları korunur.'
           Paths = {
               foreach ($part in @('Cache','Code Cache','GPUCache')) { @{ Path = "$env:ProgramData\GOG.com\Galaxy\webcache\$part"; Label = "GOG $part" } }
               @{ Path = "$env:ProgramData\GOG.com\Galaxy\logs"; Label = 'GOG logs'; OlderThanDays = 7 }
           } }
        @{ Id = 'clean.battlenet'; Supported = { param($c) 'Battle.net resmî önbellek sıfırlama yöntemi ayrıca doğrulanmalı; Agent/veri klasörleri otomatik silinmez.' }; Page = 'QuickClean'; Group = 'Oyun başlatıcıları'; Title = 'Battle.net'; Processes = @('Battle.net','Agent'); Default = $false; RequireClosed = $true
           Detect = @{ Names = @('Battle.net'); Paths = @("$env:APPDATA\Battle.net") }
           Description = 'Otomatik silme kapalı: resmî önbellek sıfırlama prosedürü ayrıca doğrulanmalı. Oyun/veri klasörleri korunur.'
           Paths = { @(@{ Path = "$env:APPDATA\Battle.net\Cache"; Label = 'Battle.net Cache' }, @{ Path = "$env:LOCALAPPDATA\Battle.net\Cache"; Label = 'Battle.net Cache (Local)' }) } }
        @{ Id = 'clean.ea'; Supported = { param($c) 'EA app menüsü > Yardım > App Recovery > Clear cache kullanın. Belirsiz cache yolu otomatik silinmez.' }; Page = 'QuickClean'; Group = 'Oyun başlatıcıları'; Title = 'EA app'; Processes = @('EADesktop'); Default = $false; RequireClosed = $true
           Detect = @{ Names = @('EA app', 'EA Desktop'); Paths = @("$env:LOCALAPPDATA\Electronic Arts\EA Desktop") }
           Description = 'EA app > Yardım > App Recovery > Clear cache. Üreticinin kurtarma aracını kullanın; Livn bu kayıttan dosya silmez.'
           Paths = { @(@{ Path = "$env:LOCALAPPDATA\Electronic Arts\EA Desktop\cache"; Label = 'EA cache' }) } }
        @{ Id = 'clean.ubisoft'; Keeps = 'Oyun dosyaları, kayıtlar ve 7 günden yeni loglar'; Page = 'QuickClean'; Group = 'Oyun başlatıcıları'; Title = 'Ubisoft Connect'; Processes = @('upc', 'UbisoftConnect'); Default = $false; RequireClosed = $true
           Detect = @{ Names = @('Ubisoft Connect', 'Uplay'); Paths = @("${env:ProgramFiles(x86)}\Ubisoft\Ubisoft Game Launcher") }
           Description = 'Başlatıcının log ve HTTP önbelleği (kurulum klasöründe). Oyun dosyalarına dokunulmaz.'
           Paths = {
               $base = Get-LtUbisoftInstallPath
               @(
                   @{ Path = (Join-Path $base 'logs'); Label = 'Ubisoft logs'; OlderThanDays = 7 },
                   @{ Path = (Join-Path $base 'cache\http'); Label = 'Ubisoft http cache' }
               ) } }
        @{ Id = 'clean.rockstar'; Keeps = 'Yerel profil, Social Club, oyun kayıtları ve 7 günden yeni raporlar'; Page = 'QuickClean'; Group = 'Oyun başlatıcıları'; Title = 'Rockstar Launcher — eski çökme raporları'; Processes = @('Launcher', 'LauncherPatcher', 'RockstarService'); Default = $false; RequireClosed = $true
           Detect = @{ Names = @('Rockstar Games Launcher'); Paths = @("$env:LOCALAPPDATA\Rockstar Games\Launcher") }
           Description = 'Yalnız mevcut Launcher\CrashReports içindeki 7 günden eski raporlar. Yerel profil, Social Club ve oyun kayıtları silinmez. Launcher adlı süreç açıksa ihtiyat gereği atlanır; hiçbir süreç zorla kapatılmaz.'
           Paths = { @(@{ Path = "$env:LOCALAPPDATA\Rockstar Games\Launcher\CrashReports"; Label = 'Rockstar CrashReports'; OlderThanDays = 7 }) } }
        @{ Id = 'clean.xbox'; Supported = { param($c) 'Xbox için Windows Ayarları > Uygulamalar > Xbox > Gelişmiş seçenekler > Onar kullanın. LocalCache kökü otomatik silinmez.' }; Page = 'QuickClean'; Group = 'Oyun başlatıcıları'; Title = 'Xbox uygulaması'; Processes = @('XboxPcApp'); Default = $false; RequireClosed = $true
           Detect = @{ Names = @(); Paths = @("$env:LOCALAPPDATA\Packages\Microsoft.GamingApp_8wekyb3d8bbwe") }
           Description = 'Windows Ayarları > Uygulamalar > Xbox > Gelişmiş seçenekler > Onar. Livn LocalCache kökünü silmez.'
           Paths = { @(@{ Path = "$env:LOCALAPPDATA\Packages\Microsoft.GamingApp_8wekyb3d8bbwe\LocalCache"; Label = 'Xbox LocalCache' }) } }
        @{ Id = 'clean.riot'; Keeps = 'Vanguard, oyunlar, yapılandırma ve 7 günden yeni loglar'; Page = 'QuickClean'; Group = 'Oyun başlatıcıları'; Title = 'Riot Client'; Processes = @('RiotClientServices'); Default = $false; RequireClosed = $true
           Detect = @{ Names = @('Riot Client', 'Riot Vanguard', 'VALORANT', 'League of Legends'); Paths = @("$env:LOCALAPPDATA\Riot Games") }
           Description = 'Riot Client Cache/Code Cache/GPUCache ve 7 günden eski VALORANT logları. Vanguard, oyunlar ve yapılandırma korunur.'
           Paths = { @(
               @{ Path = "$env:LOCALAPPDATA\Riot Games\Riot Client\Cache"; Label = 'Riot Cache' },
               @{ Path = "$env:LOCALAPPDATA\Riot Games\Riot Client\Code Cache"; Label = 'Riot Code Cache' },
               @{ Path = "$env:LOCALAPPDATA\Riot Games\Riot Client\GPUCache"; Label = 'Riot GPUCache' },
               @{ Path = "$env:LOCALAPPDATA\VALORANT\Saved\Logs"; Label = 'VALORANT Logs'; OlderThanDays = 7 }) } }
        @{ Id = 'clean.minecraft'; Keeps = 'Dünyalar, modlar, sürümler, varlıklar, hesap dosyaları ve 7 günden yeni loglar'; Page = 'QuickClean'; Group = 'Oyun başlatıcıları'; Title = 'Minecraft Java — eski loglar'; Processes = @('java','javaw','Minecraft','MinecraftLauncher'); Default = $false; RequireClosed = $true
           Detect = @{ Names = @('Minecraft Launcher'); Paths = @("$env:APPDATA\.minecraft") }
           Description = 'Yalnız varsayılan .minecraft içindeki 7 günden eski loglar ve çökme raporları. Dünyalar, modlar, sürümler, varlıklar ve hesap dosyaları korunur. Bedrock ve özel instance klasörleri kapsam dışı. Java açıksa zorla kapatılmaz.'
           Paths = { @(@{ Path = "$env:APPDATA\.minecraft\logs"; Label = 'Minecraft logs'; OlderThanDays = 7 }, @{ Path = "$env:APPDATA\.minecraft\crash-reports"; Label = 'Minecraft crash-reports'; OlderThanDays = 7 }) } }

        # ----------------------------- Log ve sistem ------------------------
        @{ Id = 'clean.dns'; Page = 'QuickClean'; Group = 'Log ve sistem'; Title = 'DNS önbelleğini boşalt'
           Description = 'ipconfig /flushdns (çıkış kodu doğrulanır).'; Default = $true
           Run = { param($ctx, $cancel) [void](Invoke-LtNativeChecked -FilePath "$env:SystemRoot\System32\ipconfig.exe" -Arguments @('/flushdns') -TimeoutSec 60); @{ Bytes = 0; Message = 'DNS önbelleği boşaltıldı.' } } }
        @{ Id = 'clean.crashdumps'; Page = 'QuickClean'; Group = 'Log ve sistem'; Title = 'Çökme dökümleri (*.dmp)'
           Description = 'Minidump, kullanıcı CrashDumps ve MEMORY.DMP. Sorun giderme verisi kaybolur.'; Default = $false
           Paths = { @(
               @{ Path = "$env:SystemRoot\Minidump"; Label = 'Minidump'; Filter = '*.dmp'; Recurse = $false },
               @{ Path = "$env:LOCALAPPDATA\CrashDumps"; Label = 'CrashDumps'; Filter = '*.dmp'; Recurse = $false }) }
           PreviewPaths = { @(@{ File = "$env:SystemRoot\MEMORY.DMP"; Label = 'MEMORY.DMP' }) }
           Run = {
               param($ctx, $cancel)
               @{ Bytes = (Remove-LtFileSafe -Path "$env:SystemRoot\MEMORY.DMP"); Measured = $true; Message = '' }
           } }
        @{ Id = 'clean.eventlogs'; Page = 'QuickClean'; Group = 'Log ve sistem'; Title = 'Windows olay günlüklerini temizle'
           Description = 'Tüm olay günlükleri silinir (Güvenlik günlüğü dahil; 1102 olayı oluşur). Sorun giderme kayıtları kaybolur.'; Default = $false
           Run = {
               param($ctx, $cancel)
               $list = Invoke-LtNativeChecked -FilePath "$env:SystemRoot\System32\wevtutil.exe" -Arguments @('el') -TimeoutSec 120
               $ok = 0; $fail = 0
               foreach ($ln in ($list.StdOut -split "`r?`n")) {
                   if ([string]::IsNullOrWhiteSpace($ln)) { continue }
                   if ($null -ne $cancel -and $cancel.Requested) { break }
                   $r = Invoke-LtNative -FilePath "$env:SystemRoot\System32\wevtutil.exe" -Arguments @('cl', $ln.Trim()) -TimeoutSec 60
                   if ($r.ExitCode -eq 0) { $ok++ } else { $fail++ }
               }
               @{ Bytes = 0; Failed = $fail; Message = "$ok günlük temizlendi, $fail günlük temizlenemedi (bazı analitik/hata ayıklama günlükleri temizlenemez)." }
           } }
        @{ Id = 'clean.wucache'; Page = 'QuickClean'; Group = 'Log ve sistem'; Title = 'Windows Update indirme önbelleği'
           Description = 'SoftwareDistribution\Download. wuauserv/bits durdurulur, sonra önceki durumlarına döndürülür. Bekleyen güncellemeler yeniden indirilir.'; Default = $false
           PreviewPaths = { @(@{ Path = "$env:SystemRoot\SoftwareDistribution\Download"; Label = 'SoftwareDistribution\Download' }) }
           Run = {
               param($ctx, $cancel)
               $state = @{}
               foreach ($s in @('wuauserv', 'bits')) { $state[$s] = ((Get-LtServiceInfo -Name $s).Status -eq 'Running'); Stop-LtServiceSafe -Name $s -TimeoutSec 30 }
               try { $r = Remove-LtFolderContents -Path "$env:SystemRoot\SoftwareDistribution\Download" -Cancel $cancel }
               finally { foreach ($s in @('bits', 'wuauserv')) { if ($state[$s]) { try { Start-LtServiceSafe -Name $s } catch { Write-LtLog "  $s yeniden başlatılamadı: $($_.Exception.Message)" 'WARN' } } } }
               @{ Bytes = $r.Bytes; Measured = $true; Failed = $r.Failed; Message = "$($r.Files) dosya silindi." }
           } }
        @{ Id = 'clean.deliveryopt'; Page = 'QuickClean'; Group = 'Log ve sistem'; Title = 'Teslim İyileştirme önbelleği'
           Description = 'Delete-DeliveryOptimizationCache (Windows cmdlet''i).'; Default = $true
           # Windows 10 1809+ cmdlet'i; yoksa Desteklenmiyor (klasore dogrudan dokunulmaz)
           Run = { param($ctx, $cancel) @{ Bytes = (Invoke-LtDeliveryOptimizationCleanup); Measured = $true; Message = 'Önbellek temizlendi.' } } }

        # ----------------------------- Gelismis -----------------------------
        @{ Id = 'adv.component-cleanup'; Page = 'AdvancedClean'; Group = 'Bileşen deposu'; Title = 'WinSxS temizliği (DISM StartComponentCleanup)'
           Description = 'Eski bileşen sürümlerini kaldırır. Süre: dakikalar. Çıkış kodu doğrulanır.'; Default = $false; LongRunning = $true
           Run = { param($ctx, $cancel) Invoke-LtDism -Arguments @('/Online', '/Cleanup-Image', '/StartComponentCleanup') } }
        @{ Id = 'adv.component-resetbase'; Page = 'AdvancedClean'; Group = 'Bileşen deposu'; Title = 'WinSxS temizliği + /ResetBase'
           Description = 'Daha fazla yer açar ama YÜKLÜ GÜNCELLEMELER ARTIK KALDIRILAMAZ.'; Default = $false; LongRunning = $true
           Warning = '/ResetBase sonrası mevcut güncellemeler kaldırılamaz.'
           Run = { param($ctx, $cancel) Invoke-LtDism -Arguments @('/Online', '/Cleanup-Image', '/StartComponentCleanup', '/ResetBase') } }
        @{ Id = 'adv.sfc'; Page = 'AdvancedClean'; Group = 'Onarım'; Title = 'Sistem dosyası denetimi (sfc /scannow)'
           Description = 'Bozuk sistem dosyalarını tarar/onarır. Ayrıntı: %windir%\Logs\CBS\CBS.log.'; Default = $false; LongRunning = $true
           Run = {
               param($ctx, $cancel)
               $r = Invoke-LtNative -FilePath "$env:SystemRoot\System32\sfc.exe" -Arguments @('/scannow') -TimeoutSec 7200 -OutputEncoding Unicode
               foreach ($ln in ($r.StdOut -split "`r?`n")) { $t = $ln.Trim(); if ($t -and $t -notmatch '\d+\s?%') { Write-LtLog "  [SFC] $t" 'INFO' } }
               if ($r.TimedOut) { throw 'SFC zaman aşımına uğradı.' }
               if ($r.ExitCode -ne 0) { throw "SFC çıkış kodu $($r.ExitCode). Ayrıntı için CBS.log'a bakın." }
               @{ Bytes = 0; Message = 'SFC tamamlandı (çıkış kodu 0). Bu bir onarım denetimidir, dosya silmez; boyut ölçülmez. Ayrıntı yukarıdaki çıktıda ve CBS.log''da.' }
           } }
        @{ Id = 'adv.dism-restore'; Page = 'AdvancedClean'; Group = 'Onarım'; Title = 'DISM /RestoreHealth'
           Description = 'Bileşen deposunu Windows Update üzerinden onarır (internet gerekir).'; Default = $false; LongRunning = $true
           Run = { param($ctx, $cancel) Invoke-LtDism -Arguments @('/Online', '/Cleanup-Image', '/RestoreHealth') } }
        @{ Id = 'adv.cleanmgr'; Page = 'AdvancedClean'; Group = 'Disk'; Title = 'Disk Temizleme (cleanmgr /sagerun)'
           Description = 'Güvenli kategorilerle Windows Disk Temizleme çalıştırılır. Kategori seçimi StateFlags0777 değerine yazılır.'; Default = $false; LongRunning = $true
           Run = {
               param($ctx, $cancel)
               $root = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
               foreach ($c in @('Temporary Files', 'Temporary Setup Files', 'Old ChkDsk Files', 'Setup Log Files', 'Thumbnail Cache', 'Update Cleanup', 'Windows Error Reporting Files', 'Delivery Optimization Files')) {
                   if (Test-LtRegKey "$root\$c") { [void](Set-LtRegValue -Path "$root\$c" -Name 'StateFlags0777' -Kind DWord -Data 2) }
               }
               $freeBefore = Get-LtSystemDriveFreeBytes
               $p = Start-LtProcessAndWait -FilePath "$env:SystemRoot\System32\cleanmgr.exe" -Arguments '/sagerun:777' -TimeoutMinutes 30 -Cancel $cancel
               if (-not $p.Exited) { throw 'Disk Temizleme 30 dakika içinde bitmedi veya iptal edildi (arka planda sürebilir).' }
               $freeAfter = Get-LtSystemDriveFreeBytes
               $delta = $freeAfter - $freeBefore
               if ($freeBefore -le 0 -or $freeAfter -le 0) { return @{ Bytes = 0; Message = "Disk Temizleme bitti (çıkış kodu $($p.ExitCode)). Sistem sürücüsünün boş alanı okunamadığı için açılan alan ölçülmedi." } }
               if ($delta -le 0) { return @{ Bytes = 0; Measured = $true; Message = "Disk Temizleme bitti (çıkış kodu $($p.ExitCode)). Boş alanda ölçülebilir artış olmadı; seçili kategorilerde temizlenecek öğe kalmamış olabilir (ör. Hızlı Temizlik veya DISM önce çalıştıysa)." } }
               @{ Bytes = $delta; Measured = $true; Message = ("Disk Temizleme bitti (çıkış kodu {0}). Boş alan yaklaşık {1} arttı (aynı anda yazan başka işlemler farkı etkileyebilir)." -f $p.ExitCode, (Format-LtBytes $delta)) }
           } }
        @{ Id = 'adv.usb-ghosts'; Page = 'AdvancedClean'; Group = 'Gizlilik'; Title = 'Bağlı olmayan USB depolama aygıt kayıtlarını kaldır'
           Description = 'Şu an takılı OLMAYAN USBSTOR aygıtlarını pnputil /remove-device ile kaldırır (Windows 10 2004+). Eski sürümün MountedDevices silmesi kaldırıldı (dahili sürücü harflerini bozabiliyordu).'; Default = $false
           Supported = { param($c) if ($c.Build -lt 19041) { 'pnputil /remove-device Windows 10 2004 (19041) ve sonrası gerektirir.' } }
           Run = {
               param($ctx, $cancel)
               $ghost = @(Get-LtGhostUsbStorage)
               $ok = 0; $fail = 0
               foreach ($d in $ghost) {
                   $r = Invoke-LtNative -FilePath "$env:SystemRoot\System32\pnputil.exe" -Arguments @('/remove-device', $d.InstanceId) -TimeoutSec 60
                   if ($r.ExitCode -eq 0) { $ok++ } else { $fail++ }
               }
               @{ Bytes = 0; Failed = $fail; Message = "$ok aygıt kaydı kaldırıldı, $fail kaldırılamadı ($($ghost.Count) bağlı olmayan USB depolama aygıtı bulundu)." }
           } }

        # ----------------------------- Tek seferlik (diger sayfalar) ---------
        @{ Id = 'mem.purge-standby'; Page = 'Performance'; Group = 'Bellek (tek seferlik)'; Title = 'Bekleme (standby) listesini şimdi boşalt'
           Description = 'NtSetSystemInformation(MemoryPurgeStandbyList). ISLC gerekmez. Önbellek boşaldığı için sonraki dosya erişimleri bir süre yavaşlayabilir.'; Default = $false
           Run = { param($ctx, $cancel) $r = Invoke-LtMemoryList -Command PurgeStandby; if ($r.Status -ne 'Success') { throw $r.Message }; @{ Bytes = $r.BytesFreed; Message = $r.Message } } }
        @{ Id = 'mem.flush-modified'; Page = 'Performance'; Group = 'Bellek (tek seferlik)'; Title = 'Değiştirilmiş (modified) listeyi şimdi diske yaz'
           Description = 'NtSetSystemInformation(MemoryFlushModifiedList).'; Default = $false
           Run = { param($ctx, $cancel) $r = Invoke-LtMemoryList -Command FlushModified; if ($r.Status -ne 'Success') { throw $r.Message }; @{ Bytes = $r.BytesFreed; Message = $r.Message } } }
        @{ Id = 'net.stack-reset'; Page = 'Network'; Group = 'Onarım (geri alınamaz)'; Title = 'TCP/IP ve Winsock sıfırla'
           Description = 'netsh int ip reset + netsh winsock reset. Statik IP, VPN ve LSP ayarları sıfırlanabilir. Yeniden başlatma gerekir.'; Default = $false
           Warning = 'Ağ yapılandırması sıfırlanır; statik IP/DNS ayarlarını not edin.'
           Run = {
               param($ctx, $cancel)
               [void](Invoke-LtNativeChecked -FilePath "$env:SystemRoot\System32\netsh.exe" -Arguments @('int', 'ip', 'reset') -SuccessCodes @(0, 1) -TimeoutSec 120)
               [void](Invoke-LtNativeChecked -FilePath "$env:SystemRoot\System32\netsh.exe" -Arguments @('winsock', 'reset') -TimeoutSec 120)
               @{ Bytes = 0; Restart = $true; Message = 'Sıfırlandı. Yeniden başlatma gerekir.' }
           } }
        @{ Id = 'priv.onedrive-uninstall'; Page = 'Privacy'; Group = 'Kaldırma (geri alınamaz)'; Title = 'OneDrive''ı kaldır'
           Description = 'OneDriveSetup /uninstall çalıştırılır. Dosyalarınız silinmez; geri almak için OneDrive''ı yeniden yükleyin.'; Default = $false
           Warning = 'OneDrive eşitlemesi durur.'
           Run = {
               param($ctx, $cancel)
               $setup = @("$env:SystemRoot\System32\OneDriveSetup.exe", "$env:SystemRoot\SysWOW64\OneDriveSetup.exe") + @(Get-ChildItem -Path "$env:LOCALAPPDATA\Microsoft\OneDrive" -Recurse -Filter 'OneDriveSetup.exe' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
               if (-not $setup) { throw 'NOTSUPPORTED:OneDriveSetup.exe bulunamadı (OneDrive kurulu olmayabilir).' }
               Stop-LtProcessSafe -Names @('OneDrive')
               $r = Invoke-LtNative -FilePath $setup -Arguments @('/uninstall') -TimeoutSec 600
               if ($r.ExitCode -ne 0) { throw "OneDriveSetup çıkış kodu $($r.ExitCode)." }
               $left = @("$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe", "$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe", "${env:ProgramFiles(x86)}\Microsoft OneDrive\OneDrive.exe") | Where-Object { $_ -and -not $_.StartsWith('\') -and (Test-Path -LiteralPath $_) }
               if (@($left).Count -gt 0) { throw "Kaldırma komutu başarılı döndü ancak OneDrive.exe hâlâ mevcut: $(@($left)[0])" }
               @{ Bytes = 0; Message = 'OneDrive kaldırıldı ve doğrulandı.' }
           } }
    )
}

function Get-LtSystemDriveFreeBytes {
    <# Sistem surucusundeki bos alan (salt okunur); okunamazsa 0. #>
    try {
        $name = ([string]$env:SystemDrive).TrimEnd(':')
        if (-not $name) { return [long]0 }
        $d = Get-PSDrive -Name $name -ErrorAction Stop
        return [long]$d.Free
    } catch { return [long]0 }
}

function Invoke-LtDism {
    param([string[]]$Arguments)
    $r = Invoke-LtNative -FilePath "$env:SystemRoot\System32\dism.exe" -Arguments (@($Arguments) + '/NoRestart') -TimeoutSec 7200
    foreach ($ln in ($r.StdOut -split "`r?`n")) {
        $t = $ln.Trim()
        if ($t -and $t -notmatch '\[=*\s*[\d.,]+%' -and $t -notmatch '^[\d.,]+%') { Write-LtLog "  [DISM] $t" 'INFO' }
    }
    if ($r.TimedOut) { throw 'DISM zaman aşımına uğradı.' }
    # 0 = basarili, 3010 = basarili, yeniden baslatma gerekli
    # DISM acilan alani bildirmez; Bytes olculmus sayilmaz (Measured yok)
    if ($r.ExitCode -eq 3010) { return @{ Bytes = 0; Restart = $true; Message = 'DISM tamamlandı (3010: yeniden başlatma gerekli). Açılan alan DISM tarafından bildirilmez; ölçülmedi.' } }
    if ($r.ExitCode -ne 0) { throw ('DISM çıkış kodu {0} (0x{0:X8}). Ayrıntı: %windir%\Logs\DISM\dism.log' -f $r.ExitCode) }
    return @{ Bytes = 0; Message = 'DISM tamamlandı (çıkış kodu 0). Açılan alan DISM tarafından bildirilmez; ölçülmedi.' }
}

# ---------------------------------------------------------------------------
# TEMIZLIK ONIZLEMESI (salt okunur)
# ---------------------------------------------------------------------------
# Silme ile AYNI secim kurallari (filtre, alt klasor, yas, baglanti atlama, yol
# sinirlari) kullanilir; hicbir dosya degistirilmez, uygulama kapatilmaz, Run
# bloklari (bakim komutlari) calistirilmaz. Sonuc TAHMINDIR: silme ani yeniden
# taranir ve her dosya icin yol/kapsam/baglanti kontrolleri silme aninda tekrar yapilir.
function Get-LtDeleteScopeIssue {
    <# $null = silme kurallarina gore taranabilir/silinebilir; aksi halde neden. Istisna firlatmaz. #>
    param([string]$Path)
    if (-not (Test-LtSafeDeletePath $Path)) { return 'güvenlik sınırı dışında; taranmadı ve silinmez' }
    try { Assert-LtNoReparsePath -Path $Path } catch { return 'bağlantı (junction/symlink) üzerinden; taranmadı ve silinmez' }
    return $null
}

function Get-LtDirFiles {
    <# Klasor dosyalari (ayri fonksiyon: testlerde erisim hatasi enjekte edilebilir). #>
    param([Parameter(Mandatory)][System.IO.DirectoryInfo]$Directory, [string]$Filter = '*')
    return $Directory.GetFiles($Filter)
}

function Measure-LtFolderContents {
    <#
      Remove-LtFolderContents'in silecegi dosyalari SAYAR; hicbir seyi degistirmez.
      Donus: @{ Exists; Files; Bytes; Unreadable; LinksSkipped; Cancelled; Truncated; OutOfScope }
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Path, [string]$Filter = '*', [bool]$Recurse = $true, $Cancel = $null,
          [ValidateRange(0,3650)][int]$OlderThanDays = 0, [int]$MaxFiles = 1000000)
    $res = @{ Exists = $false; Files = 0; Bytes = [long]0; Unreadable = 0; LinksSkipped = 0; Cancelled = $false; Truncated = $false; OutOfScope = '' }
    $issue = Get-LtDeleteScopeIssue -Path $Path
    if ($issue) { $res.OutOfScope = $issue; return $res }
    if (-not [System.IO.Directory]::Exists($Path)) { return $res }
    $res.Exists = $true
    $cutoff = [DateTime]::UtcNow.AddDays(-$OlderThanDays)
    $stack = New-Object System.Collections.Stack
    $stack.Push((New-Object System.IO.DirectoryInfo($Path)))
    $n = 0
    while ($stack.Count -gt 0) {
        $d = $stack.Pop()
        try { $files = @(Get-LtDirFiles -Directory $d -Filter $Filter) } catch { $res.Unreadable++; continue }
        foreach ($f in $files) {
            if ($OlderThanDays -gt 0 -and $f.LastWriteTimeUtc -ge $cutoff) { continue }
            $n++
            if (($n % 200) -eq 0 -and $null -ne $Cancel -and $Cancel.Requested) { $res.Cancelled = $true; return $res }
            # Silme sirasinda baglanti dosyalari reddedilir (Assert-LtDeletePermitted); burada da sayilmaz
            if (($f.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { $res.LinksSkipped++; continue }
            if ($res.Files -ge $MaxFiles) { $res.Truncated = $true; return $res }
            try { $res.Bytes += [long]$f.Length; $res.Files++ } catch { $res.Unreadable++ }
        }
        if (-not $Recurse) { continue }
        try { $subs = $d.GetDirectories() } catch { $res.Unreadable++; continue }
        foreach ($s in $subs) {
            if (($s.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { $res.LinksSkipped++; continue }
            $stack.Push($s)
        }
    }
    return $res
}

function Format-LtCleanupScope {
    <# Hedef kapsamini Turkce acikla (ne silinir / ne korunur). #>
    param($Spec)
    if (Get-LtProp $Spec 'File') { return 'yalnız bu dosya' }
    $parts = New-Object System.Collections.ArrayList
    $filter = [string](Get-LtProp $Spec 'Filter' '*')
    if ($filter -eq '*') { [void]$parts.Add('klasörün içeriği (klasörün kendisi korunur)') } else { [void]$parts.Add("yalnız $filter") }
    if (-not [bool](Get-LtProp $Spec 'Recurse' $true)) { [void]$parts.Add('alt klasörlere inilmez') } else { [void]$parts.Add('alt klasörler dahil') }
    $days = [int](Get-LtProp $Spec 'OlderThanDays' 0)
    if ($days -gt 0) { [void]$parts.Add("yalnız $days günden eski dosyalar") }
    [void]$parts.Add('bağlantılar (junction/symlink) izlenmez')
    return ($parts -join ', ')
}

function Get-LtCleanupItemPreview {
    <#
      Tek ogenin salt okunur onizlemesi.
      Status: Ready | NotSupported | Simulated | Error | Cancelled
      Kind  : Files | Maintenance | Mixed
    #>
    param([Parameter(Mandatory)]$Item, [Parameter(Mandatory)]$Context, $Cancel = $null)
    $hasPaths = [bool](Get-LtProp $Item 'Paths')
    $hasRun = [bool](Get-LtProp $Item 'Run')
    $preview = Get-LtProp $Item 'PreviewPaths'
    $kind = if ($hasRun -and -not $hasPaths -and -not $preview) { 'Maintenance' } elseif ($hasRun) { 'Mixed' } else { 'Files' }
    $p = [ordered]@{
        Id = $Item.Id; Title = $Item.Title; Kind = $kind; Status = 'Ready'; Message = ''
        Files = 0; Bytes = [long]0; Targets = @(); Notes = @(); RunningApps = @()
        Keeps = [string](Get-LtProp $Item 'Keeps' 'Hedef klasörler dışındaki her şey (hesap, oturum, ayarlar, kayıtlı oyun/mod ve kişisel dosyalar)')
        Complete = $true
    }
    $why = Get-LtCleanupAvailability $Item $Context
    if ($why) { $p.Status = 'NotSupported'; $p.Message = $why; $p.Complete = $false; return [pscustomobject]$p }
    if (-not (Test-LtLiveSystem) -and -not (Test-LtCleanupSandbox)) {
        # Kuru calisma: gercek dosya sistemi taranmaz, hedef bloklari degerlendirilmez
        $p.Status = 'Simulated'; $p.Complete = $false
        $p.Message = 'Kuru çalışma: gerçek dosya sistemi taranmadı; sayı ve boyut gösterilmez.'
        return [pscustomobject]$p
    }
    $notes = New-Object System.Collections.ArrayList
    $running = @(Get-LtRunningProcessesFor $Item | ForEach-Object { $_.ProcessName } | Select-Object -Unique)
    if ($running.Count -gt 0) {
        $p.RunningApps = $running
        if (Get-LtProp $Item 'RequireClosed' $false) { [void]$notes.Add("Açık: $($running -join ', '). Temizlik sırasında kapalı değilse atlanır; Livn bu süreçleri kapatmaz.") }
        else { [void]$notes.Add("Açık: $($running -join ', '). Temizlikte kapatma sorulur; kullanımdaki dosyalar atlanır.") }
    }
    $specs = New-Object System.Collections.ArrayList
    try {
        foreach ($sb in @((Get-LtProp $Item 'Paths'), $preview)) {
            if (-not $sb) { continue }
            foreach ($spec in @(& $sb)) { if ($null -ne $spec) { [void]$specs.Add($spec) } }
        }
    } catch {
        $msg = $_.Exception.Message
        if ($msg -like 'NOTSUPPORTED:*') { $p.Status = 'NotSupported'; $p.Message = $msg.Substring(13) }
        else { $p.Status = 'Error'; $p.Message = "Hedefler okunamadı: $msg" }
        $p.Complete = $false
        $p.Notes = @($notes)
        return [pscustomobject]$p
    }
    $targets = New-Object System.Collections.ArrayList
    foreach ($spec in $specs) {
        if ($null -ne $Cancel -and $Cancel.Requested) { $p.Status = 'Cancelled'; $p.Complete = $false; break }
        $label = [string](Get-LtProp $spec 'Label' '')
        $file = [string](Get-LtProp $spec 'File' '')
        $t = [ordered]@{ Label = $label; Path = $(if ($file) { $file } else { [string](Get-LtProp $spec 'Path' '') }); Scope = (Format-LtCleanupScope $spec); State = 'Scanned'; Files = 0; Bytes = [long]0; Note = '' }
        if ($file) {
            $issue = Get-LtDeleteScopeIssue -Path $file
            if ($issue) { $t.State = 'OutOfScope'; $t.Note = $issue }
            elseif ([System.IO.File]::Exists($file)) { $t.Files = 1; $t.Bytes = [long](New-Object System.IO.FileInfo($file)).Length }
            else { $t.State = 'Missing'; $t.Note = 'dosya yok' }
        } else {
            $m = Measure-LtFolderContents -Path $t.Path -Filter ([string](Get-LtProp $spec 'Filter' '*')) -Recurse ([bool](Get-LtProp $spec 'Recurse' $true)) -Cancel $Cancel -OlderThanDays ([int](Get-LtProp $spec 'OlderThanDays' 0))
            $t.Files = $m.Files; $t.Bytes = $m.Bytes
            if ($m.OutOfScope) { $t.State = 'OutOfScope'; $t.Note = $m.OutOfScope }
            elseif (-not $m.Exists) { $t.State = 'Missing'; $t.Note = 'klasör yok' }
            else {
                $extra = New-Object System.Collections.ArrayList
                if ($m.Unreadable -gt 0) { $t.State = 'Partial'; [void]$extra.Add("$($m.Unreadable) klasör/dosya erişim hatası nedeniyle taranamadı") }
                if ($m.LinksSkipped -gt 0) { [void]$extra.Add("$($m.LinksSkipped) bağlantı atlandı") }
                if ($m.Truncated) { $t.State = 'Partial'; [void]$extra.Add('dosya sınırına ulaşıldı; toplam eksik') }
                if ($m.Cancelled) { $t.State = 'Partial'; [void]$extra.Add('iptal edildi') }
                $t.Note = ($extra -join '; ')
            }
            if ($m.Cancelled) { $p.Status = 'Cancelled' }
        }
        if ($t.State -in @('Partial', 'OutOfScope')) { $p.Complete = $false }
        $p.Files += $t.Files; $p.Bytes += $t.Bytes
        [void]$targets.Add([pscustomobject]$t)
    }
    if ($hasRun) {
        if ($preview) { [void]$notes.Add('Ek bakım adımları (servis durdurma/başlatma vb.) önizlemede çalıştırılmaz.') }
        else { [void]$notes.Add('Bakım/komut işlemi: boyutu önceden güvenilir biçimde hesaplanamaz; tahmin gösterilmez.') }
        if ($kind -eq 'Maintenance') { $p.Complete = $false }
    }
    if ($specs.Count -eq 0 -and -not $hasRun) { [void]$notes.Add('Bu sistemde taranacak hedef bulunamadı.') }
    $p.Targets = @($targets)
    $p.Notes = @($notes)
    return [pscustomobject]$p
}

function Get-LtCleanupPreview {
    <# Secili temizlik ogelerinin salt okunur onizlemesi. Hicbir dosyayi silmez veya degistirmez. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Ids, [Parameter(Mandatory)]$Context, $Progress = $null, $Cancel = $null)
    $ids2 = @($Ids | Select-Object -Unique)
    $items = New-Object System.Collections.ArrayList
    $i = 0
    foreach ($id in $ids2) {
        $item = Get-LtCleanupItem $id
        if ($null -ne $Cancel -and $Cancel.Requested) {
            [void]$items.Add([pscustomobject]@{ Id = $id; Title = $item.Title; Kind = ''; Status = 'Cancelled'; Message = 'İptal edildi; taranmadı.'; Files = 0; Bytes = [long]0; Targets = @(); Notes = @(); RunningApps = @(); Keeps = ''; Complete = $false })
            continue
        }
        Update-LtProgress $Progress $i $ids2.Count "Önizleme (salt okunur): $($item.Title)"
        try { [void]$items.Add((Get-LtCleanupItemPreview -Item $item -Context $Context -Cancel $Cancel)) }
        catch { [void]$items.Add([pscustomobject]@{ Id = $id; Title = $item.Title; Kind = ''; Status = 'Error'; Message = $_.Exception.Message; Files = 0; Bytes = [long]0; Targets = @(); Notes = @(); RunningApps = @(); Keeps = ''; Complete = $false }) }
        $i++
    }
    Update-LtProgress $Progress $ids2.Count $ids2.Count 'Önizleme tamamlandı'
    $files = 0; $bytes = [long]0
    foreach ($x in $items) { $files += [int]$x.Files; $bytes += [long]$x.Bytes }
    return [pscustomobject]@{
        Items = @($items); Files = $files; Bytes = $bytes
        Simulated = (-not (Test-LtLiveSystem) -and -not (Test-LtCleanupSandbox))
        Cancelled = [bool]($null -ne $Cancel -and $Cancel.Requested)
        Complete = (@($items | Where-Object { -not $_.Complete }).Count -eq 0)
    }
}

$script:LtCleanupCache = $null
function Get-LtCleanupCatalog {
    param([switch]$Refresh)
    if ($Refresh -or $null -eq $script:LtCleanupCache) { $script:LtCleanupCache = @(Get-LtCleanupDefinitions) }
    return $script:LtCleanupCache
}

function Get-LtCleanupItem([string]$Id) {
    $i = Get-LtCleanupCatalog | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
    if (-not $i) { throw "Bilinmeyen temizlik kimliği: $Id" }
    return $i
}

function Get-LtCleanupAvailability {
    <# Donus: $null = kullanilabilir, metin = neden kullanilamaz (uygulama yuklu degil vb.) #>
    param([Parameter(Mandatory)]$Item, [Parameter(Mandatory)]$Context)
    $sb = Get-LtProp $Item 'Supported'
    if ($sb) { $r = & $sb $Context; if ($r) { return [string]$r } }
    $det = Get-LtProp $Item 'Detect'
    if ($det -and -not (Test-LtAppPresent -DisplayNames @($det.Names) -Paths @($det.Paths))) { return 'Uygulama bu sistemde bulunamadı.' }
    return $null
}

function Get-LtRunningProcessesFor {
    param([Parameter(Mandatory)]$Item)
    $names = @(Get-LtProp $Item 'Processes' @())
    if ($names.Count -eq 0) { return @() }
    # Yalnizca gorunur penceresi olan surecler (arka plan yardimcilari - ornegin Edge
    # baslangic hizlandirma - uygulamanin "acik" sayilmasina neden olmaz; kilitli
    # dosyalar zaten "Kismen" olarak raporlanir).
    # Bellek arka ucunda gercek surec listesi okunmaz (Core/SideEffects.ps1)
    if (Get-LtProp $Item 'RequireClosed' $false) { return @(Get-LtProcessesByName -Names $names) }
    return @(Get-LtProcessesByName -Names $names -WithWindow)
}

function Test-LtCleanupUserScoped {
    <# Ogenin kullanici profiline (TEMP/AppData/Masaustu) yazip yazmadigi veya kullanici uygulamasi kapatip kapatmadigi. #>
    param([Parameter(Mandatory)]$Item)
    if (@(Get-LtProp $Item 'Processes' @()).Count -gt 0) { return $true }
    $roots = @($env:USERPROFILE, $env:TEMP, $env:LOCALAPPDATA, $env:APPDATA) | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') + '\' }
    $sb = Get-LtProp $Item 'Paths'
    if (-not $sb) { $sb = Get-LtProp $Item 'PreviewPaths' }
    if (-not $sb) { return $false }
    foreach ($spec in @(& $sb)) {
        if ($null -eq $spec) { continue }
        $p = ([string]$spec.Path).TrimEnd('\') + '\'
        foreach ($r in $roots) { if ($p.StartsWith($r, [StringComparison]::OrdinalIgnoreCase)) { return $true } }
    }
    return $false
}

function Get-LtCleanupUserScopeIssue {
    <#
      Gercek sistemde, kullanici kapsamli oge yalniz yukseltilmis hesap oturumun sahibi ise calisir.
      UAC'de farkli yonetici hesabi kullanildiysa yanlis profil temizlenir ve asil kullanicinin
      uygulamalari kapatilabilir; bu durumda oge atlanir.
    #>
    param([Parameter(Mandatory)]$Item)
    if (-not (Test-LtLiveSystem)) { return $null }
    if (-not (Test-LtCleanupUserScoped $Item)) { return $null }
    try { [void](Get-LtInteractiveUserSid); return $null }
    catch { return "Kullanıcıya ait temizlik atlandı: $($_.Exception.Message) Livn Tools'u kendi hesabınızla, 'Yönetici olarak çalıştır' onayıyla açın." }
}

function Invoke-LtCleanupItem {
    param([Parameter(Mandatory)]$Item, [Parameter(Mandatory)]$Context, $Cancel = $null, [switch]$CloseApps)
    $id = $Item.Id; $title = $Item.Title
    $why = Get-LtCleanupAvailability $Item $Context
    if ($why) { return New-LtResult -Id $id -Title $title -Status NotSupported -Message $why }
    if (-not (Test-LtLiveSystem) -and -not (Test-LtCleanupSandbox)) {
        # KURU CALISMA: Paths / Run / Processes DEGERLENDIRILMEZ. Gercek sistemde hicbir
        # dosya silinmez, hicbir uygulama kapatilmaz, hicbir komut calistirilmaz.
        $what = @()
        if (Get-LtProp $Item 'Paths') { $what += 'dosya silme' }
        if (Get-LtProp $Item 'Run') { $what += 'komut/bakım işlemi' }
        if (@(Get-LtProp $Item 'Processes' @()).Count -gt 0) { $what += 'açıksa uygulamayı kapatma' }
        Write-LtLog "  [KURU ÇALIŞMA] $title — simüle edildi, gerçek sisteme dokunulmadı." 'DEBUG'
        return New-LtResult -Id $id -Title $title -Status Skipped -Simulated $true `
            -Message ("Kuru çalışma: simüle edildi ({0}). Gerçek sistemde hiçbir dosya silinmedi, uygulama kapatılmadı, komut çalıştırılmadı." -f ($what -join ', '))
    }
    $userWhy = Get-LtCleanupUserScopeIssue $Item
    if ($userWhy) { return New-LtResult -Id $id -Title $title -Status NotSupported -Message $userWhy }
    $running = @(Get-LtRunningProcessesFor $Item)
    if ($running.Count -gt 0) {
        if (Get-LtProp $Item 'RequireClosed' $false) { return New-LtResult -Id $id -Title $title -Status Skipped -Message 'Başlatıcı/oyun veya yardımcı süreç açık. Uygulamayı kendiniz kapatıp tekrar deneyin; süreç zorla kapatılmadı.' }
        if (-not $CloseApps) { return New-LtResult -Id $id -Title $title -Status Skipped -Message "Uygulama açık ($(@($running | ForEach-Object { $_.ProcessName } | Select-Object -Unique) -join ', ')); atlandı." }
        try { Stop-LtProcessSafe -Names @(Get-LtProp $Item 'Processes' @()) -WithWindowOnly }
        catch { return New-LtResult -Id $id -Title $title -Status Failed -Message "Uygulama kapatılamadı: $($_.Exception.Message)" }
        if (Test-LtLiveSystem) { Start-Sleep -Milliseconds 800 }
        if (@(Get-LtRunningProcessesFor $Item).Count -gt 0) { return New-LtResult -Id $id -Title $title -Status Skipped -Message 'Uygulama kapatılamadı; atlandı.' }
    }
    $bytes = [long]0; $failed = 0; $files = 0; $notes = New-Object System.Collections.ArrayList; $restart = $false
    # Boyut yalniz dosya silme (Paths) veya olcum bildiren Run (Measured) icin gercektir
    $measured = $false
    try {
        $pathsSb = Get-LtProp $Item 'Paths'
        if ($pathsSb) {
            $measured = $true
            foreach ($spec in @(& $pathsSb)) {
                if ($null -eq $spec) { continue }
                if ($null -ne $Cancel -and $Cancel.Requested) { break }
                $filter = [string](Get-LtProp $spec 'Filter' '*')
                $rec = [bool](Get-LtProp $spec 'Recurse' $true)
                $r = Remove-LtFolderContents -Path $spec.Path -Filter $filter -Recurse $rec -Cancel $Cancel -OlderThanDays ([int](Get-LtProp $spec 'OlderThanDays' 0))
                $bytes += $r.Bytes; $failed += $r.Failed; $files += $r.Files
                if ($r.Exists -and ($r.Files -gt 0 -or $r.Failed -gt 0)) {
                    Write-LtLog ("  {0}: {1} silindi{2}" -f $spec.Label, (Format-LtBytes $r.Bytes), $(if ($r.Failed) { ", $($r.Failed) öğe kullanımda/erişilemedi" } else { '' })) 'DEBUG'
                }
            }
        }
        $runSb = Get-LtProp $Item 'Run'
        if ($runSb) {
            $o = & $runSb $Context $Cancel
            if ($o) {
                $bytes += [long](Get-LtProp $o 'Bytes' 0)
                if (Get-LtProp $o 'Measured' $false) { $measured = $true }
                $failed += [int](Get-LtProp $o 'Failed' 0)
                $m = [string](Get-LtProp $o 'Message' ''); if ($m) { [void]$notes.Add($m) }
                if (Get-LtProp $o 'Restart' $false) { $restart = $true }
            }
        }
    } catch {
        $msg = $_.Exception.Message
        if ($msg -like 'NOTSUPPORTED:*') { return New-LtResult -Id $id -Title $title -Status NotSupported -Message $msg.Substring(13) }
        return New-LtResult -Id $id -Title $title -Status Failed -Message $msg -BytesFreed $bytes -SizeMeasured $measured
    }
    if ($null -ne $Cancel -and $Cancel.Requested) {
        return New-LtResult -Id $id -Title $title -Status Partial -Message ("İptal edildi; o ana kadar {0} silindi." -f (Format-LtBytes $bytes)) -BytesFreed $bytes -SizeMeasured $measured
    }
    $text = if ($files -gt 0 -or $bytes -gt 0) { "{0} temizlendi ({1} dosya)." -f (Format-LtBytes $bytes), $files } else { '' }
    if ($notes.Count -gt 0) { $text = (($text, ($notes -join ' ')) | Where-Object { $_ }) -join ' ' }
    if (-not $text) { $text = 'Temizlenecek bir şey yoktu.' }
    $rk = if ($restart) { 'Reboot' } else { 'None' }
    if ($failed -gt 0) {
        return New-LtResult -Id $id -Title $title -Status Partial -Message "$text $failed öğe kullanımda olduğu veya erişilemediği için silinemedi." -BytesFreed $bytes -RestartRequired $restart -RestartKind $rk -SizeMeasured $measured
    }
    return New-LtResult -Id $id -Title $title -Status Success -Message $text -BytesFreed $bytes -RestartRequired $restart -RestartKind $rk -SizeMeasured $measured
}

function Get-LtCleanupTotalText {
    <#
      Toplam boyut metni. Boyutu olculmeyen islemler (DISM, SFC, DNS, USB kayitlari...)
      0 B olarak toplanip "hicbir sey silinmedi" izlenimi vermez; ayrica sayilir.
    #>
    param([object[]]$Results)
    $ran = @(@($Results) | Where-Object { $_.Status -in @('Success', 'Partial', 'Failed') -and -not $_.Simulated })
    $measured = @($ran | Where-Object { Get-LtProp $_ 'SizeMeasured' $false })
    $unmeasured = @($ran | Where-Object { -not (Get-LtProp $_ 'SizeMeasured' $false) })
    $bytes = [long]0
    foreach ($r in $measured) { $bytes += [long]$r.BytesFreed }
    if ($ran.Count -eq 0) { return 'çalıştırılan işlem yok.' }
    if ($measured.Count -eq 0) {
        return ('{0} işlem çalıştı; bu işlemler açılan alanı bildirmez (DISM, SFC, DNS, USB kayıtları vb.), boyut ölçülmedi.' -f $unmeasured.Count)
    }
    $text = 'ölçülen toplam {0} ({1} öğe)' -f (Format-LtBytes $bytes), $measured.Count
    if ($unmeasured.Count -gt 0) { $text += '; {0} işlemin açtığı alan ölçülmedi ({1})' -f $unmeasured.Count, ((@($unmeasured | ForEach-Object { $_.Title }) | Select-Object -First 4) -join ', ') }
    return $text + '.'
}

function Invoke-LtCleanup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Ids,
        [Parameter(Mandatory)]$Context,
        $Progress = $null,
        $Cancel = $null,
        [string[]]$CloseAppIds = @()
    )
    $results = New-Object System.Collections.ArrayList
    $ids2 = @($Ids | Select-Object -Unique)
    $i = 0; $total = [long]0
    if (Test-LtLiveSystem) { Write-LtLog "Temizlik başladı ($($ids2.Count) öğe). Bu işlemler GERİ ALINAMAZ." 'RUN' }
    elseif (Test-LtCleanupSandbox) { Write-LtLog "Temizlik (TEST KÖKÜ) başladı ($($ids2.Count) öğe): dosya silme yalnızca test klasöründe." 'RUN' }
    else { Write-LtLog "KURU ÇALIŞMA: $($ids2.Count) temizlik öğesi simüle edilecek; gerçek sistemde hiçbir şey silinmez veya çalıştırılmaz." 'RUN' }
    foreach ($id in $ids2) {
        $item = Get-LtCleanupItem $id
        if ($null -ne $Cancel -and $Cancel.Requested) {
            [void]$results.Add((New-LtResult -Id $id -Title $item.Title -Status Skipped -Message 'Kullanıcı iptal etti.'))
            continue
        }
        Update-LtProgress $Progress $i $ids2.Count "Temizleniyor: $($item.Title)"
        $r = Invoke-LtCleanupItem -Item $item -Context $Context -Cancel $Cancel -CloseApps:($CloseAppIds -contains $id)
        $total += $r.BytesFreed
        [void]$results.Add($r)
        Write-LtResultLog $r
        $i++
    }
    Update-LtProgress $Progress $ids2.Count $ids2.Count 'Tamamlandı'
    $sum = Get-LtResultSummary $results
    $sum.BytesFreed = $total
    $totalText = Get-LtCleanupTotalText -Results $results
    Write-LtLog ("Temizlik bitti: {0}" -f $totalText) 'OK'
    return [pscustomobject]@{ Results = @($results); Summary = $sum; BytesFreed = $total; TotalText = $totalText }
}
