# Livn Tools - RecoveryKit.ps1
# "Kurtarma Kiti": formattan ONCE surucu paketleri, uygulama listesi, Livn ayarlari, (istege bagli)
# Wi-Fi profilleri ve oyun kayitlari secilen bir diske (ornek: USB) kopyalanir; Livn'in kendisi de
# kite kopyalanir. Formattan SONRA internet yokken bile once ag surucusu kurulur, sonra digerleri.
#
# Ilkeler:
# - Kit olusturma sistem ayari DEGISTIRMEZ: yalniz okur ve secilen klasore yazar.
# - Geri yukleme adimlari (surucu kurulumu, Wi-Fi ekleme, kayit kopyalama) ayri onayla yapilir ve
#   Livn geri alma gunlugune girmez (surucu Aygit Yoneticisi'nden kaldirilabilir).
# - Kit dosyasi guvenilmeyen girdidir: surum, yol ve kimlikler dogrulanir.
# - Bellek arka ucunda pnputil/netsh/Get-WindowsDriver CALISTIRILMAZ; kullanici profiline YAZILMAZ.

Set-StrictMode -Version 2.0

$script:LtKitSchema = 1
$script:LtKitPrefix = 'LivnKurtarma-'
# Secime bagli (bu bilgisayarin aygit/oturum kimligine dayali) ayarlar kitten otomatik secilmez
$script:LtKitSelectionDependent = @('net.ackfreq', 'net.rss-on', 'power.installed', 'mem.islc-autostart', 'gpu.app-high-perf')

# ---------------------------------------------------------------------------
# Kaynak bilgileri (salt okunur)
# ---------------------------------------------------------------------------
function Join-LtKitPath([string]$Root, [string]$Relative) {
    <# Kit icindeki yollar manifestte Windows bicimiyle (ters egik cizgi) saklanir. #>
    $sep = [IO.Path]::DirectorySeparatorChar
    return (Join-Path $Root ($Relative -replace '[\\/]', $sep))
}

function Get-LtKitDriverGroup([string]$Class) {
    switch -Regex ($Class) {
        '^Net$'     { return 'Network' }
        '^Display$' { return 'Display' }
        default     { return 'Other' }
    }
}

function Get-LtWindowsDriverStore {
    <# Gercek surucu deposu (salt okunur; DISM). Testlerde taklit edilebilsin diye ayri. #>
    return @(Get-WindowsDriver -Online -ErrorAction Stop)
}

function Get-LtKitDrivers {
    <# Ucuncu taraf (Windows ile gelmeyen) surucu paketleri. Donus: @{ Inf; Class; Provider; Version; Date; Original; Group } #>
    if ((Get-LtBackend) -eq 'Memory') {
        $m = Get-LtMemoryState
        $list = if ($m.ContainsKey('Drivers') -and $m.Drivers) { @($m.Drivers) } else { @() }
    } else {
        $list = @(Get-LtWindowsDriverStore | ForEach-Object {
            @{ Inf = [string]$_.Driver; Class = [string]$_.ClassName; Provider = [string]$_.ProviderName; Version = [string]$_.Version
               Date = $(if ($_.Date) { ([datetime]$_.Date).ToString('yyyy-MM-dd') } else { '' }); Original = [IO.Path]::GetFileName([string]$_.OriginalFileName) }
        })
    }
    return @($list | Where-Object { [string]$_.Inf -match '^oem\d+\.inf$' } | ForEach-Object {
        $h = @{}; foreach ($k in $_.Keys) { $h[$k] = $_[$k] }; $h.Group = Get-LtKitDriverGroup $h.Class; $h })
}

function Get-LtKitSaveSources {
    <# Yaygin oyun kayit klasorleri (yalniz var olanlar). Bellek arka ucu: Mem.KitSaveSources. #>
    if ((Get-LtBackend) -eq 'Memory') {
        $m = Get-LtMemoryState
        return @(if ($m.ContainsKey('KitSaveSources') -and $m.KitSaveSources) { $m.KitSaveSources } else { @() })
    }
    $out = @()
    $saved = if ($env:USERPROFILE) { Join-Path $env:USERPROFILE 'Saved Games' } else { '' }
    $docs = [Environment]::GetFolderPath('MyDocuments')
    if ($saved -and [IO.Directory]::Exists($saved)) { $out += @{ Name = 'Saved Games'; Path = $saved; Restore = 'SavedGames' } }
    if ($docs) {
        $mg = Join-Path $docs 'My Games'
        if ([IO.Directory]::Exists($mg)) { $out += @{ Name = 'Belgeler\My Games'; Path = $mg; Restore = 'MyGames' } }
    }
    return $out
}

function Get-LtDirectorySize {
    <# Baglanti noktalarina (junction/symlink) inmeden boyut ve dosya sayisi. #>
    param([Parameter(Mandatory)][string]$Path)
    $bytes = [long]0; $files = 0
    if (-not [IO.Directory]::Exists($Path)) { return @{ Bytes = 0; Files = 0 } }
    $stack = New-Object System.Collections.Stack
    $stack.Push((New-Object IO.DirectoryInfo $Path))
    while ($stack.Count -gt 0) {
        $d = $stack.Pop()
        try { foreach ($f in $d.GetFiles()) { $bytes += $f.Length; $files++ } } catch { $null = $_ }
        try { foreach ($s in $d.GetDirectories()) { if (($s.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { $stack.Push($s) } } } catch { $null = $_ }
    }
    return @{ Bytes = $bytes; Files = $files }
}

function Test-LtKitTarget {
    <# Hedef klasor: var olmali; sistem surucusu olmamali (format onu siler). Donus: $null veya neden. #>
    param([string]$Target, [string]$SystemDrive = $env:SystemDrive)
    if ([string]::IsNullOrWhiteSpace($Target)) { return 'Hedef klasör seçilmedi.' }
    if (-not [IO.Directory]::Exists($Target)) { return "Hedef klasör yok: $Target" }
    if (Test-LtKitLinkedPath $Target) { return 'Hedef bağlantı noktası içeriyor; doğrudan disk klasörünü seçin.' }
    $root = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Target))
    if ($SystemDrive -and $root.TrimEnd('\', '/') -ieq $SystemDrive.TrimEnd('\', '/')) {
        return "Hedef sistem sürücüsünde ($SystemDrive). Format bu sürücüyü silebilir; kiti USB belleğe veya başka bir diske kaydedin."
    }
    return $null
}

function Get-LtKitPlan {
    <#
      Kit icerigi ve tahmini boyut (hicbir sey yazmaz).
      Options: @{ NetDrivers; OtherDrivers; GpuDrivers; Apps; Livn; Wifi; Saves }
    #>
    param([string]$Target, [Parameter(Mandatory)][hashtable]$Options, [string]$SystemDrive = $env:SystemDrive)
    $drivers = @(Get-LtKitDrivers)
    $chosen = @($drivers | Where-Object {
        ($_.Group -eq 'Network' -and $Options.NetDrivers) -or ($_.Group -eq 'Other' -and $Options.OtherDrivers) -or ($_.Group -eq 'Display' -and $Options.GpuDrivers) })
    $saves = @()
    $saveBytes = [long]0
    if ($Options.Saves) {
        foreach ($s in @(Get-LtKitSaveSources)) { $z = Get-LtDirectorySize -Path $s.Path; $saveBytes += $z.Bytes; $saves += @{ Name = $s.Name; Path = $s.Path; Restore = $s.Restore; Bytes = $z.Bytes; Files = $z.Files } }
    }
    $warn = New-Object System.Collections.ArrayList
    if (-not (Test-LtLiveSystem)) { [void]$warn.Add('Kuru çalışma: sürücüler örnek listedir; oluşturulacak kit DENEME olarak işaretlenir ve formatta kullanılamaz.') }
    if (@($drivers | Where-Object { $_.Group -eq 'Network' }).Count -eq 0) { [void]$warn.Add('Üçüncü taraf ağ sürücüsü bulunamadı: Windows ağ kartınızı kendi sürücüsüyle tanıyor olabilir. Formattan sonra internet yoksa üreticinin sürücüsünü ayrıca indirip kite ekleyin.') }
    if ($Options.Wifi) { [void]$warn.Add('Wi-Fi parolaları kitte DÜZ METİN olarak saklanır. USB belleği güvende tutun; geri yükledikten sonra WiFi klasörünü silin.') }
    $targetIssue = if ($Target) { Test-LtKitTarget -Target $Target -SystemDrive $SystemDrive } else { 'Hedef klasör seçilmedi.' }
    $free = $null
    if ($Target -and -not $targetIssue) { try { $free = [long](New-Object IO.DriveInfo ([IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Target)))).AvailableFreeSpace } catch { $free = $null } }
    return [pscustomobject]@{
        Drivers = $chosen; DriverCounts = @{ Network = @($chosen | Where-Object { $_.Group -eq 'Network' }).Count; Other = @($chosen | Where-Object { $_.Group -eq 'Other' }).Count; Display = @($chosen | Where-Object { $_.Group -eq 'Display' }).Count }
        AllDrivers = $drivers; Saves = $saves; SaveBytes = $saveBytes; Warnings = @($warn); TargetIssue = $targetIssue; FreeBytes = $free; Options = $Options
    }
}

function Format-LtKitPlan {
    param([Parameter(Mandatory)]$Plan)
    $o = $Plan.Options
    $lines = New-Object System.Collections.ArrayList
    $dc = $Plan.DriverCounts
    [void]$lines.Add("Sürücüler: ağ $($dc.Network), diğer donanım $($dc.Other), ekran kartı $($dc.Display) paket (toplam üçüncü taraf: $(@($Plan.AllDrivers).Count)).")
    if ($o.Apps) { [void]$lines.Add('Uygulama listesi: kurulu uygulamalar (Format Sonrası kataloğu + Windows uygulama listesi).') }
    if ($o.Livn) { [void]$lines.Add('Livn Tools kopyası ve Livn ayarları (internetsiz çalıştırmak için).') }
    if ($o.Wifi) { [void]$lines.Add('Wi-Fi ağları ve parolaları.') }
    if ($o.Saves) { [void]$lines.Add("Oyun kayıtları: $(Format-LtBytes $Plan.SaveBytes) ($((@($Plan.Saves) | ForEach-Object { $_.Name }) -join ', '))") }
    if ($Plan.TargetIssue) { [void]$lines.Add("Hedef: $($Plan.TargetIssue)") }
    elseif ($null -ne $Plan.FreeBytes) { [void]$lines.Add("Hedefte boş alan: $(Format-LtBytes $Plan.FreeBytes). Sürücü boyutu dışa aktarılırken belli olur (genellikle 0,2–2 GB).") }
    foreach ($w in @($Plan.Warnings)) { [void]$lines.Add("Uyarı: $w") }
    return ($lines -join "`n")
}

# ---------------------------------------------------------------------------
# Kit olusturma
# ---------------------------------------------------------------------------
function Export-LtDriverPackage {
    <# Tek surucu paketini disa aktarir (pnputil /export-driver). Bellek: yer tutucu .inf. #>
    param([Parameter(Mandatory)][string]$Inf, [Parameter(Mandatory)][string]$Destination)
    [void][IO.Directory]::CreateDirectory($Destination)
    if ((Get-LtBackend) -eq 'Memory') {
        [IO.File]::WriteAllText((Join-Path $Destination $Inf), "; Livn deneme sürücü paketi: $Inf")
        return @{ Ok = $true; Message = 'Deneme: dışa aktarma simüle edildi.' }
    }
    $r = Invoke-LtNative -FilePath "$env:SystemRoot\System32\pnputil.exe" -Arguments @('/export-driver', $Inf, $Destination) -TimeoutSec 300
    $infs = @([IO.Directory]::GetFiles($Destination, '*.inf', [IO.SearchOption]::AllDirectories))
    if ($r.ExitCode -eq 0 -and $infs.Count -gt 0) { return @{ Ok = $true; Message = '' } }
    return @{ Ok = $false; Message = "pnputil çıkış kodu $($r.ExitCode)" }
}

function Export-LtWifiProfiles {
    <# netsh wlan export profile key=clear. Bellek: ornek profil. Donus: dosya sayisi. #>
    param([Parameter(Mandatory)][string]$Destination)
    [void][IO.Directory]::CreateDirectory($Destination)
    if ((Get-LtBackend) -eq 'Memory') {
        [IO.File]::WriteAllText((Join-Path $Destination 'Wi-Fi-DenemeAgi.xml'), '<WLANProfile><name>DenemeAgi</name></WLANProfile>')
        return 1
    }
    $r = Invoke-LtNative -FilePath "$env:SystemRoot\System32\netsh.exe" -Arguments @('wlan', 'export', 'profile', 'key=clear', "folder=$Destination") -TimeoutSec 60
    $n = @([IO.Directory]::GetFiles($Destination, '*.xml')).Count
    if ($r.ExitCode -ne 0 -and $n -eq 0) { throw "Wi-Fi profilleri alınamadı (netsh çıkış kodu $($r.ExitCode); Wi-Fi bağdaştırıcısı veya WLAN hizmeti olmayabilir)." }
    return $n
}

function Test-LtKitLinkedPath {
    param([Parameter(Mandatory)][string]$Path)
    $item = New-Object IO.DirectoryInfo ([IO.Path]::GetFullPath($Path))
    while ($null -ne $item) {
        if (($item.Attributes -ne -1) -and (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { return $true }
        $item = $item.Parent
    }
    return $false
}

function Get-LtKitMissingAppFiles {
    param([Parameter(Mandatory)][string]$Root)
    $required = @(
        'Main.ps1',
        'LivnTools.bat',
        'src/Catalog/Helpers.ps1',
        'src/Catalog/Tweaks.ps1',
        'src/Cleanup.ps1',
        'src/Core/Backend.ps1',
        'src/Core/Common.ps1',
        'src/Core/Demo.ps1',
        'src/Core/Journal.ps1',
        'src/Core/Providers.ps1',
        'src/Core/SideEffects.ps1',
        'src/Core/SystemInfo.ps1',
        'src/Engine.ps1',
        'src/Health.ps1',
        'src/LivnTools.psm1',
        'src/Network.ps1',
        'src/RecoveryKit.ps1',
        'src/Setup.ps1',
        'src/Startup.ps1',
        'src/UI/App.ps1',
        'src/UI/Dialogs.ps1',
        'src/UI/MainWindow.xaml',
        'src/UI/ViewModels.ps1'
    )
    foreach ($rel in $required) {
        $file = Join-LtKitPath $Root $rel
        if (-not [IO.File]::Exists($file) -or (New-Object IO.FileInfo $file).Length -eq 0) { $rel }
    }
}

function Copy-LtDirectoryTree {
    <# Agaci kopyalar; baglanti noktalarina inmez; var olan dosyaya -NoOverwrite ile dokunmaz. Donus: @{ Files; Bytes; Skipped; Failed } #>
    param([Parameter(Mandatory)][string]$Source, [Parameter(Mandatory)][string]$Destination, [switch]$NoOverwrite, $Cancel = $null)
    $res = @{ Files = 0; Bytes = [long]0; Skipped = 0; Failed = 0; Cancelled = $false }
    if ($null -ne $Cancel -and $Cancel.Requested) { $res.Cancelled = $true; return $res }
    if (-not [IO.Directory]::Exists($Source) -or (Test-LtKitLinkedPath $Source) -or (Test-LtKitLinkedPath $Destination)) { $res.Failed++; return $res }
    $sourceRoot = [IO.Path]::GetFullPath($Source).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $destinationRoot = [IO.Path]::GetFullPath($Destination).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if ($destinationRoot.StartsWith($sourceRoot, [StringComparison]::OrdinalIgnoreCase)) { $res.Failed++; return $res }
    $src = (New-Object IO.DirectoryInfo $Source).FullName.TrimEnd('\', '/')
    $stack = New-Object System.Collections.Stack
    $stack.Push((New-Object IO.DirectoryInfo $src))
    while ($stack.Count -gt 0) {
        if ($null -ne $Cancel -and $Cancel.Requested) { $res.Cancelled = $true; break }
        $d = $stack.Pop()
        $rel = $d.FullName.Substring($src.Length).TrimStart('\', '/')
        $destDir = if ($rel) { Join-Path $Destination $rel } else { $Destination }
        try { if (Test-LtKitLinkedPath $destDir) { $res.Failed++; continue }; [void][IO.Directory]::CreateDirectory($destDir) } catch { $res.Failed++; continue }
        try {
            foreach ($f in $d.GetFiles()) {
                if ($null -ne $Cancel -and $Cancel.Requested) { $res.Cancelled = $true; break }
                if (($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { $res.Failed++; continue }
                $target = Join-Path $destDir $f.Name
                if ([IO.File]::Exists($target) -and (((New-Object IO.FileInfo $target).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { $res.Failed++; continue }
                if ($NoOverwrite -and [IO.File]::Exists($target)) { $res.Skipped++; continue }
                try { [IO.File]::Copy($f.FullName, $target, (-not $NoOverwrite)); $res.Files++; $res.Bytes += $f.Length } catch { $res.Failed++ }
            }
        } catch { $res.Failed++ }
        try { foreach ($s in $d.GetDirectories()) { if (($s.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { $stack.Push($s) } else { $res.Failed++ } } } catch { $res.Failed++ }
    }
    return $res
}

function Get-LtKitAppliedTweakIds {
    <# Livn'in uyguladigi ve su an uygulanmis olan ayarlar (secime bagli olanlar haric). #>
    param([Parameter(Mandatory)]$Context)
    # Eski surumlerden kalan (artik katalogda olmayan) kimlikler sessizce atlanir
    $catalog = @(Get-LtCatalog | ForEach-Object { $_.Id })
    $ids = @(Get-LtLedgerEntries | ForEach-Object { @($_.tweakIds) } | Where-Object { $_ -and $catalog -contains [string]$_ } | Select-Object -Unique)
    $out = New-Object System.Collections.ArrayList
    foreach ($id in $ids) {
        if ($script:LtKitSelectionDependent -contains $id -or $id -like 'nic.*' -or $id -like 'msi.*' -or $id -like 'dns.*' -or $id -like 'startup.*') { continue }
        $t = Get-LtTweak $id
        if (-not $t) { continue }
        try { if ((Get-LtTweakStatus $t $Context).State -eq 'Applied') { [void]$out.Add($id) } } catch { $null = $_ }
    }
    return @($out)
}

function New-LtKitReadme {
    param([Parameter(Mandatory)]$Manifest)
    $nl = "`r`n"
    $t = @(
        $(if ($Manifest.Simulated) { 'DENEME KİTİ — KURU ÇALIŞMADA OLUŞTURULDU, GERÇEK SÜRÜCÜ İÇERMEZ. FORMATTAN ÖNCE KULLANMAYIN.' } else { 'LIVN TOOLS KURTARMA KİTİ' })
        "Oluşturma: $($Manifest.Created) · Windows derleme $($Manifest.Build)"
        ''
        'FORMATTAN SONRA'
        '1. Bu klasördeki LivnTools\LivnTools.bat dosyasını çalıştırın (internet gerekmez).'
        '   Livn kiti kendiliğinden bulur ve "Kurtarma Kiti" sayfasını açar.'
        '2. Önce "Sürücüleri kur (ağ önce)" — internet bağlantınız gelir.'
        '3. Sonra Wi-Fi ağları, Format Sonrası uygulamaları ve Livn ayarları.'
        ''
        'LIVN ÇALIŞMAZSA (elle):'
        '  Yönetici komut isteminde:  pnputil /add-driver "<bu klasör>\Drivers\Network\*.inf" /subdirs /install'
        '  veya Aygıt Yöneticisi > aygıt > Sürücüyü güncelleştir > Bilgisayarımı tara > bu kitin Drivers klasörü.'
        ''
        'Kitte olmayanlar: kişisel dosyalarınız (Belgeler, Resimler, Masaüstü), tarayıcı verileri, lisans anahtarları.'
        'Bunları ayrıca yedekleyin. Tarayıcıda hesap eşitlemesini açmak en kolay yoldur.'
    )
    $status = [string](Get-LtProp $Manifest 'Status' 'Unknown')
    if ($status -ne 'Success') { $t = @("KİT TAMAMLANMADI ($status). Formattan önce eksikleri giderin ve kiti yeniden oluşturun.", '') + $t }
    if (-not $Manifest.Contents.Livn) { $t += @('', 'Livn uygulama kopyası yok veya eksik. Kit içindeki başlatıcıya güvenmeyin; uygulamayı ayrıca edinin.') }
    $t += @('', 'Bölüm sonuçları:') + @((Get-LtProp $Manifest 'Parts' @()) | ForEach-Object { "$($_.Name) [$($_.Status)]: $($_.Message)" })
    if ($Manifest.Contents.Wifi) { $t += @('', 'UYARI: WiFi klasöründeki dosyalarda parolalar düz metindir. Geri yükledikten sonra klasörü silin.') }
    if (@($Manifest.OtherApps).Count -gt 0) {
        $t += @('', 'Katalogda olmayan kurulu uygulamalar (elle kurun):')
        $t += @($Manifest.OtherApps | Select-Object -First 200 | ForEach-Object { "  - $_" })
    }
    return ($t -join $nl) + $nl
}

function New-LtRecoveryKit {
    <# Kiti olusturur. Donus: @{ Path; Parts = @(@{ Name; Status; Message }); Manifest } #>
    param([Parameter(Mandatory)][string]$Target, [Parameter(Mandatory)][hashtable]$Options, [Parameter(Mandatory)]$Context,
          [string]$AppRoot = '', [string]$SystemDrive = $env:SystemDrive, $Progress = $null, $Cancel = $null, [datetime]$Now = (Get-Date))
    $issue = Test-LtKitTarget -Target $Target -SystemDrive $SystemDrive
    if ($issue) { throw $issue }
    $plan = Get-LtKitPlan -Target $Target -Options $Options -SystemDrive $SystemDrive
    # Kuru calismada (bellek arka ucu) kit DENEME olarak isaretlenir: gercek surucu icermez ve
    # gercek sistemde geri yukleme icin kabul edilmez.
    $simulated = -not (Test-LtLiveSystem)
    $name = $script:LtKitPrefix + $Now.ToString('yyyyMMdd-HHmm') + $(if ($simulated) { '-DENEME' } else { '' })
    $root = Join-Path $Target $name
    $i = 1; while ([IO.Directory]::Exists($root)) { $i++; $root = Join-Path $Target "$name-$i" }
    [void][IO.Directory]::CreateDirectory($root)
    $parts = New-Object System.Collections.ArrayList
    $step = { param($t) if ($Progress) { $Progress.Text = $t } ; Write-LtLog "Kurtarma kiti: $t" 'INFO' }

    # 1) Suruculer
    $exported = New-Object System.Collections.ArrayList
    $failed = 0
    if ($Progress) { $Progress.Total = @($plan.Drivers).Count }
    $n = 0
    foreach ($d in @($plan.Drivers)) {
        if ($null -ne $Cancel -and $Cancel.Requested) { break }
        & $step "Sürücü dışa aktarılıyor: $($d.Provider) $($d.Class) ($($d.Inf))"
        $safeProv = ([string]$d.Provider -replace '[^\w\.-]', '_')
        if ($safeProv.Length -gt 40) { $safeProv = $safeProv.Substring(0, 40) }
        $rel = "Drivers\$($d.Group)\$($d.Class)_$($safeProv)_$([IO.Path]::GetFileNameWithoutExtension($d.Inf))"
        try {
            $r = Export-LtDriverPackage -Inf $d.Inf -Destination (Join-LtKitPath $root $rel)
            if ($r.Ok) { [void]$exported.Add(@{ Inf = $d.Inf; Class = $d.Class; Group = $d.Group; Provider = $d.Provider; Version = $d.Version; Date = $d.Date; Original = $d.Original; Folder = $rel }) }
            else { $failed++; Write-LtLog "  $($d.Inf): $($r.Message)" 'WARN' }
        } catch { $failed++; Write-LtLog "  $($d.Inf): $($_.Exception.Message)" 'WARN' }
        $n++; if ($Progress) { $Progress.Done = $n }
    }
    if ($Progress) { $Progress.Total = 0 }
    if (@($plan.Drivers).Count -gt 0 -or $Options.NetDrivers -or $Options.OtherDrivers) {
        $st = if ($null -ne $Cancel -and $Cancel.Requested) { 'Cancelled' } elseif (@($plan.Drivers).Count -eq 0) { 'Skipped' } elseif ($failed -eq 0) { 'Success' } elseif ($exported.Count -gt 0) { 'Partial' } else { 'Failed' }
        [void]$parts.Add(@{ Name = 'Sürücüler'; Status = $st; Message = "$($exported.Count) paket alındı$(if ($failed) { ", $failed paket alınamadı" })." })
    }

    # 2) Uygulamalar
    $catalogIds = @(); $otherApps = @()
    if ($Options.Apps -and -not ($null -ne $Cancel -and $Cancel.Requested)) {
        & $step 'Kurulu uygulamalar okunuyor'
        try {
            $inv = Get-LtSetupInventory
            $catalogIds = @($inv.InstalledIds)
            $names = @(Get-LtInstalledDisplayNames -Fresh | Where-Object { $_ } | Sort-Object -Unique)
            $otherApps = @($names | Where-Object { $n2 = $_; -not (@(Get-LtSetupArpMatches -DisplayNames @($n2)).Count) } | Where-Object { $_ -notmatch '^(Microsoft (Visual C\+\+|\.NET|Windows Desktop Runtime|Edge Update|Update Health)|Windows |Update for )' })
            [void]$parts.Add(@{ Name = 'Uygulama listesi'; Status = 'Success'; Message = "$($catalogIds.Count) katalog uygulaması, $($otherApps.Count) diğer uygulama listelendi." })
        } catch { [void]$parts.Add(@{ Name = 'Uygulama listesi'; Status = 'Failed'; Message = $_.Exception.Message }) }
    }

    # 3) Livn ayarlari ve kopyasi: eksik kaynak veya kopya basarili sayilmaz.
    $tweaks = @(); $livnReady = $false
    if ($Options.Livn -and -not ($null -ne $Cancel -and $Cancel.Requested)) {
        & $step 'Livn ayarları ve uygulama kopyası'
        $total = @{ Files = 0; Failed = 0 }; $missing = @(); $copyMsg = ''
        try {
            $tweaks = @(Get-LtKitAppliedTweakIds -Context $Context)
            if (-not $AppRoot -or -not [IO.Directory]::Exists($AppRoot)) { throw 'Livn kaynak klasörü bulunamadı.' }
            if (Test-LtKitLinkedPath $AppRoot) { throw 'Livn kaynak klasörü bağlantı noktası içeriyor.' }
            $missing = @(Get-LtKitMissingAppFiles -Root $AppRoot)
            if ($missing.Count) { throw ('Livn kaynak dosyaları eksik: ' + ($missing -join ', ')) }
            $dest = Join-Path $root 'LivnTools'
            [void][IO.Directory]::CreateDirectory($dest)
            foreach ($item in @('Main.ps1', 'LivnTools.bat')) {
                if ($null -ne $Cancel -and $Cancel.Requested) { break }
                $p = Join-Path $AppRoot $item
                if (((New-Object IO.FileInfo $p).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Kaynak dosya bağlantı noktası: $item" }
                [IO.File]::Copy($p, (Join-Path $dest $item), $true); $total.Files++
            }
            foreach ($dir in @('src', '_Files')) {
                if ($dir -eq '_Files' -and -not [IO.Directory]::Exists((Join-Path $AppRoot $dir))) { continue }
                $c = Copy-LtDirectoryTree -Source (Join-Path $AppRoot $dir) -Destination (Join-Path $dest $dir) -Cancel $Cancel
                $total.Files += $c.Files; $total.Failed += $c.Failed
            }
            $missing = @(Get-LtKitMissingAppFiles -Root $dest)
            $livnReady = $missing.Count -eq 0
            $copyMsg = " Livn kopyası: $($total.Files) dosya, $($total.Failed) hata."
            if ($missing.Count) { $copyMsg += ' Eksik: ' + ($missing -join ', ') }
        } catch { $total.Failed++; $copyMsg += ' ' + $_.Exception.Message }
        $st = if ($null -ne $Cancel -and $Cancel.Requested) { 'Cancelled' } elseif (-not $livnReady) { 'Failed' } elseif ($total.Failed) { 'Partial' } else { 'Success' }
        [void]$parts.Add(@{ Name = 'Livn Tools'; Status = $st; Message = "$($tweaks.Count) uygulanmış ayar kaydedildi.$copyMsg" })
    }

    # 4) Wi-Fi
    $wifiCount = 0
    if ($Options.Wifi -and -not ($null -ne $Cancel -and $Cancel.Requested)) {
        & $step 'Wi-Fi ağları dışa aktarılıyor'
        try { $wifiCount = Export-LtWifiProfiles -Destination (Join-Path $root 'WiFi'); [void]$parts.Add(@{ Name = 'Wi-Fi'; Status = 'Success'; Message = "$wifiCount ağ alındı (parolalar düz metin)." }) }
        catch { [void]$parts.Add(@{ Name = 'Wi-Fi'; Status = 'Failed'; Message = $_.Exception.Message }) }
    }

    # 5) Oyun kayitlari
    $saveEntries = @()
    if ($Options.Saves -and -not ($null -ne $Cancel -and $Cancel.Requested)) {
        foreach ($s in @($plan.Saves)) {
            if ($null -ne $Cancel -and $Cancel.Requested) { break }
            & $step "Oyun kayıtları kopyalanıyor: $($s.Name)"
            $rel = "Saves\$($s.Restore)"
            $c = Copy-LtDirectoryTree -Source $s.Path -Destination (Join-LtKitPath $root $rel) -Cancel $Cancel
            $saveEntries += @{ Name = $s.Name; Restore = $s.Restore; Folder = $rel; Files = $c.Files; Bytes = $c.Bytes; Failed = $c.Failed }
        }
        if (@($plan.Saves).Count -gt 0) {
            $f = [int](@($saveEntries | ForEach-Object { $_.Failed } | Measure-Object -Sum).Sum)
            $sz = [long](@($saveEntries | ForEach-Object { $_.Bytes } | Measure-Object -Sum).Sum)
            [void]$parts.Add(@{ Name = 'Oyun kayıtları'; Status = $(if ($null -ne $Cancel -and $Cancel.Requested) { 'Cancelled' } elseif ($f -and $sz -eq 0) { 'Failed' } elseif ($f) { 'Partial' } else { 'Success' }); Message = "$(Format-LtBytes $sz) kopyalandı$(if ($f) { ", $f öğe kopyalanamadı (kullanımda olabilir)" })." })
        } else { [void]$parts.Add(@{ Name = 'Oyun kayıtları'; Status = 'Skipped'; Message = 'Saved Games / My Games klasörü bulunamadı.' }) }
    }

    $cancelled = $null -ne $Cancel -and $Cancel.Requested
    if ($cancelled) { [void]$parts.Add(@{ Name = 'İşlem'; Status = 'Cancelled'; Message = 'İptal edildi. Kit tamamlanmadı; format öncesinde yeniden oluşturun.' }) }
    $bad = @($parts | Where-Object { $_.Status -in @('Failed', 'Partial') }).Count
    $good = @($parts | Where-Object { $_.Status -eq 'Success' }).Count
    $status = if ($cancelled) { 'Cancelled' } elseif ($bad -and $good) { 'Partial' } elseif ($bad) { 'Failed' } elseif ($good) { 'Success' } else { 'Skipped' }
    $manifest = [ordered]@{
        Status = $status; Parts = @($parts)
        Schema = $script:LtKitSchema; Simulated = $simulated; Tool = "Livn Tools $(Get-LtVersion)"; Created = $Now.ToString('yyyy-MM-dd HH:mm'); Build = [int](Get-LtProp $Context 'Build' 0)
        Hardware = @{ Cpu = [string](Get-LtProp (Get-LtProp $Context 'Cpu' @{}) 'Name' ''); Gpus = @(@(Get-LtProp $Context 'Gpus' @()) | ForEach-Object { [string](Get-LtProp $_ 'Name' '') }) }
        Contents = @{ Drivers = ($exported.Count -gt 0); Apps = (@($parts | Where-Object { $_.Name -eq 'Uygulama listesi' -and $_.Status -eq 'Success' }).Count -gt 0); Livn = $livnReady; Wifi = ($wifiCount -gt 0); Saves = (@($saveEntries).Count -gt 0) }
        Drivers = @($exported); AppIds = @($catalogIds); OtherApps = @($otherApps); TweakIds = @($tweaks); Saves = @($saveEntries)
        MenuDelayMs = Get-LtProp $Context 'MenuDelayMs' $null
    }
    Write-LtFileAtomic -Path (Join-Path $root 'kit.json') -Content (ConvertTo-Json -InputObject $manifest -Depth 6)
    Write-LtFileAtomic -Path (Join-Path $root 'KIT_OKU.txt') -Content (New-LtKitReadme -Manifest $manifest)
    Write-LtLog "Kurtarma kiti ($status): $root" $(if ($status -eq 'Success') { 'OK' } else { 'WARN' })
    return [pscustomobject]@{ Path = $root; Status = $status; Parts = @($parts); Manifest = $manifest }
}

# ---------------------------------------------------------------------------
# Kiti okuma (guvenilmeyen girdi)
# ---------------------------------------------------------------------------
function Test-LtKitRelativePath {
    <# Yalniz kit icinde, '..' veya mutlak yol olmayan goreli yol. #>
    param([string]$Path, [string]$Prefix)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if ([IO.Path]::IsPathRooted($Path) -or $Path -match '(^|[\\/])\.\.([\\/]|$)' -or $Path -match ':') { return $false }
    return ($Path -match ('^' + [regex]::Escape($Prefix) + '[\\/][^\\/]'))
}

function Read-LtRecoveryKit {
    <# kit.json dogrulanir; bilinmeyen ayar/uygulama kimlikleri ve kit disina cikan yollar atilir. #>
    param([Parameter(Mandatory)][string]$Path)
    $root = if ([IO.File]::Exists($Path)) { Split-Path -Parent $Path } else { $Path }
    $file = Join-Path $root 'kit.json'
    if (-not [IO.File]::Exists($file)) { throw "Kurtarma kiti bulunamadı (kit.json yok): $root" }
    if ((New-Object IO.FileInfo $file).Length -gt 5MB) { throw 'kit.json beklenenden büyük; okunmadı.' }
    $k = [IO.File]::ReadAllText($file) | ConvertFrom-Json -ErrorAction Stop | ConvertTo-LtHashtable
    if ([int](Get-LtProp $k 'Schema' 0) -ne $script:LtKitSchema) { throw 'Desteklenmeyen kit sürümü.' }
    $simulated = [bool](Get-LtProp $k 'Simulated' $false)
    if ($simulated -and (Test-LtLiveSystem)) { throw 'Bu bir DENEME kitidir (kuru çalışmada oluşturuldu) ve gerçek sürücü içermez. Gerçek modda yeni kit oluşturun.' }
    $catalog = @(Get-LtCatalog | ForEach-Object { $_.Id })
    $apps = @(Get-LtSetupApps | ForEach-Object { $_.Id })
    $drivers = @(@(Get-LtProp $k 'Drivers' @()) | Where-Object {
        $_ -is [System.Collections.IDictionary] -and (Test-LtKitRelativePath -Path ([string]$_.Folder) -Prefix 'Drivers') -and [string]$_.Group -in @('Network', 'Other', 'Display') })
    $saves = @(@(Get-LtProp $k 'Saves' @()) | Where-Object {
        $_ -is [System.Collections.IDictionary] -and (Test-LtKitRelativePath -Path ([string]$_.Folder) -Prefix 'Saves') -and [string]$_.Restore -in @('SavedGames', 'MyGames') })
    return [pscustomobject]@{
        Root = $root; Status = [string](Get-LtProp $k 'Status' 'Unknown'); Simulated = $simulated; Created = [string](Get-LtProp $k 'Created' ''); Tool = [string](Get-LtProp $k 'Tool' ''); Build = [int](Get-LtProp $k 'Build' 0)
        Drivers = $drivers; AppIds = @(@(Get-LtProp $k 'AppIds' @()) | Where-Object { $apps -contains [string]$_ })
        TweakIds = @(@(Get-LtProp $k 'TweakIds' @()) | Where-Object { $catalog -contains [string]$_ -and $script:LtKitSelectionDependent -notcontains [string]$_ })
        OtherApps = @(@(Get-LtProp $k 'OtherApps' @()) | ForEach-Object { [string]$_ } | Select-Object -First 500)
        Saves = $saves; HasWifi = [IO.Directory]::Exists((Join-Path $root 'WiFi')); HasLivn = (@(Get-LtKitMissingAppFiles -Root (Join-Path $root 'LivnTools')).Count -eq 0)
        MenuDelayMs = Get-LtProp $k 'MenuDelayMs' $null
    }
}

function Find-LtRecoveryKits {
    <# Uygulamanin yaninda ve surucu koklerinde (1 seviye) kit arar. Bellek: Mem.KitSearchRoots. #>
    param([string]$AppRoot = '')
    $roots = New-Object System.Collections.ArrayList
    if ($AppRoot) { $parent = Split-Path -Parent $AppRoot; if ($parent) { [void]$roots.Add($parent) } }
    if ((Get-LtBackend) -eq 'Memory') {
        $m = Get-LtMemoryState
        if ($m.ContainsKey('KitSearchRoots') -and $m.KitSearchRoots) { foreach ($r in $m.KitSearchRoots) { [void]$roots.Add($r) } }
    } else {
        foreach ($d in [IO.DriveInfo]::GetDrives()) {
            try { if ($d.IsReady -and $d.DriveType -in @([IO.DriveType]::Removable, [IO.DriveType]::Fixed)) { [void]$roots.Add($d.RootDirectory.FullName) } } catch { $null = $_ }
        }
    }
    $found = New-Object System.Collections.ArrayList
    foreach ($r in @($roots | Select-Object -Unique)) {
        try {
            $cands = @($r) + @([IO.Directory]::GetDirectories($r, "$($script:LtKitPrefix)*"))
            foreach ($dir in $cands) {
                if (-not [IO.File]::Exists((Join-Path $dir 'kit.json'))) { continue }
                if ((Test-LtLiveSystem) -and $dir -like '*-DENEME*') { continue }
                [void]$found.Add($dir)
            }
        } catch { $null = $_ }
    }
    return @($found | Select-Object -Unique | Sort-Object -Descending)
}

function Format-LtKitSummary {
    param([Parameter(Mandatory)]$Kit)
    $g = @{ Network = 0; Other = 0; Display = 0 }
    foreach ($d in @($Kit.Drivers)) { $g[[string]$d.Group]++ }
    $lines = @(
        "Kit: $($Kit.Root)$(if ($Kit.Simulated) { '  (DENEME kiti — gerçek sürücü içermez)' })"
        "Kit durumu: $(Get-LtProp $Kit 'Status' 'Unknown')"
        "Oluşturma: $($Kit.Created) · $($Kit.Tool)"
        "Sürücüler: ağ $($g.Network), diğer $($g.Other), ekran kartı $($g.Display)"
        "Uygulamalar: $(@($Kit.AppIds).Count) katalog uygulaması$(if (@($Kit.OtherApps).Count) { " + $(@($Kit.OtherApps).Count) elle kurulacak (KIT_OKU.txt)" })"
        "Livn ayarları: $(@($Kit.TweakIds).Count)"
        "Wi-Fi: $(if ($Kit.HasWifi) { 'var' } else { 'yok' }) · Oyun kayıtları: $(@($Kit.Saves).Count) klasör"
    )
    return ($lines -join "`n")
}

# ---------------------------------------------------------------------------
# Geri yukleme (ayri onayla; Livn geri alma gunlugune girmez)
# ---------------------------------------------------------------------------
function Get-LtPnpUtilResult([int]$Code) {
    switch ($Code) {
        0    { return @{ Status = 'Success'; Text = 'Kuruldu.' } }
        3010 { return @{ Status = 'Success'; Text = 'Kuruldu; tamamlanması için yeniden başlatın.'; Reboot = $true } }
        1641 { return @{ Status = 'Success'; Text = 'Kuruldu; yeniden başlatma başladı.'; Reboot = $true } }
        259  { return @{ Status = 'AlreadyApplied'; Text = 'Eşleşen aygıt yok veya aygıt zaten daha yeni/uygun sürücüyü kullanıyor.' } }
        default { return @{ Status = 'Failed'; Text = "pnputil çıkış kodu $Code." } }
    }
}

function Install-LtKitDrivers {
    <# Gruptaki tum paketleri surucu deposuna ekler ve eslesen aygitlara kurar (ag her zaman once cagrilmali). #>
    param([Parameter(Mandatory)]$Kit, [Parameter(Mandatory)][ValidateSet('Network', 'Other', 'Display')][string]$Group)
    $folder = Join-LtKitPath $Kit.Root "Drivers\$Group"
    $title = @{ Network = 'Ağ sürücüleri'; Other = 'Diğer donanım sürücüleri'; Display = 'Ekran kartı sürücüleri' }[$Group]
    if (@($Kit.Drivers | Where-Object { $_.Group -eq $Group }).Count -eq 0 -or -not [IO.Directory]::Exists($folder)) {
        return New-LtResult -Id "kit.drivers.$Group" -Title $title -Status Skipped -Message 'Kitte bu gruba ait sürücü yok.'
    }
    if (-not (Test-LtLiveSystem)) {
        $m = Get-LtMemoryState
        if ($m) { [void]$m.Calls.Add("Kit.InstallDrivers|$Group") }
        return New-LtResult -Id "kit.drivers.$Group" -Title $title -Status Skipped -Simulated $true -Message 'Kuru çalışma: sürücü kurulmadı.'
    }
    $r = Invoke-LtNative -FilePath "$env:SystemRoot\System32\pnputil.exe" -Arguments @('/add-driver', (Join-Path $folder '*.inf'), '/subdirs', '/install') -TimeoutSec 1800
    if ($r.TimedOut) { return New-LtResult -Id "kit.drivers.$Group" -Title $title -Status Failed -Message 'Zaman aşımı.' }
    $info = Get-LtPnpUtilResult $r.ExitCode
    foreach ($l in (($r.StdOut + "`n" + $r.StdErr) -split "`r?`n")) { if ($l.Trim()) { Write-LtLog "  $l" 'DEBUG' } }
    return New-LtResult -Id "kit.drivers.$Group" -Title $title -Status $info.Status -Message $info.Text -RestartRequired ([bool](Get-LtProp $info 'Reboot' $false)) -RestartKind $(if (Get-LtProp $info 'Reboot' $false) { 'Reboot' } else { 'None' })
}

function Import-LtKitWifiProfiles {
    param([Parameter(Mandatory)]$Kit)
    $dir = Join-Path $Kit.Root 'WiFi'
    $files = @(if ([IO.Directory]::Exists($dir)) { [IO.Directory]::GetFiles($dir, '*.xml') })
    if ($files.Count -eq 0) { return New-LtResult -Id 'kit.wifi' -Title 'Wi-Fi ağları' -Status Skipped -Message 'Kitte Wi-Fi profili yok.' }
    if (-not (Test-LtLiveSystem)) {
        $m = Get-LtMemoryState; if ($m) { [void]$m.Calls.Add("Kit.Wifi|$($files.Count)") }
        return New-LtResult -Id 'kit.wifi' -Title 'Wi-Fi ağları' -Status Skipped -Simulated $true -Message "Kuru çalışma: $($files.Count) ağ eklenmedi."
    }
    $ok = 0; $bad = 0
    foreach ($f in $files) {
        $r = Invoke-LtNative -FilePath "$env:SystemRoot\System32\netsh.exe" -Arguments @('wlan', 'add', 'profile', "filename=$f", 'user=current') -TimeoutSec 60
        if ($r.ExitCode -eq 0) { $ok++ } else { $bad++ }
    }
    $st = if ($bad -eq 0) { 'Success' } elseif ($ok -gt 0) { 'Partial' } else { 'Failed' }
    return New-LtResult -Id 'kit.wifi' -Title 'Wi-Fi ağları' -Status $st -Message "$ok ağ eklendi$(if ($bad) { ", $bad eklenemedi (Wi-Fi bağdaştırıcısının sürücüsü kurulu mu?)" }). Kitteki WiFi klasörünü artık silebilirsiniz."
}

function Get-LtKitSaveDestination([string]$Restore) {
    switch ($Restore) {
        'SavedGames' { if ($env:USERPROFILE) { return (Join-Path $env:USERPROFILE 'Saved Games') } }
        'MyGames'    { $d = [Environment]::GetFolderPath('MyDocuments'); if ($d) { return (Join-Path $d 'My Games') } }
    }
    return $null
}

function Restore-LtKitSaves {
    <# Kayitlari geri kopyalar; var olan dosyanin USTUNE YAZMAZ. #>
    param([Parameter(Mandatory)]$Kit, $Cancel = $null)
    if (@($Kit.Saves).Count -eq 0) { return New-LtResult -Id 'kit.saves' -Title 'Oyun kayıtları' -Status Skipped -Message 'Kitte oyun kaydı yok.' }
    if (-not (Test-LtLiveSystem)) {
        $m = Get-LtMemoryState; if ($m) { [void]$m.Calls.Add("Kit.Saves|$(@($Kit.Saves).Count)") }
        return New-LtResult -Id 'kit.saves' -Title 'Oyun kayıtları' -Status Skipped -Simulated $true -Message 'Kuru çalışma: kullanıcı klasörlerine kopyalanmadı.'
    }
    [void](Get-LtInteractiveUserSid)
    $files = 0; $skipped = 0; $failed = 0
    foreach ($s in @($Kit.Saves)) {
        $dest = Get-LtKitSaveDestination ([string]$s.Restore)
        if (-not $dest) { $failed++; continue }
        $c = Copy-LtDirectoryTree -Source (Join-LtKitPath $Kit.Root ([string]$s.Folder)) -Destination $dest -NoOverwrite -Cancel $Cancel
        $files += $c.Files; $skipped += $c.Skipped; $failed += $c.Failed
    }
    $st = if ($null -ne $Cancel -and $Cancel.Requested) { 'Partial' } elseif ($failed -eq 0) { 'Success' } elseif ($files -gt 0) { 'Partial' } else { 'Failed' }
    return New-LtResult -Id 'kit.saves' -Title 'Oyun kayıtları' -Status $st -Message "$(if ($null -ne $Cancel -and $Cancel.Requested) { 'İptal edildi; geri yükleme tamamlanmadı. ' })$files dosya geri kopyalandı; var olan $skipped dosyaya dokunulmadı$(if ($failed) { "; $failed hata" })."
}
