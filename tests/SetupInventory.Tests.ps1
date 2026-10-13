#Requires -Modules Pester
# Format Sonrası uygulama envanteri: kurulu / kurulu değil / durum okunamadı.
# WinGet yokluğu veya sorgu hatası ASLA "kurulu değil" sayılmaz. Envanter arka planda,
# sınırlı sıklıkta okunur; seçimler, arama ve kategori korunur. Gerçek winget çalıştırılmaz.

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
}

Describe 'Envanter motoru' {
    BeforeEach {
        $sys = New-LtTestSystem
        Mock -ModuleName LivnTools -CommandName Invoke-LtNative -MockWith { throw 'YAN ETKİ: winget çalıştırıldı' }
    }
    AfterEach { Remove-LtTestSystem $sys }

    It 'Kurulu ve kurulu olmayan uygulamaları ayırır; gerçek winget çalıştırılmaz' {
        $inv = Get-LtSetupInventory
        $inv.Status | Should -Be 'Ok'
        $inv.Simulated | Should -BeTrue
        Get-LtSetupAppState -Inventory $inv -Id 'Mozilla.Firefox' | Should -Be 'Installed'
        Get-LtSetupAppState -Inventory $inv -Id 'Brave.Brave' | Should -Be 'NotInstalled'
        # Sahte Uninstall kaydında var, WinGet envanterinde yok
        Get-LtSetupAppState -Inventory $inv -Id 'Google.Chrome' | Should -Be 'InstalledExternal'
        @($inv.ExternalIds) | Should -Contain 'Google.Chrome'
        @($inv.ExternalIds) | Should -Not -Contain 'Valve.Steam' -Because 'Steam WinGet ile de eşleşiyor'
        Should -Invoke -ModuleName LivnTools -CommandName Invoke-LtNative -Times 0 -Exactly
    }

    It 'Kimlik karşılaştırması büyük/küçük harf duyarsızdır ve katalog dışı kimlikler alınmaz' {
        $sys.Mem.Setup.InstalledIds = @('valve.steam', 'Some.Other.Package')
        $inv = Get-LtSetupInventory
        @($inv.InstalledIds | Sort-Object) | Should -Be @('Discord.Discord', 'Google.Chrome', 'Valve.Steam')
        @($inv.InstalledIds) | Should -Not -Contain 'Some.Other.Package'
        Get-LtSetupAppState -Inventory $inv -Id 'Valve.Steam' | Should -Be 'Installed'
    }

    It 'Boş WinGet envanteri: Windows listesinde olmayanlar kurulu değil (okuma başarılı olduğu için)' {
        $sys.Mem.Setup.InstalledIds = @()
        $inv = Get-LtSetupInventory
        $inv.Status | Should -Be 'Ok'
        $arp = @('Google.Chrome', 'Valve.Steam', 'Discord.Discord')
        foreach ($app in Get-LtSetupApps) {
            $expected = if ($arp -contains $app.Id) { 'InstalledExternal' } else { 'NotInstalled' }
            Get-LtSetupAppState -Inventory $inv -Id $app.Id | Should -Be $expected -Because $app.Id
        }
    }

    It 'WinGet yoksa hiçbir uygulama "kurulu değil" sayılmaz' {
        $sys.Mem.Setup.WingetAvailable = $false
        $inv = Get-LtSetupInventory
        $inv.Status | Should -Be 'WingetMissing'
        $inv.Message | Should -Match 'bulunamadı'
        foreach ($app in Get-LtSetupApps) {
            $expected = if (@('Google.Chrome', 'Valve.Steam', 'Discord.Discord') -contains $app.Id) { 'InstalledExternal' } else { 'Unknown' }
            Get-LtSetupAppState -Inventory $inv -Id $app.Id | Should -Be $expected -Because $app.Id
        }
    }

    It 'Sorgu hatası "durum okunamadı" olur, "kurulu değil" olmaz' {
        $sys.Mem.Faults['Winget.Inventory:export'] = 'Kaynak sözleşmesi okunamadı'
        $inv = Get-LtSetupInventory
        $inv.Status | Should -Be 'Error'
        $inv.Message | Should -Match 'Kaynak sözleşmesi'
        foreach ($app in Get-LtSetupApps) {
            $expected = if (@('Google.Chrome', 'Valve.Steam', 'Discord.Discord') -contains $app.Id) { 'InstalledExternal' } else { 'Unknown' }
            Get-LtSetupAppState -Inventory $inv -Id $app.Id | Should -Be $expected -Because $app.Id
        }
        Get-LtSetupStateText 'Unknown' | Should -Be 'Durum okunamadı'
    }

    It 'DirectX bileşenleri sistem dosyasından algılanır' {
        Get-LtSetupAppState -Inventory (Get-LtSetupInventory) -Id 'Microsoft.DirectX' | Should -Be 'NotInstalled'
        $sys.Mem.Setup.Files = @('System32\d3dx9_43.dll')
        Get-LtSetupAppState -Inventory (Get-LtSetupInventory) -Id 'Microsoft.DirectX' | Should -Be 'InstalledExternal'
    }

    It 'WinGet dışı kurulan Brave (kullanıcı başına kayıt) kurulu görünür' {
        [void](Set-LtRegValue 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\BraveSoftware Brave-Browser' 'DisplayName' -Kind String -Data 'Brave')
        $inv = Get-LtSetupInventory
        Get-LtSetupAppState -Inventory $inv -Id 'Brave.Brave' | Should -Be 'InstalledExternal'
        Get-LtSetupStateText 'InstalledExternal' | Should -Be 'Kurulu (WinGet dışı)'
    }

    It 'Windows listesi desenleri benzer adlı başka ürünleri eşleştirmez' {
        $cases = @(
            @{ Name = 'Brave'; Id = 'Brave.Brave'; Match = $true }
            @{ Name = 'Brave Beta'; Id = 'Brave.Brave'; Match = $false }
            @{ Name = 'Git'; Id = 'Git.Git'; Match = $true }
            @{ Name = 'Git version 2.44.0'; Id = 'Git.Git'; Match = $true }
            @{ Name = 'Git LFS version 3.4.1'; Id = 'Git.Git'; Match = $false }
            @{ Name = 'GitHub Desktop'; Id = 'Git.Git'; Match = $false }
            @{ Name = '7-Zip 23.01 (x64)'; Id = '7zip.7zip'; Match = $true }
            @{ Name = 'Notepad++ (64-bit x64)'; Id = 'Notepad++.Notepad++'; Match = $true }
            @{ Name = 'Mozilla Firefox (x64 tr)'; Id = 'Mozilla.Firefox'; Match = $true }
            @{ Name = 'Mozilla Maintenance Service'; Id = 'Mozilla.Firefox'; Match = $false }
            @{ Name = 'Microsoft Visual Studio Code (User)'; Id = 'Microsoft.VisualStudioCode'; Match = $true }
            @{ Name = 'Steam Mover'; Id = 'Valve.Steam'; Match = $false }
            @{ Name = 'Discord PTB'; Id = 'Discord.Discord'; Match = $false }
        )
        foreach ($t in $cases) {
            (@(Get-LtSetupArpMatches -DisplayNames @($t.Name)) -contains $t.Id) | Should -Be $t.Match -Because $t.Name
        }
        @(Get-LtSetupApps | Where-Object { -not $_.Arp -and $_.Id -ne 'Microsoft.DirectX' }).Count | Should -Be 0 -Because 'her katalog uygulamasının Windows listesi deseni (veya dosya deseni) olmalı'
        (@(Get-LtSetupArpMatches -DisplayNames @('Microsoft Visual C++ 2015-2022 Redistributable (x64) - 14.44.35211')) -contains 'Microsoft.VCRedist.2015+.x64') | Should -BeTrue
        (@(Get-LtSetupArpMatches -DisplayNames @('Microsoft Visual C++ v14 Redistributable (x86) - 14.50.1')) -contains 'Microsoft.VCRedist.2015+.x86') | Should -BeTrue
        (@(Get-LtSetupArpMatches -DisplayNames @('Microsoft Visual C++ 2013 Redistributable (x64) - 12.0.40664')) -contains 'Microsoft.VCRedist.2015+.x64') | Should -BeFalse
        (@(Get-LtSetupArpMatches -DisplayNames @('Microsoft Windows Desktop Runtime - 8.0.31 (x64)')) -contains 'Microsoft.DotNet.DesktopRuntime.8') | Should -BeTrue
        (@(Get-LtSetupArpMatches -DisplayNames @('Microsoft Windows Desktop Runtime - 6.0.36 (x64)')) -contains 'Microsoft.DotNet.DesktopRuntime.8') | Should -BeFalse
    }

    It 'Gerçek dalda: WinGet komutu yoksa Available=false; export hatası istisna olarak iletilir' {
        Mock -ModuleName LivnTools -CommandName Test-LtLiveSystem -MockWith { $true }
        Mock -ModuleName LivnTools -CommandName Get-LtInteractiveUserSid -MockWith { 'S-1-5-21-1000' }
        Mock -ModuleName LivnTools -CommandName Get-LtWingetVersion -MockWith { [version]'1.9.25200' }
        Mock -ModuleName LivnTools -CommandName Get-Command -ParameterFilter { $Name -eq 'winget.exe' } -MockWith { $null }
        Mock -ModuleName LivnTools -CommandName Get-LtWingetInstalledIds -MockWith { throw 'export çıkış kodu 5' }
        (Read-LtWingetInventory).Available | Should -BeFalse
        (Get-LtSetupInventory).Status | Should -Be 'WingetMissing'
        Mock -ModuleName LivnTools -CommandName Get-Command -ParameterFilter { $Name -eq 'winget.exe' } -MockWith { [pscustomobject]@{ Source = 'C:\fake\winget.exe' } }
        $inv = Get-LtSetupInventory
        $inv.Status | Should -Be 'Error'
        $inv.Message | Should -Match 'çıkış kodu 5'
        Should -Invoke -ModuleName LivnTools -CommandName Invoke-LtNative -Times 0 -Exactly
        # Arka plan envanteri kaynak sözleşmesini kullanıcı adına kabul etmez
        Should -Invoke -ModuleName LivnTools -CommandName Get-LtWingetInstalledIds -ParameterFilter { -not $AcceptSourceAgreements } -Times 1 -Exactly
        Should -Invoke -ModuleName LivnTools -CommandName Get-LtWingetInstalledIds -ParameterFilter { [bool]$AcceptSourceAgreements } -Times 0 -Exactly
    }

    It 'Envanter export komutu sözleşme kabulü içermez; kurulum akışı içerir' {
        Mock -ModuleName LivnTools -CommandName Test-LtLiveSystem -MockWith { $true }
        Mock -ModuleName LivnTools -CommandName Assert-LtLiveSystem -MockWith { }
        Mock -ModuleName LivnTools -CommandName Get-LtWingetPath -MockWith { 'C:\fake\winget.exe' }
        $script:wingetCalls = New-Object System.Collections.ArrayList
        Mock -ModuleName LivnTools -CommandName Invoke-LtNative -MockWith {
            [void]$script:wingetCalls.Add(($Arguments -join ' '))
            $out = $Arguments[[array]::IndexOf($Arguments, '--output') + 1]
            [IO.File]::WriteAllText($out, '{"Sources":[{"Packages":[{"PackageIdentifier":"Valve.Steam"}]}]}')
            [pscustomobject]@{ ExitCode = 0; StdOut = ''; StdErr = ''; TimedOut = $false; Cancelled = $false }
        }
        @(Get-LtWingetInstalledIds) | Should -Be @('Valve.Steam')
        @(Get-LtWingetInstalledIds -AcceptSourceAgreements) | Should -Be @('Valve.Steam')
        $script:wingetCalls[0] | Should -Not -Match 'accept-source-agreements'
        $script:wingetCalls[1] | Should -Match 'accept-source-agreements'
        @(Get-ChildItem -LiteralPath (Get-LtDataRoot) -Filter 'winget-inventory-*').Count | Should -Be 0
    }

    It 'WinGet export hatası anlaşılır metne çevrilir ve geçici dosya kalmaz' {
        Mock -ModuleName LivnTools -CommandName Test-LtLiveSystem -MockWith { $true }
        Mock -ModuleName LivnTools -CommandName Assert-LtLiveSystem -MockWith { }
        Mock -ModuleName LivnTools -CommandName Invoke-LtNative -MockWith { [pscustomobject]@{ ExitCode = [int]0x8A150045; StdOut = ''; StdErr = ''; TimedOut = $false; Cancelled = $false } }
        { Get-LtWingetInstalledIds -WingetPath 'C:\fake\winget.exe' } | Should -Throw '*kaynağı açılamadı*0x8A150045*'
        @(Get-ChildItem -LiteralPath (Get-LtDataRoot) -Filter 'winget-inventory-*').Count | Should -Be 0
    }

    It 'Eski WinGet: envanter okunmaz, "kurulu değil" denmez ve yönlendirme gösterilir' {
        $sys.Mem.Setup.WingetVersion = 'v1.2.10271'
        $inv = Get-LtSetupInventory
        $inv.Status | Should -Be 'WingetOutdated'
        $inv.Message | Should -Match 'çok eski'
        Get-LtSetupAppState -Inventory $inv -Id 'Mozilla.Firefox' | Should -Be 'Unknown' -Because 'WinGet listesi okunmadı'
        Get-LtSetupAppState -Inventory $inv -Id 'Google.Chrome' | Should -Be 'InstalledExternal' -Because 'Windows listesi yine okunur'
    }

    It 'winget.exe PATH dışında da bulunur (WindowsApps takma adı, sonra App Installer klasörü)' {
        Mock -ModuleName LivnTools -CommandName Test-LtLiveSystem -MockWith { $true }
        Mock -ModuleName LivnTools -CommandName Assert-LtLiveSystem -MockWith { }
        Mock -ModuleName LivnTools -CommandName Get-LtInteractiveUserSid -MockWith { 'S-1-5-21-1000' }
        Mock -ModuleName LivnTools -CommandName Get-Command -ParameterFilter { $Name -eq 'winget.exe' } -MockWith { $null }
        $saved = $env:LOCALAPPDATA
        try {
            $env:LOCALAPPDATA = 'C:\Users\kaan\AppData\Local'
            Mock -ModuleName LivnTools -CommandName Test-Path -ParameterFilter { $LiteralPath -like '*WindowsApps*winget.exe' } -MockWith { $true }
            Get-LtWingetPath | Should -BeLike '*Microsoft*WindowsApps*winget.exe'
            Mock -ModuleName LivnTools -CommandName Test-Path -ParameterFilter { $LiteralPath -like '*WindowsApps*winget.exe' } -MockWith { $false }
            { Get-LtWingetPath } | Should -Throw 'WINGET_MISSING:*'
        } finally { $env:LOCALAPPDATA = $saved }
    }

    It 'WinGet sürümü ve hata kodları yorumlanır' {
        ConvertFrom-LtWingetVersion 'v1.9.25200' | Should -Be ([version]'1.9.25200')
        ConvertFrom-LtWingetVersion 'v1.6' | Should -Be ([version]'1.6.0')
        ConvertFrom-LtWingetVersion 'bilinmiyor' | Should -BeNullOrEmpty
        (Get-LtWingetErrorInfo ([int]0x8A150061)).Kind | Should -Be 'Installed'
        (Get-LtWingetErrorInfo ([int]0x8A150109)).Kind | Should -Be 'RebootToFinish'
        (Get-LtWingetErrorInfo ([int]0x8A150101)).Text | Should -Match 'Uygulama açık'
        (Get-LtWingetErrorInfo ([int]0x8A15003A)).Text | Should -Match 'Grup İlkesi'
        (Get-LtWingetErrorInfo 1603).Text | Should -Match '1603'
    }

    It 'Yenileme sıklığı sınırlıdır' {
        $now = Get-Date
        (Test-LtSetupInventoryRefresh -Now $now).Allowed | Should -BeTrue
        (Test-LtSetupInventoryRefresh -LastAttempt $now.AddSeconds(-5) -Now $now).Allowed | Should -BeFalse
        (Test-LtSetupInventoryRefresh -LastAttempt $now.AddMinutes(-11) -Now $now).Allowed | Should -BeTrue
        $f = Test-LtSetupInventoryRefresh -LastAttempt $now.AddSeconds(-10) -Now $now -Force
        $f.Allowed | Should -BeFalse
        $f.WaitSeconds | Should -Be 20
        (Test-LtSetupInventoryRefresh -LastAttempt $now.AddSeconds(-31) -Now $now -Force).Allowed | Should -BeTrue
        (Test-LtSetupInventoryRefresh -Now $now -Force -Running).Allowed | Should -BeFalse
    }

    It 'Envanter kurulum davranışını değiştirmez: kurulumda exact kimlik, winget kaynağı ve no-upgrade korunur' {
        $src = Get-Content (Join-Path $script:RepoRoot 'src/Core/SideEffects.ps1') -Raw
        $src | Should -Match "'install','--id',\`$item.Id,'--exact','--source','winget','--no-upgrade'"
        $src | Should -Not -Match "'upgrade'"
    }
}

Describe 'Envanter arayüzü (gerçek ikincil runspace, sahte denetimler)' {
    BeforeAll {
        $src = Join-Path $script:RepoRoot 'src/UI'
        . (Join-Path $src 'ViewModels.ps1')
        . (Join-Path $src 'Dialogs.ps1')
        . (Join-Path $src 'App.ps1')
        Initialize-LtViewModels

        function New-FakeSetupControl {
            $o = [pscustomobject]@{ Text = ''; Content = ''; IsEnabled = $true; IsChecked = $false; ItemsSource = $null; SelectedItem = $null; SelectedIndex = -1; SelectedItems = (New-Object System.Collections.ArrayList); Visibility = 'Visible'; Value = 0; IsIndeterminate = $false }
            foreach ($ev in @('Add_SelectionChanged', 'Add_TextChanged', 'Add_Click')) { $o | Add-Member -MemberType ScriptMethod -Name $ev -Value { param($h) } }
            $o | Add-Member -MemberType ScriptMethod -Name AppendText -Value { param($t) $this.Text += $t }
            $o | Add-Member -MemberType ScriptMethod -Name ScrollToEnd -Value { }
            return $o
        }
        function Wait-LtSideJob([int]$TimeoutSec = 60) {
            $deadline = (Get-Date).AddSeconds($TimeoutSec)
            while ($script:Ui.SideJob -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 100; Complete-LtSideJobIfDone }
            if ($script:Ui.SideJob) { throw 'Envanter işi zaman aşımına uğradı.' }
        }
        function Wait-LtMainJob([int]$TimeoutSec = 60) {
            $deadline = (Get-Date).AddSeconds($TimeoutSec)
            while ($script:Ui.Job -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 100; Complete-LtJobIfDone }
        }
        $script:DialogLog = New-Object System.Collections.ArrayList
        function Show-LtReportDialog { param($Owner, $Title, $Head, $Intro, $Rows, $Mode, $OkText, [switch]$ShowRestorePoint, $RestorePointDefault, [switch]$RequireConsent, $Foot, $OkEnabled)
            [void]$script:DialogLog.Add([pscustomobject]@{ Title = $Title; Head = $Head; Rows = @($Rows) })
            return @{ Confirmed = $false } }
    }
    BeforeEach {
        $sys = New-LtTestSystem
        $queue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
        Initialize-LivnTools -DataRoot $sys.Root -Backend Memory -LogQueue $queue
        $controls = @{}
        foreach ($n in @('SetupAppList', 'TxtSetupSearch', 'CmbSetupCategory', 'ChkSetupSelected', 'BtnSetupClear', 'BtnSetupInventory', 'TxtSetupInventory', 'TxtSetupSelection',
                         'TxtStatus', 'LogBox', 'ProgressPanel', 'BtnCancel', 'TxtProgress', 'ProgMain', 'SetupRemoveList', 'TxtSetupResults')) { $controls[$n] = New-FakeSetupControl }
        $script:Ui = @{
            Window = $null; C = $controls; LogQueue = $queue; DataRoot = (Get-LtDataRoot); AppRoot = $script:RepoRoot
            ModulePath = (Join-Path $script:RepoRoot 'src/LivnTools.psm1'); Job = $null; SideJob = $null; WorkerRS = $null; Ctx = $sys.Ctx
            RefreshQueue = (New-Object System.Collections.ArrayList); Cleanups = @{}; CleanupGroups = @{}
        }
        Initialize-LtSetupView
    }
    AfterEach {
        if ($script:Ui.SideJob) { Wait-LtSideJob }
        if ($script:Ui.WorkerRS) { $script:Ui.WorkerRS.Dispose() }
        Remove-LtTestSystem $sys
    }

    It 'Başlangıçta durum "henüz okunmadı"; envanter arka planda okunur ve satırlara yazılır' {
        ($script:Ui.SetupApps | Where-Object Id -eq 'Mozilla.Firefox').StateText | Should -Be 'Durum henüz okunmadı'
        Request-LtSetupInventory | Should -BeTrue
        $controls.TxtSetupInventory.Text | Should -Match 'okunuyor'
        $controls.BtnSetupInventory.IsEnabled | Should -BeFalse
        Wait-LtSideJob
        ($script:Ui.SetupApps | Where-Object Id -eq 'Mozilla.Firefox').State | Should -Be 'Installed'
        ($script:Ui.SetupApps | Where-Object Id -eq 'Brave.Brave').StateText | Should -Be 'Kurulu değil'
        ($script:Ui.SetupApps | Where-Object Id -eq 'Google.Chrome').StateText | Should -Be 'Kurulu (WinGet dışı)'
        $controls.TxtSetupInventory.Text | Should -Match 'Kurulu: 5 \(2 tanesi WinGet dışı kurulum\)'
        $controls.TxtSetupInventory.Text | Should -Match 'deneme envanteri'
        $controls.BtnSetupInventory.IsEnabled | Should -BeTrue
    }

    It 'Arama, kategori, gizli seçimler ve kurulum sepeti envanter sonrası korunur' {
        Set-LtSetupPackageSelection -Ids @('Valve.Steam', 'Google.Chrome')
        $controls.TxtSetupSearch.Text = 'chrome'
        Update-LtSetupAppsView
        @($controls.SetupAppList.ItemsSource).Count | Should -Be 1
        [void](Request-LtSetupInventory)
        Wait-LtSideJob
        @($script:Ui.SetupSelected.Keys | Sort-Object) | Should -Be @('Google.Chrome', 'Valve.Steam')
        $controls.TxtSetupSearch.Text | Should -Be 'chrome'
        @($controls.SetupAppList.ItemsSource).Count | Should -Be 1
        @($controls.SetupAppList.SelectedItems).Count | Should -Be 1
        $controls.TxtSetupSelection.Text | Should -Match 'Filtre dışında seçili: 1'
        @(Get-LtChosenSetupApps).Count | Should -Be 2
    }

    It 'Otomatik yenileme sınırlıdır; elle yenileme 30 saniyeden önce reddedilir ve nedeni gösterilir' {
        [void](Request-LtSetupInventory); Wait-LtSideJob
        Request-LtSetupInventory | Should -BeFalse
        Request-LtSetupInventory -Force | Should -BeFalse
        $controls.TxtStatus.Text | Should -Match 'sn sonra'
        $script:Ui.SetupInventory.LastAttempt = (Get-Date).AddSeconds(-31)
        Request-LtSetupInventory -Force | Should -BeTrue
        Wait-LtSideJob
    }

    It 'Hata açıkça gösterilir, satırlar "durum okunamadı" olur ve yeniden deneme başarılı olabilir' {
        $sys.Mem.Faults['Winget.Inventory:export'] = 'Ağ hatası'
        [void](Request-LtSetupInventory); Wait-LtSideJob
        $script:Ui.SetupInventory.Result.Status | Should -Be 'Error'
        @($script:Ui.SetupApps | Where-Object { $_.State -ne 'Unknown' } | ForEach-Object { $_.Id } | Sort-Object) | Should -Be @('Discord.Discord', 'Google.Chrome', 'Valve.Steam')
        @($script:Ui.SetupApps | Where-Object { $_.State -eq 'NotInstalled' }).Count | Should -Be 0
        $controls.TxtSetupInventory.Text | Should -Match 'WinGet durumu okunamadı'
        $controls.TxtSetupInventory.Text | Should -Match 'diğerlerinin durumu bilinmiyor'
        $controls.BtnSetupInventory.Content | Should -Be 'Yeniden dene'
        $sys.Mem.Faults.Remove('Winget.Inventory:export')
        $script:Ui.SetupInventory.LastAttempt = (Get-Date).AddMinutes(-1)
        Request-LtSetupInventory -Force | Should -BeTrue
        Wait-LtSideJob
        $script:Ui.SetupInventory.Result.Status | Should -Be 'Ok'
        $controls.BtnSetupInventory.Content | Should -Be 'Kurulum durumunu yenile'
    }

    It 'WinGet yoksa kurulu değil denmez' {
        $sys.Mem.Setup.WingetAvailable = $false
        [void](Request-LtSetupInventory); Wait-LtSideJob
        @($script:Ui.SetupApps | Where-Object { $_.StateText -eq 'Kurulu değil' }).Count | Should -Be 0
        $controls.TxtSetupInventory.Text | Should -Match 'WinGet'
    }

    It 'Ana iş kuyruğu meşgulken envanter ayrı çalışır ve onu bloklamaz' {
        [void](Start-LtJob -Title 'uzun ayar işi' -Body { param($a, $p, $c) Start-Sleep -Milliseconds 1500; @{ ok = 1 } })
        $script:Ui.Job | Should -Not -BeNullOrEmpty
        Request-LtSetupInventory | Should -BeTrue
        Wait-LtSideJob
        $script:Ui.SetupInventory.Result.Status | Should -Be 'Ok'
        $script:Ui.Job | Should -Not -BeNullOrEmpty -Because 'ana iş hâlâ sürüyor olmalı'
        Wait-LtMainJob
    }

    It 'Kurulum sürerken envanter başlatılmaz, bekletilir' {
        $script:Ui.Job = @{ Title = 'Uygulama işlemleri' }
        try { Request-LtSetupInventory -Force | Should -BeFalse; $script:Ui.SetupInventory.Pending | Should -BeTrue }
        finally { $script:Ui.Job = $null }
        $script:Ui.SideJob | Should -BeNullOrEmpty
    }

    It 'Kurulum onayında kurulu görünen uygulama "yükseltilmez" olarak işaretlenir' {
        [void](Request-LtSetupInventory); Wait-LtSideJob
        Set-LtSetupPackageSelection -Ids @('Mozilla.Firefox', 'Google.Chrome', 'Brave.Brave')
        $script:DialogLog.Clear()
        Invoke-LtSetupUiAction -Mode Install
        $rows = @($script:DialogLog[0].Rows)
        ($rows | Where-Object Title -eq 'Firefox').KindText | Should -Be 'Kurulu görünüyor'
        ($rows | Where-Object Title -eq 'Firefox').Message | Should -Match 'yükseltilmez'
        ($rows | Where-Object Title -eq 'Google Chrome').KindText | Should -Be 'Kurulu görünüyor' -Because 'WinGet dışı kurulum da yeniden kurulmaz'
        ($rows | Where-Object Title -eq 'Brave').KindText | Should -Be 'Simüle et'
        $script:Ui.Job | Should -BeNullOrEmpty -Because 'onay verilmedi'
    }
}
