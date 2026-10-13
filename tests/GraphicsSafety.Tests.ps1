#Requires -Modules Pester
BeforeAll { . (Join-Path $PSScriptRoot 'TestHelpers.ps1') }
Describe 'Graphics capability claims and read-only device inspection' {
    BeforeEach { $sys = New-LtTestSystem }
    AfterEach { Remove-LtTestSystem $sys }
    It 'Reports HAGS support and effective state only from the driver query, not from HwSchMode' {
        [void](Set-LtRegValue 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' -Kind DWord -Data 2)
        $result = Get-LtGraphicsConfiguration
        $result.Configured | Should -Match 'HwSchMode=2'
        $result.Supported | Should -Be 'Destekleniyor'
        $result.Effective | Should -Be 'Kapalı' -Because 'sahte sürücü etkin değil diyor; kayıtlı tercih etkin durum sayılmaz'
        $sys.Mem.DemoContext.Hags = @{ Supported = $null; Enabled = $null; Detail = 'okunamadı' }
        $unknown = Get-LtGraphicsConfiguration
        $unknown.Supported | Should -Be 'Unknown'
        $unknown.Effective | Should -Be 'Unknown'
    }
    It 'Does not infer disabled HAGS from an absent preference' {
        $sys.Mem.DemoContext.Hags = @{ Supported = $null; Enabled = $null; Detail = 'okunamadı' }
        $result = Get-LtGraphicsConfiguration
        $result.Configured | Should -Match 'varsayılanı'
        $result.Effective | Should -Be 'Unknown'
    }
    It 'Reads only the selected PCI device preference without writing' {
        $gpu = @($sys.Ctx.MsiDevices | Where-Object Class -eq 'GPU')[0]
        $path = "HKLM\SYSTEM\CurrentControlSet\Enum\$($gpu.InstanceId)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
        [void](Set-LtRegValue $path 'MSISupported' -Kind DWord -Data 1)
        $count = $sys.Mem.Calls.Count
        $result = Get-LtMsiDeviceConfiguration -Context $sys.Ctx -InstanceId $gpu.InstanceId
        $result.InstanceId | Should -Be $gpu.InstanceId
        $result.Configured | Should -Match 'DWORD'
        $result.Supported | Should -Be 'MSI' -Because 'sahte GPU kesme desteği: hat tabanlı + MSI'
        $result.Effective | Should -Be 'Unknown'
        @($sys.Mem.Calls | Select-Object -Skip $count | Where-Object { $_ -like 'Registry.Set*' }).Count | Should -Be 0
    }
    It 'Rejects unknown or ambiguous device selections' {
        { Get-LtMsiDeviceConfiguration -Context $sys.Ctx -InstanceId 'PCI\UNKNOWN\1' } | Should -Throw
        $device = $sys.Ctx.MsiDevices[0]
        $sys.Ctx.MsiDevices = @($device, $device)
        { Get-LtMsiDeviceConfiguration -Context $sys.Ctx -InstanceId $device.InstanceId } | Should -Throw
    }
    It 'Does not launch Windows Settings in Memory mode even when called directly' {
        Mock -ModuleName LivnTools Start-Process { throw 'must not launch' }
        { Open-LtGraphicsSettings } | Should -Throw '*KURU*'
        Should -Invoke -ModuleName LivnTools Start-Process -Times 0 -Exactly
    }
    It 'Refuses MSI writes until a matching device is selected' {
        foreach ($id in @('msi.gpu', 'msi.nic')) {
            (Invoke-LtApply -TweakIds $id -Context $sys.Ctx).Results[0].Status | Should -Be 'NotSupported'
            { Resolve-LtTweakActions (Get-LtTweak $id) $sys.Ctx } | Should -Throw '*seçin*'
        }
        @(Get-LtLedgerEntries).Count | Should -Be 0
    }
    It 'Can still revert an old HAGS registry record' {
        $old = New-LtRegAction -Path 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'HwSchMode' -Value 2
        [void](Add-LtLedgerOriginal -Key (Get-LtActionKey $old) -Action $old -Snapshot (Get-LtActionSnapshot $old) -TweakId 'gpu.hags')
        Invoke-LtActionApply $old
        (Invoke-LtRevert -TweakIds 'gpu.hags' -Context $sys.Ctx -Target Previous).Results[0].Status | Should -Be 'Success'
        (Get-LtRegValue $old.Path $old.Name).Exists | Should -BeFalse
    }
    It 'Can still revert an old MSI registry record' {
        $device = $sys.Ctx.MsiDevices[0]
        $old = New-LtRegAction -Path "HKLM\SYSTEM\CurrentControlSet\Enum\$($device.InstanceId)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties" -Name 'MSISupported' -Value 1
        [void](Add-LtLedgerOriginal -Key (Get-LtActionKey $old) -Action $old -Snapshot (Get-LtActionSnapshot $old) -TweakId 'msi.gpu')
        Invoke-LtActionApply $old
        (Invoke-LtRevert -TweakIds 'msi.gpu' -Context $sys.Ctx -Target Previous).Results[0].Status | Should -Be 'Success'
        (Get-LtRegValue $old.Path $old.Name).Exists | Should -BeFalse
    }
}
