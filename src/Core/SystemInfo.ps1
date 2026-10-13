# Livn Tools - Core/SystemInfo.ps1
# Sistem baglami (surum, surum turu, donanim), yerel API yardimcisi,
# geri yukleme noktasi (dogrulamali) ve bellek listesi komutlari.

Set-StrictMode -Version 2.0

$script:LtNativeSource = @'
using System;
using System.Runtime.InteropServices;

namespace LivnTools
{
    public static class NativeInfo
    {
        [StructLayout(LayoutKind.Sequential)]
        private struct FILETIME { public uint Low; public uint High; }

        [StructLayout(LayoutKind.Sequential)]
        private struct MEMORYSTATUSEX
        {
            public uint dwLength; public uint dwMemoryLoad;
            public ulong ullTotalPhys; public ulong ullAvailPhys;
            public ulong ullTotalPageFile; public ulong ullAvailPageFile;
            public ulong ullTotalVirtual; public ulong ullAvailVirtual; public ulong ullAvailExtendedVirtual;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct LUID { public uint LowPart; public int HighPart; }

        [StructLayout(LayoutKind.Sequential)]
        private struct TOKEN_PRIVILEGES { public int PrivilegeCount; public LUID Luid; public int Attributes; }

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetSystemTimes(out FILETIME idle, out FILETIME kernel, out FILETIME user);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX buffer);
        [DllImport("kernel32.dll")]
        private static extern ulong GetTickCount64();
        [DllImport("kernel32.dll")]
        private static extern IntPtr GetCurrentProcess();
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool CloseHandle(IntPtr h);
        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);
        [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern bool LookupPrivilegeValue(string system, string name, out LUID luid);
        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern bool AdjustTokenPrivileges(IntPtr token, bool disableAll, ref TOKEN_PRIVILEGES state, int len, IntPtr prev, IntPtr retLen);
        [DllImport("ntdll.dll")]
        private static extern int NtSetSystemInformation(int infoClass, ref int info, int length);

        [StructLayout(LayoutKind.Sequential)]
        private struct D3DKMT_ADAPTERINFO { public uint hAdapter; public LUID AdapterLuid; public uint NumOfSources; public int bPrecisePresentRegionsPreferred; }
        [StructLayout(LayoutKind.Sequential)]
        private struct D3DKMT_ENUMADAPTERS2 { public uint NumAdapters; public IntPtr pAdapters; }
        [StructLayout(LayoutKind.Sequential)]
        private struct D3DKMT_QUERYADAPTERINFO { public uint hAdapter; public int Type; public IntPtr pPrivateDriverData; public uint PrivateDriverDataSize; }
        [StructLayout(LayoutKind.Sequential)]
        private struct D3DKMT_CLOSEADAPTER { public uint hAdapter; }
        [DllImport("gdi32.dll")]
        private static extern int D3DKMTEnumAdapters2(ref D3DKMT_ENUMADAPTERS2 data);
        [DllImport("gdi32.dll")]
        private static extern int D3DKMTQueryAdapterInfo(ref D3DKMT_QUERYADAPTERINFO data);
        [DllImport("gdi32.dll")]
        private static extern int D3DKMTCloseAdapter(ref D3DKMT_CLOSEADAPTER data);

        private static ulong lastIdle, lastKernel, lastUser;

        private static ulong ToU64(FILETIME f) { return ((ulong)f.High << 32) | f.Low; }

        /// <summary>Iki cagri arasindaki toplam CPU kullanimi (yuzde). Ilk cagri 0 dondurur.</summary>
        public static double CpuPercent()
        {
            FILETIME i, k, u;
            if (!GetSystemTimes(out i, out k, out u)) return -1;
            ulong idle = ToU64(i), kernel = ToU64(k), user = ToU64(u);
            ulong dIdle = idle - lastIdle, dKernel = kernel - lastKernel, dUser = user - lastUser;
            bool first = lastKernel == 0;
            lastIdle = idle; lastKernel = kernel; lastUser = user;
            ulong total = dKernel + dUser;   // kernel suresi idle'i da icerir
            if (first || total == 0) return 0;
            return Math.Max(0.0, Math.Min(100.0, (double)(total - dIdle) * 100.0 / total));
        }

        public static ulong[] Memory()
        {
            MEMORYSTATUSEX m = new MEMORYSTATUSEX();
            m.dwLength = (uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX));
            if (!GlobalMemoryStatusEx(ref m)) return new ulong[] { 0, 0 };
            return new ulong[] { m.ullTotalPhys, m.ullAvailPhys };
        }

        public static ulong UptimeMs() { return GetTickCount64(); }

        /// <summary>Surec belirtecinde ayricaligi etkinlestirir. 0 = basarili, aksi halde Win32 hata kodu.</summary>
        public static int EnablePrivilege(string name)
        {
            IntPtr token;
            if (!OpenProcessToken(GetCurrentProcess(), 0x0020 | 0x0008, out token)) return Marshal.GetLastWin32Error();
            try
            {
                LUID luid;
                if (!LookupPrivilegeValue(null, name, out luid)) return Marshal.GetLastWin32Error();
                TOKEN_PRIVILEGES tp = new TOKEN_PRIVILEGES();
                tp.PrivilegeCount = 1; tp.Luid = luid; tp.Attributes = 0x00000002;
                if (!AdjustTokenPrivileges(token, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero)) return Marshal.GetLastWin32Error();
                int err = Marshal.GetLastWin32Error();
                return err == 1300 ? 1300 : 0; // ERROR_NOT_ALL_ASSIGNED
            }
            finally { CloseHandle(token); }
        }

        /// <summary>
        /// Salt okunur: her grafik bagdastiricisi icin D3DKMT_WDDM_2_7_CAPS degeri
        /// (KMTQAITYPE_WDDM_2_7_CAPS = 70). bit0 HwSchSupported, bit1 HwSchEnabled,
        /// bit2 HwSchEnabledByDefault. Sorgu basarisizsa 0xFFFFFFFF.
        /// </summary>
        public static uint[] HagsCaps()
        {
            D3DKMT_ENUMADAPTERS2 e = new D3DKMT_ENUMADAPTERS2();
            int st = D3DKMTEnumAdapters2(ref e);
            if (st != 0) throw new InvalidOperationException(String.Format("D3DKMTEnumAdapters2 NTSTATUS 0x{0:X8}", st));
            if (e.NumAdapters == 0) return new uint[0];
            int size = Marshal.SizeOf(typeof(D3DKMT_ADAPTERINFO));
            IntPtr buf = Marshal.AllocHGlobal(size * (int)e.NumAdapters);
            IntPtr caps = Marshal.AllocHGlobal(4);
            try
            {
                e.pAdapters = buf;
                st = D3DKMTEnumAdapters2(ref e);
                if (st != 0) throw new InvalidOperationException(String.Format("D3DKMTEnumAdapters2 NTSTATUS 0x{0:X8}", st));
                uint[] result = new uint[e.NumAdapters];
                for (int i = 0; i < (int)e.NumAdapters; i++)
                {
                    D3DKMT_ADAPTERINFO info = (D3DKMT_ADAPTERINFO)Marshal.PtrToStructure(IntPtr.Add(buf, i * size), typeof(D3DKMT_ADAPTERINFO));
                    try
                    {
                        Marshal.WriteInt32(caps, 0);
                        D3DKMT_QUERYADAPTERINFO q = new D3DKMT_QUERYADAPTERINFO();
                        q.hAdapter = info.hAdapter; q.Type = 70; q.pPrivateDriverData = caps; q.PrivateDriverDataSize = 4;
                        result[i] = D3DKMTQueryAdapterInfo(ref q) == 0 ? (uint)Marshal.ReadInt32(caps) : 0xFFFFFFFF;
                    }
                    finally
                    {
                        D3DKMT_CLOSEADAPTER c = new D3DKMT_CLOSEADAPTER();
                        c.hAdapter = info.hAdapter;
                        D3DKMTCloseAdapter(ref c);
                    }
                }
                return result;
            }
            finally { Marshal.FreeHGlobal(caps); Marshal.FreeHGlobal(buf); }
        }

        /// <summary>SystemMemoryListInformation (80). Donus: NTSTATUS (0 = basarili).</summary>
        public static int MemoryListCommand(int command)
        {
            int cmd = command;
            return NtSetSystemInformation(80, ref cmd, 4);
        }
    }
}
'@

function Initialize-LtNative {
    if (-not ('LivnTools.NativeInfo' -as [type])) {
        Add-Type -TypeDefinition $script:LtNativeSource -Language CSharp -ErrorAction Stop
    }
}

# ---------------------------------------------------------------------------
# Sistem baglami
# ---------------------------------------------------------------------------
function Get-LtSystemContext {
    <#
      Tweak destek kontrolleri ve dinamik eylemler icin sistem bilgisi.
      Her alan ayri try/catch icindedir: bir bilginin okunamamasi digerlerini engellemez.
    #>
    [CmdletBinding()]
    param([string]$AppRoot = '')
    $ctx = @{
        Build = 0; Ubr = 0; EditionId = ''; ProductName = ''; DisplayVersion = ''; IsServer = $false
        IsWin11 = $false; IsLaptop = $false; IsAdmin = $false
        Cpu = @{ Name = ''; Vendor = 'Other'; Cores = 0; Threads = 0 }
        RamGB = 0; RamMB = 0; Gpus = @(); Nics = @(); MsiDevices = @(); PowerSchemes = @(); AppRoot = $AppRoot
        Hags = @{ Supported = $null; Enabled = $null; Detail = 'Okunmadı' }; ModernStandby = $null
        Errors = @()
    }
    $errs = New-Object System.Collections.ArrayList
    try {
        $cv = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
        $ctx.Build          = [int](Get-LtRegValue $cv 'CurrentBuildNumber').Data
        $ubr = Get-LtRegValue $cv 'UBR'; if ($ubr.Exists) { $ctx.Ubr = [int]$ubr.Data }
        $ctx.EditionId      = [string](Get-LtRegValue $cv 'EditionID').Data
        $ctx.ProductName    = [string](Get-LtRegValue $cv 'ProductName').Data
        $dv = Get-LtRegValue $cv 'DisplayVersion'; if ($dv.Exists) { $ctx.DisplayVersion = [string]$dv.Data }
        $it = Get-LtRegValue $cv 'InstallationType'
        $ctx.IsServer = ($it.Exists -and [string]$it.Data -match 'Server')
        $ctx.IsWin11  = ($ctx.Build -ge 22000 -and -not $ctx.IsServer)
        if ($ctx.IsWin11) { $ctx.ProductName = $ctx.ProductName -replace 'Windows 10', 'Windows 11' }
    } catch { [void]$errs.Add("Sürüm: $($_.Exception.Message)") }

    if ((Get-LtBackend) -eq 'Memory') {
        # Sahte sistem (Initialize-LtMemoryDemo) donanim bilgisi saglar
        $m = Get-LtMemoryState
        if ($m.ContainsKey('DemoContext') -and $m.DemoContext) { foreach ($k in $m.DemoContext.Keys) { $ctx[$k] = $m.DemoContext[$k] } }
        $ctx.PowerSchemes = @(Get-LtPowerSchemes)
        $ctx.Errors = @($errs)
        return $ctx
    }

    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $ctx.IsAdmin = (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { [void]$errs.Add("Yetki: $($_.Exception.Message)") }
    try {
        $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1
        $ctx.Cpu = @{
            Name = ($cpu.Name -replace '\s+', ' ').Trim()
            Vendor = if ($cpu.Manufacturer -match 'AMD') { 'AMD' } elseif ($cpu.Manufacturer -match 'Intel') { 'Intel' } else { 'Other' }
            Cores = [int]$cpu.NumberOfCores; Threads = [int]$cpu.NumberOfLogicalProcessors
        }
    } catch { [void]$errs.Add("CPU: $($_.Exception.Message)") }
    try {
        $bytes = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).TotalPhysicalMemory
        $ctx.RamMB = [long][math]::Floor($bytes / 1MB)
        $ctx.RamGB = [math]::Round($bytes / 1GB)
    } catch { [void]$errs.Add("RAM: $($_.Exception.Message)") }
    try {
        $ctx.IsLaptop = [bool](Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
    } catch { [void]$errs.Add("Pil: $($_.Exception.Message)") }
    try {
        $ctx.Gpus = @(Get-CimInstance Win32_VideoController -ErrorAction Stop |
            Where-Object { $_.PNPDeviceID -like 'PCI\*' } |
            ForEach-Object {
                $vendor = 'Other'
                if ($_.PNPDeviceID -match 'VEN_10DE') { $vendor = 'NVIDIA' }
                elseif ($_.PNPDeviceID -match 'VEN_1002') { $vendor = 'AMD' }
                elseif ($_.PNPDeviceID -match 'VEN_8086') { $vendor = 'Intel' }
                @{ Name = $_.Name; Vendor = $vendor; InstanceId = $_.PNPDeviceID; DriverVersion = $_.DriverVersion }
            })
    } catch { [void]$errs.Add("GPU: $($_.Exception.Message)") }
    try {
        $ctx.Nics = @(Get-NetAdapter -Physical -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' } | ForEach-Object {
            $wifi = ([string]$_.PhysicalMediaType -match '802\.11') -or ([int]$_.NdisPhysicalMedium -eq 9)
            @{ Name = $_.Name; InterfaceGuid = ([string]$_.InterfaceGuid).ToLowerInvariant(); Description = $_.InterfaceDescription; LinkSpeed = [string]$_.LinkSpeed; InstanceId = $_.PnPDeviceID; Wifi = [bool]$wifi }
        })
    } catch { [void]$errs.Add("Ağ: $($_.Exception.Message)") }
    try {
        $dev = @(Get-PnpDevice -PresentOnly -ErrorAction Stop | Where-Object {
            $_.InstanceId -like 'PCI\*' -and (
                $_.Class -eq 'Display' -or $_.Class -eq 'Net' -or
                ($_.Class -eq 'SCSIAdapter' -and ($_.Service -eq 'stornvme' -or [string]$_.FriendlyName -match 'NVM'))
            )
        })
        $ctx.MsiDevices = @($dev | ForEach-Object {
            $cls = switch ($_.Class) { 'Display' { 'GPU' } 'Net' { 'NIC' } default { 'NVMe' } }
            @{ Class = $cls; Name = [string]$_.FriendlyName; InstanceId = $_.InstanceId; InterruptSupport = (Get-LtPciInterruptSupport $_.InstanceId) }
        })
    } catch { [void]$errs.Add("PnP: $($_.Exception.Message)") }
    $ctx.Hags = Get-LtHagsCapability
    $ctx.ModernStandby = Get-LtModernStandby
    try { $ctx.PowerSchemes = @(Get-LtPowerSchemes) } catch { [void]$errs.Add("Güç planı: $($_.Exception.Message)") }
    $ctx.Errors = @($errs)
    return $ctx
}

function Get-LtOsLabel($Ctx) {
    $label = $Ctx.ProductName
    if ($Ctx.DisplayVersion) { $label += " $($Ctx.DisplayVersion)" }
    $label += " (derleme $($Ctx.Build).$($Ctx.Ubr))"
    return $label
}

# ---------------------------------------------------------------------------
# Geri yukleme noktasi — olusturuldugu DOGRULANMADAN basarili sayilmaz
# ---------------------------------------------------------------------------
function New-LtRestorePoint {
    [CmdletBinding()]
    param([string]$Description = "Livn Tools $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
    $id = 'system.restorepoint'
    $title = 'Sistem geri yükleme noktası'
    if ((Get-LtBackend) -eq 'Memory') {
        $m = Get-LtMemoryState
        if (-not $m.ContainsKey('RestorePoints')) { $m.RestorePoints = New-Object System.Collections.ArrayList }
        if ($m.ContainsKey('RestoreThrottled') -and $m.RestoreThrottled) {
            return New-LtResult -Id $id -Title $title -Status Skipped -Message 'Windows son 24 saat içinde oluşturulmuş bir nokta olduğu için yeni nokta oluşturmadı.'
        }
        [void]$m.RestorePoints.Add($Description)
        return New-LtResult -Id $id -Title $title -Status Success -Message "Oluşturuldu ve doğrulandı: $Description"
    }
    try {
        $before = @(Get-CimInstance -Namespace 'root/default' -ClassName SystemRestore -ErrorAction Stop)
    } catch {
        return New-LtResult -Id $id -Title $title -Status NotSupported -Message "Sistem Geri Yükleme bu sistemde kullanılamıyor: $($_.Exception.Message)"
    }
    $start = Get-Date
    try {
        $r = Invoke-CimMethod -Namespace 'root/default' -ClassName SystemRestore -MethodName CreateRestorePoint -Arguments @{
            Description = $Description; RestorePointType = [uint32]12; EventType = [uint32]100
        } -ErrorAction Stop
        $rv = [int]$r.ReturnValue
    } catch {
        return New-LtResult -Id $id -Title $title -Status Failed -Message "Geri yükleme noktası oluşturulamadı: $($_.Exception.Message)"
    }
    $after = @(Get-CimInstance -Namespace 'root/default' -ClassName SystemRestore -ErrorAction SilentlyContinue)
    $mine = $after | Where-Object { $_.Description -eq $Description } | Select-Object -First 1
    if ($rv -eq 0 -and $mine) {
        return New-LtResult -Id $id -Title $title -Status Success -Message "Oluşturuldu ve doğrulandı (sıra no $($mine.SequenceNumber))."
    }
    if ($rv -eq 1058) {
        return New-LtResult -Id $id -Title $title -Status Failed -Message 'Sistem Geri Yükleme hizmeti devre dışı (1058). Sistem Koruması ayarlarını kontrol edin.'
    }
    $last = $before | Sort-Object SequenceNumber | Select-Object -Last 1
    if ($last) {
        $lastTime = [Management.ManagementDateTimeConverter]::ToDateTime($last.CreationTime)
        if (($start - $lastTime).TotalHours -lt 24) {
            return New-LtResult -Id $id -Title $title -Status Skipped -Message ("Windows yeni nokta oluşturmadı: son 24 saatte oluşturulmuş nokta var ({0:g} - '{1}'). Değişiklikler yine de Livn Tools günlüğüyle geri alınabilir." -f $lastTime, $last.Description)
        }
    }
    return New-LtResult -Id $id -Title $title -Status Failed -Message "Geri yükleme noktası doğrulanamadı (dönüş kodu $rv). Sistem Koruması sistem sürücüsünde kapalı olabilir."
}

# ---------------------------------------------------------------------------
# Bellek listesi komutlari (ISLC gerektirmez)
# ---------------------------------------------------------------------------
function Get-LtMemoryListBytes {
    <# Donus: @{ Standby; Modified } bayt (WMI sinifi yerellestirilmez) #>
    if ((Get-LtBackend) -eq 'Memory') { return @{ Standby = [long]0; Modified = [long]0 } }
    $m = Get-CimInstance Win32_PerfRawData_PerfOS_Memory -ErrorAction Stop
    return @{
        Standby  = [long]$m.StandbyCacheNormalPriorityBytes + [long]$m.StandbyCacheReserveBytes + [long]$m.StandbyCacheCoreBytes
        Modified = [long]$m.ModifiedPageListBytes
    }
}

function Invoke-LtMemoryList {
    <# PurgeStandby = 4 (MemoryPurgeStandbyList), FlushModified = 3 (MemoryFlushModifiedList) #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('PurgeStandby','FlushModified')][string]$Command)
    $id = "memory.$($Command.ToLowerInvariant())"
    $title = if ($Command -eq 'PurgeStandby') { 'Bekleme (standby) listesini boşalt' } else { 'Değiştirilmiş (modified) listeyi diske yaz' }
    if ((Get-LtBackend) -eq 'Memory') {
        return New-LtResult -Id $id -Title $title -Status Success -Message 'Bellek arka ucu: komut simüle edildi.'
    }
    try {
        Initialize-LtNative
        # Performans sayaclari bozuk olabilir (lodctr /r gerekir); olcum yoksa islem yine yapilir
        $before = $null
        try { $before = Get-LtMemoryListBytes } catch { Write-LtLog "Bellek listesi boyutu okunamadı (performans sayaçları): $($_.Exception.Message)" 'WARN' }
        $priv = [LivnTools.NativeInfo]::EnablePrivilege('SeProfileSingleProcessPrivilege')
        if ($priv -ne 0) { return New-LtResult -Id $id -Title $title -Status Failed -Message "SeProfileSingleProcessPrivilege etkinleştirilemedi (Win32 hata $priv)." }
        $code = if ($Command -eq 'PurgeStandby') { 4 } else { 3 }
        $st = [LivnTools.NativeInfo]::MemoryListCommand($code)
        if ($st -ne 0) {
            return New-LtResult -Id $id -Title $title -Status Failed -Message ('NtSetSystemInformation başarısız (NTSTATUS 0x{0:X8}).' -f $st)
        }
        Start-Sleep -Milliseconds 300
        $field = if ($Command -eq 'PurgeStandby') { 'Standby' } else { 'Modified' }
        $after = $null
        if ($null -ne $before) { try { $after = Get-LtMemoryListBytes } catch { $null = $_ } }
        if ($null -eq $before -or $null -eq $after) {
            return New-LtResult -Id $id -Title $title -Status Success -Message "Tamamlandı. $field listesinin boyutu ölçülemedi (performans sayaçları okunamıyor)."
        }
        $delta = [long]$before[$field] - [long]$after[$field]
        return New-LtResult -Id $id -Title $title -Status Success -Message ("Tamamlandı. {0} listesi: {1} → {2}" -f $field, (Format-LtBytes $before[$field]), (Format-LtBytes $after[$field])) -BytesFreed ([math]::Max(0, $delta))
    } catch {
        return New-LtResult -Id $id -Title $title -Status Failed -Message $_.Exception.Message
    }
}

function Get-LtPciInterruptSupport {
    <#
      Salt okunur: DEVPKEY_PciDevice_InterruptSupport ({3AB22E31-8264-4B4E-9AF5-A8D2D8E33E62} 14).
      Bit maskesi: 1 = hat tabanli, 2 = MSI, 4 = MSI-X. Okunamazsa $null (destek bilinmiyor).
    #>
    param([string]$InstanceId)
    if ((Get-LtBackend) -eq 'Memory') { return $null }
    try {
        $p = Get-PnpDeviceProperty -InstanceId $InstanceId -KeyName '{3AB22E31-8264-4B4E-9AF5-A8D2D8E33E62} 14' -ErrorAction Stop
        if ($null -eq $p -or $null -eq $p.Data) { return $null }
        return [int]$p.Data
    } catch { return $null }
}

function Get-LtHagsCapability {
    <#
      Salt okunur HAGS yetenek sorgusu (D3DKMT WDDM 2.7 yetenekleri).
      Supported/Enabled: $true / $false / $null (okunamadi). Yazma yapmaz.
    #>
    if ((Get-LtBackend) -eq 'Memory') {
        $m = Get-LtMemoryState
        if ($m.ContainsKey('DemoContext') -and $m.DemoContext -and $m.DemoContext.ContainsKey('Hags')) { return $m.DemoContext.Hags }
        return @{ Supported = $null; Enabled = $null; Detail = 'Bellek arka ucu: sorgulanmadı' }
    }
    try {
        Initialize-LtNative
        $caps = @([LivnTools.NativeInfo]::HagsCaps() | Where-Object { $_ -ne [uint32]::MaxValue })
        if ($caps.Count -eq 0) { return @{ Supported = $null; Enabled = $null; Detail = 'Sürücü WDDM 2.7 yetenek sorgusunu yanıtlamadı' } }
        $supported = [bool](@($caps | Where-Object { ($_ -band 1) -ne 0 }).Count)
        $enabled = [bool](@($caps | Where-Object { ($_ -band 2) -ne 0 }).Count)
        return @{ Supported = $supported; Enabled = $enabled; Detail = 'WDDM 2.7 sürücü sorgusu' }
    } catch {
        return @{ Supported = $null; Enabled = $null; Detail = "Sorgu başarısız: $($_.Exception.Message)" }
    }
}

function Format-LtTriState($Value, [string]$Yes = 'Evet', [string]$No = 'Hayır') {
    if ($null -eq $Value) { return 'Unknown' }
    if ($Value) { return $Yes }
    return $No
}

function Format-LtInterruptSupport($Bits) {
    if ($null -eq $Bits) { return 'Unknown' }
    $b = [int]$Bits
    if (($b -band 4) -and ($b -band 2)) { return 'MSI ve MSI-X' }
    if ($b -band 4) { return 'MSI-X' }
    if ($b -band 2) { return 'MSI' }
    return 'Yalnız hat tabanlı kesme'
}

function Get-LtGraphicsConfiguration {
    # Kayitli tercih + surucunun bildirdigi yetenek. Okuma yazma yapmaz.
    $v = Get-LtRegValue 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode'
    $preference = if (-not $v.Exists) { 'Sürücü/Windows varsayılanı' }
        elseif ($v.Kind -eq 'DWord' -and [long]$v.Data -eq 2) { 'Açık tercihi (HwSchMode=2)' }
        elseif ($v.Kind -eq 'DWord' -and [long]$v.Data -eq 1) { 'Kapalı tercihi (HwSchMode=1)' }
        else { 'Tanınmayan kayıt: ' + (Format-LtRegState $v) }
    $caps = Get-LtHagsCapability
    @{ Configured = $preference
       Supported = (Format-LtTriState (Get-LtProp $caps 'Supported' $null) 'Destekleniyor' 'Desteklenmiyor')
       Effective = (Format-LtTriState (Get-LtProp $caps 'Enabled' $null) 'Açık' 'Kapalı')
       Detail = [string](Get-LtProp $caps 'Detail' '') }
}
function Get-LtMsiDeviceConfiguration {
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)][string]$InstanceId)
    $selectedDevices = @($Context.MsiDevices | Where-Object { $_.InstanceId -ieq $InstanceId -and $_.Class -in @('GPU','NIC') })
    if ($selectedDevices.Count -ne 1 -or $InstanceId -notmatch '^PCI\\[^\\]+\\[^\\]+$') {
        throw 'Algılanan GPU/ağ aygıtlarından tam olarak birini seçin.'
    }
    $device = $selectedDevices[0]
    $path = "HKLM\SYSTEM\CurrentControlSet\Enum\$($device.InstanceId)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
    $v = Get-LtRegValue $path 'MSISupported'
    $preference = if (-not $v.Exists) { 'Kayıt yok' } else { Format-LtRegState $v }
    @{ InstanceId = $device.InstanceId; Name = $device.Name; Class = $device.Class; Configured = $preference; Supported = (Format-LtInterruptSupport (Get-LtProp $device 'InterruptSupport' $null)); Effective = 'Unknown' }
}
