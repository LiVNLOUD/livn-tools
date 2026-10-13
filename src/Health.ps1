# Livn Tools - Health.ps1
# "Sistem Kontrolu": format sonrasi / oyun oncesi salt okunur saglik raporu.
# Iki katman:
#   Get-LtHealthFacts   -> ham bilgiler (Windows: CIM/registry/API; Memory: sahte sistem)
#   Get-LtHealthReport  -> bilgilerden durum + oneri + eylem (saf islev, birim testlenebilir)
# Hicbir kontrol sistem ayari degistirmez. Eylemler yalniz sabit, izinli bir listeden
# Windows ekranlarini veya Livn sayfalarini acar.

Set-StrictMode -Version 2.0

$script:LtDisplaySource = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
namespace LivnTools {
    public class DisplayModeInfo {
        public string Name; public string Adapter; public int Width; public int Height; public int Current; public int Max;
    }
    public static class DisplayInfo {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct DISPLAY_DEVICE {
            public int cb;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
            public int StateFlags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
        }
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct DEVMODE {
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
            public short dmSpecVersion; public short dmDriverVersion; public short dmSize; public short dmDriverExtra; public int dmFields;
            public int dmPositionX; public int dmPositionY; public int dmDisplayOrientation; public int dmDisplayFixedOutput;
            public short dmColor; public short dmDuplex; public short dmYResolution; public short dmTTOption; public short dmCollate;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
            public short dmLogPixels; public int dmBitsPerPel; public int dmPelsWidth; public int dmPelsHeight;
            public int dmDisplayFlags; public int dmDisplayFrequency;
            public int dmICMMethod; public int dmICMIntent; public int dmMediaType; public int dmDitherType;
            public int dmReserved1; public int dmReserved2; public int dmPanningWidth; public int dmPanningHeight;
        }
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern bool EnumDisplayDevices(string lpDevice, uint iDevNum, ref DISPLAY_DEVICE lpDisplayDevice, uint dwFlags);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);
        private const int ENUM_CURRENT_SETTINGS = -1;
        private const int ATTACHED_TO_DESKTOP = 0x1;

        /// <summary>Salt okunur: masaustune bagli her ekran icin mevcut ve ayni cozunurlukte desteklenen en yuksek yenileme hizi.</summary>
        public static DisplayModeInfo[] Read() {
            List<DisplayModeInfo> list = new List<DisplayModeInfo>();
            for (uint i = 0; i < 32; i++) {
                DISPLAY_DEVICE d = new DISPLAY_DEVICE(); d.cb = Marshal.SizeOf(typeof(DISPLAY_DEVICE));
                if (!EnumDisplayDevices(null, i, ref d, 0)) break;
                if ((d.StateFlags & ATTACHED_TO_DESKTOP) == 0) continue;
                DEVMODE cur = new DEVMODE(); cur.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
                if (!EnumDisplaySettings(d.DeviceName, ENUM_CURRENT_SETTINGS, ref cur)) continue;
                int max = cur.dmDisplayFrequency;
                for (int m = 0; m < 2000; m++) {
                    DEVMODE mode = new DEVMODE(); mode.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
                    if (!EnumDisplaySettings(d.DeviceName, m, ref mode)) break;
                    if (mode.dmPelsWidth == cur.dmPelsWidth && mode.dmPelsHeight == cur.dmPelsHeight && mode.dmDisplayFrequency > max) max = mode.dmDisplayFrequency;
                }
                DISPLAY_DEVICE mon = new DISPLAY_DEVICE(); mon.cb = Marshal.SizeOf(typeof(DISPLAY_DEVICE));
                string name = EnumDisplayDevices(d.DeviceName, 0, ref mon, 0) ? mon.DeviceString : d.DeviceName;
                DisplayModeInfo info = new DisplayModeInfo();
                info.Name = name; info.Adapter = d.DeviceString; info.Width = cur.dmPelsWidth; info.Height = cur.dmPelsHeight;
                info.Current = cur.dmDisplayFrequency; info.Max = max;
                list.Add(info);
            }
            return list.ToArray();
        }
    }
}
'@

# Kontrol eylemleri: yalniz bu sabit listeden acilir (keyfi komut/URI yok)
$script:LtHealthLinks = [ordered]@{
    'optional-drivers' = @{ Label = 'İsteğe bağlı sürücüler'; Uri = 'ms-settings:windowsupdate-optionalupdates' }
    'windows-update'   = @{ Label = 'Windows Update'; Uri = 'ms-settings:windowsupdate' }
    'device-manager'   = @{ Label = 'Aygıt Yöneticisi'; File = 'devmgmt.msc'; Args = '' }
    'display-advanced' = @{ Label = 'Gelişmiş ekran ayarları'; Uri = 'ms-settings:display-advanced' }
    'reliability'      = @{ Label = 'Güvenilirlik İzleyicisi'; File = 'perfmon.exe'; Args = '/rel' }
    'storage'          = @{ Label = 'Depolama ayarları'; Uri = 'ms-settings:storagesense' }
    'gaming'           = @{ Label = 'Oyun Modu ayarları'; Uri = 'ms-settings:gaming-gamemode' }
    'captures'         = @{ Label = 'Oyun kaydı ayarları'; Uri = 'ms-settings:gaming-gamedvr' }
    'graphics'         = @{ Label = 'Grafik ayarları'; Uri = 'ms-settings:display-advancedgraphics' }
    'power'            = @{ Label = 'Güç ayarları'; Uri = 'ms-settings:powersleep' }
    'driver-nvidia'    = @{ Label = 'NVIDIA sürücüleri'; Uri = 'https://www.nvidia.com/Download/index.aspx' }
    'driver-amd'       = @{ Label = 'AMD sürücüleri'; Uri = 'https://www.amd.com/en/support/download/drivers.html' }
    'driver-intel'     = @{ Label = 'Intel sürücüleri'; Uri = 'https://www.intel.com/content/www/us/en/support/detect.html' }
}

$script:LtProblemCodeText = @{
    1 = 'yapılandırılmamış'; 3 = 'sürücü bozuk veya bellek yetersiz'; 10 = 'başlatılamıyor'; 12 = 'kaynak çakışması'
    14 = 'yeniden başlatma gerekiyor'; 18 = 'sürücü yeniden yüklenmeli'; 19 = 'kayıt bilgisi bozuk'; 21 = 'kaldırılıyor'
    22 = 'devre dışı'; 24 = 'eksik veya hatalı kurulum'; 28 = 'sürücü yüklü değil'; 29 = 'donanım kaynağı yok'
    31 = 'sürücü yüklenemedi'; 32 = 'sürücü hizmeti devre dışı'; 37 = 'sürücü başlatılamadı'; 39 = 'sürücü yüklenemiyor'
    41 = 'sürücü yüklendi ama aygıt bulunamadı'; 43 = 'aygıt sorun bildirdi'; 48 = 'sürücü engellendi'; 52 = 'sürücü imzası doğrulanamadı'
}

# ---------------------------------------------------------------------------
# Ham bilgiler
# ---------------------------------------------------------------------------
function Get-LtPendingRebootReasons {
    <# Registry'den (Windows ve Memory arka ucu ayni kod). #>
    $reasons = New-Object System.Collections.ArrayList
    if (Test-LtRegKey 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { [void]$reasons.Add('Windows bileşen güncellemesi') }
    if (Test-LtRegKey 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { [void]$reasons.Add('Windows Update') }
    $pfro = Get-LtRegValue 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager' 'PendingFileRenameOperations'
    if ($pfro.Exists -and @($pfro.Data | Where-Object { $_ }).Count -gt 0) { [void]$reasons.Add('bekleyen dosya değişikliği') }
    return @($reasons)
}

function Get-LtStartupEnabledCount {
    try { return @(Get-LtStartupItems | Where-Object { $_.Enabled }).Count } catch { return $null }
}

function Get-LtHealthFacts {
    <#
      Salt okunur bilgi toplama. Her alan ayri try/catch: okunamayan alan $null olur
      ve rapor bunu "okunamadı" olarak gosterir (yanlis "sorun yok" demez).
    #>
    param([Parameter(Mandatory)]$Context)
    $f = @{
        ProblemDevices = $null; Gpus = $null; Displays = $null; Memory = $null; SystemDisk = $null
        Events = $null; PendingReboot = @(Get-LtPendingRebootReasons); WindowsUpdate = $null; Network = $null
        Gaming = $null; StartupEnabled = (Get-LtStartupEnabledCount); IsLaptop = [bool](Get-LtProp $Context 'IsLaptop' $false)
        Build = [int](Get-LtProp $Context 'Build' 0)
    }
    # Windows Update (registry + servis: her iki arka uc)
    try {
        $wu = Get-LtServiceInfo -Name 'wuauserv'
        $noAuto = Get-LtRegValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'NoAutoUpdate'
        $f.WindowsUpdate = @{ ServiceDisabled = ($wu.Exists -and $wu.StartType -eq 'Disabled'); PolicyNoAutoUpdate = ($noAuto.Exists -and [long]$noAuto.Data -eq 1) }
    } catch { $f.WindowsUpdate = $null }
    # Oyun ayarlari (registry: her iki arka uc)
    try {
        $gm = Get-LtRegValue 'HKCU\Software\Microsoft\GameBar' 'AutoGameModeEnabled'
        $hist = Get-LtRegValue 'HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'HistoricalCaptureEnabled'
        $plan = $null; try { $plan = Get-LtActivePowerScheme } catch { $null = $_ }
        $f.Gaming = @{
            GameMode = (-not $gm.Exists -or [long]$gm.Data -ne 0)
            BackgroundRecording = ($hist.Exists -and [long]$hist.Data -eq 1)
            ActivePlan = $plan
            Hags = Get-LtProp $Context 'Hags' $null
            Vbs = $null
        }
    } catch { $f.Gaming = $null }

    if ((Get-LtBackend) -eq 'Memory') {
        $m = Get-LtMemoryState
        $h = if ($m.ContainsKey('Health') -and $m.Health) { $m.Health } else { @{} }
        foreach ($k in @('ProblemDevices', 'Gpus', 'Displays', 'Memory', 'SystemDisk', 'Events', 'Network')) {
            if ($h.ContainsKey($k)) { $f[$k] = $h[$k] }
        }
        if ($f.Gaming -and $h.ContainsKey('Vbs')) { $f.Gaming.Vbs = $h.Vbs }
        return $f
    }

    try {
        $f.ProblemDevices = @(Get-CimInstance Win32_PnPEntity -Filter 'ConfigManagerErrorCode <> 0' -ErrorAction Stop | ForEach-Object {
            @{ Name = [string]$_.Name; Class = [string]$_.PNPClass; Code = [int]$_.ConfigManagerErrorCode }
        })
    } catch { $f.ProblemDevices = $null }
    try {
        $f.Gpus = @(Get-CimInstance Win32_VideoController -ErrorAction Stop | Where-Object { [string]$_.PNPDeviceID -like 'PCI\*' } | ForEach-Object {
            $vendor = 'Other'
            if ($_.PNPDeviceID -match 'VEN_10DE') { $vendor = 'NVIDIA' } elseif ($_.PNPDeviceID -match 'VEN_1002') { $vendor = 'AMD' } elseif ($_.PNPDeviceID -match 'VEN_8086') { $vendor = 'Intel' }
            $date = $null; try { if ($_.DriverDate) { $date = [datetime]$_.DriverDate } } catch { $null = $_ }
            @{ Name = [string]$_.Name; Vendor = $vendor; Inf = [string]$_.InfFilename; DriverVersion = [string]$_.DriverVersion; DriverDate = $date }
        })
    } catch { $f.Gpus = $null }
    try {
        if (-not ('LivnTools.DisplayInfo' -as [type])) { Add-Type -TypeDefinition $script:LtDisplaySource -Language CSharp -ErrorAction Stop }
        $f.Displays = @([LivnTools.DisplayInfo]::Read() | ForEach-Object { @{ Name = $_.Name; Width = $_.Width; Height = $_.Height; Current = $_.Current; Max = $_.Max } })
    } catch { $f.Displays = $null }
    try {
        $mods = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction Stop)
        $f.Memory = @{ Modules = @($mods | ForEach-Object { @{ CapacityGB = [math]::Round([double]$_.Capacity / 1GB); Speed = [int]$_.Speed; Configured = [int]$_.ConfiguredClockSpeed; Type = [int]$_.SMBIOSMemoryType } }) }
    } catch { $f.Memory = $null }
    try { $f.SystemDisk = Get-LtSystemDiskFacts } catch { $f.SystemDisk = $null }
    try { $f.Events = Get-LtStabilityEventCounts -Days 14 } catch { $f.Events = $null }
    try {
        $f.Network = @{ Adapters = @(Get-NetAdapter -Physical -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' } | ForEach-Object {
            $wifi = ([string]$_.PhysicalMediaType -match '802\.11') -or ([int]$_.NdisPhysicalMedium -eq 9)
            @{ Name = [string]$_.Name; Description = [string]$_.InterfaceDescription; Wifi = $wifi; LinkSpeedBps = [long]$_.ReceiveLinkSpeed }
        }) }
    } catch { $f.Network = $null }
    try {
        $dg = Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName Win32_DeviceGuard -ErrorAction Stop
        if ($f.Gaming) { $f.Gaming.Vbs = @{ Running = ([int]$dg.VirtualizationBasedSecurityStatus -eq 2); Hvci = (@($dg.SecurityServicesRunning) -contains 2) } }
    } catch { $null = $_ }
    return $f
}

function Get-LtSystemDiskFacts {
    <# Sistem surucusunun bulundugu fiziksel disk: tur, saglik, bos alan, TRIM, sicaklik/asinma (varsa). #>
    $letter = ([string]$env:SystemDrive).TrimEnd(':')
    $drive = New-Object System.IO.DriveInfo ($letter + ':')
    $out = @{ Letter = $letter; FreeBytes = [long]$drive.AvailableFreeSpace; SizeBytes = [long]$drive.TotalSize; MediaType = 'Unknown'; Health = 'Unknown'; Trim = $null; TemperatureC = $null; WearPercent = $null }
    try {
        $num = (Get-Partition -DriveLetter $letter -ErrorAction Stop | Select-Object -First 1).DiskNumber
        $pd = Get-PhysicalDisk -ErrorAction Stop | Where-Object { [string]$_.DeviceId -eq [string]$num } | Select-Object -First 1
        if ($pd) {
            $out.MediaType = [string]$pd.MediaType
            $out.Health = [string]$pd.HealthStatus
            try {
                $rc = $pd | Get-StorageReliabilityCounter -ErrorAction Stop
                if ($rc.Temperature) { $out.TemperatureC = [int]$rc.Temperature }
                if ($null -ne $rc.Wear) { $out.WearPercent = [int]$rc.Wear }
            } catch { $null = $_ }
        }
    } catch { $null = $_ }
    try {
        $r = Invoke-LtNative -FilePath "$env:SystemRoot\System32\fsutil.exe" -Arguments @('behavior', 'query', 'DisableDeleteNotify') -TimeoutSec 30
        $m = [regex]::Match([string]$r.StdOut, 'NTFS\s+DisableDeleteNotify\s*=\s*(\d)')
        if ($m.Success) { $out.Trim = ($m.Groups[1].Value -eq '0') }
    } catch { $null = $_ }
    return $out
}

function Get-LtStabilityEventCounts {
    <# Son N gunde: WHEA donanim hatasi, beklenmedik kapanma (Kernel-Power 41), mavi ekran (BugCheck 1001). #>
    param([int]$Days = 14)
    $since = (Get-Date).AddDays(-$Days)
    $count = {
        param($filter)
        try { return @(Get-WinEvent -FilterHashtable $filter -MaxEvents 500 -ErrorAction Stop) }
        catch { if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') { return @() } throw }
    }
    $whea = & $count @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger'; StartTime = $since }
    $kp = & $count @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41; StartTime = $since }
    $bc = & $count @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; Id = 1001; StartTime = $since }
    $last = $null
    if (@($bc).Count -gt 0) { $last = (@($bc) | Sort-Object TimeCreated -Descending | Select-Object -First 1).TimeCreated }
    return @{ Days = $Days; Whea = @($whea).Count; UnexpectedShutdown = @($kp).Count; BugCheck = @($bc).Count; LastBugCheck = $last }
}

# ---------------------------------------------------------------------------
# Degerlendirme (saf islev)
# ---------------------------------------------------------------------------
function New-LtHealthCheck {
    param([string]$Id, [string]$Area, [string]$Title, [ValidateSet('Ok', 'Info', 'Warning', 'Problem', 'Unknown')][string]$Status,
          [string]$Finding, [string]$Advice = '', [string[]]$Links = @(), [string]$Page = '', [string[]]$Tweaks = @())
    [pscustomobject]@{ Id = $Id; Area = $Area; Title = $Title; Status = $Status; Finding = $Finding; Advice = $Advice; Links = @($Links); Page = $Page; Tweaks = @($Tweaks) }
}

function Get-LtHealthReport {
    <# Donus: kontrol listesi (Problem > Warning > Info > Unknown > Ok sirasinda). #>
    param([Parameter(Mandatory)]$Facts)
    $checks = New-Object System.Collections.ArrayList
    $add = { param($c) [void]$checks.Add($c) }

    # 1. Surucusu eksik/hatali aygitlar
    $pd = $Facts.ProblemDevices
    if ($null -eq $pd) { & $add (New-LtHealthCheck 'drivers' 'Sürücüler' 'Aygıt sürücüleri' Unknown 'Aygıt durumu okunamadı.' '' @('device-manager')) }
    else {
        $real = @($pd | Where-Object { [int]$_.Code -ne 22 })
        $disabled = @($pd | Where-Object { [int]$_.Code -eq 22 })
        if ($real.Count -gt 0) {
            $list = (@($real | Select-Object -First 5 | ForEach-Object { $t = $script:LtProblemCodeText[[int]$_.Code]; if (-not $t) { $t = "kod $($_.Code)" }; "$($_.Name) ($t)" }) -join '; ')
            if ($real.Count -gt 5) { $list += "; +$($real.Count - 5) aygıt" }
            $missing = @($real | Where-Object { [int]$_.Code -eq 28 }).Count
            $adv = if ($missing -gt 0) { 'Önce Windows Update > İsteğe bağlı güncellemeler altındaki sürücüleri kurun; yoksa anakart/dizüstü üreticisinin destek sayfasından indirin.' } else { 'Aygıt Yöneticisi''nde aygıtın özelliklerinden hata ayrıntısına bakın; sürücüyü yeniden kurmak çoğu zaman çözer.' }
            & $add (New-LtHealthCheck 'drivers' 'Sürücüler' 'Aygıt sürücüleri' Problem "$($real.Count) aygıtta sorun: $list" $adv @('optional-drivers', 'device-manager'))
        } elseif ($disabled.Count -gt 0) {
            & $add (New-LtHealthCheck 'drivers' 'Sürücüler' 'Aygıt sürücüleri' Info "Sürücü sorunu yok; $($disabled.Count) aygıt elle devre dışı bırakılmış." 'Bilerek kapattıysanız işlem gerekmez.' @('device-manager'))
        } else {
            & $add (New-LtHealthCheck 'drivers' 'Sürücüler' 'Aygıt sürücüleri' Ok 'Tüm aygıtlar sürücüsüyle çalışıyor.')
        }
    }

    # 2. Ekran karti surucusu
    $gpus = $Facts.Gpus
    if ($null -eq $gpus) { & $add (New-LtHealthCheck 'gpu-driver' 'Sürücüler' 'Ekran kartı sürücüsü' Unknown 'Ekran kartı bilgisi okunamadı.') }
    elseif (@($gpus).Count -eq 0) { & $add (New-LtHealthCheck 'gpu-driver' 'Sürücüler' 'Ekran kartı sürücüsü' Info 'PCI ekran kartı algılanmadı (sanal makine veya farklı veri yolu olabilir).') }
    else {
        $basic = @($gpus | Where-Object { [string]$_.Inf -ieq 'display.inf' })
        $vendorLink = { param($v) switch ($v) { 'NVIDIA' { 'driver-nvidia' } 'AMD' { 'driver-amd' } 'Intel' { 'driver-intel' } default { 'optional-drivers' } } }
        if ($basic.Count -gt 0) {
            $links = @($basic | ForEach-Object { & $vendorLink $_.Vendor } | Select-Object -Unique)
            & $add (New-LtHealthCheck 'gpu-driver' 'Sürücüler' 'Ekran kartı sürücüsü' Problem ("Microsoft temel görüntü sürücüsüyle çalışıyor: " + (@($basic | ForEach-Object { $_.Name }) -join ', ')) 'Üreticinin güncel sürücüsünü kurun. Temel sürücüyle oyun performansı, yüksek yenileme hızı ve HAGS çalışmaz.' $links)
        } else {
            $old = @($gpus | Where-Object { $_.DriverDate -and ([datetime]$_.DriverDate) -lt (Get-Date).AddMonths(-18) })
            if ($old.Count -gt 0) {
                $links = @($old | ForEach-Object { & $vendorLink $_.Vendor } | Select-Object -Unique)
                & $add (New-LtHealthCheck 'gpu-driver' 'Sürücüler' 'Ekran kartı sürücüsü' Info ("Sürücü 18 aydan eski: " + (@($old | ForEach-Object { "$($_.Name) ($(([datetime]$_.DriverDate).ToString('yyyy-MM-dd')))" }) -join ', ')) 'Yeni oyunlar için üreticinin güncel sürücüsü önerilir. Sorunsuz çalışıyorsa güncelleme zorunlu değildir.' $links)
            } else {
                & $add (New-LtHealthCheck 'gpu-driver' 'Sürücüler' 'Ekran kartı sürücüsü' Ok ('Üretici sürücüsü yüklü: ' + (@($gpus | ForEach-Object { $_.Name }) -join ', ')))
            }
        }
    }

    # 3. Ekran yenileme hizi
    $disp = $Facts.Displays
    if ($null -eq $disp) { & $add (New-LtHealthCheck 'refresh' 'Ekran' 'Yenileme hızı' Unknown 'Ekran modları okunamadı.' '' @('display-advanced')) }
    elseif (@($disp).Count -eq 0) { & $add (New-LtHealthCheck 'refresh' 'Ekran' 'Yenileme hızı' Unknown 'Masaüstüne bağlı ekran bulunamadı.') }
    else {
        $low = @($disp | Where-Object { [int]$_.Max -gt ([int]$_.Current + 1) })
        if ($low.Count -gt 0) {
            $txt = (@($low | ForEach-Object { "$($_.Name) $($_.Width)×$($_.Height): $($_.Current) Hz (desteklenen en yüksek $($_.Max) Hz)" }) -join '; ')
            & $add (New-LtHealthCheck 'refresh' 'Ekran' 'Yenileme hızı' Warning $txt 'Ayarlar > Ekran > Gelişmiş ekran ayarları''ndan yenileme hızını yükseltin. Kablo/port (HDMI sürümü, DisplayPort) en yüksek hızı sınırlayabilir.' @('display-advanced'))
        } else {
            & $add (New-LtHealthCheck 'refresh' 'Ekran' 'Yenileme hızı' Ok ((@($disp | ForEach-Object { "$($_.Name): $($_.Current) Hz" }) -join '; ') + ' — desteklenen en yüksek değerde.'))
        }
    }

    # 4. Bellek
    $mem = $Facts.Memory
    if ($null -eq $mem -or @($mem.Modules).Count -eq 0) { & $add (New-LtHealthCheck 'ram' 'Bellek' 'RAM hızı ve kanal' Unknown 'Bellek modülleri okunamadı.') }
    else {
        $mods = @($mem.Modules)
        $cfg = [int](@($mods | ForEach-Object { [int]$_.Configured } | Measure-Object -Minimum).Minimum)
        $rated = [int](@($mods | ForEach-Object { [int]$_.Speed } | Measure-Object -Maximum).Maximum)
        $type = switch ([int]$mods[0].Type) { 26 { 'DDR4' } 34 { 'DDR5' } 24 { 'DDR3' } default { 'RAM' } }
        $total = [int](@($mods | ForEach-Object { [int]$_.CapacityGB } | Measure-Object -Sum).Sum)
        $finding = "$total GB $type, $($mods.Count) modül, çalışma hızı $cfg MT/s"
        $notes = New-Object System.Collections.ArrayList
        $status = 'Ok'
        if ($cfg -gt 0 -and $rated -gt 0 -and $cfg -lt [int]($rated * 0.95)) {
            $status = 'Warning'; [void]$notes.Add("Modüller $rated MT/s bildiriyor ama $cfg MT/s'de çalışıyor.")
        }
        if (($type -eq 'DDR4' -and $cfg -gt 0 -and $cfg -le 2666) -or ($type -eq 'DDR5' -and $cfg -gt 0 -and $cfg -le 4800)) {
            if ($status -eq 'Ok') { $status = 'Info' }
            [void]$notes.Add('Bu, standart (JEDEC) temel hızdır. Bellek kitinizin etiketinde daha yüksek hız yazıyorsa BIOS''ta XMP/EXPO profilini açın ve ardından kararlılığı test edin.')
        }
        if ($mods.Count -eq 1 -and -not $Facts.IsLaptop) {
            if ($status -eq 'Ok') { $status = 'Info' }
            [void]$notes.Add('Tek modül tek kanal çalışır; çift kanal için anakart kılavuzundaki yuvalara iki modül önerilir (özellikle dahili grafikte belirgin).')
        }
        & $add (New-LtHealthCheck 'ram' 'Bellek' 'RAM hızı ve kanal' $status $finding ($notes -join ' '))
    }

    # 5. Sistem diski
    $sd = $Facts.SystemDisk
    if ($null -eq $sd) { & $add (New-LtHealthCheck 'disk' 'Depolama' 'Sistem diski' Unknown 'Disk bilgisi okunamadı.') }
    else {
        $status = 'Ok'; $notes = New-Object System.Collections.ArrayList
        $free = [long]$sd.FreeBytes; $size = [long]$sd.SizeBytes
        $pct = if ($size -gt 0) { [math]::Round(100.0 * $free / $size) } else { 0 }
        $finding = "$($sd.Letter): $(Format-LtBytes $free) boş (%$pct), tür: $(if ($sd.MediaType -and $sd.MediaType -ne 'Unspecified') { $sd.MediaType } else { 'bilinmiyor' }), sağlık: $($sd.Health)"
        $rank = @{ Ok = 0; Info = 1; Warning = 2; Problem = 3 }
        $st = @{ V = 'Ok' }
        $raise = { param($s) if ($rank[$s] -gt $rank[$st.V]) { $st.V = $s } }
        if ($sd.Health -and $sd.Health -notin @('Healthy', 'Unknown')) { & $raise 'Problem'; [void]$notes.Add('Disk sağlığı kötü bildiriliyor: verilerinizi hemen yedekleyin.') }
        if ($free -lt 5GB) { & $raise 'Problem'; [void]$notes.Add('Boş alan kritik: güncellemeler ve oyun yamaları başarısız olabilir.') }
        elseif ($free -lt 20GB -or $pct -lt 10) { & $raise 'Warning'; [void]$notes.Add('Boş alan az: Hızlı/Gelişmiş Temizlik veya Depolama ayarlarını kullanın.') }
        if ($sd.MediaType -eq 'HDD') { & $raise 'Info'; [void]$notes.Add('Windows mekanik diskte: SSD açılış ve oyun yükleme sürelerini belirgin kısaltır.') }
        if ($sd.MediaType -eq 'SSD' -and $false -eq $sd.Trim) { & $raise 'Warning'; [void]$notes.Add('TRIM kapalı: yönetici komut isteminde "fsutil behavior set DisableDeleteNotify 0" ile açın.') }
        if ($null -ne $sd.TemperatureC -and [int]$sd.TemperatureC -ge 70) { & $raise 'Warning'; [void]$notes.Add("Disk sıcaklığı yüksek ($($sd.TemperatureC) °C): hava akışını kontrol edin.") }
        if ($null -ne $sd.WearPercent -and [int]$sd.WearPercent -ge 80) { & $raise 'Warning'; [void]$notes.Add("SSD ömrünün %$($sd.WearPercent)'i kullanılmış: yedekleme ve değişim planlayın.") }
        $status = $st.V
        $links = if ($free -lt 20GB -or $pct -lt 10) { @('storage') } else { @() }
        $page = if ($free -lt 20GB -or $pct -lt 10) { 'QuickClean' } else { '' }
        & $add (New-LtHealthCheck 'disk' 'Depolama' 'Sistem diski' $status $finding ($notes -join ' ') $links $page)
    }

    # 6. Kararlilik olaylari
    $ev = $Facts.Events
    if ($null -eq $ev) { & $add (New-LtHealthCheck 'stability' 'Kararlılık' 'Çökme ve donanım hataları' Unknown 'Olay günlüğü okunamadı.' '' @('reliability')) }
    else {
        $parts = New-Object System.Collections.ArrayList; $notes = New-Object System.Collections.ArrayList
        $status = 'Ok'
        if ([int]$ev.Whea -gt 0) { $status = 'Problem'; [void]$parts.Add("$($ev.Whea) donanım hatası (WHEA)"); [void]$notes.Add('WHEA kayıtları genellikle kararsız hız aşırtma/XMP, aşırı ısınma veya arızalı donanımdan gelir; hız aşırtmayı geri alıp test edin.') }
        if ([int]$ev.BugCheck -gt 0) { $status = 'Problem'; [void]$parts.Add("$($ev.BugCheck) mavi ekran$(if ($ev.LastBugCheck) { ' (son: ' + ([datetime]$ev.LastBugCheck).ToString('yyyy-MM-dd HH:mm') + ')' })"); [void]$notes.Add('Güvenilirlik İzleyicisi''nde hata kodunu ve ilgili sürücüyü görün.') }
        if ([int]$ev.UnexpectedShutdown -gt 0) { if ($status -eq 'Ok') { $status = 'Warning' }; [void]$parts.Add("$($ev.UnexpectedShutdown) beklenmedik kapanma"); [void]$notes.Add('Elektrik kesintisi, güç düğmesine uzun basma, güç kaynağı veya donma kaynaklı olabilir.') }
        $finding = if ($parts.Count -gt 0) { "Son $($ev.Days) günde: " + ($parts -join ', ') + '.' } else { "Son $($ev.Days) günde mavi ekran, beklenmedik kapanma veya donanım hatası kaydı yok." }
        & $add (New-LtHealthCheck 'stability' 'Kararlılık' 'Çökme ve donanım hataları' $status $finding ($notes -join ' ') $(if ($status -ne 'Ok') { @('reliability') } else { @() }))
    }

    # 7. Bekleyen yeniden baslatma
    $pr = @($Facts.PendingReboot)
    if ($pr.Count -gt 0) { & $add (New-LtHealthCheck 'reboot' 'Kararlılık' 'Bekleyen yeniden başlatma' Warning ('Yeniden başlatma bekleniyor: ' + ($pr -join ', ') + '.') 'Ayar uygulamadan ve sürücü kurmadan önce bilgisayarı yeniden başlatın.') }
    else { & $add (New-LtHealthCheck 'reboot' 'Kararlılık' 'Bekleyen yeniden başlatma' Ok 'Bekleyen yeniden başlatma yok.') }

    # 8. Windows Update
    $wu = $Facts.WindowsUpdate
    if ($null -eq $wu) { & $add (New-LtHealthCheck 'windows-update' 'Kararlılık' 'Windows Update' Unknown 'Windows Update durumu okunamadı.') }
    elseif ($wu.ServiceDisabled -or $wu.PolicyNoAutoUpdate) {
        $why = @(); if ($wu.ServiceDisabled) { $why += 'servis devre dışı' }; if ($wu.PolicyNoAutoUpdate) { $why += 'otomatik güncelleme ilkeyle kapalı' }
        & $add (New-LtHealthCheck 'windows-update' 'Kararlılık' 'Windows Update' Warning ('Güncellemeler kapalı: ' + ($why -join ', ') + '.') 'Güvenlik yamaları ve sürücü düzeltmeleri gelmez. Ertelemek için Livn''in güncelleme erteleme seçeneklerini kullanın; tamamen kapatmayın.' @('windows-update'))
    } else { & $add (New-LtHealthCheck 'windows-update' 'Kararlılık' 'Windows Update' Ok 'Windows Update çalışıyor.') }

    # 9. Ag baglantisi
    $net = $Facts.Network
    if ($null -eq $net) { & $add (New-LtHealthCheck 'network' 'Ağ' 'Bağlantı türü' Unknown 'Ağ bağdaştırıcıları okunamadı.') }
    else {
        $ad = @($net.Adapters)
        if ($ad.Count -eq 0) { & $add (New-LtHealthCheck 'network' 'Ağ' 'Bağlantı türü' Problem 'Bağlı fiziksel ağ bağdaştırıcısı yok.' 'Kabloyu/Wi-Fi bağlantısını ve ağ sürücüsünü kontrol edin.' @('device-manager')) }
        else {
            $wired = @($ad | Where-Object { -not $_.Wifi })
            $desc = (@($ad | ForEach-Object { "$($_.Name) ($(if ($_.Wifi) { 'Wi-Fi' } else { 'kablolu' }), $([math]::Round([double]$_.LinkSpeedBps / 1e6)) Mb/s)" }) -join '; ')
            if ($wired.Count -eq 0) {
                & $add (New-LtHealthCheck 'network' 'Ağ' 'Bağlantı türü' Info $desc 'Oyunlarda Wi-Fi gecikme dalgalanması (jitter) ve paket kaybına daha açıktır. Mümkünse kablo kullanın; Ağ sayfasındaki gecikme ölçümüyle farkı görün.' @() 'Network')
            } elseif (@($wired | Where-Object { [long]$_.LinkSpeedBps -gt 0 -and [long]$_.LinkSpeedBps -lt 1000000000 }).Count -gt 0) {
                & $add (New-LtHealthCheck 'network' 'Ağ' 'Bağlantı türü' Info $desc 'Kablolu bağlantı 1 Gb/s altında: kablo (Cat5e veya üstü), port veya modem bağlantı hızını kontrol edin. Ping''i değil, indirme hızını sınırlar.' @() 'Network')
            } else {
                & $add (New-LtHealthCheck 'network' 'Ağ' 'Bağlantı türü' Ok $desc)
            }
        }
    }

    # 10. Oyun ayarlari
    $g = $Facts.Gaming
    if ($null -eq $g) { & $add (New-LtHealthCheck 'gaming' 'Oyun' 'Oyun ayarları' Unknown 'Oyun ayarları okunamadı.') }
    else {
        $parts = New-Object System.Collections.ArrayList; $notes = New-Object System.Collections.ArrayList
        $status = 'Ok'; $tweaks = New-Object System.Collections.ArrayList; $links = New-Object System.Collections.ArrayList
        [void]$parts.Add("Oyun Modu $(if ($g.GameMode) { 'açık' } else { 'kapalı' })")
        if (-not $g.GameMode) { $status = 'Info'; [void]$notes.Add('Oyun Modu kapalı: açmak arka plan güncellemelerinin oyun sırasında başlamasını sınırlar.'); [void]$tweaks.Add('game.mode') }
        if ($g.BackgroundRecording) { $status = 'Warning'; [void]$parts.Add('arka plan kaydı açık'); [void]$notes.Add('"Olanları kaydet" sürekli video kodlar ve performansı düşürebilir; kullanmıyorsanız kapatın.'); [void]$tweaks.Add('game.bgrecord-off') }
        $plan = [string]$g.ActivePlan
        if ($plan -eq 'a1841308-3541-4fab-bc81-f71556f20b4a') { $status = 'Warning'; [void]$parts.Add('Güç Tasarrufu planı etkin'); [void]$notes.Add('Güç Tasarrufu planı işlemci hızını sınırlar.'); [void]$links.Add('power') }
        $h = $g.Hags
        if ($h) {
            $hs = Get-LtProp $h 'Supported' $null; $he = Get-LtProp $h 'Enabled' $null
            if ($true -eq $hs) { [void]$parts.Add("HAGS $(if ($true -eq $he) { 'açık' } elseif ($false -eq $he) { 'kapalı' } else { 'durumu okunamadı' })") }
        }
        $vbs = $g.Vbs
        if ($vbs -and $vbs.Running) {
            if ($status -eq 'Ok') { $status = 'Info' }
            [void]$parts.Add("VBS açık$(if ($vbs.Hvci) { ' (Bellek bütünlüğü/HVCI dahil)' })")
            [void]$notes.Add('VBS/HVCI bir güvenlik özelliğidir; bazı oyunlarda performans maliyeti olabilir. Livn bunu hazır seçimlerde kapatmaz; kararı Güvenlik sayfasında, riskleri okuyarak verin.')
        }
        & $add (New-LtHealthCheck 'gaming' 'Oyun' 'Oyun ayarları' $status (($parts -join ', ') + '.') ($notes -join ' ') @($links) '' @($tweaks))
    }

    # 11. Baslangic uygulamalari
    $su = $Facts.StartupEnabled
    if ($null -ne $su) {
        if ([int]$su -gt 8) { & $add (New-LtHealthCheck 'startup' 'Performans' 'Başlangıç uygulamaları' Info "$su uygulama Windows açılışında başlıyor." 'Gerekmeyenleri Başlangıç sayfasından kapatın; açılış süresi ve arka plan yükü azalır.' @() 'Startup') }
        else { & $add (New-LtHealthCheck 'startup' 'Performans' 'Başlangıç uygulamaları' Ok "$su uygulama açılışta başlıyor." '' @() 'Startup') }
    }

    $order = @{ Problem = 0; Warning = 1; Info = 2; Unknown = 3; Ok = 4 }
    return @($checks | Sort-Object @{ Expression = { $order[$_.Status] } }, @{ Expression = { $_.Area } })
}

function Get-LtHealthSummary {
    param([Parameter(Mandatory)][object[]]$Checks)
    $c = @{ Problem = 0; Warning = 0; Info = 0; Unknown = 0; Ok = 0 }
    foreach ($x in $Checks) { $c[[string]$x.Status]++ }
    $head = if ($c.Problem -gt 0) { "$($c.Problem) sorun" } elseif ($c.Warning -gt 0) { "$($c.Warning) uyarı" } else { 'Ciddi sorun bulunmadı' }
    return "$head · $($c.Warning) uyarı · $($c.Info) bilgi · $($c.Ok) tamam$(if ($c.Unknown) { " · $($c.Unknown) okunamadı" })"
}

function Format-LtHealthReportText {
    <# Paylasilabilir duz metin rapor (kisisel veri: bilgisayar/kullanici adi YAZILMAZ). #>
    param([Parameter(Mandatory)][object[]]$Checks, $Context = $null)
    $names = @{ Problem = 'SORUN'; Warning = 'UYARI'; Info = 'BİLGİ'; Unknown = 'OKUNAMADI'; Ok = 'TAMAM' }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("Livn Tools $(Get-LtVersion) — Sistem Kontrolü ($((Get-Date).ToString('yyyy-MM-dd HH:mm')))")
    if ($Context) {
        $os = try { Get-LtOsLabel $Context } catch { '' }
        if ($os) { [void]$sb.AppendLine("Sistem: $os") }
        $cpu = [string](Get-LtProp (Get-LtProp $Context 'Cpu' @{}) 'Name' '')
        if ($cpu) { [void]$sb.AppendLine("İşlemci: $cpu · RAM: $(Get-LtProp $Context 'RamGB' '?') GB") }
    }
    [void]$sb.AppendLine((Get-LtHealthSummary -Checks $Checks))
    [void]$sb.AppendLine('')
    foreach ($c in $Checks) {
        [void]$sb.AppendLine("[$($names[[string]$c.Status])] $($c.Title): $($c.Finding)")
        if ($c.Advice) { [void]$sb.AppendLine("    Öneri: $($c.Advice)") }
    }
    return $sb.ToString()
}

function Get-LtHealthLinks { return $script:LtHealthLinks }

function Open-LtHealthLink {
    <# Yalniz $script:LtHealthLinks icindeki sabit hedefler; kullanicinin kabugunda acilir. #>
    param([Parameter(Mandatory)][string]$Id)
    if (-not $script:LtHealthLinks.Contains($Id)) { throw "Bilinmeyen bağlantı: $Id" }
    Assert-LtLiveSystem -Operation "Windows ekranı aç: $Id"
    $l = $script:LtHealthLinks[$Id]
    if ($l.ContainsKey('Uri')) { Start-Process -FilePath "$env:SystemRoot\explorer.exe" -ArgumentList ('"' + $l.Uri + '"') -ErrorAction Stop; return }
    if ($l.Args) { Start-Process -FilePath $l.File -ArgumentList $l.Args -ErrorAction Stop } else { Start-Process -FilePath $l.File -ErrorAction Stop }
}
