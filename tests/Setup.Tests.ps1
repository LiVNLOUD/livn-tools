BeforeAll { . (Join-Path $PSScriptRoot 'TestHelpers.ps1') }
Describe 'Portable setup profile' {
    BeforeEach { $sys = New-LtTestSystem }
    AfterEach { Remove-LtTestSystem $sys }
    It 'Round trips choices but no machine identity, paths or original-state ledger' {
        $callsBefore=$sys.Mem.Calls.Count
        $sys.Ctx.MenuDelayMs=100
        $v = New-LtSetupProfile -TweakIds @('ui.effects-off','ui.menu-delay','input.mouse-accel-off') -PackageIds @('Valve.Steam') -Context $sys.Ctx
        $path=Join-Path $sys.Root 'portable.json'; Save-LtSetupProfile $path $v
        $r=Read-LtSetupProfile $path
        $r.MenuDelayMs | Should -Be 100
        $r.PackageIds | Should -Contain Valve.Steam
        $r.Keys | Should -Not -Contain UserSid
        $r.Keys | Should -Not -Contain AppRoot
        @(Get-LtLedgerEntries).Count | Should -Be 0
        $sys.Mem.Calls.Count | Should -Be $callsBefore
    }
    It 'Rejects hardware, security and unknown choices instead of replaying them' {
        foreach ($id in @('power.installed','sec.cfg-off','clean.minecraft','unknown')) {
            { New-LtSetupProfile -TweakIds $id } | Should -Throw
        }
        { New-LtSetupProfile -PackageIds 'fake;cmd' } | Should -Throw
    }
    It 'Rejects commands and backup payloads at the profile boundary' {
        foreach ($key in @('Script','Journal','UserSid','IslcPath','Arguments')) {
            $v=New-LtSetupProfile; $v[$key]='anything'
            { Test-LtSetupProfile $v } | Should -Throw
        }
    }
    It 'Refuses bad schema, scalar arrays and missing menu parameters' {
        { Test-LtSetupProfile @{SchemaVersion=2;TweakIds=@();PackageIds=@()} } | Should -Throw
        { Test-LtSetupProfile @{SchemaVersion=1;TweakIds='ui.darkmode';PackageIds=@()} } | Should -Throw
        { New-LtSetupProfile -TweakIds ui.menu-delay } | Should -Throw
    }
    It 'Imports without applying and captures originals on the target computer when applied' {
        $path=Join-Path $sys.Root 'portable.json'
        Save-LtSetupProfile $path (New-LtSetupProfile -TweakIds ui.animations-off)
        $v=Read-LtSetupProfile $path
        (Get-LtUserParameter Animation)[0] | Should -Be 1
        $sys.Mem.UserSettings.Animation=[int[]]@(0)
        $action=@{Type='UserParameter';Setting='Animation'}
        $targetOriginal=Get-LtActionSnapshot $action
        (Invoke-LtApply -TweakIds $v.TweakIds -Context $sys.Ctx).Results[0].Status | Should -Be Success
        (Invoke-LtRevert -TweakIds $v.TweakIds -Context $sys.Ctx -Target Previous).Summary.Failed | Should -Be 0
        Test-LtSnapshotEqual $action (Get-LtActionSnapshot $action) $targetOriginal | Should -BeTrue
    }
}
Describe 'Optional setup actions' {
    BeforeEach { $sys=New-LtTestSystem }
    AfterEach { Remove-LtTestSystem $sys }
    It 'Simulates every install and removal in Memory without reaching the primitives' {
        Mock -ModuleName LivnTools Install-LtSetupPackage { throw 'real install reached' }
        Mock -ModuleName LivnTools Remove-LtOptionalApp { throw 'real uninstall reached' }
        $a=Invoke-LtSetupBatch -Mode Install -Ids (Get-LtSetupApps).Id -Accepted
        $b=Invoke-LtSetupBatch -Mode Remove -Ids (Get-LtRemovableApps).Id -Accepted
        @($a.Results | Where-Object { -not $_.Simulated }).Count | Should -Be 0
        @($b.Results | Where-Object { -not $_.Simulated }).Count | Should -Be 0
        Should -Invoke -ModuleName LivnTools Install-LtSetupPackage -Times 0 -Exactly
        Should -Invoke -ModuleName LivnTools Remove-LtOptionalApp -Times 0 -Exactly
    }
    It 'Guards directly invoked primitives in Memory too' {
        { Install-LtSetupPackage -Id Valve.Steam } | Should -Throw '*KURU*'
        { Remove-LtOptionalApp -Id Microsoft.BingNews } | Should -Throw '*KURU*'
        { Get-LtWingetInstalledIds } | Should -Throw '*KURU*'
        @(Get-LtOptionalAppNames).Count | Should -Be 0
    }
    It 'Rejects unapproved and unknown requests before running anything' {
        { Invoke-LtSetupBatch -Mode Install -Ids Valve.Steam } | Should -Throw
        { Invoke-LtSetupBatch -Mode Install -Ids @('Valve.Steam','random.exe') -Accepted } | Should -Throw
        { Invoke-LtSetupBatch -Mode Remove -Ids Microsoft.WindowsStore -Accepted } | Should -Throw
        (Get-LtRemovableApps).Id | Should -Not -Contain Microsoft.GamingApp
    }
    It 'Honors cancellation before starting any package' {
        $r=Invoke-LtSetupBatch -Mode Install -Ids (Get-LtSetupApps).Id -Accepted -Cancel @{Requested=$true}
        @($r.Results | Where-Object Status -ne Skipped).Count | Should -Be 0
    }
    It 'Skips a package matched in the WinGet inventory without upgrading' {
        Mock -ModuleName LivnTools Test-LtLiveSystem { $true }
        Mock -ModuleName LivnTools Get-LtWingetPath { 'unused.exe' }
        Mock -ModuleName LivnTools Get-LtWingetVersion { [version]'1.9.25200' }
        Mock -ModuleName LivnTools Get-LtWingetInstalledIds { @('Valve.Steam') }
        Mock -ModuleName LivnTools Invoke-LtNative { throw 'unexpected install' }
        (Install-LtSetupPackage Valve.Steam).Status | Should -Be AlreadyApplied
        Should -Invoke -ModuleName LivnTools Invoke-LtNative -Times 0 -Exactly
    }
    It 'Does not report native success as installed if inventory verification fails' {
        Mock -ModuleName LivnTools Test-LtLiveSystem { $true }
        Mock -ModuleName LivnTools Get-LtWingetPath { 'unused.exe' }
        Mock -ModuleName LivnTools Get-LtWingetVersion { [version]'1.9.25200' }
        Mock -ModuleName LivnTools Get-LtWingetInstalledIds { @() }
        Mock -ModuleName LivnTools Invoke-LtNative { @{ExitCode=0;TimedOut=$false;StdOut='';StdErr=''} }
        { Install-LtSetupPackage Brave.Brave } | Should -Throw '*doğrulanamadı*'
        Should -Invoke -ModuleName LivnTools Invoke-LtNative -Times 1 -Exactly -ParameterFilter {
            $Arguments -contains '--exact' -and $Arguments -contains '--no-upgrade' -and $Arguments -contains 'winget' -and $Arguments -notcontains '--ignore-security-hash'
        }
    }
    It 'Skips an app that Windows lists as installed even when WinGet cannot correlate it' {
        Mock -ModuleName LivnTools Test-LtLiveSystem { $true }
        Mock -ModuleName LivnTools Get-LtWingetPath { 'unused.exe' }
        Mock -ModuleName LivnTools Get-LtWingetVersion { [version]'1.9.25200' }
        Mock -ModuleName LivnTools Get-LtWingetInstalledIds { @() }
        Mock -ModuleName LivnTools Get-LtInstalledDisplayNames { @('Brave', 'Microsoft Edge') }
        Mock -ModuleName LivnTools Invoke-LtNative { throw 'must not install' }
        $r = Install-LtSetupPackage Brave.Brave
        $r.Status | Should -Be 'AlreadyApplied'
        $r.Message | Should -Match 'WinGet dışı'
        Should -Invoke -ModuleName LivnTools Invoke-LtNative -Times 0 -Exactly
    }
    It 'Accepts the Windows app list as post-install verification when WinGet cannot correlate the package' {
        Mock -ModuleName LivnTools Test-LtLiveSystem { $true }
        Mock -ModuleName LivnTools Get-LtWingetPath { 'unused.exe' }
        Mock -ModuleName LivnTools Get-LtWingetVersion { [version]'1.9.25200' }
        Mock -ModuleName LivnTools Get-LtWingetInstalledIds { @() }
        $script:arpCalls = 0
        Mock -ModuleName LivnTools Get-LtInstalledDisplayNames { $script:arpCalls++; if ($script:arpCalls -gt 1) { @('Brave') } else { @() } }
        Mock -ModuleName LivnTools Invoke-LtNative { @{ExitCode=0;TimedOut=$false;StdOut='';StdErr=''} }
        (Install-LtSetupPackage Brave.Brave).Status | Should -Be 'Success'
    }
    It 'Maps WinGet install exit codes: already installed, reboot to finish, app in use' {
        Mock -ModuleName LivnTools Test-LtLiveSystem { $true }
        Mock -ModuleName LivnTools Get-LtWingetPath { 'unused.exe' }
        Mock -ModuleName LivnTools Get-LtWingetVersion { [version]'1.9.25200' }
        Mock -ModuleName LivnTools Get-LtWingetInstalledIds { @() }
        Mock -ModuleName LivnTools Get-LtInstalledDisplayNames { @() }
        Mock -ModuleName LivnTools Invoke-LtNative { [pscustomobject]@{ ExitCode = [int]0x8A150061; TimedOut = $false; StdOut = ''; StdErr = '' } }
        (Install-LtSetupPackage Brave.Brave).Status | Should -Be 'AlreadyApplied'
        Mock -ModuleName LivnTools Invoke-LtNative { [pscustomobject]@{ ExitCode = [int]0x8A150109; TimedOut = $false; StdOut = ''; StdErr = '' } }
        $r = Install-LtSetupPackage Brave.Brave
        $r.Status | Should -Be 'Success'
        $r.RestartRequired | Should -BeTrue
        $r.Message | Should -Match 'yeniden başlat'
        Mock -ModuleName LivnTools Invoke-LtNative { [pscustomobject]@{ ExitCode = [int]0x8A150101; TimedOut = $false; StdOut = ''; StdErr = '' } }
        { Install-LtSetupPackage Brave.Brave } | Should -Throw '*Uygulama açık*'
    }
    It 'Refuses to install with an outdated WinGet before running the installer' {
        Mock -ModuleName LivnTools Test-LtLiveSystem { $true }
        Mock -ModuleName LivnTools Get-LtWingetPath { 'unused.exe' }
        Mock -ModuleName LivnTools Get-LtWingetVersion { [version]'1.2.10271' }
        Mock -ModuleName LivnTools Get-LtWingetInstalledIds { throw 'must not query' }
        Mock -ModuleName LivnTools Invoke-LtNative { throw 'must not install' }
        { Install-LtSetupPackage Brave.Brave } | Should -Throw '*çok eski*'
    }
    It 'Reports the missing App Installer with guidance' {
        Mock -ModuleName LivnTools Test-LtLiveSystem { $true }
        Mock -ModuleName LivnTools Get-LtWingetPath { throw 'WINGET_MISSING:yok' }
        { Install-LtSetupPackage Brave.Brave } | Should -Throw '*WinGet*edinin*'
    }
    It 'Reads the installed inventory once per batch instead of once per package' {
        Mock -ModuleName LivnTools Test-LtLiveSystem { $true }
        Mock -ModuleName LivnTools Get-LtWingetPath { 'unused.exe' }
        Mock -ModuleName LivnTools Get-LtWingetVersion { [version]'1.9.25200' }
        Mock -ModuleName LivnTools Get-LtInstalledDisplayNames { @() }
        $script:exports = 0
        Mock -ModuleName LivnTools Get-LtWingetInstalledIds { $script:exports++; if ($script:exports -eq 1) { @('Valve.Steam') } else { @('Valve.Steam', 'Brave.Brave') } }
        Mock -ModuleName LivnTools Invoke-LtNative { [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = ''; StdErr = '' } }
        $r = Invoke-LtSetupBatch -Mode Install -Ids @('Valve.Steam', 'Brave.Brave') -Accepted
        ($r.Results | Where-Object Id -eq 'Valve.Steam').Status | Should -Be 'AlreadyApplied'
        ($r.Results | Where-Object Id -eq 'Brave.Brave').Status | Should -Be 'Success'
        $script:exports | Should -Be 2 -Because 'bir toplu envanter + yalnız kurulan paketin doğrulaması'
        Should -Invoke -ModuleName LivnTools Invoke-LtNative -Times 1 -Exactly
    }
    It 'Reports a failed package and continues the remaining selection' {
        Mock -ModuleName LivnTools Test-LtLiveSystem { $true }
        Mock -ModuleName LivnTools Install-LtSetupPackage {
            param($Id)
            if ($Id -eq 'Valve.Steam') { throw 'test failure' }
            New-LtResult -Id $Id -Title $Id -Status Success
        }
        $r=Invoke-LtSetupBatch -Mode Install -Ids @('Valve.Steam','7zip.7zip') -Accepted
        $r.Results[0].Status | Should -Be Failed
        $r.Results[1].Status | Should -Be Success
    }
}
Describe 'Expanded visual settings' {
    BeforeEach { $sys=New-LtTestSystem }
    AfterEach { Remove-LtTestSystem $sys }
    It 'Restores mixed original effects without rewriting the raw shared preferences mask' {
        $sys.Mem.UserSettings.VisualEffects=[int[]]@(1,0,1,0,1)
        [void](Set-LtRegValue 'HKCU\Control Panel\Desktop' UserPreferencesMask -Kind Binary -Data 'AQIDBA==')
        $before=Get-LtRegValue 'HKCU\Control Panel\Desktop' UserPreferencesMask
        (Invoke-LtApply -TweakIds ui.effects-off -Context $sys.Ctx).Results[0].Status | Should -Be Success
        (Get-LtUserParameter VisualEffects) -join ',' | Should -Be '0,0,0,0,0'
        (Invoke-LtRevert -TweakIds ui.effects-off -Context $sys.Ctx -Target Previous).Summary.Failed | Should -Be 0
        (Get-LtUserParameter VisualEffects) -join ',' | Should -Be '1,0,1,0,1'
        (Get-LtRegValue 'HKCU\Control Panel\Desktop' UserPreferencesMask).Data | Should -Be $before.Data
    }
    It 'Rejects malformed effect values and detects an API no-op' {
        { Set-LtUserParameter VisualEffects @(0,0,0,0,2) } | Should -Throw
        { Set-LtUserParameter VisualEffects @(0) } | Should -Throw
        $sys.Mem.NoOps['UserParameter.Set:VisualEffects']=$true
        (Invoke-LtApply -TweakIds ui.effects-off -Context $sys.Ctx).Results[0].Status | Should -Be Failed
    }
    It 'Keeps the responsive preset limited to appearance preferences' {
        $ids=(Get-LtPresets).Responsive.Ids
        foreach ($id in $ids) { $id | Should -BeLike 'ui.*' }
        (Invoke-LtApply -TweakIds $ids -Context $sys.Ctx).Summary.Failed | Should -Be 0
        (Invoke-LtRevert -TweakIds $ids -Context $sys.Ctx -Target Previous).Summary.Failed | Should -Be 0
    }
}

Describe 'Optional Appx removal primitives with mocked Windows commands' {
    BeforeAll {
        $script:AddedGetAppx = -not (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)
        $script:AddedRemoveAppx = -not (Get-Command Remove-AppxPackage -ErrorAction SilentlyContinue)
        if ($script:AddedGetAppx) { function global:Get-AppxPackage { [CmdletBinding()]param([string]$Name) throw 'test stub must be mocked' } }
        if ($script:AddedRemoveAppx) { function global:Remove-AppxPackage { [CmdletBinding()]param([string]$Package) throw 'test stub must be mocked' } }
    }
    AfterAll {
        if ($script:AddedGetAppx) { Remove-Item Function:\Get-AppxPackage }
        if ($script:AddedRemoveAppx) { Remove-Item Function:\Remove-AppxPackage }
    }
    BeforeEach {
        $sys=New-LtTestSystem
        Mock -ModuleName LivnTools Test-LtLiveSystem { $true }
    }
    AfterEach { Remove-LtTestSystem $sys }
    It 'Refuses framework or non-removable packages before any removal' {
        Mock -ModuleName LivnTools Get-AppxPackage { [pscustomobject]@{Name='Microsoft.BingNews';PackageFullName='test_full';IsFramework=$true;IsResourcePackage=$false;NonRemovable=$false} }
        Mock -ModuleName LivnTools Remove-AppxPackage { throw 'must not remove' }
        { Remove-LtOptionalApp Microsoft.BingNews } | Should -Throw '*Korunan*'
        Should -Invoke -ModuleName LivnTools Remove-AppxPackage -Times 0 -Exactly
    }
    It 'Verifies absence and never uses all-users or provisioning removal' {
        $script:AppxGone=$false
        Mock -ModuleName LivnTools Get-AppxPackage {
            if (-not $script:AppxGone) { [pscustomobject]@{Name='Microsoft.BingNews';PackageFullName='test_full';IsFramework=$false;IsResourcePackage=$false;NonRemovable=$false} }
        }
        Mock -ModuleName LivnTools Remove-AppxPackage { $script:AppxGone=$true }
        (Remove-LtOptionalApp Microsoft.BingNews).Status | Should -Be Success
        Should -Invoke -ModuleName LivnTools Remove-AppxPackage -Times 1 -Exactly -ParameterFilter { $Package -eq 'test_full' }
        $body = (Get-Command Remove-LtOptionalApp).ScriptBlock.ToString()
        $body | Should -Not -Match '-AllUsers|Remove-AppxProvisionedPackage'
    }
    It 'Does not report success when the package survives removal' {
        Mock -ModuleName LivnTools Get-AppxPackage { [pscustomobject]@{Name='Microsoft.BingNews';PackageFullName='test_full';IsFramework=$false;IsResourcePackage=$false;NonRemovable=$false} }
        Mock -ModuleName LivnTools Remove-AppxPackage { }
        { Remove-LtOptionalApp Microsoft.BingNews } | Should -Throw '*doğrulanamadı*'
    }
}

Describe 'Setup catalog discovery' {
    It 'Has unique package IDs and complete browsing metadata' {
        $apps=@(Get-LtSetupApps)
        $apps.Count | Should -BeGreaterThan 30
        @($apps.Id | Select-Object -Unique).Count | Should -Be $apps.Count
        foreach ($app in $apps) {
            $app.Id | Should -Match '^[A-Za-z0-9+]+[.][A-Za-z0-9.+-]+$'
            $app.Category | Should -Not -BeNullOrEmpty
            $app.Description | Should -Not -BeNullOrEmpty
        }
    }
    It 'Finds Turkish text, literal symbols and combined category restrictions' {
        $apps=@(Get-LtSetupApps)
        @(Find-LtSetupApps -Apps $apps -Query 'iletisim').Count | Should -Be 3
        @(Find-LtSetupApps -Apps $apps -Query 'tarayici').Count | Should -Be 4
        (Find-LtSetupApps -Apps $apps -Query 'NOTEPAD++').Id | Should -Be 'Notepad++.Notepad++'
        @(Find-LtSetupApps -Apps $apps -Query 'Steam' -Category 'Tarayıcı').Count | Should -Be 0
        @(Find-LtSetupApps -Apps $apps -Query '[').Count | Should -Be 0
    }
    It 'Supports empty and selected-only views without changing the source' {
        $apps=@(Get-LtSetupApps)
        @(Find-LtSetupApps -Apps $apps -SelectedOnly).Count | Should -Be 0
        (Find-LtSetupApps -Apps $apps -SelectedOnly -SelectedIds @('Valve.Steam','unknown')).Id | Should -Be 'Valve.Steam'
        @(Find-LtSetupApps -Apps $apps).Count | Should -Be $apps.Count
    }
}
