#Requires -Modules Pester
BeforeAll { . (Join-Path $PSScriptRoot 'TestHelpers.ps1') }
Describe 'SPI user preferences' {
    BeforeEach { $sys = New-LtTestSystem; $sys.Ctx.MenuDelayMs = 100 }
    AfterEach { Remove-LtTestSystem $sys }
    It 'Applies and restores all three session preferences and missing raw values' {
        foreach ($pair in @(@('input.mouse-accel-off','Mouse'), @('ui.menu-delay','MenuDelay'), @('ui.animations-off','Animation'))) {
            $a = @{ Type='UserParameter'; Setting=$pair[1] }
            $before = Get-LtActionSnapshot $a
            (Invoke-LtApply -TweakIds $pair[0] -Context $sys.Ctx).Results[0].Status | Should -Be 'Success'
            (Invoke-LtRevert -TweakIds $pair[0] -Context $sys.Ctx -Target Previous).Results[0].Status | Should -Be 'Success'
            Test-LtSnapshotEqual $a (Get-LtActionSnapshot $a) $before | Should -BeTrue
        }
    }
    It 'Preserves differences between effective value and registry type/data' {
        [void](Set-LtRegValue 'HKCU\Control Panel\Desktop' 'MenuShowDelay' -Kind DWord -Data 200)
        $sys.Mem.UserSettings.MenuDelay = [int[]]@(450)
        $a = @{ Type='UserParameter'; Setting='MenuDelay' }
        $before = Get-LtActionSnapshot $a
        [void](Invoke-LtApply -TweakIds 'ui.menu-delay' -Context $sys.Ctx)
        (Invoke-LtRevert -TweakIds 'ui.menu-delay' -Context $sys.Ctx -Target Previous).Results[0].Status | Should -Be 'Success'
        Test-LtSnapshotEqual $a (Get-LtActionSnapshot $a) $before | Should -BeTrue
    }
    It 'Detects API no-op even if the registry already contains the desired preference' {
        [void](Set-LtRegValue 'HKCU\Control Panel\Desktop' 'MenuShowDelay' -Kind String -Data '100')
        $sys.Mem.NoOps['UserParameter.Set:MenuDelay'] = $true
        (Invoke-LtApply -TweakIds 'ui.menu-delay' -Context $sys.Ctx).Results[0].Status | Should -Be 'Failed'
    }
    It 'Rolls back effective state after a partial persistence failure' {
        $sys.Mem.Faults['Registry.Set:HKCU\Control Panel\Mouse|MouseThreshold2'] = 'injected persistence failure'
        $a = @{ Type='UserParameter'; Setting='Mouse' }; $before = Get-LtActionSnapshot $a
        (Invoke-LtApply -TweakIds 'input.mouse-accel-off' -Context $sys.Ctx).Results[0].Status | Should -Be 'Failed'
        Test-LtSnapshotEqual $a (Get-LtActionSnapshot $a) $before | Should -BeTrue
    }
    It 'Blocks writes when elevated identity differs from session owner' {
        $sys.Mem.UserSettings.SessionOwnerSid = 'S-1-5-21-2000'
        { Set-LtUserParameter Mouse @(0,0,0) } | Should -Throw
        (Invoke-LtApply -TweakIds 'input.mouse-accel-off' -Context $sys.Ctx).Results[0].Status | Should -Be 'NotSupported'
        @($sys.Mem.Calls | Where-Object { $_ -like 'UserParameter.Set*' }).Count | Should -Be 0
    }
    It 'Refuses to restore a snapshot belonging to another user' {
        $snap = Get-LtUserParameterSnapshot 'MenuDelay'
        $sys.Mem.UserSettings.UserSid = 'S-1-5-21-2000'
        $sys.Mem.UserSettings.SessionOwnerSid = 'S-1-5-21-2000'
        { Restore-LtUserParameterSnapshot MenuDelay $snap } | Should -Throw '*farklı kullanıcı*'
    }
    It 'Requires a menu duration chosen from the supported choices' {
        $sys.Ctx.Remove('MenuDelayMs')
        (Invoke-LtApply -TweakIds 'ui.menu-delay' -Context $sys.Ctx).Results[0].Status | Should -Be 'NotSupported'
        $sys.Ctx.MenuDelayMs = -1
        (Invoke-LtApply -TweakIds 'ui.menu-delay' -Context $sys.Ctx).Results[0].Status | Should -Be 'NotSupported'
    }
    It 'Never compiles or invokes the Windows native helper in Memory mode' {
        Mock -ModuleName LivnTools Initialize-LtUserSettingsNative { throw 'native helper reached' }
        Set-LtUserParameter Animation @(0)
        ([int[]](Get-LtUserParameter Animation))[0] | Should -Be 0
        Should -Invoke -ModuleName LivnTools Initialize-LtUserSettingsNative -Times 0 -Exactly
    }
    It 'Blocks legacy registry records without losing their rollback path' {
        $old = New-LtRegAction -Path 'HKCU\Control Panel\Desktop' -Name 'MenuShowDelay' -Kind String -Value '0'
        [void](Add-LtLedgerOriginal -Key (Get-LtActionKey $old) -Action $old -Snapshot (Get-LtActionSnapshot $old) -TweakId 'ui.menu-delay')
        Invoke-LtActionApply $old
        (Invoke-LtApply -TweakIds 'ui.menu-delay' -Context $sys.Ctx).Results[0].Status | Should -Be 'NotSupported'
        $result = Invoke-LtRevert -TweakIds 'ui.menu-delay' -Context $sys.Ctx -Target Previous
        $result.Results[0].Status | Should -Be 'Success'
        $result.Results[0].RestartKind | Should -Be 'Logoff'
    }
}
