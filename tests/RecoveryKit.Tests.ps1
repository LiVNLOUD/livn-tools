#Requires -Modules Pester
# Kurtarma kiti: formattan once surucu/uygulama/ayar/kayit yedegi, formattan sonra ag-once kurulum.
# Tum testler bellek arka ucunda ve gecici klasorlerde calisir; pnputil/netsh/Get-WindowsDriver
# CALISTIRILMAZ, kullanici profiline yazilmaz.

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    function New-TempDir([string]$Name) {
        $d = Join-Path ([IO.Path]::GetTempPath()) ("lt-kit-$Name-" + [guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($d); return $d
    }
    function Get-AllOptions { @{ NetDrivers = $true; OtherDrivers = $true; GpuDrivers = $false; Apps = $true; Livn = $true; Wifi = $false; Saves = $true } }
}

Describe 'Kurtarma kiti planı' {
    BeforeEach { $sys = New-LtTestSystem; $usb = New-TempDir 'usb' }
    AfterEach { Remove-LtTestSystem $sys; Remove-Item -LiteralPath $usb -Recurse -Force -ErrorAction SilentlyContinue }

    It 'Yalnız üçüncü taraf sürücüler gruplanır; ekran kartı varsayılan olarak dışarıda' {
        $all = @(Get-LtKitDrivers)
        $all.Count | Should -Be 6
        @($all | Where-Object { $_.Group -eq 'Network' }).Count | Should -Be 2
        @($all | Where-Object { $_.Group -eq 'Display' }).Count | Should -Be 1
        $plan = Get-LtKitPlan -Target $usb -SystemDrive '' -Options (Get-AllOptions)
        $plan.DriverCounts.Network | Should -Be 2
        $plan.DriverCounts.Display | Should -Be 0
        $plan.DriverCounts.Other | Should -Be 3
        $plan.TargetIssue | Should -BeNullOrEmpty
        (Format-LtKitPlan -Plan $plan) | Should -Match 'ağ 2'
    }

    It 'Windows ile gelen (oem olmayan) sürücü paketleri alınmaz' {
        $sys.Mem.Drivers += @{ Inf = 'netrtwlane.inf'; Class = 'Net'; Provider = 'Microsoft'; Version = '1'; Date = ''; Original = 'netrtwlane.inf' }
        @(Get-LtKitDrivers | Where-Object { $_.Inf -eq 'netrtwlane.inf' }).Count | Should -Be 0
    }

    It 'Sistem sürücüsü ve olmayan klasör hedef olarak reddedilir' {
        Test-LtKitTarget -Target '' | Should -Match 'seçilmedi'
        Test-LtKitTarget -Target (Join-Path $usb 'yok') | Should -Match 'yok'
        $sysRoot = [IO.Path]::GetPathRoot($usb)
        Test-LtKitTarget -Target $usb -SystemDrive $sysRoot | Should -Match 'sistem sürücüsünde'
        { New-LtRecoveryKit -Target $usb -Options (Get-AllOptions) -Context $sys.Ctx -SystemDrive $sysRoot } | Should -Throw '*sistem sürücüsünde*'
        @([IO.Directory]::GetDirectories($usb)).Count | Should -Be 0
    }

    It 'Ağ sürücüsü yoksa ve Wi-Fi seçiliyse uyarır; kuru çalışma açıkça belirtilir' {
        $sys.Mem.Drivers = @($sys.Mem.Drivers | Where-Object { $_.Class -ne 'Net' })
        $o = Get-AllOptions; $o.Wifi = $true
        $plan = Get-LtKitPlan -Target $usb -SystemDrive '' -Options $o
        ($plan.Warnings -join ' ') | Should -Match 'ağ sürücüsü bulunamadı'
        ($plan.Warnings -join ' ') | Should -Match 'DÜZ METİN'
        ($plan.Warnings -join ' ') | Should -Match 'Kuru çalışma'
    }
}

Describe 'Kurtarma kiti oluşturma (kuru çalışma)' {
    BeforeEach {
        $sys = New-LtTestSystem
        $usb = New-TempDir 'usb'
        $saves = New-TempDir 'saves'
        [void][IO.Directory]::CreateDirectory((Join-Path $saves 'Oyun1'))
        [IO.File]::WriteAllText((Join-Path $saves 'Oyun1/kayit.sav'), 'kayit-verisi')
        $sys.Mem.KitSaveSources = @(@{ Name = 'Saved Games'; Path = $saves; Restore = 'SavedGames' })
        Mock -ModuleName LivnTools Invoke-LtNative { throw 'harici komut çalışmamalı' }
        Mock -ModuleName LivnTools Get-LtWindowsDriverStore { throw 'gerçek sürücü deposu okunmamalı' }
    }
    AfterEach {
        Remove-LtTestSystem $sys
        foreach ($d in @($usb, $saves)) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'Klasör yapısı, kit.json ve KIT_OKU.txt oluşur; kit DENEME olarak işaretlenir' {
        [void](Invoke-LtApply -TweakIds 'game.mode' -Context $sys.Ctx)
        $k = New-LtRecoveryKit -Target $usb -SystemDrive '' -Options (Get-AllOptions) -Context $sys.Ctx -AppRoot $script:RepoRoot -Now ([datetime]'2026-10-02 14:30')
        $k.Path | Should -BeLike (Join-Path $usb 'LivnKurtarma-20261002-1430-DENEME')
        $root = $k.Path
        [IO.File]::Exists((Join-Path $root 'kit.json')) | Should -BeTrue
        $readme = [IO.File]::ReadAllText((Join-Path $root 'KIT_OKU.txt'))
        $readme | Should -Match 'DENEME KİTİ'
        $readme | Should -Match 'pnputil /add-driver'
        @([IO.Directory]::GetFiles((Join-Path $root 'Drivers/Network'), '*.inf', 'AllDirectories')).Count | Should -Be 2
        [IO.Directory]::Exists((Join-Path $root 'Drivers/Display')) | Should -BeFalse
        [IO.File]::Exists((Join-Path $root 'LivnTools/Main.ps1')) | Should -BeTrue
        [IO.File]::Exists((Join-Path $root 'LivnTools/src/RecoveryKit.ps1')) | Should -BeTrue
        [IO.File]::ReadAllText((Join-Path $root 'Saves/SavedGames/Oyun1/kayit.sav')) | Should -Be 'kayit-verisi'
        [IO.Directory]::Exists((Join-Path $root 'WiFi')) | Should -BeFalse -Because 'Wi-Fi yalnız açıkça seçilince alınır'
        $j = [IO.File]::ReadAllText((Join-Path $root 'kit.json')) | ConvertFrom-Json
        $j.Simulated | Should -BeTrue
        @($j.TweakIds) | Should -Contain 'game.mode'
        @($j.Drivers | ForEach-Object { $_.Folder }) | Should -Contain 'Drivers\Network\Net_Realtek_oem3'
        @($k.Parts | Where-Object { $_.Status -eq 'Failed' }).Count | Should -Be 0
        Should -Invoke -ModuleName LivnTools -CommandName Invoke-LtNative -Times 0 -Exactly
        Should -Invoke -ModuleName LivnTools -CommandName Get-LtWindowsDriverStore -Times 0 -Exactly
        @(Get-LtBlockedOperations).Count | Should -Be 0
    }

    It 'Livn copy errors cannot produce success and are persisted in the manifest' {
        Mock -ModuleName LivnTools Copy-LtDirectoryTree { @{ Files = 0; Bytes = 0; Skipped = 0; Failed = 2; Cancelled = $false } }
        $k = New-LtRecoveryKit -Target $usb -SystemDrive '' -Options (Get-AllOptions) -Context $sys.Ctx -AppRoot $script:RepoRoot
        ($k.Parts | Where-Object Name -eq 'Livn Tools').Status | Should -Be 'Failed'
        $k.Status | Should -Be 'Partial'
        $k.Manifest.Contents.Livn | Should -BeFalse
        $saved = Get-Content (Join-Path $k.Path 'kit.json') -Raw | ConvertFrom-Json
        $saved.Status | Should -Be 'Partial'
        (Read-LtRecoveryKit $k.Path).HasLivn | Should -BeFalse
        [IO.File]::ReadAllText((Join-Path $k.Path 'KIT_OKU.txt')) | Should -Match 'KİT TAMAMLANMADI'
    }

    It 'Missing application root fails instead of promising an offline launcher' {
        $o = Get-AllOptions; $o.NetDrivers = $false; $o.OtherDrivers = $false; $o.Apps = $false; $o.Saves = $false
        $k = New-LtRecoveryKit -Target $usb -SystemDrive '' -Options $o -Context $sys.Ctx
        $k.Status | Should -Be 'Failed'
        $k.Manifest.Contents.Livn | Should -BeFalse
    }

    It 'Complete application copy is successful and every required file exists' {
        $o = Get-AllOptions; $o.Saves = $false
        $k = New-LtRecoveryKit -Target $usb -SystemDrive '' -Options $o -Context $sys.Ctx -AppRoot $script:RepoRoot
        $k.Status | Should -Be 'Success'
        @(Get-LtKitMissingAppFiles (Join-Path $k.Path 'LivnTools')).Count | Should -Be 0
        (Read-LtRecoveryKit $k.Path).HasLivn | Should -BeTrue
    }

    It 'Cancellation prevents later inventory wifi and copy operations' {
        Mock -ModuleName LivnTools Get-LtSetupInventory { throw 'must not start' }
        Mock -ModuleName LivnTools Export-LtWifiProfiles { throw 'must not start' }
        Mock -ModuleName LivnTools Copy-LtDirectoryTree { throw 'must not start' }
        $o = Get-AllOptions; $o.Wifi = $true
        $k = New-LtRecoveryKit -Target $usb -SystemDrive '' -Options $o -Context $sys.Ctx -AppRoot $script:RepoRoot -Cancel @{ Requested = $true }
        $k.Status | Should -Be 'Cancelled'
        $k.Manifest.Contents.Apps | Should -BeFalse
        $k.Manifest.Contents.Livn | Should -BeFalse
        Should -Invoke -ModuleName LivnTools Get-LtSetupInventory -Times 0 -Exactly
        Should -Invoke -ModuleName LivnTools Export-LtWifiProfiles -Times 0 -Exactly
        Should -Invoke -ModuleName LivnTools Copy-LtDirectoryTree -Times 0 -Exactly
    }

    It 'Cancellation during driver export is recorded and stops subsequent sections' {
        $cancel = @{ Requested = $false }
        Mock -ModuleName LivnTools Export-LtDriverPackage { $cancel.Requested = $true; @{ Ok = $true } }
        Mock -ModuleName LivnTools Get-LtSetupInventory { throw 'must not start' }
        $k = New-LtRecoveryKit -Target $usb -SystemDrive '' -Options (Get-AllOptions) -Context $sys.Ctx -Cancel $cancel
        $k.Status | Should -Be 'Cancelled'
        @($k.Manifest.Drivers).Count | Should -Be 1
        Should -Invoke -ModuleName LivnTools Get-LtSetupInventory -Times 0 -Exactly
    }

    It 'Seçime bağlı (bu PC''ye özgü) ayarlar kite yazılmaz' {
        Mock -ModuleName LivnTools Get-LtLedgerEntries { @(@{ tweakIds = @('game.mode', 'net.ackfreq', 'nic.flowcontrol-off', 'dns.cloudflare', 'yok.boyle') }) }
        Mock -ModuleName LivnTools Get-LtTweakStatus { @{ State = 'Applied' } }
        $ids = @(Get-LtKitAppliedTweakIds -Context $sys.Ctx)
        $ids | Should -Be @('game.mode')
    }

    It 'Wi-Fi seçilince parola uyarısı kite yazılır; aynı dakikada ikinci kit ayrı klasöre gider' {
        $o = Get-AllOptions; $o.Wifi = $true; $o.Saves = $false
        $now = [datetime]'2026-10-02 14:30'
        $a = New-LtRecoveryKit -Target $usb -SystemDrive '' -Options $o -Context $sys.Ctx -Now $now
        $b = New-LtRecoveryKit -Target $usb -SystemDrive '' -Options $o -Context $sys.Ctx -Now $now
        $b.Path | Should -Not -Be $a.Path
        @([IO.Directory]::GetFiles((Join-Path $a.Path 'WiFi'), '*.xml')).Count | Should -Be 1
        [IO.File]::ReadAllText((Join-Path $a.Path 'KIT_OKU.txt')) | Should -Match 'parolalar düz metindir'
    }

    It 'İptal edilince sürücü dışa aktarma durur' {
        $cancel = [hashtable]::Synchronized(@{ Requested = $true })
        $k = New-LtRecoveryKit -Target $usb -SystemDrive '' -Options (Get-AllOptions) -Context $sys.Ctx -Cancel $cancel
        @($k.Manifest.Drivers).Count | Should -Be 0
    }
}

Describe 'Kurtarma kitini okuma (güvenilmeyen girdi)' {
    BeforeEach {
        $sys = New-LtTestSystem
        $usb = New-TempDir 'usb'
        $sys.Mem.KitSaveSources = @()
        $k = New-LtRecoveryKit -Target $usb -SystemDrive '' -Options (Get-AllOptions) -Context $sys.Ctx
        $kitRoot = $k.Path
    }
    AfterEach { Remove-LtTestSystem $sys; Remove-Item -LiteralPath $usb -Recurse -Force -ErrorAction SilentlyContinue }

    It 'Oluşturulan kit geri okunur ve özetlenir' {
        $kit = Read-LtRecoveryKit -Path $kitRoot
        $kit.Simulated | Should -BeTrue
        @($kit.Drivers).Count | Should -Be 5
        (Format-LtKitSummary -Kit $kit) | Should -Match 'ağ 2, diğer 3, ekran kartı 0'
        (Read-LtRecoveryKit -Path (Join-Path $kitRoot 'kit.json')).Root | Should -Be $kitRoot
    }

    It 'Bilinmeyen kimlikler, kit dışına çıkan yollar ve seçime bağlı ayarlar atılır' {
        $j = [ordered]@{
            Schema = 1; Simulated = $true; Created = 'x'; Tool = 'x'; Build = 22631
            Drivers = @(
                @{ Inf = 'oem1.inf'; Group = 'Network'; Folder = 'Drivers\Network\ok' },
                @{ Inf = 'oem2.inf'; Group = 'Network'; Folder = '..\..\Windows\System32' },
                @{ Inf = 'oem3.inf'; Group = 'Network'; Folder = 'C:\Windows' },
                @{ Inf = 'oem4.inf'; Group = 'Network'; Folder = 'DriversX\a' },
                @{ Inf = 'oem5.inf'; Group = 'Kotu'; Folder = 'Drivers\Other\x' })
            AppIds = @('Mozilla.Firefox', 'Kotu.Uygulama'); TweakIds = @('game.mode', 'yok.boyle', 'net.ackfreq')
            Saves = @(@{ Restore = 'SavedGames'; Folder = 'Saves\SavedGames' }, @{ Restore = 'Profil'; Folder = 'Saves\x' }, @{ Restore = 'MyGames'; Folder = 'Saves\..\..\x' })
        }
        [IO.File]::WriteAllText((Join-Path $kitRoot 'kit.json'), (ConvertTo-Json -InputObject $j -Depth 5))
        $kit = Read-LtRecoveryKit -Path $kitRoot
        @($kit.Drivers | ForEach-Object { $_.Inf }) | Should -Be @('oem1.inf')
        $kit.AppIds | Should -Be @('Mozilla.Firefox')
        $kit.TweakIds | Should -Be @('game.mode')
        @($kit.Saves).Count | Should -Be 1
    }

    It 'Yanlış şema ve eksik dosya reddedilir' {
        [IO.File]::WriteAllText((Join-Path $kitRoot 'kit.json'), '{"Schema": 99}')
        { Read-LtRecoveryKit -Path $kitRoot } | Should -Throw '*Desteklenmeyen*'
        { Read-LtRecoveryKit -Path (Join-Path $usb 'yok') } | Should -Throw '*kit.json yok*'
    }

    It 'Kit arama: hedef köklerde ve uygulamanın üst klasöründe bulunur' {
        $sys.Mem.KitSearchRoots = @($usb)
        @(Find-LtRecoveryKits) | Should -Be @($kitRoot)
        $sys.Mem.KitSearchRoots = @()
        @(Find-LtRecoveryKits -AppRoot (Join-Path $kitRoot 'LivnTools')) | Should -Be @($kitRoot)
    }
}

Describe 'Formattan sonra geri yükleme (kuru çalışma)' {
    BeforeEach {
        $sys = New-LtTestSystem
        $usb = New-TempDir 'usb'
        $saves = New-TempDir 'saves'
        [IO.File]::WriteAllText((Join-Path $saves 'a.sav'), '1')
        $sys.Mem.KitSaveSources = @(@{ Name = 'Saved Games'; Path = $saves; Restore = 'SavedGames' })
        $o = Get-AllOptions; $o.Wifi = $true; $o.GpuDrivers = $true
        $kit = Read-LtRecoveryKit -Path (New-LtRecoveryKit -Target $usb -SystemDrive '' -Options $o -Context $sys.Ctx).Path
        Mock -ModuleName LivnTools Invoke-LtNative { throw 'harici komut çalışmamalı' }
        $sys.Mem.Calls.Clear()
    }
    AfterEach {
        Remove-LtTestSystem $sys
        foreach ($d in @($usb, $saves)) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'Sürücüler ağ önce kurulur; hiçbir harici komut çalışmaz' {
        $r = @('Network', 'Other', 'Display') | ForEach-Object { Install-LtKitDrivers -Kit $kit -Group $_ }
        @($r | ForEach-Object { $_.Status }) | Should -Be @('Skipped', 'Skipped', 'Skipped')
        @($r | Where-Object { -not $_.Simulated }).Count | Should -Be 0
        @($sys.Mem.Calls) | Should -Be @('Kit.InstallDrivers|Network', 'Kit.InstallDrivers|Other', 'Kit.InstallDrivers|Display')
        Should -Invoke -ModuleName LivnTools -CommandName Invoke-LtNative -Times 0 -Exactly
    }

    It 'Wi-Fi ve oyun kayıtları kuru çalışmada kullanıcı profiline yazılmaz' {
        (Import-LtKitWifiProfiles -Kit $kit).Simulated | Should -BeTrue
        (Restore-LtKitSaves -Kit $kit).Simulated | Should -BeTrue
        @($sys.Mem.Calls) | Should -Be @('Kit.Wifi|1', 'Kit.Saves|1')
        Should -Invoke -ModuleName LivnTools -CommandName Invoke-LtNative -Times 0 -Exactly
    }

    It 'Kitte olmayan grup atlanır' {
        $empty = [pscustomobject]@{ Root = $kit.Root; Drivers = @(); Saves = @() }
        (Install-LtKitDrivers -Kit $empty -Group Network).Status | Should -Be 'Skipped'
        (Restore-LtKitSaves -Kit $empty).Message | Should -Match 'oyun kaydı yok'
        $sys.Mem.Calls.Count | Should -Be 0
    }

    It 'Gerçek modda DENEME kiti reddedilir ve aramada atlanır' {
        Mock -ModuleName LivnTools Test-LtLiveSystem { $true }
        { Read-LtRecoveryKit -Path $kit.Root } | Should -Throw '*DENEME*'
    }
}

Describe 'Kurtarma kiti yardımcıları' {
    It 'pnputil çıkış kodları doğru yorumlanır' {
        (Get-LtPnpUtilResult 0).Status | Should -Be 'Success'
        (Get-LtPnpUtilResult 3010).Reboot | Should -BeTrue
        (Get-LtPnpUtilResult 1641).Reboot | Should -BeTrue
        (Get-LtPnpUtilResult 259).Status | Should -Be 'AlreadyApplied'
        (Get-LtPnpUtilResult 5).Status | Should -Be 'Failed'
    }

    It 'Göreli yol denetimi kit dışına çıkışı engeller' {
        Test-LtKitRelativePath -Path 'Drivers\Network\x' -Prefix 'Drivers' | Should -BeTrue
        foreach ($bad in @('Drivers\..\..\x', '..\Drivers\x', 'C:\Drivers\x', '/etc/x', 'DriversX\a', 'Drivers', '')) {
            Test-LtKitRelativePath -Path $bad -Prefix 'Drivers' | Should -BeFalse -Because $bad
        }
    }

    It 'Missing copy source and recursive destination are failures' {
        $src = New-TempDir 'recursive'
        try {
            (Copy-LtDirectoryTree -Source (Join-Path $src 'missing') -Destination (Join-Path $src 'dst')).Failed | Should -Be 1
            (Copy-LtDirectoryTree -Source $src -Destination (Join-Path $src 'inside')).Failed | Should -Be 1
            [IO.Directory]::Exists((Join-Path $src 'inside')) | Should -BeFalse
            (Copy-LtDirectoryTree -Source $src -Destination $src).Failed | Should -Be 1
        } finally { Remove-Item $src -Recurse -Force }
    }

    It 'Pre-cancelled copy creates no destination and reports cancellation' {
        $src = New-TempDir 'cancel'
        try {
            $dest = Join-Path $src 'not-created'
            $r = Copy-LtDirectoryTree -Source $src -Destination $dest -Cancel @{ Requested = $true }
            $r.Cancelled | Should -BeTrue
            $r.Files | Should -Be 0
            Test-Path $dest | Should -BeFalse
        } finally { Remove-Item $src -Recurse -Force }
    }

    It 'Linked source or destination is rejected before file IO' {
        $src = New-TempDir 'link'
        try {
            Mock -ModuleName LivnTools Test-LtKitLinkedPath { $true }
            (Copy-LtDirectoryTree -Source $src -Destination (Join-Path $src 'dst')).Failed | Should -Be 1
            Test-LtKitTarget -Target $src | Should -Match 'bağlantı'
        } finally { Remove-Item $src -Recurse -Force }
    }

    It 'Geri kopyalama var olan dosyanın üstüne yazmaz' {
        $src = New-TempDir 'src'; $dst = New-TempDir 'dst'
        try {
            [void][IO.Directory]::CreateDirectory((Join-Path $src 'alt'))
            [IO.File]::WriteAllText((Join-Path $src 'alt/a.sav'), 'kitteki')
            [IO.File]::WriteAllText((Join-Path $src 'b.sav'), 'yeni')
            [void][IO.Directory]::CreateDirectory((Join-Path $dst 'alt'))
            [IO.File]::WriteAllText((Join-Path $dst 'alt/a.sav'), 'oyuncunun-yeni-kaydi')
            $r = Copy-LtDirectoryTree -Source $src -Destination $dst -NoOverwrite
            $r.Files | Should -Be 1; $r.Skipped | Should -Be 1
            [IO.File]::ReadAllText((Join-Path $dst 'alt/a.sav')) | Should -Be 'oyuncunun-yeni-kaydi'
            [IO.File]::ReadAllText((Join-Path $dst 'b.sav')) | Should -Be 'yeni'
        } finally { Remove-Item -LiteralPath $src, $dst -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Describe 'Kurtarma kiti arayüz akışı (WPF olmadan, iş gövdesi doğrudan)' {
    BeforeAll {
        $src = Join-Path $script:RepoRoot 'src/UI'
        . (Join-Path $src 'ViewModels.ps1')
        . (Join-Path $src 'Dialogs.ps1')
        . (Join-Path $src 'App.ps1')
    }
    BeforeEach {
        $sys = New-LtTestSystem
        $usb = New-TempDir 'usb'
        $sys.Mem.KitSaveSources = @()
        $o = Get-AllOptions; $o.GpuDrivers = $true
        $made = New-LtRecoveryKit -Target $usb -SystemDrive '' -Options $o -Context $sys.Ctx
        $chk = { param($v) [pscustomobject]@{ IsChecked = $v } }
        $script:Ui = @{ Ctx = $sys.Ctx; Window = $null; Job = $null
            C = @{ TxtKitSummary = [pscustomobject]@{ Text = '' }; TxtStatus = [pscustomobject]@{ Text = '' }
                   ChkKitNet = (& $chk $true); ChkKitOther = (& $chk $true); ChkKitGpu = (& $chk $false); ChkKitApps = (& $chk $true)
                   ChkKitLivn = (& $chk $true); ChkKitSaves = (& $chk $false); ChkKitWifi = (& $chk $false) } }
        $script:jobs = New-Object System.Collections.ArrayList
        function Start-LtJob { param($Title, $Body, $JobArgs, $OnDone, [switch]$Quiet) [void]$script:jobs.Add(@{ Body = $Body; Args = $JobArgs; OnDone = $OnDone }); $true }
        $script:answers = New-Object System.Collections.Queue
        function Show-LtMessage { param($Owner, $Text, $Buttons, $Icon) $script:answers.Dequeue() }
    }
    AfterEach { Remove-LtTestSystem $sys; Remove-Item -LiteralPath $usb -Recurse -Force -ErrorAction SilentlyContinue }

    It 'Seçenekler onay kutularından okunur' {
        $o = Get-LtKitOptionsFromUi
        $o.NetDrivers | Should -BeTrue; $o.GpuDrivers | Should -BeFalse; $o.Saves | Should -BeFalse
    }

    It 'Sürücü adımı: onay → ağ, diğer, (istenirse) ekran kartı sırasıyla' {
        [void](Set-LtLoadedKit -Path $made.Path)
        $script:Ui.C.TxtKitSummary.Text | Should -Match 'ekran kartı 1'
        $script:answers.Enqueue('Yes'); $script:answers.Enqueue('Yes')
        Start-LtKitRestoreStep Drivers
        $script:jobs.Count | Should -Be 1
        $p = @{ Text = '' }
        $r = & $script:jobs[0].Body $script:jobs[0].Args $p @{ Requested = $false }
        @($r.Results | ForEach-Object { $_.Id }) | Should -Be @('kit.drivers.Network', 'kit.drivers.Other', 'kit.drivers.Display')
        @($sys.Mem.Calls | Where-Object { $_ -like 'Kit.*' }) | Should -Be @('Kit.InstallDrivers|Network', 'Kit.InstallDrivers|Other', 'Kit.InstallDrivers|Display')
    }

    It 'Ekran kartı sorusuna Hayır denince GPU sürücüsü kurulmaz; ilk onaya Hayır denince iş başlamaz' {
        [void](Set-LtLoadedKit -Path $made.Path)
        $script:answers.Enqueue('Yes'); $script:answers.Enqueue('No')
        Start-LtKitRestoreStep Drivers
        $r = & $script:jobs[0].Body $script:jobs[0].Args @{ Text = '' } @{ Requested = $false }
        @($r.Results | ForEach-Object { $_.Id }) | Should -Not -Contain 'kit.drivers.Display'
        $script:answers.Enqueue('No')
        Start-LtKitRestoreStep Wifi
        $script:jobs.Count | Should -Be 1
    }

    It 'Kit yüklenmeden geri yükleme başlamaz' {
        $script:Ui.Kit = $null
        Start-LtKitRestoreStep Saves
        $script:jobs.Count | Should -Be 0
        $script:Ui.C.TxtStatus.Text | Should -Match 'Önce kiti'
    }
}
