#Requires -Modules Pester
BeforeAll { . (Join-Path $PSScriptRoot 'TestHelpers.ps1') }
Describe 'Pagefile configuration and rollback' {
    BeforeEach {
        $sys = New-LtTestSystem
        $action = @{ Type = 'Pagefile' }
        $key = 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
        $sys.Mem.Pagefile.Automatic = $false
        $sys.Mem.Pagefile.Settings = @(
            @{ Name = 'C:\pagefile.sys'; InitialSize = 2048; MaximumSize = 4096 },
            @{ Name = 'D:\pagefile.sys'; InitialSize = 8192; MaximumSize = 16384 }
        )
        [void](Set-LtRegValue $key 'PagingFiles' -Kind MultiString -Data @('C:\pagefile.sys 2048 4096', 'D:\pagefile.sys 8192 16384'))
        $before = Get-LtActionSnapshot $action
    }
    AfterEach { Remove-LtTestSystem $sys }
    It 'Restores all custom drives and sizes after a JSON ledger round trip' {
        (Invoke-LtApply -TweakIds 'mem.pagefile-auto' -Context $sys.Ctx).Results[0].Status | Should -Be 'Success'
        (Get-LtPagefileConfiguration).Automatic | Should -BeTrue
        # Simulate changes made by Windows or the user after enabling automatic mode.
        $sys.Mem.Pagefile.Settings = @(@{ Name = 'E:\pagefile.sys'; InitialSize = 0; MaximumSize = 0 })
        [void](Set-LtRegValue $key 'PagingFiles' -Kind MultiString -Data @('E:\pagefile.sys 0 0'))
        (Invoke-LtRevert -TweakIds 'mem.pagefile-auto' -Context $sys.Ctx -Target Previous).Results[0].Status | Should -Be 'Success'
        Test-LtSnapshotEqual $action (Get-LtPagefileConfiguration) $before | Should -BeTrue
    }
    It 'Preserves the first snapshot on repeated application' {
        [void](Invoke-LtApply -TweakIds 'mem.pagefile-auto' -Context $sys.Ctx)
        (Invoke-LtApply -TweakIds 'mem.pagefile-auto' -Context $sys.Ctx).Results[0].Status | Should -Be 'AlreadyApplied'
        Test-LtSnapshotEqual $action (Get-LtLedgerEntry 'Pagefile|System').original $before | Should -BeTrue
    }
    It 'Does not create a backup or write when already automatic' {
        $sys.Mem.Pagefile.Automatic = $true
        (Invoke-LtApply -TweakIds 'mem.pagefile-auto' -Context $sys.Ctx).Results[0].Status | Should -Be 'AlreadyApplied'
        @(Get-LtLedgerEntries).Count | Should -Be 0
        @($sys.Mem.Calls | Where-Object { $_ -like 'Pagefile.SetAutomatic*' }).Count | Should -Be 0
    }
    It 'Detects silent write failure and restores original configuration' {
        $sys.Mem.NoOps['Pagefile.SetAutomatic:system'] = $true
        (Invoke-LtApply -TweakIds 'mem.pagefile-auto' -Context $sys.Ctx).Results[0].Status | Should -Be 'Failed'
        Test-LtSnapshotEqual $action (Get-LtPagefileConfiguration) $before | Should -BeTrue
    }
    It 'Rolls back a partial apply that changes state before throwing' {
        Mock -ModuleName LivnTools Set-LtPagefileAutomatic {
            (Get-LtMemoryState).Pagefile.Automatic = $true
            throw 'injected partial failure'
        }
        (Invoke-LtApply -TweakIds 'mem.pagefile-auto' -Context $sys.Ctx).Results[0].Status | Should -Be 'Failed'
        Test-LtSnapshotEqual $action (Get-LtPagefileConfiguration) $before | Should -BeTrue
    }
    It 'Retains the ledger when rollback cannot restore configuration' {
        [void](Invoke-LtApply -TweakIds 'mem.pagefile-auto' -Context $sys.Ctx)
        $sys.Mem.Faults['Pagefile.Restore:system'] = 'access denied'
        (Invoke-LtRevert -TweakIds 'mem.pagefile-auto' -Context $sys.Ctx -Target Previous).Results[0].Status | Should -Be 'Failed'
        Get-LtLedgerEntry 'Pagefile|System' | Should -Not -BeNullOrEmpty
    }
    It 'Restores an originally missing PagingFiles value' {
        Remove-LtRegValue $key 'PagingFiles'
        $sys.Mem.Pagefile.Settings = @()
        $original = Get-LtPagefileConfiguration
        [void](Invoke-LtApply -TweakIds 'mem.pagefile-auto' -Context $sys.Ctx)
        [void](Set-LtRegValue $key 'PagingFiles' -Kind MultiString -Data @('C:\pagefile.sys 0 0'))
        [void](Invoke-LtRevert -TweakIds 'mem.pagefile-auto' -Context $sys.Ctx -Target Previous)
        Test-LtSnapshotEqual $action (Get-LtPagefileConfiguration) $original | Should -BeTrue
    }
    It 'Blocks legacy records but still allows previous-value restoration' {
        $old = New-LtRegAction -Path $key -Name 'PagingFiles' -Kind MultiString -Value @('?:\pagefile.sys')
        [void](Add-LtLedgerOriginal -Key (Get-LtActionKey $old) -Action $old -Snapshot (Get-LtActionSnapshot $old) -TweakId 'mem.pagefile-auto')
        Invoke-LtActionApply $old
        (Invoke-LtApply -TweakIds 'mem.pagefile-auto' -Context $sys.Ctx).Results[0].Status | Should -Be 'NotSupported'
        (Invoke-LtRevert -TweakIds 'mem.pagefile-auto' -Context $sys.Ctx -Target Previous).Results[0].Status | Should -Be 'Success'
        @(Get-LtLedgerEntries).Count | Should -Be 0
    }
    It 'Does not claim a universal Windows default or include this tweak in presets' {
        Test-LtActionHasDefault $action | Should -BeFalse
        foreach ($p in (Get-LtPresets).Values) { $p.Ids | Should -Not -Contain 'mem.pagefile-auto' }
    }
    It 'Rejects equality when a single drive size differs' {
        $sys.Mem.Pagefile.Settings[1].MaximumSize = 32768
        Test-LtSnapshotEqual $action (Get-LtPagefileConfiguration) $before | Should -BeFalse
    }
}
