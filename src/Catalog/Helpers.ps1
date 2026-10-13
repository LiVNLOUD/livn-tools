# Livn Tools - Catalog/Helpers.ps1
# Katalog tanimlarini kisa ve okunur tutmak icin eylem kuruculari.

Set-StrictMode -Version 2.0

function New-LtRegAction {
    <#
      -Default 'Absent'            : Windows varsayilaninda deger yok
      -Default @('DWord', 2)       : Windows varsayilani bu deger
      -Default $null (belirtilmez) : varsayilan bilinmiyor -> yalnizca "onceki ayar" geri alinabilir
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [AllowEmptyString()][string]$Name = '',
        [ValidateSet('DWord','QWord','String','ExpandString','MultiString','Binary')][string]$Kind = 'DWord',
        $Value = $null,
        $Default = $null,
        [switch]$Absent
    )
    $d = $null
    if ($Default -is [string] -and $Default -eq 'Absent') { $d = 'Absent' }
    elseif ($null -ne $Default) {
        $arr = @($Default)
        if ($arr.Count -eq 2 -and $arr[0] -is [string] -and @('DWord','QWord','String','ExpandString','MultiString','Binary') -contains $arr[0]) {
            $d = @{ Kind = $arr[0]; Value = $arr[1] }
        } else {
            $d = @{ Kind = $Kind; Value = $Default }
        }
    }
    $a = @{ Type = 'Registry'; Path = $Path; Name = $Name; Kind = $Kind; Value = $Value; Default = $d }
    if ($Absent) { $a.Absent = $true }
    return $a
}

function New-LtServiceAction {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$StartType, [string]$Default = $null, [switch]$Stop)
    $a = @{ Type = 'Service'; Name = $Name; StartType = $StartType; Stop = [bool]$Stop; Default = $null }
    if ($Default) { $a.Default = $Default }
    return $a
}

function New-LtBcdAction {
    param([Parameter(Mandatory)][string]$Element, [Parameter(Mandatory)][ValidateSet('Absent','Yes','No')][string]$Value, [string]$Default = 'Absent')
    @{ Type = 'Bcd'; Element = $Element; Value = $Value; Default = $Default }
}

function New-LtTcpAction {
    param([Parameter(Mandatory)][string]$Setting, [Parameter(Mandatory)][string]$Value, [string]$Default = $null)
    $a = @{ Type = 'TcpGlobal'; Setting = $Setting; Value = $Value; Default = $null }
    if ($Default) { $a.Default = $Default }
    return $a
}

function Get-LtSelectedNic {
    param([Parameter(Mandatory)]$Ctx)
    $selected = [string](Get-LtProp $Ctx 'SelectedNicGuid' '')
    if (-not $selected) { throw 'Hedef adaptör seçilmedi: Ağ sayfasının üstündeki "Hedef adaptör" listesinden bir adaptör seçin.' }
    $guid = ([guid]$selected).ToString('D')
    $devices = @($Ctx.Nics | Where-Object { ([string]$_.InterfaceGuid).Trim('{}') -ieq $guid })
    if ($devices.Count -ne 1) { throw 'Seçilen adaptör artık mevcut değil veya kimliği belirsiz.' }
    return $devices[0]
}

function New-LtGpuPreferenceActions {
    <# Uygulama basina GPU tercihi (Ayarlar > Grafik ile ayni kayit). Yalniz yerel surucudeki .exe yollari. #>
    param([Parameter(Mandatory)]$Ctx)
    $apps = @(Get-LtProp $Ctx 'GpuPreferenceApps' @() | Where-Object { $_ })
    if ($apps.Count -eq 0) { throw 'Önce oyunun .exe dosyasını seçin.' }
    foreach ($p in $apps) {
        if ([string]$p -notmatch '^[A-Za-z]:\\[^"<>|*?]+\.exe$') { throw "Geçersiz uygulama yolu: $p" }
        New-LtRegAction -Path 'HKCU\Software\Microsoft\DirectX\UserGpuPreferences' -Name ([string]$p) -Kind String -Value 'GpuPreference=2;' -Default 'Absent'
    }
}

function Get-LtSelectedMsiDevice {
    <# GPU ve MSI sayfasinda secilen tek PCI aygiti; sinif eslesmezse veya aygit kaybolduysa hata. #>
    param([Parameter(Mandatory)]$Ctx, [Parameter(Mandatory)][ValidateSet('GPU','NIC')][string]$Class)
    $label = if ($Class -eq 'GPU') { 'ekran kartı' } else { 'ağ kartı' }
    $selected = [string](Get-LtProp $Ctx 'SelectedMsiInstanceId' '')
    if (-not $selected) { throw "Önce GPU ve MSI sayfasındaki aygıt listesinden bir $label seçin." }
    $devices = @($Ctx.MsiDevices | Where-Object { [string]$_.InstanceId -ieq $selected })
    if ($devices.Count -ne 1 -or $selected -notmatch '^PCI\\[^\\]+\\[^\\]+$') { throw 'Seçilen aygıt artık mevcut değil veya kimliği belirsiz. Listeden yeniden seçin.' }
    if ($devices[0].Class -ne $Class) { throw "Seçili aygıt bir $label değil; bu ayar yalnız seçili $label için uygulanır." }
    return $devices[0]
}

function Get-LtMsiSupportIssue {
    <# $null = secili aygit donanim olarak MSI/MSI-X bildiriyor; aksi halde neden metni #>
    param([Parameter(Mandatory)]$Ctx, [Parameter(Mandatory)][ValidateSet('GPU','NIC')][string]$Class)
    try { $device = Get-LtSelectedMsiDevice -Ctx $Ctx -Class $Class } catch { return $_.Exception.Message }
    $bits = Get-LtProp $device 'InterruptSupport' $null
    if ($null -eq $bits) { return 'Aygıtın MSI donanım desteği okunamadı. Desteği bilinmeyen aygıta MSI tercihi yazılmaz.' }
    if (([int]$bits -band 6) -eq 0) { return 'Aygıt yalnız hat tabanlı kesme bildiriyor; MSI desteklemiyor.' }
    return $null
}

function New-LtMsiAction {
    param([Parameter(Mandatory)]$Ctx, [Parameter(Mandatory)][ValidateSet('GPU','NIC')][string]$Class)
    $device = Get-LtSelectedMsiDevice -Ctx $Ctx -Class $Class
    New-LtRegAction -Path "HKLM\SYSTEM\CurrentControlSet\Enum\$($device.InstanceId)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties" -Name 'MSISupported' -Value 1
}

function Get-LtNicSelectionIssue {
    <# $null = secili adaptor gecerli; aksi halde kullaniciya gosterilecek neden (istisna degil). #>
    param([Parameter(Mandatory)]$Ctx)
    try { [void](Get-LtSelectedNic $Ctx); return $null } catch { return $_.Exception.Message }
}

function New-LtNicActions {
    <#
      Etkin fiziksel adaptorlerden, verilen anahtar kelimelerden birini destekleyen
      ve istenen degeri gecerli kabul edenler icin eylem uretir. Yerellestirilmis
      DisplayName kullanilmaz; RegistryKeyword/RegistryValue kullanilir.
    #>
    param($Ctx, [string[]]$Keywords, [string]$Value)
    $actions = New-Object System.Collections.ArrayList
    foreach ($nic in @((Get-LtSelectedNic $Ctx))) {
        foreach ($kw in $Keywords) {
            try { $p = Get-LtNicProperty -Adapter $nic.Name -Keyword $kw -InterfaceGuid $nic.InterfaceGuid } catch { continue }
            if (-not $p.Exists) { continue }
            if (@($p.Valid).Count -gt 0 -and @($p.Valid) -notcontains $Value) { continue }
            [void]$actions.Add(@{ Type = 'NicProperty'; Adapter = $nic.Name; InterfaceGuid = $nic.InterfaceGuid; Keyword = $kw; Value = $Value; Default = 'DriverDefault' })
        }
    }
    return @($actions)
}

function Test-LtEditionIn {
    param($Ctx, [string[]]$Patterns)
    foreach ($p in $Patterns) { if ([string]$Ctx.EditionId -like $p) { return $true } }
    return $false
}

function Get-LtUserParameterSupport {
    param([string]$TweakId)
    $legacy = @(Get-LtLedgerEntries | Where-Object { @($_.tweakIds) -contains $TweakId -and $_.action.Type -eq 'Registry' })
    if ($legacy.Count -gt 0) { return 'Eski registry işlem kaydı var. Önce Değişiklik Geçmişi üzerinden önceki ayara dönün; ardından API yöntemiyle uygulayın.' }
    try { [void](Get-LtInteractiveUserSid) } catch { return $_.Exception.Message }
    return $null
}
function Get-LtMenuDelayChoice {
    param($Context)
    $value = Get-LtProp $Context 'MenuDelayMs'
    if ($null -eq $value -or @('0','100','200','400','800') -notcontains [string]$value) { throw 'Menü gecikmesini 0, 100, 200, 400 veya 800 ms olarak seçin.' }
    return [int]$value
}


function Get-LtIslcProfile {
    <# Conservative starting heuristic, NOT a benchmark-derived optimum.
       RAM is relevant to the thresholds; CPU/GPU model is not a CLI parameter. #>
    param($Context)
    $mb = [double](Get-LtProp $Context 'RamMB')
    if ($mb -le 0) { $mb = [double](Get-LtProp $Context 'RamGB') * 1024 }
    if ([double]::IsNaN($mb) -or [double]::IsInfinity($mb) -or $mb -lt 2048) {
        throw 'ISLC profili için en az 2 GB RAM bilgisi okunabilmeli; tahmini donanım kullanılmaz.'
    }
    $free = [int][math]::Max(512, [math]::Min(4096, [math]::Floor($mb * 0.10)))
    return [pscustomobject]@{
        RamMB = [long][math]::Floor($mb); FreeMemoryMB = $free; ListSizeMB = 1024; PollingMs = 1000
        Arguments = "-minimized -polling 1000 -listsize 1024 -freememory $free"
        Note = 'Başlangıç profili: RAM %10 (512–4096 MB sınırı), liste 1024 MB, tarama 1000 ms. En iyi ayar iddiası değildir. ISLC mevcut timer ayarlarını korur; otomatik başlatmadan önce kendi arayüzünde kontrol edin.'
    }
}

function Get-LtIslcFile {
    param($Context)
    $path = [string](Get-LtProp $Context 'IslcPath')
    if (-not $path) {
        $task = Get-LtScheduledTaskInfo -TaskPath '\LivnTools\' -TaskName 'ISLC'
        if ($task.Exists) { $path = [string]$task.Execute }
    }
    if (-not $path) { $path = Get-LtPowerPlanFile $Context 'Intelligent standby list cleaner ISLC.exe' }
    if (-not $path -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw 'ISLC bulunamadı. Resmî siteden indirip kalıcı bir klasöre çıkartın ve ISLC dosyasını seçin.'
    }
    $file = Get-Item -LiteralPath $path -ErrorAction Stop
    if ($file.Name -ne 'Intelligent standby list cleaner ISLC.exe') { throw 'ISLC paketindeki asıl uygulamayı seçin; indirme/kurulum EXE dosyasını seçmeyin.' }
    $v = $file.VersionInfo
    $version = New-Object version($v.FileMajorPart, $v.FileMinorPart, $v.FileBuildPart, $v.FilePrivatePart)
    if ($version -lt [version]'1.0.3.7' -or $version -gt [version]'1.0.4.8') {
        throw "ISLC $version için bu entegrasyonun sürüm aralığı henüz güncellenmedi (1.0.3.7–1.0.4.8)."
    }
    return [pscustomobject]@{ Path = $file.FullName; Version = $version.ToString(); LatestKnown = '1.0.4.8'; IsOlder = ($version -lt [version]'1.0.4.8') }
}

function Get-LtSelectedPowerPlan {
    param($Context)
    $id = [string](Get-LtProp $Context 'SelectedPowerPlanGuid')
    $guid = [guid]::Empty
    if (-not [guid]::TryParse($id, [ref]$guid)) { throw 'Etkinleştirilecek kurulu güç planını listeden seçin.' }
    $id = $guid.ToString()
    if (@(Get-LtPowerSchemes) -notcontains $id) { throw 'Seçili güç planı artık sistemde bulunmuyor. Plan listesini yenileyin.' }
    return $id
}
