#Requires -Modules Pester
BeforeAll { . (Join-Path $PSScriptRoot 'TestHelpers.ps1') }
Describe 'R3 regression: deletion boundaries' {
    BeforeEach {
        $sys = New-LtTestSystem
        $sandbox = Join-Path ([IO.Path]::GetTempPath()) ('lt-boundary-' + [guid]::NewGuid().ToString('N'))
        $sibling = $sandbox + '-other'
        New-Item -ItemType Directory -Path $sandbox, $sibling -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $sibling 'keep.txt') -Value 'keep'
        Set-LtCleanupTestRoot $sandbox
    }
    AfterEach {
        Set-LtCleanupTestRoot $null
        Remove-Item -LiteralPath $sandbox, $sibling -Recurse -Force -ErrorAction SilentlyContinue
        Remove-LtTestSystem $sys
    }
    It 'Rejects a sibling that shares the root prefix' {
        { Remove-LtFolderContents -Path $sibling } | Should -Throw
        { Remove-LtFileSafe -Path (Join-Path $sibling 'keep.txt') } | Should -Throw
        Get-Content -LiteralPath (Join-Path $sibling 'keep.txt') | Should -Be 'keep'
    }
    It 'Rejects traversal into the sibling' {
        $escape = Join-Path $sandbox ('../' + (Split-Path $sibling -Leaf))
        { Remove-LtFolderContents -Path $escape } | Should -Throw
        Test-Path (Join-Path $sibling 'keep.txt') | Should -BeTrue
    }
    It 'Rejects a selected directory link and its descendants' {
        $link = Join-Path $sandbox 'linked'
        $kind = if ([IO.Path]::DirectorySeparatorChar -eq '/') { 'SymbolicLink' } else { 'Junction' }
        New-Item -ItemType $kind -Path $link -Target $sibling -ErrorAction Stop | Out-Null
        try {
            { Remove-LtFolderContents -Path $link } | Should -Throw
            { Remove-LtFileSafe -Path (Join-Path $link 'keep.txt') } | Should -Throw
            Test-Path (Join-Path $sibling 'keep.txt') | Should -BeTrue
        } finally { [IO.Directory]::Delete($link) }
    }
}
Describe 'R3 regression: tweak behavior' {
    BeforeEach { $sys = New-LtTestSystem }
    AfterEach { Remove-LtTestSystem $sys }
    It 'Leaves existing Games scheduling preferences untouched' {
        $key = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'
        [void](Set-LtRegValue $key 'Priority' -Kind DWord -Data 7)
        [void](Set-LtRegValue $key 'Scheduling Category' -Kind String -Data 'Low')
        [void](Invoke-LtApply -TweakIds 'sched.mmcss-games' -Context $sys.Ctx)
        (Get-LtRegValue $key 'Priority').Data | Should -Be 7
        (Get-LtRegValue $key 'Scheduling Category').Data | Should -Be 'Low'
        (Get-LtRegValue $key 'SFIO Priority').Exists | Should -BeFalse
    }
    It 'Never batches security reductions, high-risk device writes, updates or general service shutdown' {
        $presets = Get-LtPresets
        foreach ($name in $presets.Keys) {
            $p = $presets[$name]
            $ids = @($p.Ids) + @(foreach ($group in @(Get-LtProp $p 'OneOf' @())) { $group })
            foreach ($id in $ids) {
                $id | Should -Not -Match '^(sec\.|msi\.|svc\.|wu\.)' -Because "$name/$id"
                $id | Should -Not -BeIn @('mem.pagefile-auto','priv.dmwappush-off','power.installed','mem.islc-autostart') -Because "$name/$id"
                $t = Get-LtTweak $id
                $t | Should -Not -BeNullOrEmpty -Because "$name/$id katalogda olmalı"
                $t.Risk | Should -BeIn @('Low','Medium') -Because "$name/$id"
                $t.Evidence | Should -Not -Be 'Unverified' -Because "$name/$id"
            }
        }
    }
    It 'Keeps hardware, timer and network experiments in the explicit performance preset only' {
        $presets = Get-LtPresets
        foreach ($name in @('Standard','Aggressive','Responsive')) {
            foreach ($id in $presets[$name].Ids) { $id | Should -Not -Match '^(nic\.|timer\.|sched\.|net\.|gpu\.|power\.)' -Because "$name/$id" }
        }
        # Temel yalnız Windows varsayılanına dönüşleri içerir
        foreach ($id in @($presets.Minimal.Ids | Where-Object { $_ -match '^(timer|net)\.' })) {
            $id | Should -BeIn @('timer.platformclock-default','net.autotuning-normal','net.cubic')
        }
    }
    It 'Does not claim a universal event log default' {
        $actions = @(Resolve-LtTweakActions (Get-LtTweak 'sys.eventlog-size') $sys.Ctx)
        foreach ($a in $actions) { Test-LtActionHasDefault $a | Should -BeFalse }
    }
    It 'Does not treat a running disabled service as stopped' {
        $a = @{ Type = 'Service'; Name = 'example'; StartType = 'Disabled'; Stop = $true }
        Test-LtActionDesired $a @{ Exists = $true; StartType = 'Disabled'; Status = 'Running' } | Should -BeFalse
        Test-LtActionDesired $a @{ Exists = $true; StartType = 'Disabled'; Status = 'Stopped' } | Should -BeTrue
    }
    It 'Rolls back startup type when service stop fails' {
        $before = Get-LtServiceInfo 'SysMain'
        $sys.Mem.Faults['Service.Stop:SysMain'] = 'injected stop failure'
        $result = Invoke-LtApply -TweakIds 'svc.sysmain-off' -Context $sys.Ctx
        $result.Results[0].Status | Should -Be 'Failed'
        (Get-LtServiceInfo 'SysMain').StartType | Should -Be $before.StartType
        (Get-LtServiceInfo 'SysMain').Status | Should -Be $before.Status
    }
    It 'Detects service state mismatch during rollback verification' {
        $a = @{ Type = 'Service'; Name = 'example' }
        Test-LtSnapshotEqual $a @{ Exists = $true; StartType = 'Automatic'; Status = 'Stopped' } @{ Exists = $true; StartType = 'Automatic'; Status = 'Running' } | Should -BeFalse
    }
}
