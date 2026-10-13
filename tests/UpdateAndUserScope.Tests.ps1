#Requires -Modules Pester
BeforeAll { . (Join-Path $PSScriptRoot 'TestHelpers.ps1') }
Describe 'Windows Update separation' {
    BeforeEach { $sys = New-LtTestSystem -Build '19045'; $key = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' }
    AfterEach { Remove-LtTestSystem $sys }
    It 'Feature deferral does not defer security updates or change restart policy' {
        (Invoke-LtApply -TweakIds 'wu.defer' -Context $sys.Ctx).Results[0].Status | Should -Be 'Success'
        (Get-LtRegValue $key DeferFeatureUpdatesPeriodInDays).Data | Should -Be 365
        (Get-LtRegValue $key DeferQualityUpdatesPeriodInDays).Exists | Should -BeFalse
        (Get-LtRegValue "$key\AU" NoAutoRebootWithLoggedOnUsers).Exists | Should -BeFalse
    }
    It 'Quality deferral is independent and neither choice belongs to a preset' {
        [void](Invoke-LtApply -TweakIds 'wu.defer' -Context $sys.Ctx)
        (Invoke-LtApply -TweakIds 'wu.quality-defer' -Context $sys.Ctx).Results[0].Status | Should -Be 'Success'
        (Invoke-LtRevert -TweakIds 'wu.quality-defer' -Context $sys.Ctx -Target Previous).Results[0].Status | Should -Be 'Success'
        (Get-LtRegValue $key DeferFeatureUpdatesPeriodInDays).Data | Should -Be 365
        foreach ($preset in (Get-LtPresets).Values) {
            $preset.Ids | Should -Not -Contain 'wu.defer'
            $preset.Ids | Should -Not -Contain 'wu.quality-defer'
        }
    }
    It 'Rejects the legacy feature GPO path on Windows 11' {
        $sys.Ctx.Build = 22631
        (Invoke-LtApply -TweakIds 'wu.defer' -Context $sys.Ctx).Results[0].Status | Should -Be 'NotSupported'
        (Get-LtRegValue $key DeferFeatureUpdates).Exists | Should -BeFalse
    }
    It 'Retains the rollback path for the old combined action' {
        $a = New-LtRegAction -Path "$key\AU" -Name NoAutoRebootWithLoggedOnUsers -Value 1
        [void](Add-LtLedgerOriginal -Key (Get-LtActionKey $a) -Action $a -Snapshot (Get-LtActionSnapshot $a) -TweakId 'wu.defer')
        Invoke-LtActionApply $a
        (Invoke-LtApply -TweakIds 'wu.quality-defer' -Context $sys.Ctx).Results[0].Status | Should -Be 'NotSupported'
        (Invoke-LtRevert -TweakIds 'wu.defer' -Context $sys.Ctx -Target Previous).Results[0].Status | Should -Be 'Success'
        (Get-LtRegValue "$key\AU" NoAutoRebootWithLoggedOnUsers).Exists | Should -BeFalse
    }
}
Describe 'Registry user ownership' {
    BeforeEach {
        $sys = New-LtTestSystem
        $a = New-LtRegAction -Path 'HKCU\Software\LivnScopeTest' -Name 'Preference' -Value 1 -Default 'Absent'
    }
    AfterEach { Remove-LtTestSystem $sys }
    It 'Includes account identity and restores missing user values' {
        $snap = Get-LtActionSnapshot $a
        $snap.UserSid | Should -Be $sys.Mem.UserSettings.UserSid
        Invoke-LtActionApply $a
        Restore-LtActionSnapshot $a $snap
        Test-LtSnapshotEqual $a (Get-LtActionSnapshot $a) $snap | Should -BeTrue
    }
    It 'Guards direct HKCU mutation primitives under another elevated account' {
        $sys.Mem.UserSettings.SessionOwnerSid = 'S-1-5-21-9999'
        { Set-LtRegValue $a.Path Preference -Kind DWord -Data 1 } | Should -Throw
        { New-LtRegKey $a.Path } | Should -Throw
        { Remove-LtRegValue $a.Path Preference } | Should -Throw
        { Remove-LtRegKeyIfEmpty $a.Path } | Should -Throw
        (Test-LtRegKey $a.Path) | Should -BeFalse
    }
    It 'Refuses cross-user snapshot restore even when the values match' {
        $snap = Get-LtActionSnapshot $a
        $sys.Mem.UserSettings.UserSid = 'S-1-5-21-2000'
        $sys.Mem.UserSettings.SessionOwnerSid = 'S-1-5-21-2000'
        Test-LtSnapshotEqual $a (Get-LtActionSnapshot $a) $snap | Should -BeFalse
        { Restore-LtActionSnapshot $a $snap } | Should -Throw
    }
    It 'Refuses ownerless legacy snapshots before mutation' {
        $snap = Get-LtActionSnapshot $a
        $snap.Remove('UserSid')
        Invoke-LtActionApply $a
        { Restore-LtActionSnapshot $a $snap } | Should -Throw
        (Get-LtRegValue $a.Path Preference).Data | Should -Be 1
    }
    It 'Does not merge a second account into an existing ledger record' {
        [void](Add-LtLedgerOriginal -Key (Get-LtActionKey $a) -Action $a -Snapshot (Get-LtActionSnapshot $a) -TweakId 'first')
        $sys.Mem.UserSettings.UserSid = 'S-1-5-21-2000'
        $sys.Mem.UserSettings.SessionOwnerSid = 'S-1-5-21-2000'
        { Add-LtLedgerOriginal -Key (Get-LtActionKey $a) -Action $a -Snapshot (Get-LtActionSnapshot $a) -TweakId 'second' } | Should -Throw
        (Get-LtLedgerEntry (Get-LtActionKey $a)).tweakIds | Should -Not -Contain 'second'
    }
    It 'Blocks engine apply and rollback for an ownerless ledger while retaining it' {
        $action = New-LtRegAction -Path 'HKCU\Software\Microsoft\GameBar' -Name AutoGameModeEnabled -Value 1
        $snap = Get-LtActionSnapshot $action
        $snap.Remove('UserSid')
        [void](Add-LtLedgerOriginal -Key (Get-LtActionKey $action) -Action $action -Snapshot $snap -TweakId 'game.mode')
        (Invoke-LtApply -TweakIds 'game.mode' -Context $sys.Ctx).Results[0].Status | Should -Be 'Failed'
        (Get-LtRegValue $action.Path AutoGameModeEnabled).Exists | Should -BeFalse
        (Invoke-LtRevert -TweakIds 'game.mode' -Context $sys.Ctx -Target Previous).Results[0].Status | Should -Be 'Failed'
        (Get-LtLedgerEntry (Get-LtActionKey $action)) | Should -Not -BeNullOrEmpty
    }
    It 'Keeps machine-wide settings available without a matching desktop owner' {
        $sys.Mem.UserSettings.SessionOwnerSid = 'S-1-5-21-9999'
        { Set-LtRegValue 'HKLM\SOFTWARE\LivnScopeTest' Preference -Kind DWord -Data 1 } | Should -Not -Throw
    }
}
