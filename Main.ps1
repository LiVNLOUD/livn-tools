#Requires -Version 5.1
<#
.SYNOPSIS
    Livn Tools v3.5 - System Optimization Suite
    Developed for livn.tr / LiVNLOUD/livn-tools
    Author: TheHybred / Livn Team
#>

# ─── ADMIN CHECK ───────────────────────────────────────────────────────────────
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Set-StrictMode -Off
# MIMARI: Global SilentlyContinue kaldirildi — hatalar artik loglara dusecek.
# Kritik olmayan islemlerde -ErrorAction SilentlyContinue hala bireysel olarak kullanilabilir.
$ErrorActionPreference = 'Continue'
$global:RootPath    = $PSScriptRoot
$global:BackupPath  = Join-Path $RootPath "_Files\Backups"
$global:LogPath     = Join-Path $RootPath "_Files\Logs"
$global:LogFile     = Join-Path $LogPath ("LivnTools_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".txt")
[void][System.Reflection.Assembly]::LoadWithPartialName('presentationframework')
[void][System.Reflection.Assembly]::LoadWithPartialName('presentationcore')
[void][System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')
Add-Type -AssemblyName System.Drawing

foreach ($d in @($global:BackupPath, $global:LogPath)) {
    if (-not (Test-Path $d)) { New-Item -Path $d -ItemType Directory -Force | Out-Null }
}

# ─── HARDWARE-AWARE DETECTION ENGINE ──────────────────────────────────────────
# CPU / GPU / NIC donanim taramasi — script basinda bir kez calisir
$global:HW = @{
    CpuName     = ''
    CpuIsAMD    = $false
    CpuIsIntel  = $false
    CpuCores    = 0
    CpuThreads  = 0
    GpuName     = ''
    GpuIsNV     = $false
    GpuIsAMD    = $false
    GpuVRAM_MB  = 0
    NicName     = ''
    NicIs10G    = $false
    RamGB       = 0
}

try {
    $cpuObj = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cpuObj) {
        $global:HW.CpuName    = ($cpuObj.Name -replace '\s+', ' ').Trim()
        $global:HW.CpuIsAMD   = $cpuObj.Name -match '(?i)AMD|Ryzen'
        $global:HW.CpuIsIntel = $cpuObj.Name -match '(?i)Intel'
        $global:HW.CpuCores   = $cpuObj.NumberOfCores
        $global:HW.CpuThreads = $cpuObj.NumberOfLogicalProcessors
    }
} catch {}

try {
    # Tum GPU'lari al, en yuksek VRAM'e sahip olanı sec (iGPU'ya karsi dGPU onceligi)
    $gpuAll = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -notmatch '(?i)Remote Desktop|Virtual|Basic Display' } |
              Sort-Object AdapterRAM -Descending
    $gpuObj = $gpuAll | Select-Object -First 1
    if ($gpuObj) {
        $global:HW.GpuName    = $gpuObj.Name
        $global:HW.GpuIsNV    = $gpuObj.Name -match '(?i)NVIDIA|GeForce|RTX|GTX'
        $global:HW.GpuIsAMD   = $gpuObj.Name -match '(?i)AMD|Radeon|RX\s'
        $global:HW.GpuVRAM_MB = [math]::Round($gpuObj.AdapterRAM / 1MB)
    }
} catch {}

try {
    $nicObj = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
    if ($nicObj) {
        $global:HW.NicName  = $nicObj.Name
        $global:HW.NicIs10G = $nicObj.LinkSpeed -match '10 Gbps'
    }
} catch {}

try {
    $global:HW.RamGB = [math]::Round((Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).TotalPhysicalMemory / 1GB)
} catch {}

# ─── APP DETECTION ENGINE (Registry + Path + Process - Cok Katmanli) ────────────
# Tum Uninstall key'lerini tek seferde cache'le — tekrar tekrar registry okumak yerine
$global:_RegCache = @()
try {
    $global:_RegCache = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    ) | ForEach-Object {
        Get-ItemProperty $_ -ErrorAction SilentlyContinue
    } | Where-Object { $_.DisplayName }
} catch {}

# DisplayName uzerinden arama (cache'li, hizli)
function Test-RegName {
    param([string[]]$Names, [switch]$Exact)
    foreach ($n in $Names) {
        if ($Exact) {
            # Tam eşleşme — örn. "Opera GX" varken "Opera GX Browser Helper" olmasın
            if ($global:_RegCache | Where-Object {
                $_.DisplayName -eq $n -or
                $_.DisplayName -like "$n *" -or
                $_.DisplayName -like "$n (*"
            }) { return $true }
        } else {
            # Geniş arama — örn. "Microsoft Edge" → "Microsoft Edge WebView2 Runtime" de yakalanır
            if ($global:_RegCache | Where-Object { $_.DisplayName -like "*$n*" }) { return $true }
        }
    }
    return $false
}

# Publisher uzerinden arama
function Test-RegPublisher([string]$Publisher) {
    return [bool]($global:_RegCache | Where-Object { $_.Publisher -like "*$Publisher*" } | Select-Object -First 1)
}

# Herhangi bir path var mi (wildcard ve versiyon-klasoru destekli)
function Test-AnyPath([string[]]$Paths) {
    foreach ($p in $Paths) {
        try {
            # Direkt path kontrolu
            if (Test-Path $p -ErrorAction SilentlyContinue) { return $true }
            # Versiyon-klasoru pattern: parent klasoru var mi?
            $parent = Split-Path $p -Parent
            if (Test-Path $parent -ErrorAction SilentlyContinue) {
                # Alt klasorlerde ara (versiyonlu kurulum: AppData\Programs\Opera GXD.x\opera.exe)
                $leaf = Split-Path $p -Leaf
                if (Get-ChildItem $parent -Recurse -Filter $leaf -ErrorAction SilentlyContinue | Select-Object -First 1) {
                    return $true
                }
            }
        } catch {}
    }
    return $false
}

# Kombine: Registry VEYA path (en az biri yeterlii)
function Test-App {
    param([string[]]$RegNames, [string[]]$Paths = @(), [string[]]$Publishers = @(), [switch]$Exact)
    if ($RegNames  -and (Test-RegName $RegNames -Exact:$Exact)) { return $true }
    if ($Publishers -and (Test-RegPublisher $Publishers[0]))     { return $true }
    if ($Paths     -and (Test-AnyPath $Paths))                  { return $true }
    return $false
}

# ─── UYGULAMA KURULUM TABLOSU ─────────────────────────────────────────────────
# Her entry: DisplayName patterns, fallback paths, publisher patterns
$global:AppInstalled = @{

    # ── TARAYICILAR ──────────────────────────────────────────────────────────
    'Chrome'     = Test-App -Exact `
        -RegNames   @('Google Chrome') `
        -Paths      @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
                      "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe")

    'Brave'      = Test-App -Exact `
        -RegNames   @('Brave','Brave Browser') `
        -Paths      @("$env:ProgramFiles\BraveSoftware\Brave-Browser\Application\brave.exe",
                      "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\Application\brave.exe")

    'Firefox'    = Test-App -Exact `
        -RegNames   @('Mozilla Firefox','Firefox') `
        -Paths      @("$env:ProgramFiles\Mozilla Firefox\firefox.exe",
                      "${env:ProgramFiles(x86)}\Mozilla Firefox\firefox.exe")

    'Edge'       = Test-App -Exact `
        -RegNames   @('Microsoft Edge') `
        -Paths      @("$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
                      "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe")

    'Opera'      = Test-App -Exact `
        -RegNames   @('Opera Stable','Opera Browser','Opera') `
        -Paths      @("$env:LOCALAPPDATA\Programs\Opera\opera.exe",
                      "$env:LOCALAPPDATA\Programs\Opera\launcher.exe")

    'OperaGX'    = Test-App -Exact `
        -RegNames   @('Opera GX','Opera GX Stable') `
        -Paths      @("$env:LOCALAPPDATA\Programs\Opera GX\launcher.exe",
                      "$env:LOCALAPPDATA\Programs\Opera GX\opera.exe",
                      "$env:ProgramFiles\Opera GX\launcher.exe")

    'Vivaldi'    = Test-App `
        -RegNames   @('Vivaldi') `
        -Paths      @("$env:LOCALAPPDATA\Programs\Vivaldi\Application\vivaldi.exe",
                      "$env:ProgramFiles\Vivaldi\Application\vivaldi.exe")

    'Tor'        = Test-App `
        -RegNames   @('Tor Browser') `
        -Paths      @("$env:LOCALAPPDATA\Tor Browser\Browser\firefox.exe")

    # ── MESAJLASMA / ILETISIM ────────────────────────────────────────────────
    'Discord'    = Test-App `
        -RegNames   @('Discord') `
        -Paths      @("$env:LOCALAPPDATA\Discord\Update.exe")

    'Telegram'   = Test-App `
        -RegNames   @('Telegram','Telegram Desktop') `
        -Paths      @("$env:APPDATA\Telegram Desktop\Telegram.exe",
                      "$env:LOCALAPPDATA\Telegram Desktop\Telegram.exe")

    'WhatsApp'   = Test-App `
        -RegNames   @('WhatsApp') `
        -Paths      @("$env:LOCALAPPDATA\WhatsApp\WhatsApp.exe",
                      "$env:LOCALAPPDATA\Packages\5319275A.WhatsAppDesktop_cv1g1gvanyjgm\LocalCache\Roaming\WhatsApp\WhatsApp.exe")

    'Slack'      = Test-App `
        -RegNames   @('Slack') `
        -Paths      @("$env:LOCALAPPDATA\slack\slack.exe")

    'Zoom'       = Test-App `
        -RegNames   @('Zoom','Zoom Workplace') `
        -Paths      @("$env:APPDATA\Zoom\bin\Zoom.exe",
                      "$env:ProgramFiles\Zoom\bin\Zoom.exe")

    'Teams'      = Test-App `
        -RegNames   @('Microsoft Teams','Teams') `
        -Paths      @("$env:LOCALAPPDATA\Microsoft\Teams\current\Teams.exe",
                      "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\app\MSTeams.exe")

    # ── OYUN LAUNCHER'LARI ───────────────────────────────────────────────────
    'Steam'      = Test-App `
        -RegNames   @('Steam') `
        -Publishers @('Valve') `
        -Paths      @("${env:ProgramFiles(x86)}\Steam\steam.exe",
                      "$env:ProgramFiles\Steam\steam.exe")

    'EpicGames'  = Test-App `
        -RegNames   @('Epic Games Launcher','Epic Games') `
        -Publishers @('Epic Games') `
        -Paths      @("${env:ProgramFiles(x86)}\Epic Games\Launcher\Portal\Binaries\Win32\EpicGamesLauncher.exe",
                      "$env:ProgramFiles\Epic Games\Launcher\Portal\Binaries\Win64\EpicGamesLauncher.exe")

    'GOGGalaxy'  = Test-App `
        -RegNames   @('GOG Galaxy','GOG.com') `
        -Publishers @('GOG') `
        -Paths      @("${env:ProgramFiles(x86)}\GOG Galaxy\GalaxyClient.exe",
                      "$env:ProgramFiles\GOG Galaxy\GalaxyClient.exe")

    'UbisoftConnect' = Test-App `
        -RegNames   @('Ubisoft Connect','Uplay','Ubisoft Game Launcher') `
        -Publishers @('Ubisoft') `
        -Paths      @("${env:ProgramFiles(x86)}\Ubisoft\Ubisoft Game Launcher\UbisoftConnect.exe",
                      "$env:ProgramFiles\Ubisoft\Ubisoft Game Launcher\UbisoftConnect.exe")

    'Battlenet'  = Test-App `
        -RegNames   @('Battle.net','Battlenet','Blizzard Battle.net') `
        -Publishers @('Blizzard') `
        -Paths      @("${env:ProgramFiles(x86)}\Battle.net\Battle.net.exe",
                      "$env:ProgramFiles\Battle.net\Battle.net.exe")

    'EADesktop'  = Test-App `
        -RegNames   @('EA Desktop','EA app','EADesktop','Electronic Arts') `
        -Publishers @('Electronic Arts','EA Technologies') `
        -Paths      @("$env:ProgramFiles\Electronic Arts\EA Desktop\EA Desktop.exe",
                      "${env:ProgramFiles(x86)}\Electronic Arts\EA Desktop\EA Desktop.exe")

    'Xbox'       = Test-App `
        -RegNames   @('Xbox','Xbox Console Companion','Xbox App') `
        -Paths      @("$env:ProgramFiles\WindowsApps\Microsoft.GamingApp_8wekyb3d8bbwe\Gaming.Desktop.x64.Launcher.exe",
                      "$env:SystemRoot\System32\XboxGameBarWidgets.exe")

    'Rockstar'   = Test-App `
        -RegNames   @('Rockstar Games Launcher','Rockstar') `
        -Publishers @('Rockstar Games') `
        -Paths      @("$env:ProgramFiles\Rockstar Games\Launcher\Launcher.exe",
                      "${env:ProgramFiles(x86)}\Rockstar Games\Launcher\Launcher.exe")

    'Minecraft'  = Test-App `
        -RegNames   @('Minecraft Launcher','Minecraft') `
        -Paths      @("$env:LOCALAPPDATA\Packages\Microsoft.4297127D64EC6_8wekyb3d8bbwe\LocalCache\Local\runtime\java-runtime-gamma\bin\java.exe",
                      "$env:ProgramFiles\Minecraft Launcher\MinecraftLauncher.exe")

    'Riot'       = Test-App `
        -RegNames   @('Riot Client','Riot Games','Riot Vanguard','League of Legends','VALORANT') `
        -Publishers @('Riot Games') `
        -Paths      @("$env:ProgramFiles\Riot Games\Riot Client\RiotClientServices.exe",
                      "${env:ProgramFiles(x86)}\Riot Games\Riot Client\RiotClientServices.exe")

    # ── MEDYA / EGLENCE ──────────────────────────────────────────────────────
    'Spotify'    = Test-App `
        -RegNames   @('Spotify') `
        -Paths      @("$env:APPDATA\Spotify\Spotify.exe",
                      "$env:LOCALAPPDATA\Microsoft\WindowsApps\Spotify.exe")

    'VLC'        = Test-App `
        -RegNames   @('VLC media player') `
        -Paths      @("$env:ProgramFiles\VideoLAN\VLC\vlc.exe",
                      "${env:ProgramFiles(x86)}\VideoLAN\VLC\vlc.exe")

    # ── DIGER YAYGIN UYGULAMALAR ─────────────────────────────────────────────
    'Skype'      = Test-App `
        -RegNames   @('Skype') `
        -Paths      @("$env:LOCALAPPDATA\Microsoft\WindowsApps\Skype.exe",
                      "$env:ProgramFiles\WindowsApps\Microsoft.SkypeApp_kzf8qxf38zg5c\Skype\Skype.exe")

    'OneDrive'   = Test-App `
        -RegNames   @('Microsoft OneDrive','OneDrive') `
        -Paths      @("$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe")
}

function Test-RegValueEquals([string]$path, [string]$name, $expected) {
    try {
        $val = (Get-ItemProperty -Path $path -Name $name -ErrorAction Stop).$name
        return ($val -eq $expected)
    } catch { return $false }
}

# ─── PROCESS ACIK MI KONTROLU (WPF popup oncesi) ──────────────────────────────
function Confirm-AppClosed([string]$processName, [string]$appDisplayName) {
    $proc = Get-Process -Name $processName -ErrorAction SilentlyContinue
    if ($proc) {
        $result = [System.Windows.MessageBox]::Show(
            "$appDisplayName su anda acik!`n`nTemizlik icin uygulamanin kapatilmasi onerilir.`nYine de devam etmek istiyor musunuz?",
            "Uygulama Acik - $appDisplayName",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Warning)
        return ($result -eq [System.Windows.MessageBoxResult]::Yes)
    }
    return $true
}

# ─── XAML UI DEFINITION ────────────────────────────────────────────────────────
[xml]$XAML = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Livn Tools v3.5"
    Height="800" Width="1200"
    MinHeight="640" MinWidth="960"
    WindowStartupLocation="CenterScreen"
    Background="Transparent"
    FontFamily="Segoe UI"
    AllowsTransparency="True"
    WindowStyle="None">

    <Window.Resources>
        <!-- COLORS -->
        <SolidColorBrush x:Key="BgDeep"       Color="#0D0E1A"/>
        <SolidColorBrush x:Key="BgSidebar"    Color="#12132A"/>
        <SolidColorBrush x:Key="BgCard"       Color="#1A1B35"/>
        <SolidColorBrush x:Key="BgCardHover"  Color="#21234A"/>
        <SolidColorBrush x:Key="AccentPurple" Color="#7B5EA7"/>
        <SolidColorBrush x:Key="AccentBlue"   Color="#4A90D9"/>
        <SolidColorBrush x:Key="AccentGreen"  Color="#4CAF50"/>
        <SolidColorBrush x:Key="AccentOrange" Color="#FF9800"/>
        <SolidColorBrush x:Key="AccentRed"    Color="#F44336"/>
        <SolidColorBrush x:Key="TextPrimary"  Color="#E8E8F0"/>
        <SolidColorBrush x:Key="TextSecond"   Color="#9898B0"/>
        <SolidColorBrush x:Key="BorderColor"  Color="#2A2B4A"/>

        <!-- SCROLLBAR STYLE -->
        <Style x:Key="DarkScroll" TargetType="ScrollBar">
            <Setter Property="Background" Value="#1A1B35"/>
            <Setter Property="Width" Value="6"/>
        </Style>

        <!-- BUTTON BASE STYLE -->
        <Style x:Key="BtnBase" TargetType="Button">
            <Setter Property="Background"    Value="#1A1B35"/>
            <Setter Property="Foreground"    Value="#E8E8F0"/>
            <Setter Property="BorderBrush"   Value="#2A2B4A"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding"       Value="10,6"/>
            <Setter Property="FontSize"      Value="12"/>
            <Setter Property="Cursor"        Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="6" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="#21234A"/>
                                <Setter TargetName="bd" Property="BorderBrush" Value="#7B5EA7"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="#7B5EA7"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- ACCENT BUTTON -->
        <Style x:Key="BtnAccent" TargetType="Button" BasedOn="{StaticResource BtnBase}">
            <Setter Property="Background"  Value="#7B5EA7"/>
            <Setter Property="BorderBrush" Value="#9B7EC7"/>
            <Setter Property="FontWeight"  Value="SemiBold"/>
        </Style>

        <!-- DANGER BUTTON -->
        <Style x:Key="BtnDanger" TargetType="Button" BasedOn="{StaticResource BtnBase}">
            <Setter Property="Background"  Value="#4A1A1A"/>
            <Setter Property="BorderBrush" Value="#F44336"/>
            <Setter Property="Foreground"  Value="#F44336"/>
        </Style>

        <!-- SUCCESS BUTTON -->
        <Style x:Key="BtnSuccess" TargetType="Button" BasedOn="{StaticResource BtnBase}">
            <Setter Property="Background"  Value="#1A4A1A"/>
            <Setter Property="BorderBrush" Value="#4CAF50"/>
            <Setter Property="Foreground"  Value="#4CAF50"/>
        </Style>

        <!-- ACTIVE (SELECTED) BUTTON — seçili durum için mor kenarlı -->
        <Style x:Key="BtnActive" TargetType="Button" BasedOn="{StaticResource BtnBase}">
            <Setter Property="Background"        Value="#2D1F4A"/>
            <Setter Property="BorderBrush"       Value="#7B5EA7"/>
            <Setter Property="BorderThickness"   Value="2"/>
            <Setter Property="Foreground"        Value="#E8E8F0"/>
            <Setter Property="FontWeight"        Value="SemiBold"/>
        </Style>

        <!-- CHECKBOX STYLE -->
        <Style TargetType="CheckBox">
            <Setter Property="Foreground"    Value="#E8E8F0"/>
            <Setter Property="FontSize"      Value="12"/>
            <Setter Property="Margin"        Value="0,4"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="CheckBox">
                        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                            <Border x:Name="bx" Width="16" Height="16" CornerRadius="3"
                                    Background="#1A1B35" BorderBrush="#2A2B4A" BorderThickness="1">
                                <TextBlock x:Name="chk" Text="&#xE73E;" FontFamily="Segoe MDL2 Assets"
                                           FontSize="10" Foreground="#7B5EA7"
                                           HorizontalAlignment="Center" VerticalAlignment="Center"
                                           Visibility="Collapsed"/>
                            </Border>
                            <ContentPresenter Margin="8,0,0,0" VerticalAlignment="Center"/>
                        </StackPanel>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="chk" Property="Visibility" Value="Visible"/>
                                <Setter TargetName="bx"  Property="BorderBrush" Value="#7B5EA7"/>
                                <Setter TargetName="bx"  Property="Background"  Value="#21234A"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bx" Property="BorderBrush" Value="#7B5EA7"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- TREEVIEW ITEM STYLE -->
        <!-- NAV CATEGORY: Tıklanamaz grup başlığı (Temizlik, Optimizasyon) -->
        <Style x:Key="NavCategory" TargetType="TreeViewItem">
            <Setter Property="Background"      Value="Transparent"/>
            <Setter Property="Foreground"      Value="#6A6A8A"/>
            <Setter Property="FontSize"        Value="11"/>
            <Setter Property="Padding"         Value="8,0"/>
            <Setter Property="Cursor"          Value="Arrow"/>
            <Setter Property="IsExpanded"      Value="True"/>
            <Setter Property="Focusable"       Value="False"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TreeViewItem">
                        <StackPanel>
                            <Border x:Name="header" Background="Transparent"
                                    CornerRadius="4" Margin="4,3,4,1" Height="26"
                                    IsHitTestVisible="False">
                                <ContentPresenter ContentSource="Header"
                                                  HorizontalAlignment="Left"
                                                  VerticalAlignment="Center"
                                                  RecognizesAccessKey="False"
                                                  Margin="{TemplateBinding Padding}"/>
                            </Border>
                            <ItemsPresenter x:Name="items" Margin="14,0,0,0"/>
                        </StackPanel>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="NavItem" TargetType="TreeViewItem">
            <Setter Property="Background"      Value="Transparent"/>
            <Setter Property="Foreground"      Value="#9898B0"/>
            <Setter Property="FontSize"        Value="13"/>
            <Setter Property="Padding"         Value="8,0"/>
            <Setter Property="Cursor"          Value="Hand"/>
            <Setter Property="IsExpanded"      Value="True"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TreeViewItem">
                        <StackPanel>
                            <Border x:Name="header" Background="{TemplateBinding Background}"
                                    CornerRadius="6" Margin="4,2" Height="32"
                                    UseLayoutRounding="True" SnapsToDevicePixels="True">
                                <ContentPresenter ContentSource="Header"
                                                  HorizontalAlignment="Left"
                                                  VerticalAlignment="Center"
                                                  RecognizesAccessKey="False"
                                                  Margin="{TemplateBinding Padding}"/>
                            </Border>
                            <ItemsPresenter x:Name="items" Margin="14,0,0,0"/>
                        </StackPanel>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="header" Property="Background" Value="#21234A"/>
                                <Setter Property="Foreground" Value="#E8E8F0"/>
                            </Trigger>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="header" Property="Background" Value="#2D1F4A"/>
                                <Setter Property="Foreground" Value="#E8E8F0"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- SEPARATOR STYLE -->
        <Style TargetType="Separator">
            <Setter Property="Background" Value="#2A2B4A"/>
            <Setter Property="Margin"     Value="0,8"/>
        </Style>

        <!-- TEXTBOX TERMINAL STYLE -->
        <Style x:Key="Terminal" TargetType="TextBox">
            <Setter Property="Background"        Value="#080910"/>
            <Setter Property="Foreground"        Value="#00FF88"/>
            <Setter Property="FontFamily"        Value="Cascadia Code, Consolas, Courier New"/>
            <Setter Property="FontSize"          Value="11"/>
            <Setter Property="BorderBrush"       Value="#2A2B4A"/>
            <Setter Property="BorderThickness"   Value="1"/>
            <Setter Property="Padding"           Value="10"/>
            <Setter Property="IsReadOnly"        Value="True"/>
            <Setter Property="TextWrapping"      Value="Wrap"/>
            <Setter Property="VerticalScrollBarVisibility" Value="Auto"/>
        </Style>

        <!-- PROGRESSBAR STYLE -->
        <Style TargetType="ProgressBar">
            <Setter Property="Background"  Value="#1A1B35"/>
            <Setter Property="BorderBrush" Value="#2A2B4A"/>
            <Setter Property="Height"      Value="4"/>
            <Setter Property="Foreground"  Value="#7B5EA7"/>
        </Style>

        <!-- SLIDER STYLE -->
        <Style TargetType="Slider">
            <Setter Property="Foreground" Value="#7B5EA7"/>
        </Style>

        <!-- COMBOBOX STYLE -->
        <Style TargetType="ComboBox">
            <Setter Property="Background"  Value="#1A1B35"/>
            <Setter Property="Foreground"  Value="#E8E8F0"/>
            <Setter Property="BorderBrush" Value="#2A2B4A"/>
            <Setter Property="Padding"     Value="8,6"/>
            <Setter Property="FontSize"    Value="12"/>
        </Style>

        <!-- GROUPBOX STYLE -->
        <Style TargetType="GroupBox">
            <Setter Property="Foreground"      Value="#9898B0"/>
            <Setter Property="BorderBrush"     Value="#2A2B4A"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding"         Value="10"/>
            <Setter Property="Margin"          Value="0,6"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="GroupBox">
                        <Border Background="#1A1B35" BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="8">
                            <Grid>
                                <Grid.RowDefinitions>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition/>
                                </Grid.RowDefinitions>
                                <Border Grid.Row="0" Background="#21234A" CornerRadius="8,8,0,0" Padding="12,8">
                                    <ContentPresenter ContentSource="Header" TextBlock.Foreground="#9898B0"
                                                      TextBlock.FontSize="11" TextBlock.FontWeight="SemiBold"/>
                                </Border>
                                <ContentPresenter Grid.Row="1" Margin="{TemplateBinding Padding}"/>
                            </Grid>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <!-- MAIN GRID — wrapped in a Border for CornerRadius clipping (fixes white strip) -->
    <Border Background="#0D0E1A" CornerRadius="10" ClipToBounds="True">
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="48"/>  <!-- Title Bar -->
            <RowDefinition Height="56"/>  <!-- HW Monitor Bar -->
            <RowDefinition Height="40"/>  <!-- Global Presets Bar -->
            <RowDefinition Height="*"/>   <!-- Content -->
            <RowDefinition Height="180"/> <!-- Terminal -->
            <RowDefinition Height="36"/>  <!-- Status Bar -->
        </Grid.RowDefinitions>

        <!-- ── TITLE BAR ─────────────────────────────────────────── -->
        <Border Grid.Row="0" Background="#080910" x:Name="TitleBar"
                BorderBrush="#2A2B4A" BorderThickness="0,0,0,1">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <!-- Logo + Title -->
                <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center" Margin="16,0">
                    <TextBlock Text="&#xE9F5;" FontFamily="Segoe MDL2 Assets" FontSize="20"
                               Foreground="#7B5EA7" VerticalAlignment="Center"/>
                    <TextBlock Text="  LIVN TOOLS" FontSize="15" FontWeight="Bold"
                               Foreground="#E8E8F0" VerticalAlignment="Center" Margin="8,0,0,0"/>
                    <TextBlock Text=" v3.5" FontSize="11" Foreground="#9898B0" VerticalAlignment="Center" Margin="2,2,0,0"/>
                </StackPanel>
                <!-- Window Controls -->
                <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center" Margin="0,0,8,0">
                    <Button x:Name="BtnMinimize" Content="&#xE921;" FontFamily="Segoe MDL2 Assets"
                            FontSize="11" Width="40" Height="32" Style="{StaticResource BtnBase}"
                            BorderThickness="0" Background="Transparent" ToolTip="Minimize"/>
                    <Button x:Name="BtnMaximize" Content="&#xE922;" FontFamily="Segoe MDL2 Assets"
                            FontSize="11" Width="40" Height="32" Style="{StaticResource BtnBase}"
                            BorderThickness="0" Background="Transparent" ToolTip="Maximize"/>
                    <Button x:Name="BtnClose" Content="&#xE8BB;" FontFamily="Segoe MDL2 Assets"
                            FontSize="11" Width="40" Height="32" Style="{StaticResource BtnBase}"
                            BorderThickness="0" Background="Transparent" Foreground="#F44336" ToolTip="Close"/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- ── HW MONITOR BAR ────────────────────────────────────── -->
        <Border Grid.Row="1" Background="#0F1020" BorderBrush="#2A2B4A" BorderThickness="0,0,0,1">
            <Grid Margin="16,0">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <!-- CPU -->
                <StackPanel Grid.Column="0" VerticalAlignment="Center" Margin="0,0,20,0">
                    <StackPanel Orientation="Horizontal">
                        <TextBlock Text="&#xE950;" FontFamily="Segoe MDL2 Assets" FontSize="12"
                                   Foreground="#7B5EA7" VerticalAlignment="Center"/>
                        <TextBlock Text=" CPU" FontSize="10" Foreground="#9898B0" VerticalAlignment="Center"/>
                        <TextBlock x:Name="TxtCpuPct" Text=" 0%" FontSize="13" FontWeight="Bold"
                                   Foreground="#E8E8F0" VerticalAlignment="Center"/>
                    </StackPanel>
                    <ProgressBar x:Name="ProgCpu" Value="0" Maximum="100" Margin="0,4,0,0"/>
                    <TextBlock x:Name="TxtCpuName" Text="Loading..." FontSize="9"
                               Foreground="#9898B0" Margin="0,2,0,0"/>
                </StackPanel>

                <!-- RAM -->
                <StackPanel Grid.Column="1" VerticalAlignment="Center" Margin="0,0,20,0">
                    <StackPanel Orientation="Horizontal">
                        <TextBlock Text="&#xE7F4;" FontFamily="Segoe MDL2 Assets" FontSize="12"
                                   Foreground="#4A90D9" VerticalAlignment="Center"/>
                        <TextBlock Text=" RAM" FontSize="10" Foreground="#9898B0" VerticalAlignment="Center"/>
                        <TextBlock x:Name="TxtRamPct" Text=" 0%" FontSize="13" FontWeight="Bold"
                                   Foreground="#E8E8F0" VerticalAlignment="Center"/>
                    </StackPanel>
                    <ProgressBar x:Name="ProgRam" Value="0" Maximum="100" Margin="0,4,0,0" Foreground="#4A90D9"/>
                    <TextBlock x:Name="TxtRamDetail" Text="0 / 0 GB" FontSize="9"
                               Foreground="#9898B0" Margin="0,2,0,0"/>
                </StackPanel>

                <!-- System Info -->
                <StackPanel Grid.Column="2" VerticalAlignment="Center">
                    <StackPanel Orientation="Horizontal">
                        <TextBlock Text="&#xE77B;" FontFamily="Segoe MDL2 Assets" FontSize="12"
                                   Foreground="#4CAF50" VerticalAlignment="Center"/>
                        <TextBlock x:Name="TxtUserPC" Text=" User @ PC" FontSize="12"
                                   Foreground="#E8E8F0" VerticalAlignment="Center" Margin="6,0,0,0"/>
                    </StackPanel>
                    <TextBlock x:Name="TxtOS" Text="Windows" FontSize="9" Foreground="#9898B0" Margin="0,4,0,0"/>
                    <TextBlock x:Name="TxtUptime" Text="Uptime: --" FontSize="9" Foreground="#9898B0"/>
                </StackPanel>

                <!-- USB Watchdog + Clock -->
                <StackPanel Grid.Column="3" VerticalAlignment="Center" HorizontalAlignment="Right" Margin="0,0,4,0">
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,0,0,4">
                        <TextBlock Text="&#xE88E;" FontFamily="Segoe MDL2 Assets" FontSize="11"
                                   Foreground="#FF9800" VerticalAlignment="Center"/>
                        <TextBlock x:Name="TxtUsbLabel" Text=" USB: " FontSize="10"
                                   Foreground="#9898B0" VerticalAlignment="Center"/>
                        <TextBlock x:Name="TxtUsbCount" Text="Taranıyor..." FontSize="11"
                                   FontWeight="SemiBold" Foreground="#9898B0" VerticalAlignment="Center"/>
                    </StackPanel>
                    <TextBlock x:Name="TxtClock" Text="00:00:00" FontSize="18" FontWeight="Light"
                               Foreground="#7B5EA7" HorizontalAlignment="Right"/>
                    <TextBlock x:Name="TxtDate" Text="" FontSize="9" Foreground="#9898B0"
                               HorizontalAlignment="Right"/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- ── GLOBAL PRESETS BAR ────────────────────────────────── -->
        <Border x:Name="GlobalPresetsBar" Grid.Row="2" Background="#0D0E1A" BorderBrush="#2A2B4A" BorderThickness="0,0,0,1" Visibility="Collapsed">
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="16,0">
                <TextBlock Text="&#xECFA;" FontFamily="Segoe MDL2 Assets" FontSize="13"
                           Foreground="#9898B0" VerticalAlignment="Center"/>
                <TextBlock Text="  GLOBAL PRESET:" FontSize="11" FontWeight="SemiBold"
                           Foreground="#9898B0" VerticalAlignment="Center" Margin="0,0,14,0"/>

                <Button x:Name="BtnPresetMinimal" Style="{StaticResource BtnBase}"
                        Padding="8,4" Margin="0,0,5,0" Height="26" ToolTip="Safe: Temel temizlik ve stabilite">
                    <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                        <TextBlock Text="&#xE728;" FontFamily="Segoe MDL2 Assets" FontSize="11" VerticalAlignment="Center" Margin="0,2,0,0"/>
                        <TextBlock Text=" Minimal" FontSize="11" VerticalAlignment="Center" Margin="3,0,0,0"/>
                    </StackPanel>
                </Button>
                <Button x:Name="BtnPresetStandard" Style="{StaticResource BtnBase}"
                        Padding="8,4" Margin="0,0,5,0" Height="26" ToolTip="Balanced: Gaming + Streaming dengesi">
                    <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                        <TextBlock Text="&#xE7B5;" FontFamily="Segoe MDL2 Assets" FontSize="11" VerticalAlignment="Center" Margin="0,2,0,0"/>
                        <TextBlock Text=" Standard" FontSize="11" VerticalAlignment="Center" Margin="3,0,0,0"/>
                    </StackPanel>
                </Button>
                <Button x:Name="BtnPresetAggressive" Style="{StaticResource BtnAccent}"
                        Padding="8,4" Margin="0,0,5,0" Height="26" ToolTip="Gaming: Maksimum performans, latency odakli">
                    <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                        <TextBlock Text="&#xE945;" FontFamily="Segoe MDL2 Assets" FontSize="11" VerticalAlignment="Center" Margin="0,2,0,0"/>
                        <TextBlock Text=" Aggressive" FontSize="11" VerticalAlignment="Center" Margin="3,0,0,0"/>
                    </StackPanel>
                </Button>
                <Button x:Name="BtnApplyAll" Style="{StaticResource BtnAccent}"
                        Padding="8,4" Margin="0,0,5,0" Height="26">
                    <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                        <TextBlock Text="&#xE74E;" FontFamily="Segoe MDL2 Assets" FontSize="11" VerticalAlignment="Center" Margin="0,2,0,0"/>
                        <TextBlock Text=" Apply All" FontSize="11" VerticalAlignment="Center" Margin="3,0,0,0"/>
                    </StackPanel>
                </Button>
                <Button x:Name="BtnRestoreBackup" Style="{StaticResource BtnDanger}"
                        Padding="8,4" Height="26" ToolTip="Son Registry yedegini geri yukle">
                    <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                        <TextBlock Text="&#xE777;" FontFamily="Segoe MDL2 Assets" FontSize="11" VerticalAlignment="Center" Margin="0,2,0,0"/>
                        <TextBlock Text=" Geri Don" FontSize="11" VerticalAlignment="Center" Margin="3,0,0,0"/>
                    </StackPanel>
                </Button>
            </StackPanel>
        </Border>

        <!-- ── CONTENT AREA ─────────────────────────────────────── -->
        <Grid Grid.Row="3">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="210"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <!-- SIDEBAR -->
            <Border Grid.Column="0" Background="#12132A" BorderBrush="#2A2B4A" BorderThickness="0,0,1,0">
                <DockPanel>
                    <TextBlock DockPanel.Dock="Top" Text="NAVIGASYON" FontSize="9" FontWeight="Bold"
                               Foreground="#4A4A6A" Margin="16,12,0,8"/>

                    <!-- Bottom sidebar info — DockPanel'da ScrollViewer'dan ONCE dock edilir, boylece her zaman gorunur -->
                    <Border DockPanel.Dock="Bottom" Margin="8,4,8,8" Padding="10,6"
                            Background="#1A1B35" CornerRadius="8">
                        <StackPanel>
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock Text="&#xE7EF;" FontFamily="Segoe MDL2 Assets"
                                           FontSize="10" Foreground="#9898B0" VerticalAlignment="Center"/>
                                <TextBlock Text="  livn.tr"
                                           FontSize="10" Foreground="#9898B0" VerticalAlignment="Center"/>
                            </StackPanel>
                            <TextBlock Text="LiVNLOUD/livn-tools" FontSize="9" Foreground="#4A4A6A" Margin="18,2,0,0"/>
                        </StackPanel>
                    </Border>

                    <!-- ScrollViewer son element — kalan alani doldurur, icerik sigmazsa scroll olusur -->
                    <ScrollViewer VerticalScrollBarVisibility="Auto">
                        <TreeView x:Name="NavTree" Background="Transparent" BorderThickness="0"
                                  Margin="8,0">

                            <!-- TEMIZLIK -->
                            <TreeViewItem x:Name="NavCatTemizlik" Style="{StaticResource NavCategory}">
                                <TreeViewItem.Header>
                                    <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                        <TextBlock Text="&#xE74D;" FontFamily="Segoe MDL2 Assets" FontSize="11"
                                                   x:Name="NavCatTemizlikIcon" Foreground="#4A4A6A"
                                                   VerticalAlignment="Center" Margin="0,1,5,0"/>
                                        <TextBlock x:Name="NavCatTemizlikText" Text="TEMIZLIK"
                                                   FontSize="10" FontWeight="Bold"
                                                   Foreground="#4A4A6A" VerticalAlignment="Center"
                                                   FontFamily="Segoe UI"/>
                                    </StackPanel>
                                </TreeViewItem.Header>
                                <TreeViewItem x:Name="NavQuickClean"
                                              Style="{StaticResource NavItem}">
                                    <TreeViewItem.Header>
                                        <Grid UseLayoutRounding="True" SnapsToDevicePixels="True">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="20"/>
                                            <ColumnDefinition Width="*"/>
                                        </Grid.ColumnDefinitions>
                                        <Border Grid.Column="0" Width="16" Height="16" HorizontalAlignment="Center" VerticalAlignment="Center">
                                        <TextBlock Text="&#xE74D;" FontFamily="Segoe MDL2 Assets" FontSize="14" Foreground="#4A90D9" HorizontalAlignment="Center" VerticalAlignment="Center" LineHeight="14" Padding="0" Margin="0,1,0,0"/>
                                    </Border>
                                        <TextBlock Grid.Column="1" Text="  Quick Clean" FontSize="12" VerticalAlignment="Center" LineHeight="14" Padding="0"/>
                                    </Grid>
                                    </TreeViewItem.Header>
                                </TreeViewItem>
                                <TreeViewItem x:Name="NavAdvancedClean" Style="{StaticResource NavItem}">
                                    <TreeViewItem.Header>
                                        <Grid UseLayoutRounding="True" SnapsToDevicePixels="True">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="20"/>
                                            <ColumnDefinition Width="*"/>
                                        </Grid.ColumnDefinitions>
                                        <Border Grid.Column="0" Width="16" Height="16" HorizontalAlignment="Center" VerticalAlignment="Center">
                                        <TextBlock Text="&#xE74D;" FontFamily="Segoe MDL2 Assets" FontSize="14" Foreground="#FF9800" HorizontalAlignment="Center" VerticalAlignment="Center" LineHeight="14" Padding="0" Margin="0,1,0,0"/>
                                    </Border>
                                        <TextBlock Grid.Column="1" Text="  Advanced Clean" FontSize="12" VerticalAlignment="Center" LineHeight="14" Padding="0"/>
                                    </Grid>
                                    </TreeViewItem.Header>
                                </TreeViewItem>
                            </TreeViewItem>

                            <!-- OPTIMIZASYON -->
                            <TreeViewItem x:Name="NavCatOptimizasyon" Style="{StaticResource NavCategory}" Margin="0,8,0,0">
                                <TreeViewItem.Header>
                                    <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                        <TextBlock Text="&#xE9F9;" FontFamily="Segoe MDL2 Assets" FontSize="11"
                                                   x:Name="NavCatOptimIcon" Foreground="#4A4A6A"
                                                   VerticalAlignment="Center" Margin="0,1,5,0"/>
                                        <TextBlock x:Name="NavCatOptimText" Text="OPTiMiZASYON"
                                                   FontSize="10" FontWeight="Bold"
                                                   Foreground="#4A4A6A" VerticalAlignment="Center"
                                                   FontFamily="Segoe UI"/>
                                    </StackPanel>
                                </TreeViewItem.Header>
                                <TreeViewItem x:Name="NavPerformance" Style="{StaticResource NavItem}">
                                    <TreeViewItem.Header>
                                        <Grid UseLayoutRounding="True" SnapsToDevicePixels="True">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="20"/>
                                            <ColumnDefinition Width="*"/>
                                        </Grid.ColumnDefinitions>
                                        <Border Grid.Column="0" Width="16" Height="16" HorizontalAlignment="Center" VerticalAlignment="Center">
                                        <TextBlock Text="&#xE945;" FontFamily="Segoe MDL2 Assets" FontSize="14" Foreground="#7B5EA7" HorizontalAlignment="Center" VerticalAlignment="Center" LineHeight="14" Padding="0" Margin="0,1,0,0"/>
                                    </Border>
                                        <TextBlock Grid.Column="1" Text="  Performance" FontSize="12" VerticalAlignment="Center" LineHeight="14" Padding="0"/>
                                    </Grid>
                                    </TreeViewItem.Header>
                                </TreeViewItem>
                                <TreeViewItem x:Name="NavNetwork" Style="{StaticResource NavItem}">
                                    <TreeViewItem.Header>
                                        <Grid UseLayoutRounding="True" SnapsToDevicePixels="True">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="20"/>
                                            <ColumnDefinition Width="*"/>
                                        </Grid.ColumnDefinitions>
                                        <Border Grid.Column="0" Width="16" Height="16" HorizontalAlignment="Center" VerticalAlignment="Center">
                                        <TextBlock Text="&#xEC27;" FontFamily="Segoe MDL2 Assets" FontSize="14" Foreground="#4A90D9" HorizontalAlignment="Center" VerticalAlignment="Center" LineHeight="14" Padding="0" Margin="0,1,0,0"/>
                                    </Border>
                                        <TextBlock Grid.Column="1" Text="  Network" FontSize="12" VerticalAlignment="Center" LineHeight="14" Padding="0"/>
                                    </Grid>
                                    </TreeViewItem.Header>
                                </TreeViewItem>
                                <TreeViewItem x:Name="NavKernel" Style="{StaticResource NavItem}">
                                    <TreeViewItem.Header>
                                        <Grid UseLayoutRounding="True" SnapsToDevicePixels="True">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="20"/>
                                            <ColumnDefinition Width="*"/>
                                        </Grid.ColumnDefinitions>
                                        <Border Grid.Column="0" Width="16" Height="16" HorizontalAlignment="Center" VerticalAlignment="Center">
                                        <TextBlock Text="&#xF093;" FontFamily="Segoe MDL2 Assets" FontSize="14" Foreground="#FF9800" HorizontalAlignment="Center" VerticalAlignment="Center" LineHeight="14" Padding="0" Margin="0,1,0,0"/>
                                    </Border>
                                        <TextBlock Grid.Column="1" Text="  Kernel &amp; Input" FontSize="12" VerticalAlignment="Center" LineHeight="14" Padding="0"/>
                                    </Grid>
                                    </TreeViewItem.Header>
                                </TreeViewItem>
                                <TreeViewItem x:Name="NavGPU" Style="{StaticResource NavItem}">
                                    <TreeViewItem.Header>
                                        <Grid UseLayoutRounding="True" SnapsToDevicePixels="True">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="20"/>
                                            <ColumnDefinition Width="*"/>
                                        </Grid.ColumnDefinitions>
                                        <Border Grid.Column="0" Width="16" Height="16" HorizontalAlignment="Center" VerticalAlignment="Center">
                                        <TextBlock Text="&#xE7F4;" FontFamily="Segoe MDL2 Assets" FontSize="14" Foreground="#4CAF50" HorizontalAlignment="Center" VerticalAlignment="Center" LineHeight="14" Padding="0" Margin="0,1,0,0"/>
                                    </Border>
                                        <TextBlock Grid.Column="1" Text="  GPU &amp; MSI" FontSize="12" VerticalAlignment="Center" LineHeight="14" Padding="0"/>
                                    </Grid>
                                    </TreeViewItem.Header>
                                </TreeViewItem>
                                <TreeViewItem x:Name="NavPrivacy" Style="{StaticResource NavItem}">
                                    <TreeViewItem.Header>
                                        <Grid UseLayoutRounding="True" SnapsToDevicePixels="True">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="20"/>
                                            <ColumnDefinition Width="*"/>
                                        </Grid.ColumnDefinitions>
                                        <Border Grid.Column="0" Width="16" Height="16" HorizontalAlignment="Center" VerticalAlignment="Center">
                                        <TextBlock Text="&#xE72E;" FontFamily="Segoe MDL2 Assets" FontSize="14" Foreground="#F44336" HorizontalAlignment="Center" VerticalAlignment="Center" LineHeight="14" Padding="0" Margin="0,1,0,0"/>
                                    </Border>
                                        <TextBlock Grid.Column="1" Text="  Privacy &amp; Telemetry" FontSize="12" VerticalAlignment="Center" LineHeight="14" Padding="0"/>
                                    </Grid>
                                    </TreeViewItem.Header>
                                </TreeViewItem>
                                <TreeViewItem x:Name="NavWinTweaks" Style="{StaticResource NavItem}">
                                    <TreeViewItem.Header>
                                        <Grid UseLayoutRounding="True" SnapsToDevicePixels="True">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="20"/>
                                            <ColumnDefinition Width="*"/>
                                        </Grid.ColumnDefinitions>
                                        <Border Grid.Column="0" Width="16" Height="16" HorizontalAlignment="Center" VerticalAlignment="Center">
                                        <TextBlock Text="&#xE115;" FontFamily="Segoe MDL2 Assets" FontSize="14" Foreground="#9898B0" HorizontalAlignment="Center" VerticalAlignment="Center" LineHeight="14" Padding="0" Margin="0,1,0,0"/>
                                    </Border>
                                        <TextBlock Grid.Column="1" Text="  Windows Tweaks" FontSize="12" VerticalAlignment="Center" LineHeight="14" Padding="0"/>
                                    </Grid>
                                    </TreeViewItem.Header>
                                </TreeViewItem>
                            </TreeViewItem>

                                <TreeViewItem x:Name="NavRunScript" Style="{StaticResource NavItem}"
                                          Margin="0,4,0,0">
                                <TreeViewItem.Header>
                                    <Grid UseLayoutRounding="True" SnapsToDevicePixels="True">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="20"/>
                                            <ColumnDefinition Width="*"/>
                                        </Grid.ColumnDefinitions>
                                        <Border Grid.Column="0" Width="16" Height="16" HorizontalAlignment="Center" VerticalAlignment="Center">
                                        <TextBlock Text="&#xE943;" FontFamily="Segoe MDL2 Assets" FontSize="14" Foreground="#7B5EA7" HorizontalAlignment="Center" VerticalAlignment="Center" LineHeight="14" Padding="0" Margin="0,1,0,0"/>
                                    </Border>
                                        <TextBlock Grid.Column="1" Text="  Run Script" FontSize="12" VerticalAlignment="Center" LineHeight="14" Padding="0"/>
                                    </Grid>
                                </TreeViewItem.Header>
                            </TreeViewItem>
                        </TreeView>
                    </ScrollViewer>
                </DockPanel>
            </Border>

            <!-- MAIN CONTENT PANEL -->
            <ScrollViewer Grid.Column="1" VerticalScrollBarVisibility="Auto" Padding="0"
                          Background="#0D0E1A">
                <Grid x:Name="ContentArea" Margin="20,16">

                    <!-- ===== QUICK CLEAN PAGE ===== -->
                    <StackPanel x:Name="PageQuickClean" Visibility="Visible">
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
                                    <TextBlock Text="&#xE74D;" FontFamily="Segoe MDL2 Assets" FontSize="20" Foreground="#4A90D9" VerticalAlignment="Center" Margin="0,3,0,0"/>
                                    <TextBlock Text="  Quick Clean" FontSize="20" FontWeight="Bold" Foreground="#E8E8F0" VerticalAlignment="Center"/>
                                </StackPanel>
                        <TextBlock Text="Gecici dosyalar, onbellekler ve gereksiz loglari hizla temizle."
                                   FontSize="12" Foreground="#9898B0" Margin="0,0,0,16"/>

                        <!-- ── CLEAN PROGRESS BAR ──────────────────────────── -->
                        <Border x:Name="CleanProgressContainer" Visibility="Collapsed"
                                Background="#1A1B35" CornerRadius="8" Padding="12,10" Margin="0,0,0,12"
                                BorderBrush="#2A2B4A" BorderThickness="1">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                                    <TextBlock x:Name="TxtCleanStatus" Text="Temizleniyor..."
                                               FontSize="11" Foreground="#9898B0" VerticalAlignment="Center"/>
                                    <TextBlock x:Name="TxtCleanPct" Text="  0%"
                                               FontSize="11" FontWeight="Bold" Foreground="#7B5EA7" VerticalAlignment="Center"/>
                                </StackPanel>
                                <Border x:Name="CleanProgressTrack" Height="6" CornerRadius="3"
                                        Background="#21234A" HorizontalAlignment="Stretch">
                                    <Border x:Name="CleanProgressFill" Height="6" CornerRadius="3"
                                            Background="#7B5EA7" HorizontalAlignment="Left" Width="0"/>
                                </Border>
                            </StackPanel>
                        </Border>

                        <WrapPanel>
                            <Button x:Name="BtnRunQuickClean" 
                                    Style="{StaticResource BtnAccent}" Margin="0,0,10,0" Height="36" FontSize="13">
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock Text="&#xE74D;" FontFamily="Segoe MDL2 Assets" FontSize="12" VerticalAlignment="Center" LineHeight="14" Padding="0" Margin="0,2,0,0"/>
                                <TextBlock Text=" Temizligi Baslat" FontSize="12" VerticalAlignment="Center" Margin="4,0,0,0"/>
                            </StackPanel>
                        </Button>
                            <Button x:Name="BtnSelectAllQC" 
                                    Style="{StaticResource BtnBase}" Height="36" Margin="0,0,10,0">
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock Text="&#xE73B;" FontFamily="Segoe MDL2 Assets" FontSize="12" VerticalAlignment="Center" LineHeight="14" Padding="0" Margin="0,2,0,0"/>
                                <TextBlock Text=" Tumunu Sec" FontSize="12" VerticalAlignment="Center" Margin="4,0,0,0"/>
                            </StackPanel>
                        </Button>
                            <Button x:Name="BtnDeselectAllQC" 
                                    Style="{StaticResource BtnBase}" Height="36">
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock Text="&#xE8E6;" FontFamily="Segoe MDL2 Assets" FontSize="12" VerticalAlignment="Center" LineHeight="14" Padding="0" Margin="0,2,0,0"/>
                                <TextBlock Text=" Temizle" FontSize="12" VerticalAlignment="Center" Margin="4,0,0,0"/>
                            </StackPanel>
                        </Button>
                        </WrapPanel>

                        <GroupBox Header="WINDOWS GECICI DOSYALAR" Margin="0,14,0,0">
                            <WrapPanel>
                                <CheckBox x:Name="ChkTempWin"   Content="%TEMP% klasoru"          Margin="0,4,20,4" ToolTip="%TEMP% klasorunu temizler. Gecici uygulama dosyalarini siler." IsChecked="True"/>
                                <CheckBox x:Name="ChkTempSys"   Content="Windows Temp (System)"   Margin="0,4,20,4" ToolTip="Windows sistem Temp klasorunu temizler (C:\Windows\Temp)." IsChecked="True"/>
                                <CheckBox x:Name="ChkPrefetch"  Content="Prefetch Dosyalari"       Margin="0,4,20,4" ToolTip="Prefetch dosyalarini temizler. Ilk acilis biraz yavaslar, sonra normale doner." IsChecked="True"/>
                                <CheckBox x:Name="ChkRecycleBin" Content="Geri Donusum Kutusu"    Margin="0,4,20,4" ToolTip="Geri Donusum Kutusunu kalici olarak bosaltir." IsChecked="True"/>
                                <CheckBox x:Name="ChkThumb"     Content="Thumbnail Cache"          Margin="0,4,20,4" ToolTip="Explorer thumbnail onbellegini temizler. Yeniden olusturulur." IsChecked="True"/>
                                <CheckBox x:Name="ChkFontCache" Content="Font Cache"               Margin="0,4,20,4" ToolTip="Font Cache servisini durdurur ve font onbellegini temizler." IsChecked="False"/>
                            </WrapPanel>
                        </GroupBox>
                        <GroupBox Header="TARAYICI ONBELLEKLERI">
                            <StackPanel>
                                <WrapPanel>
                                    <CheckBox x:Name="ChkChromeCache"  Content="Chrome"      Margin="0,4,20,4" ToolTip="Google Chrome cache temizler." IsChecked="False"/>
                                    <CheckBox x:Name="ChkEdgeCache"    Content="Edge"        Margin="0,4,20,4" ToolTip="Microsoft Edge cache temizler." IsChecked="False"/>
                                    <CheckBox x:Name="ChkFirefoxCache" Content="Firefox"     Margin="0,4,20,4" ToolTip="Mozilla Firefox cache temizler." IsChecked="False"/>
                                    <CheckBox x:Name="ChkBraveCache"   Content="Brave"       Margin="0,4,20,4" ToolTip="Brave Browser cache temizler." IsChecked="False"/>
                                    <CheckBox x:Name="ChkOperaCache"   Content="Opera / GX"  Margin="0,4,20,4" ToolTip="Opera ve Opera GX cache temizler." IsChecked="False"/>
                                    <CheckBox x:Name="ChkVivaldiCache" Content="Vivaldi"     Margin="0,4,20,4" ToolTip="Vivaldi Browser cache temizler." IsChecked="False"/>
                                    <CheckBox x:Name="ChkTorCache"     Content="Tor Browser" Margin="0,4,20,4" ToolTip="Tor Browser cache temizler." IsChecked="False"/>
                                </WrapPanel>
                                <TextBlock Text="Yalnizca kurulu uygulamalar aktif gorunur. Soluk gorunenler sisteminizde bulunamadi."
                                           FontSize="9" Foreground="#4A4A6A" Margin="0,4,0,0"/>
                            </StackPanel>
                        </GroupBox>
                        <GroupBox Header="ILETISIM &amp; SOSYAL UYGULAMALAR">
                            <StackPanel>
                                <WrapPanel>
                                    <CheckBox x:Name="ChkDiscordCache"  Content="Discord"   Margin="0,4,20,4" ToolTip="Discord Cache, Code Cache ve GPU Cache temizler." IsChecked="False"/>
                                    <CheckBox x:Name="ChkTelegramCache" Content="Telegram"  Margin="0,4,20,4" ToolTip="Telegram Desktop cache temizler." IsChecked="False"/>
                                    <CheckBox x:Name="ChkWhatsAppCache" Content="WhatsApp"  Margin="0,4,20,4" ToolTip="WhatsApp Desktop cache temizler." IsChecked="False"/>
                                    <CheckBox x:Name="ChkSlackCache"    Content="Slack"     Margin="0,4,20,4" ToolTip="Slack uygulama cache temizler." IsChecked="False"/>
                                    <CheckBox x:Name="ChkZoomCache"     Content="Zoom"      Margin="0,4,20,4" ToolTip="Zoom toplanti kayitlari ve cache temizler." IsChecked="False"/>
                                    <CheckBox x:Name="ChkTeamsCache"    Content="Teams"     Margin="0,4,20,4" ToolTip="Microsoft Teams cache ve log dosyalarini temizler." IsChecked="False"/>
                                    <CheckBox x:Name="ChkSkypeCache"    Content="Skype"     Margin="0,4,20,4" ToolTip="Skype cache temizler." IsChecked="False"/>
                                    <CheckBox x:Name="ChkSpotifyCache"  Content="Spotify"   Margin="0,4,20,4" ToolTip="Spotify muzik onbellegi ve veri dosyalarini temizler." IsChecked="False"/>
                                </WrapPanel>
                                <TextBlock Text="Yalnizca kurulu uygulamalar aktif gorunur."
                                           FontSize="9" Foreground="#4A4A6A" Margin="0,4,0,0"/>
                            </StackPanel>
                        </GroupBox>
                        <GroupBox Header="OYUN LAUNCHER ONBELLEKLERI">
                            <StackPanel>
                                <WrapPanel>
                                    <CheckBox x:Name="ChkSteamCache"      Content="Steam"           Margin="0,4,20,4" ToolTip="Steam shader ve HTML cache dosyalarini temizler." IsChecked="False"/>
                                    <CheckBox x:Name="ChkEpicCache"       Content="Epic Games"      Margin="0,4,20,4" ToolTip="Epic Games Launcher web cache temizler." IsChecked="False"/>
                                    <CheckBox x:Name="ChkGOGCache"        Content="GOG Galaxy"      Margin="0,4,20,4" ToolTip="GOG Galaxy cache ve log dosyalarini temizler." IsChecked="False"/>
                                    <CheckBox x:Name="ChkUbisoftCache"    Content="Ubisoft Connect" Margin="0,4,20,4" ToolTip="Ubisoft Connect cache dosyalarini temizler." IsChecked="False"/>
                                    <CheckBox x:Name="ChkEACache"         Content="EA Desktop"      Margin="0,4,20,4" ToolTip="EA Desktop uygulama cache temizler." IsChecked="False"/>
                                    <CheckBox x:Name="ChkXboxCache"       Content="Xbox App"        Margin="0,4,20,4" ToolTip="Xbox / GamingApp gecici dosyalarini temizler." IsChecked="False"/>
                                    <CheckBox x:Name="ChkBnetCache"       Content="Battle.net"      Margin="0,4,20,4" ToolTip="Battle.net Agent ve cache dosyalarini temizler." IsChecked="False"/>
                                    <CheckBox x:Name="ChkRockstarCache"   Content="Rockstar"        Margin="0,4,20,4" ToolTip="Rockstar Games Launcher cache temizler." IsChecked="False"/>
                                    <CheckBox x:Name="ChkRiotCache"       Content="Riot / LoL"      Margin="0,4,20,4" ToolTip="Riot Games ve League of Legends cache temizler." IsChecked="False"/>
                                    <CheckBox x:Name="ChkMinecraftCache"  Content="Minecraft"       Margin="0,4,20,4" ToolTip="Minecraft Launcher log ve gecici dosyalarini temizler." IsChecked="False"/>
                                </WrapPanel>
                                <TextBlock Text="Yalnizca kurulu uygulamalar aktif gorunur."
                                           FontSize="9" Foreground="#4A4A6A" Margin="0,4,0,0"/>
                            </StackPanel>
                        </GroupBox>
                        <GroupBox Header="LOG &amp; SISTEM TEMIZLIGI">
                            <WrapPanel>
                                <CheckBox x:Name="ChkDNSCache"     Content="DNS Cache Flush"             Margin="0,4,20,4" ToolTip="DNS cozumleme onbellegini temizler (ipconfig /flushdns). Ag sorunlarinda faydali." IsChecked="True"/>
                                <CheckBox x:Name="ChkEventLogs"   Content="Windows Event Logs"           Margin="0,4,20,4" ToolTip="Windows olay gunluklerini temizler. Sorun giderme kayitlari silinir." IsChecked="False"/>
                                <CheckBox x:Name="ChkCrashDumps"  Content="Crash Dumps (*.dmp)"          Margin="0,4,20,4" ToolTip="Sistem cokme dump dosyalarini (*.dmp) siler." IsChecked="True"/>
                                <CheckBox x:Name="ChkWinUpdCache" Content="Windows Update Cache"         Margin="0,4,20,4" ToolTip="Windows Update indirme onbellegini temizler. Guncelleme yeniden indirilir." IsChecked="False"/>
                                <CheckBox x:Name="ChkDeliveryOpt" Content="Delivery Optimization Files" Margin="0,4,20,4" ToolTip="Windows Delivery Optimization dosyalarini temizler." IsChecked="True"/>
                            </WrapPanel>
                        </GroupBox>
                        <!-- Space at bottom for terminal -->
                        <Border Height="12"/>
                    </StackPanel>

                    <!-- ===== ADVANCED CLEAN PAGE ===== -->
                    <StackPanel x:Name="PageAdvancedClean" Visibility="Collapsed">
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
                                    <TextBlock Text="&#xE74D;" FontFamily="Segoe MDL2 Assets" FontSize="20" Foreground="#FF9800" VerticalAlignment="Center" Margin="0,3,0,0"/>
                                    <TextBlock Text="  Advanced Clean" FontSize="20" FontWeight="Bold" Foreground="#E8E8F0" VerticalAlignment="Center"/>
                                </StackPanel>
                        <TextBlock Text="Gelismis sistem temizligi. Bazi islemler uzun sure alabilir, yeniden baslatma gerektirebilir."
                                   FontSize="12" Foreground="#FF9800" Margin="0,0,0,16"/>

                        <WrapPanel>
                            <Button x:Name="BtnRunAdvClean" 
                                    Style="{StaticResource BtnAccent}" Margin="0,0,10,0" Height="36" FontSize="13">
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock Text="&#xE74D;" FontFamily="Segoe MDL2 Assets" FontSize="12" VerticalAlignment="Center" LineHeight="14" Padding="0" Margin="0,2,0,0"/>
                                <TextBlock Text=" Gelismis Temizligi Baslat" FontSize="12" VerticalAlignment="Center" Margin="4,0,0,0"/>
                            </StackPanel>
                        </Button>
                        </WrapPanel>

                        <!-- ── ADVANCED CLEAN PROGRESS BAR ─────────────────── -->
                        <Border x:Name="AdvCleanProgressContainer" Visibility="Collapsed"
                                Background="#1A1B35" CornerRadius="8" Padding="12,10" Margin="0,12,0,0"
                                BorderBrush="#2A2B4A" BorderThickness="1">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                                    <TextBlock x:Name="TxtAdvCleanStatus" Text="Calistiriliyor..."
                                               FontSize="11" Foreground="#9898B0" VerticalAlignment="Center"/>
                                    <TextBlock x:Name="TxtAdvCleanStep" Text=""
                                               FontSize="11" Foreground="#FF9800" VerticalAlignment="Center" Margin="8,0,0,0"/>
                                </StackPanel>
                                <Border x:Name="AdvCleanProgressTrack" Height="6" CornerRadius="3"
                                        Background="#21234A" HorizontalAlignment="Stretch">
                                    <Border x:Name="AdvCleanProgressFill" Height="6" CornerRadius="3"
                                            Background="#FF9800" HorizontalAlignment="Left" Width="0"/>
                                </Border>
                            </StackPanel>
                        </Border>

                        <GroupBox Header="WINSxS &amp; SISTEM BILESENLERI" Margin="0,14,0,0">
                            <StackPanel>
                                <WrapPanel>
                                    <CheckBox x:Name="ChkWinSxS"      Content="WinSxS Cleanup (DISM)"          Margin="0,4,20,4" IsChecked="False"
                                              ToolTip="DISM ile WinSxS Component Store temizligi yapar. Eski Windows update kalintilari kaldirilir."/>
                                    <CheckBox x:Name="ChkSuperFetch"   Content="Disable SuperFetch / SysMain"   Margin="0,4,20,4" IsChecked="False"
                                              ToolTip="SysMain servisini devre disi birakir. SSD sistemlerde gereksiz RAM kullanimi azalir."/>
                                    <CheckBox x:Name="ChkHibernation"  Content="Hibernation Dosyasi Sil"        Margin="0,4,20,4" IsChecked="False"
                                              ToolTip="Hibernation ozelligini kapatir ve hiberfil.sys dosyasini siler. Disk alani kazanilir (RAM boyutu kadar)."/>
                                    <CheckBox x:Name="ChkPageFile"     Content="PageFile Temizle (Kapanista)"   Margin="0,4,20,4" IsChecked="False"
                                              ToolTip="Bilgisayar kapanirken PageFile dosyasini temizler. Gizlilik icin onerilir, kapanma suresi uzayabilir."/>
                                </WrapPanel>
                                <Border Background="#1A1A2E" CornerRadius="4" Padding="10,7" Margin="0,6,0,0">
                                    <StackPanel>
                                        <TextBlock FontSize="10" Foreground="#FF9800" TextWrapping="Wrap">
                                            <Run Text="[!] WinSxS Cleanup:"/>
                                            <Run Text=" Surec 10-20 dakika surebilir. Islem sirasinda bilgisayari kapatmayin." Foreground="#9898B0"/>
                                        </TextBlock>
                                        <TextBlock FontSize="10" Foreground="#FF9800" TextWrapping="Wrap" Margin="0,4,0,0">
                                            <Run Text="[!] Hibernation Sil:"/>
                                            <Run Text=" Hizi Baslat (Fast Startup) ozelligi de kapanir. Guc ayarlarindan yeniden etkinlestirilebilir." Foreground="#9898B0"/>
                                        </TextBlock>
                                        <TextBlock FontSize="10" Foreground="#4A90D9" TextWrapping="Wrap" Margin="0,4,0,0">
                                            <Run Text="[i] PageFile Temizle:"/>
                                            <Run Text=" 16 GB+ RAM&apos;e sahip sistemlerde gizlilik avantaji saglar, performans etkisi minimumdur." Foreground="#9898B0"/>
                                        </TextBlock>
                                    </StackPanel>
                                </Border>
                            </StackPanel>
                        </GroupBox>

                        <GroupBox Header="USB VE AYGIT GECMISI" Margin="0,0,0,0">
                            <StackPanel>
                                <WrapPanel>
                                    <CheckBox x:Name="ChkUSBHistory" Content="USB Baglanti Gecmisini Temizle" Margin="0,4,20,4" IsChecked="False"
                                              ToolTip="Registry USB gecmisi (USBSTOR, MountedDevices), setupapi.dev.log ve Windows Event log temizlenir. USB takili degilken calistirin."/>
                                </WrapPanel>
                                <Border Background="#1A1A2E" CornerRadius="4" Padding="10,7" Margin="0,6,0,0">
                                    <StackPanel>
                                        <TextBlock FontSize="10" Foreground="#FF9800" TextWrapping="Wrap">
                                            <Run Text="[!] USB Gecmisi:"/>
                                            <Run Text=" Tum USB aygitlarini cikarin, sonra bu secenegi calistirin." Foreground="#9898B0"/>
                                        </TextBlock>
                                        <TextBlock FontSize="10" Foreground="#4A90D9" TextWrapping="Wrap" Margin="0,4,0,0">
                                            <Run Text="[i] USB Watchdog:"/>
                                            <Run Text=" Sol panelde 0 Cihaz Bagli gordugunuzde bu secenegi etkinlestirin." Foreground="#9898B0"/>
                                        </TextBlock>
                                    </StackPanel>
                                </Border>
                            </StackPanel>
                        </GroupBox>

                        <GroupBox Header="SFC &amp; DISK ONARIMI">
                            <StackPanel>
                                <WrapPanel>
                                    <CheckBox x:Name="ChkSFC"          Content="SFC /scannow"            Margin="0,4,20,4" IsChecked="False"
                                              ToolTip="System File Checker calistirir. Bozuk veya eksik Windows sistem dosyalarini tarar ve onarir."/>
                                    <CheckBox x:Name="ChkDISM"         Content="DISM Health Restore"     Margin="0,4,20,4" IsChecked="False"
                                              ToolTip="DISM RestoreHealth calistirir. Windows Update uzerinden sistem imajini onarir. Internet baglantisi gerekir."/>
                                    <CheckBox x:Name="ChkDiskCleanup"  Content="Disk Cleanup (cleanmgr)" Margin="0,4,20,4" IsChecked="True"
                                              ToolTip="Windows Disk Cleanup aracini calistirir. Gecici dosyalar, thumbnails ve sistem dosyalari temizlenir."/>
                                </WrapPanel>
                                <Border Background="#1A1A2E" CornerRadius="4" Padding="10,7" Margin="0,6,0,0">
                                    <StackPanel>
                                        <TextBlock FontSize="10" Foreground="#FF9800" TextWrapping="Wrap">
                                            <Run Text="[!] SFC /scannow:"/>
                                            <Run Text=" Tarama 10-30 dakika surebilir. Islem tamamlanmadan pencereyi kapatmayin." Foreground="#9898B0"/>
                                        </TextBlock>
                                        <TextBlock FontSize="10" Foreground="#FF9800" TextWrapping="Wrap" Margin="0,4,0,0">
                                            <Run Text="[!] DISM Health Restore:"/>
                                            <Run Text=" SFC sonrasi calistirmaniz onerilir. 15-45 dakika surebilir, aktif internet baglantisi gerektirir." Foreground="#9898B0"/>
                                        </TextBlock>
                                        <TextBlock FontSize="10" Foreground="#4CAF50" TextWrapping="Wrap" Margin="0,4,0,0">
                                            <Run Text="[v] Onerilen siralama:"/>
                                            <Run Text=" Once DISM, ardindan SFC calistirin. Eger sonuc degismiyorsa SFC tek basina yeterlidir." Foreground="#9898B0"/>
                                        </TextBlock>
                                    </StackPanel>
                                </Border>
                            </StackPanel>
                        </GroupBox>

                        <Border Height="12"/>
                    </StackPanel>

                    <!-- ===== PERFORMANCE PAGE ===== -->
                    <StackPanel x:Name="PagePerformance" Visibility="Collapsed">
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
                                    <TextBlock Text="&#xE945;" FontFamily="Segoe MDL2 Assets" FontSize="20" Foreground="#7B5EA7" VerticalAlignment="Center" Margin="0,3,0,0"/>
                                    <TextBlock Text="  Performance" FontSize="20" FontWeight="Bold" Foreground="#E8E8F0" VerticalAlignment="Center"/>
                                </StackPanel>
                        <TextBlock Text="CPU, guc plani ve zamanlayici optimizasyonlari."
                                   FontSize="12" Foreground="#9898B0" Margin="0,0,0,16"/>

                        <WrapPanel>
                            <Button x:Name="BtnApplyPerf" 
                                    Style="{StaticResource BtnAccent}" Margin="0,0,10,0" Height="36">
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock Text="&#xE74E;" FontFamily="Segoe MDL2 Assets" FontSize="12" VerticalAlignment="Center" LineHeight="14" Padding="0" Margin="0,2,0,0"/>
                                <TextBlock Text=" Uygula" FontSize="12" VerticalAlignment="Center" Margin="4,0,0,0"/>
                            </StackPanel>
                        </Button>
                            <Button x:Name="BtnBackupPerf"
                                    Style="{StaticResource BtnBase}" Height="36"
                                    ToolTip="Performans ile ilgili registry anahtarlarını _Files\Backups klasörüne yedekle">
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock Text="&#xE74E;" FontFamily="Segoe MDL2 Assets" FontSize="12" VerticalAlignment="Center" LineHeight="14" Padding="0" Margin="0,2,0,0"/>
                                <TextBlock Text=" Backup" FontSize="12" VerticalAlignment="Center" Margin="4,0,0,0"/>
                            </StackPanel>
                        </Button>
                        </WrapPanel>

                        <Border x:Name="PerfProgressContainer" Visibility="Collapsed"
                                Background="#1A1B35" CornerRadius="8" Padding="12,10" Margin="0,10,0,0"
                                BorderBrush="#2A2B4A" BorderThickness="1">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                                    <TextBlock x:Name="PerfProgressStatus" Text="Uygulanıyor..."
                                               FontSize="11" Foreground="#E8E8F0" VerticalAlignment="Center"/>
                                    <TextBlock x:Name="PerfProgressStep" Text=""
                                               FontSize="11" Foreground="#7B5EA7" VerticalAlignment="Center" Margin="6,0,0,0"/>
                                </StackPanel>
                                <Border x:Name="PerfProgressTrack" Height="5" CornerRadius="3" Background="#2A2B4A">
                                    <Border x:Name="PerfProgressFill" HorizontalAlignment="Left"
                                            Background="#7B5EA7" Height="5" CornerRadius="3" Width="0"/>
                                </Border>
                            </StackPanel>
                        </Border>

                        <GroupBox Header="GUC PLANI" Margin="0,14,0,0">
                            <StackPanel>
                                <WrapPanel Margin="0,0,0,8">
                                    <Button x:Name="BtnPlanBitsum"     Style="{StaticResource BtnBase}" Margin="0,0,8,0" Height="30" FontSize="11"
                                            ToolTip="Bitsum Highest Performance — maksimum performans güç planı">
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock Text="&#xE945;" FontFamily="Segoe MDL2 Assets" FontSize="12" VerticalAlignment="Center" LineHeight="14" Padding="0" Margin="0,2,0,0"/>
                                <TextBlock Text=" Bitsum Highest" FontSize="12" VerticalAlignment="Center" Margin="4,0,0,0"/>
                            </StackPanel>
                        </Button>
                                    <Button x:Name="BtnPlanHybred"     Style="{StaticResource BtnBase}" Margin="0,0,8,0" Height="30" FontSize="11"
                                            ToolTip="HybredLowLatencyHighPerf.pow — Maksimum düşük gecikme + yüksek performans">
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock Text="&#xE9A1;" FontFamily="Segoe MDL2 Assets" FontSize="12" VerticalAlignment="Center" LineHeight="14" Padding="0" Margin="0,2,0,0"/>
                                <TextBlock Text=" Hybred HighPerf" FontSize="12" VerticalAlignment="Center" Margin="4,0,0,0"/>
                            </StackPanel>
                        </Button>
                                    <Button x:Name="BtnPlanHybred2"    Style="{StaticResource BtnBase}" Margin="0,0,8,0" Height="30" FontSize="11"
                                            ToolTip="HybredLowLatencyBalanced.pow — Oyun + streaming dengesi için düşük gecikme">
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock Text="&#xE7B5;" FontFamily="Segoe MDL2 Assets" FontSize="12" VerticalAlignment="Center" LineHeight="14" Padding="0" Margin="0,2,0,0"/>
                                <TextBlock Text=" Hybred Balanced" FontSize="12" VerticalAlignment="Center" Margin="4,0,0,0"/>
                            </StackPanel>
                        </Button>
                                    <Button x:Name="BtnPlanUlti"             Style="{StaticResource BtnBase}"   Margin="0,0,8,0" Height="30" FontSize="11">
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock Text="&#xE7F4;" FontFamily="Segoe MDL2 Assets" FontSize="12" VerticalAlignment="Center" LineHeight="14" Padding="0" Margin="0,2,0,0"/>
                                <TextBlock Text=" Ultimate" FontSize="12" VerticalAlignment="Center" Margin="4,0,0,0"/>
                            </StackPanel>
                        </Button>
                                    <Button x:Name="BtnPlanBalanced"         Style="{StaticResource BtnBase}"   Margin="0,0,8,0" Height="30" FontSize="11">
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock Text="&#xE7B5;" FontFamily="Segoe MDL2 Assets" FontSize="12" VerticalAlignment="Center" LineHeight="14" Padding="0" Margin="0,2,0,0"/>
                                <TextBlock Text=" Balanced" FontSize="12" VerticalAlignment="Center" Margin="4,0,0,0"/>
                            </StackPanel>
                        </Button>
                                    <Button x:Name="BtnPlanDefault"           Style="{StaticResource BtnBase}"                    Height="30" FontSize="11">
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock Text="&#xE728;" FontFamily="Segoe MDL2 Assets" FontSize="12" VerticalAlignment="Center" LineHeight="14" Padding="0" Margin="0,2,0,0"/>
                                <TextBlock Text=" Default" FontSize="12" VerticalAlignment="Center" Margin="4,0,0,0"/>
                            </StackPanel>
                        </Button>
                                </WrapPanel>
                                <TextBlock x:Name="TxtActivePlan" Text="Aktif plan: Taranıyor..." FontSize="10" Foreground="#9898B0" Margin="0,0,0,6"/>
                                <CheckBox x:Name="ChkHPET"          Content="HPET Devre Disi (bcdedit)"           ToolTip="HPET zamanlayici devre disi birakilir. Dusuk CPU latency saglar." IsChecked="True"  Margin="0,4,20,4"/>
                                <CheckBox x:Name="ChkTimerRes"      Content="Timer Resolution 0.5ms"              ToolTip="Zamanlayici cozunurlugunu 0.5ms yapar. Daha hassas zamanlama saglar." IsChecked="False" Margin="0,4,20,4"/>
                                <CheckBox x:Name="ChkCpuPriority"   Content="CPU Priority Boost"                  ToolTip="CPU ve GPU oyun onceliklerini arttirir. SystemResponsiveness=0 yapilir." IsChecked="True"  Margin="0,4,20,4"/>
                            </StackPanel>
                        </GroupBox>

                        <GroupBox Header="WIN32 PRIORITY SEPARATION">
                            <StackPanel>
                                <WrapPanel Margin="0,0,0,8">
                                    <Button x:Name="BtnW32BestFPS"      Style="{StaticResource BtnAccent}" Margin="0,0,8,0" Height="30" FontSize="11" ToolTip="Latency odakli, en dusuk input lag">
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock Text="&#xE945;" FontFamily="Segoe MDL2 Assets" FontSize="12" VerticalAlignment="Center" LineHeight="14" Padding="0" Margin="0,2,0,0"/>
                                <TextBlock Text=" BestFPS (0x14)" FontSize="12" VerticalAlignment="Center" Margin="4,0,0,0"/>
                            </StackPanel>
                        </Button>
                                    <Button x:Name="BtnW32Balanced"    Style="{StaticResource BtnBase}"   Margin="0,0,8,0" Height="30" FontSize="11">
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock Text="&#xE7B5;" FontFamily="Segoe MDL2 Assets" FontSize="12" VerticalAlignment="Center" LineHeight="14" Padding="0" Margin="0,2,0,0"/>
                                <TextBlock Text=" Balanced (0x18)" FontSize="12" VerticalAlignment="Center" Margin="4,0,0,0"/>
                            </StackPanel>
                        </Button>
                                    <Button x:Name="BtnW32Default"      Style="{StaticResource BtnBase}"   Height="30" FontSize="11">
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock Text="&#xE728;" FontFamily="Segoe MDL2 Assets" FontSize="12" VerticalAlignment="Center" LineHeight="14" Padding="0" Margin="0,2,0,0"/>
                                <TextBlock Text=" Default (0x26)" FontSize="12" VerticalAlignment="Center" Margin="4,0,0,0"/>
                            </StackPanel>
                        </Button>
                                </WrapPanel>
                                <TextBlock Text="Win32PrioritySeparation, CPU zamanlamasini foreground/background surecler arasinda boler. BestFPS maksimum foreground onceligi verir."
                                           FontSize="10" Foreground="#9898B0" TextWrapping="Wrap"/>
                            </StackPanel>
                        </GroupBox>

                        <GroupBox Header="SERVIS OPTIMIZASYONU">
                            <WrapPanel>
                                <CheckBox x:Name="ChkSysMain"     Content="SysMain (SuperFetch) Kapat"  Margin="0,4,20,4" ToolTip="SysMain (Superfetch) servisini devre disi birakir." IsChecked="False"/>
                                <CheckBox x:Name="ChkWSearch"     Content="Windows Search Kapat"        Margin="0,4,20,4" ToolTip="Windows Search indexleme servisini devre disi birakir." IsChecked="False"/>
                                <CheckBox x:Name="ChkWUpdate"     Content="Windows Update Gecikmeli"    Margin="0,4,20,4" ToolTip="Feature update'leri 365 gün, quality update'leri 7 gün erteler. Otomatik yeniden baslatmayi engeller." IsChecked="False"/>
                                <CheckBox x:Name="ChkGameMode"    Content="Game Mode Etkin"             Margin="0,4,20,4" ToolTip="Windows Game Mode aktiflestirilir. Oyun sirasinda arka plan kisitlanir." IsChecked="True"/>
                                <CheckBox x:Name="ChkHwAccel"     Content="Hardware-Accelerated GPU Scheduling" Margin="0,4,20,4" ToolTip="Hardware-Accelerated GPU Scheduling aktiflestirilir. Guncel GPU gerektirir." IsChecked="True"/>
                            </WrapPanel>
                        </GroupBox>

                        <GroupBox Header="RAM OPTIMIZASYONU (ISLC)" Margin="0,8,0,0">
                            <StackPanel>
                                <WrapPanel>
                                    <CheckBox x:Name="ChkEmptyRAM"    Content="Standby List Temizle"  Margin="0,4,20,4" IsChecked="True"
                                              ToolTip="ISLC -purge ile RAM standby listesini anlık temizler. Oyun/render sonrası performans artışı sağlar."/>
                                    <CheckBox x:Name="ChkModifiedRAM" Content="Modified List Temizle" Margin="0,4,20,4" IsChecked="True"
                                              ToolTip="ISLC -runonce ile modified bellek sayfalarını temizler."/>
                                </WrapPanel>
                                <Border Background="#1A1A2E" CornerRadius="4" Padding="10,7" Margin="0,6,0,0">
                                    <StackPanel>
                                        <TextBlock FontSize="10" Foreground="#7B5EA7" TextWrapping="Wrap">
                                            <Run Text="[i] Intelligent Standby List Cleaner (ISLC):"/>
                                        </TextBlock>
                                        <TextBlock FontSize="10" Foreground="#9898B0" TextWrapping="Wrap" Margin="0,3,0,0">
                                            <Run Text="    ISLC her Windows açılışında otomatik çalışacak şekilde Görev Zamanlayıcı&apos;ya eklenir."/>
                                        </TextBlock>
                                        <TextBlock FontSize="10" Foreground="#9898B0" TextWrapping="Wrap" Margin="0,2,0,0">
                                            <Run Text="    Exe: _Files\ISLC\Intelligent standby list cleaner ISLC.exe"/>
                                        </TextBlock>
                                    </StackPanel>
                                </Border>
                            </StackPanel>
                        </GroupBox>
                        <Border Height="12"/>
                    </StackPanel>

                    <!-- ===== NETWORK PAGE ===== -->
                    <StackPanel x:Name="PageNetwork" Visibility="Collapsed">
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
                                    <TextBlock Text="&#xEC27;" FontFamily="Segoe MDL2 Assets" FontSize="20" Foreground="#4A90D9" VerticalAlignment="Center" Margin="0,3,0,0"/>
                                    <TextBlock Text="  Network" FontSize="20" FontWeight="Bold" Foreground="#E8E8F0" VerticalAlignment="Center"/>
                                </StackPanel>
                        <TextBlock Text="TCP/IP yigini, ag gecikmesi ve adaptor optimizasyonlari."
                                   FontSize="12" Foreground="#9898B0" Margin="0,0,0,16"/>

                        <WrapPanel>
                            <Button x:Name="BtnApplyNetwork" 
                                    Style="{StaticResource BtnAccent}" Margin="0,0,10,0" Height="36">
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock Text="&#xE74E;" FontFamily="Segoe MDL2 Assets" FontSize="12" VerticalAlignment="Center" LineHeight="14" Padding="0" Margin="0,2,0,0"/>
                                <TextBlock Text=" Uygula" FontSize="12" VerticalAlignment="Center" Margin="4,0,0,0"/>
                            </StackPanel>
                        </Button>
                            <Button x:Name="BtnResetNetwork" 
                                    Style="{StaticResource BtnDanger}" Height="36" Margin="0,0,10,0">
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock Text="&#xE72C;" FontFamily="Segoe MDL2 Assets" FontSize="12" VerticalAlignment="Center" LineHeight="14" Padding="0" Margin="0,2,0,0"/>
                                <TextBlock Text=" TCP/IP Sifirla" FontSize="12" VerticalAlignment="Center" Margin="4,0,0,0"/>
                            </StackPanel>
                        </Button>
                            <Button x:Name="BtnBackupNetwork"
                                    Style="{StaticResource BtnBase}" Height="36"
                                    ToolTip="Ağ ayarları registry anahtarlarını _Files\Backups klasörüne yedekle">
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock Text="&#xE74E;" FontFamily="Segoe MDL2 Assets" FontSize="12" VerticalAlignment="Center" LineHeight="14" Padding="0" Margin="0,2,0,0"/>
                                <TextBlock Text=" Backup" FontSize="12" VerticalAlignment="Center" Margin="4,0,0,0"/>
                            </StackPanel>
                        </Button>
                        </WrapPanel>

                        <Border x:Name="NetProgressContainer" Visibility="Collapsed"
                                Background="#1A1B35" CornerRadius="8" Padding="12,10" Margin="0,10,0,0"
                                BorderBrush="#2A2B4A" BorderThickness="1">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                                    <TextBlock x:Name="NetProgressStatus" Text="Uygulanıyor..."
                                               FontSize="11" Foreground="#E8E8F0" VerticalAlignment="Center"/>
                                    <TextBlock x:Name="NetProgressStep" Text=""
                                               FontSize="11" Foreground="#4A90D9" VerticalAlignment="Center" Margin="6,0,0,0"/>
                                </StackPanel>
                                <Border x:Name="NetProgressTrack" Height="5" CornerRadius="3" Background="#2A2B4A">
                                    <Border x:Name="NetProgressFill" HorizontalAlignment="Left"
                                            Background="#4A90D9" Height="5" CornerRadius="3" Width="0"/>
                                </Border>
                            </StackPanel>
                        </Border>

                        <GroupBox Header="TCP/IP OPTIMIZASYONU" Margin="0,14,0,0">
                            <WrapPanel>
                                <CheckBox x:Name="ChkAutoTuning"   Content="Autotuning Normal'e Al"              Margin="0,4,20,4" ToolTip="TCP Receive Window Auto-Tuning = Normal. Kapatmak hizi 10-20Mbps'e kitler! Normal en iyi ayardir." IsChecked="True"/>
                                <CheckBox x:Name="ChkECN"          Content="ECN Capability Kapat"               Margin="0,4,20,4" ToolTip="ECN (Explicit Congestion Notification) devre disi birakilir." IsChecked="True"/>
                                <CheckBox x:Name="ChkRSC"          Content="RSC (Receive Segment Coalescing) Kapat" Margin="0,4,20,4" ToolTip="Receive Segment Coalescing devre disi birakilir. Latency duser." IsChecked="True"/>
                                <CheckBox x:Name="ChkCongestion"   Content="Congestion → CUBIC (Modern)"        Margin="0,4,20,4" ToolTip="TCP congestion algoritmasi CUBIC olarak ayarlanir. CTCP eskidi, CUBIC daha iyi paket kaybi/gecikme yonetimi saglar." IsChecked="True"/>
                                <CheckBox x:Name="ChkNetThrottle"  Content="NetworkThrottlingIndex Kaldir"       Margin="0,4,20,4" ToolTip="Network throttling devre disi birakilir. Oyun ve streaming icin." IsChecked="True"/>
                                <CheckBox x:Name="ChkNagle"        Content="Nagle Algoritmasi Kapat"             Margin="0,4,20,4" ToolTip="Nagle algoritmasi devre disi birakilir. TCP latency duser." IsChecked="True"/>
                                <CheckBox x:Name="ChkTCPNoDelay"   Content="TCP No Delay"                        Margin="0,4,20,4" ToolTip="TCP NoDelay aktiflestirilir. Kucuk paketler gecikmeden gonderilir." IsChecked="True"/>
                                <CheckBox x:Name="ChkTCPACKFreq"   Content="TcpAckFrequency = 1"                 Margin="0,4,20,4" ToolTip="TCP ACK frekansini optimize eder. Latency azalir." IsChecked="True"/>
                            </WrapPanel>
                        </GroupBox>

                        <GroupBox Header="NIC ADAPTOR OPTIMIZASYONU (Get-NetAdapter)">
                            <StackPanel>
                                <WrapPanel Margin="0,0,0,8">
                                    <Button x:Name="BtnScanAdapters" 
                                            Style="{StaticResource BtnBase}" Height="28" FontSize="11" Margin="0,0,8,0">
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock Text="&#xE72E;" FontFamily="Segoe MDL2 Assets" FontSize="12" VerticalAlignment="Center" LineHeight="14" Padding="0" Margin="0,2,0,0"/>
                                <TextBlock Text=" Adaptorleri Tara" FontSize="12" VerticalAlignment="Center" Margin="4,0,0,0"/>
                            </StackPanel>
                        </Button>
                                </WrapPanel>
                                <CheckBox x:Name="ChkRSS"         Content="RSS (Receive-Side Scaling) Etkin"   Margin="0,4,20,4" ToolTip="Receive Side Scaling aktiflestirilir. Ag trafigi coklu CPU cekirdegine dagitilir." IsChecked="True"/>
                                <CheckBox x:Name="ChkFlowCtrl"    Content="Flow Control Kapat"                  Margin="0,4,20,4" ToolTip="NIC flow control devre disi birakilir." IsChecked="True"/>
                                <CheckBox x:Name="ChkIntMod"      Content="Interrupt Moderation → Adaptive"     Margin="0,4,20,4" ToolTip="Interrupt Moderation Adaptive moda alinir. Tamamen kapatmak CPU'yu %100'e firlatabilir. Adaptive en iyi dengedir." IsChecked="True"/>
                                <CheckBox x:Name="ChkGreenEth"    Content="Green Ethernet / EEE Kapat"          Margin="0,4,20,4" ToolTip="Green Ethernet guc tasarrufu devre disi birakilir." IsChecked="True"/>
                                <CheckBox x:Name="ChkGigaLite"    Content="Giga Lite Kapat"                     Margin="0,4,20,4" ToolTip="Gigabit Lite modu devre disi birakilir." IsChecked="True"/>
                                <CheckBox x:Name="ChkAdaptInter"  Content="Adaptive Inter-Frame Spacing Kapat"  Margin="0,4,20,4" ToolTip="Bazi NIC sürücülerinde bulunan adaptif kare araligi modunu devre disi birakir. Latency tutarliligini arttirir." IsChecked="False"/>
                                <TextBlock x:Name="TxtAdapterInfo" Text="Adaptor bilgisi icin &apos;Adaptorleri Tara&apos; tikla."
                                           FontSize="10" Foreground="#9898B0" Margin="0,6,0,0"/>
                            </StackPanel>
                        </GroupBox>

                        <GroupBox Header="DNS">
                            <WrapPanel>
                                <CheckBox x:Name="ChkDNSPrefetch" Content="DNS Cache Optimizasyonu"       Margin="0,4,20,4" ToolTip="DNS istemci onbellegini optimize eder: negatif TTL ayarlanir, maksimum cache buyuklugu arttirilir. Ag gecikmesi azalir." IsChecked="True"/>
                                <CheckBox x:Name="ChkMDNS"        Content="mDNS Kapat"               Margin="0,4,20,4" ToolTip="mDNS devre disi birakilir. DIKKAT: Ev aginda Chromecast, akilli TV ve yazici kesfini kor eder! Sadece guvenlik odakli ortamlar icin." IsChecked="False"/>
                                <CheckBox x:Name="ChkLLMNR"       Content="LLMNR Kapat"              Margin="0,4,20,4" ToolTip="LLMNR devre disi birakilir. Ag guvenligi artar." IsChecked="True"/>
                            </WrapPanel>
                        </GroupBox>
                        <Border Height="12"/>
                    </StackPanel>

                    <!-- ===== KERNEL &amp; INPUT PAGE ===== -->
                    <StackPanel x:Name="PageKernel" Visibility="Collapsed">
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
                                    <TextBlock Text="&#xF093;" FontFamily="Segoe MDL2 Assets" FontSize="20" Foreground="#FF9800" VerticalAlignment="Center" Margin="0,3,0,0"/>
                                    <TextBlock Text="  Kernel &amp; Input" FontSize="20" FontWeight="Bold" Foreground="#E8E8F0" VerticalAlignment="Center"/>
                                </StackPanel>
                        <TextBlock Text="Kernel guvenlik ozellikleri, bellek yonetimi ve giris aygiti optimizasyonlari."
                                   FontSize="12" Foreground="#FF9800" Margin="0,0,0,16"/>

                        <WrapPanel>
                            <Button x:Name="BtnApplyKernel" 
                                    Style="{StaticResource BtnAccent}" Margin="0,0,10,0" Height="36">
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock Text="&#xE74E;" FontFamily="Segoe MDL2 Assets" FontSize="12" VerticalAlignment="Center" LineHeight="14" Padding="0" Margin="0,2,0,0"/>
                                <TextBlock Text=" Uygula" FontSize="12" VerticalAlignment="Center" Margin="4,0,0,0"/>
                            </StackPanel>
                        </Button>
                            <Button x:Name="BtnBackupKernel"
                                    Style="{StaticResource BtnBase}" Height="36"
                                    ToolTip="Kernel &amp; Input registry anahtarlarını _Files\Backups klasörüne yedekle">
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock Text="&#xE74E;" FontFamily="Segoe MDL2 Assets" FontSize="12" VerticalAlignment="Center" LineHeight="14" Padding="0" Margin="0,2,0,0"/>
                                <TextBlock Text=" Backup" FontSize="12" VerticalAlignment="Center" Margin="4,0,0,0"/>
                            </StackPanel>
                        </Button>
                        </WrapPanel>


                        <Border x:Name="KernProgressContainer" Visibility="Collapsed"
                                Background="#1A1B35" CornerRadius="8" Padding="12,10" Margin="0,10,0,0"
                                BorderBrush="#2A2B4A" BorderThickness="1">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                                    <TextBlock x:Name="KernProgressStatus" Text="Uygulanıyor..."
                                               FontSize="11" Foreground="#E8E8F0" VerticalAlignment="Center"/>
                                    <TextBlock x:Name="KernProgressStep" Text=""
                                               FontSize="11" Foreground="#E91E63" VerticalAlignment="Center" Margin="6,0,0,0"/>
                                </StackPanel>
                                <Border x:Name="KernProgressTrack" Height="5" CornerRadius="3" Background="#2A2B4A">
                                    <Border x:Name="KernProgressFill" HorizontalAlignment="Left"
                                            Background="#E91E63" Height="5" CornerRadius="3" Width="0"/>
                                </Border>
                            </StackPanel>
                        </Border>

                        <GroupBox Header="GUVENLIK / SANALLASTIRMA (DIKKATLI OL)" Margin="0,14,0,0">
                            <StackPanel>
                                <Border Background="#2A1010" CornerRadius="4" Padding="8,6" Margin="0,0,0,8">
                                    <StackPanel Orientation="Horizontal">
                                        <TextBlock Text="&#xE7BA;" FontFamily="Segoe MDL2 Assets" Foreground="#FF9800" VerticalAlignment="Center" Margin="0,2,0,0"/>
                                        <TextBlock Text="  Bu ayarlar sistem guvenligini etkiler. Yedek alinmasi onerilir."
                                                   FontSize="11" Foreground="#FF9800" VerticalAlignment="Center"/>
                                    </StackPanel>
                                </Border>
                                <CheckBox x:Name="ChkVBS"         Content="VBS / Core Isolation Kapat"             Margin="0,4,20,4" ToolTip="VBS devre disi birakilir. Yeniden baslatma gerektirir. GUVENLIK RISKI!" IsChecked="False"/>
                                <CheckBox x:Name="ChkDMAProtect"  Content="DMA Protection Kapat (Kernel DMA)"      Margin="0,4,20,4" ToolTip="DMA Korumasi devre disi birakilir. GUVENLIK RISKI!" IsChecked="False"/>
                                <CheckBox x:Name="ChkSpectre"     Content="Spectre/Meltdown Mitigations Kapat"     Margin="0,4,20,4" ToolTip="Spectre/Meltdown korumasi devre disi birakilir. GUVENLIK RISKI!" IsChecked="False"/>
                                <CheckBox x:Name="ChkCFG"         Content="Control Flow Guard (CFG) Kapat"         Margin="0,4,20,4" ToolTip="Control Flow Guard devre disi birakilir. GUVENLIK RISKI!" IsChecked="False"/>
                                <CheckBox x:Name="ChkHVCI"        Content="HVCI (Hypervisor Protected Code) Kapat" Margin="0,4,20,4" ToolTip="Hypervisor Protected Code Integrity devre disi birakilir." IsChecked="False"/>
                            </StackPanel>
                        </GroupBox>

                        <GroupBox Header="BELLEK OPTIMIZASYONU">
                            <WrapPanel>
                                <CheckBox x:Name="ChkLargePages"    Content="Large Pages Etkin"                  Margin="0,4,20,4" ToolTip="Large Pages destegi aktiflestirilir. Bellek yogun uygulamalarda faydali." IsChecked="False"/>
                                <CheckBox x:Name="ChkContMem"       Content="DX Contiguous Memory Allocation"    Margin="0,4,20,4" ToolTip="DirectX Contiguous Memory Allocation etkinlestirilir." IsChecked="True"/>
                                <!-- SecondLevelDataCache KALDIRILDI: Windows XP'den kalma plasebo. Modern kernel CPU cache'i donanim seviyesinde yonetir. -->
                                <CheckBox x:Name="ChkPagingFiles"   Content="PageFile Optimize"                  Margin="0,4,20,4" ToolTip="PageFile boyutunu sistem yonetimine birakir (otomatik). Manuel olarak kotu ayarlanmis pagefile'larda performans kazanimi saglar." IsChecked="False"/>
                            </WrapPanel>
                        </GroupBox>

                        <GroupBox Header="MOUSE &amp; KEYBOARD INPUT BUFFER (MarkC Fix)">
                            <StackPanel>
                                <TextBlock Text="MouseDataQueueSize ve KeyboardDataQueueSize, input buffer boyutunu belirler. Dusuk deger = daha az gecikme."
                                           FontSize="10" Foreground="#9898B0" TextWrapping="Wrap" Margin="0,0,0,8"/>
                                <WrapPanel>
                                    <CheckBox x:Name="ChkMouseBuffer" Content="Mouse Buffer Optimize (MarkC)"  Margin="0,4,20,4" ToolTip="Mouse veri kuyrugu boyutu optimize edilir (MarkC Fix)." IsChecked="True"/>
                                    <CheckBox x:Name="ChkKbBuffer"    Content="Keyboard Buffer Optimize"       Margin="0,4,20,4" ToolTip="Klavye veri kuyrugu boyutu optimize edilir." IsChecked="True"/>
                                    <CheckBox x:Name="ChkRawInput"    Content="Raw Input Thread Boost"         Margin="0,4,20,4" ToolTip="Raw Input modu aktiflestirilir. Daha hassas fare girisi saglar." IsChecked="True"/>
                                    <CheckBox x:Name="ChkMouseSmooth" Content="Mouse Smoothing Kapat"          Margin="0,4,20,4" ToolTip="Mouse smoothing egrileri optimize edilir (MarkC Fix)." IsChecked="True"/>
                                    <CheckBox x:Name="ChkMouseAccel"  Content="Mouse Acceleration Kapat (EPP)" Margin="0,4,20,4" ToolTip="Mouse Acceleration (Enhanced Pointer Precision) devre disi birakilir." IsChecked="True"/>
                                </WrapPanel>
                            </StackPanel>
                        </GroupBox>
                        <Border Height="12"/>
                    </StackPanel>

                    <!-- ===== GPU &amp; MSI PAGE ===== -->
                    <StackPanel x:Name="PageGPU" Visibility="Collapsed">
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
                                    <TextBlock Text="&#xE7F4;" FontFamily="Segoe MDL2 Assets" FontSize="20" Foreground="#4CAF50" VerticalAlignment="Center" Margin="0,3,0,0"/>
                                    <TextBlock Text="  GPU &amp; MSI Mode" FontSize="20" FontWeight="Bold" Foreground="#E8E8F0" VerticalAlignment="Center"/>
                                </StackPanel>
                        <TextBlock Text="Ekran karti gecikme optimizasyonlari ve MSI (Message Signaled Interrupts)."
                                   FontSize="12" Foreground="#9898B0" Margin="0,0,0,16"/>

                        <WrapPanel>
                            <Button x:Name="BtnDetectGPU" 
                                    Style="{StaticResource BtnBase}" Margin="0,0,10,0" Height="36">
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock Text="&#xE72E;" FontFamily="Segoe MDL2 Assets" FontSize="12" VerticalAlignment="Center" LineHeight="14" Padding="0" Margin="0,2,0,0"/>
                                <TextBlock Text=" GPU Algila" FontSize="12" VerticalAlignment="Center" Margin="4,0,0,0"/>
                            </StackPanel>
                        </Button>
                            <Button x:Name="BtnApplyGPU" 
                                    Style="{StaticResource BtnAccent}" Margin="0,0,10,0" Height="36">
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock Text="&#xE74E;" FontFamily="Segoe MDL2 Assets" FontSize="12" VerticalAlignment="Center" LineHeight="14" Padding="0" Margin="0,2,0,0"/>
                                <TextBlock Text=" Uygula" FontSize="12" VerticalAlignment="Center" Margin="4,0,0,0"/>
                            </StackPanel>
                        </Button>
                            <Button x:Name="BtnBackupGPU"
                                    Style="{StaticResource BtnBase}" Height="36"
                                    ToolTip="GPU &amp; MSI registry anahtarlarını _Files\Backups klasörüne yedekle">
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock Text="&#xE74E;" FontFamily="Segoe MDL2 Assets" FontSize="12" VerticalAlignment="Center" LineHeight="14" Padding="0" Margin="0,2,0,0"/>
                                <TextBlock Text=" Backup" FontSize="12" VerticalAlignment="Center" Margin="4,0,0,0"/>
                            </StackPanel>
                        </Button>
                        </WrapPanel>

                        <Border x:Name="GpuInfoBorder" Background="#1A1B35" CornerRadius="8" Padding="14,10"
                                Margin="0,14,0,0" BorderBrush="#2A2B4A" BorderThickness="1">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                    <TextBlock Text="&#xE7F4;" FontFamily="Segoe MDL2 Assets"
                                               FontSize="10" FontWeight="SemiBold" Foreground="#9898B0" VerticalAlignment="Center"/>
                                    <TextBlock Text="  GPU BILGISI"
                                               FontSize="10" FontWeight="SemiBold" Foreground="#9898B0" VerticalAlignment="Center"/>
                                </StackPanel>
                                <TextBlock x:Name="TxtGPUInfo" Text="GPU algilanmadi. &apos;GPU Algila&apos; butonuna tikla."
                                           FontSize="12" Foreground="#E8E8F0" Margin="0,6,0,0"/>
                            </StackPanel>
                        </Border>


                        <Border x:Name="GPUProgressContainer" Visibility="Collapsed"
                                Background="#1A1B35" CornerRadius="8" Padding="12,10" Margin="0,10,0,0"
                                BorderBrush="#2A2B4A" BorderThickness="1">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                                    <TextBlock x:Name="GPUProgressStatus" Text="Uygulanıyor..."
                                               FontSize="11" Foreground="#E8E8F0" VerticalAlignment="Center"/>
                                    <TextBlock x:Name="GPUProgressStep" Text=""
                                               FontSize="11" Foreground="#FF9800" VerticalAlignment="Center" Margin="6,0,0,0"/>
                                </StackPanel>
                                <Border x:Name="GPUProgressTrack" Height="5" CornerRadius="3" Background="#2A2B4A">
                                    <Border x:Name="GPUProgressFill" HorizontalAlignment="Left"
                                            Background="#FF9800" Height="5" CornerRadius="3" Width="0"/>
                                </Border>
                            </StackPanel>
                        </Border>

                        <GroupBox Header="MSI MODE (Message Signaled Interrupts)" Margin="0,8,0,0">
                            <StackPanel>
                                <TextBlock Text="MSI Mode, PCIe cihazlarinin (GPU, NVMe, NIC) interrupt islemlerini optimize eder. DPC/ISR gecikmelerini azaltir."
                                           FontSize="10" Foreground="#9898B0" TextWrapping="Wrap" Margin="0,0,0,8"/>
                                <WrapPanel>
                                    <CheckBox x:Name="ChkMSIGPU"    Content="GPU MSI Mode"      Margin="0,4,20,4" ToolTip="GPU icin MSI modu aktiflestirilir. DPC/ISR latency duser." IsChecked="True"/>
                                    <CheckBox x:Name="ChkMSINVMe"   Content="NVMe MSI Mode"     Margin="0,4,20,4" ToolTip="NVMe SSD icin MSI modu aktiflestirilir." IsChecked="True"/>
                                    <CheckBox x:Name="ChkMSINIC"    Content="NIC MSI Mode"      Margin="0,4,20,4" ToolTip="Ag karti (NIC) icin MSI modu aktiflestirilir. Ag gecikme ve DPC latency azalir. Sadece yuksek trafik aglarinda one cikar." IsChecked="False"/>
                                    <CheckBox x:Name="ChkMSIPrio"   Content="MSI IRQ Priority Yukselt" Margin="0,4,20,4" ToolTip="MSI Interrupt Priority HIGH olarak ayarlanir." IsChecked="True"/>
                                </WrapPanel>
                            </StackPanel>
                        </GroupBox>

                        <GroupBox x:Name="GrpNvidia" Header="NVIDIA LATENCY OPTIMIZASYONU">
                            <WrapPanel>
                                <CheckBox x:Name="ChkNvPrerender"   Content="Max Pre-Rendered Frames = 1"      Margin="0,4,20,4" ToolTip="NVIDIA pre-rendered frame sayisi 1e dusurulur. Input latency azalir." IsChecked="True"/>
                                <CheckBox x:Name="ChkNvPower"       Content="Prefer Max Performance"           Margin="0,4,20,4" ToolTip="NVIDIA GPU maksimum performans moduna kilitlenir." IsChecked="True"/>
                                <CheckBox x:Name="ChkNvSync"        Content="V-Sync Kapat (Driver)"            Margin="0,4,20,4" ToolTip="NVIDIA V-Sync (driver) devre disi birakilir." IsChecked="True"/>
                                <CheckBox x:Name="ChkNvShaderCache" Content="Shader Cache Etkin"               Margin="0,4,20,4" ToolTip="NVIDIA Shader Cache aktiflestirilir. Oyun acilis surelerini kisaltir, GPU shader derlemesini azaltir." IsChecked="True"/>
                                <CheckBox x:Name="ChkNvTexFilter"   Content="Texture Filter Quality = High Perf" Margin="0,4,20,4" ToolTip="Texture filtreleme kalitesi maksimum performans moduna alinir. FPS kazanci saglar, gorsel etki minimumdur." IsChecked="False"/>
                                <CheckBox x:Name="ChkNvFastSync"    Content="Ultra Low Latency Mode"           Margin="0,4,20,4" ToolTip="NVIDIA frame delay optimizasyonu uygulanir." IsChecked="True"/>
                            </WrapPanel>
                        </GroupBox>

                        <GroupBox x:Name="GrpAmd" Header="AMD LATENCY OPTIMIZASYONU">
                            <WrapPanel>
                                <CheckBox x:Name="ChkAMDAntiLag"   Content="Anti-Lag Etkin (Registry)"    Margin="0,4,20,4" ToolTip="AMD Anti-Lag aktiflestirilir. Input latency azalir." IsChecked="True"/>
                                <CheckBox x:Name="ChkAMDChill"     Content="AMD Chill Kapat"               Margin="0,4,20,4" ToolTip="AMD Chill dinamik kare hizi kontrolu devre disi birakilir." IsChecked="True"/>
                                <CheckBox x:Name="ChkAMDPower"     Content="Profile: Max Performance"      Margin="0,4,20,4" ToolTip="AMD GPU guc performans modu optimize edilir." IsChecked="True"/>
                            </WrapPanel>
                        </GroupBox>
                        <Border Height="12"/>
                    </StackPanel>

                    <!-- ===== PRIVACY &amp; TELEMETRY PAGE ===== -->
                    <StackPanel x:Name="PagePrivacy" Visibility="Collapsed">
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
                                    <TextBlock Text="&#xE72E;" FontFamily="Segoe MDL2 Assets" FontSize="20" Foreground="#F44336" VerticalAlignment="Center" Margin="0,3,0,0"/>
                                    <TextBlock Text="  Privacy &amp; Telemetry" FontSize="20" FontWeight="Bold" Foreground="#E8E8F0" VerticalAlignment="Center"/>
                                </StackPanel>
                        <TextBlock Text="Windows telemetri, veri paylasimi ve reklam servislerini devre disi birak."
                                   FontSize="12" Foreground="#9898B0" Margin="0,0,0,16"/>

                        <WrapPanel>
                            <Button x:Name="BtnApplyPrivacy" 
                                    Style="{StaticResource BtnAccent}" Margin="0,0,10,0" Height="36">
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock Text="&#xE74E;" FontFamily="Segoe MDL2 Assets" FontSize="12" VerticalAlignment="Center" LineHeight="14" Padding="0" Margin="0,2,0,0"/>
                                <TextBlock Text=" Uygula" FontSize="12" VerticalAlignment="Center" Margin="4,0,0,0"/>
                            </StackPanel>
                        </Button>
                            <Button x:Name="BtnBackupPrivacy"
                                    Style="{StaticResource BtnBase}" Height="36"
                                    ToolTip="Privacy &amp; Telemetry registry anahtarlarını _Files\Backups klasörüne yedekle">
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock Text="&#xE74E;" FontFamily="Segoe MDL2 Assets" FontSize="12" VerticalAlignment="Center" LineHeight="14" Padding="0" Margin="0,2,0,0"/>
                                <TextBlock Text=" Backup" FontSize="12" VerticalAlignment="Center" Margin="4,0,0,0"/>
                            </StackPanel>
                        </Button>
                        </WrapPanel>


                        <Border x:Name="PrivProgressContainer" Visibility="Collapsed"
                                Background="#1A1B35" CornerRadius="8" Padding="12,10" Margin="0,10,0,0"
                                BorderBrush="#2A2B4A" BorderThickness="1">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                                    <TextBlock x:Name="PrivProgressStatus" Text="Uygulanıyor..."
                                               FontSize="11" Foreground="#E8E8F0" VerticalAlignment="Center"/>
                                    <TextBlock x:Name="PrivProgressStep" Text=""
                                               FontSize="11" Foreground="#4CAF50" VerticalAlignment="Center" Margin="6,0,0,0"/>
                                </StackPanel>
                                <Border x:Name="PrivProgressTrack" Height="5" CornerRadius="3" Background="#2A2B4A">
                                    <Border x:Name="PrivProgressFill" HorizontalAlignment="Left"
                                            Background="#4CAF50" Height="5" CornerRadius="3" Width="0"/>
                                </Border>
                            </StackPanel>
                        </Border>

                        <GroupBox Header="TELEMETRI &amp; TANI" Margin="0,14,0,0">
                            <WrapPanel>
                                <CheckBox x:Name="ChkDiagTrack"      Content="DiagTrack Servisi Kapat"               Margin="0,4,20,4" ToolTip="Connected User Experiences and Telemetry servisi devre disi birakilir." IsChecked="True"/>
                                <CheckBox x:Name="ChkDMWAppSupport"  Content="dmwappushsvc Kapat"                    Margin="0,4,20,4" ToolTip="dmwappushservice (telemetri) servisi devre disi birakilir." IsChecked="True"/>
                                <CheckBox x:Name="ChkCEIP"           Content="CEIP Kapat"                             Margin="0,4,20,4" ToolTip="Customer Experience Improvement Program (SQMClient) devre disi birakilir. Kullanim verisi Microsoft'a gonderilmez." IsChecked="True"/>
                                <CheckBox x:Name="ChkTelemetryReg"   Content="Telemetry Level = 0 (Security)"        Margin="0,4,20,4" ToolTip="Telemetri registry ayarlari sifirlanir. Veri toplama en dusuge indirilir." IsChecked="True"/>
                                <CheckBox x:Name="ChkAppCompat"      Content="Application Compatibility Telemetry"   Margin="0,4,20,4" ToolTip="Application Compatibility Assistant devre disi birakilir." IsChecked="True"/>
                                <CheckBox x:Name="ChkErrorReport"    Content="Windows Error Reporting Kapat"         Margin="0,4,20,4" ToolTip="Windows Hata Raporlama servisi devre disi birakilir." IsChecked="True"/>
                                <CheckBox x:Name="ChkActivityHist"   Content="Activity History Kapat"                Margin="0,4,20,4" ToolTip="Activity History ve Timeline ozelligi devre disi birakilir." IsChecked="True"/>
                            </WrapPanel>
                        </GroupBox>

                        <GroupBox Header="CORTANA &amp; REKLAM">
                            <WrapPanel>
                                <CheckBox x:Name="ChkCortana"       Content="Cortana Kapat"                   Margin="0,4,20,4" ToolTip="Cortana ve Bing arama entegrasyonu devre disi birakilir." IsChecked="True"/>
                                <CheckBox x:Name="ChkAdID"          Content="Advertising ID Kapat"            Margin="0,4,20,4" ToolTip="Kisisellestirilmis reklam kimligi devre disi birakilir." IsChecked="True"/>
                                <CheckBox x:Name="ChkTailored"      Content="Tailored Experiences Kapat"      Margin="0,4,20,4" ToolTip="Kullanim verilerine dayali kisilestirilmis deneyimler kapatilir." IsChecked="True"/>
                                <CheckBox x:Name="ChkTyping"        Content="Inking &amp; Typing Personalization Kapat" Margin="0,4,20,4" ToolTip="Klavye ve konusma veri toplama devre disi birakilir." IsChecked="True"/>
                            </WrapPanel>
                        </GroupBox>

                        <GroupBox Header="ONEDRIVE &amp; BLOATWARE">
                            <WrapPanel>
                                <CheckBox x:Name="ChkOneDrive"     Content="OneDrive Kaldir"           Margin="0,4,20,4" ToolTip="OneDrive surec ve baslangic girisi devre disi birakilir." IsChecked="False"/>
                                <CheckBox x:Name="ChkXboxServices" Content="Xbox Services Kapat"       Margin="0,4,20,4" ToolTip="Xbox ilgili servisler devre disi birakilir." IsChecked="False"/>
                                <CheckBox x:Name="ChkBingSearch"   Content="Start Menu Bing Search Kapat" Margin="0,4,20,4" ToolTip="Baslat menusu Bing arama entegrasyonu devre disi birakilir." IsChecked="True"/>
                                <CheckBox x:Name="ChkSuggestApps"  Content="Suggested Apps Kapat"      Margin="0,4,20,4" ToolTip="Microsoft Store uygulama onerileri kapatilir." IsChecked="True"/>
                                <CheckBox x:Name="ChkConsumerExp"  Content="Consumer Experience Kapat" Margin="0,4,20,4" ToolTip="Consumer Experience ozellikleri devre disi birakilir." IsChecked="True"/>
                            </WrapPanel>
                        </GroupBox>
                        <Border Height="12"/>
                    </StackPanel>

                    <!-- ===== WINDOWS TWEAKS PAGE ===== -->
                    <StackPanel x:Name="PageWinTweaks" Visibility="Collapsed">
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
                                    <TextBlock Text="&#xE115;" FontFamily="Segoe MDL2 Assets" FontSize="20" Foreground="#9898B0" VerticalAlignment="Center" Margin="0,3,0,0"/>
                                    <TextBlock Text="  Windows Tweaks" FontSize="20" FontWeight="Bold" Foreground="#E8E8F0" VerticalAlignment="Center"/>
                                </StackPanel>
                        <TextBlock Text="Cesitli Windows deneyim ve kararlilik iyilestirmeleri."
                                   FontSize="12" Foreground="#9898B0" Margin="0,0,0,16"/>

                        <WrapPanel>
                            <Button x:Name="BtnApplyWinTweaks" 
                                    Style="{StaticResource BtnAccent}" Margin="0,0,10,0" Height="36">
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock Text="&#xE74E;" FontFamily="Segoe MDL2 Assets" FontSize="12" VerticalAlignment="Center" LineHeight="14" Padding="0" Margin="0,2,0,0"/>
                                <TextBlock Text=" Uygula" FontSize="12" VerticalAlignment="Center" Margin="4,0,0,0"/>
                            </StackPanel>
                        </Button>
                            <Button x:Name="BtnBackupWinTweaks"
                                    Style="{StaticResource BtnBase}" Height="36"
                                    ToolTip="Windows Tweaks registry anahtarlarını _Files\Backups klasörüne yedekle">
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock Text="&#xE74E;" FontFamily="Segoe MDL2 Assets" FontSize="12" VerticalAlignment="Center" LineHeight="14" Padding="0" Margin="0,2,0,0"/>
                                <TextBlock Text=" Backup" FontSize="12" VerticalAlignment="Center" Margin="4,0,0,0"/>
                            </StackPanel>
                        </Button>
                        </WrapPanel>

                        <!-- ── WINTWEAKS PROGRESS BAR ──────────────────────── -->
                        <Border x:Name="WinProgressContainer" Visibility="Collapsed"
                                Background="#1A1B35" CornerRadius="8" Padding="12,10" Margin="0,10,0,0"
                                BorderBrush="#2A2B4A" BorderThickness="1">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                                    <TextBlock x:Name="WinProgressStatus" Text="Uygulanıyor..."
                                               FontSize="11" Foreground="#E8E8F0" VerticalAlignment="Center"/>
                                    <TextBlock x:Name="WinProgressStep" Text=""
                                               FontSize="11" Foreground="#9898B0" VerticalAlignment="Center" Margin="6,0,0,0"/>
                                </StackPanel>
                                <Border x:Name="WinProgressTrack" Height="5" CornerRadius="3" Background="#2A2B4A">
                                    <Border x:Name="WinProgressFill" HorizontalAlignment="Left"
                                            Background="#9898B0" Height="5" CornerRadius="3" Width="0"/>
                                </Border>
                            </StackPanel>
                        </Border>

                        <GroupBox Header="GORSEL &amp; UI OPTIMIZASYONU" Margin="0,14,0,0">
                            <WrapPanel>
                                <CheckBox x:Name="ChkAnimations"   Content="Animasyonlari Kapat"                  Margin="0,4,20,4" ToolTip="Windows arayuz animasyonlarini devre disi birakir. Daha hizli hissettiren arayuz." IsChecked="True"/>
                                <CheckBox x:Name="ChkTransparency" Content="Transparency Kapat"                   Margin="0,4,20,4" ToolTip="Arayuz seffafligini devre disi birakir. Hafif performans kazanimi." IsChecked="False"/>
                                <CheckBox x:Name="ChkJPEGQuality"  Content="JPEG Kalite %100 (Desktop BG)"        Margin="0,4,20,4" ToolTip="Masaüstü arka planı JPEG sıkıştırma kalitesini %100'e ayarlar. Windows'un arka planı gereksiz yere sıkıştırmasını engeller." IsChecked="True"/>
                                <CheckBox x:Name="ChkMenuDelay"    Content="Menu ShowDelay = 0ms"                 Margin="0,4,20,4" ToolTip="Baslat menusu acilma gecikmesini kaldirir." IsChecked="True"/>
                                <CheckBox x:Name="ChkTaskbarAnims" Content="Taskbar Animasyonlarini Kapat"        Margin="0,4,20,4" ToolTip="Gorev cubugu animasyonlarini devre disi birakir." IsChecked="True"/>
                                <CheckBox x:Name="ChkDarkMode"     Content="Dark Mode Etkin"                      Margin="0,4,20,4" ToolTip="Windows Dark Mode aktiflestirilir." IsChecked="False"/>
                            </WrapPanel>
                        </GroupBox>

                        <GroupBox Header="HATA &amp; LOG YONETIMI">
                            <WrapPanel>
                                <CheckBox x:Name="ChkBSODDetail"   Content="BSOD Detayli Hata Kodu (AutoReboot Kapat)" Margin="0,4,20,4" ToolTip="BSOD ekraninda detayli kod gosterilir, otomatik yeniden baslatma kapatilir." IsChecked="True"/>
                                <CheckBox x:Name="ChkCrashDumpFull" Content="Full Memory Dump (Crash)"              Margin="0,4,20,4" ToolTip="Tam bellek dump olusturulur. Sorun gidermede detayli bilgi saglar." IsChecked="False"/>
                                <CheckBox x:Name="ChkEventLogSize" Content="Event Log Max Size Artir"              Margin="0,4,20,4" ToolTip="Windows Event Log maksimum boyutu arttirilir." IsChecked="False"/>
                            </WrapPanel>
                        </GroupBox>

                        <GroupBox Header="EXPLORER &amp; SHELl">
                            <WrapPanel>
                                <CheckBox x:Name="ChkLaunchTo"     Content="Explorer: This PC&apos;de Ac"             Margin="0,4,20,4" ToolTip="Explorer This PCde acilar (Hizli Erisim yerine)." IsChecked="True"/>
                                <CheckBox x:Name="ChkNumlock"      Content="NumLock Baslangicta Acik"            Margin="0,4,20,4" ToolTip="Baslangicta NumLock acik olacak sekilde ayarlanir." IsChecked="True"/>
                                <CheckBox x:Name="ChkHideExt"      Content="Dosya Uzantilarini Goster"           Margin="0,4,20,4" ToolTip="Dosya uzantilarini Explorerda goruntule." IsChecked="True"/>
                                <CheckBox x:Name="ChkLongPaths"    Content="Long Path Support Etkin"             Margin="0,4,20,4" ToolTip="260 karakter sinirini kaldirir. Uzun dosya yollarini destekler." IsChecked="True"/>
                                <CheckBox x:Name="ChkContextMenu"  Content="Eski Sag Tik Menusu (Win11)"        Margin="0,4,20,4" ToolTip="Windows 11 icin eski tam sag tik menusu geri getirilir." IsChecked="False"/>
                            </WrapPanel>
                        </GroupBox>
                        <Border Height="12"/>
                    </StackPanel>

                    <!-- ===== RUN SCRIPT PAGE ===== -->
                    <Grid x:Name="PageRunScript" Visibility="Collapsed">
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                        </Grid.RowDefinitions>

                        <StackPanel Grid.Row="0">
                            <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
                                    <TextBlock Text="&#xE943;" FontFamily="Segoe MDL2 Assets" FontSize="20" Foreground="#7B5EA7" VerticalAlignment="Center" Margin="0,3,0,0"/>
                                    <TextBlock Text="  Run Script" FontSize="20" FontWeight="Bold" Foreground="#E8E8F0" VerticalAlignment="Center"/>
                                </StackPanel>
                            <TextBlock Text=".ps1 / .bat / .cmd dosyalarini import et, goruntule ve calistir."
                                       FontSize="12" Foreground="#9898B0" Margin="0,0,0,16"/>
                        </StackPanel>

                        <WrapPanel Grid.Row="1" Margin="0,0,0,12">
                            <Button x:Name="BtnImportScript" 
                                    Style="{StaticResource BtnBase}" Margin="0,0,10,0" Height="36" FontSize="12">
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock Text="&#xE8E5;" FontFamily="Segoe MDL2 Assets" FontSize="12" VerticalAlignment="Center" LineHeight="14" Padding="0" Margin="0,2,0,0"/>
                                <TextBlock Text=" Script Ice Aktar" FontSize="12" VerticalAlignment="Center" Margin="4,0,0,0"/>
                            </StackPanel>
                        </Button>
                            <Button x:Name="BtnRunImported" 
                                    Style="{StaticResource BtnAccent}" Margin="0,0,10,0" Height="36">
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock Text="&#xE768;" FontFamily="Segoe MDL2 Assets" FontSize="12" VerticalAlignment="Center" LineHeight="14" Padding="0" Margin="0,2,0,0"/>
                                <TextBlock Text=" Calistir" FontSize="12" VerticalAlignment="Center" Margin="4,0,0,0"/>
                            </StackPanel>
                        </Button>
                            <Button x:Name="BtnClearEditor" 
                                    Style="{StaticResource BtnDanger}" Height="36">
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock Text="&#xE74D;" FontFamily="Segoe MDL2 Assets" FontSize="12" VerticalAlignment="Center" LineHeight="14" Padding="0" Margin="0,2,0,0"/>
                                <TextBlock Text=" Temizle" FontSize="12" VerticalAlignment="Center" Margin="4,0,0,0"/>
                            </StackPanel>
                        </Button>
                        </WrapPanel>

                        <Grid Grid.Row="2">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <Border Background="#0C0D18" CornerRadius="8" BorderBrush="#2A2B4A" BorderThickness="1">
                                <TextBox x:Name="ScriptEditor"
                                         Background="Transparent"
                                         Foreground="#C8D8FF"
                                         FontFamily="Cascadia Code, Consolas, Courier New"
                                         FontSize="12"
                                         BorderThickness="0"
                                         Padding="14"
                                         AcceptsReturn="True"
                                         AcceptsTab="True"
                                         TextWrapping="NoWrap"
                                         VerticalScrollBarVisibility="Auto"
                                         HorizontalScrollBarVisibility="Auto"
                                         MinHeight="280"
                                         Text="# Bir script dosyasi import edin veya buraya kodu yapistirin...&#x0a;# Desteklenen formatlar: .ps1, .bat, .cmd"/>
                            </Border>
                        </Grid>
                    </Grid>

                </Grid>
            </ScrollViewer>
        </Grid>

        <!-- ── TERMINAL BAR ──────────────────────────────────────── -->
        <Border Grid.Row="4" Background="#080910" BorderBrush="#2A2B4A" BorderThickness="0,1,0,0">
            <DockPanel>
                <!-- Terminal Header -->
                <Border DockPanel.Dock="Top" Background="#0F1020" Padding="12,6">
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
                            <TextBlock Text="&#xE756;" FontFamily="Segoe MDL2 Assets" Foreground="#00FF88" FontSize="12" Margin="0,2,0,0"/>
                            <TextBlock Text="  TERMINAL" FontSize="10" FontWeight="Bold"
                                       Foreground="#9898B0" VerticalAlignment="Center"/>
                            <Border x:Name="TerminalBusyDot" Background="#FF9800" CornerRadius="4"
                                    Width="8" Height="8" Margin="8,0,0,0" Visibility="Collapsed"/>
                        </StackPanel>
                        <StackPanel Grid.Column="1" Orientation="Horizontal">
                            <Button x:Name="BtnSaveLog" 
                                    Style="{StaticResource BtnBase}" Height="30" FontSize="11" Margin="0,0,6,0">
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock Text="&#xE74E;" FontFamily="Segoe MDL2 Assets" FontSize="11" VerticalAlignment="Center" Margin="0,2,0,0"/>
                                <TextBlock Text=" Log Kaydet" FontSize="11" VerticalAlignment="Center" Margin="4,0,0,0"/>
                            </StackPanel>
                        </Button>
                            <Button x:Name="BtnClearLog" 
                                    Style="{StaticResource BtnBase}" Height="30" FontSize="11">
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock Text="&#xE74D;" FontFamily="Segoe MDL2 Assets" FontSize="11" VerticalAlignment="Center" Margin="0,2,0,0"/>
                                <TextBlock Text=" Temizle" FontSize="11" VerticalAlignment="Center" Margin="4,0,0,0"/>
                            </StackPanel>
                        </Button>
                        </StackPanel>
                    </Grid>
                </Border>
                <!-- Terminal Output -->
                <TextBox x:Name="Terminal" Style="{StaticResource Terminal}"
                         BorderThickness="0" MinHeight="120"/>
            </DockPanel>
        </Border>

        <!-- ── STATUS BAR ────────────────────────────────────────── -->
        <Border Grid.Row="5" Background="#080910" BorderBrush="#2A2B4A" BorderThickness="0,1,0,0" Padding="16,0">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
                    <TextBlock x:Name="TxtStatus" Text="Hazir." FontSize="11" Foreground="#9898B0"/>
                </StackPanel>
                <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                    <TextBlock x:Name="TxtVersion" Text="Livn Tools v3.5  |  livn.tr"
                               FontSize="10" Foreground="#4A4A6A"/>
                </StackPanel>
            </Grid>
        </Border>
    </Grid>
    </Border>
</Window>
"@

# ─── LOAD XAML ─────────────────────────────────────────────────────────────────
try {
    $reader = [System.Xml.XmlNodeReader]::new($XAML)
    $Window = [Windows.Markup.XamlReader]::Load($reader)
} catch {
    [System.Windows.Forms.MessageBox]::Show("XAML yuklenemedi: $_", "Livn Tools - Hata")
    exit
}

# ─── CONTROL REFERENCES ────────────────────────────────────────────────────────
function Get-Ctrl($name) { $Window.FindName($name) }

# Window controls
$BtnClose        = Get-Ctrl 'BtnClose'
$BtnMinimize     = Get-Ctrl 'BtnMinimize'
$BtnMaximize     = Get-Ctrl 'BtnMaximize'

# HW Monitor
$TxtCpuPct    = Get-Ctrl 'TxtCpuPct';    $ProgCpu    = Get-Ctrl 'ProgCpu'
$TxtCpuName   = Get-Ctrl 'TxtCpuName';   $TxtRamPct  = Get-Ctrl 'TxtRamPct'
$ProgRam      = Get-Ctrl 'ProgRam';       $TxtRamDetail = Get-Ctrl 'TxtRamDetail'
$TxtUserPC    = Get-Ctrl 'TxtUserPC';     $TxtOS      = Get-Ctrl 'TxtOS'
$TxtUptime    = Get-Ctrl 'TxtUptime';     $TxtClock   = Get-Ctrl 'TxtClock'
$TxtDate      = Get-Ctrl 'TxtDate'

# Navigation
$NavTree          = Get-Ctrl 'NavTree'
$NavCatTemizlik   = Get-Ctrl 'NavCatTemizlik'
$NavCatOptimizasyon = Get-Ctrl 'NavCatOptimizasyon'
$NavCatTemizlikText = Get-Ctrl 'NavCatTemizlikText'
$NavCatOptimText    = Get-Ctrl 'NavCatOptimText'
$NavCatTemizlikIcon = Get-Ctrl 'NavCatTemizlikIcon'
$NavCatOptimIcon    = Get-Ctrl 'NavCatOptimIcon'
$NavQuickClean    = Get-Ctrl 'NavQuickClean'

$NavAdvancedClean = Get-Ctrl 'NavAdvancedClean'
$NavPerformance   = Get-Ctrl 'NavPerformance'
$NavNetwork       = Get-Ctrl 'NavNetwork'
$NavKernel        = Get-Ctrl 'NavKernel'
$NavGPU           = Get-Ctrl 'NavGPU'
$NavPrivacy       = Get-Ctrl 'NavPrivacy'
$NavWinTweaks     = Get-Ctrl 'NavWinTweaks'
$NavRunScript     = Get-Ctrl 'NavRunScript'

# Pages
$Pages = @{
    'QuickClean'    = Get-Ctrl 'PageQuickClean'
    'AdvancedClean' = Get-Ctrl 'PageAdvancedClean'
    'Performance'   = Get-Ctrl 'PagePerformance'
    'Network'       = Get-Ctrl 'PageNetwork'
    'Kernel'        = Get-Ctrl 'PageKernel'
    'GPU'           = Get-Ctrl 'PageGPU'
    'Privacy'       = Get-Ctrl 'PagePrivacy'
    'WinTweaks'     = Get-Ctrl 'PageWinTweaks'
    'RunScript'     = Get-Ctrl 'PageRunScript'
}

# Preset / global buttons
$BtnPresetMinimal    = Get-Ctrl 'BtnPresetMinimal'
$BtnPresetStandard   = Get-Ctrl 'BtnPresetStandard'
$BtnPresetAggressive = Get-Ctrl 'BtnPresetAggressive'
$BtnApplyAll         = Get-Ctrl 'BtnApplyAll'
$BtnRestoreBackup    = Get-Ctrl 'BtnRestoreBackup'

# Terminal
$Terminal            = Get-Ctrl 'Terminal'
$TerminalBusyDot     = Get-Ctrl 'TerminalBusyDot'
$BtnSaveLog          = Get-Ctrl 'BtnSaveLog'
$BtnClearLog         = Get-Ctrl 'BtnClearLog'
$TxtStatus           = Get-Ctrl 'TxtStatus'

# Page buttons
$BtnRunQuickClean   = Get-Ctrl 'BtnRunQuickClean'
$BtnSelectAllQC     = Get-Ctrl 'BtnSelectAllQC'
$BtnDeselectAllQC   = Get-Ctrl 'BtnDeselectAllQC'
$BtnRunAdvClean     = Get-Ctrl 'BtnRunAdvClean'
$BtnApplyPerf       = Get-Ctrl 'BtnApplyPerf'
$BtnBackupPerf      = Get-Ctrl 'BtnBackupPerf'
$BtnPlanBitsum      = Get-Ctrl 'BtnPlanBitsum'
$BtnPlanHybred      = Get-Ctrl 'BtnPlanHybred'
$BtnPlanHybred2     = Get-Ctrl 'BtnPlanHybred2'
$BtnPlanUlti        = Get-Ctrl 'BtnPlanUlti'
$BtnPlanBalanced    = Get-Ctrl 'BtnPlanBalanced'
$BtnPlanDefault     = Get-Ctrl 'BtnPlanDefault'
$TxtActivePlan      = Get-Ctrl 'TxtActivePlan'
$BtnW32BestFPS      = Get-Ctrl 'BtnW32BestFPS'
$BtnW32Balanced     = Get-Ctrl 'BtnW32Balanced'
$BtnW32Default      = Get-Ctrl 'BtnW32Default'
$BtnApplyNetwork    = Get-Ctrl 'BtnApplyNetwork'
$BtnResetNetwork    = Get-Ctrl 'BtnResetNetwork'
$BtnBackupNetwork   = Get-Ctrl 'BtnBackupNetwork'
$BtnScanAdapters    = Get-Ctrl 'BtnScanAdapters'
$TxtAdapterInfo     = Get-Ctrl 'TxtAdapterInfo'

# USB Watchdog
$TxtUsbCount        = Get-Ctrl 'TxtUsbCount'
$global:UsbDeviceCache = @{}
$BtnApplyKernel     = Get-Ctrl 'BtnApplyKernel'
$BtnBackupKernel    = Get-Ctrl 'BtnBackupKernel'
$BtnDetectGPU       = Get-Ctrl 'BtnDetectGPU'
$TxtGPUInfo         = Get-Ctrl 'TxtGPUInfo'
$BtnApplyGPU        = Get-Ctrl 'BtnApplyGPU'
$BtnBackupGPU       = Get-Ctrl 'BtnBackupGPU'
$GrpNvidia          = Get-Ctrl 'GrpNvidia'
$GrpAmd             = Get-Ctrl 'GrpAmd'
$BtnApplyPrivacy    = Get-Ctrl 'BtnApplyPrivacy'
$BtnBackupPrivacy   = Get-Ctrl 'BtnBackupPrivacy'
$BtnApplyWinTweaks  = Get-Ctrl 'BtnApplyWinTweaks'
$BtnBackupWinTweaks = Get-Ctrl 'BtnBackupWinTweaks'

# Progress bar (QuickClean)
$CleanProgressContainer = Get-Ctrl 'CleanProgressContainer'
$CleanProgressFill      = Get-Ctrl 'CleanProgressFill'
$CleanProgressTrack     = Get-Ctrl 'CleanProgressTrack'
$TxtCleanStatus         = Get-Ctrl 'TxtCleanStatus'
$TxtCleanPct            = Get-Ctrl 'TxtCleanPct'

# Progress bar (AdvancedClean)
$AdvCleanProgressContainer = Get-Ctrl 'AdvCleanProgressContainer'
$AdvCleanProgressFill      = Get-Ctrl 'AdvCleanProgressFill'
$AdvCleanProgressTrack     = Get-Ctrl 'AdvCleanProgressTrack'
$TxtAdvCleanStatus         = Get-Ctrl 'TxtAdvCleanStatus'
$TxtAdvCleanStep           = Get-Ctrl 'TxtAdvCleanStep'

# Progress bars — Optimizasyon sayfaları (Perf, Net, Kern, GPU, Priv)
$global:_OptProgressBars = @{}
foreach ($pg in @('Perf','Net','Kern','GPU','Priv','Win')) {
    $global:_OptProgressBars[$pg] = @{
        Container = (Get-Ctrl "${pg}ProgressContainer")
        Track     = (Get-Ctrl "${pg}ProgressTrack")
        Fill      = (Get-Ctrl "${pg}ProgressFill")
        Status    = (Get-Ctrl "${pg}ProgressStatus")
        Step      = (Get-Ctrl "${pg}ProgressStep")
    }
}

# Async job registry — watchTimer closure güvenliği için
$global:_AsyncJobs = @{}

$BtnImportScript    = Get-Ctrl 'BtnImportScript'
$BtnRunImported     = Get-Ctrl 'BtnRunImported'
$BtnClearEditor     = Get-Ctrl 'BtnClearEditor'
$ScriptEditor       = Get-Ctrl 'ScriptEditor'

# ─── HELPER: RENK DONUSTURUCU ─────────────────────────────────────────────────
function New-Brush {
    param([string]$hex)
    try { return [System.Windows.Media.BrushConverter]::new().ConvertFrom($hex) }
    catch { return [System.Windows.Media.Brushes]::White }
}

# ─── HELPER: TERMINAL LOG ──────────────────────────────────────────────────────
function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $ts  = Get-Date -Format 'HH:mm:ss'
    $prefix = switch ($Level) {
        'OK'    { '[  OK  ]' }
        'WARN'  { '[ WARN ]' }
        'ERROR' { '[ERROR ]' }
        'RUN'   { '[ RUN  ]' }
        default { '[ INFO ]' }
    }
    $line = "$ts  $prefix  $Message"
    $Window.Dispatcher.Invoke([action]{
        $Terminal.AppendText($line + "`r`n")
        $Terminal.ScrollToEnd()
    })
    Add-Content -Path $global:LogFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
}

function Set-Status([string]$msg) {
    $Window.Dispatcher.Invoke([action]{ $TxtStatus.Text = $msg })
}

function Set-Busy([bool]$busy) {
    $Window.Dispatcher.Invoke([action]{
        $TerminalBusyDot.Visibility = if ($busy) { 'Visible' } else { 'Collapsed' }
        # Apply butonlarını meşguliyet sırasında devre dışı bırak — çift tıklama önleme
        $applyBtns = @(
            'BtnApplyPerf','BtnApplyNetwork','BtnApplyKernel',
            'BtnApplyGPU','BtnApplyPrivacy','BtnApplyWinTweaks',
            'BtnRunQuickClean','BtnRunAdvClean','BtnApplyAll'
        )
        foreach ($btnName in $applyBtns) {
            $btn = $Window.FindName($btnName)
            if ($btn) { $btn.IsEnabled = -not $busy }
        }
    })
}

# ─── BACKUP REGISTRY ──────────────────────────────────────────────────────────
function Backup-Registry {
    param([string]$KeyPath, [string]$Label)
    try {
        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $safe  = $Label -replace '[^a-zA-Z0-9]', '_'
        $out   = Join-Path $global:BackupPath ("${safe}_${stamp}.reg")
        $regKey = $KeyPath -replace 'HKLM:\\', 'HKEY_LOCAL_MACHINE\' -replace 'HKCU:\\', 'HKEY_CURRENT_USER\'
        reg export $regKey $out /y 2>$null | Out-Null
        Write-Log "Yedek alindi: $out" 'OK'
    } catch {
        Write-Log "Yedek alinamadi: $Label - $_" 'WARN'
    }
}

function Set-ActiveButton {
    param(
        [System.Windows.Controls.Button]$ActiveBtn,
        [System.Windows.Controls.Button[]]$Group,
        [string]$DefaultStyle = 'BtnBase'
    )
    $Window.Dispatcher.Invoke([action]{
        foreach ($btn in $Group) {
            $btn.Style = if ($btn -eq $ActiveBtn) {
                $Window.Resources['BtnActive']
            } else {
                $Window.Resources[$DefaultStyle]
            }
        }
    })
}

$script:_cleanTotalBytes = 0
$script:_cleanExpectedBytes = 1

function Reset-CleanProgress {
    $script:_cleanTotalBytes   = 0
    $script:_cleanExpectedBytes = 1
    $Window.Dispatcher.Invoke([action]{
        $CleanProgressContainer.Visibility = 'Visible'
        $CleanProgressFill.Width = 0
        $CleanProgressFill.Background = New-Brush '#7B5EA7'
        $TxtCleanPct.Text    = '  0%'
        $TxtCleanPct.Foreground    = New-Brush '#7B5EA7'
        $TxtCleanStatus.Text = 'Temizleniyor...'
        $TxtCleanStatus.Foreground = New-Brush '#9898B0'
    })
}

function Update-CleanProgress {
    param([long]$AddBytes, [string]$StatusText = '')
    $script:_cleanTotalBytes += $AddBytes
    $pct = if ($script:_cleanExpectedBytes -gt 0) {
        [math]::Min(99, [math]::Round($script:_cleanTotalBytes / $script:_cleanExpectedBytes * 100))
    } else { 0 }
    $Window.Dispatcher.Invoke([action]{
        $trackWidth = $CleanProgressTrack.ActualWidth
        if ($trackWidth -gt 0) {
            $targetW = [math]::Round($trackWidth * $pct / 100, 1)
            $anim = [System.Windows.Media.Animation.DoubleAnimation]::new()
            $anim.To       = $targetW
            $anim.Duration = [System.Windows.Duration][TimeSpan]::FromMilliseconds(200)
            $CleanProgressFill.BeginAnimation(
                [System.Windows.FrameworkElement]::WidthProperty, $anim)
        }
        $TxtCleanPct.Text = "  $pct%"
        if ($StatusText) { $TxtCleanStatus.Text = $StatusText }
    })
}

function Finish-CleanProgress {
    param([long]$TotalBytes)
    $Window.Dispatcher.Invoke([action]{
        $CleanProgressFill.Width = $CleanProgressTrack.ActualWidth
        $TxtCleanPct.Text = '  100%'
        $savedMB = [math]::Round($TotalBytes / 1MB, 1)
        $TxtCleanStatus.Text = if ($savedMB -gt 0) { "Tamamlandi! $savedMB MB temizlendi" } else { 'Sistem zaten temizdi.' }
        $TxtCleanStatus.Foreground = New-Brush '#4CAF50'
        $TxtCleanPct.Foreground    = New-Brush '#4CAF50'
        $CleanProgressFill.Background = [System.Windows.Media.Brushes]::Green
    })
}

function Remove-SafeFolder {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path $Path)) { return [long]0 }
    try {
        $items = Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue
        $bytes = ($items | Where-Object { -not $_.PSIsContainer } |
                  Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        if (-not $bytes) { $bytes = [long]0 }
        Remove-Item -Path "$Path\*" -Recurse -Force -ErrorAction SilentlyContinue
        if ($bytes -gt 0) {
            $mb = [math]::Round($bytes / 1MB, 1)
            Write-Log "$Label temizlendi: $mb MB" 'OK'
        } else {
            Write-Log "$Label zaten temizdi" 'INFO'
        }
        return [long]$bytes
    } catch {
        Write-Log "$Label temizlenemedi: $_" 'WARN'
        return [long]0
    }
}

# ─── NAVIGATION ───────────────────────────────────────────────────────────────
$GlobalPresetsBar = Get-Ctrl 'GlobalPresetsBar'

# Helper: Optimization pages that should show the Global Presets bar
$OptimizationPages = @('Performance','Network','Kernel','GPU','Privacy','WinTweaks')

function Show-Page([string]$name) {
    foreach ($k in $Pages.Keys) {
        $Pages[$k].Visibility = if ($k -eq $name) { 'Visible' } else { 'Collapsed' }
    }
    # Show Global Presets bar only for Optimization pages
    $GlobalPresetsBar.Visibility = if ($OptimizationPages -contains $name) { 'Visible' } else { 'Collapsed' }

    # NavCategory aktif/pasif renk — Temizlik ve Optimizasyon indikatörleri
    $isClean = @('QuickClean','AdvancedClean') -contains $name
    $isOptim = $OptimizationPages -contains $name
    $activeClr  = '#E8E8F0'  # aktif metin
    $activeIcon = '#7B5EA7'  # aktif ikon (mor)
    $idleClr    = '#4A4A6A'  # pasif gri

    if ($NavCatTemizlikText) {
        $NavCatTemizlikText.Foreground = New-Brush $(if ($isClean) { $activeClr } else { $idleClr })
        $NavCatTemizlikIcon.Foreground = New-Brush $(if ($isClean) { '#4A90D9' } else { $idleClr })
    }
    if ($NavCatOptimText) {
        $NavCatOptimText.Foreground  = New-Brush $(if ($isOptim) { $activeClr } else { $idleClr })
        $NavCatOptimIcon.Foreground  = New-Brush $(if ($isOptim) { $activeIcon } else { $idleClr })
    }
    Set-Status "Sayfa: $name"
}

$NavQuickClean.Add_Selected({    Show-Page 'QuickClean' })
$NavAdvancedClean.Add_Selected({ Show-Page 'AdvancedClean' })
$NavPerformance.Add_Selected({   Show-Page 'Performance' })
$NavNetwork.Add_Selected({       Show-Page 'Network' })
$NavKernel.Add_Selected({        Show-Page 'Kernel' })
$NavGPU.Add_Selected({           Show-Page 'GPU' })
$NavPrivacy.Add_Selected({       Show-Page 'Privacy' })
$NavWinTweaks.Add_Selected({     Show-Page 'WinTweaks' })
$NavRunScript.Add_Selected({     Show-Page 'RunScript' })

# ─── WINDOW CONTROLS ──────────────────────────────────────────────────────────
$BtnClose.Add_Click({    $Window.Close() })
$BtnMinimize.Add_Click({ $Window.WindowState = 'Minimized' })
$BtnMaximize.Add_Click({
    if ($Window.WindowState -eq 'Maximized') { $Window.WindowState = 'Normal' }
    else { $Window.WindowState = 'Maximized' }
})
# Title bar drag-to-move (event handler attached in code, NOT in XAML)
$TitleBar = $Window.FindName('TitleBar')
$TitleBar.Add_MouseLeftButtonDown({
    param($s, $e)
    try { $Window.DragMove() } catch {}
})

# ─── HARDWARE MONITOR TIMER ───────────────────────────────────────────────────
$global:CpuCounter = $null
try { $global:CpuCounter = [System.Diagnostics.PerformanceCounter]::new('Processor', '% Processor Time', '_Total') } catch {}

# Static info
$cpuName  = (Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1).Name
$osCapt   = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption
$totalRAM = [math]::Round((Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).TotalPhysicalMemory / 1GB, 1)
$TxtCpuName.Text  = if ($cpuName)  { $cpuName -replace '\s+', ' ' } else { 'CPU bilgisi yok' }
$TxtUserPC.Text   = " $env:USERNAME @ $env:COMPUTERNAME"
$TxtOS.Text       = if ($osCapt) { $osCapt } else { 'Windows' }

$HWTimer = [System.Windows.Threading.DispatcherTimer]::new()
$HWTimer.Interval = [TimeSpan]::FromSeconds(2)

# ── Lightweight RAM counter (WMI yerine PerformanceCounter — CPU maliyeti ~0) ──
$global:RamCounter = $null
try { $global:RamCounter = [System.Diagnostics.PerformanceCounter]::new('Memory', 'Available MBytes') } catch {}

$HWTimer.Add_Tick({
    # CPU
    try {
        $cpuVal = [math]::Round($global:CpuCounter.NextValue(), 1)
        $TxtCpuPct.Text   = " $cpuVal%"
        $ProgCpu.Value    = $cpuVal
    } catch {}

    # RAM — PerformanceCounter ile (WMI yerine, ~100x daha hafif)
    try {
        if ($global:RamCounter) {
            $freeMB  = $global:RamCounter.NextValue()
            $totalMB = $totalRAM * 1024
            $usedGB  = [math]::Round(($totalMB - $freeMB) / 1024, 1)
            $pct     = [math]::Round($usedGB / $totalRAM * 100, 0)
            $TxtRamPct.Text    = " $pct%"
            $ProgRam.Value     = $pct
            $TxtRamDetail.Text = "$usedGB / $totalRAM GB"
        }
    } catch {}

    # Uptime — Environment.TickCount64 ile (WMI yerine, anlik)
    try {
        $up = [TimeSpan]::FromMilliseconds([Environment]::TickCount64)
        $TxtUptime.Text = "Uptime: $($up.Days)g $($up.Hours)s $($up.Minutes)d"
    } catch {}

    # Clock
    $TxtClock.Text = Get-Date -Format 'HH:mm:ss'
    $TxtDate.Text  = Get-Date -Format 'dd.MM.yyyy'

    # USB Watchdog - Her 4 saniyede bir tara (her 2sn tick * 2)
    # DriveInfo ile (WMI Win32_DiskDrive yerine — ~50x daha hafif)
    if (-not $global:_UsbTickCounter) { $global:_UsbTickCounter = 0 }
    $global:_UsbTickCounter++
    if ($global:_UsbTickCounter % 2 -eq 0) {
        try {
            $usbDrives = @([System.IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Removable' -and $_.IsReady })
            $usbCount  = $usbDrives.Count

            # Degisiklik algilama
            $currentIds = ($usbDrives | ForEach-Object { $_.Name }) -join ','
            if ($currentIds -ne $global:_UsbLastIds) {
                $global:_UsbLastIds = $currentIds
                if ($usbCount -gt 0) {
                    $label = if ($usbCount -eq 1) { "1 Cihaz Bagli" } else { "$usbCount Cihaz Bagli" }
                    $TxtUsbCount.Text       = $label
                    $TxtUsbCount.Foreground = [System.Windows.Media.Brushes]::Orange
                    $usbDrives | ForEach-Object { Write-Log "USB Algilandi: $($_.Name) [$($_.VolumeLabel)]" 'WARN' }
                } else {
                    $TxtUsbCount.Text       = 'Yok'
                    $TxtUsbCount.Foreground = [System.Windows.Media.Brushes]::Gray
                    if ($global:_UsbTickCounter -gt 2) { Write-Log "USB aygit cikarildi veya hic bagli degil." 'INFO' }
                }
            }
        } catch {}
    }

    # Aktif guc plani guncelle (her 10 tick = 20sn)
    if ($global:_UsbTickCounter % 10 -eq 0) {
        try {
            $activeLine = powercfg /getactivescheme 2>&1 | Where-Object { $_ -match 'Power Scheme GUID' } | Select-Object -First 1
            if ($activeLine -match '\((.+)\)') {
                $TxtActivePlan.Text = "Aktif plan: $($Matches[1])"
            }
        } catch {}
    }
})
$HWTimer.Start()

# ─── OTOMATIK SISTEM GERI YUKLEME NOKTASI ─────────────────────────────────────
# Her oturumda bir kez olusturulur — kullanicinin sistemi bozulursa 2dk'da geri donebilir
$global:_RestorePointCreated = $false
function Ensure-RestorePoint {
    if ($global:_RestorePointCreated) { return }
    try {
        Write-Log "Sistem Geri Yukleme Noktasi olusturuluyor..." 'RUN'
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description "LivnTools_Oncesi_$(Get-Date -Format 'yyyyMMdd_HHmm')" -RestorePointType 'MODIFY_SETTINGS' -ErrorAction SilentlyContinue
        $global:_RestorePointCreated = $true
        Write-Log "Sistem Geri Yukleme Noktasi olusturuldu." 'OK'
    } catch {
        Write-Log "Geri yukleme noktasi olusturulamadi: $_ (Windows kisitlamasi olabilir)" 'WARN'
    }
}

# ─── ASYNC RUNNER ─────────────────────────────────────────────────────────────
# Runs a scriptblock on a background runspace.
# Extra variables can be passed via -Vars hashtable and accessed as $using:VarName
function Invoke-Async {
    param(
        [scriptblock]$Block,
        [string]$TaskName    = 'Gorev',
        [hashtable]$Vars     = @{},
        [string]$ProgressKey = ''    # 'Perf','Net','Kern','GPU','Priv' — bos = bar yok
    )

    # ── Optimizasyon gorevi ise: Restore Point + Otomatik Backup ──
    if ($ProgressKey -ne '') {
        Ensure-RestorePoint
        # Otomatik Registry yedekleme — kullanici Backup butonunu unutsa bile korunur
        $autoBackupMap = @{
            'Perf' = @(
                @('HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management', 'Auto_Perf_MemMgmt')
                @('HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile', 'Auto_Perf_MM')
            )
            'Net'  = @(
                @('HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters', 'Auto_Net_TCP')
                @('HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters', 'Auto_Net_DNS')
            )
            'Kern' = @(
                @('HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard', 'Auto_Kern_DevGuard')
                @('HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management', 'Auto_Kern_MemMgmt')
                @('HKCU:\Control Panel\Mouse', 'Auto_Kern_Mouse')
            )
            'GPU'  = @(
                @('HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}', 'Auto_GPU_Class')
                @('HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers', 'Auto_GPU_GfxDrv')
            )
            'Priv' = @(
                @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection', 'Auto_Priv_DataColl')
                @('HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo', 'Auto_Priv_AdID')
            )
        }
        if ($autoBackupMap.ContainsKey($ProgressKey)) {
            try {
                foreach ($entry in $autoBackupMap[$ProgressKey]) {
                    Backup-Registry $entry[0] $entry[1]
                }
                Write-Log "Otomatik registry yedegi alindi ($ProgressKey)" 'OK'
            } catch { Write-Log "Otomatik yedek hatasi: $_" 'WARN' }
        }
    }

    Set-Busy $true
    Set-Status "$TaskName calisiyor..."
    Write-Log "=== $TaskName BASLADI ===" 'RUN'

    # Optimizasyon progress bar'ı göster
    if ($ProgressKey -and $global:_OptProgressBars[$ProgressKey]) {
        $pb = $global:_OptProgressBars[$ProgressKey]
        $pb.Container.Visibility = 'Visible'
        $pb.Fill.Width = 0
        $pb.Status.Text = 'Uygulanıyor...'
        $pb.Step.Text   = ''
    }

    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'STA'
    $rs.ThreadOptions  = 'ReuseThread'
    $rs.Open()

    # ── Sabit gecisler ───────────────────────────────────────────────────────
    $rs.SessionStateProxy.SetVariable('LogFile',    $global:LogFile)
    $rs.SessionStateProxy.SetVariable('BackupPath', $global:BackupPath)
    $rs.SessionStateProxy.SetVariable('RootPath',   $global:RootPath)
    $rs.SessionStateProxy.SetVariable('Window',     $Window)
    $rs.SessionStateProxy.SetVariable('Terminal',   $Terminal)

    # ── Dinamik degiskenler ($using:X sorununu cozer) ───────────────────────
    # $opts yerine direkt $opts olarak runspace'e set edilir
    foreach ($kv in $Vars.GetEnumerator()) {
        $rs.SessionStateProxy.SetVariable($kv.Key, $kv.Value)
    }

    # ── Write-Log runspace'te tanim ─────────────────────────────────────────
    $logFuncDef  = ${function:Write-Log}.ToString()

    # ── $using: referanslarini $varName'e donustur ───────────────────────────
    # Hem "$using:Var" hem "$using:Var.Property" kaliplarini yakalar
    $blockText   = $Block.ToString() -replace '\$using:(\w+)', '$$$1'
    $patchedBlock = [scriptblock]::Create($blockText)

    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript({
        param($logFuncDef, $block)
        . ([scriptblock]::Create("function Write-Log { $logFuncDef }"))
        & $block
    }).AddArgument($logFuncDef).AddArgument($patchedBlock)

    $handle = $ps.BeginInvoke()

    # DispatcherTimer closure'da dis scope degiskenler kaybolabiliyor.
    # Unique key ile global hashtable uzerinden erisiyoruz — tamamen guvenli.
    $timerKey = [System.Guid]::NewGuid().ToString()
    if (-not $global:_AsyncJobs) { $global:_AsyncJobs = @{} }
    $global:_AsyncJobs[$timerKey] = @{
        ps          = $ps
        rs          = $rs
        handle      = $handle
        taskName    = $TaskName
        progressKey = $ProgressKey
    }

    $watchTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $watchTimer.Interval = [TimeSpan]::FromMilliseconds(300)
    $watchTimer.Tag      = $timerKey

    $watchTimer.Add_Tick({
        param($sender, $e)
        $key = $sender.Tag
        $job = $global:_AsyncJobs[$key]
        if ($job -and $job.handle.IsCompleted) {
            $sender.Stop()
            try { $job.ps.EndInvoke($job.handle) } catch { Write-Log "Async hata: $_" 'ERROR' }
            try { $job.ps.Dispose() } catch {}
            try { $job.rs.Close(); $job.rs.Dispose() } catch {}
            $global:_AsyncJobs.Remove($key)
            Set-Busy $false
            Set-Status "$($job.taskName) tamamlandi."
            Write-Log "=== $($job.taskName) TAMAMLANDI ===" 'OK'
            if ($job.taskName -eq 'Advanced Clean') {
                $advCT = [System.Windows.Threading.DispatcherTimer]::new()
                $advCT.Interval = [TimeSpan]::FromSeconds(3)
                $advCT.Tag = $AdvCleanProgressContainer
                $advCT.Add_Tick({ param($s,$e); $s.Stop(); if ($s.Tag) { $s.Tag.Visibility = 'Collapsed' } })
                $advCT.Start()
            }
            # Progress bar'ı tamamlandı göster, sonra gizle
            if ($job.progressKey -and $global:_OptProgressBars[$job.progressKey]) {
                $pb = $global:_OptProgressBars[$job.progressKey]
                $pb.Status.Text       = 'Tamamlandi!'
                $pb.Status.Foreground = New-Brush '#4CAF50'
                $pb.Step.Text         = ''
                if ($pb.Track.ActualWidth -gt 0) {
                    $pb.Fill.Width      = $pb.Track.ActualWidth
                    $pb.Fill.Background = [System.Windows.Media.Brushes]::Green
                }
                # 2 saniye sonra gizle
                $hideTimer = [System.Windows.Threading.DispatcherTimer]::new()
                $hideTimer.Interval = [TimeSpan]::FromSeconds(2)
                $hideTimer.Tag = $pb
                $hideTimer.Add_Tick({
                    param($s,$e)
                    $s.Stop()
                    $s.Tag.Container.Visibility = 'Collapsed'
                })
                $hideTimer.Start()
            }
        }
    })
    $watchTimer.Start()
}

# ─── BACKEND: QUICK CLEAN ─────────────────────────────────────────────────────
function Get-CheckVal([string]$name) {
    $c = $Window.FindName($name)
    if ($c -eq $null) { return $false }
    return ($c.IsChecked -eq $true)
}

# ─── DRY HELPER: Checkbox isimlerinden opts hashtable olustur ─────────────────
# Kullanim: Get-PageOpts @{ HPET='ChkHPET'; TimerRes='ChkTimerRes'; ... }
# Apply butonlarinda ve Apply All'da tekrar eden $Window.FindName kodunu tek satirda toplar.
function Get-PageOpts([hashtable]$map) {
    $result = @{}
    foreach ($kv in $map.GetEnumerator()) {
        $result[$kv.Key] = (Get-CheckVal $kv.Value)
    }
    return $result
}

$BtnSelectAllQC.Add_Click({
    # Sistem checkbox'lari her zaman isaretlenir
    @('ChkTempWin','ChkTempSys','ChkPrefetch','ChkRecycleBin','ChkThumb','ChkFontCache',
      'ChkDNSCache','ChkEventLogs','ChkCrashDumps','ChkWinUpdCache','ChkDeliveryOpt') | ForEach-Object {
        $c = $Window.FindName($_); if ($c) { $c.IsChecked = $true }
    }
    # App checkbox'lari: sadece IsEnabled=True olanlar (kurulu)
    @('ChkChromeCache','ChkEdgeCache','ChkFirefoxCache','ChkBraveCache','ChkOperaCache',
      'ChkVivaldiCache','ChkTorCache',
      'ChkDiscordCache','ChkTelegramCache','ChkWhatsAppCache','ChkSlackCache',
      'ChkZoomCache','ChkTeamsCache','ChkSkypeCache','ChkSpotifyCache',
      'ChkSteamCache','ChkEpicCache','ChkGOGCache','ChkUbisoftCache','ChkEACache',
      'ChkXboxCache','ChkBnetCache','ChkRockstarCache','ChkRiotCache','ChkMinecraftCache') | ForEach-Object {
        $c = $Window.FindName($_)
        if ($c -and $c.IsEnabled) { $c.IsChecked = $true }
    }
})
$BtnDeselectAllQC.Add_Click({
    @('ChkTempWin','ChkTempSys','ChkPrefetch','ChkRecycleBin','ChkThumb','ChkFontCache',
      'ChkDNSCache','ChkEventLogs','ChkCrashDumps','ChkWinUpdCache','ChkDeliveryOpt',
      'ChkChromeCache','ChkEdgeCache','ChkFirefoxCache','ChkBraveCache','ChkOperaCache',
      'ChkVivaldiCache','ChkTorCache',
      'ChkDiscordCache','ChkTelegramCache','ChkWhatsAppCache','ChkSlackCache',
      'ChkZoomCache','ChkTeamsCache','ChkSkypeCache','ChkSpotifyCache',
      'ChkSteamCache','ChkEpicCache','ChkGOGCache','ChkUbisoftCache','ChkEACache',
      'ChkXboxCache','ChkBnetCache','ChkRockstarCache','ChkRiotCache','ChkMinecraftCache') | ForEach-Object {
        $c = $Window.FindName($_); if ($c) { $c.IsChecked = $false }
    }
})

$BtnRunQuickClean.Add_Click({
    # ── USB UYARI POPUP ─────────────────────────────────────────────────────
    $usbNow = @(Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceType -eq 'USB' })
    if ($usbNow.Count -gt 0) {
        $usbNames = ($usbNow | ForEach-Object { "  - $($_.Model)" }) -join "`n"
        $usbResult = [System.Windows.MessageBox]::Show(
            "USB depolama aygiti bagli!`n`n$usbNames`n`nTemizlik USB uzerindeki dosyalari etkilemez, ancak devam etmek istiyor musunuz?",
            "USB Aygit Bagli",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Warning)
        if ($usbResult -ne [System.Windows.MessageBoxResult]::Yes) {
            Write-Log "Temizlik USB uyarisi nedeniyle iptal edildi." 'WARN'
            return
        }
    }

    # ── UI thread'de checkbox degerlerini oku ───────────────────────────────
    $opts = @{
        TempWin     = (Get-CheckVal 'ChkTempWin')
        TempSys     = (Get-CheckVal 'ChkTempSys')
        Prefetch    = (Get-CheckVal 'ChkPrefetch')
        Recycle     = (Get-CheckVal 'ChkRecycleBin')
        Thumb       = (Get-CheckVal 'ChkThumb')
        FontCache   = (Get-CheckVal 'ChkFontCache')
        # Tarayicilar
        Chrome      = (Get-CheckVal 'ChkChromeCache')
        Edge        = (Get-CheckVal 'ChkEdgeCache')
        Firefox     = (Get-CheckVal 'ChkFirefoxCache')
        Brave       = (Get-CheckVal 'ChkBraveCache')
        Opera       = (Get-CheckVal 'ChkOperaCache')
        Vivaldi     = (Get-CheckVal 'ChkVivaldiCache')
        Tor         = (Get-CheckVal 'ChkTorCache')
        # Iletisim / Sosyal
        Discord     = (Get-CheckVal 'ChkDiscordCache')
        Telegram    = (Get-CheckVal 'ChkTelegramCache')
        WhatsApp    = (Get-CheckVal 'ChkWhatsAppCache')
        Slack       = (Get-CheckVal 'ChkSlackCache')
        Zoom        = (Get-CheckVal 'ChkZoomCache')
        Teams       = (Get-CheckVal 'ChkTeamsCache')
        Skype       = (Get-CheckVal 'ChkSkypeCache')
        Spotify     = (Get-CheckVal 'ChkSpotifyCache')
        # Oyun Launcher
        Steam       = (Get-CheckVal 'ChkSteamCache')
        EpicCache   = (Get-CheckVal 'ChkEpicCache')
        GOG         = (Get-CheckVal 'ChkGOGCache')
        Ubisoft     = (Get-CheckVal 'ChkUbisoftCache')
        EA          = (Get-CheckVal 'ChkEACache')
        Xbox        = (Get-CheckVal 'ChkXboxCache')
        Bnet        = (Get-CheckVal 'ChkBnetCache')
        Rockstar    = (Get-CheckVal 'ChkRockstarCache')
        Riot        = (Get-CheckVal 'ChkRiotCache')
        Minecraft   = (Get-CheckVal 'ChkMinecraftCache')
        # Log / Sistem
        DNS         = (Get-CheckVal 'ChkDNSCache')
        EventLogs   = (Get-CheckVal 'ChkEventLogs')
        CrashDumps  = (Get-CheckVal 'ChkCrashDumps')
        WinUpdCache = (Get-CheckVal 'ChkWinUpdCache')
        DelivOpt    = (Get-CheckVal 'ChkDeliveryOpt')
    }

    # ── Acik uygulama: Force Close sorusu (UI thread'de calis) ─────────────────
    $procChecks = @(
        @{ Key='Chrome';    Proc=@('chrome');                  Name='Google Chrome'      }
        @{ Key='Edge';      Proc=@('msedge');                  Name='Microsoft Edge'     }
        @{ Key='Firefox';   Proc=@('firefox');                 Name='Mozilla Firefox'    }
        @{ Key='Brave';     Proc=@('brave');                   Name='Brave Browser'      }
        @{ Key='Opera';     Proc=@('opera');                   Name='Opera'              }
        @{ Key='Opera';    Proc=@('opera','opera_gx_setup');  Name='Opera GX'           }  # Opera ve OperaGX aynı cache
        @{ Key='Vivaldi';   Proc=@('vivaldi');                 Name='Vivaldi'            }
        @{ Key='Discord';   Proc=@('Discord');                 Name='Discord'            }
        @{ Key='Telegram';  Proc=@('Telegram');                Name='Telegram'           }
        @{ Key='Slack';     Proc=@('slack');                   Name='Slack'              }
        @{ Key='Zoom';      Proc=@('Zoom');                    Name='Zoom'               }
        @{ Key='Teams';     Proc=@('ms-teams','Teams');        Name='Microsoft Teams'    }
        @{ Key='Spotify';   Proc=@('Spotify');                 Name='Spotify'            }
        @{ Key='Steam';     Proc=@('steam');                   Name='Steam'              }
        @{ Key='EpicCache'; Proc=@('EpicGamesLauncher');       Name='Epic Games'         }
        @{ Key='Ubisoft';   Proc=@('upc','UbisoftConnect');    Name='Ubisoft Connect'    }
        @{ Key='EA';        Proc=@('EADesktop','EALauncher');  Name='EA Desktop'         }
        @{ Key='Bnet';      Proc=@('Battle.net','Agent');      Name='Battle.net'         }
        @{ Key='Rockstar';  Proc=@('Launcher');                Name='Rockstar Launcher'  }
        @{ Key='Riot';      Proc=@('RiotClientServices');      Name='Riot Client'        }
    )
    foreach ($chk in $procChecks) {
        if ($opts[$chk.Key]) {
            # Process'leri al — arka plan servislerini dışla (Edge WebView2, Update, vs.)
            # MainWindowHandle != IntPtr.Zero = gerçek kullanıcı penceresi açık
            $allProcs = $chk.Proc | ForEach-Object {
                Get-Process -Name $_ -ErrorAction SilentlyContinue
            } | Where-Object { $_ }
            $running = $allProcs | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero }
            if ($running) {
                $r = [System.Windows.MessageBox]::Show(
                    "$($chk.Name) su anda acik!`n`nTemizlik icin kapatilmasi gerekiyor.`n`n[Evet]  → Uygulama kapatilarak temizlik yapilir`n[Hayir] → Bu uygulama temizligi atlanir",
                    "$($chk.Name) Acik",
                    [System.Windows.MessageBoxButton]::YesNo,
                    [System.Windows.MessageBoxImage]::Warning)
                if ($r -eq [System.Windows.MessageBoxResult]::Yes) {
                    $running | Stop-Process -Force -ErrorAction SilentlyContinue
                    Write-Log "$($chk.Name) kapatildi, temizlenecek." 'INFO'
                    Start-Sleep -Milliseconds 800  # Process'in tamamen kapanması için kısa bekleme
                } else {
                    $opts[$chk.Key] = $false
                    Write-Log "$($chk.Name) acik, bu temizlik atlandi." 'WARN'
                }
            }
        }
    }

    # ── Kurulu olmayan uygulamalari filtrele ─────────────────────────────────
    @(
        @{ Key='Chrome';    AppKey='Chrome'         }
        @{ Key='Edge';      AppKey='Edge'            }
        @{ Key='Firefox';   AppKey='Firefox'         }
        @{ Key='Brave';     AppKey='Brave'           }
        @{ Key='Opera';     AppKey='Opera'           }

        @{ Key='Vivaldi';   AppKey='Vivaldi'         }
        @{ Key='Tor';       AppKey='Tor'             }
        @{ Key='Discord';   AppKey='Discord'         }
        @{ Key='Telegram';  AppKey='Telegram'        }
        @{ Key='WhatsApp';  AppKey='WhatsApp'        }
        @{ Key='Slack';     AppKey='Slack'           }
        @{ Key='Zoom';      AppKey='Zoom'            }
        @{ Key='Teams';     AppKey='Teams'           }
        @{ Key='Skype';     AppKey='Skype'           }
        @{ Key='Spotify';   AppKey='Spotify'         }
        @{ Key='Steam';     AppKey='Steam'           }
        @{ Key='EpicCache'; AppKey='EpicGames'       }
        @{ Key='GOG';       AppKey='GOGGalaxy'       }
        @{ Key='Ubisoft';   AppKey='UbisoftConnect'  }
        @{ Key='EA';        AppKey='EADesktop'       }
        @{ Key='Xbox';      AppKey='Xbox'            }
        @{ Key='Bnet';      AppKey='Battlenet'       }
        @{ Key='Rockstar';  AppKey='Rockstar'        }
        @{ Key='Riot';      AppKey='Riot'            }
        @{ Key='Minecraft'; AppKey='Minecraft'       }
    ) | ForEach-Object {
        if ($opts[$_.Key] -and -not $global:AppInstalled[$_.AppKey]) {
            $opts[$_.Key] = $false
        }
    }

    # ── Baslangic disk alani ─────────────────────────────────────────────────
    try {
        $driveLetter = ($env:SystemDrive -replace ':','')
        $diskBefore  = Get-PSDrive $driveLetter -ErrorAction SilentlyContinue
        if ($diskBefore) {
            $global:_QCBeforeGB = [math]::Round($diskBefore.Free / 1GB, 2)
            Write-Log "$env:SystemDrive Bos Alan (once ): $($global:_QCBeforeGB) GB" 'INFO'
        }
    } catch {}

    # ── Temizligi runspace'te calistir — opts hashtable direkt geciliyor ─────
    Reset-CleanProgress

    # Tahmini boyutu hesapla (hangi klasorlerin var olduguna bak)
    $estBytes = [long]0
    $checkPaths = @(
        "$env:TEMP", "$env:SystemRoot\Temp", "$env:SystemRoot\Prefetch",
        "$env:LocalAppData\Google\Chrome\User Data",
        "$env:LocalAppData\Microsoft\Edge\User Data",
        "$env:APPDATA\discord\Cache",
        "$env:LOCALAPPDATA\Spotify\Storage"
    )
    foreach ($p in $checkPaths) {
        if (Test-Path $p) {
            try {
                $sz = (Get-ChildItem $p -Recurse -Force -ErrorAction SilentlyContinue |
                       Where-Object { -not $_.PSIsContainer } |
                       Measure-Object -Property Length -Sum).Sum
                if ($sz) { $estBytes += $sz }
            } catch {}
        }
    }
    if ($estBytes -lt 1MB) { $estBytes = 50MB }  # fallback minimum
    $script:_cleanExpectedBytes = $estBytes

    Invoke-Async -TaskName 'Quick Clean' -Vars @{
        opts               = $opts
        Window             = $Window
        CleanProgressContainer = $CleanProgressContainer
        CleanProgressFill  = $CleanProgressFill
        CleanProgressTrack = $CleanProgressTrack
        TxtCleanStatus     = $TxtCleanStatus
        TxtCleanPct        = $TxtCleanPct
    } -Block {

        $totalBytes = [long]0

        function Remove-SafeFolder([string]$path, [string]$label='') {
            if (-not (Test-Path $path)) { return }
            try {
                $items = Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue
                $bytes = ($items | Where-Object { -not $_.PSIsContainer } |
                          Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                if (-not $bytes) { $bytes = [long]0 }
                Remove-Item -Path "$path\*" -Recurse -Force -ErrorAction SilentlyContinue
                if ($bytes -gt 0) {
                    $mb = [math]::Round($bytes / 1MB, 1)
                    $lbl = if ($label) { $label } else { Split-Path $path -Leaf }
                    Write-Log "$lbl temizlendi: $mb MB" 'OK'
                } else {
                    $lbl = if ($label) { $label } else { Split-Path $path -Leaf }
                    Write-Log "$lbl zaten temizdi" 'INFO'
                }
                $script:totalBytes += $bytes
                # Progress guncelle
                $Window.Dispatcher.Invoke([action]{
                    if ($CleanProgressTrack.ActualWidth -gt 0) {
                        $pct = [math]::Min(99, [math]::Round($script:totalBytes / [math]::Max($script:totalBytes + 10MB, 50MB) * 100))
                        $targetW = [math]::Round($CleanProgressTrack.ActualWidth * $pct / 100, 1)
                        $anim = [System.Windows.Media.Animation.DoubleAnimation]::new()
                        $anim.To       = $targetW
                        $anim.Duration = [System.Windows.Duration][TimeSpan]::FromMilliseconds(200)
                        $CleanProgressFill.BeginAnimation([System.Windows.FrameworkElement]::WidthProperty, $anim)
                        $TxtCleanPct.Text = "  $pct%"
                        if ($lbl) { $TxtCleanStatus.Text = "$lbl temizlendi..." }
                    }
                })
            } catch {
                Write-Log "Temizlenemedi: $path - $_" 'WARN'
            }
        }
        $script:totalBytes = [long]0

        # ── WINDOWS GECICI DOSYALAR ──────────────────────────────────────────
        if ($opts.TempWin)  { Remove-SafeFolder $env:TEMP            'Windows Temp' }
        if ($opts.TempSys)  { Remove-SafeFolder "$env:SystemRoot\Temp" 'System Temp' }
        if ($opts.Prefetch) { Remove-SafeFolder "$env:SystemRoot\Prefetch" 'Prefetch' }
        if ($opts.Recycle) {
            try {
                $recyclePath = "$env:SystemDrive\`$Recycle.Bin"
                $rbytes = (Get-ChildItem $recyclePath -Recurse -Force -ErrorAction SilentlyContinue |
                           Where-Object { -not $_.PSIsContainer } |
                           Measure-Object -Property Length -Sum).Sum
                if (-not $rbytes) { $rbytes = [long]0 }
                Clear-RecycleBin -Force -ErrorAction SilentlyContinue
                $script:totalBytes += $rbytes
                Write-Log "Geri Donusum Kutusu temizlendi" 'OK'
            } catch { Write-Log "Recycle bin temizlenemedi: $_" 'WARN' }
        }
        if ($opts.Thumb) {
            $thumbFiles = @(
                "$env:LocalAppData\Microsoft\Windows\Explorer\thumbcache_*.db",
                "$env:LocalAppData\Microsoft\Windows\Explorer\iconcache_*.db"
            )
            foreach ($tp in $thumbFiles) {
                $tbytes = (Get-Item $tp -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                if ($tbytes) { $script:totalBytes += $tbytes }
                Remove-Item $tp -Force -ErrorAction SilentlyContinue
            }
            Write-Log "Thumbnail cache temizlendi" 'OK'
        }
        if ($opts.FontCache) {
            Stop-Service 'FontCache'        -Force -ErrorAction SilentlyContinue
            Stop-Service 'FontCache3.0.0.0' -Force -ErrorAction SilentlyContinue
            Remove-Item "$env:LocalAppData\FontCache\*" -Force -Recurse -ErrorAction SilentlyContinue
            Remove-Item "$env:WinDir\ServiceProfiles\LocalService\AppData\Local\FontCache\*" -Force -Recurse -ErrorAction SilentlyContinue
            Start-Service 'FontCache' -ErrorAction SilentlyContinue
            Write-Log "Font cache temizlendi" 'OK'
        }

        # ── TARAYICI CACHE ───────────────────────────────────────────────────
        if ($opts.Chrome) {
            $chromeBase = "$env:LocalAppData\Google\Chrome\User Data"
            if (Test-Path $chromeBase) {
                Get-ChildItem $chromeBase -Directory | Where-Object { $_.Name -match '^(Default|Profile \d+)$' } | ForEach-Object {
                    Remove-SafeFolder "$($_.FullName)\Cache"      'Chrome Cache'
                    Remove-SafeFolder "$($_.FullName)\Code Cache" 'Chrome Code Cache'
                    Remove-SafeFolder "$($_.FullName)\GPUCache"   'Chrome GPUCache'
                }
            }
        }
        if ($opts.Edge) {
            $edgeBase = "$env:LocalAppData\Microsoft\Edge\User Data"
            if (Test-Path $edgeBase) {
                Get-ChildItem $edgeBase -Directory | Where-Object { $_.Name -match '^(Default|Profile \d+)$' } | ForEach-Object {
                    Remove-SafeFolder "$($_.FullName)\Cache"      'Edge Cache'
                    Remove-SafeFolder "$($_.FullName)\Code Cache" 'Edge Code Cache'
                    Remove-SafeFolder "$($_.FullName)\GPUCache"   'Edge GPUCache'
                }
            }
        }
        if ($opts.Brave) {
            $braveBase = "$env:LocalAppData\BraveSoftware\Brave-Browser\User Data"
            if (Test-Path $braveBase) {
                Get-ChildItem $braveBase -Directory | Where-Object { $_.Name -match '^(Default|Profile \d+)$' } | ForEach-Object {
                    Remove-SafeFolder "$($_.FullName)\Cache"      'Brave Cache'
                    Remove-SafeFolder "$($_.FullName)\Code Cache" 'Brave Code Cache'
                    Remove-SafeFolder "$($_.FullName)\GPUCache"   'Brave GPUCache'
                }
            }
        }
        if ($opts.Opera) {
            Remove-SafeFolder "$env:APPDATA\Opera Software\Opera Stable\Cache"        'Opera Cache'
            Remove-SafeFolder "$env:APPDATA\Opera Software\Opera Stable\Code Cache"   'Opera Code Cache'
            Remove-SafeFolder "$env:APPDATA\Opera Software\Opera GX Stable\Cache"     'Opera GX Cache'
            Remove-SafeFolder "$env:APPDATA\Opera Software\Opera GX Stable\Code Cache" 'Opera GX Code Cache'
        }
        if ($opts.Firefox) {
            $ffDir = "$env:AppData\Mozilla\Firefox\Profiles"
            if (Test-Path $ffDir) {
                Get-ChildItem $ffDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                    Remove-SafeFolder "$($_.FullName)\cache2"        'Firefox Cache'
                    Remove-SafeFolder "$($_.FullName)\thumbnails"    'Firefox Thumbnails'
                    Remove-SafeFolder "$($_.FullName)\startupCache"  'Firefox StartupCache'
                }
            }
        }
        if ($opts.Vivaldi) {
            $vivaldiBase = "$env:LocalAppData\Vivaldi\User Data"
            if (Test-Path $vivaldiBase) {
                Get-ChildItem $vivaldiBase -Directory | Where-Object { $_.Name -match '^(Default|Profile \d+)$' } | ForEach-Object {
                    Remove-SafeFolder "$($_.FullName)\Cache"      'Vivaldi Cache'
                    Remove-SafeFolder "$($_.FullName)\Code Cache" 'Vivaldi Code Cache'
                }
            }
        }
        if ($opts.Tor) {
            Remove-SafeFolder "$env:LocalAppData\Tor Browser\Browser\TorBrowser\Data\Browser\profile.default\cache2" 'Tor Cache'
        }

        # ── ILETISIM / SOSYAL ────────────────────────────────────────────────
        if ($opts.Discord) {
            Remove-SafeFolder "$env:APPDATA\discord\Cache"      'Discord Cache'
            Remove-SafeFolder "$env:APPDATA\discord\Code Cache" 'Discord Code Cache'
            Remove-SafeFolder "$env:APPDATA\discord\GPUCache"   'Discord GPUCache'
            Remove-SafeFolder "$env:APPDATA\discord\logs"       'Discord Logs'
        }
        if ($opts.Telegram) {
            $tgBase = "$env:APPDATA\Telegram Desktop\tdata"
            if (Test-Path $tgBase) {
                $tlogs = Get-ChildItem $tgBase -Filter "*.log" -Recurse -ErrorAction SilentlyContinue
                $tbytes = ($tlogs | Measure-Object -Property Length -Sum).Sum
                if ($tbytes) { $script:totalBytes += $tbytes }
                $tlogs | Remove-Item -Force -ErrorAction SilentlyContinue
            }
            Write-Log "Telegram log temizlendi" 'OK'
        }
        if ($opts.WhatsApp) {
            Remove-SafeFolder "$env:LOCALAPPDATA\WhatsApp\Cache"      'WhatsApp Cache'
            Remove-SafeFolder "$env:LOCALAPPDATA\WhatsApp\Code Cache" 'WhatsApp Code Cache'
            Remove-SafeFolder "$env:LOCALAPPDATA\Packages\5319275A.WhatsAppDesktop_cv1g1gvanyjgm\LocalCache" 'WhatsApp LocalCache'
        }
        if ($opts.Slack) {
            Remove-SafeFolder "$env:APPDATA\Slack\Cache"      'Slack Cache'
            Remove-SafeFolder "$env:APPDATA\Slack\Code Cache" 'Slack Code Cache'
            Remove-SafeFolder "$env:APPDATA\Slack\GPUCache"   'Slack GPUCache'
        }
        if ($opts.Zoom) {
            Remove-SafeFolder "$env:APPDATA\Zoom\data\Cache" 'Zoom Cache'
            $zlogs = Get-ChildItem "$env:APPDATA\Zoom" -Filter "*.log" -Recurse -ErrorAction SilentlyContinue
            $zbytes = ($zlogs | Measure-Object -Property Length -Sum).Sum
            if ($zbytes) { $script:totalBytes += $zbytes }
            $zlogs | Remove-Item -Force -ErrorAction SilentlyContinue
        }
        if ($opts.Teams) {
            Remove-SafeFolder "$env:LOCALAPPDATA\Microsoft\Teams\Cache"      'Teams Cache'
            Remove-SafeFolder "$env:LOCALAPPDATA\Microsoft\Teams\Code Cache" 'Teams Code Cache'
            Remove-SafeFolder "$env:LOCALAPPDATA\Microsoft\Teams\GPUCache"   'Teams GPUCache'
            Remove-SafeFolder "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache" 'Teams LocalCache'
        }
        if ($opts.Skype) {
            Remove-SafeFolder "$env:LOCALAPPDATA\Packages\Microsoft.SkypeApp_kzf8qxf38zg5c\LocalCache" 'Skype Cache'
        }
        if ($opts.Spotify) {
            Remove-SafeFolder "$env:LOCALAPPDATA\Spotify\Storage" 'Spotify Storage'
            Remove-SafeFolder "$env:LOCALAPPDATA\Spotify\Data"    'Spotify Data'
        }

        # ── OYUN LAUNCHER ────────────────────────────────────────────────────
        if ($opts.Steam) {
            Remove-SafeFolder "$env:LocalAppData\Steam\htmlcache"             'Steam HTMLCache'
            Remove-SafeFolder "$env:LocalAppData\Steam\appcache\httpcache"    'Steam HTTPCache'
        }
        if ($opts.EpicCache) {
            Remove-SafeFolder "$env:LocalAppData\EpicGamesLauncher\Saved\webcache" 'Epic WebCache'
            Remove-SafeFolder "$env:LocalAppData\EpicGamesLauncher\Saved\logs"     'Epic Logs'
        }
        if ($opts.GOG) {
            Remove-SafeFolder "$env:LocalAppData\GOG.com\Galaxy\webcache"  'GOG WebCache'
            Remove-SafeFolder "$env:LocalAppData\GOG.com\Galaxy\logs"      'GOG Logs'
            Remove-SafeFolder "$env:ProgramData\GOG.com\Galaxy\logs"       'GOG ProgramData Logs'
        }
        if ($opts.Ubisoft) {
            Remove-SafeFolder "$env:LocalAppData\Ubisoft Game Launcher\cache" 'Ubisoft Cache'
            Remove-SafeFolder "$env:LOCALAPPDATA\Uplay\logs"                  'Uplay Logs'
        }
        if ($opts.EA) {
            Remove-SafeFolder "$env:LOCALAPPDATA\Electronic Arts\EA Desktop\cache" 'EA Cache'
            Remove-SafeFolder "$env:LOCALAPPDATA\EADesktop\cache"                  'EA Desktop Cache'
            Remove-SafeFolder "$env:PROGRAMDATA\Electronic Arts\EA Desktop\Logs"   'EA Logs'
        }
        if ($opts.Xbox) {
            Remove-SafeFolder "$env:LOCALAPPDATA\Packages\Microsoft.GamingApp_8wekyb3d8bbwe\LocalCache"  'Xbox Gaming Cache'
            Remove-SafeFolder "$env:LOCALAPPDATA\Packages\Microsoft.XboxApp_8wekyb3d8bbwe\LocalCache"    'Xbox App Cache'
        }
        if ($opts.Bnet) {
            Remove-SafeFolder "$env:APPDATA\Battle.net\Cache"                      'Battle.net Cache'
            Remove-SafeFolder "$env:ProgramData\Battle.net\Agent\data\cache"       'Battle.net Agent Cache'
        }
        if ($opts.Rockstar) {
            Remove-SafeFolder "$env:LocalAppData\Rockstar Games\Launcher\cache"         'Rockstar Cache'
            Remove-SafeFolder "$env:LocalAppData\Rockstar Games\Launcher\CrashReports"  'Rockstar CrashReports'
        }
        if ($opts.Riot) {
            Remove-SafeFolder "$env:LocalAppData\Riot Games\Riot Client\Cache"      'Riot Cache'
            Remove-SafeFolder "$env:LocalAppData\Riot Games\Riot Client\Code Cache" 'Riot Code Cache'
            Remove-SafeFolder "$env:LocalAppData\Riot Games\Riot Client\GPUCache"   'Riot GPUCache'
            Remove-SafeFolder "$env:LocalAppData\Riot Games\League of Legends\Logs" 'LoL Logs'
            Remove-SafeFolder "$env:LocalAppData\Riot Games\VALORANT\Saved\Logs"    'Valorant Logs'
        }
        if ($opts.Minecraft) {
            Remove-SafeFolder "$env:APPDATA\.minecraft\logs"          'Minecraft Logs'
            Remove-SafeFolder "$env:APPDATA\.minecraft\crash-reports" 'Minecraft Crash Reports'
        }

        # ── LOG & SISTEM ─────────────────────────────────────────────────────
        if ($opts.DNS) {
            ipconfig /flushdns | Out-Null
            Write-Log "DNS cache temizlendi" 'OK'
        }
        if ($opts.EventLogs) {
            try {
                $logNames = wevtutil el 2>&1
                foreach ($logName in $logNames) {
                    if ([string]::IsNullOrWhiteSpace($logName)) { continue }
                    wevtutil cl $logName 2>&1 | Out-Null
                }
                Write-Log "Windows Event Logs temizlendi" 'OK'
            } catch { Write-Log "Event Logs temizlenemedi: $_" 'WARN' }
        }
        if ($opts.CrashDumps) {
            $dumpPaths = @(
                "$env:SystemRoot\Minidump\*.dmp",
                "$env:LocalAppData\CrashDumps\*.dmp",
                "$env:APPDATA\*.dmp"
            )
            $dbytes = [long]0
            foreach ($dp in $dumpPaths) {
                $dfiles = Get-Item $dp -ErrorAction SilentlyContinue
                if ($dfiles) {
                    $dbytes += ($dfiles | Measure-Object -Property Length -Sum).Sum
                    $dfiles | Remove-Item -Force -ErrorAction SilentlyContinue
                }
            }
            Get-ChildItem "$env:SystemRoot" -Filter "*.dmp" -Depth 1 -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
            if ($dbytes) { $script:totalBytes += $dbytes }
            Write-Log "Crash dump dosyalari temizlendi" 'OK'
        }
        if ($opts.WinUpdCache) {
            Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
            Remove-SafeFolder "$env:SystemRoot\SoftwareDistribution\Download" 'WinUpdate Cache'
            Start-Service wuauserv -ErrorAction SilentlyContinue
        }
        if ($opts.DelivOpt) {
            Remove-SafeFolder "$env:SystemRoot\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache" 'Delivery Optimization'
        }

        # ── FIX 5: BITIS RAPORU ──────────────────────────────────────────────
        $savedMB = [math]::Round($script:totalBytes / 1MB, 1)
        if ($savedMB -gt 0) {
            Write-Log "===============================" 'INFO'
            Write-Log "TAMAMLANDI! Toplam temizlenen: $savedMB MB" 'OK'
            Write-Log "===============================" 'INFO'
        } else {
            Write-Log "TAMAMLANDI! Sistem zaten temizdi, temizlenecek bir sey bulunamadi." 'OK'
        }
        # Progress bar'i %100'e getir
        $Window.Dispatcher.Invoke([action]{
            if ($CleanProgressTrack.ActualWidth -gt 0) {
                $anim = [System.Windows.Media.Animation.DoubleAnimation]::new()
                $anim.To       = $CleanProgressTrack.ActualWidth
                $anim.Duration = [System.Windows.Duration][TimeSpan]::FromMilliseconds(300)
                $CleanProgressFill.BeginAnimation([System.Windows.FrameworkElement]::WidthProperty, $anim)
            }
            $TxtCleanPct.Text    = '  100%'
            $TxtCleanStatus.Text = if ($savedMB -gt 0) { "Tamamlandi! $savedMB MB temizlendi" } else { "Sistem zaten temizdi." }
        })
    }
})

# ─── BACKEND: ADVANCED CLEAN ──────────────────────────────────────────────────
$BtnRunAdvClean.Add_Click({
    $opts = @{
        WinSxS      = (Get-CheckVal 'ChkWinSxS')
        SuperFetch  = (Get-CheckVal 'ChkSuperFetch')
        Hibernation = (Get-CheckVal 'ChkHibernation')
        PageFile    = (Get-CheckVal 'ChkPageFile')
        SFC         = (Get-CheckVal 'ChkSFC')
        DISM        = (Get-CheckVal 'ChkDISM')
        DiskCleanup = (Get-CheckVal 'ChkDiskCleanup')
        USBHistory  = (Get-CheckVal 'ChkUSBHistory')
    }

    # Seçili adım sayısını hesapla (progress için)
    $totalSteps = ($opts.Values | Where-Object { $_ -eq $true }).Count
    if ($totalSteps -eq 0) { Write-Log "Hicbir islem secilmedi." 'WARN'; return }

    # Progress bar göster
    $Window.Dispatcher.Invoke([action]{
        $AdvCleanProgressContainer.Visibility = 'Visible'
        $AdvCleanProgressFill.Width = 0
        $TxtAdvCleanStatus.Text = 'Baslatiliyor...'
        $TxtAdvCleanStep.Text   = "0 / $totalSteps"
    })

    # Disk alanı ölçümü başlangıç
    $advDriveLetter = ($env:SystemDrive -replace ':','')
    $advDiskBefore = 0
    try {
        $d = Get-PSDrive $advDriveLetter -EA SilentlyContinue
        if ($d) { $advDiskBefore = [math]::Round($d.Free / 1GB, 2) }
    } catch {}

    Invoke-Async -TaskName 'Advanced Clean' -Vars @{
        opts                       = $opts
        totalSteps                 = $totalSteps
        Window                     = $Window
        AdvCleanProgressContainer  = $AdvCleanProgressContainer
        AdvCleanProgressFill       = $AdvCleanProgressFill
        AdvCleanProgressTrack      = $AdvCleanProgressTrack
        TxtAdvCleanStatus          = $TxtAdvCleanStatus
        TxtAdvCleanStep            = $TxtAdvCleanStep
        advDiskBefore              = $advDiskBefore
        advDriveLetter             = $advDriveLetter
    } -Block {

        $currentStep = 0

        function Advance-Step([string]$label) {
            $script:currentStep++
            $pct = [math]::Round($script:currentStep / $totalSteps * 100)
            $Window.Dispatcher.Invoke([action]{
                if ($AdvCleanProgressTrack.ActualWidth -gt 0) {
                    $targetW = [math]::Round($AdvCleanProgressTrack.ActualWidth * $pct / 100, 1)
                    $anim = [System.Windows.Media.Animation.DoubleAnimation]::new()
                    $anim.To       = $targetW
                    $anim.Duration = [System.Windows.Duration][TimeSpan]::FromMilliseconds(300)
                    $AdvCleanProgressFill.BeginAnimation([System.Windows.FrameworkElement]::WidthProperty, $anim)
                }
                $TxtAdvCleanStatus.Text = $label
                $TxtAdvCleanStep.Text   = "$($script:currentStep) / $totalSteps"
            })
        }

        # ── DISM/SFC çıktı filtresi ──────────────────────────────────────────────
        # sfc.exe UTF-16LE çıktı verir → null byte'ları temizle, sonra filtrele
        function Write-FilteredLog([string]$line, [string]$prefix='') {
            # UTF-16 null byte'larını temizle (sfc.exe sorunu)
            $line = $line -replace '\x00', ''
            if ([string]::IsNullOrWhiteSpace($line)) { return }
            # Progress/yüzde satırlarını atla
            if ($line -match '^\s*\[=')                            { return }
            if ($line -match '\d+\.\d+%')                          { return }
            if ($line -match 'Verification\s+\d+%')               { return }
            if ($line -match 'Yukleme tamamlanma')                 { return }
            if ($line -match '^\s*progress\s*:')                   { return }
            Write-Log "$prefix$($line.Trim())" 'INFO'
        }

        # ── DISM çıktısını ProcessStartInfo ile al ────────────────────────────
        function Invoke-DISM([string[]]$DismArgs) {
            # cmd /c ile çalıştır — DISM bazen UTF8 encoding ile argüman sorunları yaşıyor
            $cmdArgs = '/c dism.exe ' + ($DismArgs -join ' ')
            $psi = [System.Diagnostics.ProcessStartInfo]::new()
            $psi.FileName               = 'cmd.exe'
            $psi.Arguments              = $cmdArgs
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError  = $true
            $psi.UseShellExecute        = $false
            $psi.CreateNoWindow         = $true
            $psi.StandardOutputEncoding = [System.Text.Encoding]::GetEncoding(850)  # OEM CP850
            $p = [System.Diagnostics.Process]::Start($psi)
            while (-not $p.StandardOutput.EndOfStream) {
                $l = $p.StandardOutput.ReadLine()
                if ([string]::IsNullOrWhiteSpace($l))     { continue }
                if ($l -match '\d+\.\d+%')                { continue }
                if ($l -match '^\s*\[=')                  { continue }
                if ($l -match 'Yukleme tamamlanma')       { continue }
                # DISM help metni satırlarını atla (argümanlar yanlış gittiğinde çıkar)
                if ($l -match '/Capture-Ffu|/Apply-Ffu|WIM COMMANDS|FFU COMMANDS|GENERIC IMAGING') { continue }
                if ($l -match 'DISM\.exe \[dism_options\]') { continue }
                Write-Log "[DISM] $($l.Trim())" 'INFO'
            }
            $p.WaitForExit()
            return $p.ExitCode
        }

        # ── SFC: UTF-16LE → UTF-8 dönüşümü için temp dosya yöntemi ──────────
        function Invoke-SFC {
            $tmp = [System.IO.Path]::GetTempFileName()
            try {
                $p = Start-Process -FilePath 'cmd.exe' `
                    -ArgumentList "/c sfc /scannow > `"$tmp`" 2>&1" `
                    -Wait -PassThru -WindowStyle Hidden -Verb RunAs
                $raw = [System.IO.File]::ReadAllText($tmp, [System.Text.Encoding]::Unicode)
                $lines = $raw -split "`r?`n"
                $resultLine = ''
                foreach ($l in $lines) {
                    $clean = ($l -replace '\x00','').Trim()
                    if ([string]::IsNullOrWhiteSpace($clean))  { continue }
                    if ($clean -match 'Verification\s+\d+%')   { continue }
                    if ($clean -match '^\d+%')                  { continue }
                    Write-Log "[SFC] $clean" 'INFO'
                    if ($clean -match 'did not find|integrity violations|successfully repaired|found corrupt') {
                        $resultLine = $clean
                    }
                }
                # Net sonuç özeti
                if ($resultLine -match 'did not find|no integrity violations') {
                    Write-Log "SFC Sonucu: Bozuk sistem dosyasi bulunamadi." 'OK'
                } elseif ($resultLine -match 'successfully repaired') {
                    Write-Log "SFC Sonucu: Bozuk dosyalar tespit edildi ve onarildi." 'OK'
                } elseif ($resultLine -match 'found corrupt|unable to fix') {
                    Write-Log "SFC Sonucu: Bozuk dosya bulundu ancak onarılamadı! DISM RestoreHealth çalıştırın." 'WARN'
                }
            } catch {
                # Fallback
                sfc /scannow 2>&1 | ForEach-Object {
                    $clean = ($_ -replace '\x00','').Trim()
                    if (-not [string]::IsNullOrWhiteSpace($clean)) { Write-Log "[SFC] $clean" 'INFO' }
                }
            } finally {
                Remove-Item $tmp -Force -ErrorAction SilentlyContinue
            }
        }

        if ($opts.WinSxS) {
            Write-Log "WinSxS Cleanup baslatiliyor (DISM)..." 'RUN'
            Advance-Step 'WinSxS Cleanup (DISM)...'
            Invoke-DISM '/Online', '/Cleanup-Image', '/StartComponentCleanup', '/ResetBase'
            Write-Log "WinSxS Cleanup tamamlandi." 'OK'
        }

        if ($opts.SuperFetch) {
            Advance-Step 'SysMain/SuperFetch kapatiliyor...'
            $svcSM = Get-Service 'SysMain' -EA SilentlyContinue
            if ($svcSM -and $svcSM.StartType -ne 'Disabled') {
                Set-Service 'SysMain' -StartupType Disabled -ErrorAction SilentlyContinue
                Stop-Service 'SysMain' -Force -ErrorAction SilentlyContinue
                Write-Log "SysMain (SuperFetch) devre disi birakildi. Prefetch verileri temizlendi." 'OK'
                # Prefetch dosyalarını da temizle (SysMain kapalıyken anlamsız kalırlar)
                Remove-Item "$env:SystemRoot\Prefetch\*" -Force -Recurse -EA SilentlyContinue
                Write-Log "Prefetch klasoru temizlendi (SysMain kapali)" 'OK'
            } else {
                Write-Log "SysMain zaten kapali." 'INFO'
            }
        }

        if ($opts.Hibernation) {
            Advance-Step 'Hibernation kapatiliyor...'
            powercfg /h off 2>&1 | Out-Null
            Write-Log "Hibernation kapatildi, hiberfil.sys silindi." 'OK'
        }

        if ($opts.PageFile) {
            Advance-Step 'PageFile ayarlaniyor...'
            $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
            Set-ItemProperty -Path $regPath -Name 'ClearPageFileAtShutdown' -Value 1 -ErrorAction SilentlyContinue
            Write-Log "PageFile: kapanista temizle aktif." 'OK'
        }

        if ($opts.SFC) {
            Write-Log "SFC /scannow baslatiliyor..." 'RUN'
            Advance-Step 'SFC /scannow tarama yapiyor...'
            Invoke-SFC
            Write-Log "SFC taramasi tamamlandi." 'OK'
        }

        if ($opts.DISM) {
            Write-Log "DISM RestoreHealth baslatiliyor..." 'RUN'
            Advance-Step 'DISM RestoreHealth (internet gerektirir)...'
            Invoke-DISM '/Online', '/Cleanup-Image', '/RestoreHealth'
            Write-Log "DISM RestoreHealth tamamlandi." 'OK'
        }

        if ($opts.USBHistory) {
            Advance-Step 'USB Gecmisi temizleniyor...'
            Write-Log "--- USB Gecmisi Temizligi ---" 'INFO'
            $usbStorPath = 'HKLM:\SYSTEM\CurrentControlSet\Enum\USBSTOR'
            if (Test-Path $usbStorPath) {
                try {
                    $cnt = (Get-ChildItem $usbStorPath -Recurse -EA SilentlyContinue | Measure-Object).Count
                    Remove-Item $usbStorPath -Recurse -Force -EA SilentlyContinue
                    Write-Log "  USBSTOR: $cnt kayit silindi" 'OK'
                } catch { Write-Log "  USBSTOR hatasi: $_" 'WARN' }
            } else { Write-Log "  USBSTOR: Zaten bos" 'INFO' }
            $mountedPath = 'HKLM:\SYSTEM\MountedDevices'
            if (Test-Path $mountedPath) {
                $vals = (Get-ItemProperty $mountedPath -EA SilentlyContinue).PSObject.Properties |
                        Where-Object { $_.Name -match '\\DosDevices\\[D-Z]:' -and $_.Name -notmatch '\\C:' }
                $cnt2 = 0
                foreach ($v in $vals) { try { Remove-ItemProperty $mountedPath $v.Name -Force -EA SilentlyContinue; $cnt2++ } catch {} }
                if ($cnt2 -gt 0) { Write-Log "  MountedDevices: $cnt2 kayit silindi" 'OK' }
            }
            $setupLog = Join-Path $env:SystemRoot 'inf\setupapi.dev.log'
            if (Test-Path $setupLog) {
                try { Remove-Item $setupLog -Force -EA SilentlyContinue; Write-Log "  setupapi.dev.log silindi" 'OK' }
                catch { Write-Log "  setupapi.dev.log silinemedi" 'WARN' }
            }
            foreach ($ch in @('System','Microsoft-Windows-Kernel-PnP/Configuration')) {
                try { wevtutil cl $ch 2>&1 | Out-Null } catch {}
            }
            Write-Log "USB Gecmisi tamamlandi. Yeniden baslatma onerilir." 'OK'
        }

        if ($opts.DiskCleanup) {
            Write-Log "Disk Cleanup baslatiliyor..." 'RUN'
            Advance-Step 'Disk Cleanup (cleanmgr)...'
            $sageset = 65535
            $regClean = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
            @('Active Setup Temp Folders','Downloaded Program Files','Internet Cache Files',
              'Old ChkDsk Files','Recycle Bin','Setup Log Files','Temporary Files',
              'Temporary Setup Files','Thumbnail Cache','Update Cleanup') | ForEach-Object {
                $key = "$regClean\$_"
                if (Test-Path $key) { Set-ItemProperty -Path $key -Name "StateFlags$sageset" -Value 2 -ErrorAction SilentlyContinue }
            }
            try {
                Start-Process cleanmgr.exe -ArgumentList "/sagerun:$sageset" -ErrorAction SilentlyContinue
                # cleanmgr child process spawn ediyor, tum instance'larin bitmesini bekle
                $timeout = 180; $elapsed = 0
                do {
                    Start-Sleep -Seconds 2; $elapsed += 2
                    $running = Get-Process -Name cleanmgr -EA SilentlyContinue
                } while ($running -and $elapsed -lt $timeout)
                if ($elapsed -ge $timeout) {
                    Get-Process -Name cleanmgr -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
                    Write-Log "Disk Cleanup: zaman asimi — devam ediliyor." 'WARN'
                } else {
                    Write-Log "Disk Cleanup tamamlandi." 'OK'
                }
            } catch {
                Write-Log "Disk Cleanup hatasi: $_" 'WARN'
            }
        }

        # ── Disk alanı özeti
        $advDiskAfter = 0
        try {
            $d2 = Get-PSDrive $advDriveLetter -EA SilentlyContinue
            if ($d2) { $advDiskAfter = [math]::Round($d2.Free / 1GB, 2) }
        } catch {}
        $savedGB = [math]::Round($advDiskAfter - $advDiskBefore, 2)

        # ── Restart uyarısı — hangi işlemler restart gerektiriyor?
        $restartNeeded = @()
        if ($opts.USBHistory)  { $restartNeeded += 'USB Gecmisi' }
        if ($opts.WinSxS)     { $restartNeeded += 'WinSxS' }
        if ($opts.SuperFetch) { $restartNeeded += 'SysMain' }
        if ($opts.Hibernation){ $restartNeeded += 'Hibernation' }
        if ($opts.PageFile)   { $restartNeeded += 'PageFile' }
        if ($opts.SFC)        { $restartNeeded += 'SFC' }

        Write-Log "===============================" 'INFO'
        if ($savedGB -gt 0) {
            Write-Log "ADVANCED CLEAN TAMAMLANDI. Kazanilan disk: +${savedGB} GB" 'OK'
        } else {
            Write-Log "ADVANCED CLEAN TAMAMLANDI." 'OK'
        }
        if ($restartNeeded.Count -gt 0) {
            Write-Log "Yeniden baslama onerilir: $($restartNeeded -join ', ')" 'WARN'
        }
        Write-Log "===============================" 'INFO'

        # ── Progress %100 + durum metni + 3sn sonra kapat
        $summaryText = if ($savedGB -gt 0) { "Tamamlandi! +${savedGB} GB kazanildi" } else { "Tamamlandi!" }
        $restartText = if ($restartNeeded.Count -gt 0) { "  ⚠ Yeniden baslatma onerilir" } else { "" }
        $Window.Dispatcher.Invoke([action]{
            if ($AdvCleanProgressTrack.ActualWidth -gt 0) {
                $anim = [System.Windows.Media.Animation.DoubleAnimation]::new()
                $anim.To       = $AdvCleanProgressTrack.ActualWidth
                $anim.Duration = [System.Windows.Duration][TimeSpan]::FromMilliseconds(300)
                $AdvCleanProgressFill.BeginAnimation([System.Windows.FrameworkElement]::WidthProperty, $anim)
            }
            $TxtAdvCleanStatus.Text = $summaryText
            $TxtAdvCleanStatus.Foreground = New-Brush '#4CAF50'
            $TxtAdvCleanStep.Text   = if ($restartText) { $restartText } else { "$totalSteps / $totalSteps" }
            $TxtAdvCleanStep.Foreground = New-Brush '#FF9800'
        })

                # Bar kapanmasi watchTimer tarafindan gerceklestirilir
        $Window.Dispatcher.Invoke([action]{ $AdvCleanProgressContainer.Tag = 'done' })
    }
})

# ─── BACKEND: PERFORMANCE ─────────────────────────────────────────────────────
$BtnApplyPerf.Add_Click({
    $opts = Get-PageOpts @{
        HPET='ChkHPET'; TimerRes='ChkTimerRes'; CpuPrio='ChkCpuPriority'
        SysMain='ChkSysMain'; WSearch='ChkWSearch'; WUpdate='ChkWUpdate'
        GameMode='ChkGameMode'; HwAccel='ChkHwAccel'
        EmptyRAM='ChkEmptyRAM'; ModifiedRAM='ChkModifiedRAM'
    }
    $opts.CpuIsAMD  = $global:HW.CpuIsAMD
    $opts.CpuIsIntel= $global:HW.CpuIsIntel
    $opts.GpuIsNV   = $global:HW.GpuIsNV
    $opts.GpuIsAMD  = $global:HW.GpuIsAMD

    # Seçili plan butonunu tespit et — Uygula da power plan'ı uygulasın
    $selectedPlanBtn = $global:_PlanBtnGroup | Where-Object {
        $_.Style -eq $Window.Resources['BtnActive']
    } | Select-Object -First 1

    $planAction = $null
    if ($selectedPlanBtn -ne $null) {
        $planAction = switch ($selectedPlanBtn.Name) {
            'BtnPlanBitsum'   { 'Bitsum'   }
            'BtnPlanHybred'   { 'HybredHighPerf'  }
            'BtnPlanHybred2'  { 'HybredBalanced'  }
            'BtnPlanUlti'     { 'Ultimate' }
            'BtnPlanBalanced' { 'Balanced' }
            'BtnPlanDefault'  { 'HighPerf' }
            default           { $null }
        }
    }

    Invoke-Async -TaskName 'Performance' -ProgressKey 'Perf' -Vars @{
        opts        = $opts
        HW          = $global:HW
        planAction  = $planAction
        RootPath    = $global:RootPath
    } -Block {
        # ── RAM TEMIZLEME (ISLC + Native API Fallback) ─────────────────────
        if ($opts.EmptyRAM -or $opts.ModifiedRAM) {
            $islcExe  = 'Intelligent standby list cleaner ISLC.exe'
            $islcPath = Join-Path $RootPath "_Files\ISLC\$islcExe"

            if (Test-Path $islcPath) {
                # ── ISLC MEVCUT — onu kullan ──
                $ramGB  = if ($HW -and $HW.RamGB -gt 0) { [int]$HW.RamGB } else { 16 }
                $listMB = 1024
                $freeMB = [int]($ramGB * 1024 / 2)
                Write-Log "ISLC: RAM=${ramGB}GB | Polling=10000ms | ListSize=${listMB}MB | FreeMem=${freeMB}MB" 'INFO'

                # Mevcut ISLC kapat
                Get-Process -Name 'Intelligent standby list cleaner ISLC' -EA SilentlyContinue |
                    Stop-Process -Force -EA SilentlyContinue
                Start-Sleep -Milliseconds 500

                # Purge — standby list anlık temizle
                try {
                    $p = Start-Process $islcPath '-purge' -PassThru -WindowStyle Hidden -EA Stop
                    if (-not $p.WaitForExit(10000)) { $p | Stop-Process -Force -EA SilentlyContinue }
                    Write-Log "ISLC: Standby List temizlendi." 'OK'
                } catch { Write-Log "ISLC -purge hatasi: $_" 'WARN' }

                # Purge artigi varsa kapat
                Get-Process -Name 'Intelligent standby list cleaner ISLC' -EA SilentlyContinue |
                    Stop-Process -Force -EA SilentlyContinue
                Start-Sleep -Milliseconds 400

                # ISLC config dosyasini yaz — LaunchOnLogon=True ile
                $islcDir    = Split-Path $islcPath
                $islcConfig = Join-Path $islcDir 'ISLC.ini'
                try {
                    $iniContent = @(
                        '[Settings]',
                        'TimerRes=False',
                        "LaunchOnLogon=True",
                        "ListSize=$listMB",
                        "FreeMemory=$freeMB",
                        "PollingRate=10000",
                        'StartLLConfig=False'
                    ) -join "`r`n"
                    [System.IO.File]::WriteAllText($islcConfig, $iniContent, [System.Text.Encoding]::UTF8)
                    Write-Log "ISLC: Config yazildi (LaunchOnLogon=True, ListSize=${listMB}MB, FreeMem=${freeMB}MB)" 'OK'
                } catch { Write-Log "ISLC config yazma hatasi: $_" 'WARN' }

                # ISLC'yi minimized olarak baslat
                $monArgs = "-minimized -polling 10000 -listsize $listMB -freememory $freeMB"
                try {
                    Start-Process $islcPath $monArgs -WindowStyle Hidden -EA SilentlyContinue
                    Write-Log "ISLC: Monitoring baslatildi. Task Scheduler kaydi ISLC tarafindan yapilir." 'OK'
                } catch { Write-Log "ISLC baslatma hatasi: $_" 'WARN' }
            } else {
                # ── ISLC YOK — Native Windows API ile Standby List temizle ──
                Write-Log "ISLC bulunamadi — Native API ile RAM temizleniyor..." 'INFO'
                try {
                    # NtSetSystemInformation P/Invoke — Standby List purge
                    $nativeRAM = @'
using System;
using System.Runtime.InteropServices;
public class MemPurge {
    [DllImport("ntdll.dll")] public static extern int NtSetSystemInformation(int InfoClass, ref int Info, int Length);
    // SystemMemoryListInformation = 80, MemoryPurgeStandbyList = 4
    public static bool PurgeStandby() {
        int cmd = 4;
        int r = NtSetSystemInformation(80, ref cmd, sizeof(int));
        return r == 0;
    }
}
'@
                    # Tipi tekrar eklemeye calisma — zaten yukluyse atla
                    if (-not ([System.Management.Automation.PSTypeName]'MemPurge').Type) {
                        Add-Type -TypeDefinition $nativeRAM -Language CSharp -ErrorAction Stop
                    }

                    # SeProfileSingleProcessPrivilege gerekli — Admin olarak calistigimiz icin mevcut
                    $purgeOk = [MemPurge]::PurgeStandby()
                    if ($purgeOk) {
                        Write-Log "Native API: Standby List basariyla temizlendi (ISLC olmadan)." 'OK'
                    } else {
                        Write-Log "Native API: Standby List temizlenemedi (yetki sorunu olabilir)." 'WARN'
                    }
                } catch {
                    Write-Log "Native RAM API hatasi: $_ — ISLC'yi _Files\ISLC\ klasorune ekleyin." 'WARN'
                }
            }
        }

        # HPET — Redundancy Check
        if ($opts.HPET) {
            $bcdOut = bcdedit /enum {current} 2>&1
            $alreadyOff = ($bcdOut -match 'useplatformclock\s+No') -or ($bcdOut -notmatch 'useplatformclock')
            if ($alreadyOff -and ($bcdOut -match 'disabledynamictick\s+Yes')) {
                Write-Log "Zaten Optimize Edilmis: HPET (bcdedit)" 'INFO'
            } else {
                bcdedit /set useplatformclock false 2>&1 | Out-Null
                bcdedit /set disabledynamictick yes 2>&1 | Out-Null
                bcdedit /deletevalue useplatformtick 2>&1 | Out-Null
                Write-Log "HPET devre disi birakildi (bcdedit)" 'OK'
            }
        }

        # Timer Resolution 0.5ms — HAGS/global timer resolution registry
        if ($opts.TimerRes) {
            # Windows 11 2004+ destekli: GlobalTimerResolutionRequests registry ayari
            # + bcdedit ile platform timer'i kapat (HPET ile uyumlu)
            $trPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel'
            $cur = (Get-ItemProperty $trPath -ErrorAction SilentlyContinue).GlobalTimerResolutionRequests
            if ($cur -eq 1) {
                Write-Log "Zaten Optimize Edilmis: Timer Resolution (GlobalTimerResolutionRequests=1)" 'INFO'
            } else {
                try {
                    if (-not (Test-Path $trPath)) { New-Item -Path $trPath -Force | Out-Null }
                    Set-ItemProperty -Path $trPath -Name 'GlobalTimerResolutionRequests' -Value 1 -Type DWord -ErrorAction Stop
                    Write-Log "Timer Resolution: GlobalTimerResolutionRequests=1 uygulandi" 'OK'
                } catch {
                    Write-Log "Timer Resolution registry hatasi: $_" 'WARN'
                }
            }
            # Ek: bcdedit TSC sync policy (daha hassas zamanlama)
            bcdedit /set tscsyncpolicy enhanced 2>&1 | Out-Null
            Write-Log "bcdedit tscsyncpolicy=enhanced uygulandi" 'OK'
        }

        # CPU Priority — Hardware-Aware (AMD vs Intel fark goz onunde bulundurulur)
        if ($opts.CpuPrio) {
            $mmPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
            # Redundancy Check
            $curResp = (Get-ItemProperty $mmPath -ErrorAction SilentlyContinue).SystemResponsiveness
            if ($curResp -eq 0) {
                Write-Log "Zaten Optimize Edilmis: SystemResponsiveness=0" 'INFO'
            } else {
                Set-ItemProperty -Path $mmPath -Name 'SystemResponsiveness' -Value 0 -ErrorAction SilentlyContinue
                Write-Log "SystemResponsiveness=0 uygulandi" 'OK'
            }
            Set-ItemProperty -Path $mmPath -Name 'NetworkThrottlingIndex' -Value 0xFFFFFFFF -ErrorAction SilentlyContinue
            $gamePath = "$mmPath\Tasks\Games"
            if (-not (Test-Path $gamePath)) { New-Item -Path $gamePath -Force | Out-Null }
            @{
                'Affinity'             = 0
                'Background Only'      = 'False'
                'Clock Rate'           = 10000
                'GPU Priority'         = 8
                'Priority'             = 6
                'Scheduling Category'  = 'High'
                'SFIO Priority'        = 'High'
            }.GetEnumerator() | ForEach-Object {
                Set-ItemProperty -Path $gamePath -Name $_.Key -Value $_.Value -ErrorAction SilentlyContinue
            }
            Write-Log "CPU/GPU oyun oncelikleri yukseltildi" 'OK'

            # AMD-spesifik ek ayar: CPPC (Collaborative Processor Performance Control)
            if ($opts.CpuIsAMD) {
                Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name 'CppcEnable' -Value 1 -Type DWord -ErrorAction SilentlyContinue
                Write-Log "AMD CPPC (Preferred Core Boosting) aktif" 'OK'
            }
            # Intel-spesifik: SpeedStep hint
            if ($opts.CpuIsIntel) {
                Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name 'EnergyPerfPreference' -Value 0 -Type DWord -ErrorAction SilentlyContinue
                Write-Log "Intel SpeedStep perf modu hint uygulandi" 'OK'
            }
        }

        if ($opts.SysMain) {
            $svc = Get-Service 'SysMain' -ErrorAction SilentlyContinue
            if ($svc -and $svc.StartType -eq 'Disabled') {
                Write-Log "Zaten Optimize Edilmis: SysMain zaten kapali" 'INFO'
            } else {
                Set-Service 'SysMain' -StartupType Disabled -ErrorAction SilentlyContinue
                Stop-Service 'SysMain' -Force -ErrorAction SilentlyContinue
                Write-Log "SysMain kapatildi" 'OK'
            }
        }
        if ($opts.WSearch) {
            $svc = Get-Service 'WSearch' -ErrorAction SilentlyContinue
            if ($svc -and $svc.StartType -eq 'Disabled') {
                Write-Log "Zaten Optimize Edilmis: WSearch zaten kapali" 'INFO'
            } else {
                Set-Service 'WSearch' -StartupType Disabled -ErrorAction SilentlyContinue
                Stop-Service 'WSearch' -Force -ErrorAction SilentlyContinue
                Write-Log "Windows Search kapatildi" 'OK'
            }
        }
        if ($opts.WUpdate) {
            # Windows Update'i geciktir: AUOptions=4 (zamanlanmis), NoAutoUpdate=0, AU politikasi
            $auPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
            $wuPath = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
            try {
                if (-not (Test-Path $auPath)) { New-Item -Path $auPath -Force | Out-Null }
                $cur = (Get-ItemProperty $auPath -EA SilentlyContinue).AUOptions
                if ($cur -eq 4 -and (Get-ItemProperty $auPath -EA SilentlyContinue).NoAutoUpdate -eq 0) {
                    Write-Log "Zaten Optimize Edilmis: Windows Update Gecikmeli (AUOptions=4)" 'INFO'
                } else {
                    Set-ItemProperty -Path $auPath -Name 'AUOptions'     -Value 4    -Type DWord -EA SilentlyContinue
                    Set-ItemProperty -Path $auPath -Name 'NoAutoUpdate'  -Value 0    -Type DWord -EA SilentlyContinue
                    Set-ItemProperty -Path $auPath -Name 'ScheduledInstallDay'  -Value 0 -Type DWord -EA SilentlyContinue
                    Set-ItemProperty -Path $auPath -Name 'ScheduledInstallTime' -Value 3 -Type DWord -EA SilentlyContinue
                    if (-not (Test-Path $wuPath)) { New-Item -Path $wuPath -Force | Out-Null }
                    Set-ItemProperty -Path $wuPath -Name 'DeferFeatureUpdates'       -Value 1    -Type DWord -EA SilentlyContinue
                    Set-ItemProperty -Path $wuPath -Name 'DeferFeatureUpdatesPeriodInDays' -Value 365 -Type DWord -EA SilentlyContinue
                    Set-ItemProperty -Path $wuPath -Name 'DeferQualityUpdates'       -Value 1    -Type DWord -EA SilentlyContinue
                    Set-ItemProperty -Path $wuPath -Name 'DeferQualityUpdatesPeriodInDays' -Value 7 -Type DWord -EA SilentlyContinue
                    Write-Log "Windows Update: gecikme politikasi uygulandi (Feature=365gun, Quality=7gun)" 'OK'
                }
            } catch { Write-Log "WUpdate hatasi: $_" 'WARN' }
        }
        if ($opts.GameMode) {
            $gmPath = 'HKCU:\Software\Microsoft\GameBar'
            if (-not (Test-Path $gmPath)) { New-Item -Path $gmPath -Force | Out-Null }
            $cur = (Get-ItemProperty $gmPath -ErrorAction SilentlyContinue).AutoGameModeEnabled
            if ($cur -eq 1) {
                Write-Log "Zaten Optimize Edilmis: Game Mode aktif" 'INFO'
            } else {
                Set-ItemProperty -Path $gmPath -Name 'AllowAutoGameMode'   -Value 1 -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $gmPath -Name 'AutoGameModeEnabled' -Value 1 -ErrorAction SilentlyContinue
                Write-Log "Game Mode etkinlestirildi" 'OK'
            }
        }
        if ($opts.HwAccel) {
            # Redundancy check
            $hwPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
            $cur = (Get-ItemProperty $hwPath -ErrorAction SilentlyContinue).HwSchMode
            if ($cur -eq 2) {
                Write-Log "Zaten Optimize Edilmis: HW GPU Scheduling (HwSchMode=2)" 'INFO'
            } else {
                # GPU'ya gore kontrol (yalnizca destekleyen GPU'larda uygula)
                if ($opts.GpuIsNV -or $opts.GpuIsAMD) {
                    Set-ItemProperty -Path $hwPath -Name 'HwSchMode' -Value 2 -Type DWord -ErrorAction SilentlyContinue
                    Write-Log "Hardware-Accelerated GPU Scheduling etkinlestirildi" 'OK'
                } else {
                    Write-Log "HW GPU Scheduling: Desteklenen GPU tespit edilemedi, atlanıyor." 'WARN'
                }
            }
        }

        # ── Seçili Power Plan'ı uygula (Uygula butonuna basınca da çalışır) ─────
        if ($planAction) {
            Write-Log "Guc plani uygulanıyor: $planAction" 'RUN'
            switch ($planAction) {
                'Bitsum' {
                    $planPath = Join-Path $RootPath '_Files\Bitsum-Highest-Performance.pow'
                    if (Test-Path $planPath) {
                        $out = powercfg /import $planPath 2>&1
                        $g = [regex]::Match(($out -join ' '), '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})')
                        if ($g.Success) { powercfg /setactive $g.Value 2>&1 | Out-Null; Write-Log "Bitsum Highest Performance aktif: $($g.Value)" 'OK' }
                        else { Write-Log "Bitsum GUID alinamadi: $($out -join ' ')" 'WARN' }
                    } else { Write-Log "Bitsum .pow dosyasi bulunamadi: $planPath" 'WARN' }
                }
                'HybredHighPerf' {
                    $dirs = @((Join-Path $RootPath '_Files\HybredPowerPlans'), (Join-Path $RootPath '_Files'))
                    $pf = $dirs | ForEach-Object { Join-Path $_ 'HybredLowLatencyHighPerf.pow' } | Where-Object { Test-Path $_ } | Select-Object -First 1
                    if ($pf) {
                        $out = powercfg /import $pf 2>&1
                        $g = [regex]::Match(($out -join ' '), '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})')
                        if ($g.Success) { powercfg /setactive $g.Value 2>&1 | Out-Null; Write-Log "Hybred HighPerf aktif: $($g.Value)" 'OK' }
                        else { Write-Log "Hybred HighPerf GUID alinamadi" 'WARN' }
                    } else { Write-Log "HybredLowLatencyHighPerf.pow bulunamadi" 'WARN' }
                }
                'HybredBalanced' {
                    $dirs = @((Join-Path $RootPath '_Files\HybredPowerPlans'), (Join-Path $RootPath '_Files'))
                    $pf = $dirs | ForEach-Object { Join-Path $_ 'HybredLowLatencyBalanced.pow' } | Where-Object { Test-Path $_ } | Select-Object -First 1
                    if ($pf) {
                        $out = powercfg /import $pf 2>&1
                        $g = [regex]::Match(($out -join ' '), '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})')
                        if ($g.Success) { powercfg /setactive $g.Value 2>&1 | Out-Null; Write-Log "Hybred Balanced aktif: $($g.Value)" 'OK' }
                        else { Write-Log "Hybred Balanced GUID alinamadi" 'WARN' }
                    } else { Write-Log "HybredLowLatencyBalanced.pow bulunamadi" 'WARN' }
                }
                'Ultimate' {
                    powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1 | Out-Null
                    $g = powercfg /list 2>&1 | Where-Object { $_ -match '[0-9a-f]{8}-[0-9a-f]{4}' } |
                         Select-Object -Last 1 | ForEach-Object { [regex]::Match($_, '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})').Value }
                    if ($g) { powercfg /setactive $g 2>&1 | Out-Null; Write-Log "Ultimate Performance aktif: $g" 'OK' }
                }
                'Balanced' {
                    powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e 2>&1 | Out-Null
                    Write-Log "Balanced guc plani aktif" 'OK'
                }
                'HighPerf' {
                    powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>&1 | Out-Null
                    Write-Log "High Performance guc plani aktif" 'OK'
                }
            }
        }
    }
})

# Global plan butonu grubu
$global:_PlanBtnGroup = @($BtnPlanBitsum, $BtnPlanHybred, $BtnPlanHybred2, $BtnPlanUlti, $BtnPlanBalanced, $BtnPlanDefault)

# FIX 3: Win32 Priority buton grubu
$global:_W32BtnGroup = @($BtnW32BestFPS, $BtnW32Balanced, $BtnW32Default)

# Win32 Priority Buttons (FIX 3 — Active State)
$BtnW32BestFPS.Add_Click({
    Set-ActiveButton -ActiveBtn $BtnW32BestFPS -Group $global:_W32BtnGroup
    Invoke-Async -TaskName 'Win32PrioritySeparation BestFPS' -Block {
        Set-ItemProperty -Path 'HKLM:\SYSTEM\ControlSet001\Control\PriorityControl' -Name 'Win32PrioritySeparation' -Value 0x14 -ErrorAction SilentlyContinue
        Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' -Name 'Win32PrioritySeparation' -Value 0x14 -ErrorAction SilentlyContinue
        Write-Log "Win32PrioritySeparation = 0x14 (BestFPS) uygulandi" 'OK'
    }
})
$BtnW32Balanced.Add_Click({
    Set-ActiveButton -ActiveBtn $BtnW32Balanced -Group $global:_W32BtnGroup
    Invoke-Async -TaskName 'Win32PrioritySeparation Balanced' -Block {
        Set-ItemProperty -Path 'HKLM:\SYSTEM\ControlSet001\Control\PriorityControl' -Name 'Win32PrioritySeparation' -Value 0x18 -ErrorAction SilentlyContinue
        Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' -Name 'Win32PrioritySeparation' -Value 0x18 -ErrorAction SilentlyContinue
        Write-Log "Win32PrioritySeparation = 0x18 (Balanced) uygulandi" 'OK'
    }
})
$BtnW32Default.Add_Click({
    Set-ActiveButton -ActiveBtn $BtnW32Default -Group $global:_W32BtnGroup
    Invoke-Async -TaskName 'Win32PrioritySeparation Default' -Block {
        Set-ItemProperty -Path 'HKLM:\SYSTEM\ControlSet001\Control\PriorityControl' -Name 'Win32PrioritySeparation' -Value 0x26 -ErrorAction SilentlyContinue
        Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' -Name 'Win32PrioritySeparation' -Value 0x26 -ErrorAction SilentlyContinue
        Write-Log "Win32PrioritySeparation = 0x26 (Default) uygulandi" 'OK'
    }
})

# FIX 6+7 — Hybred Power Plans (iki butona ayrildi, GUID regex duzeltildi)
$BtnPlanHybred.Add_Click({
    Set-ActiveButton -ActiveBtn $BtnPlanHybred -Group $global:_PlanBtnGroup
    Invoke-Async -TaskName 'Hybred HighPerf Plan' -Vars @{ RootPath=$global:RootPath } -Block {
        $planDirs = @((Join-Path $RootPath '_Files\HybredPowerPlans'), (Join-Path $RootPath '_Files'))
        $pf = $planDirs | ForEach-Object { Join-Path $_ 'HybredLowLatencyHighPerf.pow' } | Where-Object { Test-Path $_ } | Select-Object -First 1
        if ($pf) {
            $out = powercfg /import $pf 2>&1
            $g = [regex]::Match(($out -join ' '), '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})')
            if ($g.Success) { powercfg /setactive $g.Value 2>&1 | Out-Null; Write-Log "Hybred HighPerf Plan aktif: $($g.Value)" 'OK' }
            else { Write-Log "Hybred HighPerf GUID alinamadi. Import: $($out -join ' ')" 'WARN' }
        } else { Write-Log "HybredLowLatencyHighPerf.pow bulunamadi. Aranan: $($planDirs -join ', ')" 'WARN' }
    }
})

$BtnPlanHybred2.Add_Click({
    Set-ActiveButton -ActiveBtn $BtnPlanHybred2 -Group $global:_PlanBtnGroup
    Invoke-Async -TaskName 'Hybred Balanced Plan' -Vars @{ RootPath=$global:RootPath } -Block {
        $planDirs = @((Join-Path $RootPath '_Files\HybredPowerPlans'), (Join-Path $RootPath '_Files'))
        $pf = $planDirs | ForEach-Object { Join-Path $_ 'HybredLowLatencyBalanced.pow' } | Where-Object { Test-Path $_ } | Select-Object -First 1
        if ($pf) {
            $out = powercfg /import $pf 2>&1
            $g = [regex]::Match(($out -join ' '), '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})')
            if ($g.Success) { powercfg /setactive $g.Value 2>&1 | Out-Null; Write-Log "Hybred Balanced Plan aktif: $($g.Value)" 'OK' }
            else { Write-Log "Hybred Balanced GUID alinamadi. Import: $($out -join ' ')" 'WARN' }
        } else { Write-Log "HybredLowLatencyBalanced.pow bulunamadi. Aranan: $($planDirs -join ', ')" 'WARN' }
    }
})

# FIX 3+6 — Bitsum (GUID parse duzeltildi)
$BtnPlanBitsum.Add_Click({
    Set-ActiveButton -ActiveBtn $BtnPlanBitsum -Group $global:_PlanBtnGroup
    Invoke-Async -TaskName 'Guc Plani - Bitsum Highest' -Vars @{ RootPath=$global:RootPath } -Block {
        $planPath = Join-Path $RootPath '_Files\Bitsum-Highest-Performance.pow'
        if (Test-Path $planPath) {
            $importOut = powercfg /import $planPath 2>&1
            $guidMatch = [regex]::Match(($importOut -join ' '), '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})')
            if ($guidMatch.Success) {
                powercfg /setactive $guidMatch.Value 2>&1 | Out-Null
                Write-Log "Bitsum Highest Performance plani aktif edildi (GUID: $($guidMatch.Value))" 'OK'
            } else {
                Write-Log "Bitsum GUID alinamadi. Import: $($importOut -join ' ')" 'WARN'
            }
        } else {
            # Bitsum bulunamadı: Ultimate Performance'ı aktifleştir
            powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1 | Out-Null
            $ultiGuid = powercfg /list 2>&1 | ForEach-Object {
                if ($_ -match '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})') { $Matches[1] }
            } | Where-Object { $_ -ne '' } | Select-Object -Last 1
            if ($ultiGuid) {
                powercfg /setactive $ultiGuid 2>&1 | Out-Null
                Write-Log "Bitsum .pow bulunamadi. Ultimate Performance aktif: $ultiGuid" 'WARN'
            } else {
                powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>&1 | Out-Null
                Write-Log "Bitsum .pow bulunamadi. High Performance guc plani aktif edildi." 'WARN'
            }
        }
    }
})
$BtnPlanUlti.Add_Click({
    Set-ActiveButton -ActiveBtn $BtnPlanUlti -Group $global:_PlanBtnGroup
    Invoke-Async -TaskName 'Guc Plani - Ultimate Performance' -Block {
        powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1 | Out-Null
        $importOut = powercfg /list 2>&1
        $guidMatch = ($importOut | Where-Object { $_ -match 'e9a42b02' } |
                     Select-Object -Last 1 | ForEach-Object {
                         [regex]::Match($_, '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})')
                     })
        if ($guidMatch -and $guidMatch.Success) {
            powercfg /setactive $guidMatch.Value 2>&1 | Out-Null
            Write-Log "Ultimate Performance aktif: $($guidMatch.Value)" 'OK'
        } else { Write-Log "Ultimate Performance plani bulunamadi" 'WARN' }
    }
})
$BtnPlanBalanced.Add_Click({
    Set-ActiveButton -ActiveBtn $BtnPlanBalanced -Group $global:_PlanBtnGroup
    Invoke-Async -TaskName 'Guc Plani - Balanced' -Block {
        powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e 2>&1 | Out-Null
        Write-Log "Balanced guc plani aktif" 'OK'
    }
})
$BtnPlanDefault.Add_Click({
    Set-ActiveButton -ActiveBtn $BtnPlanDefault -Group $global:_PlanBtnGroup
    Invoke-Async -TaskName 'Guc Plani - High Performance' -Block {
        powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>&1 | Out-Null
        Write-Log "High Performance guc plani aktif" 'OK'
    }
})

# ─── BACKEND: NETWORK ─────────────────────────────────────────────────────────
$BtnScanAdapters.Add_Click({
    $adapterText = ''
    try {
        $adapters = Get-NetAdapter -Physical | Where-Object { $_.Status -eq 'Up' }
        if ($adapters) {
            $adapterText = ($adapters | ForEach-Object {
                "► $($_.Name) | $($_.InterfaceDescription) | $($_.LinkSpeed)"
            }) -join "`n"
        } else { $adapterText = 'Aktif fiziksel adaptor bulunamadi.' }
    } catch { $adapterText = "Adaptor bilgisi alinamadi: $_" }
    $TxtAdapterInfo.Text = $adapterText
    Write-Log "Adaptorler tarandi:`n$adapterText" 'OK'
})

$BtnApplyNetwork.Add_Click({
    $opts = Get-PageOpts @{
        AutoTuning='ChkAutoTuning'; ECN='ChkECN'; RSC='ChkRSC'; Congestion='ChkCongestion'
        NetThrottle='ChkNetThrottle'; Nagle='ChkNagle'; TCPNoDelay='ChkTCPNoDelay'
        TCPACKFreq='ChkTCPACKFreq'; RSS='ChkRSS'; FlowCtrl='ChkFlowCtrl'
        IntMod='ChkIntMod'; GreenEth='ChkGreenEth'; GigaLite='ChkGigaLite'
        AdaptInter='ChkAdaptInter'; DNSPrefetch='ChkDNSPrefetch'; MDNS='ChkMDNS'; LLMNR='ChkLLMNR'
    }
    Invoke-Async -TaskName 'Network Tweaks' -ProgressKey 'Net' -Vars @{ opts=$opts } -Block {
        Write-Log "--- TCP/IP Ayarlari ---" 'INFO'
        if ($opts.AutoTuning) {
            netsh int tcp set global autotuninglevel=normal 2>&1 | Out-Null
            Write-Log "TCP AutoTuning: normal (64KB kilidi kaldirildi — dinamik pencere boyutu aktif)" 'OK'
        } else { Write-Log "TCP AutoTuning: atlanıyor" 'INFO' }
        if ($opts.ECN) {
            netsh int tcp set global ecncapability=disabled 2>&1 | Out-Null
            Write-Log "ECN: disabled" 'OK'
        } else { Write-Log "ECN: atlanıyor" 'INFO' }
        if ($opts.RSC) {  # RSC — Receive Segment Coalescing
            netsh int tcp set global rsc=disabled 2>&1 | Out-Null
            Write-Log "RSC (Receive Segment Coalescing): disabled" 'OK'
        }
        if ($opts.Congestion) {
            netsh int tcp set supplemental template=internet congestionprovider=cubic 2>&1 | Out-Null
            netsh int tcp set supplemental template=internetcustom congestionprovider=cubic 2>&1 | Out-Null
            Write-Log "Congestion Provider: CUBIC (modern, paket kaybi ve gecikme yonetimi)" 'OK'
        }
        if ($opts.NetThrottle) {
            $mmPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
            Set-ItemProperty -Path $mmPath -Name 'NetworkThrottlingIndex' -Value 0xFFFFFFFF -ErrorAction SilentlyContinue
            Write-Log "NetworkThrottlingIndex = 0xFFFFFFFF (throttling kapali)" 'OK'
        }
        if ($opts.Nagle -or $opts.TCPNoDelay -or $opts.TCPACKFreq) {
            $tcpPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
            if (Test-Path $tcpPath) {
                Get-ChildItem $tcpPath | ForEach-Object {
                    $iface = $_.PSPath
                    if ($opts.Nagle)      { Set-ItemProperty -Path $iface -Name 'TcpNoDelay'      -Value 1 -ErrorAction SilentlyContinue }
                    if ($opts.TCPNoDelay) { Set-ItemProperty -Path $iface -Name 'TcpDelAckTicks'  -Value 0 -ErrorAction SilentlyContinue }
                    if ($opts.TCPACKFreq) { Set-ItemProperty -Path $iface -Name 'TcpAckFrequency' -Value 1 -ErrorAction SilentlyContinue }
                }
            }
            Write-Log "Nagle: disabled, TCPNoDelay=1, TcpAckFrequency=1" 'OK'
        }

        # NIC Adapter tweaks via advanced properties
        if ($opts.FlowCtrl -or $opts.IntMod -or $opts.RSS -or $opts.GreenEth -or $opts.GigaLite -or $opts.AdaptInter) {
            $adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' }
            foreach ($adapter in $adapters) {
                Write-Log "NIC tweaks: $($adapter.Name) ($($adapter.InterfaceDescription))" 'RUN'
                $advProps = Get-NetAdapterAdvancedProperty -Name $adapter.Name -ErrorAction SilentlyContinue

                function Set-NicProp([string]$kw, [string]$val) {
                    $prop = $advProps | Where-Object { $_.DisplayName -match $kw } | Select-Object -First 1
                    if ($prop) {
                        try {
                            Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName $prop.DisplayName -DisplayValue $val -ErrorAction SilentlyContinue
                            Write-Log "  $($prop.DisplayName) = $val" 'OK'
                        } catch { Write-Log "  $($prop.DisplayName) ayarlanamadi" 'WARN' }
                    }
                }

                if ($opts.FlowCtrl)  { Set-NicProp 'Flow Control' 'Disabled' }
                if ($opts.IntMod)    { Set-NicProp 'Interrupt Moderation' 'Adaptive' }
                if ($opts.RSS) {
                    try { Enable-NetAdapterRss -Name $adapter.Name -ErrorAction SilentlyContinue; Write-Log "  RSS etkin: $($adapter.Name)" 'OK' } catch {}
                }
                if ($opts.GreenEth) {
                    Set-NicProp 'Green Ethernet' 'Disabled'
                    Set-NicProp 'Energy-Efficient Ethernet' 'Disabled'
                    Set-NicProp 'EEE' 'Disabled'
                }
                if ($opts.GigaLite)  { Set-NicProp 'Giga Lite' 'Disabled' }
                if ($opts.AdaptInter) {
                    Set-NicProp 'Adaptive Inter-Frame Spacing' 'Disabled'
                    Set-NicProp 'Interrupt Moderation Rate' '3'
                }
            }
        }

        if ($opts.LLMNR) {
            $dnPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'
            if (-not (Test-Path $dnPath)) { New-Item -Path $dnPath -Force | Out-Null }
            Set-ItemProperty -Path $dnPath -Name 'EnableMulticast' -Value 0 -ErrorAction SilentlyContinue
            Write-Log "LLMNR: disabled (DNS hijacking riski azalir)" 'OK'
        }
        if ($opts.DNSPrefetch) {
            # DNS Cache optimizasyonu: negatif TTL ve maksimum cache boyutu
            $dnsCachePath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters'
            if (-not (Test-Path $dnsCachePath)) { New-Item -Path $dnsCachePath -Force | Out-Null }
            Set-ItemProperty -Path $dnsCachePath -Name 'EnableDnsCache'        -Value 1    -Type DWord -EA SilentlyContinue
            Set-ItemProperty -Path $dnsCachePath -Name 'MaxCacheTtl'           -Value 3600  -Type DWord -EA SilentlyContinue
            Set-ItemProperty -Path $dnsCachePath -Name 'MaxNegativeCacheTtl'   -Value 0    -Type DWord -EA SilentlyContinue
            Set-ItemProperty -Path $dnsCachePath -Name 'CacheHashTableBucketSize' -Value 1 -Type DWord -EA SilentlyContinue
            Set-ItemProperty -Path $dnsCachePath -Name 'CacheHashTableSize'    -Value 384  -Type DWord -EA SilentlyContinue
            Write-Log "DNS Cache optimizasyonu uygulandı (MaxTTL=3600s=1saat, NegTTL=0)" 'OK'
        }
        if ($opts.MDNS) {
            $mdnPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters'
            Set-ItemProperty -Path $mdnPath -Name 'EnableMDNS' -Value 0 -ErrorAction SilentlyContinue
            Write-Log "mDNS kapatildi" 'OK'
        }
    }
})

$BtnResetNetwork.Add_Click({
    Invoke-Async -TaskName 'TCP/IP Reset' -Block {
        netsh int ip reset 2>&1 | ForEach-Object { Write-Log $_ }
        netsh winsock reset 2>&1 | ForEach-Object { Write-Log $_ }
        ipconfig /flushdns 2>&1 | Out-Null
        Write-Log "TCP/IP ve Winsock sifirlandi. Yeniden baslatma gerekebilir." 'WARN'
    }
})

# ─── BACKEND: KERNEL & INPUT ──────────────────────────────────────────────────
$BtnApplyKernel.Add_Click({
    $opts = Get-PageOpts @{
        VBS='ChkVBS'; DMAProtect='ChkDMAProtect'; Spectre='ChkSpectre'; CFG='ChkCFG'
        HVCI='ChkHVCI'; LargePages='ChkLargePages'; ContMem='ChkContMem'
        MouseBuf='ChkMouseBuffer'; KbBuf='ChkKbBuffer'; RawInput='ChkRawInput'
        MouseSmooth='ChkMouseSmooth'; MouseAccel='ChkMouseAccel'; PagingFiles='ChkPagingFiles'
    }
    $opts.SecLvlCache = $false  # KALDIRILDI — plasebo, artik islenmez
    Invoke-Async -TaskName 'Kernel & Input' -ProgressKey 'Kern' -Vars @{ opts=$opts } -Block {
        Write-Log "--- Guvenlik Mitigasyonlari ---" 'INFO'
        if ($opts.VBS) {
            $dgPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'
            Set-ItemProperty -Path $dgPath -Name 'EnableVirtualizationBasedSecurity' -Value 0 -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $dgPath -Name 'RequirePlatformSecurityFeatures'   -Value 0 -ErrorAction SilentlyContinue
            Write-Log "VBS / Core Isolation: disabled. Yeniden baslatma gerekli." 'WARN'
        } else { Write-Log "VBS: atlanıyor" 'INFO' }
        if ($opts.DMAProtect) {
            Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' -Name 'EnableKernelDmaProtection' -Value 0 -ErrorAction SilentlyContinue
            Write-Log "DMA Protection: disabled" 'WARN'
        } else { Write-Log "DMA Protection: atlanıyor" 'INFO' }
        Write-Log "--- Bellek & Giris Aygitlari ---" 'INFO'
        if ($opts.Spectre) {
            $featurePath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
            Set-ItemProperty -Path $featurePath -Name 'FeatureSettingsOverride'     -Value 3 -Type DWord -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $featurePath -Name 'FeatureSettingsOverrideMask' -Value 3 -Type DWord -ErrorAction SilentlyContinue
            Write-Log "Spectre/Meltdown: disabled (Guvenlik riski!)" 'WARN'
        } else { Write-Log "Spectre/Meltdown: atlanıyor" 'INFO' }
        if ($opts.HVCI) {
            $ciPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity'
            if (-not (Test-Path $ciPath)) { New-Item -Path $ciPath -Force | Out-Null }
            Set-ItemProperty -Path $ciPath -Name 'Enabled' -Value 0 -ErrorAction SilentlyContinue
            Write-Log "HVCI: disabled" 'WARN'
        } else { Write-Log "HVCI: atlanıyor" 'INFO' }
        if ($opts.CFG) {
            # Control Flow Guard (CFG) — kernel MitigationOptions bit 2 kapat
            # Bit masking: mevcut değeri oku, CFG bitini kapat
            $kernCfgPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel'
            try {
                $curOpts = (Get-ItemProperty $kernCfgPath -EA SilentlyContinue).MitigationOptions
                if ($curOpts -eq $null) { $curOpts = [int64]0 }
                # CFG disable mask: 0x200 (bit 9) = CFG audit/disable
                $newOpts = [int64]$curOpts -bor [int64]0x200
                Set-ItemProperty -Path $kernCfgPath -Name 'MitigationOptions' -Value $newOpts -Type QWord -EA SilentlyContinue
                Write-Log "CFG MitigationOptions = 0x$('{0:X}' -f $newOpts) (CFG kapatildi)" 'WARN'
            } catch { Write-Log "CFG ayarlanamadi: $_" 'WARN' }
        }
        if ($opts.LargePages) {
            # Large Pages — SeLockMemoryPrivilege + LargePageMinimum
            $memLpPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
            Set-ItemProperty -Path $memLpPath -Name 'LargePageMinimum' -Value 0 -Type DWord -EA SilentlyContinue
            Write-Log "LargePageMinimum = 0 (Large Pages aktif)" 'OK'
            # SeLockMemoryPrivilege — kullanici hesabina ekle (Local Security Policy)
            try {
                $privPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel'
                $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
                Write-Log "LargePages: SeLockMemoryPrivilege icin '$user' politikaya eklenmelidir (secpol.msc)." 'INFO'
            } catch {}
        }
        if ($opts.ContMem) {
            $dxPath = 'HKLM:\SOFTWARE\Microsoft\DirectX'
            if (-not (Test-Path $dxPath)) { New-Item -Path $dxPath -Force | Out-Null }
            Set-ItemProperty -Path $dxPath -Name 'D3D12_ENABLE_UNSAFE_COMMAND_BUFFER_REUSE' -Value 1 -ErrorAction SilentlyContinue
            # Contiguous memory for legacy DX
            $gpuPrefsPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
            Set-ItemProperty -Path $gpuPrefsPath -Name 'DpiMapIommuContiguous' -Value 1 -ErrorAction SilentlyContinue
            Write-Log "DirectX Contiguous Memory Allocation etkin" 'OK'
        }
        # SecondLevelDataCache KALDIRILDI — XP-era plasebo. Modern Windows kernel CPU cache'i donanim seviyesinde dinamik yonetir.
        # Mouse & Keyboard Buffer (MarkC Fix logic)
        if ($opts.MouseBuf) {
            $mousePath = 'HKLM:\SYSTEM\CurrentControlSet\Services\mouclass\Parameters'
            Set-ItemProperty -Path $mousePath -Name 'MouseDataQueueSize' -Value 16 -ErrorAction SilentlyContinue
            Write-Log "Mouse: MouseDataQueueSize=16 (MarkC)" 'OK'
        }
        if ($opts.KbBuf) {
            $kbPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\kbdclass\Parameters'
            Set-ItemProperty -Path $kbPath -Name 'KeyboardDataQueueSize' -Value 16 -ErrorAction SilentlyContinue
            Write-Log "Keyboard: KeyboardDataQueueSize=16" 'OK'
        }
        if ($opts.RawInput) {
            # MouseSensitivity=10 → 1:1 pointer mapping (EPP kapaliyken ideal)
            Set-ItemProperty -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseSensitivity' -Value '10' -EA SilentlyContinue
            # HID aygitlarin uyku moduna girmesini engelle (USB input latency azalir)
            $hidPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\HidUsb\Parameters'
            if (-not (Test-Path $hidPath)) { New-Item $hidPath -Force | Out-Null }
            Set-ItemProperty -Path $hidPath -Name 'WaitWakeEnabled' -Value 0 -Type DWord -EA SilentlyContinue
            # Fare ve klavye ham girisini isleyen sureci yuksek oncelikle isle
            $csrPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\csrss.exe\PerfOptions'
            if (-not (Test-Path $csrPath)) { New-Item $csrPath -Force | Out-Null }
            Set-ItemProperty -Path $csrPath -Name 'CpuPriorityClass'        -Value 4 -Type DWord -EA SilentlyContinue
            Set-ItemProperty -Path $csrPath -Name 'IoPriority'              -Value 3 -Type DWord -EA SilentlyContinue
            Write-Log "Raw Input: 1:1 hassasiyet, HID uyku engeli, csrss yuksek oncelik" 'OK'
        }
        if ($opts.MouseSmooth) {
            $cpMouse = 'HKCU:\Control Panel\Mouse'
            Set-ItemProperty -Path $cpMouse -Name 'SmoothMouseXCurve' -Value ([byte[]](0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xC0,0xCC,0x0C,0x00,0x00,0x00,0x00,0x00,0x80,0x99,0x19,0x00,0x00,0x00,0x00,0x00,0x40,0x66,0x26,0x00,0x00,0x00,0x00,0x00,0x00,0x33,0x33,0x00,0x00,0x00,0x00,0x00)) -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $cpMouse -Name 'SmoothMouseYCurve' -Value ([byte[]](0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x38,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x70,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xA8,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xE0,0x00,0x00,0x00,0x00,0x00)) -ErrorAction SilentlyContinue
            Write-Log "Mouse Smoothing devre disi (MarkC Fix curves)" 'OK'
        }
        if ($opts.MouseAccel) {
            $cpMouse = 'HKCU:\Control Panel\Mouse'
            Set-ItemProperty -Path $cpMouse -Name 'MouseSpeed'     -Value '0' -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $cpMouse -Name 'MouseThreshold1' -Value '0' -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $cpMouse -Name 'MouseThreshold2' -Value '0' -ErrorAction SilentlyContinue
            Write-Log "Mouse Acceleration (EPP) kapatildi" 'OK'
        }
        if ($opts.PagingFiles) {
            # PageFile: sistem yönetimine bırak (otomatik boyutlandırma — en iyi performans)
            $memPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
            Set-ItemProperty -Path $memPath -Name 'PagingFiles' -Value 'c:\pagefile.sys 0 0' -EA SilentlyContinue
            # Sistem yönetimli pagefile için registry sıfırla
            Set-ItemProperty -Path $memPath -Name 'ExistingPageFiles' -Value @() -EA SilentlyContinue
            Write-Log "PageFile: Sistem yönetimine bırakıldı (otomatik boyutlandırma)." 'OK'
        }
    }
})

# ─── BACKEND: GPU & MSI ───────────────────────────────────────────────────────
$BtnDetectGPU.Add_Click({
    $gpus = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notmatch '(?i)Remote Desktop|Virtual|Basic Display' } |
            Sort-Object AdapterRAM -Descending
    if ($gpus) {
        $primary = $gpus | Select-Object -First 1
        $info = ($gpus | ForEach-Object {
            $vram   = if ($_.AdapterRAM -gt 0) { "$([math]::Round($_.AdapterRAM/1GB,1)) GB VRAM" } else { "VRAM bilinmiyor" }
            $isPrimary = ($_.Name -eq $primary.Name)
            $tag   = if ($isPrimary) { " [PRIMARY - Tweaks hedefi]" } else { " [secondary]" }
            "► $($_.Name) | $vram | Driver: $($_.DriverVersion)$tag"
        }) -join "`n"
        $TxtGPUInfo.Text = $info
        Write-Log "GPU algilandi (Primary: $($primary.Name)):`n$info" 'OK'

        # GPU markasina gore karsi markanin bolumunu gizle
        $allGpuNames = ($gpus | ForEach-Object { $_.Name }) -join ' '
        $hasNV  = $allGpuNames -match 'NVIDIA'
        $hasAMD = $allGpuNames -match 'AMD|Radeon'

        if ($GrpNvidia) {
            $GrpNvidia.Visibility = $(if ($hasNV) { 'Visible' } else { 'Collapsed' })
        }
        if ($GrpAmd) {
            $GrpAmd.Visibility = $(if ($hasAMD) { 'Visible' } else { 'Collapsed' })
        }
    } else {
        $TxtGPUInfo.Text = "GPU bilgisi alinamadi."
        Write-Log "GPU bilgisi alinamadi" 'WARN'
    }
})

$BtnApplyGPU.Add_Click({
    $opts = Get-PageOpts @{
        MSIGPU='ChkMSIGPU'; MSINVMe='ChkMSINVMe'; MSINIC='ChkMSINIC'; MSIPRIO='ChkMSIPrio'
        NvPrerender='ChkNvPrerender'; NvPower='ChkNvPower'; NvSync='ChkNvSync'
        NvShaderCache='ChkNvShaderCache'; NvTexFilter='ChkNvTexFilter'; NvFastSync='ChkNvFastSync'
        AMDAntiLag='ChkAMDAntiLag'; AMDChill='ChkAMDChill'; AMDPower='ChkAMDPower'
    }
    Invoke-Async -TaskName 'GPU & MSI' -ProgressKey 'GPU' -Vars @{ opts=$opts; HW=$global:HW } -Block {
        $script:msiCount = 0
        $gpuClassPath  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
        $nvmeClassPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e97b-e325-11ce-bfc1-08002be10318}'
        $nicClassPath  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}'
        if ($opts.MSIGPU -or $opts.MSINVMe -or $opts.MSINIC) {
            Write-Log "MSI Mode tarama basliyor..." 'RUN'
        }
        # GPU MSI — sadece ChkMSIGPU seçiliyse GPU class taraniyor
        if ($opts.MSIGPU -and (Test-Path $gpuClassPath)) {
            Get-ChildItem $gpuClassPath -ErrorAction SilentlyContinue |
            Where-Object { $_.PSChildName -match '^\d{4}$' } | ForEach-Object {
                $driverDesc = (Get-ItemProperty $_.PSPath -Name 'DriverDesc' -EA SilentlyContinue).DriverDesc
                if ($driverDesc -and $driverDesc -notmatch '(?i)Microsoft Basic|Remote Desktop|Virtual') {
                    $intPath = "$($_.PSPath)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
                    if (-not (Test-Path $intPath)) { try { New-Item $intPath -Force -EA SilentlyContinue | Out-Null } catch {} }
                    Set-ItemProperty $intPath -Name 'MSISupported' -Value 1 -Type DWord -EA SilentlyContinue
                    if ($opts.MSIPRIO) {
                        $affPath = "$($_.PSPath)\Device Parameters\Interrupt Management\Affinity Policy"
                        if (-not (Test-Path $affPath)) { try { New-Item $affPath -Force -EA SilentlyContinue | Out-Null } catch {} }
                        Set-ItemProperty $affPath -Name 'DevicePriority' -Value 3 -Type DWord -EA SilentlyContinue
                    }
                    Write-Log "  GPU MSI Mode: $driverDesc" 'OK'
                    $script:msiCount++
                }
            }
        }
        if ($opts.MSINVMe -and (Test-Path $nvmeClassPath)) {
            Get-ChildItem $nvmeClassPath -ErrorAction SilentlyContinue |
            Where-Object { $_.PSChildName -match '^\d{4}$' } | ForEach-Object {
                $driverDesc = (Get-ItemProperty $_.PSPath -Name 'DriverDesc' -EA SilentlyContinue).DriverDesc
                if ($driverDesc) {
                    $intPath = "$($_.PSPath)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
                    if (-not (Test-Path $intPath)) { try { New-Item $intPath -Force -EA SilentlyContinue | Out-Null } catch {} }
                    Set-ItemProperty $intPath -Name 'MSISupported' -Value 1 -Type DWord -EA SilentlyContinue
                    if ($opts.MSIPRIO) {
                        $affPath = "$($_.PSPath)\Device Parameters\Interrupt Management\Affinity Policy"
                        if (-not (Test-Path $affPath)) { try { New-Item $affPath -Force -EA SilentlyContinue | Out-Null } catch {} }
                        Set-ItemProperty $affPath -Name 'DevicePriority' -Value 3 -Type DWord -EA SilentlyContinue
                    }
                    Write-Log "  NVMe MSI Mode: $driverDesc" 'OK'
                    $script:msiCount++
                }
            }
        }
        # NIC MSI Mode
        if ($opts.MSINIC -and (Test-Path $nicClassPath)) {
            Get-ChildItem $nicClassPath -ErrorAction SilentlyContinue |
            Where-Object { $_.PSChildName -match '^\d{4}$' } | ForEach-Object {
                $driverDesc = (Get-ItemProperty $_.PSPath -Name 'DriverDesc' -EA SilentlyContinue).DriverDesc
                if ($driverDesc -and $driverDesc -notmatch '(?i)Microsoft|Virtual|Hyper-V|WAN Miniport|Bluetooth') {
                    $intPath = "$($_.PSPath)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
                    if (-not (Test-Path $intPath)) { try { New-Item $intPath -Force -EA SilentlyContinue | Out-Null } catch {} }
                    Set-ItemProperty $intPath -Name 'MSISupported' -Value 1 -Type DWord -EA SilentlyContinue
                    if ($opts.MSIPRIO) {
                        $affPath = "$($_.PSPath)\Device Parameters\Interrupt Management\Affinity Policy"
                        if (-not (Test-Path $affPath)) { try { New-Item $affPath -Force -EA SilentlyContinue | Out-Null } catch {} }
                        Set-ItemProperty $affPath -Name 'DevicePriority' -Value 3 -Type DWord -EA SilentlyContinue
                    }
                    Write-Log "  NIC MSI Mode: $driverDesc" 'OK'
                    $script:msiCount++
                }
            }
        }
        if ($opts.MSIGPU -or $opts.MSINVMe -or $opts.MSINIC) {
            if ($script:msiCount -gt 0) {
                Write-Log "MSI Mode: $($script:msiCount) aygit icin etkinlestirildi. Yeniden baslatma gerekli." 'OK'
                if ($opts.MSIPRIO) { Write-Log "  MSI IRQ Priority = High (DevicePriority=3)" 'OK' }
            } else {
                Write-Log "MSI Mode: Uygun aygit bulunamadi." 'WARN'
            }
        } else { Write-Log "MSI Mode: Secilmedi, atlanıyor." 'INFO' }

        $nvPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
        $nvSelected = $opts.NvPrerender -or $opts.NvPower -or $opts.NvSync -or $opts.NvFastSync -or $opts.NvShaderCache -or $opts.NvTexFilter
        if ($nvSelected) {
            if (Test-Path $nvPath) {
                $nvFound = $false
                Get-ChildItem $nvPath | Where-Object { $_.PSChildName -match '^\d{4}$' } | ForEach-Object {
                    $subkey = $_.PSPath
                    $driverDesc = (Get-ItemProperty -Path $subkey -Name 'DriverDesc' -EA SilentlyContinue).DriverDesc
                    # Sadece primary GPU'yu hedefle (en yuksek VRAM) — cift GPU sistemlerde yanlis GPU'ya yazma
                    $isTargetGpu = $driverDesc -match 'NVIDIA' -and (
                        $HW.GpuName -eq '' -or
                        $driverDesc -like "*$($HW.GpuName -replace '^NVIDIA\s*','')*" -or
                        $HW.GpuName -like "*$driverDesc*"
                    )
                    if ($isTargetGpu) {
                        $nvFound = $true
                        $applied = @()
                        if ($opts.NvPrerender) { Set-ItemProperty -Path $subkey -Name 'RMDxgkNDDSwapChainAcquireToHwCursorLatency' -Value 0 -EA SilentlyContinue; $applied += 'Prerender=0' }
                        if ($opts.NvPower)     { Set-ItemProperty -Path $subkey -Name 'DisableDynamicPstate' -Value 1 -EA SilentlyContinue; $applied += 'DynamicPstate=off' }
                        if ($opts.NvFastSync)  { Set-ItemProperty -Path $subkey -Name 'RMVSyncDelayFrameCount' -Value 0 -EA SilentlyContinue; $applied += 'FastSync=0' }
                        if ($opts.NvSync)      { 
                            # NVIDIA VSync registry devre disi — driver profil seviyesinde
                            Set-ItemProperty -Path $subkey -Name 'PerfLevelSrc'   -Value 0x2222 -Type DWord -EA SilentlyContinue
                            $applied += 'VSync=off(profil)'
                        }
                        if ($opts.NvShaderCache) { Set-ItemProperty -Path $subkey -Name 'DisableShaderDiskCache' -Value 0 -EA SilentlyContinue; $applied += 'ShaderCache=on' }
                        if ($opts.NvTexFilter)   { Set-ItemProperty -Path $subkey -Name 'TextureQualityOption' -Value 3 -EA SilentlyContinue; $applied += 'TexFilter=HighPerf' }
                        Write-Log "NVIDIA tweaks: $driverDesc" 'OK'
                        Write-Log "  Uygulanan: $($applied -join ', ')" 'OK'
                    }
                }
                if (-not $nvFound) { Write-Log "NVIDIA: Bu sistemde NVIDIA GPU bulunamadi." 'WARN' }
            } else { Write-Log "NVIDIA: GPU registry yolu bulunamadi." 'WARN' }
        } else { Write-Log "NVIDIA tweaks: Secilmedi, atlanıyor." 'INFO' }

        $amdPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
        $amdSelected = $opts.AMDAntiLag -or $opts.AMDChill -or $opts.AMDPower
        if ($amdSelected) {
            if (Test-Path $amdPath) {
                $amdFound = $false
                Get-ChildItem $amdPath | Where-Object { $_.PSChildName -match '^\d{4}$' } | ForEach-Object {
                    $subkey = $_.PSPath
                    $driverDesc = (Get-ItemProperty -Path $subkey -Name 'DriverDesc' -EA SilentlyContinue).DriverDesc
                    # Sadece primary GPU — AMD APU + AMD dGPU sistemlerde APU'yu atla
                    $isTargetAmd = $driverDesc -match 'AMD|Radeon|ATI' -and (
                        $HW.GpuName -eq '' -or
                        $driverDesc -like "*$($HW.GpuName -replace '^AMD\s*','')*" -or
                        $HW.GpuName -like "*$driverDesc*"
                    )
                    if ($isTargetAmd) {
                        $amdFound = $true
                        $applied = @()
                        if ($opts.AMDAntiLag) { Set-ItemProperty -Path $subkey -Name 'KMD_EnableAntiLag' -Value 1 -EA SilentlyContinue; $applied += 'AntiLag=1' }
                        if ($opts.AMDChill)   { Set-ItemProperty -Path $subkey -Name 'KMD_EnableChill'   -Value 0 -EA SilentlyContinue; $applied += 'Chill=0' }
                        if ($opts.AMDPower)   { Set-ItemProperty -Path $subkey -Name 'KMD_FRTEnabled'    -Value 0 -EA SilentlyContinue
                                                Set-ItemProperty -Path $subkey -Name 'EnableUlps'         -Value 0 -EA SilentlyContinue
                                                $applied += 'MaxPerf(ULPS=0,FRT=0)' }
                        Write-Log "AMD tweaks: $driverDesc" 'OK'
                        Write-Log "  Uygulanan: $($applied -join ', ')" 'OK'
                    }
                }
                if (-not $amdFound) { Write-Log "AMD: Bu sistemde AMD GPU bulunamadi." 'WARN' }
            } else { Write-Log "AMD: GPU registry yolu bulunamadi." 'WARN' }
        } else { Write-Log "AMD tweaks: Secilmedi, atlanıyor." 'INFO' }
    }
})

# ─── BACKEND: PRIVACY & TELEMETRY ─────────────────────────────────────────────
$BtnApplyPrivacy.Add_Click({
    $opts = Get-PageOpts @{
        DiagTrack='ChkDiagTrack'; DMWApp='ChkDMWAppSupport'; TelemetryReg='ChkTelemetryReg'
        AppCompat='ChkAppCompat'; ErrReport='ChkErrorReport'; ActHist='ChkActivityHist'
        Cortana='ChkCortana'; AdID='ChkAdID'; Tailored='ChkTailored'; Typing='ChkTyping'
        CEIP='ChkCEIP'; OneDrive='ChkOneDrive'; XboxSvc='ChkXboxServices'
        BingSearch='ChkBingSearch'; SuggestApps='ChkSuggestApps'; ConsumerExp='ChkConsumerExp'
    }
    Invoke-Async -TaskName 'Privacy & Telemetry' -ProgressKey 'Priv' -Vars @{ opts=$opts } -Block {
        Write-Log "--- Servisler ---" 'INFO'
        if ($opts.DiagTrack) {
            Stop-Service 'DiagTrack'  -Force -ErrorAction SilentlyContinue
            Set-Service 'DiagTrack' -StartupType Disabled -ErrorAction SilentlyContinue
            Write-Log "DiagTrack kapatildi" 'OK'
        }
        if ($opts.DMWApp) {
            Stop-Service 'dmwappushservice' -Force -ErrorAction SilentlyContinue
            Set-Service 'dmwappushservice' -StartupType Disabled -ErrorAction SilentlyContinue
            Write-Log "dmwappushservice kapatildi" 'OK'
        }
        if ($opts.TelemetryReg) {
            $telPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
            if (-not (Test-Path $telPath)) { New-Item -Path $telPath -Force | Out-Null }
            Set-ItemProperty -Path $telPath -Name 'AllowTelemetry' -Value 0 -ErrorAction SilentlyContinue
            Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' -Name 'AllowTelemetry' -Value 0 -ErrorAction SilentlyContinue
            Write-Log "Telemetry Level = 0 (Security only)" 'OK'
        }
        if ($opts.DiagTrack -or $opts.DMWApp -or $opts.TelemetryReg) {
            Write-Log "--- Registry Gizlilik Ayarlari ---" 'INFO'
        }
        if ($opts.AppCompat) {
            $schPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat'
            if (-not (Test-Path $schPath)) { New-Item -Path $schPath -Force | Out-Null }
            Set-ItemProperty -Path $schPath -Name 'DisableInventory'     -Value 1 -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $schPath -Name 'DisableProgramTelemetry' -Value 1 -ErrorAction SilentlyContinue
            Write-Log "App Compat telemetri kapatildi" 'OK'
        }
        if ($opts.ErrReport) {
            $wePath = 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting'
            Set-ItemProperty -Path $wePath -Name 'Disabled' -Value 1 -ErrorAction SilentlyContinue
            Set-Service 'WerSvc' -StartupType Disabled -ErrorAction SilentlyContinue
            Write-Log "Windows Error Reporting kapatildi" 'OK'
        }
        if ($opts.ActHist) {
            $ahPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
            if (-not (Test-Path $ahPath)) { New-Item -Path $ahPath -Force | Out-Null }
            Set-ItemProperty -Path $ahPath -Name 'EnableActivityFeed' -Value 0 -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $ahPath -Name 'PublishUserActivities' -Value 0 -ErrorAction SilentlyContinue
            Write-Log "Activity History kapatildi" 'OK'
        }
        if ($opts.Cortana) {
            $corPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'
            if (-not (Test-Path $corPath)) { New-Item -Path $corPath -Force | Out-Null }
            Set-ItemProperty -Path $corPath -Name 'AllowCortana' -Value 0 -ErrorAction SilentlyContinue
            Write-Log "Cortana kapatildi" 'OK'
        }
        if ($opts.AdID) {
            $adPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo'
            if (-not (Test-Path $adPath)) { New-Item -Path $adPath -Force | Out-Null }
            Set-ItemProperty -Path $adPath -Name 'Enabled' -Value 0 -ErrorAction SilentlyContinue
            Write-Log "Advertising ID kapatildi" 'OK'
        }
        if ($opts.Tailored) {
            $tePath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy'
            if (-not (Test-Path $tePath)) { New-Item -Path $tePath -Force | Out-Null }
            Set-ItemProperty -Path $tePath -Name 'TailoredExperiencesWithDiagnosticDataEnabled' -Value 0 -ErrorAction SilentlyContinue
            Write-Log "Tailored Experiences kapatildi" 'OK'
        }
        if ($opts.BingSearch) {
            $bingPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'
            Set-ItemProperty -Path $bingPath -Name 'BingSearchEnabled'    -Value 0 -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $bingPath -Name 'CortanaConsent'        -Value 0 -ErrorAction SilentlyContinue
            Write-Log "Bing Search Start Menu'dan kapatildi" 'OK'
        }
        if ($opts.SuggestApps) {
            Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'SystemPaneSuggestionsEnabled' -Value 0 -ErrorAction SilentlyContinue
            Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'SilentInstalledAppsEnabled'    -Value 0 -ErrorAction SilentlyContinue
            Write-Log "Suggested Apps kapatildi" 'OK'
        }
        if ($opts.ConsumerExp) {
            $cePath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
            if (-not (Test-Path $cePath)) { New-Item -Path $cePath -Force | Out-Null }
            Set-ItemProperty -Path $cePath -Name 'DisableWindowsConsumerFeatures' -Value 1 -ErrorAction SilentlyContinue
            Write-Log "Consumer Experience kapatildi" 'OK'
        }
        if ($opts.Typing) {
            # Inking & Typing Personalization — klavye/konuşma veri toplama
            $inkPath = 'HKCU:\Software\Microsoft\InputPersonalization'
            if (-not (Test-Path $inkPath)) { New-Item -Path $inkPath -Force | Out-Null }
            Set-ItemProperty -Path $inkPath -Name 'RestrictImplicitInkCollection' -Value 1 -EA SilentlyContinue
            Set-ItemProperty -Path $inkPath -Name 'RestrictImplicitTextCollection' -Value 1 -EA SilentlyContinue
            $inkTrain = "$inkPath\TrainedDataStore"
            if (-not (Test-Path $inkTrain)) { New-Item -Path $inkTrain -Force | Out-Null }
            Set-ItemProperty -Path $inkTrain -Name 'HarvestContacts' -Value 0 -EA SilentlyContinue
            $inkText = 'HKCU:\Software\Microsoft\Personalization\Settings'
            if (-not (Test-Path $inkText)) { New-Item -Path $inkText -Force | Out-Null }
            Set-ItemProperty -Path $inkText -Name 'AcceptedPrivacyPolicy' -Value 0 -EA SilentlyContinue
            Write-Log "Inking & Typing Personalization kapatildi" 'OK'
        }
        if ($opts.CEIP) {
            # CEIP / SQM veri toplama
            $sqmPath = 'HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows'
            if (-not (Test-Path $sqmPath)) { New-Item -Path $sqmPath -Force | Out-Null }
            Set-ItemProperty -Path $sqmPath -Name 'CEIPEnable' -Value 0 -EA SilentlyContinue
            $sqm2 = 'HKLM:\SOFTWARE\Microsoft\SQMClient\Windows'
            if (-not (Test-Path $sqm2)) { New-Item -Path $sqm2 -Force | Out-Null }
            Set-ItemProperty -Path $sqm2 -Name 'CEIPEnable' -Value 0 -EA SilentlyContinue
            Write-Log "CEIP (Customer Experience Improvement Program) kapatildi" 'OK'
        }
        if ($opts.XboxSvc) {
            @('XblAuthManager','XblGameSave','XboxNetApiSvc','XboxGipSvc') | ForEach-Object {
                Set-Service -Name $_ -StartupType Disabled -ErrorAction SilentlyContinue
                Stop-Service -Name $_ -Force -ErrorAction SilentlyContinue
                Write-Log "Xbox servisi kapatildi: $_" 'OK'
            }
        }
        if ($opts.OneDrive) {
            Write-Log "OneDrive kaldiriliyor..." 'RUN'
            taskkill /f /im OneDrive.exe 2>&1 | Out-Null
            $oneDrivePaths = @(
                "$env:SystemRoot\SysWOW64\OneDriveSetup.exe",
                "$env:SystemRoot\System32\OneDriveSetup.exe",
                "$env:LocalAppData\Microsoft\OneDrive\OneDriveSetup.exe"
            )
            foreach ($od in $oneDrivePaths) {
                if (Test-Path $od) {
                    Start-Process $od -ArgumentList '/uninstall' -Wait -ErrorAction SilentlyContinue
                    Write-Log "OneDrive kaldirildi: $od" 'OK'
                    break
                }
            }
        }
    }
})

# ─── BACKEND: WINDOWS TWEAKS ──────────────────────────────────────────────────
$BtnApplyWinTweaks.Add_Click({
    $opts = Get-PageOpts @{
        Animations='ChkAnimations'; JPEGQuality='ChkJPEGQuality'; MenuDelay='ChkMenuDelay'
        TaskbarAnims='ChkTaskbarAnims'; BSODDetail='ChkBSODDetail'; LaunchTo='ChkLaunchTo'
        NumLock='ChkNumlock'; HideExt='ChkHideExt'; LongPaths='ChkLongPaths'
        ContextMenu='ChkContextMenu'; DarkMode='ChkDarkMode'; Transparency='ChkTransparency'
        CrashDumpFull='ChkCrashDumpFull'; EventLogSize='ChkEventLogSize'
    }
    Invoke-Async -TaskName 'Windows Tweaks' -ProgressKey 'Win' -Vars @{ opts=$opts } -Block {
        Write-Log "--- Gorsel & UI ---" 'INFO'
        if ($opts.Animations) {
            $visPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
            Set-ItemProperty -Path $visPath -Name 'VisualFXSetting' -Value 2 -ErrorAction SilentlyContinue
            $deskPath = 'HKCU:\Control Panel\Desktop\WindowMetrics'
            Set-ItemProperty -Path $deskPath -Name 'MinAnimate' -Value '0' -ErrorAction SilentlyContinue
            $deskPath2 = 'HKCU:\Control Panel\Desktop'
            Set-ItemProperty -Path $deskPath2 -Name 'DragFullWindows'   -Value '0' -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $deskPath2 -Name 'FontSmoothing'     -Value 2   -ErrorAction SilentlyContinue
            Write-Log "Animasyonlar kapatildi" 'OK'
        }
        if ($opts.JPEGQuality) {
            $jpgPath = 'HKCU:\Control Panel\Desktop'
            Set-ItemProperty -Path $jpgPath -Name 'JPEGImportQuality' -Value 100 -ErrorAction SilentlyContinue
            Write-Log "JPEG Kalite = 100 (tam)" 'OK'
        }
        if ($opts.MenuDelay) {
            Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'MenuShowDelay' -Value '0' -ErrorAction SilentlyContinue
            Write-Log "MenuShowDelay = 0ms" 'OK'
        }
        if ($opts.TaskbarAnims) {
            Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'TaskbarAnimations' -Value 0 -ErrorAction SilentlyContinue
            Write-Log "Taskbar animasyonlari kapatildi" 'OK'
        }
        if ($opts.BSODDetail) {
            $crashPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl'
            Set-ItemProperty -Path $crashPath -Name 'AutoReboot' -Value 0 -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $crashPath -Name 'DisplayParameters' -Value 1 -ErrorAction SilentlyContinue
            Write-Log "BSOD AutoReboot kapatildi, detayli hata kodu aktif" 'OK'
        }
        if ($opts.LaunchTo) {
            Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'LaunchTo' -Value 1 -ErrorAction SilentlyContinue
            Write-Log "Explorer This PC'de acilacak sekilde ayarlandi" 'OK'
        }
        if ($opts.NumLock) {
            Set-ItemProperty -Path 'HKCU:\Control Panel\Keyboard' -Name 'InitialKeyboardIndicators' -Value '2' -ErrorAction SilentlyContinue
            Write-Log "NumLock baslangicta acik" 'OK'
        }
        if ($opts.HideExt) {
            Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'HideFileExt' -Value 0 -ErrorAction SilentlyContinue
            Write-Log "Dosya uzantilari gorunur" 'OK'
        }
        if ($opts.LongPaths) {
            Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -Value 1 -ErrorAction SilentlyContinue
            Write-Log "Long Path Support etkin" 'OK'
        }
        if ($opts.Transparency) {
            $transPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
            if (-not (Test-Path $transPath)) { New-Item -Path $transPath -Force | Out-Null }
            Set-ItemProperty -Path $transPath -Name 'EnableTransparency' -Value 0 -EA SilentlyContinue
            Write-Log "Arayuz seffafligi kapatildi" 'OK'
        }
        if ($opts.ContextMenu) {
            $cmdPath = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'
            if (-not (Test-Path $cmdPath)) { New-Item -Path $cmdPath -Force | Out-Null }
            Set-ItemProperty -Path $cmdPath -Name '(default)' -Value '' -ErrorAction SilentlyContinue
            Write-Log "Eski sag tik menusu aktif (Win11). Sayfa sonu Explorer restart ile uygulanacak." 'OK'
        }
        if ($opts.DarkMode) {
            Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'AppsUseLightTheme'   -Value 0 -ErrorAction SilentlyContinue
            Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'SystemUsesLightTheme' -Value 0 -ErrorAction SilentlyContinue
            Write-Log "Dark Mode etkinlestirildi" 'OK'
        }
        if ($opts.CrashDumpFull) {
            $crashPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl'
            Set-ItemProperty -Path $crashPath -Name 'CrashDumpEnabled' -Value 1 -Type DWord -EA SilentlyContinue
            Write-Log "Tam bellek dump aktif (CrashDumpEnabled=1)" 'OK'
        }
        if ($opts.EventLogSize) {
            $logNames = @('Application','System','Security')
            foreach ($logName in $logNames) {
                try {
                    # Get-EventLog Win11'de deprecated — wevtutil ile ayarla
                    $result = wevtutil sl $logName /ms:104857600 2>&1  # 100MB = 104857600 byte
                    if ($LASTEXITCODE -eq 0) {
                        Write-Log "Event Log '$logName' max boyutu 100MB yapildi (wevtutil)" 'OK'
                    } else {
                        # Fallback: registry ile boyut ayarla
                        $evtPath = "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\$logName"
                        if (Test-Path $evtPath) {
                            Set-ItemProperty -Path $evtPath -Name 'MaxSize' -Value 104857600 -Type DWord -EA SilentlyContinue
                            Write-Log "Event Log '$logName' max boyutu 100MB (registry)" 'OK'
                        }
                    }
                } catch { Write-Log "EventLogSize '$logName' ayarlanamadi: $_" 'WARN' }
            }
        }
        # Explorer restart - sadece görsel UI değişiklikleri seçiliyse yap
        $explorerRestartNeeded = $opts.Animations -or $opts.TaskbarAnims -or $opts.ContextMenu -or
                                  $opts.DarkMode -or $opts.Transparency -or $opts.LaunchTo -or
                                  $opts.HideExt -or $opts.MenuDelay
        if ($explorerRestartNeeded) {
            Write-Log "--- Explorer Yeniden Baslatma ---" 'INFO'
            Write-Log "Explorer yeniden baslatiliyor..." 'RUN'
            Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 600
            Start-Process explorer
            Write-Log "Explorer yeniden baslatildi" 'OK'
        } else {
            Write-Log "Explorer restart: UI tweaks secilmedi, atlanıyor." 'INFO'
        }
    }
})

# ─── BACKEND: RUN SCRIPT ──────────────────────────────────────────────────────
$BtnImportScript.Add_Click({
    $ofd = [System.Windows.Forms.OpenFileDialog]::new()
    $ofd.Filter = 'Script Dosyalari|*.ps1;*.bat;*.cmd;*.txt|Tum Dosyalar|*.*'
    $ofd.Title  = 'Script Dosyasi Sec'
    if ($ofd.ShowDialog() -eq 'OK') {
        try {
            $content = Get-Content $ofd.FileName -Raw -Encoding UTF8
            $ScriptEditor.Text = $content
            Write-Log "Script ice aktarildi: $($ofd.FileName)" 'OK'
        } catch {
            Write-Log "Script okunamadi: $_" 'ERROR'
        }
    }
})

$BtnRunImported.Add_Click({
    $code = $ScriptEditor.Text
    if ([string]::IsNullOrWhiteSpace($code)) {
        Write-Log "Calistirilacak kod yok." 'WARN'
        return
    }
    Invoke-Async -TaskName 'Custom Script' -Vars @{ code=$code } -Block {
        try {
            $sb = [scriptblock]::Create($code)
            & $sb 2>&1 | ForEach-Object { Write-Log $_.ToString() }
        } catch {
            Write-Log "Script hatasi: $_" 'ERROR'
        }
    }
})

$BtnClearEditor.Add_Click({
    $ScriptEditor.Text = "# Buraya kod yapistirin veya import edin...`r`n"
    Write-Log "Script editoru temizlendi" 'INFO'
})

# ─── GLOBAL PRESETS ───────────────────────────────────────────────────────────
function Apply-PresetCheckboxes([hashtable]$map) {
    foreach ($key in $map.Keys) {
        $ctrl = $Window.FindName($key)
        if ($ctrl) { $ctrl.IsChecked = $map[$key] }
    }
}

$PresetMinimal = @{
    # Quick Clean - safe only
    ChkTempWin=$true; ChkTempSys=$true; ChkPrefetch=$true; ChkRecycleBin=$true
    ChkThumb=$false; ChkFontCache=$false; ChkChromeCache=$false; ChkEdgeCache=$false
    ChkFirefoxCache=$false; ChkSteamCache=$false; ChkDNSCache=$true
    ChkEventLogs=$false; ChkCrashDumps=$false; ChkWinUpdCache=$false; ChkDeliveryOpt=$false
    # Performance - minimal
    ChkHPET=$false; ChkTimerRes=$false; ChkCpuPriority=$false; ChkSysMain=$false; ChkWSearch=$false
    ChkGameMode=$true; ChkHwAccel=$false; ChkWUpdate=$false; ChkEmptyRAM=$false; ChkModifiedRAM=$false
    # Network - safe
    ChkAutoTuning=$false; ChkECN=$false; ChkRSC=$false; ChkCongestion=$false
    ChkNetThrottle=$false; ChkNagle=$false; ChkRSS=$true; ChkDNSPrefetch=$true
    ChkFlowCtrl=$false; ChkIntMod=$false; ChkGreenEth=$false; ChkGigaLite=$false; ChkAdaptInter=$false
    # Kernel - nothing risky
    ChkVBS=$false; ChkDMAProtect=$false; ChkSpectre=$false; ChkCFG=$false; ChkHVCI=$false
    ChkMouseAccel=$false; ChkMouseSmooth=$false; ChkMouseBuffer=$false; ChkKbBuffer=$false
    ChkRawInput=$false; ChkLargePages=$false; ChkContMem=$false; ChkPagingFiles=$false
    # GPU - safe
    ChkMSIGPU=$false; ChkMSINVMe=$false; ChkMSINIC=$false; ChkMSIPrio=$false
    ChkNvShaderCache=$true; ChkNvTexFilter=$false
    # Privacy - safe
    ChkDiagTrack=$true; ChkTelemetryReg=$true; ChkAdID=$true; ChkBingSearch=$true
    ChkCEIP=$true; ChkOneDrive=$false; ChkXboxServices=$false
    # Tweaks - safe
    ChkAnimations=$false; ChkMenuDelay=$true; ChkBSODDetail=$true; ChkHideExt=$true; ChkLongPaths=$true
    ChkJPEGQuality=$true; ChkNumlock=$true; ChkDarkMode=$false; ChkContextMenu=$false
    ChkTransparency=$false; ChkCrashDumpFull=$false; ChkEventLogSize=$false
}

$PresetStandard = @{
    # Quick Clean
    ChkTempWin=$true; ChkTempSys=$true; ChkPrefetch=$true; ChkRecycleBin=$true
    ChkThumb=$true; ChkChromeCache=$true; ChkEdgeCache=$true; ChkDNSCache=$true
    ChkCrashDumps=$true; ChkDeliveryOpt=$true
    # Performance
    ChkHPET=$true; ChkTimerRes=$false; ChkCpuPriority=$true; ChkGameMode=$true; ChkHwAccel=$true
    ChkSysMain=$false; ChkWSearch=$false; ChkWUpdate=$true; ChkEmptyRAM=$true; ChkModifiedRAM=$true
    # Network
    ChkAutoTuning=$true; ChkECN=$true; ChkRSC=$true; ChkCongestion=$true
    ChkNetThrottle=$true; ChkNagle=$true; ChkTCPNoDelay=$true; ChkTCPACKFreq=$true
    ChkRSS=$true; ChkFlowCtrl=$true; ChkIntMod=$true; ChkGreenEth=$true; ChkGigaLite=$true
    ChkDNSPrefetch=$true; ChkAdaptInter=$false; ChkLLMNR=$true; ChkMDNS=$false
    # Kernel
    ChkVBS=$false; ChkDMAProtect=$false; ChkSpectre=$false; ChkCFG=$false; ChkHVCI=$false
    ChkLargePages=$false; ChkContMem=$true; ChkPagingFiles=$false
    ChkMouseBuffer=$true; ChkKbBuffer=$true; ChkMouseSmooth=$true; ChkMouseAccel=$true; ChkRawInput=$true
    # GPU
    ChkMSIGPU=$true; ChkMSINVMe=$true; ChkMSINIC=$false; ChkMSIPrio=$true
    ChkNvPrerender=$true; ChkNvPower=$true; ChkNvSync=$true; ChkNvFastSync=$true
    ChkNvShaderCache=$true; ChkNvTexFilter=$false
    ChkAMDAntiLag=$true; ChkAMDChill=$true; ChkAMDPower=$true
    # Privacy
    ChkDiagTrack=$true; ChkTelemetryReg=$true; ChkAdID=$true; ChkBingSearch=$true
    ChkCEIP=$true; ChkCortana=$true; ChkSuggestApps=$true; ChkConsumerExp=$true
    ChkOneDrive=$false; ChkXboxServices=$false
    # Tweaks
    ChkAnimations=$true; ChkMenuDelay=$true; ChkBSODDetail=$true; ChkJPEGQuality=$true
    ChkHideExt=$true; ChkLongPaths=$true; ChkNumlock=$true; ChkTaskbarAnims=$true
    ChkDarkMode=$false; ChkContextMenu=$false; ChkTransparency=$false
    ChkCrashDumpFull=$false; ChkEventLogSize=$false
}

$PresetAggressive = @{
    # Quick Clean
    ChkTempWin=$true; ChkTempSys=$true; ChkPrefetch=$true; ChkRecycleBin=$true
    ChkThumb=$true; ChkFontCache=$true; ChkChromeCache=$true; ChkEdgeCache=$true
    ChkDNSCache=$true; ChkCrashDumps=$true; ChkWinUpdCache=$false; ChkDeliveryOpt=$true
    ChkWinSxS=$false
    # Performance
    ChkHPET=$true; ChkTimerRes=$true; ChkCpuPriority=$true; ChkGameMode=$true; ChkHwAccel=$true
    ChkSysMain=$true; ChkWSearch=$true; ChkWUpdate=$true; ChkEmptyRAM=$true; ChkModifiedRAM=$true
    # Network
    ChkAutoTuning=$true; ChkECN=$true; ChkRSC=$true; ChkCongestion=$true
    ChkNetThrottle=$true; ChkNagle=$true; ChkTCPNoDelay=$true; ChkTCPACKFreq=$true
    ChkRSS=$true; ChkFlowCtrl=$true; ChkIntMod=$true; ChkGreenEth=$true; ChkGigaLite=$true
    ChkDNSPrefetch=$true; ChkAdaptInter=$true; ChkLLMNR=$true; ChkMDNS=$true
    # Kernel
    ChkVBS=$false; ChkDMAProtect=$false; ChkSpectre=$false; ChkCFG=$false; ChkHVCI=$false
    ChkLargePages=$false; ChkContMem=$true; ChkPagingFiles=$true
    ChkMouseBuffer=$true; ChkKbBuffer=$true; ChkMouseSmooth=$true; ChkMouseAccel=$true; ChkRawInput=$true
    # GPU
    ChkMSIGPU=$true; ChkMSINVMe=$true; ChkMSINIC=$true; ChkMSIPrio=$true
    ChkNvPrerender=$true; ChkNvPower=$true; ChkNvSync=$true; ChkNvFastSync=$true
    ChkNvShaderCache=$true; ChkNvTexFilter=$false
    ChkAMDAntiLag=$true; ChkAMDChill=$true; ChkAMDPower=$true
    # Privacy
    ChkDiagTrack=$true; ChkDMWAppSupport=$true; ChkTelemetryReg=$true; ChkAppCompat=$true
    ChkErrorReport=$true; ChkActivityHist=$true; ChkAdID=$true; ChkCortana=$true
    ChkCEIP=$true; ChkTailored=$true; ChkTyping=$true; ChkBingSearch=$true
    ChkSuggestApps=$true; ChkConsumerExp=$true; ChkXboxServices=$true; ChkOneDrive=$false
    # Tweaks
    ChkAnimations=$true; ChkTransparency=$true; ChkMenuDelay=$true; ChkTaskbarAnims=$true
    ChkBSODDetail=$true; ChkHideExt=$true; ChkLongPaths=$true; ChkNumlock=$true
    ChkLaunchTo=$true; ChkJPEGQuality=$true; ChkDarkMode=$false; ChkContextMenu=$false
    ChkCrashDumpFull=$false; ChkEventLogSize=$false
}

$global:_PresetBtnGroup = @($BtnPresetMinimal, $BtnPresetStandard, $BtnPresetAggressive)

$BtnPresetMinimal.Add_Click({
    Set-ActiveButton -ActiveBtn $BtnPresetMinimal -Group $global:_PresetBtnGroup
    Apply-PresetCheckboxes $PresetMinimal
    Write-Log "Preset uygulandi: Minimal (Safe)" 'OK'
    Set-Status "Preset: Minimal"
})
$BtnPresetStandard.Add_Click({
    Set-ActiveButton -ActiveBtn $BtnPresetStandard -Group $global:_PresetBtnGroup
    Apply-PresetCheckboxes $PresetStandard
    Write-Log "Preset uygulandi: Standard (Balanced)" 'OK'
    Set-Status "Preset: Standard"
})
$BtnPresetAggressive.Add_Click({
    Set-ActiveButton -ActiveBtn $BtnPresetAggressive -Group $global:_PresetBtnGroup
    Apply-PresetCheckboxes $PresetAggressive
    Write-Log "Preset uygulandi: Aggressive (Gaming)" 'OK'
    Set-Status "Preset: Aggressive"
})


$BtnBackupPerf.Add_Click({
    Backup-Registry 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'Manual_Perf_MemMgmt'
    Backup-Registry 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'Manual_Perf_MM'
    Backup-Registry 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Manual_Perf_Priority'
    Write-Log "Performance yedekleri alindi: _Files\Backups klasoru" 'OK'
})

$BtnBackupNetwork.Add_Click({
    Backup-Registry 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' 'Manual_Network_TCP'
    Backup-Registry 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces' 'Manual_Network_Interfaces'
    Backup-Registry 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'Manual_Network_MM'
    Backup-Registry 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters' 'Manual_Network_DNS'
    Write-Log "Network yedekleri alindi: _Files\Backups klasoru" 'OK'
})

$BtnBackupKernel.Add_Click({
    Backup-Registry 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'Manual_Kernel_DevGuard'
    Backup-Registry 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'Manual_Kernel_MemMgmt'
    Backup-Registry 'HKCU:\Control Panel\Mouse' 'Manual_Kernel_Mouse'
    Write-Log "Kernel & Input yedekleri alindi: _Files\Backups klasoru" 'OK'
})

$BtnBackupGPU.Add_Click({
    Backup-Registry 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}' 'Manual_GPU_Class'
    Backup-Registry 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e97b-e325-11ce-bfc1-08002be10318}' 'Manual_NVMe_Class'
    Backup-Registry 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}' 'Manual_NIC_Class'
    Backup-Registry 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'Manual_GPU_GraphicsDrivers'
    Write-Log "GPU & MSI (GPU/NVMe/NIC class) yedekleri alindi: _Files\Backups klasoru" 'OK'
})

$BtnBackupPrivacy.Add_Click({
    Backup-Registry 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'Manual_Privacy_DataCollection'
    Backup-Registry 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Manual_Privacy_AdID'
    Backup-Registry 'HKLM:\SOFTWARE\Policies\Microsoft\Windows' 'Manual_Privacy_Policies'
    Backup-Registry 'HKCU:\Software\Microsoft\InputPersonalization' 'Manual_Privacy_InputPersonalization'
    Backup-Registry 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting' 'Manual_Privacy_WER'
    Write-Log "Privacy yedekleri alindi: _Files\Backups klasoru" 'OK'
})

$BtnBackupWinTweaks.Add_Click({
    Backup-Registry 'HKCU:\Control Panel\Desktop' 'Manual_WinTweaks_Desktop'
    Backup-Registry 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Manual_WinTweaks_Explorer'
    Backup-Registry 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'Manual_WinTweaks_FileSystem'
    Write-Log "Windows Tweaks yedekleri alindi: _Files\Backups klasoru" 'OK'
})

# Apply All
$BtnApplyAll.Add_Click({
    $result = [System.Windows.MessageBox]::Show(
        "Tum optimize edilecek sayfalar SIRAYLA uygulanacak:`n`n- Performance tweaks`n- Network tweaks`n- Kernel & Input tweaks`n- GPU & MSI Mode`n- Privacy & Telemetry`n- Windows Tweaks`n`nBu islem 1-2 dakika surebilir. Devam edilsin mi?",
        "Tumunu Uygula",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Warning)
    if ($result -ne [System.Windows.MessageBoxResult]::Yes) { return }

    # ── DRY: Tum sayfa opts'larini Get-PageOpts ile topla (eskiden 80+ satir) ──
    $allPerfOpts = Get-PageOpts @{
        HPET='ChkHPET'; TimerRes='ChkTimerRes'; CpuPrio='ChkCpuPriority'
        SysMain='ChkSysMain'; WSearch='ChkWSearch'; WUpdate='ChkWUpdate'
        GameMode='ChkGameMode'; HwAccel='ChkHwAccel'
        EmptyRAM='ChkEmptyRAM'; ModifiedRAM='ChkModifiedRAM'
    }
    $allPerfOpts.CpuIsAMD  = $global:HW.CpuIsAMD
    $allPerfOpts.CpuIsIntel= $global:HW.CpuIsIntel
    $allPerfOpts.GpuIsNV   = $global:HW.GpuIsNV
    $allPerfOpts.GpuIsAMD  = $global:HW.GpuIsAMD
    $allPerfOpts.planAction= $null
    # Apply All: secili plan butonunu tespit et ve planAction'a yaz
    $selPlanBtn = $global:_PlanBtnGroup | Where-Object { $_.Style -eq $Window.Resources['BtnActive'] } | Select-Object -First 1
    if ($selPlanBtn) {
        $allPerfOpts.planAction = switch ($selPlanBtn.Name) {
            'BtnPlanBitsum'   { 'Bitsum'        }
            'BtnPlanHybred'   { 'HybredHighPerf' }
            'BtnPlanHybred2'  { 'HybredBalanced' }
            'BtnPlanUlti'     { 'Ultimate'       }
            'BtnPlanBalanced' { 'Balanced'       }
            'BtnPlanDefault'  { 'HighPerf'       }
            default           { $null            }
        }
    }

    $allNetOpts = Get-PageOpts @{
        AutoTuning='ChkAutoTuning'; ECN='ChkECN'; RSC='ChkRSC'; Congestion='ChkCongestion'
        NetThrottle='ChkNetThrottle'; Nagle='ChkNagle'; TCPNoDelay='ChkTCPNoDelay'
        TCPACKFreq='ChkTCPACKFreq'; RSS='ChkRSS'; FlowCtrl='ChkFlowCtrl'
        IntMod='ChkIntMod'; GreenEth='ChkGreenEth'; GigaLite='ChkGigaLite'
        AdaptInter='ChkAdaptInter'; DNSPrefetch='ChkDNSPrefetch'; MDNS='ChkMDNS'; LLMNR='ChkLLMNR'
    }

    $allKernOpts = Get-PageOpts @{
        VBS='ChkVBS'; DMAProtect='ChkDMAProtect'; Spectre='ChkSpectre'; CFG='ChkCFG'
        HVCI='ChkHVCI'; LargePages='ChkLargePages'; ContMem='ChkContMem'
        MouseBuf='ChkMouseBuffer'; KbBuf='ChkKbBuffer'; RawInput='ChkRawInput'
        MouseSmooth='ChkMouseSmooth'; MouseAccel='ChkMouseAccel'; PagingFiles='ChkPagingFiles'
    }

    $allGpuOpts = Get-PageOpts @{
        MSIGPU='ChkMSIGPU'; MSINVMe='ChkMSINVMe'; MSINIC='ChkMSINIC'; MSIPRIO='ChkMSIPrio'
        NvPrerender='ChkNvPrerender'; NvPower='ChkNvPower'; NvSync='ChkNvSync'
        NvShaderCache='ChkNvShaderCache'; NvTexFilter='ChkNvTexFilter'; NvFastSync='ChkNvFastSync'
        AMDAntiLag='ChkAMDAntiLag'; AMDChill='ChkAMDChill'; AMDPower='ChkAMDPower'
    }

    $allPrivOpts = Get-PageOpts @{
        DiagTrack='ChkDiagTrack'; DMWApp='ChkDMWAppSupport'; TelemetryReg='ChkTelemetryReg'
        AppCompat='ChkAppCompat'; ErrReport='ChkErrorReport'; ActHist='ChkActivityHist'
        Cortana='ChkCortana'; AdID='ChkAdID'; Tailored='ChkTailored'; Typing='ChkTyping'
        CEIP='ChkCEIP'; OneDrive='ChkOneDrive'; XboxSvc='ChkXboxServices'
        BingSearch='ChkBingSearch'; SuggestApps='ChkSuggestApps'; ConsumerExp='ChkConsumerExp'
    }

    $allWinOpts = Get-PageOpts @{
        Animations='ChkAnimations'; JPEGQuality='ChkJPEGQuality'; MenuDelay='ChkMenuDelay'
        TaskbarAnims='ChkTaskbarAnims'; BSODDetail='ChkBSODDetail'; LaunchTo='ChkLaunchTo'
        NumLock='ChkNumlock'; HideExt='ChkHideExt'; LongPaths='ChkLongPaths'
        ContextMenu='ChkContextMenu'; DarkMode='ChkDarkMode'; Transparency='ChkTransparency'
        CrashDumpFull='ChkCrashDumpFull'; EventLogSize='ChkEventLogSize'
    }

    Write-Log "=== TUM OPTIMIZASYONLAR BASLATILAYOR (SIRAYLA) ===" 'RUN'

    # Tum asamalari tek bir runspace'te sirayla calistir — Set-Busy cakilmasini onler
    Invoke-Async -TaskName 'Tum Optimizasyonlar' -Vars @{
        allPerfOpts=$allPerfOpts; allNetOpts=$allNetOpts; allKernOpts=$allKernOpts
        allGpuOpts=$allGpuOpts; allPrivOpts=$allPrivOpts; allWinOpts=$allWinOpts
        HW=$global:HW; RootPath=$global:RootPath
    } -Block {
        # ── 1. PERFORMANCE ──
        Write-Log "--- 1/6 Performance ---" 'RUN'
        $opts = $allPerfOpts
        if ($opts.HPET) {
            bcdedit /set useplatformclock false 2>&1 | Out-Null
            bcdedit /set disabledynamictick yes 2>&1 | Out-Null
            bcdedit /deletevalue useplatformtick 2>&1 | Out-Null
            Write-Log "HPET disabled" 'OK'
        }
        if ($opts.TimerRes) {
            $trPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel'
            if (-not (Test-Path $trPath)) { New-Item $trPath -Force | Out-Null }
            Set-ItemProperty $trPath 'GlobalTimerResolutionRequests' 1 -Type DWord -EA SilentlyContinue
            bcdedit /set tscsyncpolicy enhanced 2>&1 | Out-Null
            Write-Log "Timer Resolution: GlobalTimerResolutionRequests=1, TSC=enhanced" 'OK'
        }
        if ($opts.CpuPrio) {
            $mmPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
            Set-ItemProperty $mmPath 'SystemResponsiveness' 0 -EA SilentlyContinue
            Set-ItemProperty $mmPath 'NetworkThrottlingIndex' 0xFFFFFFFF -EA SilentlyContinue
            $gamePath = "$mmPath\Tasks\Games"
            if (-not (Test-Path $gamePath)) { New-Item $gamePath -Force | Out-Null }
            @{'Affinity'=0;'Background Only'='False';'Clock Rate'=10000;'GPU Priority'=8;'Priority'=6;'Scheduling Category'='High';'SFIO Priority'='High'}.GetEnumerator() | ForEach-Object { Set-ItemProperty $gamePath $_.Key $_.Value -EA SilentlyContinue }
            Write-Log "CPU/GPU oncelikleri yukseltildi" 'OK'
            if ($HW.CpuIsAMD)   { Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' 'CppcEnable' 1 -Type DWord -EA SilentlyContinue; Write-Log "AMD CPPC aktif" 'OK' }
            if ($HW.CpuIsIntel) { Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' 'EnergyPerfPreference' 0 -Type DWord -EA SilentlyContinue; Write-Log "Intel SpeedStep perf modu" 'OK' }
        }
        if ($opts.GameMode) {
            $gm='HKCU:\Software\Microsoft\GameBar'
            if (-not (Test-Path $gm)) { New-Item $gm -Force | Out-Null }
            Set-ItemProperty $gm 'AllowAutoGameMode'   1 -EA SilentlyContinue
            Set-ItemProperty $gm 'AutoGameModeEnabled' 1 -EA SilentlyContinue
            Write-Log "Game Mode aktif" 'OK'
        }
        if ($opts.HwAccel -and ($HW.GpuIsNV -or $HW.GpuIsAMD)) { Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2 -Type DWord -EA SilentlyContinue; Write-Log "HW GPU Scheduling aktif" 'OK' }
        if ($opts.SysMain) { Set-Service 'SysMain' -StartupType Disabled -EA SilentlyContinue; Stop-Service 'SysMain' -Force -EA SilentlyContinue; Write-Log "SysMain kapatildi" 'OK' }
        if ($opts.WSearch) { Set-Service 'WSearch' -StartupType Disabled -EA SilentlyContinue; Stop-Service 'WSearch' -Force -EA SilentlyContinue; Write-Log "WSearch kapatildi" 'OK' }
        if ($opts.WUpdate) {
            $auPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
            if (-not (Test-Path $auPath)) { New-Item $auPath -Force | Out-Null }
            Set-ItemProperty $auPath 'AUOptions' 4 -Type DWord -EA SilentlyContinue
            Set-ItemProperty $auPath 'NoAutoUpdate' 0 -Type DWord -EA SilentlyContinue
            $wuPath = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
            if (-not (Test-Path $wuPath)) { New-Item $wuPath -Force | Out-Null }
            Set-ItemProperty $wuPath 'DeferFeatureUpdates' 1 -Type DWord -EA SilentlyContinue
            Set-ItemProperty $wuPath 'DeferFeatureUpdatesPeriodInDays' 365 -Type DWord -EA SilentlyContinue
            Set-ItemProperty $wuPath 'DeferQualityUpdates' 1 -Type DWord -EA SilentlyContinue
            Set-ItemProperty $wuPath 'DeferQualityUpdatesPeriodInDays' 7 -Type DWord -EA SilentlyContinue
            Write-Log "Windows Update: Feature=365gun, Quality=7gun gecikme" 'OK'
        }
        # ISLC — EmptyRAM/ModifiedRAM seciliyse (ISLC + Native API Fallback)
        if ($opts.EmptyRAM -or $opts.ModifiedRAM) {
            $islcExeAA  = 'Intelligent standby list cleaner ISLC.exe'
            $islcPathAA = Join-Path $RootPath "_Files\ISLC\$islcExeAA"
            if (Test-Path $islcPathAA) {
                $ramGBAA  = if ($HW -and $HW.RamGB -gt 0) { [int]$HW.RamGB } else { 16 }
                $listMBAA = 1024
                $freeMBAA = [int]($ramGBAA * 1024 / 2)
                # Config yaz
                $islcConfigAA = Join-Path (Split-Path $islcPathAA) 'ISLC.ini'
                try {
                    $ini = "[Settings]`r`nTimerRes=False`r`nLaunchOnLogon=True`r`nListSize=$listMBAA`r`nFreeMemory=$freeMBAA`r`nPollingRate=10000`r`nStartLLConfig=False"
                    [System.IO.File]::WriteAllText($islcConfigAA, $ini, [System.Text.Encoding]::UTF8)
                    Write-Log "ISLC: Config yazildi (LaunchOnLogon=True)" 'OK'
                } catch {}
                Get-Process -Name 'Intelligent standby list cleaner ISLC' -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
                Start-Sleep -Milliseconds 500
                try {
                    $p = Start-Process $islcPathAA '-purge' -PassThru -WindowStyle Hidden -EA Stop
                    if (-not $p.WaitForExit(10000)) { $p | Stop-Process -Force -EA SilentlyContinue }
                    Write-Log "ISLC: Standby List temizlendi" 'OK'
                } catch {}
                Get-Process -Name 'Intelligent standby list cleaner ISLC' -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
                Start-Sleep -Milliseconds 400
                try {
                    Start-Process $islcPathAA "-minimized -polling 10000 -listsize $listMBAA -freememory $freeMBAA" -WindowStyle Hidden -EA SilentlyContinue
                    Write-Log "ISLC: Monitoring baslatildi (Task Scheduler ISLC tarafindan yonetilir)" 'OK'
                } catch {}
            } else {
                # Native API Fallback — ISLC yoksa
                Write-Log "ISLC bulunamadi — Native API ile RAM temizleniyor..." 'INFO'
                try {
                    $nativeRAM = 'using System; using System.Runtime.InteropServices; public class MemPurge { [DllImport("ntdll.dll")] public static extern int NtSetSystemInformation(int InfoClass, ref int Info, int Length); public static bool PurgeStandby() { int cmd = 4; int r = NtSetSystemInformation(80, ref cmd, sizeof(int)); return r == 0; } }'
                    if (-not ([System.Management.Automation.PSTypeName]'MemPurge').Type) {
                        Add-Type -TypeDefinition $nativeRAM -Language CSharp -ErrorAction Stop
                    }
                    $purgeOk = [MemPurge]::PurgeStandby()
                    if ($purgeOk) { Write-Log "Native API: Standby List temizlendi" 'OK' }
                    else          { Write-Log "Native API: Standby List temizlenemedi" 'WARN' }
                } catch { Write-Log "Native RAM API hatasi: $_" 'WARN' }
            }
        }
        # Power plan — Apply All'da secili plan uygulanir
        if ($opts.planAction) {
            Write-Log "Guc plani uygulanıyor: $($opts.planAction)" 'RUN'
            switch ($opts.planAction) {
                'Bitsum' {
                    $pf = Join-Path $RootPath '_Files\Bitsum-Highest-Performance.pow'
                    if (Test-Path $pf) {
                        $out = powercfg /import $pf 2>&1
                        $g = [regex]::Match(($out -join ' '), '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})')
                        if ($g.Success) { powercfg /setactive $g.Value 2>&1|Out-Null; Write-Log "Bitsum aktif: $($g.Value)" 'OK' }
                        else { powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>&1|Out-Null; Write-Log "Bitsum bulunamadi, HighPerf aktif" 'WARN' }
                    }
                }
                'HybredHighPerf' {
                    $dirs = @((Join-Path $RootPath '_Files\HybredPowerPlans'), (Join-Path $RootPath '_Files'))
                    $pf = $dirs | ForEach-Object { Join-Path $_ 'HybredLowLatencyHighPerf.pow' } | Where-Object { Test-Path $_ } | Select-Object -First 1
                    if ($pf) { $out=powercfg /import $pf 2>&1; $g=[regex]::Match(($out -join ' '),'([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})'); if($g.Success){powercfg /setactive $g.Value 2>&1|Out-Null; Write-Log "Hybred HighPerf aktif" 'OK'} }
                }
                'HybredBalanced' {
                    $dirs = @((Join-Path $RootPath '_Files\HybredPowerPlans'), (Join-Path $RootPath '_Files'))
                    $pf = $dirs | ForEach-Object { Join-Path $_ 'HybredLowLatencyBalanced.pow' } | Where-Object { Test-Path $_ } | Select-Object -First 1
                    if ($pf) { $out=powercfg /import $pf 2>&1; $g=[regex]::Match(($out -join ' '),'([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})'); if($g.Success){powercfg /setactive $g.Value 2>&1|Out-Null; Write-Log "Hybred Balanced aktif" 'OK'} }
                }
                'Ultimate' { powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1|Out-Null; $ulti=powercfg /list 2>&1|Where-Object{$_ -match 'e9a42b02'}|Select-Object -Last 1|ForEach-Object{[regex]::Match($_,'([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})').Value}; if($ulti){powercfg /setactive $ulti 2>&1|Out-Null; Write-Log "Ultimate Performance aktif" 'OK'} }
                'Balanced' { powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e 2>&1|Out-Null; Write-Log "Balanced aktif" 'OK' }
                'HighPerf'  { powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>&1|Out-Null; Write-Log "High Performance aktif" 'OK' }
            }
        }
        Write-Log "--- 1/6 Performance TAMAM ---" 'OK'

        # ── 2. NETWORK ──
        Write-Log "--- 2/6 Network ---" 'RUN'
        $opts = $allNetOpts
        if ($opts.AutoTuning) { netsh int tcp set global autotuninglevel=normal 2>&1|Out-Null; Write-Log "AutoTuning normal" 'OK' }
        if ($opts.ECN)        { netsh int tcp set global ecncapability=disabled 2>&1|Out-Null; Write-Log "ECN disabled" 'OK' }
        if ($opts.RSC)        { netsh int tcp set global rsc=disabled 2>&1|Out-Null; Write-Log "RSC disabled" 'OK' }
        if ($opts.Congestion) { netsh int tcp set supplemental template=internet congestionprovider=cubic 2>&1|Out-Null; netsh int tcp set supplemental template=internetcustom congestionprovider=cubic 2>&1|Out-Null; Write-Log "CUBIC aktif" 'OK' }
        if ($opts.NetThrottle) { Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex' 0xFFFFFFFF -EA SilentlyContinue; Write-Log "NetThrottle kaldirildi" 'OK' }
        if ($opts.Nagle -or $opts.TCPNoDelay -or $opts.TCPACKFreq) {
            $tp = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
            if (Test-Path $tp) { Get-ChildItem $tp | ForEach-Object { $ip=$_.PSPath; if($opts.Nagle){Set-ItemProperty $ip 'TcpNoDelay' 1 -EA SilentlyContinue}; if($opts.TCPNoDelay){Set-ItemProperty $ip 'TcpDelAckTicks' 0 -EA SilentlyContinue}; if($opts.TCPACKFreq){Set-ItemProperty $ip 'TcpAckFrequency' 1 -EA SilentlyContinue} } }
            Write-Log "Nagle/NoDelay/ACKFreq optimize edildi" 'OK'
        }
        # NIC Adapter tweaks
        if ($opts.FlowCtrl -or $opts.IntMod -or $opts.RSS -or $opts.GreenEth -or $opts.GigaLite -or $opts.AdaptInter) {
            $nicAdapters = Get-NetAdapter -Physical -EA SilentlyContinue | Where-Object { $_.Status -eq 'Up' }
            foreach ($nic in $nicAdapters) {
                $nicProps = Get-NetAdapterAdvancedProperty -Name $nic.Name -EA SilentlyContinue
                function Set-NicP([string]$kw,[string]$val){ $p=$nicProps|Where-Object{$_.DisplayName -match $kw}|Select-Object -First 1; if($p){try{Set-NetAdapterAdvancedProperty -Name $nic.Name -DisplayName $p.DisplayName -DisplayValue $val -EA SilentlyContinue; Write-Log "  $($p.DisplayName)=$val" 'OK'}catch{}} }
                if ($opts.FlowCtrl)  { Set-NicP 'Flow Control' 'Disabled' }
                if ($opts.IntMod)    { Set-NicP 'Interrupt Moderation' 'Adaptive' }
                if ($opts.GreenEth)  { Set-NicP 'Green Ethernet' 'Disabled'; Set-NicP 'Energy-Efficient Ethernet' 'Disabled'; Set-NicP 'EEE' 'Disabled' }
                if ($opts.GigaLite)  { Set-NicP 'Giga Lite' 'Disabled' }
                if ($opts.AdaptInter){ Set-NicP 'Adaptive Inter-Frame Spacing' 'Disabled'; Set-NicP 'Interrupt Moderation Rate' '3' }
                if ($opts.RSS) { try { Enable-NetAdapterRss -Name $nic.Name -EA SilentlyContinue; Write-Log "  RSS etkin: $($nic.Name)" 'OK' } catch {} }
            }
        }
        if ($opts.DNSPrefetch) {
            $dc='HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters'
            if(-not(Test-Path $dc)){New-Item $dc -Force|Out-Null}
            Set-ItemProperty $dc 'EnableDnsCache' 1 -Type DWord -EA SilentlyContinue
            Set-ItemProperty $dc 'MaxCacheTtl' 3600 -Type DWord -EA SilentlyContinue
            Set-ItemProperty $dc 'MaxNegativeCacheTtl' 0 -Type DWord -EA SilentlyContinue
            Set-ItemProperty $dc 'CacheHashTableBucketSize' 1 -Type DWord -EA SilentlyContinue
            Set-ItemProperty $dc 'CacheHashTableSize' 384 -Type DWord -EA SilentlyContinue
            Write-Log "DNS Cache optimizasyonu (MaxTTL=3600)" 'OK'
        }
        if ($opts.LLMNR) { $dn='HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'; if(-not(Test-Path $dn)){New-Item $dn -Force|Out-Null}; Set-ItemProperty $dn 'EnableMulticast' 0 -EA SilentlyContinue; Write-Log "LLMNR disabled" 'OK' }
        if ($opts.MDNS)  { Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters' 'EnableMDNS' 0 -EA SilentlyContinue; Write-Log "mDNS kapatildi" 'OK' }
        Write-Log "--- 2/6 Network TAMAM ---" 'OK'

        # ── 3. KERNEL & INPUT ──
        Write-Log "--- 3/6 Kernel & Input ---" 'RUN'
        $opts = $allKernOpts
        # Güvenlik mitigasyonları
        if ($opts.VBS)       { $dg='HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'; Set-ItemProperty $dg 'EnableVirtualizationBasedSecurity' 0 -EA SilentlyContinue; Set-ItemProperty $dg 'RequirePlatformSecurityFeatures' 0 -EA SilentlyContinue; Write-Log "VBS disabled (restart gerekli)" 'WARN' }
        if ($opts.DMAProtect){ Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'EnableKernelDmaProtection' 0 -EA SilentlyContinue; Write-Log "DMA Protection disabled" 'WARN' }
        if ($opts.Spectre)   { $fp='HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'; Set-ItemProperty $fp 'FeatureSettingsOverride' 3 -Type DWord -EA SilentlyContinue; Set-ItemProperty $fp 'FeatureSettingsOverrideMask' 3 -Type DWord -EA SilentlyContinue; Write-Log "Spectre/Meltdown disabled" 'WARN' }
        if ($opts.HVCI)      { $ci='HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity'; if(-not(Test-Path $ci)){New-Item $ci -Force|Out-Null}; Set-ItemProperty $ci 'Enabled' 0 -EA SilentlyContinue; Write-Log "HVCI disabled" 'WARN' }
        if ($opts.CFG) {
            $kp='HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel'
            $co=(Get-ItemProperty $kp -EA SilentlyContinue).MitigationOptions; if($co -eq $null){$co=[int64]0}
            Set-ItemProperty $kp 'MitigationOptions' ([int64]$co -bor [int64]0x200) -Type QWord -EA SilentlyContinue
            Write-Log "CFG disabled" 'WARN'
        }
        # Bellek ve input
        if ($opts.MouseBuf)    { Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\mouclass\Parameters' 'MouseDataQueueSize' 16 -EA SilentlyContinue; Write-Log "Mouse buffer=16" 'OK' }
        if ($opts.KbBuf)       { Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\kbdclass\Parameters' 'KeyboardDataQueueSize' 16 -EA SilentlyContinue; Write-Log "Keyboard buffer=16" 'OK' }
        if ($opts.MouseAccel)  { $m='HKCU:\Control Panel\Mouse'; Set-ItemProperty $m 'MouseSpeed' '0' -EA SilentlyContinue; Set-ItemProperty $m 'MouseThreshold1' '0' -EA SilentlyContinue; Set-ItemProperty $m 'MouseThreshold2' '0' -EA SilentlyContinue; Write-Log "Mouse accel kapali" 'OK' }
        if ($opts.MouseSmooth) {
            $cpMouse='HKCU:\Control Panel\Mouse'
            Set-ItemProperty $cpMouse 'SmoothMouseXCurve' ([byte[]](0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xC0,0xCC,0x0C,0x00,0x00,0x00,0x00,0x00,0x80,0x99,0x19,0x00,0x00,0x00,0x00,0x00,0x40,0x66,0x26,0x00,0x00,0x00,0x00,0x00,0x00,0x33,0x33,0x00,0x00,0x00,0x00,0x00)) -EA SilentlyContinue
            Set-ItemProperty $cpMouse 'SmoothMouseYCurve' ([byte[]](0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x38,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x70,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xA8,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xE0,0x00,0x00,0x00,0x00,0x00)) -EA SilentlyContinue
            Write-Log "Mouse smoothing disabled (MarkC)" 'OK'
        }
        if ($opts.RawInput) {
            Set-ItemProperty 'HKCU:\Control Panel\Mouse' 'MouseSensitivity' '10' -EA SilentlyContinue
            $hp='HKLM:\SYSTEM\CurrentControlSet\Services\HidUsb\Parameters'; if(-not(Test-Path $hp)){New-Item $hp -Force|Out-Null}; Set-ItemProperty $hp 'WaitWakeEnabled' 0 -Type DWord -EA SilentlyContinue
            $cp='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\csrss.exe\PerfOptions'; if(-not(Test-Path $cp)){New-Item $cp -Force|Out-Null}; Set-ItemProperty $cp 'CpuPriorityClass' 4 -Type DWord -EA SilentlyContinue; Set-ItemProperty $cp 'IoPriority' 3 -Type DWord -EA SilentlyContinue
            Write-Log "Raw Input: 1:1 hassasiyet, HID sleep=0, csrss yuksek oncelik" 'OK'
        }
        if ($opts.ContMem)     { $dx='HKLM:\SOFTWARE\Microsoft\DirectX'; if(-not(Test-Path $dx)){New-Item $dx -Force|Out-Null}; Set-ItemProperty $dx 'D3D12_ENABLE_UNSAFE_COMMAND_BUFFER_REUSE' 1 -EA SilentlyContinue; Write-Log "DX ContMem aktif" 'OK' }
        if ($opts.LargePages)  { Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'LargePageMinimum' 0 -Type DWord -EA SilentlyContinue; Write-Log "LargePageMinimum=0 (restart gerekli)" 'OK' }
        if ($opts.PagingFiles) { Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'PagingFiles' 'c:\pagefile.sys 0 0' -EA SilentlyContinue; Write-Log "PageFile: sistem yonetimi (otomatik)" 'OK' }
        # SecondLevelDataCache KALDIRILDI — XP-era plasebo
        Write-Log "--- 3/6 Kernel TAMAM ---" 'OK'

        # ── 4. GPU & MSI ──
        Write-Log "--- 4/6 GPU & MSI ---" 'RUN'
        $opts = $allGpuOpts
        $gpuCls='HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
        $nvmeCls='HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e97b-e325-11ce-bfc1-08002be10318}'
        $nicCls='HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}'
        $msiN=0
        foreach ($clsPath in @($gpuCls,$nvmeCls,$nicCls)) {
            $doThis = ($clsPath -eq $gpuCls -and $opts.MSIGPU) -or ($clsPath -eq $nvmeCls -and $opts.MSINVMe) -or ($clsPath -eq $nicCls -and $opts.MSINIC)
            if ($doThis -and (Test-Path $clsPath)) {
                Get-ChildItem $clsPath -EA SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' } | ForEach-Object {
                    $dd=(Get-ItemProperty $_.PSPath 'DriverDesc' -EA SilentlyContinue).DriverDesc
                    if ($dd -and $dd -notmatch '(?i)Microsoft Basic|Remote Desktop|Virtual|WAN Miniport|Bluetooth') {
                        $ip="$($_.PSPath)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
                        if(-not(Test-Path $ip)){try{New-Item $ip -Force -EA SilentlyContinue|Out-Null}catch{}}
                        Set-ItemProperty $ip 'MSISupported' 1 -Type DWord -EA SilentlyContinue
                        if ($opts.MSIPRIO) { $ap="$($_.PSPath)\Device Parameters\Interrupt Management\Affinity Policy"; if(-not(Test-Path $ap)){try{New-Item $ap -Force -EA SilentlyContinue|Out-Null}catch{}}; Set-ItemProperty $ap 'DevicePriority' 3 -Type DWord -EA SilentlyContinue }
                        Write-Log "  MSI: $dd" 'OK'; $msiN++
                    }
                }
            }
        }
        if ($msiN -gt 0) { Write-Log "MSI Mode: $msiN aygit aktif. Restart gerekli." 'OK' }
        # NVIDIA tweaks
        if ($opts.NvPrerender -or $opts.NvPower -or $opts.NvSync -or $opts.NvFastSync -or $opts.NvShaderCache -or $opts.NvTexFilter) {
            Get-ChildItem $gpuCls -EA SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' } | ForEach-Object {
                $dd = (Get-ItemProperty $_.PSPath 'DriverDesc' -EA SilentlyContinue).DriverDesc
                $isNvPrimary = $dd -match 'NVIDIA' -and ($HW.GpuName -eq '' -or $dd -like "*$($HW.GpuName -replace '^NVIDIA\s*','')*" -or $HW.GpuName -like "*$dd*")
                if ($isNvPrimary) {
                    if($opts.NvPrerender){Set-ItemProperty $_.PSPath 'RMDxgkNDDSwapChainAcquireToHwCursorLatency' 0 -EA SilentlyContinue}
                    if($opts.NvPower){Set-ItemProperty $_.PSPath 'DisableDynamicPstate' 1 -EA SilentlyContinue}
                    if($opts.NvSync){Set-ItemProperty $_.PSPath 'PerfLevelSrc' 0x2222 -Type DWord -EA SilentlyContinue}
                    if($opts.NvFastSync){Set-ItemProperty $_.PSPath 'RMVSyncDelayFrameCount' 0 -EA SilentlyContinue}
                    if($opts.NvShaderCache){Set-ItemProperty $_.PSPath 'DisableShaderDiskCache' 0 -EA SilentlyContinue}
                    if($opts.NvTexFilter){Set-ItemProperty $_.PSPath 'TextureQualityOption' 3 -EA SilentlyContinue}
                    Write-Log "NVIDIA tweaks uygulandı" 'OK'
                }
            }
        }
        # AMD tweaks
        if ($opts.AMDAntiLag -or $opts.AMDChill -or $opts.AMDPower) {
            Get-ChildItem $gpuCls -EA SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' } | ForEach-Object {
                $dd = (Get-ItemProperty $_.PSPath 'DriverDesc' -EA SilentlyContinue).DriverDesc
                $isAmdPrimary = $dd -match 'AMD|Radeon|ATI' -and ($HW.GpuName -eq '' -or $dd -like "*$($HW.GpuName -replace '^AMD\s*','')*" -or $HW.GpuName -like "*$dd*")
                if ($isAmdPrimary) {
                    if($opts.AMDAntiLag){Set-ItemProperty $_.PSPath 'KMD_EnableAntiLag' 1 -EA SilentlyContinue}
                    if($opts.AMDChill){Set-ItemProperty $_.PSPath 'KMD_EnableChill' 0 -EA SilentlyContinue}
                    if($opts.AMDPower){Set-ItemProperty $_.PSPath 'KMD_FRTEnabled' 0 -EA SilentlyContinue; Set-ItemProperty $_.PSPath 'EnableUlps' 0 -EA SilentlyContinue}
                    Write-Log "AMD tweaks uygulandı" 'OK'
                }
            }
        }
        Write-Log "--- 4/6 GPU TAMAM ---" 'OK'

        # ── 5. PRIVACY ──
        Write-Log "--- 5/6 Privacy ---" 'RUN'
        $opts = $allPrivOpts
        if ($opts.DiagTrack)    { Stop-Service 'DiagTrack' -Force -EA SilentlyContinue; Set-Service 'DiagTrack' -StartupType Disabled -EA SilentlyContinue; Write-Log "DiagTrack kapatildi" 'OK' }
        if ($opts.DMWApp)       { Stop-Service 'dmwappushservice' -Force -EA SilentlyContinue; Set-Service 'dmwappushservice' -StartupType Disabled -EA SilentlyContinue; Write-Log "dmwappushservice kapatildi" 'OK' }
        if ($opts.TelemetryReg) { $tp='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; if(-not(Test-Path $tp)){New-Item $tp -Force|Out-Null}; Set-ItemProperty $tp 'AllowTelemetry' 0 -EA SilentlyContinue; Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' 'AllowTelemetry' 0 -EA SilentlyContinue; Write-Log "Telemetry=0" 'OK' }
        if ($opts.AppCompat)    { $sc='HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat'; if(-not(Test-Path $sc)){New-Item $sc -Force|Out-Null}; Set-ItemProperty $sc 'DisableInventory' 1 -EA SilentlyContinue; Set-ItemProperty $sc 'DisableProgramTelemetry' 1 -EA SilentlyContinue; Write-Log "AppCompat telemetri kapatildi" 'OK' }
        if ($opts.ErrReport)    { Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting' 'Disabled' 1 -EA SilentlyContinue; Set-Service 'WerSvc' -StartupType Disabled -EA SilentlyContinue; Write-Log "WER kapatildi" 'OK' }
        if ($opts.ActHist)      { $ah='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; if(-not(Test-Path $ah)){New-Item $ah -Force|Out-Null}; Set-ItemProperty $ah 'EnableActivityFeed' 0 -EA SilentlyContinue; Set-ItemProperty $ah 'PublishUserActivities' 0 -EA SilentlyContinue; Write-Log "Activity History kapatildi" 'OK' }
        if ($opts.Cortana)      { $cp='HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; if(-not(Test-Path $cp)){New-Item $cp -Force|Out-Null}; Set-ItemProperty $cp 'AllowCortana' 0 -EA SilentlyContinue; Write-Log "Cortana kapatildi" 'OK' }
        if ($opts.AdID)         { $ap='HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo'; if(-not(Test-Path $ap)){New-Item $ap -Force|Out-Null}; Set-ItemProperty $ap 'Enabled' 0 -EA SilentlyContinue; Write-Log "AdvertisingID kapatildi" 'OK' }
        if ($opts.Tailored)     { $te='HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy'; if(-not(Test-Path $te)){New-Item $te -Force|Out-Null}; Set-ItemProperty $te 'TailoredExperiencesWithDiagnosticDataEnabled' 0 -EA SilentlyContinue; Write-Log "Tailored Experiences kapatildi" 'OK' }
        if ($opts.Typing) {
            $ink='HKCU:\Software\Microsoft\InputPersonalization'; if(-not(Test-Path $ink)){New-Item $ink -Force|Out-Null}
            Set-ItemProperty $ink 'RestrictImplicitInkCollection' 1 -EA SilentlyContinue
            Set-ItemProperty $ink 'RestrictImplicitTextCollection' 1 -EA SilentlyContinue
            $it="$ink\TrainedDataStore"; if(-not(Test-Path $it)){New-Item $it -Force|Out-Null}; Set-ItemProperty $it 'HarvestContacts' 0 -EA SilentlyContinue
            Write-Log "Inking & Typing Personalization kapatildi" 'OK'
        }
        if ($opts.CEIP) {
            $sq='HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows'; if(-not(Test-Path $sq)){New-Item $sq -Force|Out-Null}; Set-ItemProperty $sq 'CEIPEnable' 0 -EA SilentlyContinue
            $sq2='HKLM:\SOFTWARE\Microsoft\SQMClient\Windows'; if(-not(Test-Path $sq2)){New-Item $sq2 -Force|Out-Null}; Set-ItemProperty $sq2 'CEIPEnable' 0 -EA SilentlyContinue
            Write-Log "CEIP kapatildi" 'OK'
        }
        if ($opts.BingSearch)   { Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0 -EA SilentlyContinue; Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'CortanaConsent' 0 -EA SilentlyContinue; Write-Log "Bing arama kapatildi" 'OK' }
        if ($opts.SuggestApps)  { Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SystemPaneSuggestionsEnabled' 0 -EA SilentlyContinue; Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SilentInstalledAppsEnabled' 0 -EA SilentlyContinue; Write-Log "Suggested Apps kapatildi" 'OK' }
        if ($opts.ConsumerExp)  { $ce='HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; if(-not(Test-Path $ce)){New-Item $ce -Force|Out-Null}; Set-ItemProperty $ce 'DisableWindowsConsumerFeatures' 1 -EA SilentlyContinue; Write-Log "Consumer Experience kapatildi" 'OK' }
        if ($opts.XboxSvc)      { @('XblAuthManager','XblGameSave','XboxNetApiSvc','XboxGipSvc') | ForEach-Object { Set-Service $_ -StartupType Disabled -EA SilentlyContinue; Stop-Service $_ -Force -EA SilentlyContinue }; Write-Log "Xbox servisleri kapatildi" 'OK' }
        if ($opts.OneDrive) {
            Write-Log "OneDrive kaldiriliyor..." 'RUN'
            taskkill /f /im OneDrive.exe 2>&1 | Out-Null
            @("$env:SystemRoot\SysWOW64\OneDriveSetup.exe","$env:SystemRoot\System32\OneDriveSetup.exe","$env:LocalAppData\Microsoft\OneDrive\OneDriveSetup.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1 | ForEach-Object {
                Start-Process $_ -ArgumentList '/uninstall' -Wait -EA SilentlyContinue
                Write-Log "OneDrive kaldirildi: $_" 'OK'
            }
        }
        Write-Log "--- 5/6 Privacy TAMAM ---" 'OK'

        # ── 6. WINDOWS TWEAKS ──
        Write-Log "--- 6/6 Windows Tweaks ---" 'RUN'
        $opts = $allWinOpts
        if ($opts.Animations) {
            Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 2 -EA SilentlyContinue
            Set-ItemProperty 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate' '0' -EA SilentlyContinue
            $desk='HKCU:\Control Panel\Desktop'
            Set-ItemProperty $desk 'DragFullWindows' '0' -EA SilentlyContinue
            Set-ItemProperty $desk 'FontSmoothing' 2 -EA SilentlyContinue
            Write-Log "Animasyonlar kapatildi" 'OK'
        }
        if ($opts.TaskbarAnims) { Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAnimations' 0 -EA SilentlyContinue; Write-Log "Taskbar animasyon kapali" 'OK' }
        if ($opts.JPEGQuality)  { Set-ItemProperty 'HKCU:\Control Panel\Desktop' 'JPEGImportQuality' 100 -EA SilentlyContinue; Write-Log "JPEG kalite=100" 'OK' }
        if ($opts.MenuDelay)    { Set-ItemProperty 'HKCU:\Control Panel\Desktop' 'MenuShowDelay' '0' -EA SilentlyContinue; Write-Log "MenuDelay=0" 'OK' }
        if ($opts.BSODDetail)   { $cc='HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl'; Set-ItemProperty $cc 'AutoReboot' 0 -EA SilentlyContinue; Set-ItemProperty $cc 'DisplayParameters' 1 -EA SilentlyContinue; Write-Log "BSOD detay aktif" 'OK' }
        if ($opts.LaunchTo)     { Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'LaunchTo' 1 -EA SilentlyContinue; Write-Log "Explorer This PC'den acilir" 'OK' }
        if ($opts.NumLock)      { Set-ItemProperty 'HKCU:\Control Panel\Keyboard' 'InitialKeyboardIndicators' '2' -EA SilentlyContinue; Write-Log "NumLock baslangicta acik" 'OK' }
        if ($opts.HideExt)      { Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'HideFileExt' 0 -EA SilentlyContinue; Write-Log "Uzantilar gorunur" 'OK' }
        if ($opts.LongPaths)    { Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'LongPathsEnabled' 1 -EA SilentlyContinue; Write-Log "Long paths aktif" 'OK' }
        if ($opts.Transparency) { $tr='HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; if(-not(Test-Path $tr)){New-Item $tr -Force|Out-Null}; Set-ItemProperty $tr 'EnableTransparency' 0 -EA SilentlyContinue; Write-Log "Seffaflik kapatildi" 'OK' }
        if ($opts.ContextMenu)  { $cmd='HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'; if(-not(Test-Path $cmd)){New-Item $cmd -Force|Out-Null}; Set-ItemProperty $cmd '(default)' '' -EA SilentlyContinue; Write-Log "Eski sag tik menusu aktif" 'OK' }
        if ($opts.DarkMode)     { Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'AppsUseLightTheme' 0 -EA SilentlyContinue; Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'SystemUsesLightTheme' 0 -EA SilentlyContinue; Write-Log "Dark mode aktif" 'OK' }
        if ($opts.CrashDumpFull){ Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' 'CrashDumpEnabled' 1 -Type DWord -EA SilentlyContinue; Write-Log "Tam bellek dump aktif" 'OK' }
        if ($opts.EventLogSize) {
            @('Application','System','Security') | ForEach-Object { wevtutil sl $_ /ms:104857600 2>&1 | Out-Null }
            Write-Log "Event Log boyutu 100MB yapildi" 'OK'
        }
        # Explorer yeniden baslatma (sadece UI tweakler seçiliyse)
        $uiChanged = $opts.Animations -or $opts.TaskbarAnims -or $opts.ContextMenu -or $opts.DarkMode -or $opts.Transparency -or $opts.LaunchTo -or $opts.HideExt -or $opts.MenuDelay
        if ($uiChanged) {
            Stop-Process -Name explorer -Force -EA SilentlyContinue
            Start-Sleep -Milliseconds 600
            Start-Process explorer
            Write-Log "Explorer yeniden baslatildi" 'OK'
        }
        Write-Log "--- 6/6 Windows Tweaks TAMAM ---" 'OK'
        Write-Log "=== TUM OPTIMIZASYONLAR TAMAMLANDI ===" 'OK'
    }
})

# Restore Backup
$BtnRestoreBackup.Add_Click({
    $ofd = [System.Windows.Forms.OpenFileDialog]::new()
    $ofd.InitialDirectory = $global:BackupPath
    $ofd.Filter = 'Registry Backup|*.reg'
    $ofd.Title  = 'Yedek Sec ve Geri Yukle'
    if ($ofd.ShowDialog() -eq 'OK') {
        $res = [System.Windows.Forms.MessageBox]::Show(
            "Su yedek geri yuklenecek:`n$($ofd.FileName)`n`nDevam edilsin mi?",
            "Geri Yukleme Onayi",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning)
        if ($res -eq 'Yes') {
            try {
                reg import $ofd.FileName 2>&1 | Out-Null
                Write-Log "Yedek geri yuklendi: $($ofd.FileName)" 'OK'
                Set-Status "Geri yukleme tamamlandi."
            } catch {
                Write-Log "Geri yukleme hatasi: $_" 'ERROR'
            }
        }
    }
})

# ─── TERMINAL CONTROLS ────────────────────────────────────────────────────────
$BtnClearLog.Add_Click({
    $Terminal.Clear()
})

$BtnSaveLog.Add_Click({
    $sfd = [System.Windows.Forms.SaveFileDialog]::new()
    $sfd.Filter   = 'Text Log|*.txt'
    $sfd.FileName = "LivnTools_Log_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    if ($sfd.ShowDialog() -eq 'OK') {
        try {
            $Terminal.Text | Out-File $sfd.FileName -Encoding UTF8
            Write-Log "Log kaydedildi: $($sfd.FileName)" 'OK'
        } catch {
            Write-Log "Log kaydedilemedi: $_" 'ERROR'
        }
    }
})

# ─── STARTUP ──────────────────────────────────────────────────────────────────
# Init terminal
Write-Log "Livn Tools v3.5 baslatildi." 'OK'
Write-Log "Hosgeldin $env:USERNAME @ $env:COMPUTERNAME" 'INFO'
Write-Log "─────────────────────────────────────────" 'INFO'
Write-Log "DONANIM TARAMASI:" 'INFO'
Write-Log ("  CPU : {0} ({1}C/{2}T)" -f $global:HW.CpuName, $global:HW.CpuCores, $global:HW.CpuThreads) 'INFO'
Write-Log "  GPU : $($global:HW.GpuName) ($($global:HW.GpuVRAM_MB) MB)" 'INFO'
Write-Log "  RAM : $($global:HW.RamGB) GB" 'INFO'
if ($global:HW.NicName) { Write-Log "  NIC : $($global:HW.NicName)" 'INFO' }
Write-Log "─────────────────────────────────────────" 'INFO'
Write-Log "UYGULAMA TESPITI ($($global:_RegCache.Count) registry kaydi tarandi):" 'INFO'

Write-Log "Yedek klasoru: $global:BackupPath" 'INFO'
Write-Log "Log dosyasi: $global:LogFile" 'INFO'
Write-Log "─────────────────────────────────────────" 'INFO'

# USB ilk tarama (DriveInfo ile — hafif)
try {
    $initUsb = @([System.IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Removable' -and $_.IsReady })
    $global:_UsbLastIds = ($initUsb | ForEach-Object { $_.Name }) -join ','
    if ($initUsb.Count -gt 0) {
        $TxtUsbCount.Text       = "$($initUsb.Count) Cihaz Bagli"
        $TxtUsbCount.Foreground = [System.Windows.Media.Brushes]::Orange
        Write-Log "USB Uyari: $($initUsb.Count) adet USB depolama aygiti bagli." 'WARN'
        $initUsb | ForEach-Object { Write-Log "  - $($_.Name) [$($_.VolumeLabel)]" 'WARN' }
    } else {
        $TxtUsbCount.Text       = 'Yok'
        $TxtUsbCount.Foreground = [System.Windows.Media.Brushes]::Gray
    }
} catch { $global:_UsbLastIds = '' }

# ─── DINAMIK CHECKBOX AYARI (Registry tabanlı uygulama tespiti) ───────────────
# Her checkbox: kurulu ise IsChecked=True+IsEnabled=True, degilse False+gri
$appCheckMap = @(
    # Tarayicilar
    @{ Check='ChkChromeCache';   Key='Chrome'         }
    @{ Check='ChkEdgeCache';     Key='Edge'            }
    @{ Check='ChkFirefoxCache';  Key='Firefox'         }
    @{ Check='ChkBraveCache';    Key='Brave'           }
    @{ Check='ChkOperaCache';    Key='Opera'           }
    @{ Check='ChkVivaldiCache';  Key='Vivaldi'         }
    @{ Check='ChkTorCache';      Key='Tor'             }
    # Iletisim / Sosyal
    @{ Check='ChkDiscordCache';  Key='Discord'         }
    @{ Check='ChkTelegramCache'; Key='Telegram'        }
    @{ Check='ChkWhatsAppCache'; Key='WhatsApp'        }
    @{ Check='ChkSlackCache';    Key='Slack'           }
    @{ Check='ChkZoomCache';     Key='Zoom'            }
    @{ Check='ChkTeamsCache';    Key='Teams'           }
    @{ Check='ChkSkypeCache';    Key='Skype'           }
    @{ Check='ChkSpotifyCache';  Key='Spotify'         }
    # Oyun Launcher
    @{ Check='ChkSteamCache';    Key='Steam'           }
    @{ Check='ChkEpicCache';     Key='EpicGames'       }
    @{ Check='ChkGOGCache';      Key='GOGGalaxy'       }
    @{ Check='ChkUbisoftCache';  Key='UbisoftConnect'  }
    @{ Check='ChkEACache';       Key='EADesktop'       }
    @{ Check='ChkXboxCache';     Key='Xbox'            }
    @{ Check='ChkBnetCache';     Key='Battlenet'       }
    @{ Check='ChkRockstarCache'; Key='Rockstar'        }
    @{ Check='ChkRiotCache';     Key='Riot'            }
    @{ Check='ChkMinecraftCache';Key='Minecraft'       }
)
foreach ($entry in $appCheckMap) {
    $ctrl = $Window.FindName($entry.Check)
    if ($ctrl) {
        $installed = [bool]$global:AppInstalled[$entry.Key]
        $ctrl.IsChecked = $installed
        $ctrl.IsEnabled = $installed
        $ctrl.Opacity   = if ($installed) { 1.0 } else { 0.35 }
    }
}
# Opera GX de kurulu ise Opera kutusunu aktif et
if ($global:AppInstalled['OperaGX']) {
    $c = $Window.FindName('ChkOperaCache')
    if ($c) { $c.IsChecked = $true; $c.IsEnabled = $true; $c.Opacity = 1.0 }
}
Write-Log "Uygulama tespiti tamamlandi." 'OK'
# Tespit edilenleri logla
$detectedApps = ($appCheckMap | Where-Object { $global:AppInstalled[$_.Key] } | ForEach-Object { $_.Key }) -join ', '
if ($detectedApps) { Write-Log "  Tespit edilen: $detectedApps" 'OK' }
$notFound = ($appCheckMap | Where-Object { -not $global:AppInstalled[$_.Key] } | ForEach-Object { $_.Key }) -join ', '
if ($notFound) { Write-Log "  Kurulu degil (gri): $notFound" 'INFO' }
# Opera/OperaGX debug — hangi yolla algılandığını raporla
@('Opera','OperaGX') | ForEach-Object {
    $k = $_
    if ($global:AppInstalled[$k]) {
        Write-Log "  [DEBUG] $k kurulu olarak algilandi" 'INFO'
    }
}

# Select first nav item
$NavQuickClean.IsSelected = $true

# ─── DINAMIK DURUM TARAMASI (State Awareness) ─────────────────────────────────
# Optimizasyon checkbox'lari acilista sistemin mevcut durumunu yansitir.
# Zaten uygulanmis ayarlar yesil isaretlenir, uygulanmamis olanlar bos kalir.
Write-Log "Sistem durumu taraniyor (State Awareness)..." 'RUN'

# Yardimci: Registry degerini oku, beklenen degerle eslesirse $true don
# NOT: DWORD isaretsiz/isaretli farki icin her iki deger de Int64'e cast edilir
function Test-RegState([string]$path, [string]$name, $expected) {
    try {
        $val = (Get-ItemProperty -Path $path -Name $name -ErrorAction Stop).$name
        # Sayi karsilastirmasi — DWORD 0xFFFFFFFF = -1 sorununu cozer
        if ($expected -is [int] -or $expected -is [long] -or $expected -is [uint32]) {
            return ([long]$val -eq [long]$expected)
        }
        return ($val -eq $expected)
    } catch { return $false }
}

# Yardimci: NIC adapter ozelligini kontrol et (herhangi bir aktif NIC'de)
function Test-NicProp([string]$propName, [string]$expected) {
    try {
        $nics = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' }
        foreach ($nic in $nics) {
            $adv = Get-NetAdapterAdvancedProperty -Name $nic.Name -RegistryKeyword $propName -ErrorAction SilentlyContinue
            if ($adv -and $adv.DisplayValue -eq $expected) { return $true }
        }
        return $false
    } catch { return $false }
}

$stateMap = @(
    # ═══════════════════════════════════════════════════════════════════
    # PERFORMANCE
    # ═══════════════════════════════════════════════════════════════════
    @{ Chk='ChkHPET'; State={
        $bcd = bcdedit /enum '{current}' 2>&1 | Out-String
        $clockOff = ($bcd -match 'useplatformclock\s+No') -or ($bcd -notmatch 'useplatformclock')
        $dynOff   = $bcd -match 'disabledynamictick\s+Yes'
        return ($clockOff -and $dynOff)
    }}
    @{ Chk='ChkTimerRes';    State={ Test-RegState 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' 'GlobalTimerResolutionRequests' 1 } }
    @{ Chk='ChkCpuPriority'; State={ Test-RegState 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'SystemResponsiveness' 0 } }
    @{ Chk='ChkSysMain';     State={ (Get-Service 'SysMain' -EA SilentlyContinue).StartType -eq 'Disabled' } }
    @{ Chk='ChkWSearch';     State={ (Get-Service 'WSearch' -EA SilentlyContinue).StartType -eq 'Disabled' } }
    @{ Chk='ChkWUpdate';     State={ Test-RegState 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'AUOptions' 4 } }
    @{ Chk='ChkGameMode';    State={ Test-RegState 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1 } }
    @{ Chk='ChkHwAccel';     State={ Test-RegState 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2 } }

    # ═══════════════════════════════════════════════════════════════════
    # NETWORK
    # ═══════════════════════════════════════════════════════════════════
    # NetworkThrottlingIndex — DWORD 0xFFFFFFFF registry'de signed -1 olarak okunur
    @{ Chk='ChkNetThrottle'; State={
        try {
            $v = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex' -EA Stop).NetworkThrottlingIndex
            return ($v -eq -1 -or $v -eq 4294967295)
        } catch { return $false }
    }}
    @{ Chk='ChkDNSPrefetch'; State={ Test-RegState 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters' 'MaxCacheTtl' 3600 } }
    @{ Chk='ChkLLMNR';       State={ Test-RegState 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' 'EnableMulticast' 0 } }
    @{ Chk='ChkMDNS';        State={
        try {
            $v = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters' 'EnableMDNS' -EA Stop).EnableMDNS
            return ($v -eq 0 -or $v -eq '0')
        } catch { return $false }
    }}

    # Nagle / TCPNoDelay / ACKFreq — per-NIC interface registry kontrolu
    @{ Chk='ChkNagle'; State={
        try {
            $found = $false
            $base = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
            Get-ChildItem $base -EA SilentlyContinue | ForEach-Object {
                $nd = (Get-ItemProperty $_.PSPath 'TcpNoDelay' -EA SilentlyContinue).TcpNoDelay
                if ($nd -eq 1) { $found = $true }
            }
            return $found
        } catch { return $false }
    }}
    @{ Chk='ChkTCPNoDelay'; State={
        try {
            $found = $false
            $base = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
            Get-ChildItem $base -EA SilentlyContinue | ForEach-Object {
                $nd = (Get-ItemProperty $_.PSPath 'TcpNoDelay' -EA SilentlyContinue).TcpNoDelay
                if ($nd -eq 1) { $found = $true }
            }
            return $found
        } catch { return $false }
    }}
    @{ Chk='ChkTCPACKFreq'; State={
        try {
            $found = $false
            $base = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
            Get-ChildItem $base -EA SilentlyContinue | ForEach-Object {
                $af = (Get-ItemProperty $_.PSPath 'TcpAckFrequency' -EA SilentlyContinue).TcpAckFrequency
                if ($af -eq 1) { $found = $true }
            }
            return $found
        } catch { return $false }
    }}

    # NIC Adapter ozellikleri — aktif NIC'te kontrol
    @{ Chk='ChkRSS';        State={
        try {
            $nics = Get-NetAdapter -Physical -EA SilentlyContinue | Where-Object { $_.Status -eq 'Up' }
            foreach ($n in $nics) {
                # Yontem 1: Get-NetAdapterRss
                $rss = Get-NetAdapterRss -Name $n.Name -EA SilentlyContinue
                if ($null -ne $rss -and $rss.Enabled -eq $true) { return $true }
                # Yontem 2: Registry keyword
                $adv = Get-NetAdapterAdvancedProperty -Name $n.Name -EA SilentlyContinue | Where-Object { $_.RegistryKeyword -match 'RSS' }
                if ($adv -and ($adv.RegistryValue -eq 1 -or $adv.DisplayValue -eq 'Enabled')) { return $true }
                # Yontem 3: netsh
                $out = netsh int tcp show global 2>&1 | Out-String
                if ($out -match 'Receive-Side Scaling State\s*:\s*enabled') { return $true }
            }
            return $false
        } catch { return $false }
    }}
    @{ Chk='ChkFlowCtrl';   State={ Test-NicProp '*FlowControl' 'Disabled' } }
    @{ Chk='ChkIntMod';     State={
        try {
            $nics = Get-NetAdapter -Physical -EA SilentlyContinue | Where-Object { $_.Status -eq 'Up' }
            foreach ($n in $nics) {
                $adv = Get-NetAdapterAdvancedProperty -Name $n.Name -ErrorAction SilentlyContinue | Where-Object { $_.RegistryKeyword -match 'InterruptModeration$' }
                if ($adv -and $adv.DisplayValue -match 'Adaptive|Enabled') { return $true }
            }
            return $false
        } catch { return $false }
    }}
    @{ Chk='ChkGreenEth';   State={
        try {
            $nics = Get-NetAdapter -Physical -EA SilentlyContinue | Where-Object { $_.Status -eq 'Up' }
            foreach ($n in $nics) {
                $adv = Get-NetAdapterAdvancedProperty -Name $n.Name -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match 'Green Ethernet|Energy.Efficient|EEE' }
                if ($adv) {
                    foreach ($a in $adv) { if ($a.DisplayValue -eq 'Disabled') { return $true } }
                    return $false  # Property var ama Disabled degil
                }
                # Property yoksa = bu NIC desteklemiyor, sorun yok
            }
            return $true  # Hicbir NIC'te bu property yok = not applicable = OK
        } catch { return $false }
    }}
    @{ Chk='ChkGigaLite';   State={
        try {
            $nics = Get-NetAdapter -Physical -EA SilentlyContinue | Where-Object { $_.Status -eq 'Up' }
            foreach ($n in $nics) {
                $adv = Get-NetAdapterAdvancedProperty -Name $n.Name -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match 'Giga Lite' }
                if ($adv -and $adv.DisplayValue -eq 'Disabled') { return $true }
                if (-not $adv) { return $true }  # NIC bu ozellige sahip degil = sorun yok
            }
            return $false
        } catch { return $false }
    }}
    @{ Chk='ChkAdaptInter'; State={
        try {
            $nics = Get-NetAdapter -Physical -EA SilentlyContinue | Where-Object { $_.Status -eq 'Up' }
            foreach ($n in $nics) {
                $adv = Get-NetAdapterAdvancedProperty -Name $n.Name -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match 'Adaptive Inter.Frame' }
                if ($adv -and $adv.DisplayValue -eq 'Disabled') { return $true }
                if (-not $adv) { return $true }  # NIC bu ozellige sahip degil
            }
            return $false
        } catch { return $false }
    }}

    # ═══════════════════════════════════════════════════════════════════
    # KERNEL & INPUT
    # ═══════════════════════════════════════════════════════════════════
    @{ Chk='ChkVBS';          State={ Test-RegState 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'EnableVirtualizationBasedSecurity' 0 } }
    @{ Chk='ChkDMAProtect';   State={ Test-RegState 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'EnableKernelDmaProtection' 0 } }
    @{ Chk='ChkSpectre';      State={ Test-RegState 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'FeatureSettingsOverride' 3 } }
    @{ Chk='ChkCFG';          State={
        try {
            $v = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' 'MitigationOptions' -EA Stop).MitigationOptions
            return (([long]$v -band [long]0x200) -ne 0)
        } catch { return $false }
    }}
    @{ Chk='ChkHVCI';         State={ Test-RegState 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled' 0 } }
    @{ Chk='ChkLargePages';   State={ Test-RegState 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'LargePageMinimum' 0 } }
    @{ Chk='ChkContMem';      State={ Test-RegState 'HKLM:\SOFTWARE\Microsoft\DirectX' 'D3D12_ENABLE_UNSAFE_COMMAND_BUFFER_REUSE' 1 } }
    @{ Chk='ChkMouseBuffer';  State={ Test-RegState 'HKLM:\SYSTEM\CurrentControlSet\Services\mouclass\Parameters' 'MouseDataQueueSize' 16 } }
    @{ Chk='ChkKbBuffer';     State={ Test-RegState 'HKLM:\SYSTEM\CurrentControlSet\Services\kbdclass\Parameters' 'KeyboardDataQueueSize' 16 } }
    @{ Chk='ChkRawInput';     State={ Test-RegState 'HKCU:\Control Panel\Mouse' 'MouseSensitivity' '10' } }
    @{ Chk='ChkMouseAccel';   State={ Test-RegState 'HKCU:\Control Panel\Mouse' 'MouseSpeed' '0' } }
    @{ Chk='ChkMouseSmooth';  State={
        try {
            $curve = (Get-ItemProperty 'HKCU:\Control Panel\Mouse' 'SmoothMouseXCurve' -EA Stop).SmoothMouseXCurve
            # MarkC fix ilk byte'i 0x00, 9. byte 0xC0 — varsayilan degil
            return ($curve -is [byte[]] -and $curve.Length -ge 10 -and $curve[8] -eq 0xC0)
        } catch { return $false }
    }}
    @{ Chk='ChkPagingFiles';  State={
        try {
            $pf = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'PagingFiles' -EA Stop).PagingFiles
            # Deger bos degilse ve 'pagefile' iceriyorsa ayarlanmis
            return ($pf -ne $null -and ($pf -join '') -match 'pagefile')
        } catch { return $false }
    }}

    # ═══════════════════════════════════════════════════════════════════
    # GPU & MSI — class registry tarama
    # ═══════════════════════════════════════════════════════════════════
    @{ Chk='ChkMSIGPU'; State={
        $cls = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
        if (-not (Test-Path $cls)) { return $false }
        $found = $false
        Get-ChildItem $cls -EA SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' } | ForEach-Object {
            $msi = "$($_.PSPath)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
            if ((Get-ItemProperty $msi 'MSISupported' -EA SilentlyContinue).MSISupported -eq 1) { $found = $true }
        }
        return $found
    }}
    @{ Chk='ChkMSINVMe'; State={
        $cls = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e97b-e325-11ce-bfc1-08002be10318}'
        if (-not (Test-Path $cls)) { return $false }
        $found = $false
        Get-ChildItem $cls -EA SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' } | ForEach-Object {
            $msi = "$($_.PSPath)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
            if ((Get-ItemProperty $msi 'MSISupported' -EA SilentlyContinue).MSISupported -eq 1) { $found = $true }
        }
        return $found
    }}
    @{ Chk='ChkMSINIC'; State={
        $cls = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}'
        if (-not (Test-Path $cls)) { return $false }
        $found = $false
        Get-ChildItem $cls -EA SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' } | ForEach-Object {
            $dd = (Get-ItemProperty $_.PSPath 'DriverDesc' -EA SilentlyContinue).DriverDesc
            if ($dd -and $dd -notmatch '(?i)Virtual|WAN Miniport|Bluetooth') {
                $msi = "$($_.PSPath)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
                if ((Get-ItemProperty $msi 'MSISupported' -EA SilentlyContinue).MSISupported -eq 1) { $found = $true }
            }
        }
        return $found
    }}
    @{ Chk='ChkMSIPrio'; State={
        $cls = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
        if (-not (Test-Path $cls)) { return $false }
        $found = $false
        Get-ChildItem $cls -EA SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' } | ForEach-Object {
            $ap = "$($_.PSPath)\Device Parameters\Interrupt Management\Affinity Policy"
            if ((Get-ItemProperty $ap 'DevicePriority' -EA SilentlyContinue).DevicePriority -eq 3) { $found = $true }
        }
        return $found
    }}
    # NVIDIA tweaks — GPU class'ta per-key registry degerleri kontrol
    # Helper: NVIDIA GPU subkey'de belirli bir registry degerini kontrol et
    @{ Chk='ChkNvPrerender'; State={
        $cls = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
        if (-not (Test-Path $cls)) { return $false }
        $found = $false
        Get-ChildItem $cls -EA SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' } | ForEach-Object {
            $dd = (Get-ItemProperty $_.PSPath 'DriverDesc' -EA SilentlyContinue).DriverDesc
            if ($dd -match 'NVIDIA') {
                $v = (Get-ItemProperty $_.PSPath 'RMDxgkNDDSwapChainAcquireToHwCursorLatency' -EA SilentlyContinue).RMDxgkNDDSwapChainAcquireToHwCursorLatency
                if ($v -eq 0) { $found = $true }
            }
        }
        return $found
    }}
    @{ Chk='ChkNvPower'; State={
        $cls = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
        if (-not (Test-Path $cls)) { return $false }
        $found = $false
        Get-ChildItem $cls -EA SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' } | ForEach-Object {
            $dd = (Get-ItemProperty $_.PSPath 'DriverDesc' -EA SilentlyContinue).DriverDesc
            if ($dd -match 'NVIDIA') {
                $v = (Get-ItemProperty $_.PSPath 'DisableDynamicPstate' -EA SilentlyContinue).DisableDynamicPstate
                if ($v -eq 1) { $found = $true }
            }
        }
        return $found
    }}
    @{ Chk='ChkNvSync'; State={
        $cls = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
        if (-not (Test-Path $cls)) { return $false }
        $found = $false
        Get-ChildItem $cls -EA SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' } | ForEach-Object {
            $dd = (Get-ItemProperty $_.PSPath 'DriverDesc' -EA SilentlyContinue).DriverDesc
            if ($dd -match 'NVIDIA') {
                $v = (Get-ItemProperty $_.PSPath 'PerfLevelSrc' -EA SilentlyContinue).PerfLevelSrc
                if ($v -eq 0x2222) { $found = $true }
            }
        }
        return $found
    }}
    @{ Chk='ChkNvFastSync'; State={
        $cls = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
        if (-not (Test-Path $cls)) { return $false }
        $found = $false
        Get-ChildItem $cls -EA SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' } | ForEach-Object {
            $dd = (Get-ItemProperty $_.PSPath 'DriverDesc' -EA SilentlyContinue).DriverDesc
            if ($dd -match 'NVIDIA') {
                $v = (Get-ItemProperty $_.PSPath 'RMVSyncDelayFrameCount' -EA SilentlyContinue).RMVSyncDelayFrameCount
                if ($v -eq 0) { $found = $true }
            }
        }
        return $found
    }}
    @{ Chk='ChkNvShaderCache'; State={
        $cls = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
        if (-not (Test-Path $cls)) { return $false }
        $found = $false
        Get-ChildItem $cls -EA SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' } | ForEach-Object {
            $dd = (Get-ItemProperty $_.PSPath 'DriverDesc' -EA SilentlyContinue).DriverDesc
            if ($dd -match 'NVIDIA') {
                $v = (Get-ItemProperty $_.PSPath 'DisableShaderDiskCache' -EA SilentlyContinue).DisableShaderDiskCache
                if ($v -eq 0) { $found = $true }
            }
        }
        return $found
    }}
    @{ Chk='ChkNvTexFilter'; State={
        $cls = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
        if (-not (Test-Path $cls)) { return $false }
        $found = $false
        Get-ChildItem $cls -EA SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' } | ForEach-Object {
            $dd = (Get-ItemProperty $_.PSPath 'DriverDesc' -EA SilentlyContinue).DriverDesc
            if ($dd -match 'NVIDIA') {
                $v = (Get-ItemProperty $_.PSPath 'TextureQualityOption' -EA SilentlyContinue).TextureQualityOption
                if ($v -eq 3) { $found = $true }
            }
        }
        return $found
    }}

    # ═══════════════════════════════════════════════════════════════════
    # PRIVACY & TELEMETRY
    # ═══════════════════════════════════════════════════════════════════
    @{ Chk='ChkDiagTrack';     State={ (Get-Service 'DiagTrack' -EA SilentlyContinue).StartType -eq 'Disabled' } }
    @{ Chk='ChkDMWAppSupport'; State={ (Get-Service 'dmwappushservice' -EA SilentlyContinue).StartType -eq 'Disabled' } }
    @{ Chk='ChkTelemetryReg';  State={ Test-RegState 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 0 } }
    @{ Chk='ChkAppCompat';     State={
        (Test-RegState 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'DisableInventory' 1) -or
        (Test-RegState 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'DisableProgramTelemetry' 1)
    }}
    @{ Chk='ChkErrorReport';   State={ Test-RegState 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting' 'Disabled' 1 } }
    @{ Chk='ChkActivityHist';  State={ Test-RegState 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableActivityFeed' 0 } }
    @{ Chk='ChkCortana';       State={ Test-RegState 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'AllowCortana' 0 } }
    @{ Chk='ChkAdID';          State={ Test-RegState 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0 } }
    @{ Chk='ChkTailored';      State={ Test-RegState 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0 } }
    @{ Chk='ChkTyping';        State={ Test-RegState 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 1 } }
    @{ Chk='ChkCEIP';          State={ Test-RegState 'HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows' 'CEIPEnable' 0 } }
    @{ Chk='ChkOneDrive';      State={
        # OneDrive klasoru veya exe'si artik mevcut degilse basariyla kaldirilmis
        $odPath = "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe"
        return (-not (Test-Path $odPath))
    }}
    @{ Chk='ChkXboxServices'; State={
        try {
            # Once servis kontrolu dene
            $svc1 = Get-Service 'XblAuthManager' -EA SilentlyContinue
            $svc2 = Get-Service 'XblGameSave'    -EA SilentlyContinue
            $d1 = (-not $svc1) -or ($svc1.StartType -eq 'Disabled')
            $d2 = (-not $svc2) -or ($svc2.StartType -eq 'Disabled')
            if ($d1 -and $d2) { return $true }
            # Fallback: Registry Start degerini kontrol et (korunmali servisler icin)
            $r1 = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\XblAuthManager' 'Start' -EA SilentlyContinue).Start
            $r2 = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\XblGameSave'    'Start' -EA SilentlyContinue).Start
            return (($r1 -eq 4 -or $r1 -eq $null) -and ($r2 -eq 4 -or $r2 -eq $null))
        } catch { return $false }
    }}
    @{ Chk='ChkBingSearch';    State={ Test-RegState 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1 } }
    @{ Chk='ChkSuggestApps';   State={
        (Test-RegState 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338388Enabled' 0) -or
        (Test-RegState 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SilentInstalledAppsEnabled' 0)
    }}
    @{ Chk='ChkConsumerExp';   State={ Test-RegState 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1 } }

    # ═══════════════════════════════════════════════════════════════════
    # WINDOWS TWEAKS
    # ═══════════════════════════════════════════════════════════════════
    @{ Chk='ChkAnimations';    State={ Test-RegState 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate' '0' } }
    @{ Chk='ChkJPEGQuality';   State={ Test-RegState 'HKCU:\Control Panel\Desktop' 'JPEGImportQuality' 100 } }
    @{ Chk='ChkMenuDelay';     State={ Test-RegState 'HKCU:\Control Panel\Desktop' 'MenuShowDelay' '0' } }
    @{ Chk='ChkTaskbarAnims';  State={ Test-RegState 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAnimations' 0 } }
    @{ Chk='ChkBSODDetail';    State={ Test-RegState 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' 'AutoReboot' 0 } }
    @{ Chk='ChkLaunchTo';      State={ Test-RegState 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'LaunchTo' 1 } }
    @{ Chk='ChkNumlock';       State={
        try {
            $v = (Get-ItemProperty 'HKCU:\Control Panel\Keyboard' 'InitialKeyboardIndicators' -EA Stop).InitialKeyboardIndicators
            return ($v -eq '2' -or $v -eq '2147483650')
        } catch { return $false }
    }}
    @{ Chk='ChkHideExt';       State={ Test-RegState 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'HideFileExt' 0 } }
    @{ Chk='ChkLongPaths';     State={ Test-RegState 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'LongPathsEnabled' 1 } }
    @{ Chk='ChkContextMenu';   State={
        try {
            $p = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'
            return (Test-Path $p)
        } catch { return $false }
    }}
    @{ Chk='ChkDarkMode';      State={ Test-RegState 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'AppsUseLightTheme' 0 } }
    @{ Chk='ChkTransparency';  State={ Test-RegState 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0 } }
    @{ Chk='ChkCrashDumpFull'; State={ Test-RegState 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' 'CrashDumpEnabled' 1 } }
    @{ Chk='ChkEventLogSize';  State={
        try {
            $sz = (wevtutil gl Application 2>&1 | Out-String)
            return ($sz -match 'maxSize:\s*10[0-9]{7}')  # 100MB = 104857600
        } catch { return $false }
    }}
)

# ─── GORSEL GOSTERGE: Yesil metin + ✓ suffix ─────────────────────────────────
$appliedCount = 0
$notAppliedCount = 0
$greenBrush = New-Brush '#4CAF50'

foreach ($entry in $stateMap) {
    $ctrl = $Window.FindName($entry.Chk)
    if ($ctrl) {
        try {
            $isApplied = & $entry.State
            if ($isApplied) {
                $ctrl.IsChecked  = $true
                $ctrl.Foreground = $greenBrush
                # Content metnine ✓ ekle (tekrar eklememek icin kontrol)
                $txt = [string]$ctrl.Content
                if ($txt -and $txt -notmatch '✓$') {
                    $ctrl.Content = "$txt  ✓"
                }
                $existingTip = if ($ctrl.ToolTip) { "$($ctrl.ToolTip)`n" } else { '' }
                $ctrl.ToolTip = "${existingTip}✓ Bu ayar zaten uygulanmis."
                $appliedCount++
            } else {
                $notAppliedCount++
            }
        } catch { $notAppliedCount++ }
    }
}
Write-Log "Durum taramasi: $appliedCount ayar zaten uygulanmis, $notAppliedCount uygulanmamis." 'OK'

# ─── OZEL KONTROLLER (netsh / bcdedit gerektiren) ─────────────────────────────
# TCP netsh kontrolleri — tek sorguda birden fazla checkbox
try {
    $tcpGlobal = netsh int tcp show global 2>&1 | Out-String

    # AutoTuning = normal
    $atCtrl = $Window.FindName('ChkAutoTuning')
    if ($atCtrl -and ($tcpGlobal -match 'Receive Window Auto-Tuning Level\s*:\s*normal')) {
        $atCtrl.IsChecked = $true; $atCtrl.Foreground = $greenBrush
        $t = [string]$atCtrl.Content; if ($t -notmatch '✓$') { $atCtrl.Content = "$t  ✓" }
    }

    # ECN = disabled
    $ecnCtrl = $Window.FindName('ChkECN')
    if ($ecnCtrl -and ($tcpGlobal -match 'ECN Capability\s*:\s*disabled')) {
        $ecnCtrl.IsChecked = $true; $ecnCtrl.Foreground = $greenBrush
        $t = [string]$ecnCtrl.Content; if ($t -notmatch '✓$') { $ecnCtrl.Content = "$t  ✓" }
    }

    # RSC = disabled
    $rscCtrl = $Window.FindName('ChkRSC')
    if ($rscCtrl -and ($tcpGlobal -match 'Receive Segment Coalescing.*:\s*disabled')) {
        $rscCtrl.IsChecked = $true; $rscCtrl.Foreground = $greenBrush
        $t = [string]$rscCtrl.Content; if ($t -notmatch '✓$') { $rscCtrl.Content = "$t  ✓" }
    }
} catch {}

# Congestion = CUBIC
try {
    $tcpSupp = netsh int tcp show supplemental 2>&1 | Out-String
    $congCtrl = $Window.FindName('ChkCongestion')
    if ($congCtrl -and ($tcpSupp -match 'cubic')) {
        $congCtrl.IsChecked = $true; $congCtrl.Foreground = $greenBrush
        $t = [string]$congCtrl.Content; if ($t -notmatch '✓$') { $congCtrl.Content = "$t  ✓" }
    }
} catch {}

# GPU markasina gore acilista karsi markanin bolumunu gizle
if ($GrpNvidia) {
    $GrpNvidia.Visibility = $(if ($global:HW.GpuIsNV) { 'Visible' } else { 'Collapsed' })
}
if ($GrpAmd) {
    $GrpAmd.Visibility = $(if ($global:HW.GpuIsAMD) { 'Visible' } else { 'Collapsed' })
}

# Aktif güç planını hemen göster (HWTimer 20 saniye bekletmeden)
try {
    $activeLine = powercfg /getactivescheme 2>&1 | Where-Object { $_ -match 'Power Scheme GUID' } | Select-Object -First 1
    if ($activeLine -match '\((.+)\)') {
        $TxtActivePlan.Text = "Aktif plan: $($Matches[1])"
    }
} catch {}

# ─── SHOW WINDOW ──────────────────────────────────────────────────────────────
$Window.ShowDialog() | Out-Null
$HWTimer.Stop()
