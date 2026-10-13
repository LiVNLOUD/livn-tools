# Livn Tools - Core/Demo.ps1
# Bellek arka ucu icin gercekci SAHTE sistem. Hem testler hem de "-DryRun"
# (kuru calisma) arayuz denemesi bunu kullanir. Gercek sisteme dokunmaz.

Set-StrictMode -Version 2.0

function Initialize-LtMemoryDemo {
    [CmdletBinding()]
    param([string]$Edition = 'Professional', [string]$Build = '22631', [switch]$Server)
    if ((Get-LtBackend) -ne 'Memory') { throw 'Sahte sistem yalnızca Memory arka ucunda kurulabilir.' }
    Reset-LtMemoryBackend
    $m = Get-LtMemoryState
    $cv = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    [void](Set-LtRegValue $cv 'CurrentBuildNumber' -Kind String -Data $Build)
    [void](Set-LtRegValue $cv 'UBR' -Kind DWord -Data 4037)
    [void](Set-LtRegValue $cv 'EditionID' -Kind String -Data $Edition)
    [void](Set-LtRegValue $cv 'ProductName' -Kind String -Data 'Windows 10 Pro')
    [void](Set-LtRegValue $cv 'DisplayVersion' -Kind String -Data '23H2')
    [void](Set-LtRegValue $cv 'InstallationType' -Kind String -Data $(if ($Server) { 'Server' } else { 'Client' }))

    $svc = @{ SysMain = 2; WSearch = 2; DiagTrack = 2; dmwappushservice = 3; XblAuthManager = 3; XblGameSave = 3; XboxNetApiSvc = 3; FontCache = 2 }
    foreach ($k in $svc.Keys) { [void](Set-LtRegValue "HKLM\SYSTEM\CurrentControlSet\Services\$k" 'Start' -Kind DWord -Data $svc[$k]) }
    [void](Set-LtRegValue 'HKLM\SYSTEM\CurrentControlSet\Services\WSearch' 'DelayedAutostart' -Kind DWord -Data 1)
    $m.ServiceState['sysmain'] = 'Running'; $m.ServiceState['wsearch'] = 'Running'; $m.ServiceState['diagtrack'] = 'Running'

    $m.Nic['ethernet|*flowcontrol'] = @{ Value = '3'; Valid = @('0', '1', '2', '3', '4'); Default = '3' }
    $m.Nic['ethernet|*eee']         = @{ Value = '1'; Valid = @('0', '1'); Default = '1' }
    $m.Nic['ethernet|*rss']         = @{ Value = '1'; Valid = @('0', '1'); Default = '1' }
    $m.Nic['ethernet|adaptiveifs']  = @{ Value = '1'; Valid = @('1'); Default = '1' }   # 0 gecerli degil

    # Eski bir aracin biraktigi zorlanmis platform saati
    [void](Set-LtRegValue "HKLM\BCD00000000\Objects\$($m.BcdCurrent)\Elements\260000a2" 'Element' -Kind Binary -Data ([Convert]::ToBase64String([byte[]](1))))

    # Kuru calismada temizlik sayfasinda bazi ogeler "kurulu" gorunsun (yalnizca sahte registry;
    # gercek dosya sistemi yoklanmaz, gercek surec listesi okunmaz)
    $un = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    foreach ($app in @('Google Chrome', 'Microsoft Edge', 'Steam', 'Discord')) {
        [void](Set-LtRegValue "$un\Demo-$($app -replace '\s', '')" 'DisplayName' -Kind String -Data $app)
    }
    $m.Processes = @(@{ Name = 'chrome'; HasWindow = $true })
    # Format Sonrasi: sahte WinGet envanteri (gercek winget calistirilmaz)
    $m.Setup = @{ WingetAvailable = $true; WingetVersion = 'v1.9.25200'; InstalledIds = @('Mozilla.Firefox', 'Valve.Steam', '7zip.7zip') }

    # Sistem Kontrolu icin sahte bulgular (gercek aygit/olay gunlugu okunmaz)
    $m.Health = @{
        ProblemDevices = @(@{ Name = 'PCI Veri Alma ve Sinyal İşleme Denetleyicisi'; Class = 'Unknown'; Code = 28 })
        Gpus = @(@{ Name = 'Sahte NVIDIA GPU'; Vendor = 'NVIDIA'; Inf = 'oem12.inf'; DriverVersion = '32.0.15.6094'; DriverDate = (Get-Date).AddMonths(-2) })
        Displays = @(@{ Name = 'Sahte 144 Hz Monitör'; Width = 2560; Height = 1440; Current = 60; Max = 144 })
        Memory = @{ Modules = @(@{ CapacityGB = 16; Speed = 3200; Configured = 2133; Type = 26 }, @{ CapacityGB = 16; Speed = 3200; Configured = 2133; Type = 26 }) }
        SystemDisk = @{ Letter = 'C'; FreeBytes = 120GB; SizeBytes = 476GB; MediaType = 'SSD'; Health = 'Healthy'; Trim = $true; TemperatureC = 41; WearPercent = 3 }
        Events = @{ Days = 14; Whea = 0; UnexpectedShutdown = 1; BugCheck = 0; LastBugCheck = $null }
        Network = @{ Adapters = @(@{ Name = 'Ethernet'; Description = 'Sahte Ethernet'; Wifi = $false; LinkSpeedBps = 1000000000 }) }
        Vbs = @{ Running = $true; Hvci = $true }
    }
    $m.Network = @{
        Gateway = '192.168.1.1'
        Latency = @{ '192.168.1.1' = @{ Base = 1; Spread = 0.3; LossEvery = 0 }; '1.1.1.1' = @{ Base = 12; Spread = 1; LossEvery = 0 }; '8.8.8.8' = @{ Base = 14; Spread = 1.5; LossEvery = 0 } }
        Dns = @{ '192.168.1.1' = 18.0; '1.1.1.1' = 9.0; '8.8.8.8' = 15.0; '9.9.9.9' = 22.0 }
    }
    $run = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Run'
    [void](Set-LtRegValue $run 'Discord' -Kind String -Data '"C:\Users\demo\AppData\Local\Discord\Update.exe" --processStart Discord.exe')
    [void](Set-LtRegValue $run 'Steam' -Kind String -Data '"C:\Program Files (x86)\Steam\steam.exe" -silent')
    [void](Set-LtRegValue $run 'OneDrive' -Kind String -Data '"C:\Program Files\Microsoft OneDrive\OneDrive.exe" /background')
    [void](Set-LtRegValue 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' 'SecurityHealth' -Kind ExpandString -Data '%windir%\system32\SecurityHealthSystray.exe')
    [void](Set-LtRegValue 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' 'RtkAudUService' -Kind String -Data '"C:\Windows\System32\DriverStore\FileRepository\RtkAudUService64.exe" -background')
    # Kurtarma kiti: sahte ucuncu taraf surucu paketleri (gercek surucu deposu okunmaz)
    $m.Drivers = @(
        @{ Inf = 'oem3.inf'; Class = 'Net'; Provider = 'Realtek'; Version = '10.68.815.2023'; Date = '2023-08-15'; Original = 'rt640x64.inf' }
        @{ Inf = 'oem7.inf'; Class = 'Net'; Provider = 'Intel'; Version = '23.40.0.4'; Date = '2024-05-02'; Original = 'netwtw10.inf' }
        @{ Inf = 'oem12.inf'; Class = 'Display'; Provider = 'NVIDIA'; Version = '32.0.15.6094'; Date = '2024-08-14'; Original = 'nv_dispi.inf' }
        @{ Inf = 'oem5.inf'; Class = 'MEDIA'; Provider = 'Realtek Semiconductor Corp.'; Version = '6.0.9549.1'; Date = '2023-06-29'; Original = 'hdxrt.inf' }
        @{ Inf = 'oem9.inf'; Class = 'System'; Provider = 'Advanced Micro Devices, Inc'; Version = '2.2.0.130'; Date = '2022-03-10'; Original = 'amdgpio2.inf' }
        @{ Inf = 'oem14.inf'; Class = 'Bluetooth'; Provider = 'Intel Corporation'; Version = '23.40.0.2'; Date = '2024-04-20'; Original = 'ibtusb.inf' }
    )
    $m.StartupFolders = @{ Startup = @('Spotify.lnk'); CommonStartup = @() }

    $m.DemoContext = @{
        Cpu = @{ Name = 'Sahte CPU 8C/16T'; Vendor = 'AMD'; Cores = 8; Threads = 16 }
        RamGB = 32; IsLaptop = $false; IsAdmin = $true
        Nics = @(@{ Name = 'Ethernet'; InterfaceGuid = '{aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee}'; Description = 'Sahte Ethernet'; LinkSpeed = '1 Gbps'; InstanceId = 'PCI\VEN_8086&DEV_15F3\1' })
        Gpus = @(@{ Name = 'Sahte NVIDIA GPU'; Vendor = 'NVIDIA'; InstanceId = 'PCI\VEN_10DE&DEV_2684\4&1'; DriverVersion = '32.0' })
        MsiDevices = @(@{ Class = 'GPU'; Name = 'Sahte NVIDIA GPU'; InstanceId = 'PCI\VEN_10DE&DEV_2684\4&1'; InterruptSupport = 3 }, @{ Class = 'NIC'; Name = 'Sahte Ethernet'; InstanceId = 'PCI\VEN_8086&DEV_15F3\1'; InterruptSupport = 7 })
        Hags = @{ Supported = $true; Enabled = $false; Detail = 'Deneme sistemi' }
    }
    return $m
}
