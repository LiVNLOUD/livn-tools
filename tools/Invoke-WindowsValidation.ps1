<#
.SYNOPSIS
    Windows PowerShell 5.1 / WPF smoke checks, then Memory-backed Pester tests.
.DESCRIPTION
    Run with powershell.exe -NoProfile -STA -File tools\Invoke-WindowsValidation.ps1
    No administrator rights required. Does not invoke native setting setters.
    Creates and removes its own temporary data directory. Does not show a window.
    This is not a visual/DPI or live-system rollback acceptance test.
#>
[CmdletBinding()]
param([switch]$SmokeOnly)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'Windows is required. No validation was performed.'
}
if ($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1) {
    throw 'Run this script with Windows PowerShell 5.1 (powershell.exe), not pwsh.'
}
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    throw 'Use powershell.exe -NoProfile -STA -File tools\Invoke-WindowsValidation.ps1'
}
$root = Split-Path -Parent $PSScriptRoot
$dataRoot = Join-Path ([IO.Path]::GetTempPath()) ('lt-windows-validation-' + [guid]::NewGuid().ToString('N'))
$window = $null
$dialog = $null
try {
    Import-Module (Join-Path $root 'src\LivnTools.psm1') -Force -ErrorAction Stop
    Initialize-LivnTools -DataRoot $dataRoot -Backend Memory
    [void](Initialize-LtMemoryDemo)
    if ((Get-LtBackend) -ne 'Memory') { throw 'Expected Memory backend.' }

    # Compile against the real .NET Framework compiler. Do not call native setters.
    & (Get-Module LivnTools) {
        if (-not ('LivnTools.PowerCapabilities' -as [type])) { Add-Type -TypeDefinition $script:LtPowerCapabilitiesSource -Language CSharp }
        Initialize-LtUserSettingsNative
    }
    $caps = 'LivnTools.PowerCapabilities+Capabilities' -as [type]
    # PS 5.1 can bind SizeOf($caps) to the object overload and marshal
    # System.RuntimeType itself. Select SizeOf(Type) explicitly.
    $sizeOfType = [Runtime.InteropServices.Marshal].GetMethod('SizeOf', [type[]]@([type]))
    $capsSize = $sizeOfType.Invoke($null, [object[]]@($caps))
    if ($capsSize -ne 76 -or
        [Runtime.InteropServices.Marshal]::OffsetOf($caps, 'HiberFilePresent').ToInt32() -ne 8 -or
        [Runtime.InteropServices.Marshal]::OffsetOf($caps, 'HiberFileType').ToInt32() -ne 22) {
        throw 'Power capabilities interop layout is invalid.'
    }
    . (Join-Path $root 'src\UI\ViewModels.ps1')
    . (Join-Path $root 'src\UI\Dialogs.ps1')
    Initialize-LtViewModels
    Write-Host 'PASS: C# helpers compile under Windows PowerShell 5.1 / .NET Framework.'

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    $xamlPath = Join-Path $root 'src\UI\MainWindow.xaml'
    $window = [Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText($xamlPath))
    $dialog = [Windows.Markup.XamlReader]::Parse($script:LtReportXaml)
    # Use the application's own registered control list, without starting timers/jobs.
    $appText = [IO.File]::ReadAllText((Join-Path $root 'src\UI\App.ps1'))
    $match = [regex]::Match($appText, '(?s)\$names = @\((.*?)\)\s*\$controls')
    if (-not $match.Success) { throw 'Could not locate the application control list.' }
    $names = @([regex]::Matches($match.Groups[1].Value, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
    if ($names.Count -eq 0) { throw 'Application control list is empty.' }
    foreach ($name in $names) {
        if ($null -eq $window.FindName($name)) { throw "WPF control missing: $name" }
    }
    . (Join-Path $root 'src\UI\App.ps1')
    $script:Ui = @{}
    New-LtTweakItems
    New-LtCleanupItems
    $tweakGroups = @($script:Ui.TweakGroups.Values | ForEach-Object { $_ })
    $cleanupGroups = @($script:Ui.CleanupGroups.Values | ForEach-Object { $_ })
    $window.FindName('TweakGroups').ItemsSource = $tweakGroups
    $window.FindName('CleanupGroups').ItemsSource = $cleanupGroups
    foreach ($key in @('TweakTemplate','CleanupTemplate','TweakGroupTemplate','CleanupGroupTemplate')) {
        $template = $window.Resources[$key]
        if ($null -eq $template.LoadContent()) { throw "Template failed to instantiate: $key" }
    }
    # Instantiate the new control templates without opening a popup or touching Windows settings.
    $combo = $window.FindName('CmbInstalledPowerPlan')
    $combo.Style = $window.Resources[[Windows.Controls.ComboBox]]
    [void]$combo.ApplyTemplate()
    if ($null -eq $combo.Template.FindName('PART_Popup', $combo)) { throw 'ComboBox popup template is missing.' }
    foreach ($orientation in @('Vertical', 'Horizontal')) {
        $scrollbar = New-Object Windows.Controls.Primitives.ScrollBar
        $scrollbar.Orientation = $orientation
        $scrollbar.Style = $window.Resources[[Windows.Controls.Primitives.ScrollBar]]
        [void]$scrollbar.ApplyTemplate()
        $track = $scrollbar.Template.FindName('PART_Track', $scrollbar)
        if ($null -eq $track -or [string]$track.Orientation -ne $orientation) { throw "ScrollBar track failed: $orientation" }
        if ($track.IsDirectionReversed -ne ($orientation -eq 'Vertical')) { throw "ScrollBar direction failed: $orientation" }
    }
    Write-Host 'PASS: dark ComboBox and both ScrollBar templates instantiate.'
    $row = New-Object LivnTools.UI.ReportRow
    $row.Title = 'Memory validation'; $row.KindText = 'Preview'; $row.Message = 'No live system changes'
    $dialog.FindName('Rows').ItemsSource = @($row)
    # Collapsed panels are not measured by WPF. Exercise each optional panel
    # explicitly, with real catalog data, without starting application workers.
    # Wire the same setup handlers as the app, using actual WPF controls.
    # This exercises SelectionChanged/TextChanged reentrancy instead of control mocks.
    $script:Ui.C = @{}
    foreach ($name in $names) { $script:Ui.C[$name]=$window.FindName($name) }
    Initialize-LtSetupView
    $setupList = $window.FindName('SetupAppList')
    $search = $window.FindName('TxtSetupSearch')
    $category = $window.FindName('CmbSetupCategory')
    if (@(Get-LtChosenSetupApps).Count -ne 0) { throw 'Setup unexpectedly preselected an app.' }
    [void]$setupList.SelectedItems.Add(($script:Ui.SetupApps | Where-Object Id -eq 'Valve.Steam'))
    $search.Text = 'Firefox'
    if ($setupList.Items.Count -ne 1) { throw 'Setup search did not update from TextChanged.' }
    [void]$setupList.SelectedItems.Add($setupList.Items[0])
    $search.Text = 'NoMatchingPackageForValidation'
    if ($setupList.Items.Count -ne 0 -or @(Get-LtChosenSetupApps).Count -ne 2) { throw 'Setup lost hidden selections.' }
    $setupProfile = New-LtSetupProfile -PackageIds @((Get-LtChosenSetupApps).Id)
    Set-LtSetupPackageSelection -Ids @()
    Set-LtSetupPackageSelection -Ids @($setupProfile.PackageIds)
    $search.Text = ''
    if ($setupList.SelectedItems.Count -ne 2) { throw 'Setup profile selections were not restored.' }
    $category.SelectedItem = ($script:Ui.SetupApps | Where-Object Id -eq 'Mozilla.Firefox').Category
    if ($setupList.SelectedItems.Count -ne 1 -or @(Get-LtChosenSetupApps).Count -ne 2) { throw 'Setup category lost a hidden selection.' }
    $category.SelectedIndex = 0
    $selectedOnly=$window.FindName('ChkSetupSelected')
    $selectedOnly.IsChecked=$true
    $selectedOnly.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
    if ($setupList.Items.Count -ne 2) { throw 'Setup selected-only click did not filter.' }
    [void]$setupList.SelectedItems.Remove($setupList.SelectedItems[0])
    if ($setupList.Items.Count -ne 1 -or @(Get-LtChosenSetupApps).Count -ne 1) { throw 'Setup selected-only deselection failed.' }
    $window.FindName('BtnSetupClear').RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
    if ($setupList.Items.Count -ne 0 -or @(Get-LtChosenSetupApps).Count -ne 0) { throw 'Setup clear did not clear all selections.' }
    $selectedOnly.IsChecked=$false
    $selectedOnly.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
    Write-Host 'PASS: WPF setup search/category/selection events and profile selection restore (no installation).'
    # Inventory view with Memory data only (no winget process, no side job).
    $script:Ui.SetupInventory.Result = Get-LtSetupInventory
    Update-LtSetupInventoryView
    if (($script:Ui.SetupApps | Where-Object Id -eq 'Mozilla.Firefox').StateText -ne (Get-LtSetupStateText 'Installed')) { throw 'Setup inventory state was not applied.' }
    if (-not $window.FindName('TxtSetupInventory').Text) { throw 'Setup inventory status text is empty.' }
    $window.FindName('SetupAppList').UpdateLayout()
    Write-Host 'PASS: setup inventory states and status text (Memory, no WinGet process).'

    # Real WPF events: device selection (user bug 2 Oct). The app's own handlers are wired to the
    # actual ComboBoxes; selecting an item must reach the context through SelectionChanged.
    $wifiNic = @{ Name = 'Wi-Fi'; InterfaceGuid = '{bbbbbbbb-bbbb-cccc-dddd-eeeeeeeeeeee}'; Description = 'Validation Wi-Fi'; LinkSpeed = '866 Mbps'; InstanceId = 'PCI\WIFI\1' }
    (Get-LtMemoryState).DemoContext.Nics = @((Get-LtMemoryState).DemoContext.Nics) + @($wifiNic)
    $devCtx = Get-LtSystemContext -AppRoot $root
    if (@($devCtx.Nics).Count -lt 2) { throw 'Validation context needs two adapters.' }
    $script:Ui.Ctx = $devCtx; $script:Ui.StateLoaded = @{}; $script:Ui.CurrentPage = 'Validation'
    Initialize-LtDeviceSelectionView
    Set-LtDeviceChoicesView -Ctx $devCtx
    if ($devCtx.SelectedNicGuid) { throw 'Two adapters: no adapter may be auto-selected.' }
    if (-not (Get-LtTweakSupport (Get-LtTweak 'dns.cloudflare') $devCtx)) { throw 'DNS must be unavailable before an adapter is selected.' }
    $nicCombo = $window.FindName('CmbNetworkDevice')
    $nicCombo.SelectedIndex = 1
    if ($devCtx.SelectedNicGuid -ne $wifiNic.InterfaceGuid) { throw "Adapter selection did not reach the context (got '$($devCtx.SelectedNicGuid)')." }
    foreach ($id in @('dns.cloudflare', 'net.ackfreq')) {
        $why = Get-LtTweakSupport (Get-LtTweak $id) $devCtx
        if ($why) { throw "Selected adapter still blocks ${id}: $why" }
    }
    if ($window.FindName('TxtNetworkTarget').Text -notmatch 'Wi-Fi') { throw 'Selected adapter is not shown on the page.' }
    $nicCombo.SelectedItem = @($nicCombo.ItemsSource)[0]
    if ($devCtx.SelectedNicGuid -ne @($devCtx.Nics)[0].InterfaceGuid) { throw 'Selecting by SelectedItem did not update the context.' }
    $msiCombo = $window.FindName('CmbMsiDevice')
    if (@($msiCombo.ItemsSource).Count -gt 0) {
        $msiCombo.SelectedIndex = 0
        if (-not $devCtx.SelectedMsiInstanceId) { throw 'MSI selection did not reach the context.' }
    }
    # Re-reading system info keeps the previous selection (by GUID), without firing a refresh loop.
    $fresh = Get-LtSystemContext -AppRoot $root
    $script:Ui.Ctx = $fresh
    Set-LtDeviceChoicesView -Ctx $fresh -PreviousNic $devCtx.SelectedNicGuid -PreviousMsi ([string]$devCtx.SelectedMsiInstanceId)
    if ($fresh.SelectedNicGuid -ne $devCtx.SelectedNicGuid) { throw 'Adapter selection was lost after a context refresh.' }
    Write-Host 'PASS: real WPF SelectionChanged for adapter/MSI targets (Memory; no adapter setting applied).'

    # Recovery kit page with real checkboxes; kit is written to this run's temp directory only.
    $kitOptions = Get-LtKitOptionsFromUi
    foreach ($k in @('NetDrivers', 'OtherDrivers', 'Apps', 'Livn', 'Saves')) { if (-not $kitOptions[$k]) { throw "Kit default should include $k." } }
    foreach ($k in @('GpuDrivers', 'Wifi')) { if ($kitOptions[$k]) { throw "Kit default must not include $k." } }
    $kitTarget = Join-Path $dataRoot 'usb'
    [void][IO.Directory]::CreateDirectory($kitTarget)
    $kitOptions.Apps = $false
    $madeKit = New-LtRecoveryKit -Target $kitTarget -Options $kitOptions -Context $fresh -AppRoot $root -SystemDrive ''
    [void](Set-LtLoadedKit -Path $madeKit.Path)
    if ($window.FindName('TxtKitSummary').Text -notmatch 'DENEME') { throw 'Dry-run kit is not marked as DENEME in the UI.' }
    if (-not (Test-Path -LiteralPath (Join-Path $madeKit.Path 'LivnTools\src\RecoveryKit.ps1'))) { throw 'Kit does not contain a runnable Livn copy.' }
    Write-Host 'PASS: recovery kit defaults, dry-run kit creation and loading (temp folder; no pnputil/netsh).'

    $window.FindName('SetupRemoveList').ItemsSource = @(Get-LtSetupAppInventory)
    $window.FindName('SetupAppList').SelectedIndex = 0
    $window.FindName('SetupRemoveList').SelectedIndex = 0
    # Sistem Kontrolu ve Baslangic listeleri sahte sistemden doldurulur (salt okunur)
    $healthCtx = Get-LtSystemContext -AppRoot $root
    $window.FindName('HealthList').ItemsSource = @(ConvertTo-LtHealthViewItems @(Get-LtHealthReport -Facts (Get-LtHealthFacts -Context $healthCtx)))
    $window.FindName('StartupList').ItemsSource = @(Get-LtStartupItems)
    $window.FindName('StartupList').SelectedIndex = 0
    # Measure the content tree directly: an unshown Window has no native
    # handle and its own layout overrides may not arrange its child.
    $layoutRoot = $window.Content
    $reportRoot = $dialog.Content
    $layoutErrors = New-Object 'System.Collections.Generic.List[string]'
    $panelNames = @('ExternalToolsPanel','UserPreferencePanel','NetworkPanel','GraphicsPanel','SetupPanel','HistoryPanel','ScriptPanel','HealthPanel','StartupPanel','KitPanel')
    foreach ($scenario in @('Catalog') + $panelNames) {
        $scenarioOk = $true
        foreach ($panelName in $panelNames) {
            $window.FindName($panelName).Visibility = if ($panelName -eq $scenario) { 'Visible' } else { 'Collapsed' }
        }
        $catalogVisibility = if ($scenario -eq 'Catalog') { 'Visible' } else { 'Collapsed' }
        $window.FindName('TweakGroups').Visibility = $catalogVisibility
        $window.FindName('CleanupGroups').Visibility = $catalogVisibility
        foreach ($size in @(@(980,620), @(1240,820))) {
            try {
                $layoutRoot.Measure((New-Object Windows.Size($size[0],$size[1])))
                $layoutRoot.Arrange((New-Object Windows.Rect(0,0,$size[0],$size[1])))
                $layoutRoot.UpdateLayout()
                if ($layoutRoot.ActualWidth -le 0 -or $layoutRoot.ActualHeight -le 0) {
                    throw 'Main content root was not laid out.'
                }
                if ($scenario -ne 'Catalog') {
                    $panel = $window.FindName($scenario)
                    if ($panel.ActualWidth -le 0 -or $panel.ActualHeight -le 0) {
                        throw "Panel was not laid out: $scenario"
                    }
                }
                if ($scenario -eq 'HealthPanel') {
                    if ($null -eq $window.FindName('HealthList').ItemContainerGenerator.ContainerFromIndex(0)) { throw 'Health row was not instantiated.' }
                }
                if ($scenario -eq 'StartupPanel') {
                    if ($null -eq $window.FindName('StartupList').ItemContainerGenerator.ContainerFromIndex(0)) { throw 'Startup row was not instantiated.' }
                }
                if ($scenario -eq 'SetupPanel') {
                    # Profile controls are deliberately collapsed on entry; measure both states.
                    $profileSection=$window.FindName('SetupProfileSection')
                    $profileSection.IsExpanded=$true
                    $layoutRoot.Measure((New-Object Windows.Size($size[0],$size[1])))
                    $layoutRoot.Arrange((New-Object Windows.Rect(0,0,$size[0],$size[1])))
                    $layoutRoot.UpdateLayout()
                    if ($window.FindName('BtnProfileLoad').ActualHeight -le 0) { throw 'Expanded profile controls were not laid out.' }
                    $profileSection.IsExpanded=$false
                    $layoutRoot.Measure((New-Object Windows.Size($size[0],$size[1])))
                    $layoutRoot.Arrange((New-Object Windows.Rect(0,0,$size[0],$size[1])))
                    $layoutRoot.UpdateLayout()
                    foreach ($listName in @('SetupAppList','SetupRemoveList')) {
                        $list = $window.FindName($listName)
                        if ($null -eq $list.ItemContainerGenerator.ContainerFromIndex(0)) {
                            throw "Selected setup row was not instantiated: $listName"
                        }
                    }
                }
            } catch {
                $scenarioOk = $false
                $detail = "{0} at {1}x{2}: {3}" -f $scenario, $size[0], $size[1], $_.Exception.Message
                $layoutErrors.Add($detail)
                Write-Host "FAIL: $detail"
            }
        }
        if ($scenarioOk) { Write-Host "PASS: content layout $scenario at 980x620 and 1240x820 (no window frame)." }
    }
    try {
        $reportRoot.Measure((New-Object Windows.Size(860,640)))
        $reportRoot.Arrange((New-Object Windows.Rect(0,0,860,640)))
        $reportRoot.UpdateLayout()
        if ($reportRoot.ActualWidth -le 0 -or $reportRoot.ActualHeight -le 0) { throw 'Report content was not laid out.' }
        Write-Host 'PASS: report content layout.'
    } catch {
        $layoutErrors.Add('Report: ' + $_.Exception.Message)
        Write-Host ('FAIL: Report: ' + $_.Exception.Message)
    }
    Write-Host 'PASS: main/report XAML, registered controls and catalog template construction.'

    $ctx = Get-LtSystemContext -AppRoot $root
    $result = Invoke-LtApply -TweakIds 'game.mode' -Context $ctx
    if ($result.Results[0].Status -ne 'Success') { throw 'Memory apply failed.' }
    $result = Invoke-LtRevert -TweakIds 'game.mode' -Context $ctx -Target Previous
    if ($result.Results[0].Status -ne 'Success') { throw 'Memory rollback failed.' }
    if ((Get-LtBackend) -ne 'Memory') { throw 'Backend changed unexpectedly.' }
    Write-Host 'PASS: Memory apply and rollback. Live Windows settings were not exercised.'
    if ($layoutErrors.Count -gt 0) { throw ('Layout validation failed: ' + ($layoutErrors -join '; ')) }
} finally {
    if ($dialog) { $dialog.Close() }
    if ($window) { $window.Close() }
    # Only the unique directory allocated by this invocation is removed.
    if (Test-Path -LiteralPath $dataRoot) { Remove-Item -LiteralPath $dataRoot -Recurse -Force }
}
if (-not $SmokeOnly) {
    & (Join-Path $PSHOME 'powershell.exe') -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Invoke-Tests.ps1')
    if ($LASTEXITCODE -ne 0) { throw "Test suite failed (exit $LASTEXITCODE)." }
}
Write-Host 'Automated validation completed. Visual/DPI checks and real-system VM tests are still required.'
