#Requires -Modules Pester
BeforeAll { . (Join-Path $PSScriptRoot 'TestHelpers.ps1') }
Describe 'Hibernate configuration rollback' {
    BeforeEach { $sys = New-LtTestSystem; $key = 'HKLM\SYSTEM\CurrentControlSet\Control\Power' }
    AfterEach { Remove-LtTestSystem $sys }
    It 'Restores a full hiberfile with a custom size preference' {
        [void](Set-LtRegValue $key HiberFileSizePercent -Kind DWord -Data 75)
        $before = Get-LtHibernateConfiguration
        (Invoke-LtApply -TweakIds 'sys.hibernate-off' -Context $sys.Ctx).Results[0].Status | Should -Be 'Success'
        (Invoke-LtRevert -TweakIds 'sys.hibernate-off' -Context $sys.Ctx -Target Previous).Results[0].Status | Should -Be 'Success'
        Test-LtHibernateConfigurationEqual (Get-LtHibernateConfiguration) $before | Should -BeTrue
    }
    It 'Restores reduced type and an absent size preference' {
        $sys.Mem.HibernateType = 'Reduced'
        $before = Get-LtHibernateConfiguration
        [void](Invoke-LtApply -TweakIds 'sys.hibernate-off' -Context $sys.Ctx)
        [void](Set-LtRegValue $key HiberFileSizePercent -Kind DWord -Data 100)
        (Invoke-LtRevert -TweakIds 'sys.hibernate-off' -Context $sys.Ctx -Target Previous).Results[0].Status | Should -Be 'Success'
        Test-LtHibernateConfigurationEqual (Get-LtHibernateConfiguration) $before | Should -BeTrue
    }
    It 'Does not write when already disabled' {
        $sys.Mem.HibernateType = 'None'
        (Invoke-LtApply -TweakIds 'sys.hibernate-off' -Context $sys.Ctx).Results[0].Status | Should -Be 'AlreadyApplied'
        @($sys.Mem.Calls | Where-Object { $_ -like 'Hibernate.Set*' }).Count | Should -Be 0
    }
    It 'Refuses unknown file types before mutation' {
        $sys.Mem.HibernateType = 'Unknown'
        { Get-LtHibernateConfiguration } | Should -Throw
        @($sys.Mem.Calls | Where-Object { $_ -like 'Hibernate.Set*' }).Count | Should -Be 0
    }
    It 'Retains incomplete legacy ledger rather than inventing type and size' {
        $a = @{ Type='Hibernate'; Enabled=$false; Default=$true }
        [void](Add-LtLedgerOriginal -Key 'Hibernate|System' -Action $a -Snapshot @{ Enabled=$true } -TweakId 'sys.hibernate-off')
        (Invoke-LtApply -TweakIds 'sys.hibernate-off' -Context $sys.Ctx).Results[0].Status | Should -Be 'NotSupported'
        Set-LtHibernateEnabled $false
        (Invoke-LtRevert -TweakIds 'sys.hibernate-off' -Context $sys.Ctx -Target Previous).Results[0].Status | Should -Be 'Failed'
        Get-LtHibernateEnabled | Should -BeFalse
        @(Get-LtLedgerEntries | Where-Object { $_.key -eq 'Hibernate|System' }).Count | Should -Be 1
    }
    It 'Does not claim a successful rollback when restoration is a no-op' {
        [void](Invoke-LtApply -TweakIds 'sys.hibernate-off' -Context $sys.Ctx)
        $sys.Mem.NoOps['Hibernate.Restore:system'] = $true
        (Invoke-LtRevert -TweakIds 'sys.hibernate-off' -Context $sys.Ctx -Target Previous).Results[0].Status | Should -Be 'Failed'
        @(Get-LtLedgerEntries | Where-Object { $_.key -eq 'Hibernate|System' }).Count | Should -Be 1
    }
    It 'Does not reach native commands or compilation in Memory mode' {
        Mock -ModuleName LivnTools Invoke-LtNativeChecked { throw 'native command reached' }
        Mock -ModuleName LivnTools Add-Type { throw 'compiler reached' }
        $before = Get-LtHibernateConfiguration
        Set-LtHibernateEnabled $false
        Restore-LtHibernateConfiguration $before
        Should -Invoke -ModuleName LivnTools Invoke-LtNativeChecked -Times 0 -Exactly
        Should -Invoke -ModuleName LivnTools Add-Type -Times 0 -Exactly
    }
    It 'Has no universal Windows default' {
        Test-LtActionHasDefault @{ Type='Hibernate'; Enabled=$false } | Should -BeFalse
    }
}
