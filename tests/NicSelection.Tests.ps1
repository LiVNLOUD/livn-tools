#Requires -Modules Pester
BeforeAll { . (Join-Path $PSScriptRoot 'TestHelpers.ps1') }
Describe 'NIC target selection and deferred activation' {
    BeforeEach {
        $sys = New-LtTestSystem
        $sys.Mem.DemoContext.Nics += @{ Name = 'Ethernet 2'; InterfaceGuid = 'bbbbbbbb-bbbb-cccc-dddd-eeeeeeeeeeee'; Description = 'Second NIC'; InstanceId = 'PCI\SECOND\1' }
        $sys.Mem.Nic['ethernet 2|*flowcontrol'] = @{ Value = '3'; Valid = @('0','3'); Default = '3' }
        $sys.Ctx.Nics = $sys.Mem.DemoContext.Nics
    }
    AfterEach { Remove-LtTestSystem $sys }
    It 'Requires an explicit target even if only one adapter was originally detected' {
        foreach ($id in @('net.rss-on','net.ackfreq','nic.flowcontrol-off','nic.eee-off','nic.adaptiveifs-off')) {
            (Invoke-LtApply -TweakIds $id -Context $sys.Ctx).Results[0].Status | Should -Be 'NotSupported'
        }
        @(Get-LtLedgerEntries).Count | Should -Be 0
    }
    It 'Changes only the selected adapter and requests reboot' {
        $sys.Ctx.SelectedNicGuid = $sys.Ctx.Nics[0].InterfaceGuid
        $result = Invoke-LtApply -TweakIds 'nic.flowcontrol-off' -Context $sys.Ctx
        $result.Results[0].Status | Should -Be 'Success'
        $result.Results[0].RestartRequired | Should -BeTrue
        (Get-LtNicProperty 'Ethernet' '*FlowControl').Value | Should -Be '0'
        (Get-LtNicProperty 'Ethernet 2' '*FlowControl').Value | Should -Be '3'
    }
    It 'Reverts by GUID after the adapter has been renamed' {
        $sys.Ctx.SelectedNicGuid = $sys.Ctx.Nics[0].InterfaceGuid
        [void](Invoke-LtApply -TweakIds 'nic.flowcontrol-off' -Context $sys.Ctx)
        $sys.Mem.DemoContext.Nics[0].Name = 'Renamed'
        $sys.Mem.Nic['renamed|*flowcontrol'] = $sys.Mem.Nic['ethernet|*flowcontrol']
        $sys.Mem.Nic.Remove('ethernet|*flowcontrol')
        (Invoke-LtRevert -TweakIds 'nic.flowcontrol-off' -Context $sys.Ctx -Target Previous).Results[0].Status | Should -Be 'Success'
        (Get-LtNicProperty 'Renamed' '*FlowControl').Value | Should -Be '3'
    }
    It 'Does not fall back to a reused name when the original GUID disappears' {
        $sys.Ctx.SelectedNicGuid = $sys.Ctx.Nics[0].InterfaceGuid
        [void](Invoke-LtApply -TweakIds 'nic.flowcontrol-off' -Context $sys.Ctx)
        $sys.Mem.DemoContext.Nics = @(@{ Name = 'Ethernet'; InterfaceGuid = 'cccccccc-bbbb-cccc-dddd-eeeeeeeeeeee' })
        $sys.Mem.Nic['ethernet|*flowcontrol'].Value = '3'
        (Invoke-LtRevert -TweakIds 'nic.flowcontrol-off' -Context $sys.Ctx -Target Previous).Results[0].Status | Should -Be 'Failed'
        (Get-LtNicProperty 'Ethernet' '*FlowControl').Value | Should -Be '3'
        @(Get-LtLedgerEntries).Count | Should -Be 1
    }
    It 'Creates ACK actions only for the selected interface' {
        $sys.Ctx.SelectedNicGuid = $sys.Ctx.Nics[1].InterfaceGuid
        $actions = @(Resolve-LtTweakActions (Get-LtTweak 'net.ackfreq') $sys.Ctx)
        $actions.Count | Should -Be 1
        $actions[0].Path | Should -Match $sys.Ctx.Nics[1].InterfaceGuid
        $actions[0].Path | Should -Not -Match $sys.Ctx.Nics[0].InterfaceGuid
    }
    It 'Builds the TCP interface key with exactly one pair of braces for Get-NetAdapter style GUIDs' {
        foreach ($g in @('{BBBBBBBB-BBBB-CCCC-DDDD-EEEEEEEEEEEE}', 'bbbbbbbb-bbbb-cccc-dddd-eeeeeeeeeeee')) {
            $sys.Ctx.Nics[1].InterfaceGuid = $g
            $sys.Ctx.SelectedNicGuid = $g
            $actions = @(Resolve-LtTweakActions (Get-LtTweak 'net.ackfreq') $sys.Ctx)
            $actions[0].Path | Should -BeExactly 'HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\{bbbbbbbb-bbbb-cccc-dddd-eeeeeeeeeeee}' -Because $g
        }
    }
    It 'Rejects ambiguous adapter identity' {
        $sys.Mem.DemoContext.Nics[1].InterfaceGuid = $sys.Mem.DemoContext.Nics[0].InterfaceGuid
        { Resolve-LtNicName $sys.Mem.DemoContext.Nics[0].InterfaceGuid } | Should -Throw
    }
    It 'All advanced property writes suppress automatic adapter restarts' {
        $source = Join-Path $script:RepoRoot 'src/Core/Backend.ps1'
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($source, [ref]$null, [ref]$null)
        $writes = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Set-NetAdapterAdvancedProperty' }, $true))
        $writes.Count | Should -Be 2
        foreach ($write in $writes) {
            $parameters = @($write.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] } | ForEach-Object ParameterName)
            $parameters | Should -Contain 'NoRestart'
            $parameters | Should -Contain 'InputObject'
        }
    }
}
