#Requires -Modules Pester
# "Keşke olsaydı" özellikleri: Sistem Kontrolü, bağlantı ölçümü, DNS seçimi, başlangıç
# uygulamaları, oyun GPU tercihi, arka plan kaydı ve Oyuncu modu. Bellek arka ucu; gerçek
# sisteme, ağa veya registry'ye dokunulmaz.

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $src = Join-Path $script:RepoRoot 'src/UI'
    . (Join-Path $src 'ViewModels.ps1')
    . (Join-Path $src 'Dialogs.ps1')
    . (Join-Path $src 'App.ps1')
    function New-LtEmptyFacts {
        @{ ProblemDevices = $null; Gpus = $null; Displays = $null; Memory = $null; SystemDisk = $null; Events = $null
           PendingReboot = @(); WindowsUpdate = $null; Network = $null; Gaming = $null; StartupEnabled = $null; IsLaptop = $false; Build = 22631 }
    }
}

Describe 'Sistem Kontrolü' {
    BeforeEach { $sys = New-LtTestSystem }
    AfterEach { Remove-LtTestSystem $sys }

    It 'Sahte sistemde sorunları önce, doğru durumlarla raporlar' {
        $r = @(Get-LtHealthReport -Facts (Get-LtHealthFacts -Context $sys.Ctx))
        $r[0].Status | Should -Be 'Problem'
        ($r | Where-Object Id -eq 'drivers').Status | Should -Be 'Problem'
        ($r | Where-Object Id -eq 'drivers').Finding | Should -Match 'sürücü yüklü değil'
        ($r | Where-Object Id -eq 'refresh').Status | Should -Be 'Warning'
        ($r | Where-Object Id -eq 'refresh').Finding | Should -Match '60 Hz.*144 Hz'
        ($r | Where-Object Id -eq 'ram').Status | Should -Be 'Warning'
        ($r | Where-Object Id -eq 'ram').Advice | Should -Match 'XMP/EXPO'
        ($r | Where-Object Id -eq 'stability').Status | Should -Be 'Warning'
        ($r | Where-Object Id -eq 'gaming').Finding | Should -Match 'VBS açık'
        ($r | Where-Object Id -eq 'disk').Status | Should -Be 'Ok'
        ($r | Where-Object Id -eq 'startup').Finding | Should -Match '^6 uygulama'
        @($r | Where-Object { $_.Status -eq 'Unknown' }).Count | Should -Be 0
    }

    It 'Okunamayan bilgi için "tamam" demez' {
        $r = @(Get-LtHealthReport -Facts (New-LtEmptyFacts))
        foreach ($id in @('drivers', 'gpu-driver', 'refresh', 'ram', 'disk', 'stability', 'windows-update', 'network', 'gaming')) {
            ($r | Where-Object Id -eq $id).Status | Should -Be 'Unknown' -Because $id
        }
        ($r | Where-Object Id -eq 'reboot').Status | Should -Be 'Ok'
    }

    It 'Temel görüntü sürücüsü, düşük alan, HDD, kapalı TRIM, WHEA ve mavi ekranı yakalar' {
        $f = New-LtEmptyFacts
        $f.Gpus = @(@{ Name = 'Microsoft Temel Görüntü Bağdaştırıcısı'; Vendor = 'AMD'; Inf = 'display.inf'; DriverDate = $null })
        $f.SystemDisk = @{ Letter = 'C'; FreeBytes = 3GB; SizeBytes = 240GB; MediaType = 'SSD'; Health = 'Healthy'; Trim = $false; TemperatureC = 75; WearPercent = 85 }
        $f.Events = @{ Days = 14; Whea = 3; UnexpectedShutdown = 0; BugCheck = 2; LastBugCheck = (Get-Date).AddDays(-1) }
        $r = @(Get-LtHealthReport -Facts $f)
        $g = $r | Where-Object Id -eq 'gpu-driver'
        $g.Status | Should -Be 'Problem'
        $g.Links | Should -Contain 'driver-amd'
        $d = $r | Where-Object Id -eq 'disk'
        $d.Status | Should -Be 'Problem'
        $d.Advice | Should -Match 'TRIM'
        $d.Advice | Should -Match 'sıcaklığı'
        $d.Advice | Should -Match 'ömrünün'
        $d.Page | Should -Be 'QuickClean'
        $s = $r | Where-Object Id -eq 'stability'
        $s.Status | Should -Be 'Problem'
        $s.Finding | Should -Match '3 donanım hatası.*2 mavi ekran'
        $s.Links | Should -Contain 'reliability'
        $f.SystemDisk = @{ Letter = 'C'; FreeBytes = 200GB; SizeBytes = 1000GB; MediaType = 'HDD'; Health = 'Healthy'; Trim = $null; TemperatureC = $null; WearPercent = $null }
        (@(Get-LtHealthReport -Facts $f) | Where-Object Id -eq 'disk').Status | Should -Be 'Info'
    }

    It 'Bekleyen yeniden başlatma, kapalı Windows Update, arka plan kaydı ve Güç Tasarrufu planını bildirir' {
        [void](Set-LtRegValue 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired' 'x' -Kind DWord -Data 1)
        [void](Set-LtRegValue 'HKLM\SYSTEM\CurrentControlSet\Services\wuauserv' 'Start' -Kind DWord -Data 4)
        [void](Set-LtRegValue 'HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'HistoricalCaptureEnabled' -Kind DWord -Data 1)
        Set-LtActivePowerScheme 'a1841308-3541-4fab-bc81-f71556f20b4a'
        $r = @(Get-LtHealthReport -Facts (Get-LtHealthFacts -Context $sys.Ctx))
        ($r | Where-Object Id -eq 'reboot').Status | Should -Be 'Warning'
        ($r | Where-Object Id -eq 'windows-update').Status | Should -Be 'Warning'
        $g = $r | Where-Object Id -eq 'gaming'
        $g.Status | Should -Be 'Warning'
        $g.Tweaks | Should -Contain 'game.bgrecord-off'
        $g.Links | Should -Contain 'power'
    }

    It 'Wi-Fi ve yavaş kablolu bağlantı için bilgi verir' {
        $f = New-LtEmptyFacts
        $f.Network = @{ Adapters = @(@{ Name = 'Wi-Fi'; Description = 'x'; Wifi = $true; LinkSpeedBps = 866000000 }) }
        (@(Get-LtHealthReport -Facts $f) | Where-Object Id -eq 'network').Status | Should -Be 'Info'
        $f.Network = @{ Adapters = @(@{ Name = 'Ethernet'; Description = 'x'; Wifi = $false; LinkSpeedBps = 100000000 }) }
        (@(Get-LtHealthReport -Facts $f) | Where-Object Id -eq 'network').Advice | Should -Match '1 Gb/s'
        $f.Network = @{ Adapters = @() }
        (@(Get-LtHealthReport -Facts $f) | Where-Object Id -eq 'network').Status | Should -Be 'Problem'
    }

    It 'Rapor metni durumları içerir, bilgisayar ve kullanıcı adını içermez' {
        $r = @(Get-LtHealthReport -Facts (Get-LtHealthFacts -Context $sys.Ctx))
        $t = Format-LtHealthReportText -Checks $r -Context $sys.Ctx
        $t | Should -Match '\[SORUN\] Aygıt sürücüleri'
        $t | Should -Match 'Öneri:'
        foreach ($n in @([Environment]::MachineName, [Environment]::UserName)) { if ($n) { $t | Should -Not -Match ([regex]::Escape($n)) } }
    }

    It 'Eylem bağlantıları sabit listeden; kuru çalışmada açılmaz; bilinmeyen kimlik reddedilir' {
        Mock -ModuleName LivnTools Start-Process { throw 'açılmamalı' }
        { Open-LtHealthLink -Id 'display-advanced' } | Should -Throw '*KURU*'
        { Open-LtHealthLink -Id 'cmd /c calc' } | Should -Throw '*Bilinmeyen*'
        foreach ($l in (Get-LtHealthLinks).Values) {
            if ($l.ContainsKey('Uri')) { $l.Uri | Should -Match '^(ms-settings:|https://www\.(nvidia|amd|intel)\.com/)' }
            else { $l.File | Should -BeIn @('devmgmt.msc', 'perfmon.exe') }
        }
        Should -Invoke -ModuleName LivnTools Start-Process -Times 0 -Exactly
    }

    It 'Arayüz öğeleri sayfa, bağlantı ve ayar eylemlerini taşır' {
        $f = Get-LtHealthFacts -Context $sys.Ctx
        $f.Gaming.BackgroundRecording = $true
        $items = @(ConvertTo-LtHealthViewItems @(Get-LtHealthReport -Facts $f))
        $g = $items | Where-Object Id -eq 'gaming'
        @($g.Actions | ForEach-Object Tag) | Should -Contain 'tweak:game.bgrecord-off'
        ($items | Where-Object Id -eq 'drivers').Actions[0].Tag | Should -Be 'link:optional-drivers'
        ($items | Where-Object Id -eq 'startup').Actions[0].Tag | Should -Be 'page:Startup'
        ($items | Where-Object Id -eq 'drivers').StatusText | Should -Be 'Sorun'
    }
}

Describe 'Bağlantı ölçümü' {
    BeforeEach { $sys = New-LtTestSystem }
    AfterEach { Remove-LtTestSystem $sys }

    It 'İstatistikler: kayıp, ortalama ve dalgalanma doğru hesaplanır' {
        $s = Get-LtLatencyStats -Samples @(10, 12, $null, 11)
        $s.LossPct | Should -Be 25
        $s.Avg | Should -Be 11
        $s.Min | Should -Be 10
        $s.Max | Should -Be 12
        $s.Jitter | Should -Be 1.5
        (Get-LtLatencyStats -Samples @($null, $null)).Received | Should -Be 0
    }

    It 'Yalnız IP veya alan adı kabul edilir' {
        foreach ($ok in @('1.1.1.1', '2606:4700:4700::1111', 'eu.server.example.com', 'riot')) { Test-LtNetworkTarget $ok | Should -BeTrue -Because $ok }
        foreach ($bad in @('', ' ', 'a b', '1.1.1.1; calc', 'http://x.com', '-n 100 x', ('a' * 300))) { Test-LtNetworkTarget $bad | Should -BeFalse -Because $bad }
        { Invoke-LtLatencyTest -Custom 'http://kötü' } | Should -Throw '*Geçersiz hedef*'
    }

    It 'Sorunun evde mi hatta mı olduğunu ayırır' {
        $gwBad = @{ Kind = 'Gateway'; Received = 20; Avg = 30; Jitter = 12; LossPct = 5 }
        $gwOk = @{ Kind = 'Gateway'; Received = 20; Avg = 1; Jitter = 0.3; LossPct = 0 }
        $inetOk = @{ Kind = 'Internet'; Received = 20; Avg = 12; Jitter = 1; LossPct = 0; Address = '1.1.1.1' }
        $inetBad = @{ Kind = 'Internet'; Received = 18; Avg = 40; Jitter = 25; LossPct = 10; Address = '8.8.8.8' }
        (Get-LtLatencyVerdict -Results @($gwBad, $inetOk) -Wifi $true) -join ' ' | Should -Match 'Ev içi ağda sorun.*Wi-Fi'
        (Get-LtLatencyVerdict -Results @($gwOk, $inetBad)) -join ' ' | Should -Match 'servis sağlayıcı'
        (Get-LtLatencyVerdict -Results @(@{ Kind = 'Gateway'; Received = 0; Avg = $null; Jitter = $null; LossPct = 100 }, $inetOk)) -join ' ' | Should -Match 'ICMP'
        (Get-LtLatencyVerdict -Results @($gwOk, $inetOk, @{ Kind = 'Custom'; Received = 20; Avg = 95; Jitter = 2; LossPct = 0; Address = 'x' })) -join ' ' | Should -Match 'bölge seçimi'
    }

    It 'Ölçüm saklanır ve bir önceki ölçümle karşılaştırılır' {
        $r1 = Invoke-LtLatencyTest -Custom '203.0.113.10'
        @($r1.Results).Count | Should -Be 4
        Save-LtLatencyResult -Result $r1
        $sys.Mem.Network.Latency['1.1.1.1'] = @{ Base = 20; Spread = 1; LossEvery = 0 }
        $r2 = Invoke-LtLatencyTest
        $prev = @(Get-LtLatencyHistory)[-1]
        $cmp = @(Compare-LtLatency -Current $r2 -Previous $prev)
        ($cmp | Where-Object { $_ -like 'Cloudflare*' }) | Should -Match 'ortalama \+8 ms'
        Save-LtLatencyResult -Result $r2
        @(Get-LtLatencyHistory).Count | Should -Be 2
        (Format-LtLatencyResult -Result $r2) | Should -Match 'Modem / yönlendirici: ort'
    }

    It 'DNS hız testi en hızlıyı başa koyar ve ping iddiasında bulunmaz' {
        $r = @(Invoke-LtDnsBenchmark -Current @('192.168.1.1'))
        $r[0].Address | Should -Be '1.1.1.1'
        @($r).Count | Should -Be 4
        (Format-LtDnsBenchmark -Results $r) | Should -Match 'oyun içi ping''i değiştirmez'
    }
}

Describe 'DNS sunucusu seçimi' {
    BeforeEach { $sys = New-LtTestSystem }
    AfterEach { Remove-LtTestSystem $sys }

    It 'Adaptör seçilmeden uygulanmaz' {
        (Invoke-LtApply -TweakIds 'dns.cloudflare' -Context $sys.Ctx).Results[0].Status | Should -Be 'NotSupported'
    }
    It 'Uygular, tekrar uygulamada değişmez, önceki (DHCP) ve varsayılana döner' {
        $sys.Ctx.SelectedNicGuid = $sys.Ctx.Nics[0].InterfaceGuid
        $guid = ([guid][string]$sys.Ctx.Nics[0].InterfaceGuid).ToString('D')
        (Invoke-LtApply -TweakIds 'dns.cloudflare' -Context $sys.Ctx).Results[0].Status | Should -Be 'Success'
        $cfg = Get-LtDnsServerConfig -InterfaceGuid $guid
        $cfg.Static | Should -BeTrue
        $cfg.Servers[0] | Should -Be '1.1.1.1'
        (Invoke-LtApply -TweakIds 'dns.cloudflare' -Context $sys.Ctx).Results[0].Status | Should -Be 'AlreadyApplied'
        (Invoke-LtRevert -TweakIds 'dns.cloudflare' -Context $sys.Ctx -Target Previous).Summary.Failed | Should -Be 0
        (Get-LtDnsServerConfig -InterfaceGuid $guid).Static | Should -BeFalse
        [void](Invoke-LtApply -TweakIds 'dns.google' -Context $sys.Ctx)
        (Invoke-LtRevert -TweakIds 'dns.google' -Context $sys.Ctx -Target Default).Summary.Failed | Should -Be 0
        (Get-LtDnsServerConfig -InterfaceGuid $guid).Static | Should -BeFalse
    }
    It 'Önceden elle girilmiş DNS birebir geri yüklenir' {
        $sys.Ctx.SelectedNicGuid = $sys.Ctx.Nics[0].InterfaceGuid
        $guid = ([guid][string]$sys.Ctx.Nics[0].InterfaceGuid).ToString('D')
        Set-LtDnsServers -InterfaceGuid $guid -Servers @('10.0.0.53', '10.0.0.54')
        [void](Invoke-LtApply -TweakIds 'dns.quad9' -Context $sys.Ctx)
        (Get-LtDnsServerConfig -InterfaceGuid $guid).Servers[0] | Should -Be '9.9.9.9'
        [void](Invoke-LtRevert -TweakIds 'dns.quad9' -Context $sys.Ctx -Target Previous)
        @((Get-LtDnsServerConfig -InterfaceGuid $guid).Servers) | Should -Be @('10.0.0.53', '10.0.0.54')
    }
    It 'Mixed IPv4 and IPv6 modes survive apply and previous-state restore' -ForEach @(
        @{ V4 = $true; V6 = $false }, @{ V4 = $false; V6 = $true }
    ) {
        $sys.Ctx.SelectedNicGuid = $sys.Ctx.Nics[0].InterfaceGuid
        $guid = ([guid][string]$sys.Ctx.SelectedNicGuid).ToString('D')
        $sys.Mem.Dns = @{}
        $sys.Mem.Dns[$guid] = @{ Static = $true; Servers = @('10.0.0.53', '2001:db8::53'); Families = @{
            IPv4 = @{ Static = $V4; Servers = @('10.0.0.53') }
            IPv6 = @{ Static = $V6; Servers = @('2001:db8::53') }
        } }
        $before = Get-LtDnsServerConfig $guid
        (Invoke-LtApply -TweakIds 'dns.cloudflare' -Context $sys.Ctx).Results[0].Status | Should -Be 'Success'
        (Invoke-LtRevert -TweakIds 'dns.cloudflare' -Context $sys.Ctx -Target Previous).Summary.Failed | Should -Be 0
        $after = Get-LtDnsServerConfig $guid
        $after.Families.IPv4.Static | Should -Be $V4
        $after.Families.IPv6.Static | Should -Be $V6
        Test-LtDnsSnapshotEqual $before $after | Should -BeTrue
    }
    It 'Family comparison detects a changed DHCP mode even when aggregate servers match' {
        $a = @{ Static = $true; Servers = @('1.1.1.1'); Families = @{
            IPv4 = @{ Static = $true; Servers = @('1.1.1.1') }; IPv6 = @{ Static = $false; Servers = @('2001:db8::53') }
        } }
        $b = @{ Static = $true; Servers = @('1.1.1.1'); Families = @{
            IPv4 = @{ Static = $true; Servers = @('1.1.1.1') }; IPv6 = @{ Static = $true; Servers = @('2001:db8::53') }
        } }
        Test-LtDnsSnapshotEqual $a $b | Should -BeFalse
        $b.Families.IPv6 = @{ Static = $false; Servers = @('2001:db8::99') }
        Test-LtDnsSnapshotEqual $a $b | Should -BeTrue
    }
    It 'Geçersiz DNS adresi yazılmaz' {
        { Set-LtDnsServers -InterfaceGuid ([guid]::NewGuid().ToString()) -Servers @('1.1.1.1; calc') } | Should -Throw '*Geçersiz DNS*'
    }
}

Describe 'Başlangıç uygulamaları' {
    BeforeEach { $sys = New-LtTestSystem }
    AfterEach { Remove-LtTestSystem $sys }

    It 'Kayıt ve klasör girdilerini listeler' {
        $items = @(Get-LtStartupItems)
        $items.Count | Should -Be 6
        @($items | Where-Object { -not $_.Enabled }).Count | Should -Be 0
        ($items | Where-Object Name -eq 'Spotify.lnk').Location | Should -Match 'klasörü'
        ($items | Where-Object Name -eq 'SecurityHealth').Scope | Should -Be 'MachineRun'
    }
    It 'Görev Yöneticisi biçimini okur' {
        Test-LtStartupApprovedEnabled @{ Exists = $false } | Should -BeTrue
        Test-LtStartupApprovedEnabled @{ Exists = $true; Data = [Convert]::ToBase64String([byte[]](6, 0, 0, 0)) } | Should -BeTrue
        Test-LtStartupApprovedEnabled @{ Exists = $true; Data = [Convert]::ToBase64String([byte[]](3, 0, 0, 0, 1, 2)) } | Should -BeFalse
        Test-LtStartupApprovedEnabled @{ Exists = $true; Data = [Convert]::ToBase64String([byte[]](7)) } | Should -BeFalse
    }
    It 'Seçilenleri kapatır, girdiyi silmez, yeniden açar ve önceki duruma döner' {
        $sys.Ctx.StartupSelection = @('UserRun|Discord', 'UserFolder|Spotify.lnk')
        $r = Invoke-LtApply -TweakIds 'startup.disable-selected' -Context $sys.Ctx
        $r.Results[0].Status | Should -Be 'Success'
        $items = @(Get-LtStartupItems)
        ($items | Where-Object Name -eq 'Discord').Enabled | Should -BeFalse
        ($items | Where-Object Name -eq 'Spotify.lnk').Enabled | Should -BeFalse
        ($items | Where-Object Name -eq 'Steam').Enabled | Should -BeTrue
        (Get-LtRegValue 'HKCU\Software\Microsoft\Windows\CurrentVersion\Run' 'Discord').Exists | Should -BeTrue -Because 'girdi silinmez'
        [void](Invoke-LtApply -TweakIds 'startup.enable-selected' -Context $sys.Ctx)
        (@(Get-LtStartupItems) | Where-Object Name -eq 'Discord').Enabled | Should -BeTrue
        (Invoke-LtRevert -TweakIds 'startup.disable-selected' -Context $sys.Ctx -Target Previous).Summary.Failed | Should -Be 0
        (Get-LtRegValue 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' 'Discord').Exists | Should -BeFalse
    }
    It 'Seçim yoksa veya öğe kaybolduysa uygulamaz' {
        (Invoke-LtApply -TweakIds 'startup.disable-selected' -Context $sys.Ctx).Results[0].Status | Should -Be 'NotSupported'
        $sys.Ctx.StartupSelection = @('UserRun|YokBoyle')
        (Invoke-LtApply -TweakIds 'startup.disable-selected' -Context $sys.Ctx).Results[0].Status | Should -Not -Be 'Success'
        @(Get-LtLedgerEntries).Count | Should -Be 0
    }
}

Describe 'Oyun ayarları' {
    BeforeEach { $sys = New-LtTestSystem }
    AfterEach { Remove-LtTestSystem $sys }

    It 'GPU tercihi: oyun yoksa veya tek GPU varsa uygulanmaz; iki GPU ile yazılır ve geri alınır' {
        (Invoke-LtApply -TweakIds 'gpu.app-high-perf' -Context $sys.Ctx).Results[0].Status | Should -Be 'NotSupported'
        $sys.Ctx.GpuPreferenceApps = @('D:\Oyunlar\Valorant\VALORANT.exe')
        Get-LtTweakSupport (Get-LtTweak 'gpu.app-high-perf') $sys.Ctx | Should -Match 'tek ekran kartı'
        $sys.Ctx.Gpus = @($sys.Ctx.Gpus) + @(@{ Name = 'Sahte Intel UHD'; Vendor = 'Intel'; InstanceId = 'PCI\VEN_8086&DEV_9A49\3&1'; DriverVersion = '31.0' })
        (Invoke-LtApply -TweakIds 'gpu.app-high-perf' -Context $sys.Ctx).Results[0].Status | Should -Be 'Success'
        $v = Get-LtRegValue 'HKCU\Software\Microsoft\DirectX\UserGpuPreferences' 'D:\Oyunlar\Valorant\VALORANT.exe'
        $v.Data | Should -Be 'GpuPreference=2;'
        (Invoke-LtRevert -TweakIds 'gpu.app-high-perf' -Context $sys.Ctx -Target Default).Summary.Failed | Should -Be 0
        (Get-LtRegValue 'HKCU\Software\Microsoft\DirectX\UserGpuPreferences' 'D:\Oyunlar\Valorant\VALORANT.exe').Exists | Should -BeFalse
    }
    It 'GPU tercihi geçersiz yolu reddeder' {
        $sys.Ctx.Gpus = @($sys.Ctx.Gpus) + @(@{ Name = 'iGPU'; Vendor = 'Intel'; InstanceId = 'PCI\VEN_8086&DEV_1\1' })
        $sys.Ctx.GpuPreferenceApps = @('\\sunucu\paylasim\oyun.exe')
        { Resolve-LtTweakActions (Get-LtTweak 'gpu.app-high-perf') $sys.Ctx } | Should -Throw '*Geçersiz*'
    }
    It 'Arka plan kaydı açıksa kapatılır ve önceki değere döner' {
        $k = 'HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR'
        [void](Set-LtRegValue $k 'HistoricalCaptureEnabled' -Kind DWord -Data 1)
        (Invoke-LtApply -TweakIds 'game.bgrecord-off' -Context $sys.Ctx).Results[0].Status | Should -Be 'Success'
        [int](Get-LtRegValue $k 'HistoricalCaptureEnabled').Data | Should -Be 0
        [void](Invoke-LtRevert -TweakIds 'game.bgrecord-off' -Context $sys.Ctx -Target Previous)
        [int](Get-LtRegValue $k 'HistoricalCaptureEnabled').Data | Should -Be 1
    }
}

Describe 'Oyuncu modu' {
    BeforeEach { $sys = New-LtTestSystem }
    AfterEach { Remove-LtTestSystem $sys }

    It 'Maksimum performansın tamamını ve oyun ayarlarını içerir; güvenlik/servis/MSI/DNS içermez' {
        $p = Get-LtPresets
        foreach ($id in $p.MaxPerformance.Ids) { $p.Gamer.Ids | Should -Contain $id }
        $p.Gamer.Ids | Should -Contain 'game.bgrecord-off'
        $p.Gamer.Ids | Should -Contain 'gpu.app-high-perf'
        foreach ($id in $p.Gamer.Ids) { $id | Should -Not -Match '^(sec\.|svc\.|msi\.|dns\.|wu\.)' }
        @($p.Keys)[0] | Should -Be 'Gamer'
    }
    It 'Adaptör ve oyun seçiliyken tümü uygulanır, hiçbiri başarısız olmaz ve geri alınır' {
        $sys.Ctx.SelectedNicGuid = $sys.Ctx.Nics[0].InterfaceGuid
        $sys.Ctx.GpuPreferenceApps = @('C:\Games\game.exe')
        $sys.Ctx.Gpus = @($sys.Ctx.Gpus) + @(@{ Name = 'iGPU'; Vendor = 'Intel'; InstanceId = 'PCI\VEN_8086&DEV_1\1' })
        $r = Resolve-LtPresetSelection -Name Gamer -Context $sys.Ctx
        foreach ($id in @('nic.flowcontrol-off', 'gpu.app-high-perf', 'game.bgrecord-off', 'power.bitsum')) { $r.Selected | Should -Contain $id }
        $apply = Invoke-LtApply -TweakIds $r.Selected -Context $sys.Ctx
        $apply.Summary.Failed | Should -Be 0 -Because (($apply.Results | Where-Object Status -eq 'Failed' | ForEach-Object { "$($_.Id): $($_.Message)" }) -join ' | ')
        (Invoke-LtRevert -TweakIds $r.Selected -Context $sys.Ctx -Target Previous).Summary.Failed | Should -Be 0
    }
    It 'Tek adaptörü otomatik hedefler, seçimleri işaretler ve doğrudan önizlemeyi açar' {
        Initialize-LtViewModels
        $script:flowCalls = New-Object System.Collections.ArrayList
        function Invoke-LtTweakFlow { param($Ids, $Mode) [void]$script:flowCalls.Add(@{ Ids = @($Ids); Mode = $Mode }) }
        $fake = { [pscustomobject]@{ Text = ''; SelectedValue = $null; SelectedItem = $null; ItemsSource = $null; Foreground = '' } }
        $script:Ui = @{ Ctx = $sys.Ctx; C = @{ CmbNetworkDevice = (& $fake); TxtPresetInfo = (& $fake); TxtStatus = (& $fake); TxtNetworkTarget = (& $fake) }; StateLoaded = @{} }
        $script:Ui.C.CmbNetworkDevice.ItemsSource = @(Get-LtNetworkDeviceChoices $sys.Ctx)
        New-LtTweakItems
        Start-LtGamerMode
        $sys.Ctx.SelectedNicGuid | Should -Be $sys.Ctx.Nics[0].InterfaceGuid
        $script:Ui.C.CmbNetworkDevice.SelectedItem.InterfaceGuid | Should -Be $sys.Ctx.Nics[0].InterfaceGuid
        $script:Ui.C.TxtNetworkTarget.Text | Should -Match '^Seçili hedef: '
        $script:flowCalls.Count | Should -Be 1
        $script:flowCalls[0].Mode | Should -Be 'Apply'
        $script:flowCalls[0].Ids | Should -Contain 'nic.flowcontrol-off'
        $script:flowCalls[0].Ids | Should -Contain 'game.bgrecord-off'
        $script:Ui.Tweaks['game.bgrecord-off'].Selected | Should -BeTrue
        $script:Ui.Tweaks['sec.vbs-off'].Selected | Should -BeFalse
        $script:Ui.C.TxtPresetInfo.Text | Should -Match '^Oyuncu modu: \d+ ayar işaretlendi'
        $script:Ui.C.TxtPresetInfo.Text | Should -Match 'oyunun \.exe'
    }
}
