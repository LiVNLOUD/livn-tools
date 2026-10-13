# Livn Tools - Core/Providers.ps1
# Eylem saglayicilari. Her eylem turu icin ayni sozlesme:
#   Key      : kalici kimlik (ledger/journal anahtari)
#   Capture  : mevcut durumu JSON'a yazilabilir bir hashtable olarak okur
#   IsDesired: yakalanan durum hedefle ayni mi?
#   Apply    : hedefi uygular (hata -> istisna)
#   Restore  : yakalanan duruma birebir geri doner
#   Default  : Windows varsayilanina doner ($action.Default tanimli degilse istisna)
#   Format   : durum/hedefi insan okunur metne cevirir
# Eylemler duz hashtable'dir; ornek:
#   @{ Type='Registry'; Path='HKCU\Software\X'; Name='Y'; Kind='DWord'; Value=1; Default='Absent' }

Set-StrictMode -Version 2.0

function Get-LtProp {
    <# Hashtable/PSCustomObject'ten guvenli okuma (StrictMode uyumlu). #>
    param($Object, [string]$Name, $DefaultValue = $null)
    if ($null -eq $Object) { return $DefaultValue }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $DefaultValue
    }
    $p = $Object.PSObject.Properties[$Name]
    if ($p) { return $p.Value }
    return $DefaultValue
}

function Format-LtRegState {
    param($Snap)
    if (-not (Get-LtProp $Snap 'Exists' $false)) { return 'yok' }
    $kind = Get-LtProp $Snap 'Kind'
    $data = Get-LtProp $Snap 'Data'
    switch ($kind) {
        'DWord'       { return ('{0} (0x{1:X}) [DWORD]' -f $data, [long]$data) }
        'MultiString' { return ((@($data) -join ' | ') + ' [MULTI_SZ]') }
        'Binary'      { $b = [Convert]::FromBase64String([string]$data); $hex = ($b | Select-Object -First 16 | ForEach-Object { $_.ToString('X2') }) -join ' '; if ($b.Length -gt 16) { $hex += ' …' }; return "$hex [BINARY]" }
        default       { return "'$data' [$kind]" }
    }
}

# ---------------------------------------------------------------------------
# REGISTRY
# ---------------------------------------------------------------------------
function Get-LtMissingKeyChain {
    <# Yolun var olmayan bolumlerini (ustten alta) dondurur. #>
    param([string]$Path)
    $rp = ConvertTo-LtRegPath $Path
    $segments = @($rp.Sub.Split('\') | Where-Object { $_ -ne '' })
    $missing = New-Object System.Collections.ArrayList
    $cur = $rp.Hive
    foreach ($s in $segments) {
        $cur = "$cur\$s"
        if ($missing.Count -gt 0 -or -not (Test-LtRegKey $cur)) { [void]$missing.Add($cur) }
    }
    return @($missing)
}

function Get-LtRegistryOwnerSid {
    param($Action)
    if ((ConvertTo-LtRegPath $Action.Path).Hive -eq 'HKCU') { return (Get-LtInteractiveUserSid) }
    return ''
}
function Assert-LtRegistrySnapshotOwner {
    param($Action, $Snapshot)
    $sid = Get-LtRegistryOwnerSid $Action
    if ($sid -and (Get-LtProp $Snapshot 'UserSid' '') -ne $sid) {
        throw 'Kullanıcı yedeğinin sahibi farklı veya eski kayıtta belirsiz; kayıt korundu, geri yükleme reddedildi.'
    }
}

$script:LtProviders = @{}

$script:LtProviders['Registry'] = @{
    Key = { param($a) 'Registry|{0}|{1}' -f (ConvertTo-LtRegPath $a.Path).Full, (Get-LtProp $a 'Name' '') }
    Capture = {
        param($a)
        $name = [string](Get-LtProp $a 'Name' '')
        $sid = Get-LtRegistryOwnerSid $a
        $v = Get-LtRegValue -Path $a.Path -Name $name
        @{ UserSid = $sid; KeyExists = $v.KeyExists; Exists = $v.Exists; Kind = $v.Kind; Data = $v.Data; MissingKeys = @(Get-LtMissingKeyChain $a.Path) }
    }
    IsDesired = {
        param($a, $s)
        if (Get-LtProp $a 'Absent' $false) { return (-not $s.Exists) }
        if (-not $s.Exists) { return $false }
        if ($s.Kind -ne $a.Kind) { return $false }
        $desired = ConvertTo-LtRegData -Value (ConvertFrom-LtRegData -Data $a.Value -Kind $a.Kind) -Kind $a.Kind
        return (Test-LtRegDataEqual $s.Data $desired $a.Kind)
    }
    Apply = {
        param($a)
        $name = [string](Get-LtProp $a 'Name' '')
        if (Get-LtProp $a 'Absent' $false) { Remove-LtRegValue -Path $a.Path -Name $name; return }
        [void](Set-LtRegValue -Path $a.Path -Name $name -Kind $a.Kind -Data $a.Value)
    }
    Restore = {
        param($a, $s)
        Assert-LtRegistrySnapshotOwner $a $s
        $name = [string](Get-LtProp $a 'Name' '')
        if ($s.Exists) {
            [void](Set-LtRegValue -Path $a.Path -Name $name -Kind $s.Kind -Data $s.Data)
            return
        }
        Remove-LtRegValue -Path $a.Path -Name $name
        # Bu islem sirasinda olusturulmus anahtarlari (bos kaldiysa) alttan uste sil
        $chain = @(Get-LtProp $s 'MissingKeys' @())
        for ($i = $chain.Count - 1; $i -ge 0; $i--) {
            if (-not (Remove-LtRegKeyIfEmpty $chain[$i])) { break }
        }
    }
    Default = {
        param($a)
        $d = Get-LtProp $a 'Default'
        $name = [string](Get-LtProp $a 'Name' '')
        if ($d -eq 'Absent') { Remove-LtRegValue -Path $a.Path -Name $name; return }
        [void](Set-LtRegValue -Path $a.Path -Name $name -Kind $d.Kind -Data $d.Value)
    }
    DefaultSnapshot = {
        param($a)
        $d = Get-LtProp $a 'Default'
        if ($d -eq 'Absent') { return @{ UserSid = (Get-LtRegistryOwnerSid $a); Exists = $false } }
        return @{ UserSid = (Get-LtRegistryOwnerSid $a); Exists = $true; Kind = $d.Kind; Data = (ConvertTo-LtRegData -Value (ConvertFrom-LtRegData -Data $d.Value -Kind $d.Kind) -Kind $d.Kind) }
    }
    FormatState   = { param($a, $s) Format-LtRegState $s }
    FormatDesired = {
        param($a)
        if (Get-LtProp $a 'Absent' $false) { return 'yok (değer silinir)' }
        Format-LtRegState @{ Exists = $true; Kind = $a.Kind; Data = (ConvertTo-LtRegData -Value (ConvertFrom-LtRegData -Data $a.Value -Kind $a.Kind) -Kind $a.Kind) }
    }
    Target = { param($a) '{0}\{1}' -f (ConvertTo-LtRegPath $a.Path).Full, $(if ((Get-LtProp $a 'Name' '') -eq '') { '(Varsayılan)' } else { $a.Name }) }
}

# ---------------------------------------------------------------------------
# SERVIS
# ---------------------------------------------------------------------------
$script:LtProviders['Service'] = @{
    Key = { param($a) "Service|$($a.Name)" }
    Capture = {
        param($a)
        $i = Get-LtServiceInfo -Name $a.Name
        @{ Exists = $i.Exists; StartType = $i.StartType; Status = $i.Status }
    }
    IsDesired = {
        param($a, $s)
        $mustStop = (Get-LtProp $a 'Stop' $false) -and $a.StartType -eq 'Disabled'
        return ($s.Exists -and $s.StartType -eq $a.StartType -and (-not $mustStop -or $s.Status -eq 'Stopped'))
    }
    Apply = {
        param($a)
        Set-LtServiceStartType -Name $a.Name -StartType $a.StartType
        if ((Get-LtProp $a 'Stop' $false) -and $a.StartType -eq 'Disabled') {
            Stop-LtServiceSafe -Name $a.Name
        }
    }
    Restore = {
        param($a, $s)
        if (-not $s.Exists) { return }
        Set-LtServiceStartType -Name $a.Name -StartType $s.StartType
        if ($s.Status -eq 'Running' -and $s.StartType -ne 'Disabled') {
            Start-LtServiceSafe -Name $a.Name
        } elseif ($s.Status -eq 'Stopped') {
            Stop-LtServiceSafe -Name $a.Name
        }
    }
    Default = {
        param($a)
        $d = Get-LtProp $a 'Default'
        Set-LtServiceStartType -Name $a.Name -StartType $d
    }
    DefaultSnapshot = { param($a) @{ Exists = $true; StartType = (Get-LtProp $a 'Default'); Status = 'Unknown' } }
    FormatState   = { param($a, $s) if ($s.Exists) { "Başlangıç: $($s.StartType), Durum: $($s.Status)" } else { 'servis yok' } }
    FormatDesired = { param($a) "Başlangıç: $($a.StartType)" }
    Target = { param($a) "Servis: $($a.Name)" }
}

# ---------------------------------------------------------------------------
# BCD
# ---------------------------------------------------------------------------
$script:LtProviders['Bcd'] = @{
    Key = { param($a) "Bcd|{current}|$($a.Element)" }
    Capture = { param($a) @{ Value = (Get-LtBcdElement -Element $a.Element) } }
    IsDesired = { param($a, $s) ($s.Value -eq $a.Value) }
    Apply = { param($a) Set-LtBcdElement -Element $a.Element -Value $a.Value }
    Restore = { param($a, $s) Set-LtBcdElement -Element $a.Element -Value $s.Value }
    Default = { param($a) Set-LtBcdElement -Element $a.Element -Value (Get-LtProp $a 'Default') }
    DefaultSnapshot = { param($a) @{ Value = (Get-LtProp $a 'Default') } }
    FormatState   = { param($a, $s) @{ Absent = 'tanımsız (Windows varsayılanı)'; Yes = 'yes'; No = 'no' }[$s.Value] }
    FormatDesired = { param($a) @{ Absent = 'tanımsız (silinir)'; Yes = 'yes'; No = 'no' }[$a.Value] }
    Target = { param($a) "BCD {current} $($a.Element)" }
}

# ---------------------------------------------------------------------------
# GUC PLANI (etkin plan). Sabit hedef GUID'i sayesinde tekrar uygulama
# yinelenen plan OLUSTURMAZ: plan varsa yalnizca etkinlestirilir.
# ---------------------------------------------------------------------------
function Initialize-LtPowerScheme {
    param($a)
    $guid = $a.Guid.ToLowerInvariant()
    if ((Get-LtPowerSchemes) -contains $guid) { return $false }
    switch ($a.Source) {
        'Import'    {
            # Ice aktarma aninda icerik yeniden dogrulanir (destek kontrolunden sonra degismis olabilir)
            $expected = [string](Get-LtProp $a 'Sha256' '')
            if ($expected -and (Get-FileHash -LiteralPath $a.File -Algorithm SHA256).Hash -ne $expected) { throw "Plan dosyası beklenen içerikle eşleşmiyor: $($a.File)" }
            Import-LtPowerScheme -File $a.File -Guid $guid
        }
        'Duplicate' { Copy-LtPowerScheme -SourceGuid $a.BaseGuid -Guid $guid }
        default     { throw "Güç planı bu sistemde yok: $guid" }
    }
    if ((Get-LtPowerSchemes) -notcontains $guid) { throw "Güç planı oluşturuldu görünüyor ama listede yok: $guid" }
    return $true
}

$script:LtProviders['PowerScheme'] = @{
    Key = { param($a) 'PowerScheme|Active' }
    Capture = {
        param($a)
        @{ ActiveGuid = (Get-LtActivePowerScheme); TargetExisted = ((Get-LtPowerSchemes) -contains $a.Guid.ToLowerInvariant()) }
    }
    IsDesired = { param($a, $s) ($s.ActiveGuid -eq $a.Guid.ToLowerInvariant()) }
    Apply = {
        param($a)
        [void](Initialize-LtPowerScheme $a)
        Set-LtActivePowerScheme -Guid $a.Guid
    }
    Restore = {
        param($a, $s)
        # Yalnizca etkin plan geri alinir. Livn Tools'un sabit GUID ile olusturdugu
        # plan silinmez; tekrar uygulandiginda ayni plan yeniden kullanilir
        # (yinelenen plan olusmaz).
        Set-LtActivePowerScheme -Guid $s.ActiveGuid
    }
    Default = { param($a) Set-LtActivePowerScheme -Guid (Get-LtProp $a 'Default') }
    DefaultSnapshot = { param($a) @{ ActiveGuid = (Get-LtProp $a 'Default'); TargetExisted = $true } }
    FormatState   = { param($a, $s) "Etkin plan: $($s.ActiveGuid)" }
    FormatDesired = { param($a) "Etkin plan: $($a.Guid.ToLowerInvariant())" + $(if ($a.Source -ne 'Builtin') { ' (yoksa bir kez oluşturulur)' } else { '' }) }
    Target = { param($a) 'Etkin güç planı' }
}

# ---------------------------------------------------------------------------
# TCP GLOBAL
# ---------------------------------------------------------------------------
$script:LtProviders['TcpGlobal'] = @{
    Key = { param($a) "TcpGlobal|$($a.Setting)" }
    Capture = { param($a) @{ Value = (Get-LtTcpGlobal -Setting $a.Setting) } }
    IsDesired = { param($a, $s) ([string]$s.Value -ieq [string]$a.Value) }
    Apply = { param($a) Set-LtTcpGlobal -Setting $a.Setting -Value $a.Value }
    Restore = { param($a, $s) Set-LtTcpGlobal -Setting $a.Setting -Value $s.Value }
    Default = { param($a) Set-LtTcpGlobal -Setting $a.Setting -Value (Get-LtProp $a 'Default') }
    DefaultSnapshot = { param($a) @{ Value = (Get-LtProp $a 'Default') } }
    FormatState   = { param($a, $s) [string]$s.Value }
    FormatDesired = { param($a) [string]$a.Value }
    Target = { param($a) "TCP: $($a.Setting)" }
}

# ---------------------------------------------------------------------------
# NIC GELISMIS OZELLIK
# ---------------------------------------------------------------------------
$script:LtProviders['NicProperty'] = @{
    Key = { param($a) "Nic|$($a.InterfaceGuid)|$($a.Keyword)" }
    Capture = {
        param($a)
        $p = Get-LtNicProperty -Adapter $a.Adapter -Keyword $a.Keyword -InterfaceGuid ([string](Get-LtProp $a 'InterfaceGuid'))
        @{ Exists = $p.Exists; Value = $p.Value; Valid = @($p.Valid); Default = $p.Default }
    }
    IsDesired = { param($a, $s) ($s.Exists -and [string]$s.Value -eq [string]$a.Value) }
    Apply = {
        param($a)
        $p = Get-LtNicProperty -Adapter $a.Adapter -Keyword $a.Keyword -InterfaceGuid ([string](Get-LtProp $a 'InterfaceGuid'))
        if (-not $p.Exists) { throw "Adaptör bu özelliği desteklemiyor: $($a.Keyword)" }
        if (@($p.Valid).Count -gt 0 -and @($p.Valid) -notcontains [string]$a.Value) {
            throw "Sürücü '$($a.Value)' değerini kabul etmiyor (geçerli: $(@($p.Valid) -join ','))"
        }
        Set-LtNicProperty -Adapter $a.Adapter -Keyword $a.Keyword -InterfaceGuid ([string](Get-LtProp $a 'InterfaceGuid')) -Value $a.Value
    }
    Restore = { param($a, $s) if ($s.Exists) { Set-LtNicProperty -Adapter $a.Adapter -Keyword $a.Keyword -InterfaceGuid ([string](Get-LtProp $a 'InterfaceGuid')) -Value ([string]$s.Value) } }
    Default = { param($a) Reset-LtNicProperty -Adapter $a.Adapter -Keyword $a.Keyword -InterfaceGuid ([string](Get-LtProp $a 'InterfaceGuid')) }
    DefaultSnapshot = { param($a) $p = Get-LtNicProperty -Adapter $a.Adapter -Keyword $a.Keyword -InterfaceGuid ([string](Get-LtProp $a 'InterfaceGuid')); @{ Exists = $true; Value = [string]$p.Default } }
    FormatState   = { param($a, $s) if ($s.Exists) { 'Kayıtlı tercih: ' + [string]$s.Value + '; etkin durum ayrıca doğrulanmalı' } else { 'özellik yok' } }
    FormatDesired = { param($a) [string]$a.Value }
    Target = { param($a) "Adaptör '$($a.Adapter)': $($a.Keyword)" }
}

# ---------------------------------------------------------------------------
# OLAY GUNLUGU BOYUTU
# ---------------------------------------------------------------------------
$script:LtProviders['EventLogSize'] = @{
    Key = { param($a) "EventLogSize|$($a.Log)" }
    Capture = { param($a) @{ Bytes = (Get-LtEventLogMaxSize -LogName $a.Log) } }
    IsDesired = { param($a, $s) ([long]$s.Bytes -ge [long]$a.Bytes) }
    Apply = { param($a) Set-LtEventLogMaxSize -LogName $a.Log -Bytes $a.Bytes }
    Restore = { param($a, $s) Set-LtEventLogMaxSize -LogName $a.Log -Bytes ([long]$s.Bytes) }
    Default = { param($a) Set-LtEventLogMaxSize -LogName $a.Log -Bytes ([long](Get-LtProp $a 'Default')) }
    DefaultSnapshot = { param($a) @{ Bytes = [long](Get-LtProp $a 'Default') } }
    FormatState   = { param($a, $s) Format-LtBytes ([long]$s.Bytes) }
    FormatDesired = { param($a) 'en az ' + (Format-LtBytes ([long]$a.Bytes)) }
    Target = { param($a) "Olay günlüğü boyutu: $($a.Log)" }
}

# ---------------------------------------------------------------------------
# SISTEM MITIGASYONU (CFG). Ham kayit yalniz tani icindir. Geri alma sadece
# adlandirilmis mitigasyonu degistirir; diger guvenlik tercihlerini ezmez.
# ---------------------------------------------------------------------------
$script:LtProviders['Mitigation'] = @{
    Key = { param($a) "Mitigation|System|$($a.Name)" }
    Capture = {
        param($a)
        $raw = Get-LtRegValue -Path $script:LtKernelKey -Name 'MitigationOptions'
        @{ State = (Get-LtSystemMitigation -Name $a.Name); Raw = @{ KeyExists = $raw.KeyExists; Exists = $raw.Exists; Kind = $raw.Kind; Data = $raw.Data } }
    }
    IsDesired = { param($a, $s) ($s.State -eq $a.State) }
    Apply = { param($a) Set-LtSystemMitigation -Name $a.Name -State $a.State }
    Restore = {
        param($a, $s)
        Set-LtSystemMitigation -Name $a.Name -State $s.State
    }
    Default = { param($a) Set-LtSystemMitigation -Name $a.Name -State (Get-LtProp $a 'Default') }
    DefaultSnapshot = { param($a) @{ State = (Get-LtProp $a 'Default') } }
    FormatState   = { param($a, $s) "$($a.Name): $($s.State)" }
    FormatDesired = { param($a) "$($a.Name): $($a.State)" }
    Target = { param($a) "Sistem mitigasyonu: $($a.Name)" }
}

# ---------------------------------------------------------------------------
# ZAMANLANMIS GOREV (oturum acilisinda). Register -Force ile idempotent.
# ---------------------------------------------------------------------------
$script:LtProviders['ScheduledTask'] = @{
    Key = { param($a) "Task|$($a.TaskPath)$($a.TaskName)" }
    Capture = {
        param($a)
        $t = Get-LtScheduledTaskInfo -TaskPath $a.TaskPath -TaskName $a.TaskName
        @{ Exists = $t.Exists; Execute = $t.Execute; Arguments = $t.Arguments; Xml = $t.Xml }
    }
    IsDesired = {
        param($a, $s)
        if (Get-LtProp $a 'Absent' $false) { return (-not $s.Exists) }
        return ($s.Exists -and [string]$s.Execute -ieq [string]$a.Execute -and [string]$s.Arguments -eq [string]$a.Arguments)
    }
    Apply = {
        param($a)
        if (Get-LtProp $a 'Absent' $false) { Unregister-LtTask -TaskPath $a.TaskPath -TaskName $a.TaskName; return }
        if (-not (Test-Path -LiteralPath $a.Execute)) { throw "Çalıştırılabilir dosya bulunamadı: $($a.Execute)" }
        Register-LtLogonTask -TaskPath $a.TaskPath -TaskName $a.TaskName -Execute $a.Execute -Arguments $a.Arguments
    }
    Restore = {
        param($a, $s)
        if ($s.Exists) { Restore-LtScheduledTaskXml -TaskPath $a.TaskPath -TaskName $a.TaskName -Xml $s.Xml }
        else { Unregister-LtTask -TaskPath $a.TaskPath -TaskName $a.TaskName }
    }
    Default = { param($a) Unregister-LtTask -TaskPath $a.TaskPath -TaskName $a.TaskName }
    DefaultSnapshot = { param($a) @{ Exists = $false } }
    FormatState   = { param($a, $s) if ($s.Exists) { "var: $($s.Execute) $($s.Arguments)" } else { 'görev yok' } }
    FormatDesired = { param($a) if (Get-LtProp $a 'Absent' $false) { 'görev yok' } else { "oturum açılışında: $($a.Execute) $($a.Arguments)" } }
    Target = { param($a) "Zamanlanmış görev: $($a.TaskPath)$($a.TaskName)" }
}

# ---------------------------------------------------------------------------
# HAZIRDA BEKLETME
# ---------------------------------------------------------------------------
$script:LtProviders['Hibernate'] = @{
    Key = { param($a) 'Hibernate|System' }
    Capture = { param($a) Get-LtHibernateConfiguration }
    IsDesired = { param($a, $s) ([bool]$s.Enabled -eq [bool]$a.Enabled) }
    Apply = { param($a) Set-LtHibernateEnabled -Enabled ([bool]$a.Enabled) }
    Restore = { param($a, $s) Restore-LtHibernateConfiguration -Snapshot $s }
    Default = { param($a) throw 'Hazirda bekletme icin evrensel Windows varsayilani yok.' }
    DefaultSnapshot = { param($a) throw 'Hazirda bekletme icin evrensel Windows varsayilani yok.' }
    FormatState   = { param($a, $s) if ($s.Enabled) { 'açık ({0})' -f $s.FileType } else { 'kapalı' } }
    FormatDesired = { param($a) if ($a.Enabled) { 'açık' } else { 'kapalı' } }
    Target = { param($a) 'Hazırda bekletme' }
}

$script:LtProviders['UserParameter'] = @{
    Key = { param($a) 'UserParameter|{0}|{1}' -f (Get-LtInteractiveUserSid), $a.Setting }
    Capture = { param($a) Get-LtUserParameterSnapshot $a.Setting }
    IsDesired = {
        param($a, $s)
        if ((@($s.Values) -join ',') -ne (@($a.Values) -join ',')) { return $false }
        for ($i=0; $i -lt @($s.Raw).Count; $i++) {
            $raw = $s.Raw[$i].State
            if (-not $raw.Exists -or $raw.Kind -ne 'String' -or [string]$raw.Data -ne [string]$a.Values[$i]) { return $false }
        }
        return $true
    }
    Apply = { param($a) Set-LtUserParameter -Setting $a.Setting -Values ([int[]]$a.Values) }
    Restore = { param($a, $s) Restore-LtUserParameterSnapshot -Setting $a.Setting -Snapshot $s }
    FormatState = { param($a, $s) 'Oturum değeri: ' + (@($s.Values) -join ', ') + '; kullanıcı: ' + $s.UserSid }
    FormatDesired = { param($a) @($a.Values) -join ', ' }
    Target = { param($a) 'Windows kullanıcı tercihi: ' + $a.Setting }
}

$script:LtProviders['Pagefile'] = @{
    Key = { param($a) 'Pagefile|System' }
    Capture = { param($a) Get-LtPagefileConfiguration }
    IsDesired = { param($a, $s) [bool]$s.Automatic }
    Apply = { param($a) Set-LtPagefileAutomatic -Enabled $true }
    Restore = { param($a, $s) Restore-LtPagefileConfiguration -Snapshot $s }
    FormatState = {
        param($a, $s)
        $mode = if ($s.Automatic) { 'otomatik' } else { 'elle' }
        $rows = @($s.Settings | ForEach-Object { "$($_.Name): $($_.InitialSize)-$($_.MaximumSize) MB" })
        "Yapılandırma: $mode; $($rows -join '; '). Etkin boyut yeniden başlatma sonrası doğrulanmalı."
    }
    FormatDesired = { param($a) 'Otomatik yönetim yapılandırıldı; etkinleşme yeniden başlatma gerektirebilir' }
    Target = { param($a) 'Sistem pagefile yapılandırması' }
}

# ---------------------------------------------------------------------------
# Ortak giris noktalari
# ---------------------------------------------------------------------------
function Get-LtProvider([string]$Type) {
    if (-not $script:LtProviders.ContainsKey($Type)) { throw "Bilinmeyen eylem türü: $Type" }
    return $script:LtProviders[$Type]
}

function Get-LtActionKey($Action)          { & (Get-LtProvider $Action.Type).Key $Action }
function Get-LtActionSnapshot($Action)     { & (Get-LtProvider $Action.Type).Capture $Action }
function Test-LtActionDesired($Action, $Snapshot) { [bool](& (Get-LtProvider $Action.Type).IsDesired $Action $Snapshot) }
function Invoke-LtActionApply($Action)     { & (Get-LtProvider $Action.Type).Apply $Action }
function Restore-LtActionSnapshot($Action, $Snapshot) { & (Get-LtProvider $Action.Type).Restore $Action $Snapshot }
function Test-LtActionHasDefault($Action)  { $null -ne (Get-LtProp $Action 'Default') }
function Invoke-LtActionDefault($Action) {
    if (-not (Test-LtActionHasDefault $Action)) { throw 'Bu ayar için Windows varsayılanı tanımlı değil.' }
    & (Get-LtProvider $Action.Type).Default $Action
}
function Get-LtActionDefaultSnapshot($Action) { & (Get-LtProvider $Action.Type).DefaultSnapshot $Action }
function Format-LtActionState($Action, $Snapshot) { [string](& (Get-LtProvider $Action.Type).FormatState $Action $Snapshot) }
function Format-LtActionDesired($Action)   { [string](& (Get-LtProvider $Action.Type).FormatDesired $Action) }
function Get-LtActionTarget($Action)       { [string](& (Get-LtProvider $Action.Type).Target $Action) }

function Test-LtSnapshotEqual {
    <# Iki durum goruntusu ayni sistem durumunu mu ifade ediyor? (dogrulama icin) #>
    param($Action, $A, $B)
    switch ($Action.Type) {
        'Registry' {
            if ((ConvertTo-LtRegPath $Action.Path).Hive -eq 'HKCU') {
                $sa = [string](Get-LtProp $A 'UserSid' ''); $sb = [string](Get-LtProp $B 'UserSid' '')
                if (-not $sa -or $sa -ne $sb) { return $false }
            }
            if ([bool]$A.Exists -ne [bool]$B.Exists) { return $false }
            if (-not $A.Exists) { return $true }
            return ($A.Kind -eq $B.Kind -and (Test-LtRegDataEqual $A.Data $B.Data $A.Kind))
        }
        'Service'       { return ([bool]$A.Exists -eq [bool]$B.Exists -and $A.StartType -eq $B.StartType -and ($A.Status -eq 'Unknown' -or $B.Status -eq 'Unknown' -or $A.Status -eq $B.Status)) }
        'Bcd'           { return ($A.Value -eq $B.Value) }
        'PowerScheme'   { return ($A.ActiveGuid -eq $B.ActiveGuid) }
        'TcpGlobal'     { return ([string]$A.Value -ieq [string]$B.Value) }
        'NicProperty'   { return ([string]$A.Value -eq [string]$B.Value) }
        'EventLogSize'  { return ([long]$A.Bytes -eq [long]$B.Bytes) }
        'Mitigation'    { return ($A.State -eq $B.State) }
        'ScheduledTask' { return ([bool]$A.Exists -eq [bool]$B.Exists -and ((-not $A.Exists) -or ([string]$A.Execute -ieq [string]$B.Execute -and [string]$A.Arguments -eq [string]$B.Arguments))) }
        'UserParameter' { return (Test-LtUserParameterSnapshotEqual $A $B) }
        'Pagefile'      { return (Test-LtPagefileConfigurationEqual $A $B) }
        'Hibernate'     { return (Test-LtHibernateConfigurationEqual $A $B) }
        'DnsServers'    { return (Test-LtDnsSnapshotEqual $A $B) }
        default         { throw "Karşılaştırma tanımsız: $($Action.Type)" }
    }
}
