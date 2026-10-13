BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    . (Join-Path $script:RepoRoot 'src/UI/ViewModels.ps1')
    . (Join-Path $script:RepoRoot 'src/UI/App.ps1')
    . (Join-Path $script:RepoRoot 'src/UI/Dialogs.ps1')
    Initialize-LtViewModels
    if (-not ('LtNavigationItemsControl' -as [type])) {
        Add-Type 'public class LtNavigationItemsControl { public System.Collections.IEnumerable ItemsSource { get; set; } }'
    }
}
Describe 'Navigation preserves WPF collection bindings' {
    BeforeEach {
        $sys = New-LtTestSystem
        $controls = @{}
        $app = [IO.File]::ReadAllText((Join-Path $script:RepoRoot 'src/UI/App.ps1'))
        $m = [regex]::Match($app, '(?s)\$names = @\((.*?)\)\s*\$controls')
        foreach ($n in [regex]::Matches($m.Groups[1].Value, "'([^']+)'")) {
            $control = [pscustomobject]@{ Text=''; Content=''; Visibility='Visible'; IsChecked=$false; IsEnabled=$true; SelectedIndex=-1; Value=0; IsIndeterminate=$false; ItemsSource=$null }
            $control | Add-Member -MemberType ScriptMethod -Name ScrollToTop -Value { }
            $controls[$n.Groups[1].Value] = $control
        }
        $controls.TweakGroups = New-Object LtNavigationItemsControl
        $controls.CleanupGroups = New-Object LtNavigationItemsControl
        $script:Ui = @{ C=$controls; Ctx=$sys.Ctx; CurrentPage=''; StateLoaded=@{}; ActivePlan=''; Tweaks=@{}; TweakGroups=@{}; Cleanups=@{}; CleanupGroups=@{} }
        New-LtTweakItems
        New-LtCleanupItems
        Mock Update-LtPageState { }
        Mock Update-LtHistory { }
    }
    AfterEach { Remove-LtTestSystem $sys }
    It 'Navigates all pages with <Count> groups without scalar conversion or losing collection identity' -ForEach @(@{Count=0},@{Count=1},@{Count=3}) {
        foreach ($catalog in @($script:Ui.TweakGroups,$script:Ui.CleanupGroups)) {
            foreach ($key in @($catalog.Keys)) {
                $groups = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
                for ($i=0; $i -lt $Count; $i++) { $groups.Add((New-Object LivnTools.UI.Group)) }
                $catalog[$key] = $groups
            }
        }
        foreach ($page in $script:LtPages.Keys) {
            { Show-LtPage -Page $page } | Should -Not -Throw
            if ($script:LtOptPages -contains $page) {
                [object]::ReferenceEquals($controls.TweakGroups.ItemsSource,$script:Ui.TweakGroups[$page]) | Should -BeTrue
            } else { $controls.TweakGroups.ItemsSource | Should -BeNullOrEmpty }
            if ($script:Ui.CleanupGroups.ContainsKey($page)) {
                [object]::ReferenceEquals($controls.CleanupGroups.ItemsSource,$script:Ui.CleanupGroups[$page]) | Should -BeTrue
            } else { $controls.CleanupGroups.ItemsSource | Should -BeNullOrEmpty }
            $expected = if ($script:LtPages[$page].Kind -eq 'Cleanup') { 'Visible' } else { 'Collapsed' }
            $controls.ChkCleanupAvailable.Visibility | Should -Be $expected
            if ($page -eq 'Performance') {
                $controls.TxtPageInfo.Text | Should -Not -Match 'Launcher'
                $controls.TxtPageInfo.Text | Should -Match 'CPU'
            }
        }
    }
    It 'Switches the real catalog through cleanup, performance, setup and back' {
        foreach ($filter in @($true,$false)) {
            $controls.ChkCleanupAvailable.IsChecked = $filter
            foreach ($page in @('QuickClean','Performance','Setup','QuickClean')) {
                { Show-LtPage $page } | Should -Not -Throw
                $script:Ui.CurrentPage | Should -Be $page
            }
        }
    }
    It 'Shows named demo plans without selecting or applying one' {
        $before = Get-LtActivePowerScheme
        Set-LtPowerPlanChoicesView -Plans @(Get-LtPowerPlanChoices)
        $controls.CmbInstalledPowerPlan.IsEnabled | Should -BeTrue
        $controls.CmbInstalledPowerPlan.SelectedIndex | Should -Be -1
        $script:Ui.Ctx.SelectedPowerPlanGuid | Should -BeNullOrEmpty
        $script:Ui.Tweaks['power.installed'].Selected | Should -BeFalse
        $controls.TxtPowerPlanStatus.Text | Should -Match 'Deneme'
        (Get-LtActivePowerScheme) | Should -Be $before
    }
    It 'Keeps an empty or failed power plan list disabled after the busy state ends' {
        Set-LtPowerPlanChoicesView -Plans @()
        Set-LtBusy $false
        $controls.CmbInstalledPowerPlan.IsEnabled | Should -BeFalse
        $controls.TxtPowerPlanStatus.Text | Should -Match 'bulunamad'
        Set-LtPowerPlanChoicesView -ErrorText 'test error'
        Set-LtBusy $false
        $controls.CmbInstalledPowerPlan.IsEnabled | Should -BeFalse
        $controls.TxtPowerPlanStatus.Text | Should -Match 'test error'
    }

}

Describe 'Setup selections survive filtering' {
    BeforeEach {
        $script:Ui = @{
            SetupApps=@(Get-LtSetupApps); SetupSelected=@{}; SetupBinding=$false
            C=@{
                SetupAppList=[pscustomobject]@{ItemsSource=@();SelectedItems=(New-Object System.Collections.ArrayList)}
                TxtSetupSearch=[pscustomobject]@{Text=''}
                CmbSetupCategory=[pscustomobject]@{SelectedItem='Tümü'}
                ChkSetupSelected=[pscustomobject]@{IsChecked=$false}
                TxtSetupSelection=[pscustomobject]@{Text=''}
            }
        }
        Update-LtSetupAppsView
    }
    It 'Reviews and submits all selected packages even when the view is filtered' {
        $script:Ui.Window=$null
        $script:Ui.SetupSelected=@{'Valve.Steam'=$true;'Mozilla.Firefox'=$true}
        $script:Ui.C.TxtSetupSearch.Text='Firefox'
        Update-LtSetupAppsView
        Mock Test-LtLiveSystem { $false }
        Mock Show-LtReportDialog { @{Confirmed=$true} }
        Mock Start-LtJob { $true }
        Invoke-LtSetupUiAction -Mode Install
        Should -Invoke Show-LtReportDialog -Times 1 -Exactly -ParameterFilter {
            $Rows.Count -eq 2 -and $Rows.Title -contains 'Steam' -and $OkText -eq 'Simüle et'
        }
        Should -Invoke Start-LtJob -Times 1 -Exactly -ParameterFilter {
            $JobArgs.Ids.Count -eq 2 -and $JobArgs.Ids -contains 'Valve.Steam'
        }
    }
    It 'Starts no job if the application review is cancelled' {
        $script:Ui.Window=$null
        $script:Ui.SetupSelected=@{'Valve.Steam'=$true}
        Mock Test-LtLiveSystem { $false }
        Mock Show-LtReportDialog { @{Confirmed=$false} }
        Mock Start-LtJob { throw 'cancelled review started a job' }
        Invoke-LtSetupUiAction -Mode Install
        Should -Invoke Start-LtJob -Times 0 -Exactly
    }
    It 'Restores profile choices under an empty filter and rejects unknown IDs without losing selections' {
        $script:Ui.C.TxtSetupSearch.Text='NoMatchingPackage'
        Update-LtSetupAppsView
        Set-LtSetupPackageSelection -Ids @('Valve.Steam','Mozilla.Firefox','Valve.Steam')
        @(Get-LtChosenSetupApps).Count | Should -Be 2
        @($script:Ui.C.SetupAppList.ItemsSource).Count | Should -Be 0
        { Set-LtSetupPackageSelection -Ids @('7zip.7zip','unknown.package') } | Should -Throw
        @(Get-LtChosenSetupApps).Count | Should -Be 2
        (Get-LtChosenSetupApps).Id | Should -Contain 'Valve.Steam'
        $script:Ui.C.TxtSetupSearch.Text=''
        Update-LtSetupAppsView
        $script:Ui.C.SetupAppList.SelectedItems.Count | Should -Be 2
        Set-LtSetupPackageSelection -Ids @()
        @(Get-LtChosenSetupApps).Count | Should -Be 0
        $script:Ui.C.SetupAppList.SelectedItems.Count | Should -Be 0
    }
    It 'Starts empty and retains hidden selections for install and profile export' {
        @(Get-LtChosenSetupApps).Count | Should -Be 0
        $steam=$script:Ui.SetupApps | Where-Object Id -eq 'Valve.Steam'
        [void]$script:Ui.C.SetupAppList.SelectedItems.Add($steam)
        Sync-LtSetupSelection
        $script:Ui.C.TxtSetupSearch.Text='Firefox'
        Update-LtSetupAppsView
        $firefox=$script:Ui.C.SetupAppList.ItemsSource[0]
        [void]$script:Ui.C.SetupAppList.SelectedItems.Add($firefox)
        Sync-LtSetupSelection
        @(Get-LtChosenSetupApps).Count | Should -Be 2
        $script:Ui.C.TxtSetupSelection.Text | Should -Match 'Filtre dışında seçili: 1'
        $profile=New-LtSetupProfile -PackageIds @((Get-LtChosenSetupApps).Id)
        $profile.PackageIds | Should -Contain 'Valve.Steam'
        $profile.PackageIds | Should -Contain 'Mozilla.Firefox'
        $script:Ui.C.TxtSetupSearch.Text='no matches expected'
        Update-LtSetupAppsView
        @($script:Ui.C.SetupAppList.ItemsSource).Count | Should -Be 0
        @(Get-LtChosenSetupApps).Count | Should -Be 2
        $script:Ui.C.TxtSetupSearch.Text=''
        Update-LtSetupAppsView
        $script:Ui.C.SetupAppList.SelectedItems.Count | Should -Be 2
    }
    It 'Deselects visible rows without losing hidden rows and clears all explicitly' {
        $script:Ui.SetupSelected=@{'Valve.Steam'=$true;'Mozilla.Firefox'=$true}
        $script:Ui.C.CmbSetupCategory.SelectedItem='Tarayıcı'
        Update-LtSetupAppsView
        $script:Ui.C.SetupAppList.SelectedItems.Clear()
        Sync-LtSetupSelection
        (Get-LtChosenSetupApps).Id | Should -Be 'Valve.Steam'
        $script:Ui.SetupSelected.Clear()
        Update-LtSetupAppsView
        @(Get-LtChosenSetupApps).Count | Should -Be 0
    }
    It 'Ignores selection notifications during rebinding and refreshes selected-only rows' {
        $script:Ui.SetupSelected=@{'Valve.Steam'=$true}
        $script:Ui.SetupBinding=$true
        Sync-LtSetupSelection
        (Get-LtChosenSetupApps).Id | Should -Be 'Valve.Steam'
        $script:Ui.SetupBinding=$false
        $script:Ui.C.ChkSetupSelected.IsChecked=$true
        Update-LtSetupAppsView
        @($script:Ui.C.SetupAppList.ItemsSource).Count | Should -Be 1
        $script:Ui.C.SetupAppList.SelectedItems.Clear()
        Sync-LtSetupSelection
        @($script:Ui.C.SetupAppList.ItemsSource).Count | Should -Be 0
    }
}
