#Requires -Modules Pester
# Arayuz MANTIGI (WPF olmadan): gorunum modelleri derlenir, arka plan is hatti
# (kalici runspace, modul yukleme, gunluk kuyrugu, ilerleme) gercekten calistirilir.
# WPF pencereleri sahte denetimlerle degistirilir; Windows'ta gorsel dogrulama
# docs/WINDOWS_TEST_CHECKLIST.md ile yapilir.

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $src = Join-Path $script:RepoRoot 'src/UI'
    . (Join-Path $src 'ViewModels.ps1')
    . (Join-Path $src 'Dialogs.ps1')
    . (Join-Path $src 'App.ps1')
    Initialize-LtViewModels

    function New-FakeControl {
        $o = [pscustomobject]@{ Text = ''; Visibility = 'Visible'; IsEnabled = $true; Content = ''; Value = 0; IsIndeterminate = $false; ItemsSource = $null; Margin = $null; SelectedItems = @(); IsChecked = $false; SelectedIndex = 0 }
        $o | Add-Member -MemberType ScriptMethod -Name AppendText -Value { param($t) $this.Text += $t }
        $o | Add-Member -MemberType ScriptMethod -Name ScrollToEnd -Value { }
        $o | Add-Member -MemberType ScriptMethod -Name ScrollToTop -Value { }
        $o | Add-Member -MemberType ScriptMethod -Name Clear -Value { $this.Text = '' }
        return $o
    }

    function Wait-LtJobs([int]$TimeoutSec = 60) {
        $deadline = (Get-Date).AddSeconds($TimeoutSec)
        while (($script:Ui.Job -or $script:Ui.RefreshQueue.Count -gt 0) -and (Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 100
            $item = $null
            while ($script:Ui.LogQueue.TryDequeue([ref]$item)) { Add-LtLogLine $item.Line }
            Complete-LtJobIfDone
        }
        if ($script:Ui.Job) { throw 'Arka plan işi zaman aşımına uğradı.' }
    }

    $sys = New-LtTestSystem
    $queue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
    Initialize-LivnTools -DataRoot $sys.Root -Backend Memory -LogQueue $queue
    $controls = @{}
    foreach ($n in @('TxtStatus', 'LogBox', 'ProgressPanel', 'BtnCancel', 'TxtProgress', 'ProgMain', 'TxtPageInfo', 'BadgeRestart', 'LedgerList', 'OpsList',
                     'BtnApply', 'BtnRevertPrev', 'BtnRevertDefault', 'BtnBackupState', 'BtnRefresh', 'BtnRunCleanup', 'BtnApplyAllPages',
                     'BtnPresetMinimal', 'BtnPresetStandard', 'BtnPresetAggressive', 'BtnPresetClear', 'BtnRecoveryRevert', 'BtnRecoveryKeep',
                     'BtnHistoryRevert', 'BtnHistoryRestoreFile', 'BtnHistoryLegacyReg', 'BtnScriptRun', 'RecoveryBanner', 'TxtRecovery')) { $controls[$n] = New-FakeControl }
    $script:Ui = @{
        Window = $null; C = $controls; LogQueue = $queue; DataRoot = (Get-LtDataRoot); AppRoot = $script:RepoRoot
        ModulePath = (Join-Path $script:RepoRoot 'src/LivnTools.psm1')
        Job = $null; WorkerRS = $null; Ctx = $sys.Ctx; CurrentPage = 'Performance'; StateLoaded = @{}; RefreshQueue = (New-Object System.Collections.ArrayList)
        Tweaks = @{}; TweakGroups = @{}; Cleanups = @{}; CleanupGroups = @{}; CleanupInit = $false
        PendingRestart = $false; ActivePlan = ''; RecoveryOp = $null; NativeOk = $false; PendingMode = ''
    }
    New-LtTweakItems
    New-LtCleanupItems

    # WPF diyaloglarinin yerine gecenler (onay otomatik verilir)
    $script:DialogLog = New-Object System.Collections.ArrayList
    function Show-LtReportDialog { param($Owner, $Title, $Head, $Intro, $Rows, $Mode, $OkText, [switch]$ShowRestorePoint, $RestorePointDefault, [switch]$RequireConsent, $Foot, $OkEnabled)
        [void]$script:DialogLog.Add([pscustomobject]@{ Title = $Title; Head = $Head; Rows = @($Rows); Mode = $Mode; RequireConsent = [bool]$RequireConsent })
        return @{ Confirmed = $true; RestorePoint = $true } }
    $script:MsgAnswer = 'No'
    $script:MsgLog = New-Object System.Collections.ArrayList
    function Show-LtMessage { param($Owner, $Text, $Caption, $Buttons, $Icon) [void]$script:MsgLog.Add($Text); return $script:MsgAnswer }
}
AfterAll {
    if ($script:Ui.WorkerRS) { $script:Ui.WorkerRS.Dispose() }
    Remove-LtTestSystem $sys
}

Describe 'Gorunum modelleri' {
    It 'Her katalog ayari icin bir satir ve dogru sayfa gruplari olusur' {
        $script:Ui.Tweaks.Count | Should -Be @(Get-LtCatalog).Count
        foreach ($p in $script:LtOptPages) { $script:Ui.TweakGroups[$p].Count | Should -BeGreaterThan 0 -Because $p }
    }
    It 'Ozel gruptan ikinci secim birinciyi kaldirir (guc plani)' {
        $script:Ui.Tweaks['power.bitsum'].Selected = $true
        $script:Ui.Tweaks['power.ultimate'].Selected = $true
        $script:Ui.Tweaks['power.bitsum'].Selected | Should -BeFalse
        $script:Ui.Tweaks['power.ultimate'].Selected = $false
    }
}

Describe 'Arka plan is hatti (gercek runspace)' {
    It 'Durum okuma arka planda calisir, ana gorunum modelini gunceller ve gunluge yazar' {
        Update-LtPageState -Page 'Performance'
        Wait-LtJobs
        $vm = $script:Ui.Tweaks['timer.platformclock-default']
        $vm.StateKind | Should -Be 'Partial' -Because 'sahte sistemde useplatformclock=Yes, useplatformtick yok'
        $vm.Details | Should -Match 'useplatformclock'
        $script:Ui.Tweaks['power.balanced'].StateKind | Should -Be 'Applied'
        $script:Ui.StateLoaded['Performance'] | Should -BeTrue
    }

    It 'Onizle -> onay -> uygula akisi motoru arka planda calistirir ve sonucu satirlara yazar' {
        $script:DialogLog.Clear()
        Invoke-LtTweakFlow -Ids @('timer.platformclock-default', 'game.mode') -Mode Apply
        Wait-LtJobs
        (Get-LtBcdElement 'useplatformclock') | Should -Be 'Absent'
        $script:Ui.Tweaks['game.mode'].LastResultKind | Should -Be 'Success'
        $script:DialogLog[0].Title | Should -Be 'Önizleme'
        @($script:DialogLog[0].Rows | Where-Object Kind -eq 'WillChange').Count | Should -Be 2
        $script:DialogLog[1].Title | Should -Be 'Sonuç'
        $script:Ui.PendingRestart | Should -BeTrue -Because 'BCD degisikligi yeniden baslatma gerektirir'
        $script:Ui.C.LogBox.Text | Should -Match 'Geri yükleme noktası'
    }

    It 'Guvenlik ayari onizlemesi acik onay ister' {
        $script:DialogLog.Clear()
        Invoke-LtTweakFlow -Ids @('sec.spectre-off') -Mode Apply
        Wait-LtJobs
        $script:DialogLog[0].RequireConsent | Should -BeTrue
    }

    It 'Onceki ayara donus akisi calisir' {
        Invoke-LtTweakFlow -Ids @('timer.platformclock-default', 'sec.spectre-off') -Mode RevertPrevious
        Wait-LtJobs
        (Get-LtBcdElement 'useplatformclock') | Should -Be 'Yes'
        (Get-LtRegValue 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'FeatureSettingsOverride').Exists | Should -BeFalse
    }

    It 'Mesgulken ikinci is baslatilmaz' {
        [void](Start-LtJob -Title 'uzun' -Body { param($a, $p, $c) Start-Sleep -Milliseconds 800; @{ ok = 1 } })
        (Start-LtJob -Title 'ikinci' -Body { param($a, $p, $c) 1 }) | Should -BeFalse
        Wait-LtJobs
    }

    It 'Arka plan istisnasi yakalanir ve gunluge yazilir' {
        $script:gotErr = $null
        [void](Start-LtJob -Title 'hatali' -Body { param($a, $p, $c) throw 'Test hatası' } -OnDone { param($r, $e) $script:gotErr = @($e) })
        Wait-LtJobs
        ($script:gotErr -join ' ') | Should -Match 'Test hatası'
        $script:Ui.C.LogBox.Text | Should -Match 'Test hatası'
    }

    It 'Hazir secim guvenlik ayari secmez' {
        $presets = Get-LtPresets
        foreach ($t in $script:Ui.Tweaks.Values) { $t.Selected = $false }
        foreach ($id in $presets.Aggressive.Ids) { $script:Ui.Tweaks[$id].Selected = $true }
        @($script:Ui.Tweaks.Values | Where-Object { $_.Selected -and $_.Risk -eq 'Security' }).Count | Should -Be 0
    }

    It 'Gecmis listesi ledger ve journal kayitlarini gosterir' {
        Invoke-LtTweakFlow -Ids @('ui.show-ext') -Mode Apply
        Wait-LtJobs
        Update-LtHistory
        @($script:Ui.C.LedgerList.ItemsSource | Where-Object { $_.TweakIds -contains 'ui.show-ext' }).Count | Should -Be 1
        @($script:Ui.C.OpsList.ItemsSource).Count | Should -BeGreaterThan 2
    }
}

Describe 'Kuru çalışma: arayüz akışları gerçek sisteme dokunmaz (gerçek arka plan runspace)' {
    BeforeAll {
        # Ayrılmış geçici klasör; katalog ortam değişkenleri buraya yönlendirilir (arka plan
        # runspace'i aynı süreçte olduğu için yönlendirmeyi o da görür).
        $can = Join-Path ([IO.Path]::GetTempPath()) ('lt-canary-' + [guid]::NewGuid().ToString('N'))
        $envNames = @('TEMP', 'TMP', 'LOCALAPPDATA', 'APPDATA', 'SystemRoot')
        $saved = @{}
        foreach ($n in $envNames) { $saved[$n] = [Environment]::GetEnvironmentVariable($n); [void](New-Item -ItemType Directory -Path (Join-Path $can $n) -Force) }
        $files = @((Join-Path $can 'TEMP/k.tmp'), (Join-Path $can 'LOCALAPPDATA/Google/Chrome/User Data/Default/Cache/c.bin'), (Join-Path $can 'SystemRoot/Temp/s.tmp'))
        foreach ($f in $files) { [void](New-Item -ItemType Directory -Path (Split-Path -Parent $f) -Force); [IO.File]::WriteAllText($f, 'kanarya') }
        foreach ($n in $envNames) { [Environment]::SetEnvironmentVariable($n, (Join-Path $can $n)) }
        # Sahte sistem: Chrome kurulu ve AÇIK (pencereli)
        $mem = Get-LtMemoryState
        $mem.Processes = @(@{ Name = 'chrome'; HasWindow = $true })
        [void](Set-LtRegValue 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\T-Chrome' 'DisplayName' -Kind String -Data 'Google Chrome')
        $callsBefore = @($mem.Calls).Count
    }
    AfterAll {
        foreach ($n in $envNames) { [Environment]::SetEnvironmentVariable($n, $saved[$n]) }
        $script:MsgAnswer = 'No'
        if ((Split-Path -Leaf $can).StartsWith('lt-canary-')) { Remove-Item -LiteralPath $can -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'Temizlik akışı: "uygulamayı kapat" onaylansa bile hiçbir dosya silinmez, süreç kapatılmaz, komut çalışmaz' {
        Update-LtCleanupAvailability
        foreach ($vm in $script:Ui.Cleanups.Values) { $vm.Selected = $false }
        foreach ($id in @('clean.temp-user', 'clean.temp-system', 'clean.chrome', 'clean.recyclebin', 'clean.dns', 'clean.eventlogs', 'clean.deliveryopt')) {
            $script:Ui.Cleanups[$id].IsAvailable | Should -BeTrue -Because $id
            $script:Ui.Cleanups[$id].Selected = $true
        }
        $script:DialogLog.Clear(); $script:MsgLog.Clear()
        $script:MsgAnswer = 'Yes'
        Invoke-LtCleanupFlow -Page 'QuickClean'
        Wait-LtJobs
        $script:MsgAnswer = 'No'

        ($script:MsgLog -join ' ') | Should -Match 'Chrome' -Because 'sahte açık Chrome için kapatma sorusu soruldu'
        $script:DialogLog[0].Head | Should -Match 'KURU ÇALIŞMA'
        $script:DialogLog[1].Head | Should -Match 'Kuru çalışma: 7 işlem simüle edildi'
        foreach ($id in @('clean.temp-user', 'clean.chrome', 'clean.recyclebin', 'clean.dns')) {
            $script:Ui.Cleanups[$id].LastResult | Should -Match 'simüle' -Because $id
        }
        foreach ($f in $files) { Test-Path -LiteralPath $f | Should -BeTrue -Because $f }
        $mem = Get-LtMemoryState
        @($mem.Processes | Where-Object { $_.Name -eq 'chrome' }).Count | Should -Be 1 -Because 'sahte Chrome bile kapatılmadı'
        $newCalls = @($mem.Calls)[$callsBefore..(@($mem.Calls).Count - 1)]
        @($newCalls | Where-Object { $_ -like 'Process.*' -or $_ -like 'Service.*' -or $_ -like 'Registry.Set*' }).Count | Should -Be 0
        $script:Ui.C.LogBox.Text | Should -Match 'KURU ÇALIŞMA'
    }

    It 'Betik akışı: onay sorulmadan reddedilir, arka plan işi başlamaz, betik çalışmaz' {
        $marker = Join-Path $can 'betik-calisti.txt'
        $script:Ui.C.ScriptEditor = [pscustomobject]@{ Text = "Set-Content -LiteralPath '$marker' -Value x" }
        $script:Ui.C.CmbScriptKind = [pscustomobject]@{ SelectedIndex = 0 }
        $script:MsgLog.Clear()
        $script:MsgAnswer = 'Yes'
        Invoke-LtScriptFlow
        $script:MsgAnswer = 'No'
        $script:Ui.Job | Should -BeNullOrEmpty
        $script:MsgLog.Count | Should -Be 0
        $script:Ui.C.TxtStatus.Text | Should -Match 'Kuru çalışma'
        Start-Sleep -Milliseconds 300
        Test-Path -LiteralPath $marker | Should -BeFalse
    }

    It 'Betik gövdesi arka plan işine doğrudan verilse bile motor reddeder' {
        $marker = Join-Path $can 'betik-dogrudan.txt'
        $script:gotErr = $null
        [void](Start-LtJob -Title 'dogrudan' -Body { param($a, $p, $c) Invoke-LtUserScript -Code $a.Code -Kind PowerShell } -JobArgs @{ Code = "Set-Content -LiteralPath '$marker' -Value x" } -OnDone { param($r, $e) $script:gotErr = @($e) })
        Wait-LtJobs
        ($script:gotErr -join ' ') | Should -Match 'KURU ÇALIŞMA'
        Test-Path -LiteralPath $marker | Should -BeFalse
    }

    It 'Explorer yeniden başlatılmaz' {
        Restart-LtExplorer
        $script:Ui.C.LogBox.Text | Should -Match 'Explorer yeniden başlatılmadı'
        { Restart-LtExplorerShell } | Should -Throw '*KURU ÇALIŞMA*'
    }
}
