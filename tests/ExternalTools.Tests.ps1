BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
}
Describe 'Optional external performance integrations' {
    BeforeEach { $sys = New-LtTestSystem }
    AfterEach { Remove-LtTestSystem $sys }

    It 'Uses exact physical MB rather than rounded GB' {
        $p = Get-LtIslcProfile @{RamMB=15871; RamGB=16}
        $p.FreeMemoryMB | Should -Be 1587
        $p.Arguments | Should -Be '-minimized -polling 1000 -listsize 1024 -freememory 1587'
    }
    It 'Bounds the starting heuristic on small and large memory systems' {
        (Get-LtIslcProfile @{RamGB=2}).FreeMemoryMB | Should -Be 512
        (Get-LtIslcProfile @{RamGB=128}).FreeMemoryMB | Should -Be 4096
        (Get-LtIslcProfile @{RamGB=32}).FreeMemoryMB | Should -Be 3276
    }
    It 'Does not assume 16 GB when hardware detection fails' {
        { Get-LtIslcProfile @{} } | Should -Throw
        { Get-LtIslcProfile @{RamGB=-1} } | Should -Throw
        { Get-LtIslcProfile @{RamMB=[double]::NaN} } | Should -Throw
    }
    It 'Rejects missing or arbitrary selected applications without falling back' {
        $sys.Ctx.IslcPath = Join-Path $sys.Root 'not-found.exe'
        { Get-LtIslcFile $sys.Ctx } | Should -Throw
        $sys.Ctx.IslcPath = Join-Path $sys.Root 'wrong.exe'
        [IO.File]::WriteAllText($sys.Ctx.IslcPath, 'not an executable')
        { Get-LtIslcFile $sys.Ctx } | Should -Throw
    }
    It 'Rejects a text file renamed to the ISLC executable name' {
        $sys.Ctx.IslcPath = Join-Path $sys.Root 'Intelligent standby list cleaner ISLC.exe'
        [IO.File]::WriteAllText($sys.Ctx.IslcPath, 'not an executable')
        { Get-LtIslcFile $sys.Ctx } | Should -Throw
    }
    It 'Finds the opted-in application from its existing task after restart' {
        $sys.Ctx.AppRoot = New-LtThirdPartyFixture -Root $sys.Root
        $file = Get-LtIslcFile $sys.Ctx
        (Invoke-LtApply -TweakIds 'mem.islc-autostart' -Context $sys.Ctx).Results[0].Status | Should -Be Success
        $sys.Ctx.AppRoot = $sys.Root
        (Get-LtIslcFile $sys.Ctx).Path | Should -Be $file.Path
        (Get-LtScheduledTaskInfo -TaskPath '\LivnTools\' -TaskName ISLC).Arguments | Should -Be (Get-LtIslcProfile $sys.Ctx).Arguments
    }
    It 'Enables an installed vendor plan without importing or duplicating it and restores the previous plan' {
        $previous = Get-LtActivePowerScheme
        $vendor = 'd629ad83-277b-428f-b571-47105d8aaec8'
        $sys.Mem.PowerSchemes += $vendor
        $sys.Ctx.SelectedPowerPlanGuid = $vendor
        $before = @($sys.Mem.PowerSchemes).Count
        (Invoke-LtApply -TweakIds 'power.installed' -Context $sys.Ctx).Results[0].Status | Should -Be Success
        (Get-LtActivePowerScheme) | Should -Be $vendor
        @($sys.Mem.PowerSchemes).Count | Should -Be $before
        (Invoke-LtApply -TweakIds 'power.installed' -Context $sys.Ctx).Results[0].Status | Should -Be AlreadyApplied
        (Invoke-LtRevert -TweakIds 'power.installed' -Context $sys.Ctx -Target Previous).Summary.Failed | Should -Be 0
        (Get-LtActivePowerScheme) | Should -Be $previous
    }
    It 'Revalidates selected plan membership rather than trusting stale context' {
        $sys.Ctx.SelectedPowerPlanGuid = 'd629ad83-277b-428f-b571-47105d8aaec8'
        $sys.Ctx.PowerSchemes += $sys.Ctx.SelectedPowerPlanGuid
        { Get-LtSelectedPowerPlan $sys.Ctx } | Should -Throw
        $sys.Ctx.SelectedPowerPlanGuid = 'not-a-guid'
        { Get-LtSelectedPowerPlan $sys.Ctx } | Should -Throw
    }
    It 'Never launches vendor sites or Windows Settings in DryRun' {
        Mock -ModuleName LivnTools Start-Process { throw 'must not reach launch' }
        foreach ($id in @('ISLC','ParkControl','ProcessLasso','PresentMon','WindowsPower')) {
            { Open-LtPerformanceResource -Id $id } | Should -Throw
        }
        Should -Invoke -ModuleName LivnTools Start-Process -Times 0 -Exactly
    }
    It 'Keeps optional integrations out of all presets' {
        foreach ($preset in (Get-LtPresets).Values) {
            $preset.Ids | Should -Not -Contain 'power.installed'
            $preset.Ids | Should -Not -Contain 'mem.islc-autostart'
        }
    }
    It 'Labels demo power plans by name while retaining GUIDs as selection keys' {
        $plans = @(Get-LtPowerPlanChoices)
        ($plans | Where-Object Guid -eq '381b4222-f694-41f0-9685-ff5bb260df2e').Label | Should -Match 'Dengeli'
        @($plans | Where-Object IsActive).Count | Should -Be 1
        foreach ($plan in $plans) { $plan.Label | Should -Not -Match '[a-f0-9]{8}-' }
    }
    It 'Preserves localized and custom live plan names without displaying GUIDs' {
        Set-LtBackend Windows
        Mock -ModuleName LivnTools Invoke-LtNativeChecked {
            @{ StdOut="Power Scheme GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  (Balanced) *`nGuc Duzeni GUID: d629ad83-277b-428f-b571-47105d8aaec8  (My plan (custom))" }
        }
        $plans = @(Get-LtPowerPlanChoices)
        $plans.Count | Should -Be 2
        $plans[0].Name | Should -Be 'Balanced'
        $plans[0].IsActive | Should -BeTrue
        $plans[1].Name | Should -Be 'My plan (custom)'
        $plans[1].IsActive | Should -BeFalse
        $plans[1].Guid | Should -Be 'd629ad83-277b-428f-b571-47105d8aaec8'
    }

}
