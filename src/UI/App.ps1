# Livn Tools - UI/App.ps1
# WPF arayuzu. Sistem degistiren her is ARKA PLAN runspace'inde calisir; UI
# is parcacigi yalnizca DispatcherTimer ile kuyruklari okur (donma ve
# Dispatcher.Invoke kilitlenmesi yok). Ayni anda tek is calisir.

# NOT: UI betiklerinde StrictMode kapali tutulur; bir olay isleyicisindeki beklenmeyen
# $null ozelligi tum pencereyi kapatmasin. Motor modulu (src/*) StrictMode ile calisir.

$script:Ui = $null   # tum UI durumu tek hashtable'da

$script:LtPages = [ordered]@{
    Health        = @{ Title = 'Sistem Kontrolü'; Desc = 'Format sonrası ve oyun öncesi kontrol: sürücüler, ekran yenileme hızı, RAM, disk, çökme kayıtları, ağ ve oyun ayarları. Salt okunurdur; hiçbir ayarı değiştirmez.'; Kind = 'Health' }
    QuickClean    = @{ Title = 'Hızlı Temizlik'; Desc = 'Geçici dosyalar ve uygulama önbellekleri. Silinen dosyalar GERİ ALINAMAZ; yalnızca gerçekten silinen boyut raporlanır.'; Kind = 'Cleanup' }
    AdvancedClean = @{ Title = 'Gelişmiş Temizlik'; Desc = 'Bileşen deposu, sistem onarımı ve disk temizleme. Uzun sürebilir; geri alınamaz.'; Kind = 'Cleanup' }
    Performance   = @{ Title = 'Performans'; Desc = 'Güç planı, zamanlayıcı, CPU zamanlaması ve servisler. Ölçüm yapmadan FPS/gecikme kazancı varsaymayın.'; Kind = 'Tweak' }
    Network       = @{ Title = 'Ağ'; Desc = 'TCP/IP genel ayarları, adaptör sürücü ayarları ve ad çözümleme.'; Kind = 'Tweak' }
    Kernel        = @{ Title = 'Güvenlik ve Giriş'; Desc = 'İleri düzey güvenlik özellikleri, bellek ve fare. Güvenlik özelliklerini kapatan seçenekler hiçbir hazır seçime dahil değildir.'; Kind = 'Tweak' }
    GPU           = @{ Title = 'GPU ve MSI'; Desc = 'Grafik zamanlaması ve MSI kesme modu. MSI ayarları aygıtın donanım anahtarına yazılır.'; Kind = 'Tweak' }
    Privacy       = @{ Title = 'Gizlilik'; Desc = 'Telemetri servisleri, Grup İlkesi değerleri ve kullanıcı gizlilik ayarları.'; Kind = 'Tweak' }
    WinTweaks     = @{ Title = 'Windows Ayarları'; Desc = 'Görsel, Explorer ve sistem davranışı tercihleri.'; Kind = 'Tweak' }
    Kit           = @{ Title = 'Kurtarma Kiti'; Desc = 'Formattan önce sürücüleri, uygulama listesini, Livn ayarlarını ve oyun kayıtlarını USB belleğe alın; formattan sonra internet olmasa bile önce ağ sürücüsünü kurun.'; Kind = 'Kit' }
    Startup       = @{ Title = 'Başlangıç Uygulamaları'; Desc = 'Windows açılışında başlayan uygulamaları görün; gereksizleri Görev Yöneticisi ile aynı yöntemle kapatın. Geri alınabilir.'; Kind = 'Startup' }
    Setup         = @{ Title = 'Format Sonrası'; Desc = 'Uygulamaları seçin, kurun; kişisel format profilinizi kaydedin veya yükleyin.'; Kind = 'Setup' }
    History       = @{ Title = 'Değişiklik Geçmişi'; Desc = 'Livn Tools''un değiştirdiği ayarlar, özgün değerleri ve işlem günlüğü. Buradan tek tek geri alabilirsiniz.'; Kind = 'History' }
    RunScript     = @{ Title = 'Betik Çalıştır'; Desc = '.ps1 / .bat / .cmd betiklerini içe aktarın, inceleyin ve çalıştırın.'; Kind = 'Script' }
}
$script:LtOptPages = @('Performance', 'Network', 'Kernel', 'GPU', 'Privacy', 'WinTweaks')

$script:LtStateText = @{ Applied = 'Uygulanmış'; NotApplied = 'Uygulanmamış'; Partial = 'Kısmen uygulanmış'; NotSupported = 'Desteklenmiyor'; Unknown = 'Okunamadı'; Loading = 'Okunuyor…' }
$script:LtRiskText  = @{ Low = 'Düşük risk'; Medium = 'Orta risk'; High = 'Yüksek risk'; Security = 'GÜVENLİĞİ AZALTIR' }
$script:LtEvidenceText = @{ Documented = 'Belgelenmiş'; Community = 'Topluluk bilgisi'; Unverified = 'Doğrulanmamış fayda' }

# ---------------------------------------------------------------------------
# Yardimcilar
# ---------------------------------------------------------------------------
function Set-LtStatus([string]$Text) { $script:Ui.C.TxtStatus.Text = $Text }

function Add-LtLogLine([string]$Line) {
    $box = $script:Ui.C.LogBox
    $box.AppendText($Line + [Environment]::NewLine)
    if ($box.Text.Length -gt 400000) {
        $t = $box.Text
        $cut = $t.IndexOf("`n", $t.Length - 300000)
        if ($cut -gt 0) { $box.Text = $t.Substring($cut + 1) }
    }
    $box.ScrollToEnd()
}

function Set-LtBusy([bool]$Busy) {
    $c = $script:Ui.C
    foreach ($n in @('BtnApply', 'BtnRevertPrev', 'BtnRevertDefault', 'BtnBackupState', 'BtnRefresh', 'BtnRunCleanup', 'BtnCleanupPreview', 'BtnApplyAllPages',
                     'BtnPresetMinimal', 'BtnPresetStandard', 'BtnPresetAggressive', 'BtnPresetResponsive', 'BtnPresetMaxPerf', 'BtnProfileSave', 'BtnProfileLoad', 'BtnProfileApply', 'BtnSetupInstall', 'BtnSetupScan', 'BtnSetupRemove', 'SetupAppList', 'TxtSetupSearch', 'CmbSetupCategory', 'ChkSetupSelected', 'BtnSetupClear', 'SetupRemoveList', 'BtnPresetClear', 'BtnRecoveryRevert', 'BtnRecoveryKeep',
                     'BtnHistoryRevert', 'BtnHistoryRestoreFile', 'BtnHistoryLegacyReg', 'BtnScriptRun', 'BtnGraphicsSettings', 'BtnReadGraphics', 'CmbMsiDevice', 'CmbNetworkDevice', 'CmbMenuDelay', 'BtnExternalTool', 'BtnWindowsPower', 'BtnSelectIslc', 'BtnRefreshPowerPlans', 'CmbInstalledPowerPlan',
                     'BtnPresetGamer', 'BtnHealthRun', 'BtnHealthGamer', 'BtnHealthSave', 'BtnStartupDisable', 'BtnStartupEnable', 'BtnStartupRefresh', 'BtnPingRun', 'BtnDnsRun', 'BtnGpuAddGame', 'BtnGpuClearGames',
                     'BtnKitBrowse', 'BtnKitPreview', 'BtnKitCreate', 'BtnKitFind', 'BtnKitOpen', 'BtnKitDrivers', 'BtnKitWifi', 'BtnKitApps', 'BtnKitTweaks', 'BtnKitSaves')) {
        if ($c[$n]) { $c[$n].IsEnabled = -not $Busy }
    }
    if ($c.CmbInstalledPowerPlan) {
        $c.CmbInstalledPowerPlan.IsEnabled = (-not $Busy -and $null -ne $c.CmbInstalledPowerPlan.ItemsSource -and @($c.CmbInstalledPowerPlan.ItemsSource).Count -gt 0)
    }
    $c.ProgressPanel.Visibility = if ($Busy) { 'Visible' } else { 'Collapsed' }
    $c.BtnCancel.IsEnabled = $Busy
    $c.BtnCancel.Content = 'İptal (Esc)'
    if ($Busy) { $c.ProgMain.Value = 0; $c.ProgMain.IsIndeterminate = $true }
}

# ---------------------------------------------------------------------------
# Arka plan isleri
# ---------------------------------------------------------------------------
$script:LtJobBootstrap = {
    param($ModulePath, $DataRoot, $Backend, $LogQueue, $MemState, $BodyText, $JobArgs, $Progress, $Cancel)
    $ErrorActionPreference = 'Stop'
    # Kalici is parcacigi runspace'i: modul yalnizca ilk iste yuklenir
    if (-not (Get-Module -Name LivnTools)) {
        Import-Module $ModulePath -DisableNameChecking
        Initialize-LivnTools -DataRoot $DataRoot -Backend $Backend -LogQueue $LogQueue
        if ($Backend -eq 'Memory' -and $null -ne $MemState) { Set-LtMemoryState $MemState }
    }
    $body = [scriptblock]::Create($BodyText)
    & $body $JobArgs $Progress $Cancel
}

function Get-LtWorkerRunspace {
    $rs = $script:Ui.WorkerRS
    if ($rs -and $rs.RunspaceStateInfo.State -eq 'Opened') { return $rs }
    if ($rs) { try { $rs.Dispose() } catch { $null = $_ } }
    $rs = [RunspaceFactory]::CreateRunspace()
    $rs.ApartmentState = 'STA'
    $rs.ThreadOptions = 'ReuseThread'
    $rs.Open()
    $script:Ui.WorkerRS = $rs
    return $rs
}

function Start-LtJob {
    <#
      Isi arka planda baslatir. -Body TEK nesne dondurmelidir (dizi donecekse
      hashtable icine sarilir). -OnDone UI is parcaciginda ($sonuc, $hatalar) ile cagrilir.
      Mesgulken yeni is baslatilmaz ($false doner).
    #>
    param([Parameter(Mandatory)][string]$Title, [Parameter(Mandatory)][scriptblock]$Body, [hashtable]$JobArgs = @{}, [scriptblock]$OnDone = $null, [switch]$Quiet)
    if ($script:Ui.Job) { Set-LtStatus 'Başka bir işlem sürüyor; lütfen bitmesini bekleyin.'; return $false }
    $progress = [hashtable]::Synchronized(@{ Done = 0; Total = 0; Text = $Title })
    $cancel = [hashtable]::Synchronized(@{ Requested = $false })
    $ps = [PowerShell]::Create()
    $ps.Runspace = Get-LtWorkerRunspace
    $mem = $null
    if ((Get-LtBackend) -eq 'Memory') { $mem = Get-LtMemoryState }
    [void]$ps.AddScript($script:LtJobBootstrap.ToString()).
        AddArgument($script:Ui.ModulePath).AddArgument($script:Ui.DataRoot).AddArgument((Get-LtBackend)).
        AddArgument($script:Ui.LogQueue).AddArgument($mem).AddArgument($Body.ToString()).
        AddArgument($JobArgs).AddArgument($progress).AddArgument($cancel)
    $handle = $ps.BeginInvoke()
    $script:Ui.Job = @{ PS = $ps; Handle = $handle; OnDone = $OnDone; Progress = $progress; Cancel = $cancel; Title = $Title; Quiet = [bool]$Quiet }
    if (-not $Quiet) { Set-LtBusy $true }
    $script:Ui.C.TxtProgress.Text = $Title
    Set-LtStatus $Title
    return $true
}

function Complete-LtJobIfDone {
    $job = $script:Ui.Job
    if (-not $job) { return }
    $p = $job.Progress
    if (-not $job.Quiet) {
        $c = $script:Ui.C
        if ($p.Total -gt 0) {
            $c.ProgMain.IsIndeterminate = $false
            $c.ProgMain.Value = [math]::Min(100, [math]::Round(100 * $p.Done / $p.Total))
            $c.TxtProgress.Text = ('{0}  ({1}/{2})' -f $p.Text, [math]::Min($p.Done + 1, $p.Total), $p.Total)
        } elseif ($p.Text) { $c.TxtProgress.Text = $p.Text }
    }
    if (-not $job.Handle.IsCompleted) { return }
    $out = $null; $errs = @()
    try { $out = $job.PS.EndInvoke($job.Handle) }
    catch {
        $ex = $_.Exception
        while ($ex.InnerException) { $ex = $ex.InnerException }
        $errs += $ex.Message
    }
    try { foreach ($e in $job.PS.Streams.Error) { $errs += [string]$e } } catch { $null = $_ }
    try { $job.PS.Dispose() } catch { $null = $_ }
    $script:Ui.Job = $null
    Set-LtBusy $false
    foreach ($e in $errs) { Add-LtLogLine ("{0}  [ERROR]  Arka plan işi hatası ({1}): {2}" -f (Get-Date -Format 'HH:mm:ss'), $job.Title, $e) }
    $last = $null
    if ($out -and $out.Count -gt 0) { $last = $out[$out.Count - 1] }
    if ($job.OnDone) {
        try { & $job.OnDone $last @($errs) }
        catch { Add-LtLogLine ("{0}  [ERROR]  Sonuç işlenemedi: {1}" -f (Get-Date -Format 'HH:mm:ss'), $_.Exception.Message) }
    }
    if ($errs.Count -gt 0) { Set-LtStatus "$($job.Title): hata oluştu (günlüğe bakın)." }
    Invoke-LtNextQueued
}

function Invoke-LtNextQueued {
    # Mesgulken istenen durum yenilemeleri sirayla calistirilir
    if ($script:Ui.Job -or $script:Ui.RefreshQueue.Count -eq 0) { return }
    $page = $script:Ui.RefreshQueue[0]
    $script:Ui.RefreshQueue.RemoveAt(0)
    Update-LtPageState -Page $page
}

# ---------------------------------------------------------------------------
# Ikincil salt okunur arka plan isi (ornek: WinGet envanteri)
# ---------------------------------------------------------------------------
# Ana is kuyrugunu (ayar/temizlik/kurulum) bloklamamak icin AYRI runspace'te
# calisir. Yalniz salt okunur islevler icin kullanilir; tek yuva vardir.
function Start-LtSideJob {
    param([Parameter(Mandatory)][string]$Title, [Parameter(Mandatory)][scriptblock]$Body, [hashtable]$JobArgs = @{}, [scriptblock]$OnDone = $null)
    if ($script:Ui.SideJob) { return $false }
    $rs = [RunspaceFactory]::CreateRunspace()
    $rs.ApartmentState = 'STA'
    $rs.Open()
    $ps = [PowerShell]::Create()
    $ps.Runspace = $rs
    $mem = $null
    if ((Get-LtBackend) -eq 'Memory') { $mem = Get-LtMemoryState }
    $progress = [hashtable]::Synchronized(@{ Done = 0; Total = 0; Text = $Title })
    $cancel = [hashtable]::Synchronized(@{ Requested = $false })
    [void]$ps.AddScript($script:LtJobBootstrap.ToString()).
        AddArgument($script:Ui.ModulePath).AddArgument($script:Ui.DataRoot).AddArgument((Get-LtBackend)).
        AddArgument($script:Ui.LogQueue).AddArgument($mem).AddArgument($Body.ToString()).
        AddArgument($JobArgs).AddArgument($progress).AddArgument($cancel)
    $script:Ui.SideJob = @{ PS = $ps; RS = $rs; Handle = $ps.BeginInvoke(); OnDone = $OnDone; Title = $Title; Cancel = $cancel }
    return $true
}

function Complete-LtSideJobIfDone {
    $job = $script:Ui.SideJob
    if (-not $job -or -not $job.Handle.IsCompleted) { return }
    $out = $null; $errs = @()
    try { $out = $job.PS.EndInvoke($job.Handle) }
    catch {
        $ex = $_.Exception
        while ($ex.InnerException) { $ex = $ex.InnerException }
        $errs += $ex.Message
    }
    try { foreach ($e in $job.PS.Streams.Error) { $errs += [string]$e } } catch { $null = $_ }
    try { $job.PS.Dispose() } catch { $null = $_ }
    try { $job.RS.Close(); $job.RS.Dispose() } catch { $null = $_ }
    $script:Ui.SideJob = $null
    $last = $null
    if ($out -and $out.Count -gt 0) { $last = $out[$out.Count - 1] }
    if ($job.OnDone) {
        try { & $job.OnDone $last @($errs) }
        catch { Add-LtLogLine ("{0}  [ERROR]  Sonuç işlenemedi ({1}): {2}" -f (Get-Date -Format 'HH:mm:ss'), $job.Title, $_.Exception.Message) }
    }
}

# ---------------------------------------------------------------------------
# Gorunum modelleri
# ---------------------------------------------------------------------------
function New-LtTweakItems {
    $script:Ui.Tweaks = @{}
    $script:Ui.TweakGroups = @{}
    foreach ($page in $script:LtOptPages) { $script:Ui.TweakGroups[$page] = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]' }
    foreach ($t in @(Get-LtCatalog)) {
        $i = New-Object LivnTools.UI.TweakItem
        $i.Id = $t.Id; $i.Page = $t.Page; $i.GroupName = $t.Group; $i.Title = $t.Title; $i.Description = $t.Description
        $i.Risk = $t.Risk; $i.RiskText = $script:LtRiskText[$t.Risk]; $i.Evidence = $t.Evidence
        $i.EvidenceText = $script:LtEvidenceText[$t.Evidence]
        $i.RestartText = Get-LtRestartText $t.Restart
        $i.Exclusive = [string](Get-LtProp $t 'Exclusive' '')
        $i.Warning = [string](Get-LtProp $t 'Warning' '')
        $i.Sources = (@(Get-LtProp $t 'Sources' @()) -join '  ')
        $i.add_PropertyChanged({
            param($s, $e)
            if ($e.PropertyName -eq 'Selected' -and $s.Selected -and $s.Exclusive) {
                foreach ($o in $script:Ui.Tweaks.Values) { if ($o.Exclusive -eq $s.Exclusive -and $o.Id -ne $s.Id -and $o.Selected) { $o.Selected = $false } }
            }
        })
        $script:Ui.Tweaks[$t.Id] = $i
        # Gizli ayarlar (ornek: Baslangic sayfasinin secime bagli eylemleri) listede gosterilmez
        if (Get-LtProp $t 'Hidden' $false) { continue }
        $groups = $script:Ui.TweakGroups[$t.Page]
        $g = $null
        foreach ($x in $groups) { if ($x.Name -eq $t.Group) { $g = $x; break } }
        if (-not $g) { $g = New-Object LivnTools.UI.Group; $g.Name = $t.Group; $groups.Add($g) }
        $g.Items.Add($i)
    }
}

function New-LtCleanupItems {
    $script:Ui.Cleanups = @{}
    $script:Ui.CleanupGroups = @{}
    foreach ($c in @(Get-LtCleanupCatalog)) {
        $i = New-Object LivnTools.UI.CleanupItem
        $i.Id = $c.Id; $i.Page = $c.Page; $i.GroupName = $c.Group; $i.Title = $c.Title; $i.Description = $c.Description
        $i.Warning = [string](Get-LtProp $c 'Warning' ''); $i.LongRunning = [bool](Get-LtProp $c 'LongRunning' $false)
        $script:Ui.Cleanups[$c.Id] = $i
        if (-not $script:Ui.CleanupGroups.ContainsKey($c.Page)) { $script:Ui.CleanupGroups[$c.Page] = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]' }
        $groups = $script:Ui.CleanupGroups[$c.Page]
        $g = $null
        foreach ($x in $groups) { if ($x.Name -eq $c.Group) { $g = $x; break } }
        if (-not $g) { $g = New-Object LivnTools.UI.Group; $g.Name = $c.Group; $groups.Add($g) }
        $g.Items.Add($i)
    }
}

function Update-LtCleanupGroupsView {
    $page = $script:Ui.CurrentPage
    if (-not $script:Ui.CleanupGroups.ContainsKey($page)) { return }
    if (-not $script:Ui.C.ChkCleanupAvailable.IsChecked) { $script:Ui.C.CleanupGroups.ItemsSource=$script:Ui.CleanupGroups[$page]; return }
    $groups = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
    foreach ($group in $script:Ui.CleanupGroups[$page]) {
        $available = @($group.Items | Where-Object { $_.IsAvailable })
        if ($available.Count -eq 0) { continue }
        $g = New-Object LivnTools.UI.Group; $g.Name=$group.Name
        foreach ($item in $available) { $g.Items.Add($item) }
        $groups.Add($g)
    }
    $script:Ui.C.CleanupGroups.ItemsSource=$groups
}

function Update-LtCleanupAvailability {
    # Uygulama tespiti hizlidir (registry + yol); UI is parcaciginda yapilir
    foreach ($c in @(Get-LtCleanupCatalog)) {
        $vm = $script:Ui.Cleanups[$c.Id]
        $why = $null
        try { $why = Get-LtCleanupAvailability $c $script:Ui.Ctx } catch { $why = "Kontrol edilemedi: $($_.Exception.Message)" }
        $vm.IsAvailable = -not $why
        $vm.Reason = if ($why) { $why } else { '' }
        if ($why) { $vm.Selected = $false }
        elseif ($c.Page -eq 'QuickClean' -and -not $script:Ui.CleanupInit) { $vm.Selected = [bool](Get-LtProp $c 'Default' $false) }
    }
    $script:Ui.CleanupInit = $true
    if ($script:Ui.CurrentPage -eq 'QuickClean') { Update-LtCleanupGroupsView }
}

function Get-LtMsiDeviceChoices {
    <# Aygit kimligi yalniz secim anahtari olarak tutulur; etikette gosterilmez. #>
    param($Ctx)
    $devices = @($Ctx.MsiDevices | Where-Object { $_.Class -in @('GPU','NIC') })
    $seen = @{}
    foreach ($d in $devices) {
        $kind = if ($d.Class -eq 'GPU') { 'Ekran kartı' } else { 'Ağ kartı' }
        $name = if ([string]$d.Name) { [string]$d.Name } else { 'Adsız aygıt' }
        $base = "$kind — $name"
        $seen[$base] = 1 + [int]$(if ($seen.ContainsKey($base)) { $seen[$base] } else { 0 })
        $label = if ($seen[$base] -gt 1) { "$base ($($seen[$base]))" } else { $base }
        $support = Format-LtInterruptSupport (Get-LtProp $d 'InterruptSupport' $null)
        $label += if ($support -eq 'Unknown') { ' · MSI desteği okunamadı' } else { " · donanım: $support" }
        [pscustomobject]@{ InstanceId = $d.InstanceId; Label = $label }
    }
}

function Get-LtNetworkDeviceChoices {
    param($Ctx)
    $seen = @{}
    foreach ($n in @($Ctx.Nics)) {
        $base = if ([string]$n.Description -and [string]$n.Description -ne [string]$n.Name) { "$($n.Name) — $($n.Description)" } else { [string]$n.Name }
        $seen[$base] = 1 + [int]$(if ($seen.ContainsKey($base)) { $seen[$base] } else { 0 })
        $label = if ($seen[$base] -gt 1) { "$base ($($seen[$base]))" } else { $base }
        if ([string]$n.LinkSpeed) { $label += " · $($n.LinkSpeed)" }
        [pscustomobject]@{ InterfaceGuid = $n.InterfaceGuid; Label = $label }
    }
}

function Format-LtGraphicsStateText {
    param($Hags, $Msi)
    $sup = if ($Hags.Supported -eq 'Unknown') { 'okunamadı' } else { $Hags.Supported.ToLowerInvariant() }
    $eff = if ($Hags.Effective -eq 'Unknown') { 'okunamadı' } else { $Hags.Effective.ToLowerInvariant() }
    $text = "HAGS — kayıtlı tercih: $($Hags.Configured). Sürücü desteği: $sup. Şu an: $eff."
    if ($Hags.Effective -ne 'Unknown') { $text += ' (Tercih değişikliği yeniden başlatmadan sonra etkinleşir.)' }
    if ($Msi) {
        $kind = if ($Msi.Class -eq 'NIC') { 'Ağ kartı' } else { 'Ekran kartı' }
        $hw = if ($Msi.Supported -eq 'Unknown') { 'okunamadı' } else { $Msi.Supported }
        $text += "`nMSI — $kind $($Msi.Name): kayıtlı tercih $($Msi.Configured). Donanım desteği: $hw. Etkin kesme modu bu ekrandan doğrulanmaz."
    } else { $text += "`nMSI için listeden bir aygıt seçin." }
    return $text
}

function Format-LtPresetInfo {
    <# Hazir secim sonucunu kullaniciya acikca yazar: kac ayar, hangi secim, neler neden atlandi. #>
    param($Resolution)
    $text = "$($Resolution.Title): $(@($Resolution.Selected).Count) ayar işaretlendi"
    if (@($Resolution.Choices).Count -gt 0) { $text += ' (' + ((@($Resolution.Choices) | ForEach-Object { $_.Title }) -join ', ') + ')' }
    $text += '. Zaten uygulanmış olanlar önizlemede "Değişiklik yok" görünür.'
    $skipped = @($Resolution.Unsupported)
    if ($skipped.Count -gt 0) {
        $text += " Bu sistemde atlanan $($skipped.Count): " + ((@($skipped | Select-Object -First 4) | ForEach-Object { "$($_.Title) — $($_.Reason)" }) -join ' · ')
        if ($skipped.Count -gt 4) { $text += " · (+$($skipped.Count - 4))" }
    }
    return $text + " Devam etmek için 'Tüm sayfalardaki seçimi önizle'."
}

function Get-LtSelectedTweakIds([string[]]$Pages) {
    @($script:Ui.Tweaks.Values | Where-Object { $_.Selected -and $_.IsSupported -and $Pages -contains $_.Page } | ForEach-Object { $_.Id })
}

# ---------------------------------------------------------------------------
# Durum okuma
# ---------------------------------------------------------------------------
function Update-LtPageState {
    param([Parameter(Mandatory)][string]$Page)
    if (-not $script:Ui.Ctx) { return }
    if ($script:LtOptPages -notcontains $Page) { return }
    if ($script:Ui.Job) {
        if ($script:Ui.RefreshQueue -notcontains $Page) { [void]$script:Ui.RefreshQueue.Add($Page) }
        return
    }
    $ids = @($script:Ui.Tweaks.Values | Where-Object { $_.Page -eq $Page } | ForEach-Object { $_.Id })
    foreach ($id in $ids) { $vm = $script:Ui.Tweaks[$id]; $vm.StateText = $script:LtStateText.Loading; $vm.StateKind = 'Loading' }
    $body = {
        param($a, $p, $c)
        $out = @{}
        $p.Total = $a.Ids.Count
        $i = 0
        foreach ($id in $a.Ids) {
            $p.Done = $i; $p.Text = "Durum okunuyor: $id"
            try { $out[$id] = Get-LtTweakStatus (Get-LtTweak $id) $a.Ctx }
            catch { $out[$id] = [pscustomobject]@{ Id = $id; State = 'Unknown'; Reason = $_.Exception.Message; Actions = @(); Owned = $false; HasDefault = $false } }
            $i++
        }
        $plan = ''
        if ($a.Page -eq 'Performance') { try { $plan = Get-LtActivePowerScheme } catch { $plan = '' } }
        @{ States = $out; ActivePlan = $plan; Page = $a.Page }
    }
    $onDone = {
        param($r, $errs)
        if (-not $r) { return }
        foreach ($id in $r.States.Keys) {
            $s = $r.States[$id]; $vm = $script:Ui.Tweaks[$id]
            $vm.StateKind = $s.State
            $vm.StateText = $script:LtStateText[[string]$s.State]
            $vm.IsSupported = ($s.State -ne 'NotSupported')
            $vm.Reason = if ($s.Reason) { [string]$s.Reason } else { '' }
            $vm.Owned = [bool]$s.Owned
            $vm.HasDefault = [bool]$s.HasDefault
            $vm.Details = (@($s.Actions) | ForEach-Object { "• $($_.Target): $($_.Current)" + $(if (-not $_.InDesired) { "  (hedef: $($_.Desired))" } else { '' }) }) -join "`n"
            $vm.RefreshToolTip()
            if (-not $vm.IsSupported) { $vm.Selected = $false }
        }
        if ($r.ActivePlan) { $script:Ui.ActivePlan = $r.ActivePlan }
        $script:Ui.StateLoaded[$r.Page] = $true
        if ($script:Ui.CurrentPage -eq $r.Page) { Update-LtPageInfo $r.Page }
        Set-LtStatus ("{0}: durum okundu." -f $script:LtPages[$r.Page].Title)
    }
    [void](Start-LtJob -Title "Durum okunuyor: $($script:LtPages[$Page].Title)" -Body $body -JobArgs @{ Ids = $ids; Ctx = $script:Ui.Ctx; Page = $Page } -OnDone $onDone -Quiet)
}

function Update-LtPageInfo([string]$Page) {
    $c = $script:Ui.C; $ctx = $script:Ui.Ctx
    $txt = ''
    if ($ctx) {
        switch ($Page) {
            'QuickClean' { $txt = 'Launcher temizliği varsayılan seçilmez. EA, Battle.net ve Xbox otomatik silme kapsamı dışındadır; gerekçeler için kullanılabilirlik filtresini kaldırın. Önbellek temizliği FPS artışı garantisi değildir.' }
            'Performance' {
                $names = @{ '381b4222-f694-41f0-9685-ff5bb260df2e' = 'Dengeli'; '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' = 'Yüksek Performans'; 'a1841308-3541-4fab-bc81-f71556f20b4a' = 'Güç Tasarrufu'
                            'd72c20ca-2d2d-4ba7-b818-ababadb4ef63' = 'Nihai Performans (Livn)'; '4dcd1bfb-1ae5-4c5b-b1dd-891dfb76ed04' = 'Bitsum Highest (Livn)'
                            'e559f809-9e1d-4dae-81d4-a2ab04520d2a' = 'Hybred HighPerf (Livn)'; '34add588-ef49-43fa-98e7-4b1491abb150' = 'Hybred Balanced (Livn)' }
                $ap = [string]$script:Ui.ActivePlan
                $pn = if ($names.ContainsKey($ap)) { $names[$ap] } elseif ($ap) { "Özel plan ($ap)" } else { '—' }
                $txt = "Etkin güç planı: $pn   ·   CPU: $($ctx.Cpu.Name)   ·   RAM: $($ctx.RamGB) GB$(if ($ctx.IsLaptop) { '   ·   Dizüstü (pil algılandı): güç tüketimini artıran ayarlar pil ömrünü kısaltır.' })"
            }
            'Network' {
                $n = @($ctx.Nics | ForEach-Object { "$($_.Name) — $($_.Description) ($($_.LinkSpeed))" })
                $txt = if ($n.Count) { 'Etkin fiziksel adaptörler: ' + ($n -join ';  ') + '. Adaptör ayarları yalnızca seçilen hedefe yazılır; TCP/IP (genel) seçenekleri sistem genelini etkiler.' } else { 'Etkin fiziksel ağ adaptörü bulunamadı.' }
            }
            'GPU' {
                $g = @($ctx.Gpus | ForEach-Object { "$($_.Name) (sürücü $($_.DriverVersion))" })
                $txt = if ($g.Count) { 'Algılanan GPU: ' + ($g -join ';  ') + '. MSI seçenekleri yalnız listeden seçilen aygıta uygulanır: önce aygıtı seçin. Üreticiye özel sürücü ayarları için NVIDIA Uygulaması / AMD Software kullanın.' } else { 'PCI GPU algılanamadı.' }
            }
            'Kernel' { $txt = 'Kırmızı "GÜVENLİĞİ AZALTIR" etiketli seçenekler yalnızca açık onayla uygulanır ve hiçbir hazır seçime dahil değildir.' }
            'Privacy' { $txt = "Sürüm: $($ctx.EditionId). Bazı Grup İlkesi değerleri yalnızca Enterprise/Education sürümlerinde uygulanır; desteklenmeyenler gerekçesiyle gösterilir." }
        }
    }
    $c.TxtPageInfo.Text = $txt
    $c.TxtPageInfo.Visibility = if ($txt) { 'Visible' } else { 'Collapsed' }
}

# ---------------------------------------------------------------------------
# Sayfa gosterimi
# ---------------------------------------------------------------------------
function Set-LtPowerPlanChoicesView {
    param([object[]]$Plans=@(), [string]$ErrorText='')
    $c = $script:Ui.C
    $script:Ui.PowerPlanBinding = $true
    try {
        $c.CmbInstalledPowerPlan.ItemsSource = @($Plans)
        $c.CmbInstalledPowerPlan.SelectedIndex = -1
    } finally { $script:Ui.PowerPlanBinding = $false }
    $c.CmbInstalledPowerPlan.IsEnabled = ($Plans.Count -gt 0)
    $script:Ui.Ctx.PowerSchemes = @($Plans | ForEach-Object { $_.Guid })
    $script:Ui.Ctx.SelectedPowerPlanGuid = ''
    $script:Ui.Tweaks['power.installed'].Selected = $false
    $script:Ui.StateLoaded['Performance'] = $false
    $c.TxtPowerPlanStatus.Text = if ($ErrorText) { 'Planlar okunamadı. Yenile ile tekrar deneyin: ' + $ErrorText }
        elseif ($Plans.Count -eq 0) { 'Gösterilecek güç planı bulunamadı. Yenile ile tekrar deneyebilirsiniz.' }
        elseif ((Get-LtBackend) -eq 'Memory') { 'Deneme planları gösteriliyor; bilgisayarınızdaki gerçek planlar değildir. Seçim tek başına ayar değiştirmez.' }
        else { 'Planlar okundu. Etkin plan etiketlidir; farklı plan seçimi tek başına ayar değiştirmez.' }
}

function Show-LtPage {
    param([Parameter(Mandatory)][string]$Page)
    $c = $script:Ui.C
    $meta = $script:LtPages[$Page]
    $script:Ui.CurrentPage = $Page
    $c.TxtPageTitle.Text = $meta.Title
    $c.TxtPageDesc.Text = $meta.Desc
    $isOpt = $script:LtOptPages -contains $Page
    $isClean = $meta.Kind -eq 'Cleanup'
    $hasCleanup = $script:Ui.CleanupGroups.ContainsKey($Page)
    $c.UserPreferencePanel.Visibility = if ($Page -eq 'WinTweaks') { 'Visible' } else { 'Collapsed' }
    $c.ExternalToolsPanel.Visibility = if ($Page -eq 'Performance') { 'Visible' } else { 'Collapsed' }
    $c.NetworkPanel.Visibility = if ($Page -eq 'Network') { 'Visible' } else { 'Collapsed' }
    $c.GraphicsPanel.Visibility = if ($Page -eq 'GPU') { 'Visible' } else { 'Collapsed' }
    $c.PresetBar.Visibility = if ($isOpt) { 'Visible' } else { 'Collapsed' }
    $c.Toolbar.Visibility = if ($isOpt -or $isClean) { 'Visible' } else { 'Collapsed' }
    foreach ($n in @('BtnApply', 'BtnRevertPrev', 'BtnRevertDefault', 'BtnBackupState', 'BtnRefresh')) { $c[$n].Visibility = if ($isOpt) { 'Visible' } else { 'Collapsed' } }
    $c.BtnRunCleanup.Visibility = if ($hasCleanup) { 'Visible' } else { 'Collapsed' }
    $c.BtnCleanupPreview.Visibility = if ($isClean) { 'Visible' } else { 'Collapsed' }
    $c.BtnSelectAll.Visibility = if ($isOpt -or $isClean) { 'Visible' } else { 'Collapsed' }
    $c.BtnSelectNone.Visibility = $c.BtnSelectAll.Visibility
    $c.BtnRunCleanup.Content = if ($isClean) { 'Seçilenleri _temizle…' } else { 'Tek seferlik işlemleri _çalıştır…' }
    # Assign inside each branch so PowerShell does not enumerate the collection.
    # WPF needs IEnumerable even when there are zero or exactly one groups.
    if ($isOpt) { $c.TweakGroups.ItemsSource = $script:Ui.TweakGroups[$Page] }
    else { $c.TweakGroups.ItemsSource = $null }
    if ($hasCleanup) { $c.CleanupGroups.ItemsSource = $script:Ui.CleanupGroups[$Page] }
    else { $c.CleanupGroups.ItemsSource = $null }
    $c.ChkCleanupAvailable.Visibility = if ($isClean) { 'Visible' } else { 'Collapsed' }
    if ($hasCleanup) { Update-LtCleanupGroupsView }
    $c.TxtCleanupHeader.Visibility = if ($hasCleanup -and $isOpt) { 'Visible' } else { 'Collapsed' }
    $c.SetupPanel.Visibility = if ($Page -eq 'Setup') { 'Visible' } else { 'Collapsed' }
    $c.HistoryPanel.Visibility = if ($Page -eq 'History') { 'Visible' } else { 'Collapsed' }
    $c.ScriptPanel.Visibility = if ($Page -eq 'RunScript') { 'Visible' } else { 'Collapsed' }
    if ($c.Contains('HealthPanel') -and $c.HealthPanel) { $c.HealthPanel.Visibility = if ($Page -eq 'Health') { 'Visible' } else { 'Collapsed' } }
    if ($c.Contains('StartupPanel') -and $c.StartupPanel) { $c.StartupPanel.Visibility = if ($Page -eq 'Startup') { 'Visible' } else { 'Collapsed' } }
    if ($c.Contains('KitPanel') -and $c.KitPanel) { $c.KitPanel.Visibility = if ($Page -eq 'Kit') { 'Visible' } else { 'Collapsed' } }
    $c.MainScroll.ScrollToTop()
    Update-LtPageInfo $Page
    if ($isOpt -and -not $script:Ui.StateLoaded[$Page]) { Update-LtPageState -Page $Page }
    if ($Page -eq 'History') { Update-LtHistory }
    if ($Page -eq 'Startup') { Update-LtStartupView }
    if ($Page -eq 'Health' -and $script:Ui.Ctx -and -not $script:Ui.HealthChecks -and -not $script:Ui.Job) { [void](Start-LtHealthCheck) }
    # Format Sonrasi: envanter sinirli siklikta, arka planda (arayuzu bloklamaz)
    if ($Page -eq 'Setup' -and $script:Ui.SetupInventory) { [void](Request-LtSetupInventory) }
}

# ---------------------------------------------------------------------------
# Uygula / geri al akisi (tekil sayfa ve tum sayfalar ayni fonksiyonu kullanir)
# ---------------------------------------------------------------------------
function Invoke-LtTweakFlow {
    param([Parameter(Mandatory)][AllowEmptyCollection()][AllowNull()][string[]]$Ids, [Parameter(Mandatory)][ValidateSet('Apply', 'RevertPrevious', 'RevertDefault')][string]$Mode)
    $Ids = @($Ids | Where-Object { $_ })
    if (-not $script:Ui.Ctx) { Set-LtStatus 'Sistem bilgisi henüz okunuyor; birkaç saniye sonra tekrar deneyin.'; return }
    if ($Ids.Count -eq 0) { Set-LtStatus 'Önce en az bir ayar seçin.'; return }
    $planBody = { param($a, $p, $c) @{ Plan = @(Get-LtPlan -TweakIds $a.Ids -Context $a.Ctx -Mode $a.Mode) } }
    $onPlan = {
        param($pr, $errs)
        if (-not $pr) { return }
        $plan = @($pr.Plan)
        $mode = $script:Ui.PendingMode
        $will = @($plan | Where-Object { $_.Outcome -eq 'WillChange' })
        $sec = @($will | Where-Object { $_.Risk -eq 'Security' })
        $heads = @{ Apply = 'Değişiklik özeti — uygulanacak'; RevertPrevious = 'Önceki ayarlara dönüş özeti'; RevertDefault = 'Windows varsayılanına dönüş özeti' }
        $intro = "{0} ayardan {1} tanesi sistemi değiştirecek. Aşağıdaki liste mevcut değerleri sistemden okuyarak hazırlandı; henüz HİÇBİR değişiklik yapılmadı." -f $plan.Count, $will.Count
        $foot = 'Her değişiklikten önce özgün değer günlüğe yazılır; uygulama yarıda kalırsa bir sonraki açılışta kurtarma önerilir.'
        $rows = @(ConvertTo-LtPlanRows $plan)
        $res = Show-LtReportDialog -Owner $script:Ui.Window -Title 'Önizleme' -Head $heads[$mode] -Intro $intro -Rows $rows -Mode Confirm `
            -OkText $(if ($mode -eq 'Apply') { 'Uygula' } else { 'Geri al' }) -ShowRestorePoint -RestorePointDefault ($mode -eq 'Apply') `
            -RequireConsent:($sec.Count -gt 0) -Foot $foot -OkEnabled ($will.Count -gt 0)
        if (-not $res.Confirmed) { Set-LtStatus 'Vazgeçildi; hiçbir değişiklik yapılmadı.'; return }
        $applyIds = @($plan | Where-Object { $_.Outcome -eq 'WillChange' } | ForEach-Object { $_.Id })
        $body = {
            param($a, $p, $c)
            $rp = $null
            if ($a.RestorePoint) { $p.Text = 'Geri yükleme noktası oluşturuluyor…'; $rp = New-LtRestorePoint; Write-LtLog "[$($rp.StatusText)] $($rp.Title) — $($rp.Message)" $(if ($rp.Status -eq 'Success') { 'OK' } else { 'WARN' }) }
            if ($a.Mode -eq 'Apply') { $r = Invoke-LtApply -TweakIds $a.Ids -Context $a.Ctx -Progress $p -Cancel $c }
            elseif ($a.Mode -eq 'RevertPrevious') { $r = Invoke-LtRevert -TweakIds $a.Ids -Context $a.Ctx -Target Previous -Progress $p -Cancel $c }
            else { $r = Invoke-LtRevert -TweakIds $a.Ids -Context $a.Ctx -Target Default -Progress $p -Cancel $c }
            @{ Run = $r; RestorePoint = $rp }
        }
        $title = @{ Apply = 'Ayarlar uygulanıyor'; RevertPrevious = 'Önceki ayarlara dönülüyor'; RevertDefault = 'Windows varsayılanına dönülüyor' }[$mode]
        [void](Start-LtJob -Title $title -Body $body -JobArgs @{ Ids = $applyIds; Ctx = $script:Ui.Ctx; Mode = $mode; RestorePoint = $res.RestorePoint } -OnDone { param($r, $e) Show-LtRunResult $r })
    }
    $script:Ui.PendingMode = $Mode
    [void](Start-LtJob -Title 'Önizleme hazırlanıyor (salt okunur)…' -Body $planBody -JobArgs @{ Ids = $Ids; Ctx = $script:Ui.Ctx; Mode = $Mode } -OnDone $onPlan)
}

# ---------------------------------------------------------------------------
# Sistem Kontrolu, Baslangic, ag olcumu, oyun GPU tercihi, Oyuncu modu
# ---------------------------------------------------------------------------
$script:LtHealthStatusText = @{ Ok = 'Tamam'; Info = 'Bilgi'; Warning = 'Uyarı'; Problem = 'Sorun'; Unknown = 'Okunamadı' }

function ConvertTo-LtHealthViewItems {
    param([object[]]$Checks)
    $links = Get-LtHealthLinks
    foreach ($c in @($Checks)) {
        $actions = New-Object System.Collections.ArrayList
        foreach ($l in @($c.Links)) { if ($l -and $links.Contains($l)) { [void]$actions.Add([pscustomobject]@{ Label = $links[$l].Label; Tag = "link:$l" }) } }
        if ($c.Page -and $script:LtPages.Contains([string]$c.Page)) { [void]$actions.Add([pscustomobject]@{ Label = "$($script:LtPages[[string]$c.Page].Title) sayfası"; Tag = "page:$($c.Page)" }) }
        foreach ($t in @($c.Tweaks)) {
            if (-not $t) { continue }
            $tw = Get-LtTweak $t
            if ($tw) { [void]$actions.Add([pscustomobject]@{ Label = "Ayarı işaretle: $($tw.Title)"; Tag = "tweak:$t" }) }
        }
        [pscustomobject]@{ Id = $c.Id; Area = $c.Area; Title = $c.Title; Status = $c.Status; StatusText = $script:LtHealthStatusText[[string]$c.Status]
                           Finding = $c.Finding; Advice = [string]$c.Advice; Actions = @($actions) }
    }
}

function Select-LtNavPage([string]$Page) {
    $nav = $script:Ui.C.NavList
    try { foreach ($it in @($nav.Items)) { if ([string]$it.Tag -eq $Page) { $nav.SelectedItem = $it; return } } } catch { $null = $_ }
    Show-LtPage -Page $Page
}

function Start-LtHealthCheck {
    if (-not $script:Ui.Ctx) { Set-LtStatus 'Sistem bilgisi henüz okunuyor; birkaç saniye sonra tekrar deneyin.'; return $false }
    $script:Ui.C.TxtHealthSummary.Text = 'Kontrol ediliyor… (salt okunur; birkaç saniye sürebilir)'
    $body = { param($a, $p, $c) $p.Text = 'Sistem bilgileri okunuyor'; @{ Checks = @(Get-LtHealthReport -Facts (Get-LtHealthFacts -Context $a.Ctx)) } }
    $ok = Start-LtJob -Title 'Sistem kontrol ediliyor' -Body $body -JobArgs @{ Ctx = $script:Ui.Ctx } -OnDone { param($r, $e) Show-LtHealthResult $r $e }
    if (-not $ok) { $script:Ui.C.TxtHealthSummary.Text = 'Başka bir işlem sürüyor; bitince "Kontrolü çalıştır" düğmesine basın.' }
    return $ok
}

function Show-LtHealthResult($r, $errs) {
    if (-not $r) { $script:Ui.C.TxtHealthSummary.Text = 'Kontrol tamamlanamadı: ' + (@($errs) -join '; '); return }
    $script:Ui.HealthChecks = @($r.Checks)
    $script:Ui.C.HealthList.ItemsSource = @(ConvertTo-LtHealthViewItems $script:Ui.HealthChecks)
    $script:Ui.C.TxtHealthSummary.Text = (Get-LtHealthSummary -Checks $script:Ui.HealthChecks) + " · $(Get-Date -Format 'HH:mm')" + $(if ((Get-LtBackend) -eq 'Memory') { ' · deneme sistemi' } else { '' })
    Set-LtStatus 'Sistem kontrolü tamamlandı.'
}

function Invoke-LtHealthAction([string]$Tag) {
    $kind, $val = $Tag -split ':', 2
    switch ($kind) {
        'link' {
            if (-not (Test-LtLiveSystem)) { Set-LtStatus "Kuru çalışma: '$val' ekranı açılmadı."; return }
            try { Open-LtHealthLink -Id $val; Set-LtStatus 'Windows ekranı açıldı. Orada yapılan değişiklikler Livn geri alma günlüğüne kaydedilmez.' } catch { Set-LtStatus $_.Exception.Message }
        }
        'page' { Select-LtNavPage $val }
        'tweak' {
            $vm = $script:Ui.Tweaks[$val]
            if (-not $vm) { return }
            Select-LtNavPage $vm.Page
            $vm.Selected = $true
            Set-LtStatus "'$($vm.Title)' işaretlendi. Önizleyip onayladığınızda uygulanır."
        }
    }
}

function Save-LtHealthReportDialog {
    if (-not $script:Ui.HealthChecks) { Set-LtStatus 'Önce kontrolü çalıştırın.'; return }
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Filter = 'Metin (*.txt)|*.txt'
    $dlg.FileName = 'LivnTools-sistem-kontrolu-' + (Get-Date -Format 'yyyyMMdd-HHmm') + '.txt'
    if ($dlg.ShowDialog($script:Ui.Window) -ne $true) { return }
    try {
        Write-LtFileAtomic -Path $dlg.FileName -Content (Format-LtHealthReportText -Checks $script:Ui.HealthChecks -Context $script:Ui.Ctx)
        Set-LtStatus "Rapor kaydedildi: $($dlg.FileName)"
    } catch { Set-LtStatus "Rapor kaydedilemedi: $($_.Exception.Message)" }
}

function Update-LtStartupView {
    $c = $script:Ui.C
    if (-not $c.Contains('StartupList') -or -not $c.StartupList) { return }
    try { $items = @(Get-LtStartupItems) } catch { $items = @(); $c.TxtStartupInfo.Text = "Başlangıç listesi okunamadı: $($_.Exception.Message)"; return }
    $script:Ui.StartupItems = $items
    $c.StartupList.ItemsSource = $items
    $on = @($items | Where-Object { $_.Enabled }).Count
    $c.TxtStartupInfo.Text = "$($items.Count) öğe · $on açık · $($items.Count - $on) kapalı. Görev Zamanlayıcı görevleri ve servisler bu listede yoktur." + $(if ((Get-LtBackend) -eq 'Memory') { ' (deneme sistemi)' } else { '' })
}

function Invoke-LtStartupFlow([bool]$Enable) {
    $sel = @($script:Ui.C.StartupList.SelectedItems)
    if ($sel.Count -eq 0) { Set-LtStatus 'Önce listeden uygulama seçin.'; return }
    if (-not $script:Ui.Ctx) { Set-LtStatus 'Sistem bilgisi henüz okunuyor.'; return }
    $script:Ui.Ctx.StartupSelection = @($sel | ForEach-Object { $_.Id })
    $id = if ($Enable) { 'startup.enable-selected' } else { 'startup.disable-selected' }
    Invoke-LtTweakFlow -Ids @($id) -Mode Apply
}

function Update-LtGpuGamesView {
    $apps = @(Get-LtProp $script:Ui.Ctx 'GpuPreferenceApps' @())
    $script:Ui.C.TxtGpuGames.Text = if ($apps.Count -eq 0) { 'Eklenen oyun yok. Ekledikten sonra "Seçili oyunlar yüksek performanslı ekran kartını kullansın" ayarını işaretleyin.' }
        else { "Eklenen oyunlar ($($apps.Count)): " + ((@($apps) | ForEach-Object { [IO.Path]::GetFileName($_) }) -join ', ') }
    if ($script:Ui.Tweaks.ContainsKey('gpu.app-high-perf')) { $script:Ui.Tweaks['gpu.app-high-perf'].Selected = $false }
    $script:Ui.StateLoaded['GPU'] = $false
    if ($script:Ui.CurrentPage -eq 'GPU') { Update-LtPageState -Page 'GPU' }
}

function Start-LtLatencyMeasurement {
    if (-not $script:Ui.Ctx) { Set-LtStatus 'Sistem bilgisi henüz okunuyor.'; return }
    $target = ([string]$script:Ui.C.TxtPingTarget.Text).Trim()
    if ($target -and -not (Test-LtNetworkTarget $target)) { Set-LtStatus 'Geçersiz hedef: yalnız IP adresi veya alan adı yazın.'; return }
    $nics = @($script:Ui.Ctx.Nics)
    $wifi = ($nics.Count -gt 0 -and @($nics | Where-Object { -not (Get-LtProp $_ 'Wifi' $false) }).Count -eq 0)
    $script:Ui.C.TxtPingResult.Text = 'Ölçülüyor… (her hedefe 20 ping)'
    $body = {
        param($a, $p, $c)
        $prev = @(Get-LtLatencyHistory) | Select-Object -Last 1
        $res = Invoke-LtLatencyTest -Custom $a.Target -Progress $p -Cancel $c -Wifi $a.Wifi
        Save-LtLatencyResult -Result $res
        @{ Result = $res; Previous = $prev }
    }
    [void](Start-LtJob -Title 'Bağlantı ölçülüyor' -Body $body -JobArgs @{ Target = $target; Wifi = $wifi } -OnDone {
        param($r, $e)
        if (-not $r) { $script:Ui.C.TxtPingResult.Text = 'Ölçüm tamamlanamadı: ' + (@($e) -join '; '); return }
        $text = Format-LtLatencyResult -Result $r.Result
        if ($r.Previous) {
            $cmp = @(Compare-LtLatency -Current $r.Result -Previous $r.Previous)
            if ($cmp.Count) { $text += "`n`nÖnceki ölçüme göre ($(([datetime]$r.Previous.Time).ToString('dd.MM HH:mm'))):`n" + ($cmp -join "`n") }
        }
        if ((Get-LtBackend) -eq 'Memory') { $text = "Deneme sistemi (gerçek ağ ölçülmedi)`n" + $text }
        $script:Ui.C.TxtPingResult.Text = $text
        Set-LtStatus 'Bağlantı ölçümü tamamlandı.'
    })
}

function Start-LtDnsBenchmark {
    if (-not $script:Ui.Ctx) { Set-LtStatus 'Sistem bilgisi henüz okunuyor.'; return }
    $script:Ui.C.TxtPingResult.Text = 'DNS sunucuları ölçülüyor…'
    $body = {
        param($a, $p, $c)
        $current = @()
        if ($a.Guid) { try { $current = @((Get-LtDnsServerConfig -InterfaceGuid $a.Guid).Servers) } catch { $null = $_ } }
        @{ Results = @(Invoke-LtDnsBenchmark -Current $current -Progress $p -Cancel $c) }
    }
    [void](Start-LtJob -Title 'DNS hız testi' -Body $body -JobArgs @{ Guid = [string](Get-LtProp $script:Ui.Ctx 'SelectedNicGuid' '') } -OnDone {
        param($r, $e)
        if (-not $r) { $script:Ui.C.TxtPingResult.Text = 'DNS testi tamamlanamadı: ' + (@($e) -join '; '); return }
        $text = Format-LtDnsBenchmark -Results @($r.Results)
        if ((Get-LtBackend) -eq 'Memory') { $text = "Deneme sistemi (gerçek DNS sorgulanmadı)`n" + $text }
        $script:Ui.C.TxtPingResult.Text = $text
    })
}

function Start-LtGamerMode {
    <#
      Oyuncu modu: tek fiziksel adaptor varsa hedefler, hazir secimi isaretler ve dogrudan
      onizlemeyi acar. Uygulama yine onizleme penceresindeki onayla yapilir.
    #>
    if (-not $script:Ui.Ctx) { Set-LtStatus 'Sistem bilgisi henüz okunuyor; birkaç saniye sonra tekrar deneyin.'; return }
    $ctx = $script:Ui.Ctx
    $nics = @($ctx.Nics)
    if (-not [string](Get-LtProp $ctx 'SelectedNicGuid' '') -and $nics.Count -eq 1) {
        $guid = [string]$nics[0].InterfaceGuid
        $script:Ui.SuppressNicChange = $true
        $shown = $false
        try { $shown = Select-LtComboItem $script:Ui.C.CmbNetworkDevice 'InterfaceGuid' $guid } catch { $null = $_ } finally { $script:Ui.SuppressNicChange = $false }
        if ($shown) { Set-LtNetworkTargetFromUi } else { $ctx.SelectedNicGuid = $guid }
    }
    $r = Resolve-LtPresetSelection -Name 'Gamer' -Context $ctx
    foreach ($t in $script:Ui.Tweaks.Values) { $t.Selected = $false }
    foreach ($id in @($r.Selected)) { $vm = $script:Ui.Tweaks[$id]; if ($vm) { $vm.Selected = $true } }
    $info = Format-LtPresetInfo $r
    $script:Ui.C.TxtPresetInfo.Text = $info
    Set-LtStatus $info
    if (@($r.Selected).Count -eq 0) { return }
    Invoke-LtTweakFlow -Ids @($r.Selected) -Mode Apply
}

function Initialize-LtGamingViews {
    $c = $script:Ui.C
    if ($c.Contains('BtnHealthRun') -and $c.BtnHealthRun) {
        $c.BtnHealthRun.Add_Click({ [void](Start-LtHealthCheck) })
        $c.BtnHealthGamer.Add_Click({ Start-LtGamerMode })
        $c.BtnHealthSave.Add_Click({ Save-LtHealthReportDialog })
        $c.HealthList.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler]{
            param($src, $e)
            $tag = [string]$e.OriginalSource.Tag
            if ($tag) { Invoke-LtHealthAction $tag }
        })
    }
    if ($c.Contains('BtnStartupDisable') -and $c.BtnStartupDisable) {
        $c.BtnStartupDisable.Add_Click({ Invoke-LtStartupFlow $false })
        $c.BtnStartupEnable.Add_Click({ Invoke-LtStartupFlow $true })
        $c.BtnStartupRefresh.Add_Click({ Update-LtStartupView })
    }
    if ($c.Contains('BtnPingRun') -and $c.BtnPingRun) {
        $c.BtnPingRun.Add_Click({ Start-LtLatencyMeasurement })
        $c.BtnDnsRun.Add_Click({ Start-LtDnsBenchmark })
    }
    if ($c.Contains('BtnGpuAddGame') -and $c.BtnGpuAddGame) {
        $c.BtnGpuAddGame.Add_Click({
            if (-not $script:Ui.Ctx) { return }
            $dlg = New-Object Microsoft.Win32.OpenFileDialog
            $dlg.Filter = 'Oyun (*.exe)|*.exe'
            $dlg.Multiselect = $true
            if ($dlg.ShowDialog($script:Ui.Window) -ne $true) { return }
            $script:Ui.Ctx.GpuPreferenceApps = @(@(Get-LtProp $script:Ui.Ctx 'GpuPreferenceApps' @()) + @($dlg.FileNames) | Select-Object -Unique)
            Update-LtGpuGamesView
        })
        $c.BtnGpuClearGames.Add_Click({ if ($script:Ui.Ctx) { $script:Ui.Ctx.GpuPreferenceApps = @(); Update-LtGpuGamesView } })
    }
}

# ---------------------------------------------------------------------------
# Liste secimleri: SelectedValue SelectionChanged sirasinda henuz guncellenmemis
# olabilir (WPF). Secim her zaman SelectedItem'den okunur ve gorunur yazilir.
# ---------------------------------------------------------------------------
function ConvertTo-LtBrush([string]$Hex) {
    # WPF yoksa (testler) metin olarak birakilir
    try { return (New-Object System.Windows.Media.BrushConverter).ConvertFromString($Hex) } catch { return $Hex }
}

function Get-LtComboSelectedKey {
    param($Combo, [Parameter(Mandatory)][string]$Property)
    if ($null -eq $Combo) { return '' }
    $item = $Combo.SelectedItem
    if ($null -eq $item) { return '' }
    return [string](Get-LtProp $item $Property '')
}

function Select-LtComboItem {
    param($Combo, [Parameter(Mandatory)][string]$Property, [string]$Value)
    if ($null -eq $Combo -or -not $Value) { return $false }
    foreach ($it in @($Combo.ItemsSource)) {
        if ([string](Get-LtProp $it $Property '') -ieq $Value) { $Combo.SelectedItem = $it; return $true }
    }
    return $false
}

function Set-LtNetworkTargetFromUi {
    <# Secili adaptoru baglama yazar, gorunur metni gunceller; -Refresh: adaptore bagli secimleri temizleyip durumu yeniden okur. #>
    param([switch]$Refresh)
    if (-not $script:Ui.Ctx) { return }
    $c = $script:Ui.C
    $guid = Get-LtComboSelectedKey $c.CmbNetworkDevice 'InterfaceGuid'
    $script:Ui.Ctx.SelectedNicGuid = $guid
    if ($c.Contains('TxtNetworkTarget') -and $c.TxtNetworkTarget) {
        $c.TxtNetworkTarget.Text = if ($guid) { "Seçili hedef: $([string](Get-LtProp $c.CmbNetworkDevice.SelectedItem 'Label' '')). Adaptör ayarları ve DNS yalnız bu adaptöre uygulanır." }
            elseif (@($script:Ui.Ctx.Nics).Count -eq 0) { 'Bağlı fiziksel ağ adaptörü bulunamadı; adaptör ayarları ve DNS kullanılamaz.' }
            else { 'Hedef seçilmedi: adaptör ayarları ve DNS seçenekleri bir adaptör seçilene kadar kullanılamaz.' }
        $c.TxtNetworkTarget.Foreground = ConvertTo-LtBrush $(if ($guid) { '#7FD686' } else { '#FFC266' })
    }
    $script:Ui.StateLoaded['Network'] = $false
    if ($Refresh) {
        foreach ($id in @('net.rss-on','net.ackfreq','nic.flowcontrol-off','nic.eee-off','nic.adaptiveifs-off','dns.cloudflare','dns.google','dns.quad9')) {
            if ($script:Ui.Tweaks.ContainsKey($id)) { $script:Ui.Tweaks[$id].Selected = $false }
        }
        if ($script:Ui.CurrentPage -eq 'Network') { Update-LtPageState -Page 'Network' }
        if ($guid) { Set-LtStatus "Hedef adaptör seçildi: $([string](Get-LtProp $c.CmbNetworkDevice.SelectedItem 'Label' ''))" }
    }
}

function Set-LtMsiTargetFromUi {
    param([switch]$Refresh)
    if (-not $script:Ui.Ctx) { return }
    $c = $script:Ui.C
    $id = Get-LtComboSelectedKey $c.CmbMsiDevice 'InstanceId'
    $script:Ui.Ctx.SelectedMsiInstanceId = $id
    if ($c.Contains('TxtMsiTarget') -and $c.TxtMsiTarget) {
        $c.TxtMsiTarget.Text = if ($id) { "Seçili MSI hedefi: $([string](Get-LtProp $c.CmbMsiDevice.SelectedItem 'Label' ''))" } else { 'MSI için aygıt seçilmedi.' }
        $c.TxtMsiTarget.Foreground = ConvertTo-LtBrush $(if ($id) { '#7FD686' } else { '#FFC266' })
    }
    $script:Ui.StateLoaded['GPU'] = $false
    if ($Refresh) {
        foreach ($t in @('msi.gpu','msi.nic')) { if ($script:Ui.Tweaks.ContainsKey($t)) { $script:Ui.Tweaks[$t].Selected = $false } }
        if ($script:Ui.CurrentPage -eq 'GPU') { Update-LtPageState -Page 'GPU' }
    }
}

function Initialize-LtDeviceSelectionView {
    <# Aygit secim olaylari. Windows dogrulayicisi bunu GERCEK WPF ComboBox'larla cagirir. #>
    $c = $script:Ui.C
    $c.CmbNetworkDevice.Add_SelectionChanged({
        if (-not $script:Ui.Ctx -or $script:Ui.SuppressNicChange) { return }
        Set-LtNetworkTargetFromUi -Refresh
    })
    $c.CmbMsiDevice.Add_SelectionChanged({
        if (-not $script:Ui.Ctx -or $script:Ui.SuppressNicChange) { return }
        Set-LtMsiTargetFromUi -Refresh
    })
}

function Set-LtDeviceChoicesView {
    <#
      Sistem bilgisi (yeniden) okununca aygit listelerini doldurur. Onceki secim GUID/kimlikle
      geri yuklenir; tek fiziksel ag adaptoru varsa otomatik hedeflenir (ayar uygulamaz).
    #>
    param([Parameter(Mandatory)]$Ctx, [string]$PreviousNic = '', [string]$PreviousMsi = '')
    $c = $script:Ui.C
    $script:Ui.SuppressNicChange = $true
    try {
        $c.CmbNetworkDevice.ItemsSource = @(Get-LtNetworkDeviceChoices $Ctx)
        $c.CmbMsiDevice.ItemsSource = @(Get-LtMsiDeviceChoices $Ctx)
        $nicItems = @($c.CmbNetworkDevice.ItemsSource)
        if (-not (Select-LtComboItem $c.CmbNetworkDevice 'InterfaceGuid' $PreviousNic) -and $nicItems.Count -eq 1) { $c.CmbNetworkDevice.SelectedItem = $nicItems[0] }
        [void](Select-LtComboItem $c.CmbMsiDevice 'InstanceId' $PreviousMsi)
    } finally { $script:Ui.SuppressNicChange = $false }
    Set-LtNetworkTargetFromUi
    Set-LtMsiTargetFromUi
}

# ---------------------------------------------------------------------------
# Kurtarma kiti
# ---------------------------------------------------------------------------
function Get-LtKitOptionsFromUi {
    $c = $script:Ui.C
    @{ NetDrivers = [bool]$c.ChkKitNet.IsChecked; OtherDrivers = [bool]$c.ChkKitOther.IsChecked; GpuDrivers = [bool]$c.ChkKitGpu.IsChecked
       Apps = [bool]$c.ChkKitApps.IsChecked; Livn = [bool]$c.ChkKitLivn.IsChecked; Saves = [bool]$c.ChkKitSaves.IsChecked; Wifi = [bool]$c.ChkKitWifi.IsChecked }
}

function Select-LtFolderDialog([string]$Description) {
    # WPF (.NET Framework 4.x) klasor secici icermez; WinForms derlemesi Windows PowerShell 5.1'de
    # her zaman vardir ama varsayilan yuklu degildir (tur adi bu yuzden calisma aninda cozulur).
    Add-Type -AssemblyName System.Windows.Forms
    $dlg = New-Object -TypeName ('System.Windows.Forms.' + 'FolderBrowserDialog')
    try {
        $dlg.Description = $Description
        $dlg.ShowNewFolderButton = $true
        if ([string]$dlg.ShowDialog() -eq 'OK') { return $dlg.SelectedPath }
        return $null
    } finally { $dlg.Dispose() }
}

function Update-LtKitPlanView {
    $target = [string]$script:Ui.KitTarget
    $body = { param($a, $p, $c) @{ Text = (Format-LtKitPlan -Plan (Get-LtKitPlan -Target $a.Target -Options $a.Options)) } }
    [void](Start-LtJob -Title 'Kurtarma kiti içeriği hesaplanıyor (salt okunur)' -Body $body -JobArgs @{ Target = $target; Options = (Get-LtKitOptionsFromUi) } -OnDone {
        param($r, $e)
        $script:Ui.C.TxtKitPlan.Text = if ($r) { $r.Text } else { 'Önizleme hazırlanamadı: ' + (@($e) -join '; ') }
    })
}

function Set-LtLoadedKit([string]$Path) {
    $kit = Read-LtRecoveryKit -Path $Path
    $script:Ui.Kit = $kit
    $script:Ui.C.TxtKitSummary.Text = Format-LtKitSummary -Kit $kit
    return $kit
}

function Show-LtKitResults([object[]]$Results, [string]$Head) {
    $rows = @(ConvertTo-LtResultRows @($Results))
    [void](Show-LtReportDialog -Owner $script:Ui.Window -Title 'Kurtarma kiti' -Head $Head -Intro 'Bu işlemler Livn geri alma günlüğüne girmez.' -Rows $rows -Mode Info)
    if (@($Results | Where-Object { $_.RestartRequired }).Count -gt 0) { $script:Ui.PendingRestart = $true; Update-LtRestartBadge }
}

function Start-LtKitRestoreStep([ValidateSet('Drivers', 'Wifi', 'Saves')][string]$Step) {
    $kit = $script:Ui.Kit
    if (-not $kit) { Set-LtStatus 'Önce kiti bulun veya kit klasörünü seçin.'; return }
    $texts = @{
        Drivers = "Kitteki sürücüler kurulacak: önce ağ, sonra diğer donanım sürücüleri. Kurulumdan önce geri yükleme noktası oluşturulur. Sürücüler Livn geri alma günlüğüne girmez; gerekirse Aygıt Yöneticisi'nden kaldırılabilir. Devam edilsin mi?"
        Wifi    = "Kitteki Wi-Fi ağları bu kullanıcıya eklenecek. Wi-Fi bağdaştırıcısının sürücüsü kurulu olmalı. Devam edilsin mi?"
        Saves   = "Oyun kayıtları geri kopyalanacak. Var olan dosyaların üstüne YAZILMAZ. Devam edilsin mi?"
    }
    if ((Show-LtMessage -Owner $script:Ui.Window -Text $texts[$Step] -Buttons YesNo -Icon Question) -ne 'Yes') { Set-LtStatus 'Vazgeçildi.'; return }
    $gpu = $false
    if ($Step -eq 'Drivers' -and @($kit.Drivers | Where-Object { $_.Group -eq 'Display' }).Count -gt 0) {
        $gpu = ((Show-LtMessage -Owner $script:Ui.Window -Text 'Kitte ekran kartı sürücüsü de var. Kurulsun mu? (Üreticinin güncel sürücüsünü kuracaksanız Hayır deyin.)' -Buttons YesNo -Icon Question) -eq 'Yes')
    }
    $body = {
        param($a, $p, $c)
        $res = New-Object System.Collections.ArrayList
        switch ($a.Step) {
            'Drivers' {
                if (Test-LtLiveSystem) { $p.Text = 'Geri yükleme noktası oluşturuluyor…'; [void]$res.Add((New-LtRestorePoint)) }
                $p.Text = 'Ağ sürücüleri kuruluyor…'; [void]$res.Add((Install-LtKitDrivers -Kit $a.Kit -Group Network))
                $p.Text = 'Diğer sürücüler kuruluyor…'; [void]$res.Add((Install-LtKitDrivers -Kit $a.Kit -Group Other))
                if ($a.Gpu) { $p.Text = 'Ekran kartı sürücüleri kuruluyor…'; [void]$res.Add((Install-LtKitDrivers -Kit $a.Kit -Group Display)) }
            }
            'Wifi'  { [void]$res.Add((Import-LtKitWifiProfiles -Kit $a.Kit)) }
            'Saves' { [void]$res.Add((Restore-LtKitSaves -Kit $a.Kit -Cancel $c)) }
        }
        @{ Results = @($res) }
    }
    [void](Start-LtJob -Title 'Kurtarma kiti geri yükleniyor' -Body $body -JobArgs @{ Kit = $kit; Step = $Step; Gpu = $gpu } -OnDone {
        param($r, $e)
        if (-not $r) { Set-LtStatus ('Geri yükleme tamamlanamadı: ' + (@($e) -join '; ')); return }
        Show-LtKitResults -Results @($r.Results) -Head 'Geri yükleme sonucu'
    })
}

function Initialize-LtKitView {
    $c = $script:Ui.C
    if (-not ($c.Contains('BtnKitCreate') -and $c.BtnKitCreate)) { return }
    $c.BtnKitBrowse.Add_Click({
        $p = Select-LtFolderDialog 'Kurtarma kitinin kaydedileceği klasör (USB bellek önerilir)'
        if (-not $p) { return }
        $script:Ui.KitTarget = $p
        $issue = Test-LtKitTarget -Target $p
        $script:Ui.C.TxtKitTarget.Text = if ($issue) { $issue } else { "Hedef: $p" }
        $script:Ui.C.TxtKitTarget.Foreground = ConvertTo-LtBrush $(if ($issue) { '#FFC266' } else { '#7FD686' })
        Update-LtKitPlanView
    })
    $c.BtnKitPreview.Add_Click({ Update-LtKitPlanView })
    $c.BtnKitCreate.Add_Click({
        if (-not $script:Ui.Ctx) { Set-LtStatus 'Sistem bilgisi henüz okunuyor.'; return }
        $issue = Test-LtKitTarget -Target ([string]$script:Ui.KitTarget)
        if ($issue) { Set-LtStatus $issue; $script:Ui.C.TxtKitTarget.Text = $issue; return }
        $o = Get-LtKitOptionsFromUi
        if ($o.Wifi -and (Show-LtMessage -Owner $script:Ui.Window -Text 'Wi-Fi parolaları kitte DÜZ METİN olarak saklanacak. USB belleği güvende tutun ve geri yükledikten sonra WiFi klasörünü silin. Devam edilsin mi?' -Buttons YesNo -Icon Warning) -ne 'Yes') { return }
        $body = { param($a, $p, $c) @{ Kit = (New-LtRecoveryKit -Target $a.Target -Options $a.Options -Context $a.Ctx -AppRoot $a.AppRoot -Progress $p -Cancel $c) } }
        [void](Start-LtJob -Title 'Kurtarma kiti oluşturuluyor' -Body $body -JobArgs @{ Target = $script:Ui.KitTarget; Options = $o; Ctx = $script:Ui.Ctx; AppRoot = $script:Ui.AppRoot } -OnDone {
            param($r, $e)
            if (-not $r) { $script:Ui.C.TxtKitPlan.Text = 'Kit oluşturulamadı: ' + (@($e) -join '; '); return }
            $k = $r.Kit
            $label = @{ Success = 'Kit hazır'; Partial = 'Kit eksik'; Failed = 'Kit oluşturulamadı'; Cancelled = 'Kit iptal edildi'; Skipped = 'Kit içeriği oluşturulmadı' }[$k.Status]
            $lines = @("${label}: $($k.Path)") + @($k.Parts | ForEach-Object { "• $($_.Name) [$($_.Status)]: $($_.Message)" }) + @('', $(if ($k.Status -ne 'Success') { 'Kit tamamlanmadı. Formattan önce eksikleri giderip yeniden oluşturun.' } elseif ($k.Manifest.Contents.Livn) { 'USB belleği güvenli şekilde çıkarın. Formattan sonra kitteki LivnTools\LivnTools.bat ile başlayın.' } else { 'Livn kopyası seçilmedi; uygulamayı ayrıca saklayın.' }))
            $script:Ui.C.TxtKitPlan.Text = ($lines -join "`n")
            Set-LtStatus "${label}: $($k.Path)"
        })
    })
    $c.BtnKitFind.Add_Click({
        $body = { param($a, $p, $c) @{ Found = @(Find-LtRecoveryKits -AppRoot $a.AppRoot) } }
        [void](Start-LtJob -Title 'Kurtarma kiti aranıyor' -Body $body -JobArgs @{ AppRoot = $script:Ui.AppRoot } -OnDone {
            param($r, $e)
            $found = if ($r) { @($r.Found) } else { @() }
            if ($found.Count -eq 0) { $script:Ui.C.TxtKitSummary.Text = 'Bağlı sürücülerde kurtarma kiti bulunamadı. USB belleği takıp tekrar deneyin veya klasörü seçin.'; return }
            try { [void](Set-LtLoadedKit -Path $found[0]); if ($found.Count -gt 1) { Set-LtStatus "$($found.Count) kit bulundu; en yenisi yüklendi." } }
            catch { $script:Ui.C.TxtKitSummary.Text = "Kit okunamadı: $($_.Exception.Message)" }
        })
    })
    $c.BtnKitOpen.Add_Click({
        $p = Select-LtFolderDialog 'Kurtarma kiti klasörü (kit.json içeren)'
        if (-not $p) { return }
        try { [void](Set-LtLoadedKit -Path $p) } catch { $script:Ui.C.TxtKitSummary.Text = "Kit okunamadı: $($_.Exception.Message)" }
    })
    $c.BtnKitDrivers.Add_Click({ Start-LtKitRestoreStep Drivers })
    $c.BtnKitWifi.Add_Click({ Start-LtKitRestoreStep Wifi })
    $c.BtnKitSaves.Add_Click({ Start-LtKitRestoreStep Saves })
    $c.BtnKitApps.Add_Click({
        $kit = $script:Ui.Kit
        if (-not $kit) { Set-LtStatus 'Önce kiti yükleyin.'; return }
        try { Set-LtSetupPackageSelection -Ids @($kit.AppIds) } catch { Set-LtStatus "Uygulama seçimi yapılamadı: $($_.Exception.Message)"; return }
        Select-LtNavPage 'Setup'
        Set-LtStatus "$(@($kit.AppIds).Count) uygulama seçildi. Kurulu olanlar atlanır; 'Seçili uygulamaları kur…' ile devam edin."
    })
    $c.BtnKitTweaks.Add_Click({
        $kit = $script:Ui.Kit
        if (-not $kit -or -not $script:Ui.Ctx) { Set-LtStatus 'Önce kiti yükleyin.'; return }
        if (@($kit.TweakIds).Count -eq 0) { Set-LtStatus 'Kitte kayıtlı Livn ayarı yok.'; return }
        if ($null -ne $kit.MenuDelayMs) { $script:Ui.Ctx.MenuDelayMs = $kit.MenuDelayMs }
        Invoke-LtTweakFlow -Ids @($kit.TweakIds) -Mode Apply
    })
}

function Show-LtRunResult($r) {
    if (-not $r) { return }
    $run = $r.Run
    $rows = New-Object System.Collections.ArrayList
    if ($r.RestorePoint) { foreach ($x in @(ConvertTo-LtResultRows @($r.RestorePoint))) { [void]$rows.Add($x) } }
    foreach ($x in @(ConvertTo-LtResultRows $run.Results)) { [void]$rows.Add($x) }
    $pages = @{}
    foreach ($res in @($run.Results)) {
        $vm = $script:Ui.Tweaks[$res.Id]
        if ($vm) {
            $vm.LastResult = "Son işlem: $($res.StatusText) — $($res.Message)"
            $vm.LastResultKind = $res.Status
            $pages[$vm.Page] = $true
        }
    }
    $s = $run.Summary
    $restartKinds = @($s.RestartKinds)
    if ($restartKinds -contains 'Reboot') { $script:Ui.PendingRestart = $true }
    Update-LtRestartBadge
    $head = 'Sonuç: {0} başarılı, {1} zaten uygulanmış, {2} atlandı, {3} desteklenmiyor, {4} başarısız' -f $s.Success, $s.AlreadyApplied, $s.Skipped, $s.NotSupported, $s.Failed
    $intro = "İşlem kimliği: $($run.OperationId). Başarılı sayılan her değişiklik, uygulandıktan sonra sistemden yeniden okunarak doğrulandı."
    if ($restartKinds.Count -gt 0) { $intro += ' ' + ((@($restartKinds) | ForEach-Object { Get-LtRestartText $_ }) -join '; ') + '.' }
    Set-LtStatus $head
    [void](Show-LtReportDialog -Owner $script:Ui.Window -Title 'Sonuç' -Head $head -Intro $intro -Rows @($rows) -Mode Info)
    if ($restartKinds -contains 'Explorer') {
        if ((Show-LtMessage -Owner $script:Ui.Window -Text 'Bazı değişikliklerin görünmesi için Explorer yeniden başlatılmalı. Şimdi yeniden başlatılsın mı? (Açık Explorer pencereleri kapanır.)' -Buttons YesNo -Icon Question) -eq 'Yes') {
            Restart-LtExplorer
        }
    }
    foreach ($pg in $pages.Keys) { $script:Ui.StateLoaded[$pg] = $false; Update-LtPageState -Page $pg }
    if ($script:Ui.CurrentPage -eq 'Startup') { Update-LtStartupView }
    if ($script:Ui.HealthChecks) { $script:Ui.HealthChecks = $null; if ($script:Ui.C.Contains('TxtHealthSummary')) { $script:Ui.C.TxtHealthSummary.Text = 'Ayarlar değişti; güncel durum için kontrolü yeniden çalıştırın.' } }
}

function Restart-LtExplorer {
    # Asil koruma motorda (Restart-LtExplorerShell -> Assert-LtLiveSystem); bu kontrol yalnizca mesaj icin
    if (-not (Test-LtLiveSystem)) { Add-LtLogLine 'Kuru çalışma: Explorer yeniden başlatılmadı.'; return }
    try {
        Restart-LtExplorerShell
        Add-LtLogLine ("{0}  [OK   ]  Explorer yeniden başlatıldı." -f (Get-Date -Format 'HH:mm:ss'))
    } catch { Add-LtLogLine ("{0}  [ERROR]  Explorer yeniden başlatılamadı: {1}" -f (Get-Date -Format 'HH:mm:ss'), $_.Exception.Message) }
}

function Update-LtRestartBadge {
    $c = $script:Ui.C
    $c.BadgeRestart.Visibility = if ($script:Ui.PendingRestart) { 'Visible' } else { 'Collapsed' }
}

# ---------------------------------------------------------------------------
# Temizlik akisi
# ---------------------------------------------------------------------------
function Invoke-LtCleanupFlow {
    param([Parameter(Mandatory)][string]$Page)
    if (-not $script:Ui.Ctx) { Set-LtStatus 'Sistem bilgisi henüz okunuyor; birkaç saniye sonra tekrar deneyin.'; return }
    $items = @($script:Ui.Cleanups.Values | Where-Object { $_.Page -eq $Page -and $_.Selected -and $_.IsAvailable })
    if ($items.Count -eq 0) { Set-LtStatus 'Önce en az bir işlem seçin.'; return }
    $close = New-Object System.Collections.ArrayList
    foreach ($vm in $items) {
        $def = Get-LtCleanupItem $vm.Id
        $running = @(Get-LtRunningProcessesFor $def)
        if ($running.Count -gt 0) {
            if (Get-LtProp $def 'RequireClosed' $false) { continue }
            $a = Show-LtMessage -Owner $script:Ui.Window -Buttons YesNoCancel -Icon Warning -Text ("{0} şu anda açık.`n`nEvet: uygulama kapatılıp temizlenir (kaydedilmemiş veriler kaybolabilir).`nHayır: bu öğe atlanır.`nİptal: temizlik başlatılmaz." -f $vm.Title)
            if ($a -eq 'Cancel') { Set-LtStatus 'Temizlik iptal edildi.'; return }
            if ($a -eq 'Yes') { [void]$close.Add($vm.Id) }
        }
    }
    $live = Test-LtLiveSystem
    $kindText = if ($live) { 'Çalıştırılacak' } else { 'Simüle edilecek' }
    $rows = @(foreach ($vm in $items) { New-LtReportRow -Title $vm.Title -Kind 'WillChange' -KindText $kindText -Message ($vm.Description + $(if ($vm.Warning) { "  ⚠ $($vm.Warning)" } else { '' })) })
    if ($live) {
        $head = "$($items.Count) temizlik/bakım işlemi çalıştırılacak"
        $intro = 'Bu işlemler GERİ ALINAMAZ ve geri alma sistemine dahil değildir. Kullanımdaki dosyalar atlanır ve "Kısmen" olarak raporlanır.'
    } else {
        $head = "KURU ÇALIŞMA: $($items.Count) temizlik/bakım işlemi simüle edilecek"
        $intro = 'Kuru çalışmada gerçek sistemde hiçbir dosya silinmez, hiçbir uygulama kapatılmaz ve hiçbir bakım komutu çalıştırılmaz.'
    }
    $res = Show-LtReportDialog -Owner $script:Ui.Window -Title 'Onay' -Head $head -Intro $intro -Rows $rows -Mode Confirm -OkText $(if ($live) { 'Çalıştır' } else { 'Simüle et' })
    if (-not $res.Confirmed) { Set-LtStatus 'Vazgeçildi.'; return }
    $body = { param($a, $p, $c) Invoke-LtCleanup -Ids $a.Ids -Context $a.Ctx -Progress $p -Cancel $c -CloseAppIds $a.Close }
    $onDone = {
        param($r, $errs)
        if (-not $r) { return }
        foreach ($x in @($r.Results)) {
            $vm = $script:Ui.Cleanups[$x.Id]
            if ($vm) { $vm.LastResult = "Son işlem: $($x.StatusText) — $($x.Message)"; $vm.LastResultKind = $x.Status }
            if ($x.RestartRequired) { $script:Ui.PendingRestart = $true }
        }
        Update-LtRestartBadge
        $s = $r.Summary
        $sim = @(@($r.Results) | Where-Object { $_.Simulated }).Count
        if ($sim -gt 0) {
            $head = 'Kuru çalışma: {0} işlem simüle edildi, {1} desteklenmiyor. Gerçek sistemde değişiklik yapılmadı.' -f $sim, $s.NotSupported
            $intro = 'Hiçbir dosya silinmedi, uygulama kapatılmadı veya komut çalıştırılmadı.'
        } else {
            $head = 'Temizlik bitti: {0} · {1} başarılı, {2} kısmen, {3} atlandı, {4} desteklenmiyor, {5} başarısız' -f (Get-LtCleanupTotalText -Results @($r.Results)), $s.Success, $s.Partial, $s.Skipped, $s.NotSupported, $s.Failed
            $intro = 'Boyutlar yalnızca gerçekten silinen dosyalardan veya ölçülen boş alan farkından hesaplandı. DISM, SFC gibi bakım işlemleri açılan alanı bildirmez; bunlar için boyut gösterilmez.'
        }
        Set-LtStatus $head
        [void](Show-LtReportDialog -Owner $script:Ui.Window -Title 'Sonuç' -Head $head -Intro $intro -Rows @(ConvertTo-LtResultRows $r.Results) -Mode Info)
    }
    [void](Start-LtJob -Title 'Temizlik çalışıyor' -Body $body -JobArgs @{ Ids = @($items | ForEach-Object { $_.Id }); Ctx = $script:Ui.Ctx; Close = @($close) } -OnDone $onDone)
}

function ConvertTo-LtCleanupPreviewRows {
    param([object[]]$Items)
    foreach ($x in @($Items)) {
        $lines = New-Object System.Collections.ArrayList
        foreach ($t in @($x.Targets)) {
            switch ([string]$t.State) {
                'Scanned'    { [void]$lines.Add(('• {0}: {1} dosya, {2} — {3}' -f $t.Label, $t.Files, (Format-LtBytes $t.Bytes), $t.Scope)) }
                'Partial'    { [void]$lines.Add(('• {0}: en az {1} dosya, {2} (eksik: {3}) — {4}' -f $t.Label, $t.Files, (Format-LtBytes $t.Bytes), $t.Note, $t.Scope)) }
                'Missing'    { [void]$lines.Add(('• {0}: {1}' -f $t.Label, $t.Note)) }
                'OutOfScope' { [void]$lines.Add(('• {0}: {1}' -f $t.Label, $t.Note)) }
            }
            if ($t.State -eq 'Scanned' -and $t.Note) { [void]$lines.Add("    ($($t.Note))") }
        }
        foreach ($n in @($x.Notes)) { [void]$lines.Add("ⓘ $n") }
        if ($x.Keeps -and $x.Status -eq 'Ready') { [void]$lines.Add("Korunur: $($x.Keeps).") }
        switch ([string]$x.Status) {
            'Ready' {
                if ($x.Kind -eq 'Maintenance') { $kind = 'NoChange'; $kindText = 'Boyut hesaplanmadı'; $msg = 'Dosya temizliği değil veya boyutu önceden güvenilir hesaplanamaz.' }
                elseif ($x.Complete) { $kind = 'WillChange'; $kindText = ('~{0}' -f (Format-LtBytes $x.Bytes)); $msg = "$($x.Files) dosya (tahmini)." }
                else { $kind = 'Partial'; $kindText = ('en az ~{0}' -f (Format-LtBytes $x.Bytes)); $msg = "$($x.Files) dosya; bazı alanlar taranamadı veya ek adımların boyutu hesaplanmadı." }
            }
            'NotSupported' { $kind = 'NotSupported'; $kindText = 'Desteklenmiyor'; $msg = $x.Message }
            'Simulated'    { $kind = 'NoChange'; $kindText = 'Kuru çalışma'; $msg = $x.Message }
            'Cancelled'    { $kind = 'Partial'; $kindText = 'İptal'; $msg = 'Önizleme iptal edildi; sayılar eksik.' }
            default        { $kind = 'Error'; $kindText = 'Okunamadı'; $msg = $x.Message }
        }
        New-LtReportRow -Title $x.Title -Kind $kind -KindText $kindText -Message $msg -Changes ($lines -join "`n")
    }
}

function Invoke-LtCleanupPreviewFlow {
    <# Salt okunur: dosya silmez, uygulama kapatmaz, bakim komutu calistirmaz. #>
    param([Parameter(Mandatory)][string]$Page)
    if (-not $script:Ui.Ctx) { Set-LtStatus 'Sistem bilgisi henüz okunuyor; birkaç saniye sonra tekrar deneyin.'; return }
    $items = @($script:Ui.Cleanups.Values | Where-Object { $_.Page -eq $Page -and $_.Selected -and $_.IsAvailable } | Sort-Object Title)
    if ($items.Count -eq 0) { Set-LtStatus 'Önce en az bir temizlik öğesi seçin.'; return }
    $body = { param($a, $p, $c) Get-LtCleanupPreview -Ids $a.Ids -Context $a.Ctx -Progress $p -Cancel $c }
    $onDone = {
        param($r, $errs)
        if (-not $r) { Set-LtStatus 'Önizleme hazırlanamadı; günlüğe bakın.'; return }
        foreach ($x in @($r.Items)) {
            $vm = $script:Ui.Cleanups[$x.Id]
            if ($vm -and $x.Status -eq 'Ready' -and $x.Kind -ne 'Maintenance') { $vm.LastResult = ('Son önizleme: ~{0}, {1} dosya (tahmini; silinmedi)' -f (Format-LtBytes $x.Bytes), $x.Files); $vm.LastResultKind = '' }
        }
        if ($r.Simulated) {
            $head = 'Kuru çalışma: önizleme gerçek dosya sistemini taramadı'
        } else {
            $head = 'Tahmini temizlenebilir: {0}{1} · {2} dosya' -f $(if ($r.Complete) { '' } else { 'en az ' }), (Format-LtBytes $r.Bytes), $r.Files
            if ($r.Cancelled) { $head += ' (iptal edildi; eksik)' }
        }
        $intro = 'Önizleme hiçbir dosyayı silmedi veya değiştirmedi, uygulama kapatmadı, bakım komutu çalıştırmadı. Rakamlar tahminidir: kullanımdaki dosyalar silme sırasında atlanabilir ve dosyalar bu arada değişebilir. Silme anında yollar, kapsam ve bağlantılar yeniden denetlenir.'
        $foot = 'Temizlik GERİ ALINAMAZ; önizleme bir geri alma garantisi değildir. Boyutu güvenilir hesaplanamayan bakım işlemleri için sayı gösterilmez.'
        Set-LtStatus $head
        [void](Show-LtReportDialog -Owner $script:Ui.Window -Title 'Temizlik önizlemesi' -Head $head -Intro $intro -Rows @(ConvertTo-LtCleanupPreviewRows $r.Items) -Mode Info -Foot $foot)
    }
    [void](Start-LtJob -Title 'Temizlik önizlemesi (salt okunur)' -Body $body -JobArgs @{ Ids = @($items | ForEach-Object { $_.Id }); Ctx = $script:Ui.Ctx } -OnDone $onDone)
}

# ---------------------------------------------------------------------------
# Degisiklik gecmisi
# ---------------------------------------------------------------------------
function Update-LtHistory {
    $c = $script:Ui.C
    $ledger = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
    foreach ($e in @(Get-LtLedgerEntries | Sort-Object { [string]$_.time } -Descending)) {
        $titles = @(@($e.tweakIds) | ForEach-Object { if ($script:Ui.Tweaks.ContainsKey($_)) { $script:Ui.Tweaks[$_].Title } else { $_ } }) -join ', '
        $target = $e.key; $orig = ''
        try { $target = Get-LtActionTarget $e.action; $orig = Format-LtActionState $e.action $e.original } catch { $orig = '?' }
        $t = ''; try { $t = ([datetime]$e.time).ToString('g') } catch { $t = [string]$e.time }
        $ledger.Add([pscustomobject]@{ Tweak = $titles; Target = $target; Original = $orig; Time = $t; TweakIds = @($e.tweakIds) })
    }
    $c.LedgerList.ItemsSource = $ledger
    $ops = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
    $outcomeText = @{ completed = 'Tamamlandı'; cancelled = 'İptal edildi'; incomplete = 'YARIM KALDI'; 'recovered-reverted' = 'Kurtarıldı (geri alındı)'; 'recovered-kept' = 'Kurtarıldı (bırakıldı)' }
    foreach ($o in @(Get-LtOperations | Sort-Object Id -Descending | Select-Object -First 200)) {
        $oc = if ($outcomeText.ContainsKey([string]$o.Outcome)) { $outcomeText[[string]$o.Outcome] } else { [string]$o.Outcome }
        $ops.Add([pscustomobject]@{ Id = $o.Id; Kind = $o.Kind; Changes = $o.Changes; Outcome = $oc; Started = $o.Started })
    }
    $c.OpsList.ItemsSource = $ops
}

function Update-LtRecoveryBanner {
    $c = $script:Ui.C
    $inc = @()
    try { $inc = @(Get-LtIncompleteOperations) } catch { Add-LtLogLine "Journal okunamadı: $($_.Exception.Message)" }
    if ($inc.Count -eq 0) { $c.RecoveryBanner.Visibility = 'Collapsed'; $script:Ui.RecoveryOp = $null; return }
    $op = $inc[0]
    $script:Ui.RecoveryOp = $op.Id
    $c.TxtRecovery.Text = "Yarım kalmış işlem bulundu: $($op.Id) ($($op.Kind), $($op.Changes) değişiklik kaydı). Uygulama işlem sırasında kapanmış olabilir. Değişiklikleri işlem öncesine döndürebilir veya olduğu gibi bırakabilirsiniz (özgün değerler 'Değişiklik Geçmişi'nde kalır)." + $(if ($inc.Count -gt 1) { " (Toplam $($inc.Count) yarım işlem.)" } else { '' })
    $c.RecoveryBanner.Visibility = 'Visible'
}

# ---------------------------------------------------------------------------
# Donanim izleme (yerel API; WMI/yerellestirilmis sayac kullanilmaz)
# ---------------------------------------------------------------------------
function Update-LtHardwareBar {
    $c = $script:Ui.C
    if (-not $script:Ui.NativeOk) { return }
    try {
        $cpu = [LivnTools.NativeInfo]::CpuPercent()
        if ($cpu -ge 0) { $c.RunCpu.Text = ('{0:N0}%' -f $cpu); $c.ProgCpu.Value = $cpu }
        $m = [LivnTools.NativeInfo]::Memory()
        if ($m[0] -gt 0) {
            $used = [double]($m[0] - $m[1])
            $c.RunRam.Text = ('{0:N0}%  ({1:N1} / {2:N1} GB)' -f (100 * $used / $m[0]), ($used / 1GB), ($m[0] / 1GB))
            $c.ProgRam.Value = 100 * $used / $m[0]
        }
        $up = [TimeSpan]::FromMilliseconds([LivnTools.NativeInfo]::UptimeMs())
        $c.TxtUptime.Text = ('Çalışma süresi: {0}g {1}s {2}d' -f $up.Days, $up.Hours, $up.Minutes)
    } catch { $script:Ui.NativeOk = $false }
}

# ---------------------------------------------------------------------------
# Betik calistirma
# ---------------------------------------------------------------------------
function Invoke-LtScriptFlow {
    $c = $script:Ui.C
    $code = [string]$c.ScriptEditor.Text
    if ([string]::IsNullOrWhiteSpace($code)) { Set-LtStatus 'Çalıştırılacak kod yok.'; return }
    $kind = if ($c.CmbScriptKind.SelectedIndex -eq 1) { 'Batch' } else { 'PowerShell' }
    # Asil koruma motorda (Invoke-LtUserScript -> Assert-LtLiveSystem); burada kullaniciya erken bilgi verilir
    if (-not (Test-LtLiveSystem)) { Set-LtStatus 'Kuru çalışma modunda betik çalıştırılmaz.'; return }
    $preview = (($code -split "`r?`n") | Select-Object -First 12) -join "`n"
    $a = Show-LtMessage -Owner $script:Ui.Window -Buttons YesNo -Icon Warning -Text ("Bu {0} betiği YÖNETİCİ yetkisiyle çalıştırılacak ve geri alma sistemine dahil DEĞİL.`n`nİlk satırlar:`n{1}`n`nDevam edilsin mi?" -f $kind, $preview)
    if ($a -ne 'Yes') { return }
    $body = { param($a, $p, $c) [void](Invoke-LtUserScript -Code $a.Code -Kind $a.Kind -Cancel $c) }
    [void](Start-LtJob -Title 'Betik çalışıyor' -Body $body -JobArgs @{ Code = $code; Kind = $kind })
}

# ---------------------------------------------------------------------------
# Baslatma
# ---------------------------------------------------------------------------
function Initialize-LtSetupView {
    $c = $script:Ui.C
    $script:Ui.SetupApps = @(Get-LtSetupApps | ForEach-Object {
        $_ | Add-Member -NotePropertyName State -NotePropertyValue 'NotRead' -PassThru |
             Add-Member -NotePropertyName StateText -NotePropertyValue (Get-LtSetupStateText 'NotRead') -PassThru
    })
    $script:Ui.SetupSelected = @{}
    $script:Ui.SetupBinding = $false
    $script:Ui.SetupInventory = @{ Result = $null; LastAttempt = $null; Loading = $false; Pending = $false }
    $c.CmbSetupCategory.ItemsSource = @('Tümü') + @($script:Ui.SetupApps.Category | Select-Object -Unique)
    $c.CmbSetupCategory.SelectedIndex = 0
    Update-LtSetupAppsView
    $c.SetupAppList.Add_SelectionChanged({ Sync-LtSetupSelection })
    $c.TxtSetupSearch.Add_TextChanged({ Update-LtSetupAppsView })
    $c.CmbSetupCategory.Add_SelectionChanged({ Update-LtSetupAppsView })
    $c.ChkSetupSelected.Add_Click({ Update-LtSetupAppsView })
    $c.BtnSetupClear.Add_Click({ $script:Ui.SetupSelected.Clear(); Update-LtSetupAppsView })
    $c.BtnSetupInventory.Add_Click({ [void](Request-LtSetupInventory -Force) })
    if ($c.Contains('BtnWingetHelp') -and $c.BtnWingetHelp) {
        $c.BtnWingetHelp.Add_Click({
            try {
                $opened = Open-LtWingetHelp -Target Store
                if ($opened -eq 'Store') { Set-LtStatus 'Microsoft Store: Uygulama Yükleyici sayfası açıldı. Güncelledikten sonra "Kurulum durumunu yenile".' }
                else { Set-LtStatus 'Microsoft Store yok (LTSC/Server olabilir); WinGet kurulum yönergesi açıldı.' }
            } catch { Set-LtStatus $_.Exception.Message }
        })
    }
    Update-LtSetupInventoryView
}

function Update-LtSetupInventoryView {
    $inv = $script:Ui.SetupInventory
    $c = $script:Ui.C
    foreach ($app in @($script:Ui.SetupApps)) {
        # Okuma surerken onceki sonuc gosterilmeye devam eder; hic sonuc yoksa "okunuyor"
        $state = if ($inv.Loading -and $null -eq $inv.Result) { 'Loading' } else { Get-LtSetupAppState -Inventory $inv.Result -Id $app.Id }
        $app.State = $state
        $app.StateText = Get-LtSetupStateText $state
    }
    $r = $inv.Result
    if ($inv.Loading) {
        $text = 'Kurulu uygulamalar okunuyor (WinGet ve Windows uygulama listesi, salt okunur; kurulum veya güncelleme yapılmaz)…'
    } elseif ($null -eq $r) {
        $text = 'Kurulu durumu henüz okunmadı.'
    } elseif ($r.Status -eq 'Ok') {
        $installed = @($script:Ui.SetupApps | Where-Object { $_.State -like 'Installed*' }).Count
        $external = @($script:Ui.SetupApps | Where-Object { $_.State -eq 'InstalledExternal' }).Count
        $text = 'Kurulu: {0}{4} · Kurulu değil: {1} · Okunma: {2:HH:mm:ss}{3}. Kurulu olanlar seçilse de yükseltilmez; kurulum anında yeniden denetlenir.' -f $installed, (@($script:Ui.SetupApps).Count - $installed), ([datetime]$r.Time), $(if ($r.Simulated) { ' · deneme envanteri' } else { '' }), $(if ($external) { " ($external tanesi WinGet dışı kurulum)" } else { '' })
    } else {
        $installed = @($script:Ui.SetupApps | Where-Object { $_.State -like 'Installed*' }).Count
        $text = "WinGet durumu okunamadı: $($r.Message) Windows uygulama listesinde bulunan $installed uygulama kurulu gösterildi; diğerlerinin durumu bilinmiyor. Yeniden denemek için düğmeyi kullanın."
    }
    $c.TxtSetupInventory.Text = $text
    $c.BtnSetupInventory.Content = if ($r -and $r.Status -ne 'Ok' -and -not $inv.Loading) { 'Yeniden dene' } else { 'Kurulum durumunu yenile' }
    if ($c.Contains('BtnWingetHelp') -and $c.BtnWingetHelp) {
        $c.BtnWingetHelp.Visibility = if ($r -and @('WingetMissing', 'WingetOutdated') -contains [string]$r.Status) { 'Visible' } else { 'Collapsed' }
    }
    $c.BtnSetupInventory.IsEnabled = -not $inv.Loading
    Update-LtSetupAppsView
}

function Request-LtSetupInventory {
    <# -Force: kullanici istegi (30 sn sinir). -AfterChange: kurulum/kaldirma sonrasi zorunlu yenileme. #>
    param([switch]$Force, [switch]$AfterChange)
    $inv = $script:Ui.SetupInventory
    if ($null -eq $inv) { return $false }
    if ($script:Ui.Job -and $script:Ui.Job.Title -eq 'Uygulama işlemleri') {
        # Kurulum surerken ikinci winget sorgusu baslatilmaz; bitince yenilenir
        $inv.Pending = $true
        return $false
    }
    $running = [bool]$script:Ui.SideJob
    if ($AfterChange) { $chk = Test-LtSetupInventoryRefresh -Running:$running }
    else { $chk = Test-LtSetupInventoryRefresh -LastAttempt $inv.LastAttempt -Force:$Force -Running:$running }
    if (-not $chk.Allowed) {
        if ($AfterChange -and $running) { $inv.Pending = $true }
        if ($Force -or $AfterChange) { Set-LtStatus $chk.Reason }
        return $false
    }
    $inv.LastAttempt = Get-Date
    $inv.Loading = $true
    Update-LtSetupInventoryView
    $started = Start-LtSideJob -Title 'Kurulu uygulamalar okunuyor' -Body { param($a, $p, $c) Get-LtSetupInventory } -OnDone {
        param($r, $errs)
        $inv = $script:Ui.SetupInventory
        $inv.Loading = $false
        if ($r -and $r.PSObject.Properties['Status']) { $inv.Result = $r }
        else { $inv.Result = [pscustomobject]@{ Status = 'Error'; Message = ('Envanter işi tamamlanamadı: ' + (@($errs) -join '; ')); Time = (Get-Date); InstalledIds = @(); Simulated = $false } }
        Update-LtSetupInventoryView
        if ($inv.Result.Status -ne 'Ok') { Set-LtStatus 'Uygulama kurulum durumu okunamadı; ayrıntı Format Sonrası sayfasında.' }
        if ($inv.Pending) { $inv.Pending = $false; [void](Request-LtSetupInventory -AfterChange) }
    }
    if (-not $started) { $inv.Loading = $false; Update-LtSetupInventoryView }
    return $started
}
function Set-LtSetupPackageSelection {
    param([string[]]$Ids=@())
    $allowed = @($script:Ui.SetupApps | ForEach-Object { $_.Id })
    foreach ($id in $Ids) { if ($allowed -notcontains $id) { throw "Bilinmeyen uygulama seçimi: $id" } }
    $script:Ui.SetupSelected.Clear()
    foreach ($id in $Ids) { $script:Ui.SetupSelected[$id]=$true }
    Update-LtSetupAppsView
}
function Get-LtChosenSetupApps {
    @($script:Ui.SetupApps | Where-Object { $script:Ui.SetupSelected.ContainsKey($_.Id) })
}
function Sync-LtSetupSelection {
    if ($script:Ui.SetupBinding) { return }
    # Only visible rows may change. Hidden selections remain in the installation basket.
    foreach ($item in @($script:Ui.C.SetupAppList.ItemsSource)) { [void]$script:Ui.SetupSelected.Remove($item.Id) }
    foreach ($item in @($script:Ui.C.SetupAppList.SelectedItems)) { $script:Ui.SetupSelected[$item.Id]=$true }
    Update-LtSetupSelectionText
    if ($script:Ui.C.ChkSetupSelected.IsChecked) { Update-LtSetupAppsView }
}
function Update-LtSetupSelectionText {
    $visible = @($script:Ui.C.SetupAppList.ItemsSource)
    $selected = @(Get-LtChosenSetupApps)
    $visibleIds = @($visible | ForEach-Object { $_.Id })
    $hidden = @($selected | Where-Object { $visibleIds -notcontains $_.Id }).Count
    $script:Ui.C.TxtSetupSelection.Text = "Görünen: $($visible.Count) / $($script:Ui.SetupApps.Count) · Seçili: $($selected.Count) · Filtre dışında seçili: $hidden"
}
function Update-LtSetupAppsView {
    $c = $script:Ui.C
    $category = [string]$c.CmbSetupCategory.SelectedItem
    if (-not $category) { $category='Tümü' }
    $items = @(Find-LtSetupApps -Apps $script:Ui.SetupApps -Query $c.TxtSetupSearch.Text -Category $category -SelectedIds @($script:Ui.SetupSelected.Keys) -SelectedOnly:([bool]$c.ChkSetupSelected.IsChecked))
    $script:Ui.SetupBinding=$true
    try {
        $c.SetupAppList.ItemsSource=$items
        $c.SetupAppList.SelectedItems.Clear()
        foreach ($item in $items) { if ($script:Ui.SetupSelected.ContainsKey($item.Id)) { [void]$c.SetupAppList.SelectedItems.Add($item) } }
    } finally { $script:Ui.SetupBinding=$false }
    Update-LtSetupSelectionText
}

function Invoke-LtSetupUiAction {
    param([ValidateSet('Install','Remove')][string]$Mode)
    $items = @(if ($Mode -eq 'Install') { Get-LtChosenSetupApps } else { $script:Ui.C.SetupRemoveList.SelectedItems })
    if ($items.Count -eq 0) { Set-LtStatus 'Önce uygulama seçin.'; return }
    $note = if ($Mode -eq 'Install') { 'WinGet kaynağının ve seçili paketlerin lisans sözleşmelerini kabul ederek kurulumu başlatacaksınız. Kurulu olanlar yükseltilmez. Bu işlem Livn ayar geri almasına dahil değildir.' } else { 'Bu uygulamalar mevcut kullanıcıdan kaldırılacak. Uygulama verileri kaybolabilir; Livn üzerinden geri alınamaz. Store üzerinden yeniden kurulum verileri geri getirmez.' }
    $live = Test-LtLiveSystem
    $actionText = if (-not $live) { 'Simüle et' } elseif ($Mode -eq 'Install') { 'Kurulumu başlat' } else { 'Kaldır' }
    $intro = if ($live) { $note } else { 'KURU ÇALIŞMA: seçili uygulamalar yalnız simüle edilir; indirme, kurulum veya kaldırma yapılmaz.' }
    $rows = @(foreach ($item in $items) {
        $state = [string](Get-LtProp $item 'State' '')
        if ($Mode -eq 'Install' -and $state -like 'Installed*') {
            New-LtReportRow -Title $item.Title -Kind 'NoChange' -KindText 'Kurulu görünüyor' -Message "$($item.Id) — yükseltilmez; kurulum anında yeniden denetlenir ve kuruluysa atlanır."
        } else {
            New-LtReportRow -Title $item.Title -Kind 'WillChange' -KindText $actionText -Message $item.Id
        }
    })
    $review = Show-LtReportDialog -Owner $script:Ui.Window -Title 'Uygulama işlemleri' -Head "$($items.Count) uygulama seçildi" -Intro $intro -Rows $rows -Mode Confirm -OkText $actionText -Foot 'Filtre dışında kalan seçimler de bu listede gösterilir.'
    if (-not $review.Confirmed) { return }
    $body = { param($a,$p,$c) Invoke-LtSetupBatch -Mode $a.Mode -Ids $a.Ids -Accepted -Progress $p -Cancel $c }
    [void](Start-LtJob -Title 'Uygulama işlemleri' -Body $body -JobArgs @{ Mode=$Mode; Ids=@($items | ForEach-Object { $_.Id }) } -OnDone {
        param($r,$e)
        if ($r) { Reset-LtAppDetection; Update-LtCleanupAvailability; $script:Ui.C.TxtSetupResults.Text = (@($r.Results | ForEach-Object { "$($_.Title): $($_.StatusText) — $($_.Message)" }) -join "`n"); Set-LtStatus 'Uygulama işlemleri tamamlandı; sonuçları kontrol edin.' }
        # Kurulum/kaldirma sonrasi envanter yeniden okunur (sinir uygulanmaz; okuma suruyorsa sonra)
        [void](Request-LtSetupInventory -AfterChange)
    })
}

function Start-LtApp {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$AppRoot, [Parameter(Mandatory)][string]$DataRoot, [ValidateSet('Windows', 'Memory')][string]$Backend = 'Windows')

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    Initialize-LtViewModels

    $queue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
    Initialize-LivnTools -DataRoot $DataRoot -Backend $Backend -LogQueue $queue

    [xml]$xaml = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'MainWindow.xaml'), [System.Text.Encoding]::UTF8)
    $window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))

    $names = @('RootBorder', 'TxtVersion', 'BadgeBackend', 'BtnMinimize', 'BtnMaximize', 'BtnClose', 'RunCpu', 'ProgCpu', 'RunRam', 'ProgRam',
        'TxtOs', 'TxtHw', 'BadgeRestart', 'TxtRestart', 'TxtUptime', 'RecoveryBanner', 'BtnRecoveryRevert', 'BtnRecoveryKeep', 'TxtRecovery',
        'NavList', 'TxtPageTitle', 'TxtPageDesc', 'PresetBar', 'BtnApplyAllPages', 'BtnPresetMinimal', 'BtnPresetStandard', 'BtnPresetAggressive',
        'BtnPresetClear', 'TxtPresetInfo', 'Toolbar', 'BtnApply', 'BtnRevertPrev', 'BtnRevertDefault', 'BtnBackupState', 'BtnSelectAll', 'BtnSelectNone',
        'BtnRefresh', 'BtnRunCleanup', 'MainScroll', 'TxtPageInfo', 'TweakGroups', 'TxtCleanupHeader', 'CleanupGroups', 'HistoryPanel', 'LedgerList',
        'BtnHistoryRevert', 'BtnHistoryRestoreFile', 'BtnHistoryLegacyReg', 'BtnHistoryOpenData', 'OpsList', 'ScriptPanel', 'BtnScriptImport',
        'CmbScriptKind', 'BtnScriptRun', 'BtnScriptClear', 'ScriptEditor', 'ProgressPanel', 'BtnCancel', 'TxtProgress', 'ProgMain',
        'BtnLogToggle', 'BtnLogSave', 'BtnLogClear', 'LogBox', 'TxtDataRoot', 'TxtStatus',
        'UserPreferencePanel', 'CmbMenuDelay', 'NetworkPanel', 'CmbNetworkDevice', 'GraphicsPanel', 'BtnGraphicsSettings', 'CmbMsiDevice', 'BtnReadGraphics', 'TxtGraphicsState', 'ExternalToolsPanel', 'CmbExternalTool', 'BtnExternalTool', 'BtnWindowsPower', 'CmbInstalledPowerPlan', 'TxtPowerPlanStatus', 'BtnRefreshPowerPlans', 'BtnSelectIslc', 'TxtIslcProfile', 'BtnPresetResponsive', 'SetupPanel', 'BtnProfileSave', 'BtnProfileLoad', 'BtnProfileApply', 'TxtSetupProfile', 'SetupAppList', 'TxtSetupSearch', 'CmbSetupCategory', 'ChkSetupSelected', 'BtnSetupClear', 'BtnSetupInstall', 'BtnSetupScan', 'SetupRemoveList', 'BtnSetupRemove', 'TxtSetupResults', 'TxtSetupSelection', 'ChkCleanupAvailable', 'BtnSetupInventory', 'TxtSetupInventory', 'BtnCleanupPreview', 'BtnPresetMaxPerf', 'BtnWingetHelp',
        'BtnPresetGamer', 'HealthPanel', 'BtnHealthRun', 'BtnHealthGamer', 'BtnHealthSave', 'TxtHealthSummary', 'HealthList', 'StartupPanel', 'BtnStartupDisable', 'BtnStartupEnable', 'BtnStartupRefresh', 'StartupList', 'TxtStartupInfo',
        'TxtPingTarget', 'BtnPingRun', 'BtnDnsRun', 'TxtPingResult', 'BtnGpuAddGame', 'BtnGpuClearGames', 'TxtGpuGames', 'TxtNetworkTarget', 'TxtMsiTarget',
        'KitPanel', 'BtnKitBrowse', 'TxtKitTarget', 'ChkKitNet', 'ChkKitOther', 'ChkKitGpu', 'ChkKitApps', 'ChkKitLivn', 'ChkKitSaves', 'ChkKitWifi', 'BtnKitPreview', 'BtnKitCreate', 'TxtKitPlan',
        'BtnKitFind', 'BtnKitOpen', 'TxtKitSummary', 'BtnKitDrivers', 'BtnKitWifi', 'BtnKitApps', 'BtnKitTweaks', 'BtnKitSaves')
    $controls = @{}
    foreach ($n in $names) {
        $ctl = $window.FindName($n)
        if ($null -eq $ctl) { throw "Arayüz öğesi bulunamadı: $n" }
        $controls[$n] = $ctl
    }

    $script:Ui = @{
        Window = $window; C = $controls; LogQueue = $queue; DataRoot = (Get-LtDataRoot); AppRoot = $AppRoot
        ModulePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'LivnTools.psm1')
        Job = $null; WorkerRS = $null; Ctx = $null; CurrentPage = ''; StateLoaded = @{}; RefreshQueue = (New-Object System.Collections.ArrayList)
        Tweaks = @{}; TweakGroups = @{}; Cleanups = @{}; CleanupGroups = @{}; CleanupInit = $false
        PendingRestart = $false; ActivePlan = ''; RecoveryOp = $null; NativeOk = $false; PendingMode = ''; InTick = $false
    }
    $c = $controls
    $c.TxtVersion.Text = "v$(Get-LtVersion)"
    $window.Title = "Livn Tools v$(Get-LtVersion)"
    $c.TxtDataRoot.Text = "Veri: $(Get-LtDataRoot)"
    if ($Backend -eq 'Memory') { $c.BadgeBackend.Visibility = 'Visible' }
    try { Initialize-LtNative; $script:Ui.NativeOk = $true } catch { $script:Ui.NativeOk = $false }

    New-LtTweakItems
    New-LtCleanupItems

    # --- pencere denetimleri ---
    $c.BtnClose.Add_Click({ $script:Ui.Window.Close() })
    $c.BtnMinimize.Add_Click({ $script:Ui.Window.WindowState = 'Minimized' })
    $c.BtnMaximize.Add_Click({ if ($script:Ui.Window.WindowState -eq 'Maximized') { $script:Ui.Window.WindowState = 'Normal' } else { $script:Ui.Window.WindowState = 'Maximized' } })
    $window.Add_StateChanged({
        # WindowStyle=None + tam ekranda kenar tasmasini onle
        $script:Ui.C.RootBorder.Margin = if ($script:Ui.Window.WindowState -eq 'Maximized') { New-Object System.Windows.Thickness(7) } else { New-Object System.Windows.Thickness(0) }
    })

    # --- gezinti ---
    $c.NavList.Add_SelectionChanged({
        $sel = $script:Ui.C.NavList.SelectedItem
        if ($sel -and $sel.Tag) { Show-LtPage -Page ([string]$sel.Tag) }
    })

    # --- arac cubugu ---
    $c.BtnApply.Add_Click({ Invoke-LtTweakFlow -Ids (Get-LtSelectedTweakIds @($script:Ui.CurrentPage)) -Mode Apply })
    $c.BtnRevertPrev.Add_Click({ Invoke-LtTweakFlow -Ids (Get-LtSelectedTweakIds @($script:Ui.CurrentPage)) -Mode RevertPrevious })
    $c.BtnRevertDefault.Add_Click({ Invoke-LtTweakFlow -Ids (Get-LtSelectedTweakIds @($script:Ui.CurrentPage)) -Mode RevertDefault })
    $c.BtnApplyAllPages.Add_Click({ Invoke-LtTweakFlow -Ids (Get-LtSelectedTweakIds $script:LtOptPages) -Mode Apply })
    $c.BtnRefresh.Add_Click({ $p = $script:Ui.CurrentPage; $script:Ui.StateLoaded[$p] = $false; Update-LtPageState -Page $p })
    $c.BtnSelectAll.Add_Click({
        $p = $script:Ui.CurrentPage
        if ($script:LtOptPages -contains $p) {
            # Guvenlik ve ozel secimli (guc plani vb.) ayarlar toplu secime dahil edilmez
            foreach ($t in $script:Ui.Tweaks.Values) { if ($t.Page -eq $p -and $t.IsSupported -and $t.Risk -ne 'Security' -and -not $t.Exclusive) { $t.Selected = $true } }
            Set-LtStatus 'Desteklenen ayarlar seçildi (güvenlik ve tek seçimli gruplar hariç).'
        }
        if ($script:Ui.CleanupGroups.ContainsKey($p) -and $script:LtPages[$p].Kind -eq 'Cleanup') {
            foreach ($x in $script:Ui.Cleanups.Values) { if ($x.Page -eq $p -and $x.IsAvailable) { $x.Selected = $true } }
        }
    })
    $c.BtnSelectNone.Add_Click({
        $p = $script:Ui.CurrentPage
        foreach ($t in $script:Ui.Tweaks.Values) { if ($t.Page -eq $p) { $t.Selected = $false } }
        foreach ($x in $script:Ui.Cleanups.Values) { if ($x.Page -eq $p) { $x.Selected = $false } }
    })
    $c.BtnRunCleanup.Add_Click({ Invoke-LtCleanupFlow -Page $script:Ui.CurrentPage })
    $c.BtnCleanupPreview.Add_Click({ Invoke-LtCleanupPreviewFlow -Page $script:Ui.CurrentPage })
    $c.BtnBackupState.Add_Click({
        $p = $script:Ui.CurrentPage
        $ids = @($script:Ui.Tweaks.Values | Where-Object { $_.Page -eq $p } | ForEach-Object { $_.Id })
        $body = { param($a, $pr, $cn) Export-LtStateBackup -TweakIds $a.Ids -Context $a.Ctx -Label $a.Page }
        [void](Start-LtJob -Title 'Durum yedeği alınıyor' -Body $body -JobArgs @{ Ids = $ids; Ctx = $script:Ui.Ctx; Page = $p } -OnDone {
            param($r, $e)
            if ($r) { Set-LtStatus "Durum yedeği: $($r.Path) ($($r.Count) değer)"; [void](Show-LtMessage -Owner $script:Ui.Window -Text "Durum yedeği kaydedildi:`n$($r.Path)`n`n$($r.Count) değer (olmayan değerler dahil). Geri yüklemek için: Değişiklik Geçmişi > Durum yedeğinden geri yükle.") }
        })
    })

    $c.ChkCleanupAvailable.Add_Click({ Update-LtCleanupGroupsView })
    Initialize-LtSetupView
    $c.BtnProfileSave.Add_Click({
        if (-not $script:Ui.Ctx) { return }
        $selected = @(Get-LtSelectedTweakIds $script:LtOptPages)
        $allowed = @(Get-LtPortableTweakIds)
        $portable = @($selected | Where-Object { $allowed -contains $_ })
        $excluded = @($selected | Where-Object { $allowed -notcontains $_ })
        if ($excluded.Count -gt 0) {
            [void](Show-LtMessage -Owner $script:Ui.Window -Text ("Donanıma/sisteme özel bu seçimler profile taşınmayacak:`n" + ($excluded -join ', ')))
        }
        $dlg = New-Object Microsoft.Win32.SaveFileDialog
        $dlg.Filter = 'Livn format profili|*.json'; $dlg.FileName = 'Livn-format-profilim.json'
        if (-not $dlg.ShowDialog($script:Ui.Window)) { return }
        $body = {
            param($a, $p, $c)
            $v = New-LtSetupProfile -TweakIds $a.Ids -PackageIds $a.Apps -Context $a.Ctx
            Save-LtSetupProfile -Path $a.Path -Value $v
            [pscustomobject]@{ Path=$a.Path }
        }
        [void](Start-LtJob -Title 'Profil kaydediliyor' -Body $body -JobArgs @{ Path=$dlg.FileName; Ids=$portable; Apps=@(Get-LtChosenSetupApps | ForEach-Object { $_.Id }); Ctx=$script:Ui.Ctx } -OnDone {
            param($r,$e)
            if ($r) { $script:Ui.C.TxtSetupProfile.Text = "Profil kaydedildi: $($r.Path). Dosyayı format öncesinde başka diske kopyalayın." }
        })
    })
    $c.BtnProfileLoad.Add_Click({
        $dlg = New-Object Microsoft.Win32.OpenFileDialog; $dlg.Filter='Livn format profili|*.json'
        if (-not $dlg.ShowDialog($script:Ui.Window)) { return }
        $body = { param($a,$p,$c) Read-LtSetupProfile -Path $a.Path }
        [void](Start-LtJob -Title 'Profil denetleniyor' -Body $body -JobArgs @{ Path=$dlg.FileName } -OnDone {
            param($r,$e)
            if (-not $r) { return }
            $script:Ui.ImportedProfile = $r
            foreach ($vm in $script:Ui.Tweaks.Values) { $vm.Selected=$false }
            foreach ($id in $r.TweakIds) { $script:Ui.Tweaks[$id].Selected=$true }
            if ($script:Ui.Ctx -and $r.ContainsKey('MenuDelayMs')) { $script:Ui.Ctx.MenuDelayMs=$r.MenuDelayMs }
            Set-LtSetupPackageSelection -Ids @($r.PackageIds)
            $script:Ui.C.TxtSetupProfile.Text = "Yüklendi: $(@($r.TweakIds).Count) ayar, $(@($r.PackageIds).Count) kurulum seçimi.`n$($r.TweakIds -join ', ')`nHenüz uygulanmadı. Ayarları önizleyin; uygulama kurulumu ayrı düğmeyle başlar."
        })
    })
    $c.BtnProfileApply.Add_Click({
        if (-not $script:Ui.ImportedProfile -or -not $script:Ui.Ctx) { Set-LtStatus 'Önce profil yükleyin.'; return }
        $v = Test-LtSetupProfile $script:Ui.ImportedProfile
        if ($v.ContainsKey('MenuDelayMs')) { $script:Ui.Ctx.MenuDelayMs = $v.MenuDelayMs }
        Invoke-LtTweakFlow -Ids @($v.TweakIds) -Mode Apply
    })
    $c.BtnSetupScan.Add_Click({
        $body = { param($a,$p,$c) [pscustomobject]@{ Apps=@(Get-LtSetupAppInventory) } }
        [void](Start-LtJob -Title 'İsteğe bağlı uygulamalar okunuyor' -Body $body -JobArgs @{} -OnDone {
            param($r,$e)
            if ($r) { $script:Ui.C.SetupRemoveList.ItemsSource = @($r.Apps); Set-LtStatus 'Uygulama listesi okundu. Kaldırılacakları kendiniz seçin.' }
        })
    })
    $c.BtnSetupInstall.Add_Click({ Invoke-LtSetupUiAction -Mode Install })
    $c.BtnSetupRemove.Add_Click({ Invoke-LtSetupUiAction -Mode Remove })

    $c.CmbExternalTool.ItemsSource = @(
        [pscustomobject]@{ Id = 'ISLC'; Label = 'ISLC 1.0.4.8 — bellek izleme' },
        [pscustomobject]@{ Id = 'ParkControl'; Label = 'ParkControl — Bitsum güç planı' },
        [pscustomobject]@{ Id = 'ProcessLasso'; Label = 'Process Lasso — CPU yük yönetimi' },
        [pscustomobject]@{ Id = 'PresentMon'; Label = 'PresentMon — performans ölçümü' }
    )
    $c.CmbExternalTool.SelectedIndex = 0
    $c.BtnExternalTool.Add_Click({
        try { Open-LtPerformanceResource -Id (Get-LtComboSelectedKey $script:Ui.C.CmbExternalTool 'Id') }
        catch { Set-LtStatus $_.Exception.Message }
    })
    $c.BtnWindowsPower.Add_Click({
        try { Open-LtPerformanceResource -Id WindowsPower }
        catch { Set-LtStatus $_.Exception.Message }
    })
    $c.BtnRefreshPowerPlans.Add_Click({
        if (-not $script:Ui.Ctx) { return }
        $body = { param($a, $p, $c) [pscustomobject]@{ Plans = @(Get-LtPowerPlanChoices) } }
        [void](Start-LtJob -Title 'Kurulu güç planları okunuyor' -Body $body -JobArgs @{} -OnDone {
            param($r, $e)
            if (-not $r) { Set-LtPowerPlanChoicesView -ErrorText ([string]$e); return }
            Set-LtPowerPlanChoicesView -Plans @($r.Plans)
            Set-LtStatus 'Planlar okundu. Bir plan seçip aşağıdaki kurulu plan ayarını önizleyin.'
        })
    })
    $c.CmbInstalledPowerPlan.Add_SelectionChanged({
        if ($script:Ui.PowerPlanBinding) { return }
        if (-not $script:Ui.Ctx) { return }
        $script:Ui.Ctx.SelectedPowerPlanGuid = Get-LtComboSelectedKey $script:Ui.C.CmbInstalledPowerPlan 'Guid'
        $script:Ui.Tweaks['power.installed'].Selected = $false
        $script:Ui.StateLoaded['Performance'] = $false
        Update-LtPageState -Page 'Performance'
    })
    $c.BtnSelectIslc.Add_Click({
        if (-not $script:Ui.Ctx) { return }
        $dlg = New-Object Microsoft.Win32.OpenFileDialog
        $dlg.Title = 'Resmî paketten çıkarttığınız ISLC uygulamasını seçin'
        $dlg.Filter = 'ISLC uygulaması|Intelligent standby list cleaner ISLC.exe'
        if (-not $dlg.ShowDialog($script:Ui.Window)) { return }
        $body = {
            param($a, $p, $c)
            $ctx = @{}; foreach ($k in $a.Ctx.Keys) { $ctx[$k] = $a.Ctx[$k] }
            $ctx.IslcPath = $a.Path
            [pscustomobject]@{ File = (Get-LtIslcFile $ctx); Profile = (Get-LtIslcProfile $ctx) }
        }
        [void](Start-LtJob -Title 'ISLC dosyası ve RAM profili okunuyor' -Body $body -JobArgs @{ Path = $dlg.FileName; Ctx = $script:Ui.Ctx } -OnDone {
            param($r, $e)
            if (-not $r) { return }
            $script:Ui.Ctx.IslcPath = $r.File.Path
            $script:Ui.Tweaks['mem.islc-autostart'].Selected = $false
            $old = if ($r.File.IsOlder) { ' Eski sürüm; resmî sayfada 1.0.4.8 var.' } else { '' }
            $script:Ui.C.TxtIslcProfile.Text = "ISLC $($r.File.Version)$old`n$($r.File.Path)`n$($r.Profile.Arguments)`n$($r.Profile.Note)"
            $script:Ui.StateLoaded['Performance'] = $false
            Set-LtStatus 'ISLC seçildi; otomatik başlatma henüz değiştirilmedi. Aşağıdaki ayarı önizleyip uygulayın.'
            Update-LtPageState -Page 'Performance'
        })
    })

    $c.CmbMenuDelay.ItemsSource = @(0,100,200,400,800)
    $c.CmbMenuDelay.Add_SelectionChanged({
        if (-not $script:Ui.Ctx) { return }
        $script:Ui.Ctx.MenuDelayMs = $script:Ui.C.CmbMenuDelay.SelectedItem
        $script:Ui.Tweaks['ui.menu-delay'].Selected = $false
        $script:Ui.StateLoaded['WinTweaks'] = $false
        Update-LtPageState -Page 'WinTweaks'
    })
    Initialize-LtDeviceSelectionView
    $c.BtnGraphicsSettings.Add_Click({
        try {
            Open-LtGraphicsSettings
            Set-LtStatus 'Windows Grafik Ayarları açıldı. Burada yapılan değişiklikler Livn Tools tarafından geri alınmaz.'
        } catch { Set-LtStatus $_.Exception.Message }
    })
    $c.BtnReadGraphics.Add_Click({
        if (-not $script:Ui.Ctx) { Set-LtStatus 'Sistem bilgisi henüz okunmadı.'; return }
        $selected = Get-LtComboSelectedKey $script:Ui.C.CmbMsiDevice 'InstanceId'
        $body = {
            param($a, $p, $c)
            $hags = Get-LtGraphicsConfiguration
            $msi = if ($a.InstanceId) { Get-LtMsiDeviceConfiguration -Context $a.Ctx -InstanceId $a.InstanceId } else { $null }
            @{ Hags = $hags; Msi = $msi }
        }
        [void](Start-LtJob -Title 'Grafik yapılandırması okunuyor' -Body $body -JobArgs @{ Ctx = $script:Ui.Ctx; InstanceId = $selected } -OnDone {
            param($r, $e)
            if (-not $r) { $script:Ui.C.TxtGraphicsState.Text = 'Yapılandırma okunamadı; önceki sonuç geçerli sayılmamalı.'; return }
            $text = Format-LtGraphicsStateText -Hags $r.Hags -Msi $r.Msi
            $script:Ui.C.TxtGraphicsState.Text = $text
        })
    })

    # --- presetler: yalnizca SECIM yapar ---
    $presetHandler = {
        param([string]$Name)
        if (-not $script:Ui.Ctx) { Set-LtStatus 'Sistem bilgisi henüz okunuyor; birkaç saniye sonra tekrar deneyin.'; return }
        $r = Resolve-LtPresetSelection -Name $Name -Context $script:Ui.Ctx
        foreach ($t in $script:Ui.Tweaks.Values) { $t.Selected = $false }
        foreach ($id in @($r.Selected)) { $vm = $script:Ui.Tweaks[$id]; if ($vm) { $vm.Selected = $true } }
        $script:Ui.C.TxtPresetInfo.Text = Format-LtPresetInfo $r
        Set-LtStatus "$($r.Title) hazır seçimi yüklendi: $($r.Description)"
        foreach ($pg in $script:LtOptPages) { if (-not $script:Ui.StateLoaded[$pg]) { Update-LtPageState -Page $pg } }
    }
    $c.BtnPresetMinimal.Add_Click({ & $presetHandler 'Minimal' }.GetNewClosure())
    $c.BtnPresetStandard.Add_Click({ & $presetHandler 'Standard' }.GetNewClosure())
    $c.BtnPresetResponsive.Add_Click({ & $presetHandler 'Responsive' }.GetNewClosure())
    $c.BtnPresetAggressive.Add_Click({ & $presetHandler 'Aggressive' }.GetNewClosure())
    $c.BtnPresetMaxPerf.Add_Click({ & $presetHandler 'MaxPerformance' }.GetNewClosure())
    $c.BtnPresetGamer.Add_Click({ Start-LtGamerMode })
    Initialize-LtGamingViews
    Initialize-LtKitView
    $c.BtnPresetClear.Add_Click({ foreach ($t in $script:Ui.Tweaks.Values) { $t.Selected = $false }; $script:Ui.C.TxtPresetInfo.Text = 'Seçimler kaldırıldı.' })

    # --- kurtarma ---
    $recovery = {
        param([string]$Mode)
        $op = $script:Ui.RecoveryOp
        if (-not $op) { return }
        $body = { param($a, $p, $c) @{ Results = @(Invoke-LtRecovery -OperationId $a.Op -Mode $a.Mode); Mode = $a.Mode } }
        [void](Start-LtJob -Title 'Yarım işlem kurtarılıyor' -Body $body -JobArgs @{ Op = $op; Mode = $Mode } -OnDone {
            param($r, $e)
            Update-LtRecoveryBanner
            if ($r -and $r.Mode -eq 'Revert') {
                [void](Show-LtReportDialog -Owner $script:Ui.Window -Title 'Kurtarma' -Head 'Yarım işlem öncesi değerlere döndürüldü' -Intro 'Her değer geri yüklendikten sonra yeniden okunarak doğrulandı.' -Rows @(ConvertTo-LtResultRows $r.Results) -Mode Info)
            }
            foreach ($pg in $script:LtOptPages) { $script:Ui.StateLoaded[$pg] = $false }
            if ($script:LtOptPages -contains $script:Ui.CurrentPage) { Update-LtPageState -Page $script:Ui.CurrentPage }
        })
    }
    $c.BtnRecoveryRevert.Add_Click({ & $recovery 'Revert' }.GetNewClosure())
    $c.BtnRecoveryKeep.Add_Click({ & $recovery 'Keep' }.GetNewClosure())

    # --- gecmis ---
    $c.BtnHistoryRevert.Add_Click({
        $ids = @($script:Ui.C.LedgerList.SelectedItems | ForEach-Object { $_.TweakIds } | Where-Object { $_ } | Select-Object -Unique)
        if ($ids.Count -eq 0) { Set-LtStatus 'Listeden en az bir satır seçin.'; return }
        Invoke-LtTweakFlow -Ids $ids -Mode RevertPrevious
    })
    $c.BtnHistoryOpenData.Add_Click({ Open-LtFolder -Path (Get-LtDataRoot) })
    $c.BtnHistoryRestoreFile.Add_Click({
        $dlg = New-Object Microsoft.Win32.OpenFileDialog
        $dlg.Filter = 'Livn Tools durum yedeği (*.json)|*.json'
        $dlg.InitialDirectory = Join-Path (Get-LtDataRoot) 'backups'
        if ($dlg.ShowDialog($script:Ui.Window) -ne $true) { return }
        if ((Show-LtMessage -Owner $script:Ui.Window -Buttons YesNo -Icon Warning -Text "Yedekteki değerler geri yüklenecek:`n$($dlg.FileName)`n`nHer değer yazıldıktan sonra doğrulanır ve yapılan değişiklikler de günlüğe kaydedilir. Devam edilsin mi?") -ne 'Yes') { return }
        $body = { param($a, $p, $c) @{ Run = (Restore-LtStateBackup -Path $a.Path -Progress $p -Cancel $c); RestorePoint = $null } }
        [void](Start-LtJob -Title 'Durum yedeğinden geri yükleniyor' -Body $body -JobArgs @{ Path = $dlg.FileName } -OnDone { param($r, $e) Show-LtRunResult $r; Update-LtHistory })
    })
    $c.BtnHistoryLegacyReg.Add_Click({
        $dlg = New-Object Microsoft.Win32.OpenFileDialog
        $dlg.Filter = 'Registry yedeği (*.reg)|*.reg'
        foreach ($legacy in @((Join-Path (Get-LtDataRoot) 'legacy-v3.5\Backups'), (Join-Path $script:Ui.AppRoot '_Files\Backups'))) {
            if (Test-Path -LiteralPath $legacy) { $dlg.InitialDirectory = $legacy; break }
        }
        if ($dlg.ShowDialog($script:Ui.Window) -ne $true) { return }
        if ((Show-LtMessage -Owner $script:Ui.Window -Buttons YesNo -Icon Warning -Text "v3.5 .reg yedeği içe aktarılacak:`n$($dlg.FileName)`n`nUYARI: .reg dosyaları yalnızca içlerindeki değerleri yazar; o sırada OLMAYAN değerleri silmez ve Livn Tools günlüğüne kaydedilmez. Devam edilsin mi?") -ne 'Yes') { return }
        if (-not (Test-LtLiveSystem)) { Set-LtStatus 'Kuru çalışmada .reg içe aktarılmaz.'; return }
        $body = { param($a, $p, $c) Import-LtRegFile -Path $a.Path }
        [void](Start-LtJob -Title '.reg içe aktarılıyor' -Body $body -JobArgs @{ Path = $dlg.FileName } -OnDone { param($r, $e) Set-LtStatus $(if ($r -eq 0) { '.reg yedeği içe aktarıldı (reg.exe çıkış kodu 0).' } else { ".reg içe aktarılamadı (çıkış kodu $r)." }) })
    })

    # --- betik ---
    $c.ScriptEditor.Text = "# Buraya kod yapıştırın veya bir dosya içe aktarın.`r`n"
    $c.BtnScriptClear.Add_Click({ $script:Ui.C.ScriptEditor.Text = '' })
    $c.BtnScriptImport.Add_Click({
        $dlg = New-Object Microsoft.Win32.OpenFileDialog
        $dlg.Filter = 'Betikler (*.ps1;*.bat;*.cmd;*.txt)|*.ps1;*.bat;*.cmd;*.txt|Tüm dosyalar|*.*'
        if ($dlg.ShowDialog($script:Ui.Window) -ne $true) { return }
        $read = Read-LtTextFileAuto -Path $dlg.FileName
        $script:Ui.C.ScriptEditor.Text = $read.Text
        $script:Ui.C.CmbScriptKind.SelectedIndex = if ($dlg.FileName -match '\.(bat|cmd)$') { 1 } else { 0 }
        Set-LtStatus "İçe aktarıldı ($($read.Encoding)): $($dlg.FileName)"
    })
    $c.BtnScriptRun.Add_Click({ Invoke-LtScriptFlow })

    # --- ilerleme / iptal ---
    $c.BtnCancel.Add_Click({
        $job = $script:Ui.Job
        if ($job) {
            $job.Cancel.Requested = $true
            # Kullanici betikleri geri alma sistemine dahil degildir; boru hatti durdurulabilir.
            if ($job.Title -eq 'Betik çalışıyor') { try { [void]$job.PS.BeginStop($null, $null) } catch { $null = $_ } }
            $script:Ui.C.BtnCancel.IsEnabled = $false
            $script:Ui.C.BtnCancel.Content = 'İptal istendi…'
            Set-LtStatus 'İptal istendi: mevcut adım tamamlanınca durulacak.'
        }
    })

    # --- gunluk ---
    $c.BtnLogClear.Add_Click({ $script:Ui.C.LogBox.Clear() })
    $c.BtnLogToggle.Add_Click({
        $b = $script:Ui.C.LogBox
        if ($b.Visibility -eq 'Visible') { $b.Visibility = 'Collapsed'; $script:Ui.C.BtnLogToggle.Content = 'Göster' } else { $b.Visibility = 'Visible'; $script:Ui.C.BtnLogToggle.Content = 'Gizle' }
    })
    $c.BtnLogSave.Add_Click({
        $dlg = New-Object Microsoft.Win32.SaveFileDialog
        $dlg.Filter = 'Metin (*.txt)|*.txt'
        $dlg.FileName = "LivnTools_Gunluk_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
        if ($dlg.ShowDialog($script:Ui.Window) -eq $true) {
            [IO.File]::WriteAllText($dlg.FileName, $script:Ui.C.LogBox.Text, (New-Object System.Text.UTF8Encoding($true)))
            Set-LtStatus "Günlük kaydedildi: $($dlg.FileName)"
        }
    })

    # --- klavye ---
    $window.Add_PreviewKeyDown({
        param($s, $e)
        $ctrl = ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control) -ne 0
        if ($e.Key -eq 'F5' -and $script:LtOptPages -contains $script:Ui.CurrentPage) { $script:Ui.StateLoaded[$script:Ui.CurrentPage] = $false; Update-LtPageState -Page $script:Ui.CurrentPage; $e.Handled = $true }
        elseif ($e.Key -eq 'Escape' -and $script:Ui.Job) { $script:Ui.C.BtnCancel.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))); $e.Handled = $true }
        elseif ($ctrl -and $e.Key -eq 'Return' -and $script:LtOptPages -contains $script:Ui.CurrentPage) { Invoke-LtTweakFlow -Ids (Get-LtSelectedTweakIds @($script:Ui.CurrentPage)) -Mode Apply; $e.Handled = $true }
    })

    # --- beklenmeyen hata agi: olay isleyicisindeki hata pencereyi kapatmasin ---
    $window.Dispatcher.Add_UnhandledException({
        param($s, $e)
        try { Add-LtLogLine ("{0}  [ERROR]  Beklenmeyen arayüz hatası: {1}" -f (Get-Date -Format 'HH:mm:ss'), $e.Exception.Message) } catch { $null = $_ }
        try { Write-LtLog "Beklenmeyen arayüz hatası: $($e.Exception)" 'ERROR' } catch { $null = $_ }
        $e.Handled = $true
    })

    # --- kapanis ---
    $window.Add_Closing({
        param($s, $e)
        if ($script:Ui.Job -and -not $script:Ui.Job.Quiet) {
            $a = Show-LtMessage -Owner $script:Ui.Window -Buttons YesNo -Icon Warning -Text "Bir işlem sürüyor. Şimdi kapatırsanız işlem yarım kalabilir.`n`nYapılan değişiklikler günlüğe kaydedildiği için bir sonraki açılışta geri alma önerilir.`n`nYine de kapatılsın mı?"
            if ($a -ne 'Yes') { $e.Cancel = $true; return }
            $script:Ui.Job.Cancel.Requested = $true
        }
        foreach ($t in @($script:Ui.UiTimer, $script:Ui.HwTimer)) { if ($t) { $t.Stop() } }
        # Salt okunur ikincil is: beklemeden durdurma istenir (sistem degisikligi yapmaz)
        if ($script:Ui.SideJob) { try { [void]$script:Ui.SideJob.PS.BeginStop($null, $null) } catch { $null = $_ } }
    })

    # --- zamanlayicilar ---
    $uiTimer = New-Object System.Windows.Threading.DispatcherTimer
    $uiTimer.Interval = [TimeSpan]::FromMilliseconds(150)
    $uiTimer.Add_Tick({
        $item = $null; $n = 0
        while ($n -lt 200 -and $script:Ui.LogQueue.TryDequeue([ref]$item)) { Add-LtLogLine $item.Line; $n++ }
        # Sonuc isleme modal pencere acar; o sirada gelen tick'ler yeniden girmez
        # (aksi halde kuyruktaki is, kullanicinin onayladigi isin onune gecebilirdi).
        if (-not $script:Ui.InTick) {
            $script:Ui.InTick = $true
            try { Complete-LtJobIfDone; Complete-LtSideJobIfDone } finally { $script:Ui.InTick = $false }
        }
    })
    $script:Ui.UiTimer = $uiTimer
    $hwTimer = New-Object System.Windows.Threading.DispatcherTimer
    $hwTimer.Interval = [TimeSpan]::FromSeconds(2)
    $hwTimer.Add_Tick({ Update-LtHardwareBar })
    $script:Ui.HwTimer = $hwTimer

    # --- ilk yukleme: sistem baglami arka planda ---
    $window.Add_ContentRendered({
        $script:Ui.UiTimer.Start(); $script:Ui.HwTimer.Start()
        Update-LtHardwareBar
        Write-LtLog "Livn Tools v$(Get-LtVersion) başlatıldı. Arka uç: $(Get-LtBackend). Veri klasörü: $(Get-LtDataRoot)" 'OK'
        Update-LtRecoveryBanner
        $body = {
            param($a, $p, $c)
            $ctx = Get-LtSystemContext -AppRoot $a.AppRoot
            $ctx.PowerPlanChoices = @(); $ctx.PowerPlanReadError = ''
            try { $ctx.PowerPlanChoices = @(Get-LtPowerPlanChoices) }
            catch { $ctx.PowerPlanReadError = $_.Exception.Message }
            $ctx
        }
        [void](Start-LtJob -Title 'Sistem bilgisi okunuyor' -Body $body -JobArgs @{ AppRoot = $script:Ui.AppRoot } -Quiet -OnDone {
            param($ctx, $e)
            if (-not $ctx) { Set-LtStatus 'Sistem bilgisi okunamadı; ayarlar devre dışı.'; return }
            $prevNic = [string](Get-LtProp $script:Ui.Ctx 'SelectedNicGuid' '')
            $prevMsi = [string](Get-LtProp $script:Ui.Ctx 'SelectedMsiInstanceId' '')
            $script:Ui.Ctx = $ctx
            $cc = $script:Ui.C
            Set-LtPowerPlanChoicesView -Plans @($ctx.PowerPlanChoices) -ErrorText ([string]$ctx.PowerPlanReadError)
            Set-LtDeviceChoicesView -Ctx $ctx -PreviousNic $prevNic -PreviousMsi $prevMsi
            $demoPrefix = if ((Get-LtBackend) -eq 'Memory') { 'Deneme sistemi: ' } else { '' }
            $cc.TxtOs.Text = $demoPrefix + (Get-LtOsLabel $ctx) + $(if ($ctx.EditionId) { " · $($ctx.EditionId)" } else { '' })
            $gpu = (@($ctx.Gpus | ForEach-Object { $_.Name }) -join ', ')
            $cc.TxtHw.Text = "$($ctx.Cpu.Name) · $($ctx.RamGB) GB RAM$(if ($gpu) { " · $gpu" })"
            foreach ($er in @($ctx.Errors)) { Write-LtLog "Sistem bilgisi eksik: $er" 'WARN' }
            if ((Get-LtBackend) -eq 'Windows' -and -not $ctx.IsAdmin) { Write-LtLog 'Yönetici yetkisi yok: sistem ayarları değiştirilemez.' 'ERROR' }
            Update-LtCleanupAvailability
            if ($script:LtOptPages -contains $script:Ui.CurrentPage) { Update-LtPageState -Page $script:Ui.CurrentPage }
            Update-LtPageInfo $script:Ui.CurrentPage
            Set-LtStatus 'Hazır.'
            if ($script:Ui.CurrentPage -eq 'Health' -and -not $script:Ui.HealthChecks) { [void](Start-LtHealthCheck) }
            # Livn bir kurtarma kitinin icinden calisiyorsa kiti yukle ve Kurtarma Kiti sayfasini ac
            try {
                $parent = Split-Path -Parent ([string]$script:Ui.AppRoot)
                if ($parent -and [IO.File]::Exists((Join-Path $parent 'kit.json'))) {
                    [void](Set-LtLoadedKit -Path $parent)
                    Select-LtNavPage 'Kit'
                    Set-LtStatus 'Livn bir kurtarma kitinden açıldı. Önce "① Sürücüleri kur (ağ önce)" adımını uygulayın.'
                }
            } catch { Write-LtLog "Kurtarma kiti okunamadı: $($_.Exception.Message)" 'WARN' }
        })
    })

    $c.NavList.SelectedIndex = 1
    [void]$window.ShowDialog()
    if ($script:Ui.Job) {
        # Kapaniyor: arka plan isinin guvenli noktada (ayarlar arasinda) durmasini kisa sure bekle
        $deadline = (Get-Date).AddSeconds(15)
        while (-not $script:Ui.Job.Handle.IsCompleted -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 200 }
        try { $script:Ui.Job.PS.Dispose() } catch { $null = $_ }
    }
    if ($script:Ui.WorkerRS) { try { $script:Ui.WorkerRS.Close(); $script:Ui.WorkerRS.Dispose() } catch { $null = $_ } }
}
