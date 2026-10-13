# Livn Tools - Core/Backend.ps1
# Sistem ilkelleri (registry, servis, BCD, guc plani, TCP, NIC, olay gunlugu,
# sistem mitigasyonu, zamanlanmis gorev, hazirda bekletme).
#
# Iki arka uc vardir:
#   Windows : gercek sistem (yalniz Windows'ta, yonetici olarak)
#   Memory  : tamamen bellek ici sahte sistem. Testler ve "kuru calistirma"
#             bununla yapilir; gercek sisteme ASLA dokunmaz.
# Tum ilkeller hata durumunda istisna firlatir; cagiran taraf (provider/engine)
# yakalar ve sonuca donusturur.

Set-StrictMode -Version 2.0

$script:LtBackend = 'Windows'
$script:Mem = $null

function Set-LtBackend {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('Windows','Memory')][string]$Name)
    $script:LtBackend = $Name
    if ($Name -eq 'Memory' -and $null -eq $script:Mem) { Reset-LtMemoryBackend }
}

function Get-LtBackend { $script:LtBackend }

function Reset-LtMemoryBackend {
    <#
      Bellek ici sahte sistemi sifirlar. Testler durumu dogrudan
      $state = Get-LtMemoryState ile ayarlayabilir.
      Faults  : @{ 'Service.SetStartType:DiagTrack' = 'Erisim reddedildi' } -> ilgili cagri istisna firlatir
      NoOps   : @{ 'Registry.Set:HKLM\X|Y' = $true } -> cagri basarili gorunur ama degisiklik yapmaz (dogrulama testi)
    #>
    $script:Mem = @{
        UserSettings = @{ UserSid='S-1-5-21-1000'; SessionOwnerSid='S-1-5-21-1000'; Mouse=[int[]]@(6,10,1); MenuDelay=[int[]]@(400); Animation=[int[]]@(1); VisualEffects=[int[]]@(1,1,1,1,1) }
        HibernateType = 'Full'
        Pagefile     = @{ Automatic = $false; Settings = @() }
        Registry     = @{}                      # keyLower -> @{ Path; Values = @{ nameLower -> @{Name;Kind;Data} } }
        ServiceState = @{}                      # nameLower -> 'Running'|'Stopped'
        BcdCurrent   = '{11111111-2222-3333-4444-555555555555}'
        PowerSchemes = New-Object System.Collections.ArrayList
        PowerActive  = '381b4222-f694-41f0-9685-ff5bb260df2e'
        Tcp          = @{ AutoTuningLevel = 'Normal'; EcnCapability = 'Disabled'; CongestionProvider = 'CUBIC'; Rsc = 'Enabled'; Rss = 'Enabled' }
        Nic          = @{}                      # "adapter|keyword" -> @{ Value; Valid = @(); Default }
        EventLogSize = @{ 'Application' = 20971520; 'System' = 20971520; 'Security' = 20971520 }
        Tasks        = @{}                      # "\path\name" -> @{ Execute; Arguments; Xml }
        Setup        = @{ WingetAvailable = $true; InstalledIds = @() }   # sahte WinGet envanteri (Read-LtWingetInventory)
        Processes    = @()                      # sahte surecler: @(@{ Name; HasWindow }) (Core/SideEffects.ps1)
        Faults       = @{}
        NoOps        = @{}
        Calls        = New-Object System.Collections.ArrayList
    }
    foreach ($g in @('381b4222-f694-41f0-9685-ff5bb260df2e', '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c', 'a1841308-3541-4fab-bc81-f71556f20b4a')) {
        [void]$script:Mem.PowerSchemes.Add($g)
    }
}

function Get-LtMemoryState { $script:Mem }

function Set-LtMemoryState {
    <# Kuru calisma: UI ve arka plan runspace'i AYNI bellek ici sistemi paylasir. #>
    param([Parameter(Mandatory)][hashtable]$State)
    $script:Mem = $State
}

function Invoke-LtMemFault {
    param([string]$Op, [string]$Target)
    [void]$script:Mem.Calls.Add("$Op|$Target")
    $k = "${Op}:$Target"
    if ($script:Mem.Faults.ContainsKey($k)) { throw [string]$script:Mem.Faults[$k] }
    if ($script:Mem.Faults.ContainsKey("${Op}:*")) { throw [string]$script:Mem.Faults["${Op}:*"] }
    return [bool]($script:Mem.NoOps.ContainsKey($k))
}

# ===========================================================================
# REGISTRY
# ===========================================================================
function ConvertTo-LtRegPath {
    <# 'HKLM:\X', 'HKEY_LOCAL_MACHINE\X', 'HKLM\X' -> @{ Hive='HKLM'; Sub='X'; Full='HKLM\X' } #>
    param([Parameter(Mandatory)][string]$Path)
    $p = $Path.Trim() -replace '/', '\'
    $p = $p -replace '^Registry::', ''
    $map = @{
        'HKEY_LOCAL_MACHINE' = 'HKLM'; 'HKLM' = 'HKLM'
        'HKEY_CURRENT_USER'  = 'HKCU'; 'HKCU' = 'HKCU'
        'HKEY_USERS'         = 'HKU';  'HKU'  = 'HKU'
        'HKEY_CLASSES_ROOT'  = 'HKCR'; 'HKCR' = 'HKCR'
    }
    if ($p -notmatch '^(?<h>[A-Za-z_]+):?\\?(?<s>.*)$') { throw "Geçersiz registry yolu: $Path" }
    $h = $Matches['h'].ToUpperInvariant()
    if (-not $map.ContainsKey($h)) { throw "Desteklenmeyen hive: $Path" }
    $sub = $Matches['s'].Trim('\')
    $hive = $map[$h]
    [pscustomobject]@{ Hive = $hive; Sub = $sub; Full = if ($sub) { "$hive\$sub" } else { $hive } }
}

function Get-LtWinBaseKey([string]$Hive) {
    $enum = switch ($Hive) {
        'HKLM' { [Microsoft.Win32.RegistryHive]::LocalMachine }
        'HKCU' { [Microsoft.Win32.RegistryHive]::CurrentUser }
        'HKU'  { [Microsoft.Win32.RegistryHive]::Users }
        'HKCR' { [Microsoft.Win32.RegistryHive]::ClassesRoot }
    }
    # 32-bit PowerShell'de bile 64-bit gorunum (WOW6432Node yonlendirmesi olmasin)
    return [Microsoft.Win32.RegistryKey]::OpenBaseKey($enum, [Microsoft.Win32.RegistryView]::Registry64)
}

function ConvertTo-LtRegData {
    <# .NET registry degerini JSON'a guvenle yazilabilir bicime cevirir. #>
    param($Value, [string]$Kind)
    switch ($Kind) {
        'DWord'        { return [long][BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$Value), 0) }
        'QWord'        { return ([long]$Value).ToString([Globalization.CultureInfo]::InvariantCulture) }
        'Binary'       { return [Convert]::ToBase64String([byte[]]$Value) }
        'None'         { if ($Value -is [byte[]]) { return [Convert]::ToBase64String($Value) } return '' }
        'MultiString'  { return ,([string[]]@($Value)) }
        default        { return [string]$Value }
    }
}

function ConvertFrom-LtRegData {
    <# JSON bicimindeki veriyi .NET SetValue icin nesneye cevirir. #>
    param($Data, [string]$Kind)
    switch ($Kind) {
        'DWord'       {
            # 0xFFFFFFFF PowerShell'de Int32 -1 olarak ayristirilir; isaretsiz aralaga tasi
            $l = [long]$Data
            if ($l -lt 0) { $l += 4294967296 }
            if ($l -gt 4294967295) { throw "DWORD aralığı dışında: $Data" }
            return [BitConverter]::ToInt32([BitConverter]::GetBytes([uint32]$l), 0)
        }
        'QWord'       { return [long]::Parse([string]$Data, [Globalization.CultureInfo]::InvariantCulture) }
        'Binary'      { if ($Data -is [byte[]]) { return $Data } return [Convert]::FromBase64String([string]$Data) }
        'None'        { return [Convert]::FromBase64String([string]$Data) }
        'MultiString' { return [string[]]@($Data) }
        default       { return [string]$Data }
    }
}

function Test-LtRegDataEqual {
    param($A, $B, [string]$Kind)
    switch ($Kind) {
        'DWord'       { return ([long]$A -eq [long]$B) }
        'QWord'       { return ([string]$A -eq [string]$B) }
        'MultiString' {
            $a = @($A); $b = @($B)
            if ($a.Count -ne $b.Count) { return $false }
            for ($i = 0; $i -lt $a.Count; $i++) { if ([string]$a[$i] -cne [string]$b[$i]) { return $false } }
            return $true
        }
        default { return ([string]$A -ceq [string]$B) }
    }
}

function Get-LtRegValue {
    <#
      Donus: @{ KeyExists; Exists; Kind; Data }
      Kind: DWord|QWord|String|ExpandString|MultiString|Binary|None
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [AllowEmptyString()][string]$Name = '')
    $rp = ConvertTo-LtRegPath $Path
    if ($script:LtBackend -eq 'Memory') {
        [void]$script:Mem.Calls.Add("Registry.Get|$($rp.Full)|$Name")
        $k = $script:Mem.Registry[$rp.Full.ToLowerInvariant()]
        if ($null -eq $k) { return [pscustomobject]@{ KeyExists = $false; Exists = $false; Kind = $null; Data = $null } }
        $v = $k.Values[$Name.ToLowerInvariant()]
        if ($null -eq $v) { return [pscustomobject]@{ KeyExists = $true; Exists = $false; Kind = $null; Data = $null } }
        return [pscustomobject]@{ KeyExists = $true; Exists = $true; Kind = $v.Kind; Data = $v.Data }
    }
    $base = Get-LtWinBaseKey $rp.Hive
    try {
        $key = $base.OpenSubKey($rp.Sub, $false)
        if ($null -eq $key) { return [pscustomobject]@{ KeyExists = $false; Exists = $false; Kind = $null; Data = $null } }
        try {
            $names = $key.GetValueNames()
            $found = $false
            foreach ($n in $names) { if ($n -ieq $Name) { $found = $true; break } }
            if (-not $found) { return [pscustomobject]@{ KeyExists = $true; Exists = $false; Kind = $null; Data = $null } }
            $kind = $key.GetValueKind($Name).ToString()
            if ($kind -eq 'Unknown') { $kind = 'None' }
            $raw = $key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            return [pscustomobject]@{ KeyExists = $true; Exists = $true; Kind = $kind; Data = (ConvertTo-LtRegData -Value $raw -Kind $kind) }
        } finally { $key.Dispose() }
    } finally { $base.Dispose() }
}

function Test-LtRegKey {
    param([Parameter(Mandatory)][string]$Path)
    $rp = ConvertTo-LtRegPath $Path
    if ($script:LtBackend -eq 'Memory') { return $script:Mem.Registry.ContainsKey($rp.Full.ToLowerInvariant()) }
    $base = Get-LtWinBaseKey $rp.Hive
    try {
        $key = $base.OpenSubKey($rp.Sub, $false)
        if ($key) { $key.Dispose(); return $true }
        return $false
    } finally { $base.Dispose() }
}

function Get-LtRegSubKeyNames {
    param([Parameter(Mandatory)][string]$Path)
    $rp = ConvertTo-LtRegPath $Path
    if ($script:LtBackend -eq 'Memory') {
        $prefix = $rp.Full.ToLowerInvariant() + '\'
        $names = @{}
        foreach ($k in @($script:Mem.Registry.Keys)) {
            if ($k.StartsWith($prefix)) {
                $rest = $script:Mem.Registry[$k].Path.Substring($prefix.Length)
                $first = $rest.Split('\')[0]
                $names[$first.ToLowerInvariant()] = $first
            }
        }
        return @($names.Values)
    }
    $base = Get-LtWinBaseKey $rp.Hive
    try {
        $key = $base.OpenSubKey($rp.Sub, $false)
        if ($null -eq $key) { return @() }
        try { return @($key.GetSubKeyNames()) } finally { $key.Dispose() }
    } finally { $base.Dispose() }
}

function Get-LtRegValueNames {
    param([Parameter(Mandatory)][string]$Path)
    $rp = ConvertTo-LtRegPath $Path
    if ($script:LtBackend -eq 'Memory') {
        $k = $script:Mem.Registry[$rp.Full.ToLowerInvariant()]
        if ($null -eq $k) { return @() }
        return @($k.Values.Values | ForEach-Object { $_.Name })
    }
    $base = Get-LtWinBaseKey $rp.Hive
    try {
        $key = $base.OpenSubKey($rp.Sub, $false)
        if ($null -eq $key) { return @() }
        try { return @($key.GetValueNames()) } finally { $key.Dispose() }
    } finally { $base.Dispose() }
}

function New-LtRegKey {
    <# Anahtari olusturur. Donus: olusturulan anahtarlarin listesi (usten alta). #>
    param([Parameter(Mandatory)][string]$Path)
    $rp = ConvertTo-LtRegPath $Path
    if ($rp.Hive -eq 'HKCU') { [void](Get-LtInteractiveUserSid) }
    $segments = @($rp.Sub.Split('\') | Where-Object { $_ -ne '' })
    $created = New-Object System.Collections.ArrayList
    $cur = $rp.Hive
    foreach ($s in $segments) {
        $cur = "$cur\$s"
        if (-not (Test-LtRegKey $cur)) { [void]$created.Add($cur) }
    }
    if ($created.Count -eq 0) { return @() }
    if ($script:LtBackend -eq 'Memory') {
        if (Invoke-LtMemFault 'Registry.CreateKey' $rp.Full) { return @() }
        foreach ($c in $created) {
            $script:Mem.Registry[$c.ToLowerInvariant()] = @{ Path = $c; Values = @{} }
        }
        return @($created)
    }
    $base = Get-LtWinBaseKey $rp.Hive
    try {
        $key = $base.CreateSubKey($rp.Sub)
        if ($null -eq $key) { throw "Registry anahtarı oluşturulamadı: $($rp.Full)" }
        $key.Dispose()
    } finally { $base.Dispose() }
    return @($created)
}

function Set-LtRegValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [AllowEmptyString()][string]$Name = '',
        [Parameter(Mandatory)][ValidateSet('DWord','QWord','String','ExpandString','MultiString','Binary','None')][string]$Kind,
        [Parameter(Mandatory)][AllowEmptyString()][AllowNull()]$Data
    )
    $rp = ConvertTo-LtRegPath $Path
    if ($rp.Hive -eq 'HKCU') { [void](Get-LtInteractiveUserSid) }
    $created = @(New-LtRegKey $rp.Full)
    if ($script:LtBackend -eq 'Memory') {
        if (Invoke-LtMemFault 'Registry.Set' "$($rp.Full)|$Name") { return @($created) }
        $k = $script:Mem.Registry[$rp.Full.ToLowerInvariant()]
        # Veriyi normalize et (Windows arka ucuyla ayni bicim)
        $obj = ConvertFrom-LtRegData -Data $Data -Kind $Kind
        $k.Values[$Name.ToLowerInvariant()] = @{ Name = $Name; Kind = $Kind; Data = (ConvertTo-LtRegData -Value $obj -Kind $Kind) }
        return @($created)
    }
    $base = Get-LtWinBaseKey $rp.Hive
    try {
        $key = $base.OpenSubKey($rp.Sub, $true)
        if ($null -eq $key) { throw "Registry anahtarı açılamadı (yazma): $($rp.Full)" }
        try {
            $obj = ConvertFrom-LtRegData -Data $Data -Kind $Kind
            $key.SetValue($Name, $obj, [Microsoft.Win32.RegistryValueKind]$Kind)
        } finally { $key.Dispose() }
    } finally { $base.Dispose() }
    return @($created)
}

function Remove-LtRegValue {
    param([Parameter(Mandatory)][string]$Path, [AllowEmptyString()][string]$Name = '')
    $rp = ConvertTo-LtRegPath $Path
    if ($rp.Hive -eq 'HKCU') { [void](Get-LtInteractiveUserSid) }
    if ($script:LtBackend -eq 'Memory') {
        if (Invoke-LtMemFault 'Registry.Remove' "$($rp.Full)|$Name") { return }
        $k = $script:Mem.Registry[$rp.Full.ToLowerInvariant()]
        if ($k) { $k.Values.Remove($Name.ToLowerInvariant()) }
        return
    }
    $base = Get-LtWinBaseKey $rp.Hive
    try {
        $key = $base.OpenSubKey($rp.Sub, $true)
        if ($null -eq $key) { return }
        try { $key.DeleteValue($Name, $false) } finally { $key.Dispose() }
    } finally { $base.Dispose() }
}

function Remove-LtRegKeyIfEmpty {
    <# Anahtar bos ise (deger ve alt anahtar yok) siler. Silindiyse $true. #>
    param([Parameter(Mandatory)][string]$Path)
    $rp = ConvertTo-LtRegPath $Path
    if ($rp.Hive -eq 'HKCU') { [void](Get-LtInteractiveUserSid) }
    if (-not (Test-LtRegKey $rp.Full)) { return $false }
    if (@(Get-LtRegSubKeyNames $rp.Full).Count -gt 0) { return $false }
    $vals = @(Get-LtRegValueNames $rp.Full)
    # Varsayilan deger bossa ('' adli deger yok) anahtar bos sayilir
    if ($vals.Count -gt 0) { return $false }
    if ($script:LtBackend -eq 'Memory') {
        if (Invoke-LtMemFault 'Registry.RemoveKey' $rp.Full) { return $false }
        $script:Mem.Registry.Remove($rp.Full.ToLowerInvariant())
        return $true
    }
    $base = Get-LtWinBaseKey $rp.Hive
    try { $base.DeleteSubKey($rp.Sub, $false) } finally { $base.Dispose() }
    return $true
}

# ===========================================================================
# SERVIS
# ===========================================================================
$script:LtStartTypeMap = @{ 0 = 'Boot'; 1 = 'System'; 2 = 'Automatic'; 3 = 'Manual'; 4 = 'Disabled' }
$script:LtScStartArg   = @{ Boot = 'boot'; System = 'system'; Automatic = 'auto'; AutomaticDelayed = 'delayed-auto'; Manual = 'demand'; Disabled = 'disabled' }

function Get-LtServiceInfo {
    <# Donus: @{ Exists; StartType; Status }. Baslangic turu registry'den okunur (yerellestirmeden bagimsiz). #>
    param([Parameter(Mandatory)][string]$Name)
    $keyPath = "HKLM\SYSTEM\CurrentControlSet\Services\$Name"
    $start = Get-LtRegValue -Path $keyPath -Name 'Start'
    if (-not $start.Exists) { return [pscustomobject]@{ Exists = $false; StartType = $null; Status = $null } }
    $type = $script:LtStartTypeMap[[int]$start.Data]
    if ($type -eq 'Automatic') {
        $d = Get-LtRegValue -Path $keyPath -Name 'DelayedAutostart'
        if ($d.Exists -and [long]$d.Data -eq 1) { $type = 'AutomaticDelayed' }
    }
    $status = 'Unknown'
    if ($script:LtBackend -eq 'Memory') {
        $s = $script:Mem.ServiceState[$Name.ToLowerInvariant()]
        if ($s) { $status = $s } else { $status = 'Stopped' }
    } else {
        $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
        if ($svc) { $status = $svc.Status.ToString() }
    }
    return [pscustomobject]@{ Exists = $true; StartType = $type; Status = $status }
}

function Set-LtServiceStartType {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][ValidateSet('Boot','System','Automatic','AutomaticDelayed','Manual','Disabled')][string]$StartType)
    if ($script:LtBackend -eq 'Memory') {
        if (Invoke-LtMemFault 'Service.SetStartType' $Name) { return }
        $keyPath = "HKLM\SYSTEM\CurrentControlSet\Services\$Name"
        if (-not (Test-LtRegKey $keyPath)) { throw "Servis bulunamadı: $Name (1060)" }
        $num = @{ Boot = 0; System = 1; Automatic = 2; AutomaticDelayed = 2; Manual = 3; Disabled = 4 }[$StartType]
        [void](Set-LtRegValue -Path $keyPath -Name 'Start' -Kind DWord -Data $num)
        if ($StartType -eq 'AutomaticDelayed') { [void](Set-LtRegValue -Path $keyPath -Name 'DelayedAutostart' -Kind DWord -Data 1) }
        elseif ($StartType -eq 'Automatic') { [void](Set-LtRegValue -Path $keyPath -Name 'DelayedAutostart' -Kind DWord -Data 0) }
        return
    }
    # sc.exe hem SCM'yi hem registry'yi gunceller; cikis kodu yerellestirmeden bagimsizdir.
    [void](Invoke-LtNativeChecked -FilePath "$env:SystemRoot\System32\sc.exe" -Arguments @('config', $Name, 'start=', $script:LtScStartArg[$StartType]) -TimeoutSec 60)
}

function Stop-LtServiceSafe {
    param([Parameter(Mandatory)][string]$Name, [int]$TimeoutSec = 20)
    if ($script:LtBackend -eq 'Memory') {
        if (Invoke-LtMemFault 'Service.Stop' $Name) { return }
        $script:Mem.ServiceState[$Name.ToLowerInvariant()] = 'Stopped'
        return
    }
    $svc = Get-Service -Name $Name -ErrorAction Stop
    if ($svc.Status -eq 'Stopped') { return }
    Stop-Service -Name $Name -Force -ErrorAction Stop
    $svc.WaitForStatus('Stopped', [TimeSpan]::FromSeconds($TimeoutSec))
}

function Start-LtServiceSafe {
    param([Parameter(Mandatory)][string]$Name, [int]$TimeoutSec = 20)
    if ($script:LtBackend -eq 'Memory') {
        if (Invoke-LtMemFault 'Service.Start' $Name) { return }
        $script:Mem.ServiceState[$Name.ToLowerInvariant()] = 'Running'
        return
    }
    $svc = Get-Service -Name $Name -ErrorAction Stop
    if ($svc.Status -eq 'Running') { return }
    Start-Service -Name $Name -ErrorAction Stop
    $svc.WaitForStatus('Running', [TimeSpan]::FromSeconds($TimeoutSec))
}

# ===========================================================================
# BCD  (okuma: HKLM\BCD00000000 kovani, yazma: bcdedit, dogrulama: tekrar okuma)
# Oge tip kodlari: Microsoft Learn "BCD settings and BitLocker" tablosu.
# ===========================================================================
$script:LtBcdElementType = @{
    useplatformclock   = '260000a2'
    useplatformtick    = '260000a4'
    disabledynamictick = '260000a5'
}
$script:LtBcdCurrentGuid = $null

function ConvertFrom-LtBcdEnumOutput {
    <#
      'bcdedit /enum {current} /v' ciktisindan girdinin GUID'ini alir.
      Alan adlari (identifier/tanimlayici/Bezeichner) yerellestirilir; GUID bicimi degil.
      Tek nesne listelendigi icin ilk GUID "identifier" satiridir.
    #>
    param([string]$Text)
    $m = [regex]::Match([string]$Text, '\{[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\}')
    if (-not $m.Success) { throw 'Geçerli önyükleme girdisinin GUID değeri okunamadı.' }
    return $m.Value.ToLowerInvariant()
}

function Get-LtBcdCurrentGuid {
    if ($script:LtBackend -eq 'Memory') { return $script:Mem.BcdCurrent }
    if ($script:LtBcdCurrentGuid) { return $script:LtBcdCurrentGuid }
    $r = Invoke-LtNativeChecked -FilePath "$env:SystemRoot\System32\bcdedit.exe" -Arguments @('/enum', '{current}', '/v') -TimeoutSec 60
    $guid = ConvertFrom-LtBcdEnumOutput $r.StdOut
    if (-not (Test-LtRegKey "HKLM\BCD00000000\Objects\$guid")) {
        throw "BCD deposu registry üzerinden okunamadı (HKLM\BCD00000000\Objects\$guid)."
    }
    $script:LtBcdCurrentGuid = $guid
    return $guid
}

function Get-LtBcdElement {
    <# Donus: 'Absent' | 'Yes' | 'No' #>
    param([Parameter(Mandatory)][ValidateSet('useplatformclock','useplatformtick','disabledynamictick')][string]$Element)
    $guid = Get-LtBcdCurrentGuid
    $hex = $script:LtBcdElementType[$Element]
    $v = Get-LtRegValue -Path "HKLM\BCD00000000\Objects\$guid\Elements\$hex" -Name 'Element'
    if (-not $v.Exists) { return 'Absent' }
    $bytes = [Convert]::FromBase64String([string]$v.Data)
    if ($bytes.Length -gt 0 -and $bytes[0] -ne 0) { return 'Yes' }
    return 'No'
}

function Set-LtBcdElement {
    param(
        [Parameter(Mandatory)][ValidateSet('useplatformclock','useplatformtick','disabledynamictick')][string]$Element,
        [Parameter(Mandatory)][ValidateSet('Absent','Yes','No')][string]$Value
    )
    if ((Get-LtBcdElement $Element) -eq $Value) { return }
    if ($script:LtBackend -eq 'Memory') {
        if (Invoke-LtMemFault 'Bcd.Set' $Element) { return }
        $path = "HKLM\BCD00000000\Objects\$($script:Mem.BcdCurrent)\Elements\$($script:LtBcdElementType[$Element])"
        if ($Value -eq 'Absent') {
            Remove-LtRegValue -Path $path -Name 'Element'
            [void](Remove-LtRegKeyIfEmpty $path)
        } else {
            $b = if ($Value -eq 'Yes') { [byte[]](1) } else { [byte[]](0) }
            [void](Set-LtRegValue -Path $path -Name 'Element' -Kind Binary -Data ([Convert]::ToBase64String($b)))
        }
        return
    }
    $exe = "$env:SystemRoot\System32\bcdedit.exe"
    if ($Value -eq 'Absent') {
        [void](Invoke-LtNativeChecked -FilePath $exe -Arguments @('/deletevalue', '{current}', $Element) -TimeoutSec 60)
    } else {
        [void](Invoke-LtNativeChecked -FilePath $exe -Arguments @('/set', '{current}', $Element, $Value.ToLowerInvariant()) -TimeoutSec 60)
    }
}

# ===========================================================================
# GUC PLANI (GUID'ler yerellestirilmez; plan adlari kullanilmaz)
# ===========================================================================
$script:LtGuidRegex = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'

function ConvertFrom-LtPowercfgOutput {
    <# powercfg /list ve /getactivescheme ciktisindaki GUID'ler (plan adlari ve etiketler yerellestirilir). #>
    param([string]$Text)
    return @([regex]::Matches([string]$Text, $script:LtGuidRegex) | ForEach-Object { $_.Value.ToLowerInvariant() } | Select-Object -Unique)
}

function Get-LtPowerSchemes {
    if ($script:LtBackend -eq 'Memory') { return @($script:Mem.PowerSchemes) }
    $r = Invoke-LtNativeChecked -FilePath "$env:SystemRoot\System32\powercfg.exe" -Arguments @('/list') -TimeoutSec 60
    return @(ConvertFrom-LtPowercfgOutput $r.StdOut)
}

function Get-LtActivePowerScheme {
    if ($script:LtBackend -eq 'Memory') { return $script:Mem.PowerActive }
    $r = Invoke-LtNativeChecked -FilePath "$env:SystemRoot\System32\powercfg.exe" -Arguments @('/getactivescheme') -TimeoutSec 60
    $g = @(ConvertFrom-LtPowercfgOutput $r.StdOut)
    if ($g.Count -eq 0) { throw 'Etkin güç planı GUID değeri okunamadı.' }
    return $g[0]
}

function Set-LtActivePowerScheme {
    param([Parameter(Mandatory)][string]$Guid)
    $Guid = $Guid.ToLowerInvariant()
    if ($script:LtBackend -eq 'Memory') {
        if (Invoke-LtMemFault 'Power.SetActive' $Guid) { return }
        if ($script:Mem.PowerSchemes -notcontains $Guid) { throw "Güç planı bulunamadı: $Guid" }
        $script:Mem.PowerActive = $Guid
        return
    }
    [void](Invoke-LtNativeChecked -FilePath "$env:SystemRoot\System32\powercfg.exe" -Arguments @('/setactive', $Guid) -TimeoutSec 60)
}

function Import-LtPowerScheme {
    param([Parameter(Mandatory)][string]$File, [Parameter(Mandatory)][string]$Guid)
    $Guid = $Guid.ToLowerInvariant()
    if ($script:LtBackend -eq 'Memory') {
        if (Invoke-LtMemFault 'Power.Import' $Guid) { return }
        if (-not (Test-Path -LiteralPath $File)) { throw "Güç planı dosyası yok: $File" }
        if ($script:Mem.PowerSchemes -notcontains $Guid) { [void]$script:Mem.PowerSchemes.Add($Guid) }
        return
    }
    if (-not (Test-Path -LiteralPath $File)) { throw "Güç planı dosyası yok: $File" }
    [void](Invoke-LtNativeChecked -FilePath "$env:SystemRoot\System32\powercfg.exe" -Arguments @('/import', $File, $Guid) -TimeoutSec 60)
}

function Copy-LtPowerScheme {
    param([Parameter(Mandatory)][string]$SourceGuid, [Parameter(Mandatory)][string]$Guid)
    $Guid = $Guid.ToLowerInvariant()
    if ($script:LtBackend -eq 'Memory') {
        if (Invoke-LtMemFault 'Power.Duplicate' $Guid) { return }
        if ($script:Mem.PowerSchemes -notcontains $Guid) { [void]$script:Mem.PowerSchemes.Add($Guid) }
        return
    }
    [void](Invoke-LtNativeChecked -FilePath "$env:SystemRoot\System32\powercfg.exe" -Arguments @('/duplicatescheme', $SourceGuid, $Guid) -TimeoutSec 60)
}

function Remove-LtPowerScheme {
    param([Parameter(Mandatory)][string]$Guid)
    $Guid = $Guid.ToLowerInvariant()
    if ($script:LtBackend -eq 'Memory') {
        if (Invoke-LtMemFault 'Power.Delete' $Guid) { return }
        if ($script:Mem.PowerActive -eq $Guid) { throw 'Etkin plan silinemez.' }
        $script:Mem.PowerSchemes.Remove($Guid)
        return
    }
    [void](Invoke-LtNativeChecked -FilePath "$env:SystemRoot\System32\powercfg.exe" -Arguments @('/delete', $Guid) -TimeoutSec 60)
}

# ===========================================================================
# TCP GLOBAL (okuma: NetTCPIP CIM - yerellestirilmemis enum; yazma: netsh)
# ===========================================================================
function Get-LtTcpGlobal {
    param([Parameter(Mandatory)][ValidateSet('AutoTuningLevel','EcnCapability','CongestionProvider','Rsc','Rss')][string]$Setting)
    if ($script:LtBackend -eq 'Memory') { return [string]$script:Mem.Tcp[$Setting] }
    switch ($Setting) {
        'AutoTuningLevel'    { return [string](Get-NetTCPSetting -SettingName Internet -ErrorAction Stop).AutoTuningLevelLocal }
        'EcnCapability'      { return [string](Get-NetTCPSetting -SettingName Internet -ErrorAction Stop).EcnCapability }
        'CongestionProvider' { return [string](Get-NetTCPSetting -SettingName Internet -ErrorAction Stop).CongestionProvider }
        'Rsc'                { return [string](Get-NetOffloadGlobalSetting -ErrorAction Stop).ReceiveSegmentCoalescing }
        'Rss'                { return [string](Get-NetOffloadGlobalSetting -ErrorAction Stop).ReceiveSideScaling }
    }
}

function Set-LtTcpGlobal {
    param(
        [Parameter(Mandatory)][ValidateSet('AutoTuningLevel','EcnCapability','CongestionProvider','Rsc','Rss')][string]$Setting,
        [Parameter(Mandatory)][string]$Value
    )
    if ($script:LtBackend -eq 'Memory') {
        if (Invoke-LtMemFault 'Tcp.Set' $Setting) { return }
        $script:Mem.Tcp[$Setting] = $Value
        return
    }
    $v = $Value.ToLowerInvariant()
    $netsh = "$env:SystemRoot\System32\netsh.exe"
    switch ($Setting) {
        'AutoTuningLevel'    { $a = @('int', 'tcp', 'set', 'global', "autotuninglevel=$v") }
        'EcnCapability'      { $a = @('int', 'tcp', 'set', 'global', "ecncapability=$v") }
        'Rsc'                { $a = @('int', 'tcp', 'set', 'global', "rsc=$v") }
        'Rss'                { $a = @('int', 'tcp', 'set', 'global', "rss=$v") }
        'CongestionProvider' { $a = @('int', 'tcp', 'set', 'supplemental', 'template=internet', "congestionprovider=$v") }
    }
    [void](Invoke-LtNativeChecked -FilePath $netsh -Arguments $a -TimeoutSec 60)
}

# ===========================================================================
# NIC GELISMIS OZELLIKLER (RegistryKeyword + RegistryValue: yerellestirilmez)
# ===========================================================================
function Resolve-LtNicName {
    param([Parameter(Mandatory)][string]$InterfaceGuid)
    $guid = ([guid]$InterfaceGuid).ToString('D')
    if ($script:LtBackend -eq 'Memory') {
        $adapters = @($script:Mem.DemoContext.Nics)
    } else {
        $adapters = @(Get-NetAdapter -IncludeHidden -ErrorAction Stop)
    }
    $found = @($adapters | Where-Object { ([string]$_.InterfaceGuid).Trim('{}') -ieq $guid })
    if ($found.Count -ne 1) { throw "Adaptör kimliği bulunamadı veya belirsiz: $guid" }
    return [string]$found[0].Name
}

function Get-LtNicPropertyObject {
    param([Parameter(Mandatory)][string]$Adapter, [Parameter(Mandatory)][string]$Keyword)
    # Escape the adapter name and compare RegistryKeyword literally (*RSS is a real name).
    $items = @(Get-NetAdapterAdvancedProperty -Name ([WildcardPattern]::Escape($Adapter)) -AllProperties -ErrorAction Stop |
        Where-Object { $_.Name -ieq $Adapter -and $_.RegistryKeyword -ieq $Keyword })
    if ($items.Count -gt 1) { throw "Belirsiz adaptör özelliği: $Adapter/$Keyword" }
    if ($items.Count -eq 1) { return $items[0] }
    return $null
}

function Get-LtNicProperty {
    <# Donus: @{ Exists; Value; Valid; Default } #>
    param([Parameter(Mandatory)][string]$Adapter, [Parameter(Mandatory)][string]$Keyword, [string]$InterfaceGuid = '')
    if ($InterfaceGuid) { $Adapter = Resolve-LtNicName -InterfaceGuid $InterfaceGuid }
    if ($script:LtBackend -eq 'Memory') {
        $p = $script:Mem.Nic["$Adapter|$Keyword".ToLowerInvariant()]
        if ($null -eq $p) { return [pscustomobject]@{ Exists = $false; Value = $null; Valid = @(); Default = $null } }
        return [pscustomobject]@{ Exists = $true; Value = [string]$p.Value; Valid = @($p.Valid); Default = $p.Default }
    }
    $p = Get-LtNicPropertyObject -Adapter $Adapter -Keyword $Keyword
    if ($null -eq $p) { return [pscustomobject]@{ Exists = $false; Value = $null; Valid = @(); Default = $null } }
    return [pscustomobject]@{
        Exists  = $true
        Value   = (@($p.RegistryValue) -join ',')
        Valid   = @($p.ValidRegistryValues)
        Default = $p.DefaultRegistryValue
    }
}

function Set-LtNicProperty {
    param([Parameter(Mandatory)][string]$Adapter, [Parameter(Mandatory)][string]$Keyword, [Parameter(Mandatory)][string]$Value, [string]$InterfaceGuid = '')
    if ($InterfaceGuid) { $Adapter = Resolve-LtNicName -InterfaceGuid $InterfaceGuid }
    if ($script:LtBackend -eq 'Memory') {
        if (Invoke-LtMemFault 'Nic.Set' "$Adapter|$Keyword") { return }
        $k = "$Adapter|$Keyword".ToLowerInvariant()
        if ($null -eq $script:Mem.Nic[$k]) { throw "Adaptör özelliği yok: $Adapter/$Keyword" }
        $script:Mem.Nic[$k].Value = $Value
        return
    }
    $property = Get-LtNicPropertyObject -Adapter $Adapter -Keyword $Keyword
    if ($null -eq $property) { throw "Adaptör özelliği yok: $Adapter/$Keyword" }
    Set-NetAdapterAdvancedProperty -InputObject $property -RegistryValue $Value -NoRestart -ErrorAction Stop
}

function Reset-LtNicProperty {
    param([Parameter(Mandatory)][string]$Adapter, [Parameter(Mandatory)][string]$Keyword, [string]$InterfaceGuid = '')
    if ($InterfaceGuid) { $Adapter = Resolve-LtNicName -InterfaceGuid $InterfaceGuid }
    if ($script:LtBackend -eq 'Memory') {
        if (Invoke-LtMemFault 'Nic.Reset' "$Adapter|$Keyword") { return }
        $k = "$Adapter|$Keyword".ToLowerInvariant()
        $script:Mem.Nic[$k].Value = [string]$script:Mem.Nic[$k].Default
        return
    }
    # Reset-NetAdapterAdvancedProperty -RegistryKeyword Windows PowerShell 5.1'de her
    # surumde yok; surucunun bildirdigi varsayilan deger (DefaultRegistryValue) yazilir.
    $p = Get-LtNicPropertyObject -Adapter $Adapter -Keyword $Keyword
    if ($null -eq $p) { throw "Adaptör özelliği yok: $Adapter/$Keyword" }
    if ($null -eq $p.DefaultRegistryValue -or [string]$p.DefaultRegistryValue -eq '') { throw "Sürücü $Keyword için varsayılan değer bildirmiyor." }
    Set-NetAdapterAdvancedProperty -InputObject $p -RegistryValue $p.DefaultRegistryValue -NoRestart -ErrorAction Stop
}

# ===========================================================================
# OLAY GUNLUGU BOYUTU
# ===========================================================================
function Get-LtEventLogMaxSize {
    param([Parameter(Mandatory)][string]$LogName)
    if ($script:LtBackend -eq 'Memory') { return [long]$script:Mem.EventLogSize[$LogName] }
    return [long](Get-WinEvent -ListLog $LogName -ErrorAction Stop).MaximumSizeInBytes
}

function Set-LtEventLogMaxSize {
    param([Parameter(Mandatory)][string]$LogName, [Parameter(Mandatory)][long]$Bytes)
    if ($script:LtBackend -eq 'Memory') {
        if (Invoke-LtMemFault 'EventLog.Set' $LogName) { return }
        $script:Mem.EventLogSize[$LogName] = $Bytes
        return
    }
    [void](Invoke-LtNativeChecked -FilePath "$env:SystemRoot\System32\wevtutil.exe" -Arguments @('sl', $LogName, "/ms:$Bytes") -TimeoutSec 60)
}

# ===========================================================================
# SISTEM GENELI MITIGASYON (CFG)
# Kaynak durum: HKLM\...\Session Manager\kernel\MitigationOptions (REG_BINARY).
# CFG bitleri 40-43: 1 = ALWAYS_ON, 2 = ALWAYS_OFF, 0 = varsayilan (NOTSET).
# ===========================================================================
$script:LtKernelKey = 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel'

function Get-LtSystemMitigation {
    <# Donus: 'ON' | 'OFF' | 'NOTSET' #>
    param([Parameter(Mandatory)][ValidateSet('CFG')][string]$Name)
    if ($script:LtBackend -eq 'Memory') {
        $v = Get-LtRegValue -Path $script:LtKernelKey -Name 'MitigationOptions'
        if (-not $v.Exists) { return 'NOTSET' }
        $b = [Convert]::FromBase64String([string]$v.Data)
        if ($b.Length -lt 6) { return 'NOTSET' }
        switch ($b[5] -band 0x0F) { 1 { return 'ON' } 2 { return 'OFF' } default { return 'NOTSET' } }
    }
    $m = Get-ProcessMitigation -System -ErrorAction Stop
    $state = ([string]$m.$Name.Enable).ToUpperInvariant()
    if ($state -notin @('ON','OFF','NOTSET')) { throw "Mitigasyon durumu okunamadi: $Name" }
    return $state
}

function Set-LtSystemMitigation {
    param([Parameter(Mandatory)][ValidateSet('CFG')][string]$Name, [Parameter(Mandatory)][ValidateSet('ON','OFF','NOTSET')][string]$State)
    if ($script:LtBackend -eq 'Memory') {
        if (Invoke-LtMemFault 'Mitigation.Set' $Name) { return }
        $v = Get-LtRegValue -Path $script:LtKernelKey -Name 'MitigationOptions'
        if ($v.Exists) { $b = [Convert]::FromBase64String([string]$v.Data) } else { $b = New-Object byte[] 24 }
        if ($b.Length -lt 24) { $nb = New-Object byte[] 24; [Array]::Copy($b, $nb, $b.Length); $b = $nb }
        $nib = @{ ON = 1; OFF = 2; NOTSET = 0 }[$State]
        $b[5] = [byte](($b[5] -band 0xF0) -bor $nib)
        [void](Set-LtRegValue -Path $script:LtKernelKey -Name 'MitigationOptions' -Kind Binary -Data ([Convert]::ToBase64String($b)))
        return
    }
    switch ($State) {
        'OFF'    { Set-ProcessMitigation -System -Disable $Name -ErrorAction Stop }
        'ON'     { Set-ProcessMitigation -System -Enable $Name -ErrorAction Stop }
        'NOTSET' { Set-ProcessMitigation -System -Remove -Disable $Name -ErrorAction Stop }
    }
}

# ===========================================================================
# ZAMANLANMIS GOREV
# ===========================================================================
function Get-LtScheduledTaskInfo {
    <# Donus: @{ Exists; Execute; Arguments; Xml } #>
    param([Parameter(Mandatory)][string]$TaskPath, [Parameter(Mandatory)][string]$TaskName)
    $key = "$TaskPath$TaskName"
    if ($script:LtBackend -eq 'Memory') {
        $t = $script:Mem.Tasks[$key.ToLowerInvariant()]
        if ($null -eq $t) { return [pscustomobject]@{ Exists = $false; Execute = $null; Arguments = $null; Xml = $null } }
        return [pscustomobject]@{ Exists = $true; Execute = $t.Execute; Arguments = $t.Arguments; Xml = $t.Xml }
    }
    $t = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($null -eq $t) { return [pscustomobject]@{ Exists = $false; Execute = $null; Arguments = $null; Xml = $null } }
    $a = @($t.Actions)[0]
    $xml = Export-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction Stop
    return [pscustomobject]@{ Exists = $true; Execute = $a.Execute; Arguments = $a.Arguments; Xml = $xml }
}

function Register-LtLogonTask {
    param(
        [Parameter(Mandatory)][string]$TaskPath, [Parameter(Mandatory)][string]$TaskName,
        [Parameter(Mandatory)][string]$Execute, [string]$Arguments = '', [string]$Xml = ''
    )
    $key = "$TaskPath$TaskName"
    if ($script:LtBackend -eq 'Memory') {
        if (Invoke-LtMemFault 'Task.Register' $key) { return }
        $script:Mem.Tasks[$key.ToLowerInvariant()] = @{ Execute = $Execute; Arguments = $Arguments; Xml = "<Task exe='$Execute' args='$Arguments'/>" }
        return
    }
    if ($Xml) {
        [void](Register-ScheduledTask -Xml $Xml -TaskPath $TaskPath -TaskName $TaskName -Force -ErrorAction Stop)
        return
    }
    $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $action    = New-ScheduledTaskAction -Execute $Execute -Argument $Arguments
    $trigger   = New-ScheduledTaskTrigger -AtLogOn -User $user
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
    $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)
    # -Force: ayni ad varsa yeniden olusturur -> yinelenen gorev olusmaz
    [void](Register-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force -ErrorAction Stop)
}

function Restore-LtScheduledTaskXml {
    param([Parameter(Mandatory)][string]$TaskPath, [Parameter(Mandatory)][string]$TaskName, [Parameter(Mandatory)][string]$Xml)
    $key = "$TaskPath$TaskName"
    if ($script:LtBackend -eq 'Memory') {
        if (Invoke-LtMemFault 'Task.Register' $key) { return }
        $exe = ''; $arg = ''
        if ($Xml -match "exe='([^']*)'") { $exe = $Matches[1] }
        if ($Xml -match "args='([^']*)'") { $arg = $Matches[1] }
        $script:Mem.Tasks[$key.ToLowerInvariant()] = @{ Execute = $exe; Arguments = $arg; Xml = $Xml }
        return
    }
    [void](Register-ScheduledTask -Xml $Xml -TaskPath $TaskPath -TaskName $TaskName -Force -ErrorAction Stop)
}

function Unregister-LtTask {
    param([Parameter(Mandatory)][string]$TaskPath, [Parameter(Mandatory)][string]$TaskName)
    $key = "$TaskPath$TaskName"
    if ($script:LtBackend -eq 'Memory') {
        if (Invoke-LtMemFault 'Task.Unregister' $key) { return }
        $script:Mem.Tasks.Remove($key.ToLowerInvariant())
        return
    }
    if (Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -Confirm:$false -ErrorAction Stop
    }
}

# ===========================================================================
# HAZIRDA BEKLETME
# ===========================================================================
# SDK SYSTEM_POWER_CAPABILITIES: 76 bytes, BOOLEAN HiberFilePresent at 8,
# BOOLEAN AoAc (Modern Standby) at 20, BYTE HiberFileType at 22. Only these read-only fields are marshalled.
$script:LtPowerCapabilitiesSource = @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
namespace LivnTools {
    public static class PowerCapabilities {
        [StructLayout(LayoutKind.Explicit, Size=76)]
        public struct Capabilities {
            [FieldOffset(8)] public byte HiberFilePresent;
            [FieldOffset(20)] public byte AoAc;
            [FieldOffset(22)] public byte HiberFileType;
        }
        [DllImport("powrprof.dll", SetLastError=true)]
        [return: MarshalAs(UnmanagedType.U1)]
        private static extern bool GetPwrCapabilities(out Capabilities value);
        public static Capabilities Read() {
            Capabilities value;
            if (!GetPwrCapabilities(out value)) throw new Win32Exception(Marshal.GetLastWin32Error());
            return value;
        }
    }
}
'@

function Get-LtHibernateConfiguration {
    if ($script:LtBackend -eq 'Memory') {
        [void](Invoke-LtMemFault 'Hibernate.Read' 'system')
        $type = [string]$script:Mem.HibernateType
        $enabled = $type -ne 'None'
    } else {
        if (-not ('LivnTools.PowerCapabilities' -as [type])) {
            Add-Type -TypeDefinition $script:LtPowerCapabilitiesSource -Language CSharp -ErrorAction Stop
        }
        $caps = [LivnTools.PowerCapabilities]::Read()
        $enabled = $caps.HiberFilePresent -ne 0
        $type = switch ([int]$caps.HiberFileType) { 0 { 'None' } 1 { 'Reduced' } 2 { 'Full' } default { 'Unknown' } }
    }
    if ($type -notin @('None','Reduced','Full') -or ($enabled -ne ($type -ne 'None'))) {
        throw 'Hazirda bekletme dosya turu guvenilir bicimde okunamadi; islem durduruldu.'
    }
    $size = Get-LtRegValue -Path 'HKLM\SYSTEM\CurrentControlSet\Control\Power' -Name 'HiberFileSizePercent'
    if ($size.Exists -and ($size.Kind -ne 'DWord' -or [long]$size.Data -lt 0 -or [long]$size.Data -gt 100)) {
        throw 'Hazirda bekletme boyut tercihi desteklenmiyor; islem durduruldu.'
    }
    if ($type -eq 'Reduced' -and $size.Exists -and [long]$size.Data -ge 40) { throw 'Hazirda bekletme turu ve boyut tercihi celisiyor; islem durduruldu.' }
    @{ Version=2; Enabled=$enabled; FileType=$type; Size=@{ Exists=$size.Exists; Kind=$size.Kind; Data=$size.Data } }
}

function Get-LtModernStandby {
    <# Modern Bekleme (S0 / AoAc) destegi: $true / $false / $null (okunamadi). Salt okunur. #>
    if ($script:LtBackend -eq 'Memory') {
        if ($script:Mem.ContainsKey('DemoContext') -and $script:Mem.DemoContext -and $script:Mem.DemoContext.ContainsKey('ModernStandby')) { return $script:Mem.DemoContext.ModernStandby }
        return $false
    }
    try {
        if (-not ('LivnTools.PowerCapabilities' -as [type])) {
            Add-Type -TypeDefinition $script:LtPowerCapabilitiesSource -Language CSharp -ErrorAction Stop
        }
        return ([LivnTools.PowerCapabilities]::Read().AoAc -ne 0)
    } catch { return $null }
}

function Get-LtHibernateEnabled { return [bool](Get-LtHibernateConfiguration).Enabled }

function Set-LtHibernateEnabled {
    param([Parameter(Mandatory)][bool]$Enabled)
    if ($script:LtBackend -eq 'Memory') {
        if (Invoke-LtMemFault 'Hibernate.Set' 'system') { return }
        $script:Mem.HibernateType = if ($Enabled) { 'Full' } else { 'None' }
        return
    }
    $arg = if ($Enabled) { 'on' } else { 'off' }
    [void](Invoke-LtNativeChecked -FilePath "$env:SystemRoot\System32\powercfg.exe" -Arguments @('/hibernate', $arg) -TimeoutSec 120)
}

function Restore-LtHibernateConfiguration {
    param([Parameter(Mandatory)]$Snapshot)
    # A legacy boolean cannot reconstruct the deleted file's type or size.
    if ((Get-LtProp $Snapshot 'Version') -ne 2) {
        throw 'Eski hazirda bekletme yedeginde dosya turu ve boyutu yok. Otomatik geri alma yapilamiyor; kayit korundu.'
    }
    $type = [string]$Snapshot.FileType
    if ($type -notin @('None','Reduced','Full') -or ([bool]$Snapshot.Enabled -ne ($type -ne 'None'))) {
        throw 'Gecersiz hazirda bekletme yedegi.'
    }
    $size = $Snapshot.Size
    $percent = 0
    if ($size.Exists) {
        if ($size.Kind -ne 'DWord' -or [long]$size.Data -lt 0 -or [long]$size.Data -gt 100) { throw 'Gecersiz hazirda bekletme boyutu.' }
        $percent = [int]$size.Data
    }
    if ($type -eq 'Reduced' -and $percent -ge 40) { throw 'Azaltilmis dosya ile boyut tercihi celisiyor.' }
    if ($script:LtBackend -eq 'Memory') {
        if (Invoke-LtMemFault 'Hibernate.Restore' 'system') { return }
        $script:Mem.HibernateType = $type
    } else {
        $exe = "$env:SystemRoot\System32\powercfg.exe"
        if (-not $Snapshot.Enabled) { Set-LtHibernateEnabled -Enabled $false }
        else {
            # Reset custom sizing before choosing type; then restore custom full sizing.
            [void](Invoke-LtNativeChecked -FilePath $exe -Arguments @('/hibernate','/size','0') -TimeoutSec 120)
            [void](Invoke-LtNativeChecked -FilePath $exe -Arguments @('/hibernate','/type',$type.ToLowerInvariant()) -TimeoutSec 120)
            if ($type -eq 'Full' -and $percent -ne 0) {
                [void](Invoke-LtNativeChecked -FilePath $exe -Arguments @('/hibernate','/size',[string]$percent) -TimeoutSec 120)
            }
        }
    }
    # Preserve absence as well as the stored size preference. Never write HiberFileType directly.
    $key = 'HKLM\SYSTEM\CurrentControlSet\Control\Power'
    if ($size.Exists) { [void](Set-LtRegValue -Path $key -Name 'HiberFileSizePercent' -Kind DWord -Data $size.Data) }
    else { Remove-LtRegValue -Path $key -Name 'HiberFileSizePercent' }
}

function Test-LtHibernateConfigurationEqual {
    param($A, $B)
    if ((Get-LtProp $A 'Version') -ne 2 -or (Get-LtProp $B 'Version') -ne 2) { return $false }
    if ([bool]$A.Enabled -ne [bool]$B.Enabled -or $A.FileType -ne $B.FileType -or [bool]$A.Size.Exists -ne [bool]$B.Size.Exists) { return $false }
    return ((-not $A.Size.Exists) -or ($A.Size.Kind -eq $B.Size.Kind -and [long]$A.Size.Data -eq [long]$B.Size.Data))
}

# Pagefile configuration (not the currently allocated pagefile usage).
$script:LtPagefileKey = 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
function Get-LtPagefileRegistryAction {
    @{ Type = 'Registry'; Path = $script:LtPagefileKey; Name = 'PagingFiles'; Kind = 'MultiString' }
}
function Get-LtPagefileConfiguration {
    if ($script:LtBackend -eq 'Memory') {
        [void](Invoke-LtMemFault 'Pagefile.Read' 'system')
        $automatic = [bool]$script:Mem.Pagefile.Automatic
        $settings = @($script:Mem.Pagefile.Settings)
    } else {
        $cs = Get-CimInstance -Namespace 'root/cimv2' -ClassName Win32_ComputerSystem -ErrorAction Stop
        if ($null -eq $cs.AutomaticManagedPagefile) { throw 'AutomaticManagedPagefile okunamadı.' }
        $automatic = [bool]$cs.AutomaticManagedPagefile
        $settings = @(Get-CimInstance -Namespace 'root/cimv2' -ClassName Win32_PageFileSetting -ErrorAction Stop)
    }
    # Copy primitive values so later mutations cannot change a journal snapshot.
    $rows = @($settings | Sort-Object { [string]$_.Name } | ForEach-Object {
        @{ Name = [string]$_.Name; InitialSize = [uint32]$_.InitialSize; MaximumSize = [uint32]$_.MaximumSize }
    })
    @{ Automatic = $automatic; Settings = $rows; Raw = (Get-LtActionSnapshot (Get-LtPagefileRegistryAction)) }
}
function Set-LtPagefileAutomatic {
    param([Parameter(Mandatory)][bool]$Enabled)
    if ($script:LtBackend -eq 'Memory') {
        if (Invoke-LtMemFault 'Pagefile.SetAutomatic' 'system') { return }
        $script:Mem.Pagefile.Automatic = $Enabled
        return
    }
    Assert-LtLiveSystem -Operation 'Pagefile otomatik yönetim'
    $cs = Get-CimInstance -Namespace 'root/cimv2' -ClassName Win32_ComputerSystem -ErrorAction Stop
    $cs | Set-CimInstance -Property @{ AutomaticManagedPagefile = $Enabled } -ErrorAction Stop | Out-Null
}
function Restore-LtPagefileConfiguration {
    param([Parameter(Mandatory)]$Snapshot)
    if ($script:LtBackend -eq 'Memory') {
        if (Invoke-LtMemFault 'Pagefile.Restore' 'system') { return }
        $script:Mem.Pagefile.Automatic = [bool]$Snapshot.Automatic
        $script:Mem.Pagefile.Settings = @($Snapshot.Settings | ForEach-Object {
            @{ Name = [string]$_.Name; InitialSize = [uint32]$_.InitialSize; MaximumSize = [uint32]$_.MaximumSize }
        })
        Restore-LtActionSnapshot (Get-LtPagefileRegistryAction) $Snapshot.Raw
        return
    }
    Assert-LtLiveSystem -Operation 'Pagefile önceki yapılandırmayı geri yükle'
    Set-LtPagefileAutomatic -Enabled $false
    $existing = @(Get-CimInstance -Namespace 'root/cimv2' -ClassName Win32_PageFileSetting -ErrorAction Stop)
    # Reconcile by name, without deleting retained entries first.
    foreach ($row in @($Snapshot.Settings)) {
        $properties = @{ InitialSize = [uint32]$row.InitialSize; MaximumSize = [uint32]$row.MaximumSize }
        $match = @($existing | Where-Object { $_.Name -ieq $row.Name })
        if ($match.Count -gt 0) {
            $match | Set-CimInstance -Property $properties -ErrorAction Stop | Out-Null
        } else {
            $properties.Name = [string]$row.Name
            New-CimInstance -Namespace 'root/cimv2' -ClassName Win32_PageFileSetting -Property $properties -ErrorAction Stop | Out-Null
        }
    }
    foreach ($row in $existing) {
        if (@($Snapshot.Settings | Where-Object { $_.Name -ieq $row.Name }).Count -eq 0) {
            $row | Remove-CimInstance -ErrorAction Stop
        }
    }
    Set-LtPagefileAutomatic -Enabled ([bool]$Snapshot.Automatic)
    # Preserve original presence, registry type and multi-string entries as well.
    Restore-LtActionSnapshot (Get-LtPagefileRegistryAction) $Snapshot.Raw
}
function Test-LtPagefileConfigurationEqual {
    param($A, $B)
    if ([bool]$A.Automatic -ne [bool]$B.Automatic) { return $false }
    if (@($A.Settings).Count -ne @($B.Settings).Count) { return $false }
    $left = @($A.Settings | Sort-Object { [string]$_.Name }); $right = @($B.Settings | Sort-Object { [string]$_.Name })
    for ($i = 0; $i -lt $left.Count; $i++) {
        if ($left[$i].Name -ine $right[$i].Name -or
            [uint32]$left[$i].InitialSize -ne [uint32]$right[$i].InitialSize -or
            [uint32]$left[$i].MaximumSize -ne [uint32]$right[$i].MaximumSize) { return $false }
    }
    return (Test-LtSnapshotEqual (Get-LtPagefileRegistryAction) $A.Raw $B.Raw)
}

# SystemParametersInfo: explicitly supported user preferences; visual effects form one snapshot.
$script:LtUserSettingsSource = @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
namespace LivnTools {
    public static class UserSettings {
        [DllImport("user32.dll", EntryPoint="SystemParametersInfoW", SetLastError=true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool Spi(uint action, uint param, IntPtr data, uint flags);
        private static void Check(bool result) {
            if (!result) throw new Win32Exception(Marshal.GetLastWin32Error());
        }
        private static readonly uint[] VisualGet = { 0x1002, 0x1004, 0x1016, 0x1014, 0x1042 };
        public static int[] Read(string setting) {
            if(setting=="VisualEffects") {
                int[] result=new int[VisualGet.Length];
                IntPtr slot=Marshal.AllocHGlobal(4);
                try {
                    for(int i=0;i<VisualGet.Length;i++) { Marshal.WriteInt32(slot,0); Check(Spi(VisualGet[i],0,slot,0)); result[i]=Marshal.ReadInt32(slot)==0 ? 0 : 1; }
                    return result;
                } finally { Marshal.FreeHGlobal(slot); }
            }
            uint action; int size; int count; int offset;
            switch (setting) {
                case "Mouse": action=3; size=12; count=3; offset=0; break;
                case "MenuDelay": action=0x6A; size=4; count=1; offset=0; break;
                case "Animation": action=0x48; size=8; count=1; offset=4; break;
                default: throw new ArgumentException("Unknown setting");
            }
            IntPtr p=Marshal.AllocHGlobal(size);
            try {
                for(int i=0;i<size;i+=4) Marshal.WriteInt32(p,i,0);
                if(setting=="Animation") Marshal.WriteInt32(p,8);
                Check(Spi(action,setting=="Animation" ? 8u : 0u,p,0));
                int[] values=new int[count];
                for(int i=0;i<count;i++) values[i]=Marshal.ReadInt32(p,offset+i*4);
                return values;
            } finally { Marshal.FreeHGlobal(p); }
        }
        public static void SetSystemParameter(string setting, int[] values, bool persist) {
            uint flags=persist ? 3u : 2u; // UPDATEINIFILE | SENDCHANGE, or notify only
            if(setting=="MenuDelay") {
                if(values.Length!=1 || values[0]<0) throw new ArgumentException("Invalid menu delay");
                Check(Spi(0x6B,(uint)values[0],IntPtr.Zero,flags)); return;
            }
            if(setting=="VisualEffects") {
                if(values.Length!=VisualGet.Length) throw new ArgumentException("Invalid visual settings");
                for(int i=0;i<values.Length;i++) if(values[i]!=0 && values[i]!=1) throw new ArgumentException("Invalid boolean");
                for(int i=0;i<values.Length;i++) Check(Spi(VisualGet[i]+1,0,new IntPtr(values[i]),flags));
                return;
            }
            int size; uint action;
            if(setting=="Mouse" && values.Length==3) { size=12; action=4; }
            else if(setting=="Animation" && values.Length==1) { size=8; action=0x49; }
            else throw new ArgumentException("Invalid setting values");
            IntPtr p=Marshal.AllocHGlobal(size);
            try {
                if(setting=="Animation") { Marshal.WriteInt32(p,0,8); Marshal.WriteInt32(p,4,values[0]); }
                else for(int i=0;i<3;i++) Marshal.WriteInt32(p,i*4,values[i]);
                Check(Spi(action,setting=="Animation" ? 8u : 0u,p,flags));
            } finally { Marshal.FreeHGlobal(p); }
        }
    }
}
'@
function Initialize-LtUserSettingsNative {
    if (-not ('LivnTools.UserSettings' -as [type])) {
        Add-Type -TypeDefinition $script:LtUserSettingsSource -Language CSharp -ErrorAction Stop
    }
}
function Get-LtInteractiveUserSid {
    if ($script:LtBackend -eq 'Memory') {
        if ($script:Mem.UserSettings.UserSid -ne $script:Mem.UserSettings.SessionOwnerSid) { throw 'İşlem hesabı oturumun kullanıcı hesabıyla eşleşmiyor.' }
        return [string]$script:Mem.UserSettings.UserSid
    }
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $session = [Diagnostics.Process]::GetCurrentProcess().SessionId
    $shells = @(Get-CimInstance Win32_Process -Filter "Name='explorer.exe' AND SessionId=$session" -ErrorAction Stop)
    $owners = @($shells | ForEach-Object {
        $owner = Invoke-CimMethod -InputObject $_ -MethodName GetOwnerSid -ErrorAction Stop
        if ($owner.ReturnValue -ne 0 -or -not $owner.Sid) { throw 'Oturum sahibi doğrulanamadı.' }
        [string]$owner.Sid
    } | Select-Object -Unique)
    if ($owners.Count -ne 1 -or $owners[0] -ne $sid) { throw 'Oturum sahibi doğrulanamadı veya farklı yönetici hesabı kullanılıyor. Kullanıcı tercihi değiştirilmedi.' }
    return $sid
}
function Get-LtUserParameterRegistryActions {
    param([ValidateSet('Mouse','MenuDelay','Animation','VisualEffects')][string]$Setting)
    switch ($Setting) {
        'Mouse' { foreach ($name in @('MouseThreshold1','MouseThreshold2','MouseSpeed')) { @{ Type='Registry'; Path='HKCU\Control Panel\Mouse'; Name=$name; Kind='String' } } }
        'MenuDelay' { @{ Type='Registry'; Path='HKCU\Control Panel\Desktop'; Name='MenuShowDelay'; Kind='String' } }
        # VisualEffects restores effective values via API; never overwrites unrelated mask bits.
        'VisualEffects' { }
        'Animation' { @{ Type='Registry'; Path='HKCU\Control Panel\Desktop\WindowMetrics'; Name='MinAnimate'; Kind='String' } }
    }
}
function Get-LtUserParameter {
    param([ValidateSet('Mouse','MenuDelay','Animation','VisualEffects')][string]$Setting)
    [void](Get-LtInteractiveUserSid)
    if ($script:LtBackend -eq 'Memory') { return ,([int[]]$script:Mem.UserSettings[$Setting].Clone()) }
    Initialize-LtUserSettingsNative
    return ,([LivnTools.UserSettings]::Read($Setting))
}
function Set-LtUserParameter {
    param([ValidateSet('Mouse','MenuDelay','Animation','VisualEffects')][string]$Setting, [int[]]$Values, [bool]$Persist = $true)
    [void](Get-LtInteractiveUserSid)
    if ($Setting -eq 'Mouse' -and ($Values.Count -ne 3 -or $Values[0] -lt 0 -or $Values[1] -lt 0 -or $Values[2] -lt 0 -or $Values[2] -gt 2)) { throw 'Geçersiz fare parametreleri.' }
    if ($Setting -notin @('Mouse','VisualEffects') -and ($Values.Count -ne 1 -or $Values[0] -lt 0)) { throw 'Geçersiz kullanıcı parametresi.' }
    if ($Setting -eq 'VisualEffects' -and ($Values.Count -ne 5 -or @($Values | Where-Object { $_ -notin @(0,1) }).Count -gt 0)) { throw 'Görsel efektler için beş boolean değer gerekli.' }
    if ($Setting -eq 'Animation' -and $Values[0] -gt 1) { throw 'Animasyon değeri 0 veya 1 olmalı.' }
    if ($script:LtBackend -eq 'Memory') {
        if (Invoke-LtMemFault 'UserParameter.Set' $Setting) { return }
        $script:Mem.UserSettings[$Setting] = [int[]]$Values.Clone()
        if ($Persist -and $Setting -ne 'VisualEffects') {
            $actions = @(Get-LtUserParameterRegistryActions $Setting)
            for ($i=0; $i -lt $actions.Count; $i++) { [void](Set-LtRegValue $actions[$i].Path $actions[$i].Name -Kind String -Data ([string]$Values[$i])) }
        }
        return
    }
    Assert-LtLiveSystem -Operation "Kullanıcı tercihi: $Setting"
    Initialize-LtUserSettingsNative
    [LivnTools.UserSettings]::SetSystemParameter($Setting, $Values, $Persist)
}
function Get-LtUserParameterSnapshot {
    param([ValidateSet('Mouse','MenuDelay','Animation','VisualEffects')][string]$Setting)
    $sid = Get-LtInteractiveUserSid
    $raw = @(foreach ($a in @(Get-LtUserParameterRegistryActions $Setting)) { @{ Action=$a; State=(Get-LtActionSnapshot $a) } })
    @{ UserSid=$sid; Values=(Get-LtUserParameter $Setting); Raw=$raw }
}
function Restore-LtUserParameterSnapshot {
    param([string]$Setting, $Snapshot)
    if ((Get-LtInteractiveUserSid) -ne $Snapshot.UserSid) { throw 'Yedek farklı kullanıcıya ait; geri yükleme reddedildi.' }
    foreach ($row in @($Snapshot.Raw)) { Assert-LtRegistrySnapshotOwner $row.Action $row.State }
    # Restore effective session values without persisting normalized API defaults.
    Set-LtUserParameter -Setting $Setting -Values ([int[]]$Snapshot.Values) -Persist ($Setting -eq 'VisualEffects')
    foreach ($row in @($Snapshot.Raw)) { Restore-LtActionSnapshot $row.Action $row.State }
}
function Test-LtUserParameterSnapshotEqual {
    param($A, $B)
    if ($A.UserSid -ne $B.UserSid -or (@($A.Values) -join ',') -ne (@($B.Values) -join ',')) { return $false }
    if (@($A.Raw).Count -ne @($B.Raw).Count) { return $false }
    for ($i=0; $i -lt @($A.Raw).Count; $i++) {
        if ((Get-LtActionKey $A.Raw[$i].Action) -ne (Get-LtActionKey $B.Raw[$i].Action)) { return $false }
        if (-not (Test-LtSnapshotEqual $A.Raw[$i].Action $A.Raw[$i].State $B.Raw[$i].State)) { return $false }
    }
    return $true
}


function Get-LtPowerPlanChoices {
    if ($script:LtBackend -eq 'Memory') {
        $names = @{
            '381b4222-f694-41f0-9685-ff5bb260df2e' = 'Dengeli'
            '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' = 'Yüksek performans'
            'a1841308-3541-4fab-bc81-f71556f20b4a' = 'Güç tasarrufu'
        }
        return @($script:Mem.PowerSchemes | ForEach-Object {
            $id = [string]$_
            $name = if ($names.ContainsKey($id)) { $names[$id] } else { 'Özel güç planı' }
            $active = $id -eq (Get-LtActivePowerScheme)
            [pscustomobject]@{ Guid=$id; Name=$name; IsActive=$active; Label=($name + ' (deneme)' + $(if ($active) { ' — Etkin' } else { '' })) }
        })
    }
    $r = Invoke-LtNativeChecked -FilePath "$env:SystemRoot\System32\powercfg.exe" -Arguments @('/list') -TimeoutSec 60
    # Name is display-only. All decisions use GUID, independent of Windows language.
    return @($r.StdOut -split '[\r\n]+' | ForEach-Object {
        $m = [regex]::Match($_, $script:LtGuidRegex)
        if ($m.Success) {
            $id = $m.Value.ToLowerInvariant()
            $label = $_.Substring($m.Index + $m.Length).Trim().TrimEnd('*').Trim()
            if ($label.StartsWith('(') -and $label.EndsWith(')')) { $label = $label.Substring(1, $label.Length - 2) }
            if (-not $label) { $label = 'Adsız güç planı' }
            $active = $_.TrimEnd().EndsWith('*')
            [pscustomobject]@{ Guid=$id; Name=$label; IsActive=$active; Label=($label + $(if ($active) { ' — Etkin' } else { '' })) }
        }
    })
}
