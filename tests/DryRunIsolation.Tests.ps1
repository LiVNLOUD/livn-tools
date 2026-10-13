#Requires -Modules Pester
# KURU ÇALIŞMA (bellek arka ucu) YALITIMI — regresyon testleri.
#
# Kanıtlanan: Memory/DryRun modunda temizlik, bakım, kullanıcı betiği, .reg içe aktarma,
# Explorer yeniden başlatma ve ayar motoru GERÇEK sisteme yan etki üretmez; koruma
# arayüz düğmesinde değil motorun alt katmanındadır (doğrudan çağrılar da reddedilir).
#
# GÜVENLİK: Gerçek dosya yalnızca bu testlerin oluşturduğu, sistemin geçici klasörü
# altındaki 'lt-canary-*' / 'lt-sandbox-*' klasörlerinde yaratılır ve silinir. Yan etkili
# cmdlet'ler modül kapsamında taklit edilir (mock) — koruma bozulsa bile test makinesinde
# Geri Dönüşüm Kutusu boşaltılmaz, süreç kapatılmaz, araç başlatılmaz.

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')

    # Katalogdaki yolların kök aldığı ortam değişkenleri
    $script:CanaryEnvNames = @('TEMP', 'TMP', 'LOCALAPPDATA', 'APPDATA', 'SystemRoot', 'USERPROFILE', 'ProgramData', 'ProgramFiles', 'ProgramFiles(x86)')
    # Kuru çalışmada ASLA çağrılmaması gereken yan etkili komutlar (bu sistemde varsa taklit edilir)
    $script:SideEffectCmdlets = @('Stop-Process', 'Start-Process', 'Remove-Item', 'Clear-RecycleBin', 'Get-Process', 'Get-PnpDevice',
        'Invoke-CimMethod', 'Stop-Service', 'Start-Service', 'Set-NetAdapterAdvancedProperty', 'Set-ProcessMitigation',
        'Register-ScheduledTask', 'Unregister-ScheduledTask', 'Delete-DeliveryOptimizationCache')

    function New-LtCanary {
        <#
          Ayrılmış geçici klasör + katalog yollarında gerçek "kanarya" dosyalar.
          -RedirectEnv: katalogdaki ortam değişkenleri bu klasöre yönlendirilir.
        #>
        param([switch]$RedirectEnv)
        $root = Join-Path ([IO.Path]::GetTempPath()) ('lt-canary-' + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $root)
        $saved = @{}
        $base = @{}
        foreach ($n in $script:CanaryEnvNames) {
            $saved[$n] = [Environment]::GetEnvironmentVariable($n)
            $base[$n] = Join-Path $root ($n -replace '[()]', '')
            [void](New-Item -ItemType Directory -Path $base[$n] -Force)
        }
        $rel = @(
            @('TEMP', 'kullanici.tmp'), @('SystemRoot', 'Temp/sistem.tmp'), @('SystemRoot', 'Prefetch/APP.pf'), @('SystemRoot', 'MEMORY.DMP'),
            @('SystemRoot', 'Minidump/m.dmp'), @('SystemRoot', 'SoftwareDistribution/Download/u.cab'),
            @('SystemRoot', 'ServiceProfiles/LocalService/AppData/Local/FontCache/f.dat'),
            @('LOCALAPPDATA', 'Google/Chrome/User Data/Default/Cache/c.bin'), @('LOCALAPPDATA', 'Microsoft/Edge/User Data/Default/Cache/e.bin'),
            @('LOCALAPPDATA', 'Microsoft/Windows/Explorer/thumbcache_1.db'), @('LOCALAPPDATA', 'CrashDumps/x.dmp'),
            @('LOCALAPPDATA', 'Steam/htmlcache/s.bin'), @('APPDATA', 'discord/Cache/d.bin'))
        $files = New-Object System.Collections.ArrayList
        foreach ($r in $rel) {
            $f = Join-Path $base[$r[0]] $r[1]
            [void](New-Item -ItemType Directory -Path (Split-Path -Parent $f) -Force)
            [IO.File]::WriteAllText($f, ('kanarya-' * 64))
            [void]$files.Add($f)
        }
        if ($RedirectEnv) { foreach ($n in $script:CanaryEnvNames) { [Environment]::SetEnvironmentVariable($n, $base[$n]) } }
        return [pscustomobject]@{ Root = $root; Files = @($files); Saved = $saved; Base = $base; Redirected = [bool]$RedirectEnv }
    }

    function Remove-LtCanary($Canary) {
        if (-not $Canary) { return }
        if ($Canary.Redirected) { foreach ($n in $script:CanaryEnvNames) { [Environment]::SetEnvironmentVariable($n, $Canary.Saved[$n]) } }
        if ($Canary.Root -and (Split-Path -Leaf $Canary.Root).StartsWith('lt-canary-')) { Remove-Item -LiteralPath $Canary.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    # Remove-Item: kuru çalışmanın KENDİ veri klasöründeki journal/ledger geçici dosyaları serbest;
    # bunun dışındaki her silme yan etkidir.
    $script:MockFilter = @{
        'Remove-Item' = { -not ("$LiteralPath$Path").StartsWith((Get-LtDataRoot)) }
    }

    function Register-LtSideEffectMocks {
        # Modül kapsamında: çağrılırsa test başarısız olur ve gerçek işlem yapılmaz
        $script:MockedCmdlets = New-Object System.Collections.ArrayList
        foreach ($c in $script:SideEffectCmdlets) {
            if (Get-Command -Name $c -ErrorAction SilentlyContinue) {
                if ($script:MockFilter.ContainsKey($c)) {
                    Mock -ModuleName LivnTools -CommandName $c -ParameterFilter $script:MockFilter[$c] -MockWith { throw 'YAN ETKİ: taklit edilen komut çağrıldı' }
                } else {
                    Mock -ModuleName LivnTools -CommandName $c -MockWith { throw 'YAN ETKİ: taklit edilen komut çağrıldı' }
                }
                [void]$script:MockedCmdlets.Add($c)
            }
        }
    }

    function Assert-LtNoSideEffectCalls {
        foreach ($c in $script:MockedCmdlets) {
            if ($script:MockFilter.ContainsKey($c)) {
                Should -Invoke -ModuleName LivnTools -CommandName $c -ParameterFilter $script:MockFilter[$c] -Times 0 -Exactly -Scope It
            } else {
                Should -Invoke -ModuleName LivnTools -CommandName $c -Times 0 -Exactly -Scope It
            }
        }
    }
}

Describe 'Kuru çalışma: temizlik motoru (arayüz olmadan, doğrudan çağrı)' {
    BeforeEach {
        $sys = New-LtTestSystem
        Clear-LtBlockedOperations
        Register-LtSideEffectMocks
        Mock -ModuleName LivnTools -CommandName Invoke-LtNative -MockWith { throw 'YAN ETKİ: Invoke-LtNative' }
        Mock -ModuleName LivnTools -CommandName Remove-LtFolderContents -MockWith { throw 'YAN ETKİ: Remove-LtFolderContents' }
        $can = New-LtCanary -RedirectEnv
    }
    AfterEach {
        Remove-LtCanary $can
        Remove-LtTestSystem $sys
    }

    It 'Tüm katalog (uygulama kapatma izniyle): dosya silinmez, süreç kapatılmaz, komut çalışmaz' {
        $ids = @(Get-LtCleanupCatalog -Refresh | ForEach-Object { $_.Id })
        $r = Invoke-LtCleanup -Ids $ids -Context $sys.Ctx -CloseAppIds $ids

        @($r.Results).Count | Should -Be $ids.Count
        foreach ($x in $r.Results) {
            $ok = ($x.Status -eq 'Skipped' -and $x.Simulated) -or $x.Status -eq 'NotSupported'
            $ok | Should -BeTrue -Because "$($x.Id): $($x.Status) — $($x.Message)"
            $x.BytesFreed | Should -Be 0
        }
        # Kurulu (sahte) ve açık (sahte) Chrome dahil gerçekten simüle edildi
        ($r.Results | Where-Object Id -eq 'clean.chrome').Simulated | Should -BeTrue
        ($r.Results | Where-Object Id -eq 'clean.temp-user').Simulated | Should -BeTrue
        ($r.Results | Where-Object Id -eq 'adv.sfc').Simulated | Should -BeTrue
        ($r.Results | Where-Object Id -eq 'net.stack-reset').Simulated | Should -BeTrue

        foreach ($f in $can.Files) { Test-Path -LiteralPath $f | Should -BeTrue -Because $f }
        @(Get-LtBlockedOperations).Count | Should -Be 0 -Because 'hiçbir yan etki kapıya kadar bile ulaşmamalı'
        Should -Invoke -ModuleName LivnTools -CommandName Invoke-LtNative -Times 0 -Exactly
        Should -Invoke -ModuleName LivnTools -CommandName Remove-LtFolderContents -Times 0 -Exactly
        Assert-LtNoSideEffectCalls
        $calls = @((Get-LtMemoryState).Calls)
        @($calls | Where-Object { $_ -like 'Process.Stop|*' -or $_ -like 'Service.Stop|*' -or $_ -like 'Service.Start|*' -or $_ -like 'Registry.Set|*VolumeCaches*' }).Count | Should -Be 0
        @((Get-LtMemoryState).Processes | Where-Object { $_.Name -eq 'chrome' }).Count | Should -Be 1 -Because 'sahte Chrome bile kapatılmadı'
    }

    It 'Tek öğe: Paths, Run ve süreç listesi hiç değerlendirilmez' {
        $global:LtProbe = @{ Paths = 0; Run = 0 }
        $item = @{ Id = 't.probe'; Title = 'probe'; Processes = @('chrome')
                   Paths = { $global:LtProbe.Paths++; @(@{ Path = $env:TEMP; Label = 'x' }) }
                   Run = { param($ctx, $cancel) $global:LtProbe.Run++; @{ Bytes = 1 } } }
        try {
            $r = Invoke-LtCleanupItem -Item $item -Context $sys.Ctx -CloseApps
            $r.Status | Should -Be 'Skipped'
            $r.Simulated | Should -BeTrue
            $r.Message | Should -Match 'Kuru çalışma'
            $global:LtProbe.Paths | Should -Be 0
            $global:LtProbe.Run | Should -Be 0
            Test-Path -LiteralPath (Join-Path $env:TEMP 'kullanici.tmp') | Should -BeTrue
        } finally { Remove-Variable -Name LtProbe -Scope Global -ErrorAction SilentlyContinue }
    }

    It 'Uygulama tespiti gerçek dosya sistemini ve gerçek süreç listesini yoklamaz' {
        $it = @{ Id = 't.det'; Title = 'det'; Processes = @('pwsh', 'powershell'); Detect = @{ Names = @('Yok'); Paths = @($can.Root) } }
        (Get-LtCleanupAvailability $it $sys.Ctx) | Should -Match 'bulunamadı' -Because 'var olan gerçek klasör kuru çalışmada sayılmaz'
        @(Get-LtRunningProcessesFor $it).Count | Should -Be 0 -Because 'bu test pwsh içinde çalışıyor; gerçek süreç listesi okunmamalı'
    }
}

Describe 'Kuru çalışma: yan etki ilkelleri doğrudan çağrıldığında reddedilir' {
    BeforeEach {
        $sys = New-LtTestSystem
        Clear-LtBlockedOperations
        $can = New-LtCanary
        $marker = Join-Path $can.Root 'marker.txt'
        # Koruma bozulsa bile test makinesine dokunulmasın diye yalnızca tehlikeli cmdlet'ler taklit edilir.
        # Invoke-LtNative TAKLİT EDİLMEZ: gerçek (zararsız) bir sürecin başlatılmadığı işaret dosyasıyla kanıtlanır.
        Register-LtSideEffectMocks
        Mock -ModuleName LivnTools -CommandName Get-Command -ParameterFilter { $Name -like '*DeliveryOptimization*' } -MockWith { throw 'YAN ETKİ: Get-Command DO' }
    }
    AfterEach {
        Remove-LtCanary $can
        Remove-LtTestSystem $sys
    }

    It 'Invoke-LtNative gerçek süreç başlatmaz (işaret dosyası oluşmaz)' {
        if ($IsWindows -eq $false) { $exe = '/bin/sh'; $cmdArgs = @('-c', "echo x > '$marker'") }
        else { $exe = "$env:SystemRoot\System32\cmd.exe"; $cmdArgs = @('/d', '/c', "echo x > `"$marker`"") }
        { Invoke-LtNative -FilePath $exe -Arguments $cmdArgs } | Should -Throw '*KURU ÇALIŞMA*'
        { Invoke-LtNativeChecked -FilePath $exe -Arguments $cmdArgs } | Should -Throw '*KURU ÇALIŞMA*'
        Start-Sleep -Milliseconds 300
        Test-Path -LiteralPath $marker | Should -BeFalse
        @(Get-LtBlockedOperations).Count | Should -Be 2
    }

    It 'Remove-LtFolderContents ve Remove-LtFileSafe gerçek dosya silmez (test kökü yokken)' {
        $dir = Split-Path -Parent $can.Files[0]
        { Remove-LtFolderContents -Path $dir } | Should -Throw '*KURU ÇALIŞMA*'
        { Remove-LtFileSafe -Path $can.Files[1] } | Should -Throw '*KURU ÇALIŞMA*'
        foreach ($f in $can.Files) { Test-Path -LiteralPath $f | Should -BeTrue }
    }

    It 'Kullanıcı betiği (PowerShell ve Batch) çalıştırılmaz' {
        { Invoke-LtUserScript -Code "Set-Content -LiteralPath '$marker' -Value x" -Kind PowerShell } | Should -Throw '*KURU ÇALIŞMA*'
        { Invoke-LtUserScript -Code "echo x > `"$marker`"" -Kind Batch } | Should -Throw '*KURU ÇALIŞMA*'
        Test-Path -LiteralPath $marker | Should -BeFalse
    }

    It 'Diğer ilkeller reddedilir: <Name>' -ForEach @(
        @{ Name = 'Geri Dönüşüm Kutusu';        Action = { Clear-LtRecycleBin } }
        @{ Name = 'Teslim İyileştirme';         Action = { Invoke-LtDeliveryOptimizationCleanup } }
        @{ Name = 'Araç başlatma (cleanmgr)';   Action = { Start-LtProcessAndWait -FilePath 'cleanmgr.exe' -Arguments '/sagerun:777' } }
        @{ Name = 'Explorer yeniden başlatma';  Action = { Restart-LtExplorerShell } }
        @{ Name = '.reg içe aktarma';           Action = { Import-LtRegFile -Path (Join-Path $can.Root 'eski.reg') } }
    ) {
        { & $Action } | Should -Throw '*KURU ÇALIŞMA*'
        @(Get-LtBlockedOperations).Count | Should -Be 1
        Assert-LtNoSideEffectCalls
    }

    It 'Süreç kapatma yalnızca sahte süreç listesinde simüle edilir' {
        Stop-LtProcessSafe -Names @('chrome')
        @((Get-LtMemoryState).Processes).Count | Should -Be 0
        @((Get-LtMemoryState).Calls) | Should -Contain 'Process.Stop|chrome'
        @(Get-LtProcessesByName -Names @('pwsh', 'powershell')).Count | Should -Be 0
        Assert-LtNoSideEffectCalls
    }
}

Describe 'Açıkça ayrılmış test kökü (gerçek dosya silme yalnızca burada)' {
    BeforeEach {
        $sys = New-LtTestSystem
        Clear-LtBlockedOperations
        Register-LtSideEffectMocks
        $can = New-LtCanary -RedirectEnv
        # Not: ortam yönlendirmesi Windows'ta GetTempPath'i de değiştirir; test kökü özgün geçici klasörde
        $sandbox = Join-Path (Split-Path -Parent $can.Root) ('lt-sandbox-' + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path (Join-Path $sandbox 'cache/alt') -Force)
        [IO.File]::WriteAllText((Join-Path $sandbox 'cache/1.tmp'), ('x' * 100))
        [IO.File]::WriteAllText((Join-Path $sandbox 'cache/alt/2.tmp'), ('y' * 50))
        $env:TMP = $can.Saved['TMP']; $env:TEMP = $can.Saved['TEMP']   # Set-LtCleanupTestRoot özgün geçici klasörü kullansın
        Set-LtCleanupTestRoot $sandbox
        $env:TMP = $can.Base['TMP']; $env:TEMP = $can.Base['TEMP']
    }
    AfterEach {
        Set-LtCleanupTestRoot $null
        Remove-LtCanary $can
        if ($sandbox -and (Split-Path -Leaf $sandbox).StartsWith('lt-sandbox-')) { Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue }
        Remove-LtTestSystem $sys
    }

    It 'Test kökü içindeki öğe gerçekten silinir; sahte açık uygulama yalnızca simülasyonla kapatılır' {
        $item = @{ Id = 't.sb'; Title = 'sb'; Processes = @('chrome'); Paths = [scriptblock]::Create("@(@{ Path = '$(Join-Path $sandbox 'cache')'; Label = 'c' })") }
        $r = Invoke-LtCleanupItem -Item $item -Context $sys.Ctx -CloseApps
        $r.Status | Should -Be 'Success'
        $r.BytesFreed | Should -Be 150
        @(Get-ChildItem (Join-Path $sandbox 'cache') -Recurse -File).Count | Should -Be 0
        @((Get-LtMemoryState).Calls) | Should -Contain 'Process.Stop|chrome'
        Assert-LtNoSideEffectCalls
    }

    It 'Katalog öğeleri test kökü dışındaki gerçek yollara dokunamaz; komut/araç ilkelleri yine reddedilir' {
        $ids = @('clean.temp-user', 'clean.temp-system', 'clean.chrome', 'clean.crashdumps', 'clean.recyclebin', 'clean.dns', 'clean.eventlogs',
                 'clean.deliveryopt', 'adv.sfc', 'adv.cleanmgr', 'net.stack-reset', 'mem.purge-standby')
        $r = Invoke-LtCleanup -Ids $ids -Context $sys.Ctx -CloseAppIds $ids
        foreach ($x in $r.Results) {
            $x.Status | Should -BeIn @('Failed', 'NotSupported', 'Success') -Because "$($x.Id): $($x.Message)"
            $x.BytesFreed | Should -Be 0 -Because $x.Id
        }
        ($r.Results | Where-Object Id -eq 'clean.temp-user').Message | Should -Match 'Güvenlik'
        ($r.Results | Where-Object Id -eq 'clean.recyclebin').Message | Should -Match 'KURU ÇALIŞMA'
        ($r.Results | Where-Object Id -eq 'clean.dns').Message | Should -Match 'KURU ÇALIŞMA'
        ($r.Results | Where-Object Id -eq 'adv.cleanmgr').Message | Should -Match 'KURU ÇALIŞMA'
        foreach ($f in $can.Files) { Test-Path -LiteralPath $f | Should -BeTrue -Because $f }
        Assert-LtNoSideEffectCalls
    }
}

Describe 'Test kökü kuralları' {
    It 'Test kökü yalnızca geçici klasör altındaki, var olan, ayrı bir lt-* klasörü olabilir' {
        $tempRoot = [IO.Path]::GetTempPath()
        $ok = Join-Path $tempRoot ('lt-root-' + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $ok)
        try {
            { Set-LtCleanupTestRoot $tempRoot } | Should -Throw
            { Set-LtCleanupTestRoot (Join-Path ([IO.Path]::GetPathRoot([IO.Path]::GetFullPath($tempRoot))) 'lt-disarida') } | Should -Throw
            $plain = Join-Path $tempRoot ('baska-' + [guid]::NewGuid().ToString('N'))
            [void](New-Item -ItemType Directory -Path $plain)
            try { { Set-LtCleanupTestRoot $plain } | Should -Throw } finally { Remove-Item -LiteralPath $plain -Force }
            { Set-LtCleanupTestRoot (Join-Path $tempRoot 'lt-olmayan-klasor-xyz') } | Should -Throw
            { Set-LtCleanupTestRoot $ok } | Should -Not -Throw
            Test-LtCleanupSandbox | Should -BeTrue
        } finally {
            Set-LtCleanupTestRoot $null
            Remove-Item -LiteralPath $ok -Force
        }
        Test-LtCleanupSandbox | Should -BeFalse
    }
}

Describe 'Kuru çalışma: diğer akışlar (ayar motoru, geri yükleme noktası, bellek listesi, durum yedeği)' {
    BeforeEach {
        $sys = New-LtTestSystem
        Clear-LtBlockedOperations
        Register-LtSideEffectMocks
        Mock -ModuleName LivnTools -CommandName Invoke-LtNative -MockWith { throw 'YAN ETKİ: Invoke-LtNative' }
    }
    AfterEach { Remove-LtTestSystem $sys }

    It 'Tüm ayarlar: uygula, önceki ayara dön, Windows varsayılanı, durum yedeği ve kurtarma gerçek sisteme dokunmaz' {
        $ids = @(Get-LtCatalog | ForEach-Object { $_.Id })
        $a = Invoke-LtApply -TweakIds $ids -Context $sys.Ctx
        @($a.Results | Where-Object { $_.Status -in @('Success', 'AlreadyApplied') }).Count | Should -BeGreaterThan 10
        $bk = Export-LtStateBackup -TweakIds $ids -Context $sys.Ctx -Label 'kuru'
        [void](Invoke-LtRevert -TweakIds $ids -Context $sys.Ctx -Target Previous)
        [void](Invoke-LtRevert -TweakIds $ids -Context $sys.Ctx -Target Default)
        [void](Restore-LtStateBackup -Path $bk.Path)
        foreach ($op in @(Get-LtIncompleteOperations)) { [void](Invoke-LtRecovery -OperationId $op.Id -Mode Revert) }

        @(Get-LtBlockedOperations).Count | Should -Be 0
        Should -Invoke -ModuleName LivnTools -CommandName Invoke-LtNative -Times 0 -Exactly
        Assert-LtNoSideEffectCalls
        $bk.Path | Should -BeLike "$(Get-LtDataRoot)*" -Because 'yedek yalnızca kuru çalışmanın veri klasörüne yazılır'
    }

    It 'Geri yükleme noktası ve bellek listesi komutları simüle edilir' {
        (New-LtRestorePoint).Status | Should -Be 'Success'
        @((Get-LtMemoryState).RestorePoints).Count | Should -Be 1
        $m = Invoke-LtMemoryList -Command PurgeStandby
        $m.Status | Should -Be 'Success'; $m.Message | Should -Match 'simüle'
        Assert-LtNoSideEffectCalls
    }
}

Describe 'Yapısal kural: yan etkiler yalnızca korumalı ilkellerden yapılır' {
    It 'src altındaki her yan etkili çağrı korumalı bir fonksiyonun içinde' {
        $repo = Split-Path -Parent $PSScriptRoot
        $forbiddenCmd = @('Stop-Process', 'Remove-Item', 'Clear-RecycleBin', 'Start-Process', 'Delete-DeliveryOptimizationCache',
            'Set-ItemProperty', 'New-ItemProperty', 'Remove-ItemProperty', 'Stop-Service', 'Start-Service', 'Restart-Service', 'Set-Service',
            'Remove-AppxPackage', 'Register-ScheduledTask', 'Unregister-ScheduledTask', 'Set-ProcessMitigation', 'Set-NetAdapterAdvancedProperty',
            'Reset-NetAdapterAdvancedProperty', 'Set-CimInstance', 'New-CimInstance', 'Remove-CimInstance', 'Invoke-CimMethod', 'Checkpoint-Computer', 'Restart-Computer', 'Stop-Computer',
            'Move-Item', 'Copy-Item', 'Invoke-Expression', 'Invoke-Item', 'Clear-Content')
        $forbiddenMember = @('Delete', 'Kill', 'SetValue', 'DeleteValue', 'DeleteSubKey', 'DeleteSubKeyTree', 'CreateSubKey', 'MemoryListCommand', 'EnablePrivilege', 'SetSystemParameter')
        # Önce kapıdan geçen fonksiyonlar
        $assertGuarded = @('Get-LtWingetInstalledIds', 'Remove-LtOptionalApp', 'Open-LtPerformanceResource', 'Open-LtGraphicsSettings', 'Invoke-LtNative', 'Remove-LtFolderContents', 'Remove-LtFileSafe', 'Clear-LtRecycleBin', 'Invoke-LtDeliveryOptimizationCleanup',
            'Start-LtProcessAndWait', 'Restart-LtExplorerShell', 'Invoke-LtUserScript', 'Import-LtRegFile', 'Open-LtWingetHelp', 'Open-LtHealthLink')
        # Sistem ayarına dokunmayan, gerekçeli istisnalar
        $exempt = @{
            'Write-LtFileAtomic' = 'veri klasöründeki journal/ledger/yedek ve kullanıcının seçtiği JSON profil dosyası'
            'Read-LtLedger'      = 'bozuk ledger kopyası veri klasörüne'
            'Restore-LtAtomicWriteBackup' = 'yalnız veri klasöründeki yarım kalmış atomik yazım yedeği (.bak) geri konur'
            'Open-LtFolder'      = 'yalnızca klasör penceresi açar'
        }
        $memBranch = "LtBackend -eq 'Memory'|\(Get-LtBackend\) -eq 'Memory'|-not \(Test-LtLiveSystem\)"
        $memBranchFiles = @('Backend.ps1', 'SystemInfo.ps1', 'SideEffects.ps1')
        $violations = New-Object System.Collections.ArrayList
        foreach ($file in @(Get-ChildItem -Path (Join-Path $repo 'src') -Recurse -Include *.ps1, *.psm1 -File)) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
            $hits = $ast.FindAll({
                param($n)
                if ($n -is [System.Management.Automation.Language.CommandAst]) { return ($forbiddenCmd -contains $n.GetCommandName()) }
                if ($n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Member -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                    if ($forbiddenMember -contains $n.Member.Value) { return $true }
                    # Process.Start(): yalnızca süreç nesnesi / [Diagnostics.Process] üzerinde
                    if ($n.Member.Value -eq 'Start' -and $n.Expression.Extent.Text -match 'proc|Process') { return $true }
                }
                return $false
            }, $true)
            foreach ($h in $hits) {
                $fn = $h.Parent
                while ($fn -and -not ($fn -is [System.Management.Automation.Language.FunctionDefinitionAst])) { $fn = $fn.Parent }
                $where = '{0}:{1} {2}' -f $file.Name, $h.Extent.StartLineNumber, ($h.Extent.Text -split "`n")[0].Trim()
                if (-not $fn) { [void]$violations.Add("fonksiyon dışı: $where"); continue }
                $body = $fn.Extent.Text
                # Bellek dalı istisnası yalnızca arka uç ilkel dosyalarında geçerli (motor/UI/katalog fonksiyonlarında değil)
                $ok = ($assertGuarded -contains $fn.Name -and $body -match 'Assert-LtLiveSystem|Assert-LtDeletePermitted') -or
                      ($memBranchFiles -contains $file.Name -and $body -match $memBranch) -or $exempt.ContainsKey($fn.Name)
                if (-not $ok) { [void]$violations.Add("$($fn.Name): $where") }
            }
        }
        $violations.Count | Should -Be 0 -Because ($violations -join ' | ')
    }

    It 'Katalog Run/Paths blokları yan etkili komutları doğrudan çağırmaz' {
        $file = Join-Path (Split-Path -Parent $PSScriptRoot) 'src/Cleanup.ps1'
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$null, [ref]$null)
        $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-LtCleanupDefinitions' }, $true)
        $fn | Should -Not -BeNullOrEmpty
        $direct = @('Stop-Process', 'Remove-Item', 'Clear-RecycleBin', 'Start-Process', 'Get-PnpDevice', 'Get-Process', 'Delete-DeliveryOptimizationCache', 'Set-ItemProperty', 'Stop-Service', 'Start-Service')
        $bad = @($fn.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and ($direct -contains $n.GetCommandName()) }, $true) | ForEach-Object { "$($_.Extent.StartLineNumber): $($_.Extent.Text)" })
        $bad.Count | Should -Be 0 -Because ($bad -join ' | ')
        $dyn = @($fn.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.InvocationOperator -eq 'Ampersand' -and $n.CommandElements[0] -is [System.Management.Automation.Language.VariableExpressionAst] }, $true))
        $dyn.Count | Should -Be 0 -Because 'dinamik komut çağrısı (& $cmd) korumayı atlatabilir'
    }
}
