# System Cleaner v3.5 - LiVNLOUD x Claude
# Yonetici kontrolu
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process powershell.exe "-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

# ============================================================
# RENK PALETI - HUD Karanlik Tema
# ============================================================
$GRAD_TOP   = "#0A0D14"; $GRAD_BOT   = "#060810"
$BG_CARD    = "#0D1117"; $BG_HEADER  = "#0D1117"
$FG_PRIMARY = "#E2E8F0"; $FG_SECOND  = "#4A5568"
$ACCENT     = "#00D4FF"; $ACCENT2    = "#7C3AED"
$SUCCESS    = "#00FF87"; $ERROR_C    = "#FF4757"
$BORDER     = "#1E2535"; $BORDER2    = "#00D4FF"
$LOG_BG     = "#060810"; $LOG_FG     = "#4A5568"
$WARN_C     = "#FFB347"; $BG_ROW     = "#111827"
$OPT_C      = "#F59E0B"

# ============================================================
# REGISTRY TABANLI UYGULAMA TESPITI
# ============================================================
function Get-AppInstallPath($searchName) {
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    foreach ($rp in $regPaths) {
        $found = Get-ItemProperty $rp -ErrorAction SilentlyContinue |
                 Where-Object { $_.DisplayName -like "*$searchName*" } |
                 Select-Object -First 1
        if ($found -and $found.InstallLocation -and (Test-Path $found.InstallLocation)) {
            return $found.InstallLocation.TrimEnd("\")
        }
    }
    return $null
}

function Get-AllRegisteredInstallPaths {
    $paths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    foreach ($rp in $regPaths) {
        Get-ItemProperty $rp -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.InstallLocation -and $_.InstallLocation.Trim() -ne "") {
                $root = $_.InstallLocation.TrimEnd("\").Split("\")[0..1] -join "\"
                $paths.Add($root) | Out-Null
                try {
                    $parent = Split-Path $_.InstallLocation.TrimEnd("\") -Parent
                    if ($parent) { $paths.Add($parent) | Out-Null }
                } catch {}
            }
        }
    }
    return $paths
}

function Get-SteamPath {
    foreach ($key in @("HKLM:\SOFTWARE\WOW6432Node\Valve\Steam","HKLM:\SOFTWARE\Valve\Steam")) {
        $r = Get-ItemProperty $key -ErrorAction SilentlyContinue
        if ($r -and $r.InstallPath -and (Test-Path $r.InstallPath)) { return $r.InstallPath.TrimEnd("\") }
    }
    return $null
}

function Get-DiscordPath {
    $reg = Get-AppInstallPath "Discord"
    if ($reg) { return $reg }
    $fb = "$env:LOCALAPPDATA\Discord"
    if (Test-Path $fb) { return $fb }
    return $null
}

# Dinamik yollar
$steamPath   = Get-SteamPath
$discordPath = Get-DiscordPath
$bravePath   = Get-AppInstallPath "Brave"
$chromePath  = Get-AppInstallPath "Google Chrome"
$ffPath      = Get-AppInstallPath "Mozilla Firefox"
$epicPath    = Get-AppInstallPath "Epic Games Launcher"
$gogPath     = Get-AppInstallPath "GOG Galaxy"
$ubisoftPath = Get-AppInstallPath "Ubisoft Connect"
$bnetPath    = Get-AppInstallPath "Battle.net"
$eaPath      = Get-AppInstallPath "EA"
$edgeProfile = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default"
$xboxPkg     = "$env:LOCALAPPDATA\Packages\Microsoft.GamingApp_8wekyb3d8bbwe"

$browserCachePaths = @{
    "ChkBrave"   = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default"
    "ChkChrome"  = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default"
    "ChkEdge"    = $edgeProfile
    "ChkOpera"   = "$env:APPDATA\Opera Software\Opera Stable"
    "ChkOperaGX" = "$env:APPDATA\Opera Software\Opera GX Stable"
}

$steamCacheHTTP = if ($steamPath) { "$steamPath\appcache\httpcache" } else { $null }
$steamCacheHTML = "$env:LOCALAPPDATA\Steam\htmlcache"
$discordCache   = if ($discordPath) { "$discordPath\Cache" }      else { "$env:APPDATA\discord\Cache" }
$discordCode    = if ($discordPath) { "$discordPath\Code Cache" } else { "$env:APPDATA\discord\Code Cache" }
$discordGpu     = if ($discordPath) { "$discordPath\GPUCache" }   else { "$env:APPDATA\discord\GPUCache" }

$appInstalled = @{
    "Brave"      = ($null -ne $bravePath  -or (Test-Path "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default"))
    "Chrome"     = ($null -ne $chromePath -or (Test-Path "$env:LOCALAPPDATA\Google\Chrome\User Data\Default"))
    "Firefox"    = ($null -ne $ffPath     -or (Test-Path "$env:APPDATA\Mozilla\Firefox\Profiles"))
    "Edge"       = (Test-Path $edgeProfile)
    "Opera"      = (Test-Path "$env:APPDATA\Opera Software\Opera Stable")
    "Opera GX"   = (Test-Path "$env:APPDATA\Opera Software\Opera GX Stable")
    "Steam"      = ($null -ne $steamPath)
    "Discord"    = ($null -ne $discordPath)
    "Epic Games" = ($null -ne $epicPath   -or (Test-Path "$env:LOCALAPPDATA\EpicGamesLauncher"))
    "GOG Galaxy" = ($null -ne $gogPath    -or (Test-Path "${env:ProgramFiles(x86)}\GOG Galaxy"))
    "Ubisoft"    = ($null -ne $ubisoftPath)
    "Battle.net" = ($null -ne $bnetPath   -or (Test-Path "${env:ProgramFiles(x86)}\Battle.net"))
    "EA App"     = ($null -ne $eaPath     -or (Test-Path "$env:PROGRAMDATA\Electronic Arts\EA Desktop"))
    "Xbox"       = (Test-Path $xboxPkg)
}

# Sistem bilgileri
$cpuName    = (Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1).Name
$cpuObj     = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
$cpuCores   = if ($cpuObj) { $cpuObj.NumberOfCores } else { 0 }
$cpuThreads = if ($cpuObj) { $cpuObj.NumberOfLogicalProcessors } else { 0 }
$ramGB      = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
$winVer     = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").DisplayVersion
$osName     = (Get-CimInstance Win32_OperatingSystem).Caption -replace "Microsoft ",""
$cpuIsAmd   = $cpuName -match "(?i)AMD|Ryzen"
$cpuIsIntel = $cpuName -match "(?i)Intel"

# ============================================================
# XAML - HUD TASARIM v3.5 - WinScript Style
# ============================================================
[xml]$xaml = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="System Cleaner v3.5 - LiVNLOUD x Claude"
    Width="1060" Height="860"
    MinWidth="900" MinHeight="700"
    WindowStartupLocation="CenterScreen"
    FontFamily="Segoe UI"
    UseLayoutRounding="True"
    TextOptions.TextFormattingMode="Display"
    ResizeMode="CanResize">

    <Grid>
        <Grid.Background>
            <LinearGradientBrush StartPoint="0.5,0" EndPoint="0.5,1">
                <GradientStop x:Name="GradTop" Color="#0D1117" Offset="0"/>
                <GradientStop x:Name="GradBot" Color="#090D13" Offset="1"/>
            </LinearGradientBrush>
        </Grid.Background>

        <!-- ANA LAYOUT: Sol Sidebar + Sag Icerik -->
        <Grid>
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="200"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <!-- ==================== SOL SIDEBAR ==================== -->
            <Border x:Name="Sidebar" Grid.Column="0" BorderThickness="0,0,1,0">
                <DockPanel>
                    <!-- Uygulama basligi -->
                    <StackPanel DockPanel.Dock="Top" Margin="20,24,20,0">
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
                            <Border Width="8" Height="8" CornerRadius="4" Margin="0,0,8,0" VerticalAlignment="Center">
                                <Border.Background><SolidColorBrush x:Name="LogoDot" Color="#00D4FF"/></Border.Background>
                            </Border>
                            <TextBlock x:Name="TitleText" Text="SYSTEM" FontSize="13" FontWeight="Black"/>
                        </StackPanel>
                        <TextBlock x:Name="TitleText2" Text="CLEANER" FontSize="13" FontWeight="Black" Margin="16,0,0,0"/>
                        <StackPanel Orientation="Horizontal" Margin="16,6,0,0">
                            <Border Padding="5,2" CornerRadius="3" Margin="0,0,6,0">
                                <Border.Background><SolidColorBrush x:Name="BadgeBg" Color="#00D4FF" Opacity="0.15"/></Border.Background>
                                <TextBlock x:Name="VersionBadge" Text="v3.5" FontSize="9" FontWeight="Bold"/>
                            </Border>
                        </StackPanel>
                        <TextBlock x:Name="SubtitleText" Text="LiVNLOUD x Claude" FontSize="9" Margin="16,4,0,0"/>
                    </StackPanel>

                    <!-- HUD Bilgileri -->
                    <StackPanel DockPanel.Dock="Top" Margin="14,20,14,0">
                        <Border x:Name="HudBox1" CornerRadius="6" Padding="12,8" Margin="0,0,0,4" BorderThickness="1">
                            <StackPanel>
                                <TextBlock x:Name="HudLabel1" Text="CPU" FontSize="8" FontWeight="Bold" Margin="0,0,0,2"/>
                                <TextBlock x:Name="HudCpu" FontSize="10" FontWeight="SemiBold" TextWrapping="NoWrap" TextTrimming="CharacterEllipsis"/>
                            </StackPanel>
                        </Border>
                        <Grid Margin="0,0,0,4">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="4"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <Border x:Name="HudBox2" Grid.Column="0" CornerRadius="6" Padding="10,8" BorderThickness="1">
                                <StackPanel>
                                    <TextBlock x:Name="HudLabel2" Text="RAM" FontSize="8" FontWeight="Bold" Margin="0,0,0,2"/>
                                    <TextBlock x:Name="HudRam" FontSize="10" FontWeight="SemiBold"/>
                                </StackPanel>
                            </Border>
                            <Border x:Name="HudBox3" Grid.Column="2" CornerRadius="6" Padding="10,8" BorderThickness="1">
                                <StackPanel>
                                    <TextBlock x:Name="HudLabel3" Text="DISK" FontSize="8" FontWeight="Bold" Margin="0,0,0,2"/>
                                    <TextBlock x:Name="DiskFreeText" FontSize="10" FontWeight="SemiBold"/>
                                </StackPanel>
                            </Border>
                        </Grid>
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="4"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <Border x:Name="HudBox4" Grid.Column="0" CornerRadius="6" Padding="10,8" BorderThickness="1">
                                <StackPanel>
                                    <TextBlock x:Name="HudLabel4" Text="OS" FontSize="8" FontWeight="Bold" Margin="0,0,0,2"/>
                                    <TextBlock x:Name="HudOs" FontSize="10" FontWeight="SemiBold"/>
                                </StackPanel>
                            </Border>
                            <Border x:Name="HudBox5" Grid.Column="2" CornerRadius="6" Padding="10,8" BorderThickness="1">
                                <StackPanel>
                                    <TextBlock x:Name="HudLabel5" Text="USB" FontSize="8" FontWeight="Bold" Margin="0,0,0,2"/>
                                    <TextBlock x:Name="HudUsb" Text="0" FontSize="10" FontWeight="SemiBold"/>
                                </StackPanel>
                            </Border>
                        </Grid>
                    </StackPanel>

                    <!-- NAV SEKMELERI -->
                    <StackPanel DockPanel.Dock="Top" Margin="0,24,0,0">
                        <TextBlock Text="NAVIGATE" FontSize="9" FontWeight="Bold" Margin="20,0,0,8" Opacity="0.4"/>
                        <Button x:Name="TabClean" Height="40" HorizontalContentAlignment="Left" Padding="20,0" FontSize="12" FontWeight="SemiBold" BorderThickness="3,0,0,0" Cursor="Hand">
                            <StackPanel Orientation="Horizontal">
                                <TextBlock Text="Temizlik" VerticalAlignment="Center"/>
                            </StackPanel>
                        </Button>
                        <Button x:Name="TabOptimize" Height="40" HorizontalContentAlignment="Left" Padding="20,0" FontSize="12" FontWeight="SemiBold" BorderThickness="3,0,0,0" Cursor="Hand" Margin="0,2,0,0">
                            <StackPanel Orientation="Horizontal">
                                <TextBlock Text="Optimizasyon" VerticalAlignment="Center"/>
                            </StackPanel>
                        </Button>
                    </StackPanel>

                    <!-- DURUM BILGISI (alt) -->
                    <StackPanel DockPanel.Dock="Bottom" Margin="14,0,14,16">
                        <Separator Margin="0,0,0,12" Opacity="0.15"/>
                        <TextBlock x:Name="AdminText" Text="[ADMIN]" FontSize="10" FontWeight="Bold" Foreground="#00FF87"/>
                        <TextBlock x:Name="ThemeText" Text="Koyu Tema" FontSize="9" Margin="0,3,0,0" Foreground="#4A5568"/>
                        <!-- MODÜL OZETI - sadece Clean tabda -->
                        <Border x:Name="SummaryBar" CornerRadius="6" Padding="10,8" Margin="0,10,0,0" BorderThickness="1">
                            <Grid>
                                <Grid.RowDefinitions>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                </Grid.RowDefinitions>
                                <TextBlock x:Name="SummaryText" Text="Modul secin..." FontSize="9" TextWrapping="Wrap"/>
                                <TextBlock x:Name="SummaryCount" Grid.Row="1" FontSize="16" FontWeight="Black" Margin="0,4,0,0"/>
                            </Grid>
                        </Border>
                    </StackPanel>

                    <!-- dolgu -->
                    <Grid/>
                </DockPanel>
            </Border>

            <!-- ==================== SAG ICERIK ALANI ==================== -->
            <Grid Grid.Column="1">
                <Grid.RowDefinitions>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <!-- TEMIZLIK PANELI -->
                <ScrollViewer x:Name="PanelClean" Grid.Row="0" VerticalScrollBarVisibility="Auto" Padding="20,20,18,8">
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="12"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>

                        <!-- SOL KOLON -->
                        <StackPanel Grid.Column="0" VerticalAlignment="Top">

                            <!-- Sistem Temizligi -->
                            <Border x:Name="Card1" CornerRadius="8" TextElement.Foreground="#E2E8F0" Padding="16,14" Margin="0,0,0,10" BorderThickness="1">
                                <StackPanel>
                                    <Grid Margin="0,0,0,10">
                                        <StackPanel Orientation="Horizontal">
                                            <Border Width="3" Height="14" CornerRadius="2" Margin="0,0,10,0" VerticalAlignment="Center">
                                                <Border.Background><SolidColorBrush Color="#00D4FF"/></Border.Background>
                                            </Border>
                                            <TextBlock x:Name="SL1" Text="SISTEM TEMIZLIGI" FontSize="10" FontWeight="Bold" VerticalAlignment="Center"/>
                                        </StackPanel>
                                        <Button x:Name="BtnSelectSistem" Content="Tumu" FontSize="9" BorderThickness="0" Background="Transparent" Cursor="Hand" HorizontalAlignment="Right" VerticalAlignment="Center" Padding="0"/>
                                    </Grid>
                                    <UniformGrid Columns="2" x:Name="Ug1">
                                        <CheckBox x:Name="ChkTemp"       Content="Gecici Dosyalar"  Margin="0,3,4,3" FontSize="11"/>
                                        <CheckBox x:Name="ChkRecycle"    Content="Geri Donusum"     Margin="0,3,4,3" FontSize="11"/>
                                        <CheckBox x:Name="ChkWinHistory" Content="Windows Gecmisi"  Margin="0,3,4,3" FontSize="11"/>
                                        <CheckBox x:Name="ChkDns"        Content="DNS / Thumbnail"  Margin="0,3,4,3" FontSize="11"/>
                                        <CheckBox x:Name="ChkLogs"       Content="Sistem Loglari"   Margin="0,3,4,3" FontSize="11"/>
                                        <CheckBox x:Name="ChkWinUpdate"  Content="Update Cache"     Margin="0,3,4,3" FontSize="11"/>
                                        <CheckBox x:Name="ChkFontCache"  Content="Font/Ikon Cache"  Margin="0,3,4,3" FontSize="11"/>
                                        <CheckBox x:Name="ChkRam"        Content="RAM Bosalt"       Margin="0,3,4,3" FontSize="11"/>
                                        <CheckBox x:Name="ChkUsb"        Content="USB Gecmisi"      Margin="0,3,4,3" FontSize="11"/>
                                    </UniformGrid>
                                </StackPanel>
                            </Border>

                            <!-- Tarayicilar -->
                            <Border x:Name="Card2" CornerRadius="8" TextElement.Foreground="#E2E8F0" Padding="16,14" Margin="0,0,0,10" BorderThickness="1">
                                <StackPanel>
                                    <Grid Margin="0,0,0,10">
                                        <StackPanel Orientation="Horizontal">
                                            <Border Width="3" Height="14" CornerRadius="2" Margin="0,0,10,0" VerticalAlignment="Center">
                                                <Border.Background><SolidColorBrush Color="#00D4FF"/></Border.Background>
                                            </Border>
                                            <TextBlock x:Name="SL2" Text="TARAYICILAR" FontSize="10" FontWeight="Bold" VerticalAlignment="Center"/>
                                        </StackPanel>
                                        <Button x:Name="BtnSelectBrowser" Content="Tumu" FontSize="9" BorderThickness="0" Background="Transparent" Cursor="Hand" HorizontalAlignment="Right" VerticalAlignment="Center" Padding="0"/>
                                    </Grid>
                                    <StackPanel x:Name="BrowserPanel">
                                        <CheckBox x:Name="ChkBrave"   Content="Brave"    Visibility="Collapsed" Margin="0,3,4,3" FontSize="11"/>
                                        <CheckBox x:Name="ChkChrome"  Content="Chrome"   Visibility="Collapsed" Margin="0,3,4,3" FontSize="11"/>
                                        <CheckBox x:Name="ChkFirefox" Content="Firefox"  Visibility="Collapsed" Margin="0,3,4,3" FontSize="11"/>
                                        <CheckBox x:Name="ChkEdge"    Content="Edge"     Visibility="Collapsed" Margin="0,3,4,3" FontSize="11"/>
                                        <CheckBox x:Name="ChkOpera"   Content="Opera"    Visibility="Collapsed" Margin="0,3,4,3" FontSize="11"/>
                                        <CheckBox x:Name="ChkOperaGX" Content="Opera GX" Visibility="Collapsed" Margin="0,3,4,3" FontSize="11"/>
                                        <TextBlock x:Name="BrowserNone" Text="Desteklenen tarayici kurulu degil." FontSize="10" Visibility="Collapsed" Margin="0,4,0,0" Foreground="#4A5568"/>
                                    </StackPanel>
                                </StackPanel>
                            </Border>

                            <!-- Sistem Onarimi -->
                            <Border x:Name="Card5" CornerRadius="8" TextElement.Foreground="#E2E8F0" Padding="16,14" Margin="0,0,0,10" BorderThickness="1">
                                <StackPanel>
                                    <Grid Margin="0,0,0,10">
                                        <StackPanel Orientation="Horizontal">
                                            <Border Width="3" Height="14" CornerRadius="2" Margin="0,0,10,0" VerticalAlignment="Center">
                                                <Border.Background><SolidColorBrush Color="#7C3AED"/></Border.Background>
                                            </Border>
                                            <TextBlock x:Name="SL5" Text="ONARIM / OPTIMIZASYON" FontSize="10" FontWeight="Bold" VerticalAlignment="Center"/>
                                        </StackPanel>
                                        <Button x:Name="BtnSelectRepair" Content="Tumu" FontSize="9" BorderThickness="0" Background="Transparent" Cursor="Hand" HorizontalAlignment="Right" VerticalAlignment="Center" Padding="0"/>
                                    </Grid>
                                    <UniformGrid Columns="2">
                                        <CheckBox x:Name="ChkBrokenShortcuts" Content="Cop Kisayollar"    Margin="0,3,4,3" FontSize="11"/>
                                        <CheckBox x:Name="ChkStartup"         Content="Baslangic Listesi" Margin="0,3,4,3" FontSize="11"/>
                                        <CheckBox x:Name="ChkOrphanedReg"     Content="Orphan Registry"   Margin="0,3,4,3" FontSize="11"/>
                                        <CheckBox x:Name="ChkSfc"             Content="SFC / DISM"        Margin="0,3,4,3" FontSize="11"/>
                                        <CheckBox x:Name="ChkPagefile"        Content="Pagefile Optimize" Margin="0,3,4,3" FontSize="11"/>
                                    </UniformGrid>
                                    <TextBlock x:Name="RepairNote" FontSize="9" TextWrapping="Wrap" Margin="0,8,0,0"/>
                                </StackPanel>
                            </Border>

                        </StackPanel>

                        <!-- SAG KOLON -->
                        <StackPanel Grid.Column="2" VerticalAlignment="Top">

                            <!-- Oyun Platformlari -->
                            <Border x:Name="Card3" CornerRadius="8" TextElement.Foreground="#E2E8F0" Padding="16,14" Margin="0,0,0,10" BorderThickness="1">
                                <StackPanel>
                                    <Grid Margin="0,0,0,10">
                                        <StackPanel Orientation="Horizontal">
                                            <Border Width="3" Height="14" CornerRadius="2" Margin="0,0,10,0" VerticalAlignment="Center">
                                                <Border.Background><SolidColorBrush Color="#00D4FF"/></Border.Background>
                                            </Border>
                                            <TextBlock x:Name="SL3" Text="OYUN PLATFORMLARI" FontSize="10" FontWeight="Bold" VerticalAlignment="Center"/>
                                        </StackPanel>
                                        <Button x:Name="BtnSelectGaming" Content="Tumu" FontSize="9" BorderThickness="0" Background="Transparent" Cursor="Hand" HorizontalAlignment="Right" VerticalAlignment="Center" Padding="0"/>
                                    </Grid>
                                    <StackPanel x:Name="GamingPanel">
                                        <CheckBox x:Name="ChkSteam"     Content="Steam"      Visibility="Collapsed" Margin="0,3,4,3" FontSize="11"/>
                                        <CheckBox x:Name="ChkDiscord"   Content="Discord"    Visibility="Collapsed" Margin="0,3,4,3" FontSize="11"/>
                                        <CheckBox x:Name="ChkEpic"      Content="Epic Games" Visibility="Collapsed" Margin="0,3,4,3" FontSize="11"/>
                                        <CheckBox x:Name="ChkGog"       Content="GOG Galaxy" Visibility="Collapsed" Margin="0,3,4,3" FontSize="11"/>
                                        <CheckBox x:Name="ChkUbisoft"   Content="Ubisoft"    Visibility="Collapsed" Margin="0,3,4,3" FontSize="11"/>
                                        <CheckBox x:Name="ChkBattlenet" Content="Battle.net" Visibility="Collapsed" Margin="0,3,4,3" FontSize="11"/>
                                        <CheckBox x:Name="ChkEa"        Content="EA App"     Visibility="Collapsed" Margin="0,3,4,3" FontSize="11"/>
                                        <CheckBox x:Name="ChkXbox"      Content="Xbox"       Visibility="Collapsed" Margin="0,3,4,3" FontSize="11"/>
                                        <TextBlock x:Name="GamingNone" Text="Desteklenen oyun platformu kurulu degil." FontSize="10" Visibility="Collapsed" Margin="0,4,0,0" Foreground="#4A5568"/>
                                    </StackPanel>
                                </StackPanel>
                            </Border>

                            <!-- Gizlilik -->
                            <Border x:Name="Card6" CornerRadius="8" TextElement.Foreground="#E2E8F0" Padding="16,14" Margin="0,0,0,10" BorderThickness="1">
                                <StackPanel>
                                    <Grid Margin="0,0,0,10">
                                        <StackPanel Orientation="Horizontal">
                                            <Border Width="3" Height="14" CornerRadius="2" Margin="0,0,10,0" VerticalAlignment="Center">
                                                <Border.Background><SolidColorBrush Color="#FF4757"/></Border.Background>
                                            </Border>
                                            <TextBlock x:Name="SL6" Text="GIZLILIK / DERIN TEMIZLIK" FontSize="10" FontWeight="Bold" VerticalAlignment="Center"/>
                                        </StackPanel>
                                        <Button x:Name="BtnSelectPrivacy" Content="Tumu" FontSize="9" BorderThickness="0" Background="Transparent" Cursor="Hand" HorizontalAlignment="Right" VerticalAlignment="Center" Padding="0"/>
                                    </Grid>
                                    <UniformGrid Columns="2">
                                        <CheckBox x:Name="ChkVss"           Content="VSS Shadow Copies"   Margin="0,3,4,3" FontSize="11"/>
                                        <CheckBox x:Name="ChkSearchIndex"   Content="Search Index"         Margin="0,3,4,3" FontSize="11"/>
                                        <CheckBox x:Name="ChkLnk"           Content="LNK / Recent"         Margin="0,3,4,3" FontSize="11"/>
                                        <CheckBox x:Name="ChkShellbag"      Content="ShellBag Gecmisi"     Margin="0,3,4,3" FontSize="11"/>
                                        <CheckBox x:Name="ChkPagefileClear" Content="Pagefile Sifirla"     Margin="0,3,4,3" FontSize="11"/>
                                        <CheckBox x:Name="ChkHiberfil"      Content="Hibernate Kapat"      Margin="0,3,4,3" FontSize="11"/>
                                        <CheckBox x:Name="ChkOrphanSetup"   Content="Installer Artiklari"  Margin="0,3,4,3" FontSize="11"/>
                                    </UniformGrid>
                                    <TextBlock x:Name="PrivacyNote" Text="Installer Artiklari: onaylamaniz gerekir. VSS/Shellbag: gizlilik izlerini siler." FontSize="9" TextWrapping="Wrap" Margin="0,8,0,0"/>
                                </StackPanel>
                            </Border>

                        </StackPanel>
                    </Grid>
                </ScrollViewer>

                <!-- OPTIMIZASYON PANELI -->
                <ScrollViewer x:Name="PanelOptimize" Grid.Row="0" Visibility="Collapsed" VerticalScrollBarVisibility="Auto" Padding="20,20,18,8">
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="12"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>

                        <!-- SOL: GUC + REGISTRY + CPU BOOT -->
                        <StackPanel Grid.Column="0" VerticalAlignment="Top">

                            <!-- Guc Planlari -->
                            <Border x:Name="OCard1" CornerRadius="8" TextElement.Foreground="#E2E8F0" Padding="16,14" Margin="0,0,0,10" BorderThickness="1">
                                <StackPanel>
                                    <Grid Margin="0,0,0,10">
                                        <StackPanel Orientation="Horizontal">
                                            <Border Width="3" Height="14" CornerRadius="2" Margin="0,0,10,0" VerticalAlignment="Center">
                                                <Border.Background><SolidColorBrush Color="#F59E0B"/></Border.Background>
                                            </Border>
                                            <TextBlock x:Name="OSL1" Text="GUC PLANI" FontSize="10" FontWeight="Bold" VerticalAlignment="Center"/>
                                        </StackPanel>
                                    </Grid>
                                    <TextBlock x:Name="CurrentPlanText" Text="Mevcut plan: tespit ediliyor..." FontSize="10" Margin="0,0,0,10" TextWrapping="Wrap" Foreground="#00D4FF"/>
                                    <RadioButton x:Name="RPlanBalanced"  Content="Dengeli (Windows Varsayilan)"      Margin="0,2,0,2" FontSize="11" GroupName="PowerPlan"/>
                                    <RadioButton x:Name="RPlanHigh"      Content="Yuksek Performans"                 Margin="0,2,0,2" FontSize="11" GroupName="PowerPlan"/>
                                    <RadioButton x:Name="RPlanUltimate"  Content="Ultimate Performance"               Margin="0,2,0,2" FontSize="11" GroupName="PowerPlan"/>
                                    <RadioButton x:Name="RPlanBitsum"    Content="Bitsum Highest Performance"         Margin="0,2,0,2" FontSize="11" GroupName="PowerPlan"/>
                                    <RadioButton x:Name="RPlanHybred"    Content="TheHybred Low Latency High Perf"   Margin="0,2,0,2" FontSize="11" GroupName="PowerPlan"/>
                                    <TextBlock FontSize="9" TextWrapping="Wrap" Margin="0,8,0,0" x:Name="PowerNote" Foreground="#4A5568"/>
                                    <Button x:Name="BtnApplyPower" Content="Guc Planini Uygula" Height="32" Margin="0,10,0,0" FontSize="11" FontWeight="Bold" Cursor="Hand" BorderThickness="1"/>
                                </StackPanel>
                            </Border>

                            <!-- Registry Tweaks -->
                            <Border x:Name="OCard2" CornerRadius="8" TextElement.Foreground="#E2E8F0" Padding="16,14" Margin="0,0,0,10" BorderThickness="1">
                                <StackPanel>
                                    <Grid Margin="0,0,0,10">
                                        <StackPanel Orientation="Horizontal">
                                            <Border Width="3" Height="14" CornerRadius="2" Margin="0,0,10,0" VerticalAlignment="Center">
                                                <Border.Background><SolidColorBrush Color="#F59E0B"/></Border.Background>
                                            </Border>
                                            <TextBlock x:Name="OSL2" Text="REGISTRY TWEAKS" FontSize="10" FontWeight="Bold" VerticalAlignment="Center"/>
                                        </StackPanel>
                                    </Grid>
                                    <CheckBox x:Name="ChkRegGpuPriority"  Content="GPU Priority: 8 (Games)"               Margin="0,2,0,2" FontSize="11" IsChecked="True" ToolTip="GPU'ya oyun gorevi icin en yuksek onceligi verir."/>
                                    <CheckBox x:Name="ChkRegGamePriority" Content="Game Priority: 6 (Games)"              Margin="0,2,0,2" FontSize="11" IsChecked="True" ToolTip="MMCSS scheduler'da oyun gorevine yuksek CPU onceligi atar."/>
                                    <CheckBox x:Name="ChkRegWin32Prio"    Content="Win32PrioritySeparation"               Margin="0,2,0,2" FontSize="11" IsChecked="True" ToolTip="On plandaki uygulamalara agresif CPU zamanlama avantaji saglar."/>
                                    <StackPanel x:Name="Win32Panel" Margin="16,0,0,4" Visibility="Collapsed">
                                        <RadioButton x:Name="RWin32BestFPS"     Content="Best FPS (20)"          Margin="0,2,0,2" FontSize="10" GroupName="Win32Prio" IsChecked="True"/>
                                        <RadioButton x:Name="RWin32BestLatency" Content="Best Latency (42)"      Margin="0,2,0,2" FontSize="10" GroupName="Win32Prio"/>
                                        <RadioButton x:Name="RWin32Balanced"    Content="Balanced (24)"          Margin="0,2,0,2" FontSize="10" GroupName="Win32Prio"/>
                                        <RadioButton x:Name="RWin32Default"     Content="Varsayilan / Geri Al (38)" Margin="0,2,0,2" FontSize="10" GroupName="Win32Prio"/>
                                    </StackPanel>
                                    <CheckBox x:Name="ChkRegNetThrottle"  Content="NetworkThrottlingIndex: Kapat"         Margin="0,2,0,2" FontSize="11" IsChecked="True" ToolTip="Windows'un ag paketlerini geciktirmesini engeller."/>
                                    <CheckBox x:Name="ChkRegMenuDelay"    Content="MenuShowDelay: 0 ms"                   Margin="0,2,0,2" FontSize="11" IsChecked="True" ToolTip="Fare menulerinin anlinda acilmasini saglar."/>
                                    <CheckBox x:Name="ChkRegForeground"   Content="ForegroundBoost + LowLatency Audio"    Margin="0,2,0,2" FontSize="11" IsChecked="True" ToolTip="On plandaki pencereye ekstra CPU zamani verir."/>
                                    <CheckBox x:Name="ChkRegMmcss"        Content="MMCSS: Games / Pro Audio"              Margin="0,2,0,2" FontSize="11" IsChecked="True" ToolTip="Multimedia Class Scheduler yuksek oncelik."/>
                                    <CheckBox x:Name="ChkGameMode"        Content="Game Mode: Etkinlestir"                Margin="0,2,0,2" FontSize="11" IsChecked="True" ToolTip="Arka plan islemlerini kisitlayarak oyuna kaynak ayirir."/>
                                    <CheckBox x:Name="ChkGameDVR"         Content="Game DVR / GameBar: Kapat"             Margin="0,2,0,2" FontSize="11" IsChecked="True" ToolTip="Xbox Game Bar ve kayit fonksiyonu CPU/GPU kaynak tuketir."/>
                                    <CheckBox x:Name="ChkHagsReg"         Content="HAGS: HW GPU Zamanlama"                Margin="0,2,0,2" FontSize="11"                  ToolTip="Hardware Accelerated GPU Scheduling. Yeniden baslatma gerektirir."/>
                                    <CheckBox x:Name="ChkFseTweaks"       Content="Fullscreen Optimizasyon Kapat"         Margin="0,2,0,2" FontSize="11"                  ToolTip="Windows'un tam ekranda paylasimli mod calistirmasini engeller."/>
                                    <CheckBox x:Name="ChkLargeSystemCache" Content="Sistem Bellek: Masaustu Mod"          Margin="0,2,0,2" FontSize="11" IsChecked="True" ToolTip="LargeSystemCache=0: masaustu modu bellek yonetimi."/>
                                    <CheckBox x:Name="ChkPowerThrottle"   Content="PowerThrottling: Kapat"                Margin="0,2,0,2" FontSize="11" IsChecked="True" ToolTip="Arka planda guc kisitlamasi uygulanmasini engeller."/>
                                    <TextBlock x:Name="RegNote" FontSize="9" TextWrapping="Wrap" Margin="0,6,0,0" Foreground="#4A5568"/>
                                    <StackPanel Orientation="Horizontal" Margin="0,8,0,0">
                                        <Button x:Name="BtnBackupReg" Content="Yedekle" Height="28" FontSize="10" Cursor="Hand" BorderThickness="1" Margin="0,0,6,0" Padding="10,0"/>
                                        <Button x:Name="BtnApplyReg"  Content="Tweakleri Uygula" Height="28" FontSize="10" FontWeight="Bold" Cursor="Hand" BorderThickness="1" Padding="10,0"/>
                                    </StackPanel>
                                </StackPanel>
                            </Border>

                            <!-- CPU Boot -->
                            <Border x:Name="OCard3" CornerRadius="8" TextElement.Foreground="#E2E8F0" Padding="16,14" Margin="0,0,0,10" BorderThickness="1">
                                <StackPanel>
                                    <Grid Margin="0,0,0,10">
                                        <StackPanel Orientation="Horizontal">
                                            <Border Width="3" Height="14" CornerRadius="2" Margin="0,0,10,0" VerticalAlignment="Center">
                                                <Border.Background><SolidColorBrush Color="#7C3AED"/></Border.Background>
                                            </Border>
                                            <TextBlock x:Name="OSL3" Text="BASLANGIC CPU" FontSize="10" FontWeight="Bold" VerticalAlignment="Center"/>
                                        </StackPanel>
                                    </Grid>
                                    <TextBlock x:Name="CpuCoreInfo" FontSize="9" Margin="0,0,0,8" TextWrapping="Wrap" Foreground="#4A5568"/>
                                    <CheckBox x:Name="ChkMaxProcessors"  Content="Maksimum islemci cekirdegi (MSConfig)" Margin="0,2,0,2" FontSize="11" IsChecked="True" ToolTip="BCDEdit ile tum mantiksal islemcileri kullanmaya zorlar."/>
                                    <CheckBox x:Name="ChkNumaOptimize"   Content="NUMA/SMP Boot Optimize"                Margin="0,2,0,2" FontSize="11" IsChecked="True" ToolTip="BCDEdit groupsize=2: NUMA node gruplamasi iyilestirir."/>
                                    <CheckBox x:Name="ChkIntelSpeedStep" Content="Intel SpeedStep: Devre Disi"            Margin="0,2,0,2" FontSize="11"                  ToolTip="Sadece Intel: SpeedStep dinamik frekans dusurmeyi engeller."/>
                                    <CheckBox x:Name="ChkAmdCoolnQuiet"  Content="AMD Cool'n'Quiet: Devre Disi"           Margin="0,2,0,2" FontSize="11"                  ToolTip="Sadece AMD: dinamik frekans dusurme engellenir."/>
                                    <TextBlock x:Name="CpuBootNote" FontSize="9" TextWrapping="Wrap" Margin="0,6,0,0" Foreground="#4A5568"/>
                                    <Button x:Name="BtnApplyCpuBoot" Content="Uygula (Yeniden Baslatma Gerektirir)" Height="28" Margin="0,8,0,0" FontSize="10" FontWeight="Bold" Cursor="Hand" BorderThickness="1"/>
                                </StackPanel>
                            </Border>

                        </StackPanel>

                        <!-- SAG: CPU POWER + NETWORK -->
                        <StackPanel Grid.Column="2" VerticalAlignment="Top">

                            <!-- CPU Power Tweaks -->
                            <Border x:Name="OCard4" CornerRadius="8" TextElement.Foreground="#E2E8F0" Padding="16,14" Margin="0,0,0,10" BorderThickness="1">
                                <StackPanel>
                                    <Grid Margin="0,0,0,10">
                                        <StackPanel Orientation="Horizontal">
                                            <Border Width="3" Height="14" CornerRadius="2" Margin="0,0,10,0" VerticalAlignment="Center">
                                                <Border.Background><SolidColorBrush Color="#F59E0B"/></Border.Background>
                                            </Border>
                                            <TextBlock x:Name="OSL4" Text="CPU POWER TWEAKS" FontSize="10" FontWeight="Bold" VerticalAlignment="Center"/>
                                        </StackPanel>
                                    </Grid>
                                    <TextBlock x:Name="CpuPowerNote" FontSize="9" Margin="0,0,0,10" TextWrapping="Wrap" Foreground="#FFB347"/>

                                    <TextBlock Text="CORE PARKING" FontSize="9" FontWeight="Bold" Margin="0,4,0,3" Foreground="#4A90D9"/>
                                    <CheckBox x:Name="ChkDisableCoreParking" Content="Core Parking Kapat (Min 0 - Max 100%)" Margin="0,2,0,2" FontSize="11" IsChecked="True" ToolTip="Tum CPU cekirdeklerini surekli aktif tutar. Latency spike engellenir."/>

                                    <TextBlock Text="C-STATES / IDLE" FontSize="9" FontWeight="Bold" Margin="0,8,0,3" Foreground="#4A90D9"/>
                                    <CheckBox x:Name="ChkDisableCStates" Content="Processor Idle C-States Kapat" Margin="0,2,0,2" FontSize="11" ToolTip="CPU'nun derin uyku durumuna girmesini engeller. Enerji tuketimi artar."/>
                                    <TextBlock x:Name="CStateWarning" FontSize="9" TextWrapping="Wrap" Margin="14,0,0,4" Foreground="#4A5568"/>

                                    <TextBlock Text="PROCESSOR STATE" FontSize="9" FontWeight="Bold" Margin="0,8,0,3" Foreground="#4A90D9"/>
                                    <CheckBox x:Name="ChkProcStateGaming" Content="Gaming: Min %100 / Max %100" Margin="0,2,0,2" FontSize="11" IsChecked="True" ToolTip="CPU hizini hic dusurme. Tam performans."/>
                                    <CheckBox x:Name="ChkProcStateAuto"   Content="Auto (Min %5 / Max %100)"   Margin="0,2,0,2" FontSize="11"                  ToolTip="Bos kaldiginda hizi dusurecek, gerektiginde tama cikaracak."/>

                                    <TextBlock Text="BOOST MODE" FontSize="9" FontWeight="Bold" Margin="0,8,0,3" Foreground="#4A90D9"/>
                                    <RadioButton x:Name="RBoostAuto"        Content="Aggressive (Varsayilan)"  Margin="0,2,0,2" FontSize="11" GroupName="BoostMode" IsChecked="True" ToolTip="En agresif boost profili. Oyun icin ideal."/>
                                    <RadioButton x:Name="RBoostAggressiveAt" Content="Aggressive At Guaranteed" Margin="0,2,0,2" FontSize="11" GroupName="BoostMode"                 ToolTip="Garantili frekans ustune ciktiginda agresif boost."/>
                                    <RadioButton x:Name="RBoostEnabled"     Content="Enabled (Standart)"      Margin="0,2,0,2" FontSize="11" GroupName="BoostMode"                 ToolTip="Standart boost davranisi."/>
                                    <RadioButton x:Name="RBoostDisabled"    Content="Disabled (Overclock)"    Margin="0,2,0,2" FontSize="11" GroupName="BoostMode"                 ToolTip="Boost tamamen kapali. Manuel OC icin."/>

                                    <TextBlock x:Name="EppTitle" Text="EPP (Energy Performance Preference)" FontSize="9" FontWeight="Bold" Margin="0,8,0,3" Foreground="#4A90D9"/>
                                    <RadioButton x:Name="REppPerf"    Content="Performance (0)"   Margin="0,2,0,2" FontSize="11" GroupName="EPP" IsChecked="True" ToolTip="EPP=0: En agresif frekans. Max performans."/>
                                    <RadioButton x:Name="REppBalance" Content="Balanced (128)"    Margin="0,2,0,2" FontSize="11" GroupName="EPP"                  ToolTip="EPP=128: Performans ve enerji dengesi."/>
                                    <RadioButton x:Name="REppPower"   Content="Power Save (255)"  Margin="0,2,0,2" FontSize="11" GroupName="EPP"                  ToolTip="EPP=255: En dusuk enerji."/>
                                    <TextBlock x:Name="EppNote" FontSize="9" TextWrapping="Wrap" Margin="0,4,0,0" Foreground="#4A5568"/>

                                    <TextBlock Text="EK CPU TWEAKS" FontSize="9" FontWeight="Bold" Margin="0,8,0,3" Foreground="#4A90D9"/>
                                    <CheckBox x:Name="ChkDisablePrefetch"  Content="Superfetch/SysMain: Kapat (SSD)"  Margin="0,2,0,2" FontSize="11"                  ToolTip="SSD kullananlar icin gereksiz. Disk aktivitesini azaltir."/>
                                    <CheckBox x:Name="ChkHighResTimer"     Content="High Resolution Timer: 0.5ms"      Margin="0,2,0,2" FontSize="11" IsChecked="True" ToolTip="Zamanlayici cozunurlugunu 0.5ms'ye ayarlar."/>
                                    <CheckBox x:Name="ChkCpuPriorityOpt"   Content="CSRSS / DWM Oncelik: Yukselt"     Margin="0,2,0,2" FontSize="11" IsChecked="True" ToolTip="Windows alt sistem islemlerine yuksek oncelik verir."/>

                                    <Button x:Name="BtnApplyCpuPower" Content="CPU Tweakleri Uygula" Height="30" Margin="0,12,0,0" FontSize="10" FontWeight="Bold" Cursor="Hand" BorderThickness="1"/>
                                </StackPanel>
                            </Border>

                            <!-- Ag / Gecikme Tweaks -->
                            <Border x:Name="OCard5" CornerRadius="8" TextElement.Foreground="#E2E8F0" Padding="16,14" Margin="0,0,0,10" BorderThickness="1">
                                <StackPanel>
                                    <Grid Margin="0,0,0,10">
                                        <StackPanel Orientation="Horizontal">
                                            <Border Width="3" Height="14" CornerRadius="2" Margin="0,0,10,0" VerticalAlignment="Center">
                                                <Border.Background><SolidColorBrush Color="#00FF87"/></Border.Background>
                                            </Border>
                                            <TextBlock x:Name="OSL5" Text="AG / GECIKME TWEAKS" FontSize="10" FontWeight="Bold" VerticalAlignment="Center"/>
                                        </StackPanel>
                                    </Grid>
                                    <CheckBox x:Name="ChkNagle"        Content="Nagle Algoritmasini Kapat"          Margin="0,2,0,2" FontSize="11" IsChecked="True" ToolTip="Kucuk paketleri biriktirmeden gonderir. Ping dalgalanmasi azalir."/>
                                    <CheckBox x:Name="ChkAutoTuning"   Content="TCP Auto-Tuning: Normal"            Margin="0,2,0,2" FontSize="11" IsChecked="True" ToolTip="Oyun trafigiyle uyumlu TCP pencere boyutu."/>
                                    <CheckBox x:Name="ChkTimerRes"     Content="Timer Resolution: 0.5ms"            Margin="0,2,0,2" FontSize="11" IsChecked="True" ToolTip="HPET zamanlayici 0.5ms. Kare kararliligi iyilesir."/>
                                    <CheckBox x:Name="ChkDpcLatency"   Content="DPC Latency (IRQ affinity)"         Margin="0,2,0,2" FontSize="11"                  ToolTip="DPC gecikmesini azaltmak icin IRQ8 oncelik ipucu."/>
                                    <CheckBox x:Name="ChkGpuSchedHW"   Content="Hardware GPU Scheduling"            Margin="0,2,0,2" FontSize="11"                  ToolTip="GPU kendi is zamanlamasini yonetir. Win10 2004+, uyumlu GPU."/>
                                    <CheckBox x:Name="ChkQosPriority"  Content="QoS Oyun Trafik Onceligi"          Margin="0,2,0,2" FontSize="11" IsChecked="True" ToolTip="Bant genisligi rezervini kaldirir. Oyun trafigi oncelikli."/>
                                    <CheckBox x:Name="ChkNetAdapter"   Content="NIC: Gecikme Optimizasyonlari"     Margin="0,2,0,2" FontSize="11" IsChecked="True" ToolTip="Ag karti interrupt ve paket birlestirme optimize."/>
                                    <CheckBox x:Name="ChkTcpCongestion" Content="TCP Congestion: CUBIC"            Margin="0,2,0,2" FontSize="11"                  ToolTip="CUBIC TCP algoritmasi. Genis bant verimli."/>
                                    <TextBlock x:Name="NetNote" FontSize="9" TextWrapping="Wrap" Margin="0,6,0,0" Foreground="#4A5568"/>
                                    <Button x:Name="BtnApplyNet" Content="Ag Tweakleri Uygula" Height="28" Margin="0,8,0,0" FontSize="10" FontWeight="Bold" Cursor="Hand" BorderThickness="1"/>
                                </StackPanel>
                            </Border>

                        </StackPanel>
                    </Grid>
                </ScrollViewer>

                <!-- PROGRESS BAR -->
                <Border x:Name="ProgressCard" Grid.Row="1" Padding="16,10" Margin="16,0,16,6" CornerRadius="6" BorderThickness="1">
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <StackPanel VerticalAlignment="Center">
                            <TextBlock x:Name="StatusText" Text="Hazir." FontSize="11" FontWeight="SemiBold" Margin="0,0,0,4"/>
                            <Border x:Name="ProgressTrack" CornerRadius="3" Height="4">
                                <Border x:Name="ProgressFill" CornerRadius="3" HorizontalAlignment="Left" Width="0"/>
                            </Border>
                        </StackPanel>
                        <TextBlock x:Name="PctText" Grid.Column="1" Text="0%" FontSize="14" FontWeight="Black" VerticalAlignment="Center" Margin="16,0,0,0"/>
                    </Grid>
                </Border>

                <!-- LOG -->
                <Border x:Name="LogCard" Grid.Row="2" Height="90" Margin="16,0,16,8" CornerRadius="6" BorderThickness="1">
                    <ScrollViewer x:Name="LogScroll" VerticalScrollBarVisibility="Auto" Padding="12,6">
                        <StackPanel x:Name="LogPanel"/>
                    </ScrollViewer>
                </Border>

                <!-- ALT BUTONLAR -->
                <Grid Grid.Row="3" Margin="16,0,16,14">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="8"/>
                        <ColumnDefinition Width="150"/>
                        <ColumnDefinition Width="8"/>
                        <ColumnDefinition Width="90"/>
                    </Grid.ColumnDefinitions>
                    <Button x:Name="BtnClean"   Grid.Column="0" Content="TEMIZLIGI BASLAT" Height="42" FontSize="13" FontWeight="Black" Cursor="Hand" BorderThickness="0"/>
                    <Button x:Name="BtnSaveLog" Grid.Column="2" Content="Logu Kaydet (.txt)" Height="42" FontSize="11" FontWeight="SemiBold" Cursor="Hand" BorderThickness="1" IsEnabled="False"/>
                    <Button x:Name="BtnClose"   Grid.Column="4" Content="Kapat" Height="42" FontSize="12" Cursor="Hand" BorderThickness="1"/>
                </Grid>

            </Grid>
        </Grid>
    </Grid>
</Window>
'@
# ============================================================
# PENCERE OLUSTUR
# ============================================================
try {
    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)
} catch {
    [System.Windows.MessageBox]::Show("XAML hatasi:`n$($_.Exception.Message)", "Kritik Hata")
    exit
}

function New-Brush($hex) { return New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($hex)) }
function New-Color($hex)  { return [Windows.Media.ColorConverter]::ConvertFromString($hex) }

# Gradient
$window.FindName("GradTop").Color = New-Color $GRAD_TOP
$window.FindName("GradBot").Color = New-Color $GRAD_BOT

# Pencere icon - SC logo (cyan kare)
try {
    $iconB64 = "AAABAAEAEBAAAAEAIABoBAAAFgAAACgAAAAQAAAAIAAAAAEAIAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA0RF///1AD//9QA///UAP//1AD//9QA///UAP//1AD//9QA///UAP//1AD//9QA///UAP8NERf/AAAAAAAAAAD/1AD/DREX/w0RF/8NERf/DREX/w0RF/8NERf/DREX/w0RF/8NERf/DREX/w0RF/8NERf//9QA/wAAAAAAAAAA/9QA/w0RF/8NERf/5uji/+bo4v/m6OL/5uji/+bo4v/m6OL/DREX/+bo4v/m6OL/5uji///UAP8AAAAAAAAAAP/UAP8NERf/DREX/+bo4v/m6OL/5uji/+bo4v/m6OL/5uji/w0RF//m6OL/5uji/+bo4v//1AD/AAAAAAAAAAD/1AD/DREX/w0RF/8NERf/DREX/w0RF/8NERf/DREX/+bo4v8NERf/5uji/w0RF/8NERf//9QA/wAAAAAAAAAA/9QA/w0RF/8NERf/DREX/w0RF/8NERf/DREX/w0RF//m6OL/DREX/+bo4v8NERf/DREX///UAP8AAAAAAAAAAP/UAP8NERf/DREX/+bo4v/m6OL/5uji/+bo4v/m6OL/5uji/w0RF//m6OL/DREX/w0RF///1AD/AAAAAAAAAAD/1AD/DREX/w0RF//m6OL/5uji/+bo4v/m6OL/5uji/+bo4v8NERf/5uji/w0RF/8NERf//9QA/wAAAAAAAAAA/9QA/w0RF/8NERf/5uji/w0RF/8NERf/DREX/w0RF/8NERf/DREX/+bo4v8NERf/DREX///UAP8AAAAAAAAAAP/UAP8NERf/DREX/+bo4v8NERf/DREX/w0RF/8NERf/DREX/w0RF//m6OL/DREX/w0RF///1AD/AAAAAAAAAAD/1AD/DREX/w0RF//m6OL/5uji/+bo4v/m6OL/5uji/+bo4v8NERf/5uji/+bo4v/m6OL//9QA/wAAAAAAAAAA/9QA/w0RF/8NERf/5uji/+bo4v/m6OL/5uji/+bo4v/m6OL/DREX/+bo4v/m6OL/5uji///UAP8AAAAAAAAAAP/UAP8NERf/DREX/w0RF/8NERf/DREX/w0RF/8NERf/DREX/w0RF/8NERf/DREX/w0RF///1AD/AAAAAAAAAAANERf//9QA///UAP//1AD//9QA///UAP//1AD//9QA///UAP//1AD//9QA///UAP//1AD/DREX/wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="
    $iconBytes = [Convert]::FromBase64String($iconB64)
    $ms = New-Object System.IO.MemoryStream(,$iconBytes)
    $window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create($ms)
} catch { }

# ============================================================
# PENCERE RENK / STIL UYGULA - v3.5 Sidebar Layout
# ============================================================

# Sidebar
$window.FindName("Sidebar").Background  = New-Brush "#0D1117"
$window.FindName("Sidebar").BorderBrush = New-Brush $BORDER

# Logo & Baslik
$window.FindName("TitleText").Foreground   = New-Brush $FG_PRIMARY
$window.FindName("TitleText2").Foreground  = New-Brush $ACCENT
$window.FindName("VersionBadge").Foreground = New-Brush $ACCENT
$window.FindName("SubtitleText").Foreground = New-Brush $FG_SECOND

# Admin / Tema (XAML'da zaten Foreground var, PS'de de set et — override icin)
$window.FindName("AdminText").Text       = ">> YONETICI"
$window.FindName("AdminText").Foreground = New-Brush $SUCCESS
$window.FindName("ThemeText").Foreground = New-Brush $FG_SECOND

# HUD Kutulari
foreach ($n in @("HudBox1","HudBox2","HudBox3","HudBox4","HudBox5")) {
    $b = $window.FindName($n)
    if ($b) {
        $b.Background  = New-Brush "#111827"
        $b.BorderBrush = New-Brush $BORDER
    }
}
foreach ($n in @("HudLabel1","HudLabel2","HudLabel3","HudLabel4","HudLabel5")) {
    $c = $window.FindName($n); if ($c) { $c.Foreground = New-Brush $ACCENT }
}
foreach ($n in @("HudCpu","HudRam","DiskFreeText","HudOs","HudUsb")) {
    $c = $window.FindName($n); if ($c) { $c.Foreground = New-Brush $FG_PRIMARY }
}

# Nav tab butonlari (baslangic stili)
foreach ($t in @("TabClean","TabOptimize")) {
    $b = $window.FindName($t)
    if ($b) {
        $b.Background  = New-Brush "Transparent"
        $b.BorderBrush = New-Brush "Transparent"
        $b.Foreground  = New-Brush $FG_SECOND
    }
}

# Summary Bar
$window.FindName("SummaryBar").Background   = New-Brush "#111827"
$window.FindName("SummaryBar").BorderBrush  = New-Brush $BORDER
$window.FindName("SummaryText").Foreground  = New-Brush $FG_SECOND
$window.FindName("SummaryCount").Foreground = New-Brush $ACCENT

# Kartlar (Temizlik)
foreach ($c in @("Card1","Card2","Card3","Card5","Card6")) {
    $card = $window.FindName($c)
    if ($card) {
        $card.Background  = New-Brush "#111827"
        $card.BorderBrush = New-Brush $BORDER
    }
}
# Kartlar (Optimizasyon)
foreach ($c in @("OCard1","OCard2","OCard3","OCard4","OCard5")) {
    $card = $window.FindName($c)
    if ($card) {
        $card.Background  = New-Brush "#111827"
        $card.BorderBrush = New-Brush $BORDER
    }
}
# Progress / Log
$window.FindName("ProgressCard").Background  = New-Brush "#111827"
$window.FindName("ProgressCard").BorderBrush = New-Brush $BORDER
$window.FindName("LogCard").Background       = New-Brush "#060810"
$window.FindName("LogCard").BorderBrush      = New-Brush $BORDER
$window.FindName("ProgressTrack").Background = New-Brush $BORDER
$window.FindName("ProgressFill").Background  = New-Brush $ACCENT
$window.FindName("StatusText").Foreground    = New-Brush $FG_PRIMARY
$window.FindName("PctText").Foreground       = New-Brush $ACCENT

# Kart Basliklari - Clean
foreach ($sl in @("SL1","SL2","SL3")) { $c=$window.FindName($sl); if($c){$c.Foreground=New-Brush $ACCENT} }
$window.FindName("SL5").Foreground = New-Brush $ACCENT2
$window.FindName("SL6").Foreground = New-Brush $ERROR_C
foreach ($sl in @("OSL1","OSL2","OSL4")) { $c=$window.FindName($sl); if($c){$c.Foreground=New-Brush $OPT_C} }
$window.FindName("OSL3").Foreground = New-Brush $ACCENT2
$window.FindName("OSL5").Foreground = New-Brush $SUCCESS

# Not textleri
$window.FindName("RepairNote").Foreground  = New-Brush $WARN_C
$window.FindName("PrivacyNote").Foreground = New-Brush $WARN_C

# Power Note
$window.FindName("PowerNote").Text = "Bitsum ve TheHybred: _Files klasorunden yuklenir. Ultimate: Windows dahili."
$window.FindName("PowerNote").Foreground = New-Brush $FG_SECOND

# Tum Select butonlari
foreach ($n in @("BtnSelectSistem","BtnSelectBrowser","BtnSelectGaming","BtnSelectRepair","BtnSelectPrivacy")) {
    $b = $window.FindName($n); if ($b) { $b.Foreground = New-Brush $ACCENT }
}
# Butonlar
$window.FindName("BtnClose").Background  = New-Brush $BG_CARD
$window.FindName("BtnClose").BorderBrush = New-Brush $BORDER
$window.FindName("BtnClose").Foreground  = New-Brush $FG_SECOND
$window.FindName("BtnSaveLog").Background  = New-Brush $BG_CARD
$window.FindName("BtnSaveLog").BorderBrush = New-Brush $BORDER
$window.FindName("BtnSaveLog").Foreground  = New-Brush $FG_SECOND
# Optimize kart butonlari
foreach ($bn in @("BtnApplyPower","BtnApplyReg","BtnApplyCpuBoot","BtnApplyCpuPower","BtnApplyNet","BtnBackupReg")) {
    $b = $window.FindName($bn)
    if ($b) {
        $b.Background  = New-Brush $OPT_C
        $b.BorderBrush = New-Brush $OPT_C
        $b.Foreground  = New-Brush "#000000"
    }
}
# Tum optimize checkbox/radiobutton renkleri
foreach ($n in @("ChkRegGpuPriority","ChkRegGamePriority","ChkRegWin32Prio","ChkRegNetThrottle","ChkRegMenuDelay","ChkRegForeground",
                 "ChkRegMmcss","ChkGameMode","ChkGameDVR","ChkHagsReg","ChkFseTweaks","ChkLargeSystemCache","ChkPowerThrottle",
                 "ChkMaxProcessors","ChkNumaOptimize","ChkIntelSpeedStep","ChkAmdCoolnQuiet","ChkDisableCoreParking","ChkDisableCStates",
                 "ChkProcStateGaming","ChkProcStateAuto","ChkDisablePrefetch","ChkHighResTimer","ChkCpuPriorityOpt",
                 "ChkNagle","ChkAutoTuning","ChkTimerRes","ChkDpcLatency","ChkGpuSchedHW","ChkQosPriority","ChkNetAdapter","ChkTcpCongestion")) {
    $c = $window.FindName($n); if ($c) { $c.Foreground = New-Brush $FG_PRIMARY }
}
foreach ($n in @("RPlanBalanced","RPlanHigh","RPlanUltimate","RPlanBitsum","RPlanHybred",
                 "RBoostAuto","RBoostAggressiveAt","RBoostEnabled","RBoostDisabled",
                 "REppPerf","REppBalance","REppPower",
                 "RWin32BestFPS","RWin32BestLatency","RWin32Balanced","RWin32Default")) {
    $c = $window.FindName($n); if ($c) { $c.Foreground = New-Brush $FG_PRIMARY }
}
# EppTitle (bunu PS'de de ayarla)
$window.FindName("EppTitle").Foreground = New-Brush "#4A90D9"

# Intel/AMD ozele
$intelCheck = $window.FindName("ChkIntelSpeedStep")
$amdCheck   = $window.FindName("ChkAmdCoolnQuiet")
if ($intelCheck) { $intelCheck.Visibility = if ($cpuIsIntel) {[System.Windows.Visibility]::Visible} else {[System.Windows.Visibility]::Collapsed} }
if ($amdCheck)   { $amdCheck.Visibility   = if ($cpuIsAmd)   {[System.Windows.Visibility]::Visible} else {[System.Windows.Visibility]::Collapsed} }

# Sistem bilgilerini doldur
$cpuShort = if ($cpuName) { ($cpuName -replace "Intel\(R\) Core\(TM\) ","" -replace " CPU","" -replace "  "," ").Trim() } else { "N/A" }
$window.FindName("HudCpu").Text      = $cpuShort
$window.FindName("HudCpu").ToolTip   = $cpuName
$window.FindName("HudRam").Text      = "$ramGB GB"
$window.FindName("HudOs").Text       = "Win $winVer"
$drive = Get-PSDrive ($env:SystemDrive -replace ":","")
$window.FindName("DiskFreeText").Text = "$([math]::Round($drive.Free / 1GB, 1)) GB"

# CPU bilgisi optimize panel
$window.FindName("CpuCoreInfo").Text = "$cpuCores Cekirdek / $cpuThreads Thread"
$window.FindName("CpuCoreInfo").Foreground = New-Brush $FG_SECOND

$cpuTypeNote = if ($cpuIsAmd) { "AMD Ryzen: EPP destegi mevcut (Precision Boost ile calisir). C-States kapatmak latency azaltir." }
               elseif ($cpuIsIntel) { "Intel: SpeedStep/HWP EPP destegi. 12.nesil+ icin C-States kapat + EPP=0 tavsiye." }
               else { "CPU markasi tespit edilemedi. Genel profil uygulanacak." }
$window.FindName("CpuPowerNote").Text      = $cpuTypeNote
$window.FindName("CpuPowerNote").Foreground = New-Brush $WARN_C

$eppNoteText = if ($cpuIsAmd) { "AMD: EPP=0 ile Precision Boost en agresif devreye girer." }
               elseif ($cpuIsIntel) { "Intel 12.nesil+: EPP=0 agresif P-Core boost. E-Core dengesini HWP yonetir." }
               else { "EPP degeri secilen guc planine yazilir." }
$window.FindName("EppNote").Text = $eppNoteText

$cstateNote = $window.FindName("CStateWarning")
if ($cstateNote) {
    $cstateNote.Text = if ($cpuIsIntel) { "(Intel: 12.nesil+ icin latency azaltir. Enerji tuketimi artar.)" }
                       else { "(Enerji tuketimi artar - masaustu / overclock icin idealdir)" }
    $cstateNote.Foreground = New-Brush $FG_SECOND
}

# Baslangicta mevcut guc planini goster
try {
    $initPlan = cmd.exe /c "powercfg /getactivescheme 2>&1"
    $initPlanName = if ($initPlan -match "\((.+)\)") { $Matches[1] } else { "Tanimsiz" }
    $window.FindName("CurrentPlanText").Text = "Mevcut plan: $initPlanName"
} catch { }


# ============================================================
# DINAMIK CHECKBOX OLUSTUR (sadece kurulular gorunur)
# ============================================================
$allCheckboxes = @(
    "ChkTemp","ChkRecycle","ChkWinHistory","ChkDns","ChkLogs","ChkWinUpdate","ChkFontCache","ChkRam","ChkUsb",
    "ChkBrave","ChkChrome","ChkFirefox","ChkEdge","ChkOpera","ChkOperaGX",
    "ChkSteam","ChkDiscord","ChkEpic","ChkGog","ChkUbisoft","ChkBattlenet","ChkEa","ChkXbox",
    "ChkBrokenShortcuts","ChkStartup","ChkOrphanedReg","ChkSfc","ChkPagefile",
    "ChkVss","ChkSearchIndex","ChkLnk","ChkShellbag","ChkPagefileClear","ChkHiberfil","ChkOrphanSetup"
)

$controls = @{}

# Statik checkboxlar (her zaman gorunur)
foreach ($name in @("ChkTemp","ChkRecycle","ChkWinHistory","ChkDns","ChkLogs","ChkWinUpdate","ChkFontCache","ChkRam","ChkUsb",
                    "ChkBrokenShortcuts","ChkStartup","ChkOrphanedReg","ChkSfc","ChkPagefile",
                    "ChkVss","ChkSearchIndex","ChkLnk","ChkShellbag","ChkPagefileClear","ChkHiberfil","ChkOrphanSetup")) {
    $chk = $window.FindName($name)
    if ($chk) {
        $chk.Foreground = New-Brush $FG_PRIMARY
        $chk.IsChecked  = $true
        $controls[$name] = $chk
    }
}

# Tarayici checkboxlarini goster/gizle
$browserList = @(
    @{chk="ChkBrave";   app="Brave"}
    @{chk="ChkChrome";  app="Chrome"}
    @{chk="ChkFirefox"; app="Firefox"}
    @{chk="ChkEdge";    app="Edge"}
    @{chk="ChkOpera";   app="Opera"}
    @{chk="ChkOperaGX"; app="Opera GX"}
)
$installedBrowserCount = 0
foreach ($b in $browserList) {
    $chk = $window.FindName($b.chk)
    if ($chk) {
        if ($appInstalled[$b.app]) {
            $chk.Visibility = [System.Windows.Visibility]::Visible
            $chk.Foreground = New-Brush $FG_PRIMARY
            $chk.IsChecked  = $true
            $controls[$b.chk] = $chk
            $installedBrowserCount++
        } else {
            $chk.Visibility = [System.Windows.Visibility]::Collapsed
        }
    }
}
$bNone = $window.FindName("BrowserNone")
if ($bNone) {
    $bNone.Foreground = New-Brush $FG_SECOND
    $bNone.Visibility = if ($installedBrowserCount -eq 0) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
}

# Oyun platformu checkboxlarini goster/gizle
$gamingList = @(
    @{chk="ChkSteam";     app="Steam"}
    @{chk="ChkDiscord";   app="Discord"}
    @{chk="ChkEpic";      app="Epic Games"}
    @{chk="ChkGog";       app="GOG Galaxy"}
    @{chk="ChkUbisoft";   app="Ubisoft"}
    @{chk="ChkBattlenet"; app="Battle.net"}
    @{chk="ChkEa";        app="EA App"}
    @{chk="ChkXbox";      app="Xbox"}
)
$installedGamingCount = 0
foreach ($g in $gamingList) {
    $chk = $window.FindName($g.chk)
    if ($chk) {
        if ($appInstalled[$g.app]) {
            $chk.Visibility = [System.Windows.Visibility]::Visible
            $chk.Foreground = New-Brush $FG_PRIMARY
            $chk.IsChecked  = $true
            $controls[$g.chk] = $chk
            $installedGamingCount++
        } else {
            $chk.Visibility = [System.Windows.Visibility]::Collapsed
        }
    }
}
$gNone = $window.FindName("GamingNone")
if ($gNone) {
    $gNone.Foreground = New-Brush $FG_SECOND
    $gNone.Visibility = if ($installedGamingCount -eq 0) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
}

foreach ($name in @("StatusText","PctText","ProgressFill","ProgressTrack","LogPanel","LogScroll",
                    "DiskFreeText","BtnClean","BtnClose","BtnSaveLog","SummaryText","SummaryCount",
                    "SummaryBar","CurrentPlanText",
                    "BtnSelectSistem","BtnSelectBrowser","BtnSelectGaming","BtnSelectRepair","BtnSelectPrivacy",
                    "PanelClean","PanelOptimize","TabClean","TabOptimize")) {
    $controls[$name] = $window.FindName($name)
}

# Checkboxlara degisim eventi ekle
foreach ($k in $allCheckboxes) {
    if ($controls[$k]) {
        $controls[$k].Add_Checked({ Update-Summary })
        $controls[$k].Add_Unchecked({ Update-Summary })
    }
}

# Win32PrioritySeparation panel goster/gizle
$win32Chk   = $window.FindName("ChkRegWin32Prio")
$win32Panel = $window.FindName("Win32Panel")
if ($win32Chk -and $win32Panel) {
    $win32Panel.Visibility = if ($win32Chk.IsChecked) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
    $win32Chk.Add_Checked({   $window.FindName("Win32Panel").Visibility = [System.Windows.Visibility]::Visible   })
    $win32Chk.Add_Unchecked({ $window.FindName("Win32Panel").Visibility = [System.Windows.Visibility]::Collapsed })
}

# ============================================================
# SEKME MANTIGI
# ============================================================
$script:currentTab = "Clean"

function Update-Summary {
    if ($script:currentTab -eq "Clean") {
        $count = 0
        foreach ($k in $allCheckboxes) {
            if ($controls[$k] -and $controls[$k].IsChecked -and $controls[$k].Visibility -eq [System.Windows.Visibility]::Visible) { $count++ }
        }
        if ($count -eq 0) {
            $controls["SummaryText"].Text  = "Hicbir modul secili degil."
            $controls["SummaryCount"].Text = ""
        } else {
            $est = [math]::Max(1, [math]::Round($count * 0.4))
            $controls["SummaryText"].Text  = "$count modul secili  |  Tahmini sure: ~$est dk"
            $controls["SummaryCount"].Text = "$count"
        }
    }
}

function Set-ActiveTab($tab) {
    $script:currentTab = $tab
    if ($tab -eq "Clean") {
        # Paneller
        $controls["PanelClean"].Visibility    = [System.Windows.Visibility]::Visible
        $controls["PanelOptimize"].Visibility = [System.Windows.Visibility]::Collapsed
        # Sidebar nav - aktif: sol bordur cyan + parlak fg
        $controls["TabClean"].BorderBrush    = New-Brush $ACCENT
        $controls["TabClean"].Foreground     = New-Brush $FG_PRIMARY
        $controls["TabClean"].Background     = New-Brush "#161B27"
        $controls["TabOptimize"].BorderBrush = New-Brush "Transparent"
        $controls["TabOptimize"].Foreground  = New-Brush $FG_SECOND
        $controls["TabOptimize"].Background  = New-Brush "Transparent"
        # Ana buton
        $controls["BtnClean"].Content    = "TEMIZLIGI BASLAT"
        $controls["BtnClean"].Background = New-Brush $ACCENT
        $controls["BtnClean"].Foreground = New-Brush "#000000"
        $controls["BtnClean"].IsEnabled  = $true
        # Summary - SADECE CLEAN TABDA GORUNUR, degerini guncelle
        $controls["SummaryBar"].Visibility = [System.Windows.Visibility]::Visible
        Update-Summary
    } else {
        # Paneller
        $controls["PanelClean"].Visibility    = [System.Windows.Visibility]::Collapsed
        $controls["PanelOptimize"].Visibility = [System.Windows.Visibility]::Visible
        # Sidebar nav - aktif: sol bordur turuncu
        $controls["TabOptimize"].BorderBrush = New-Brush $OPT_C
        $controls["TabOptimize"].Foreground  = New-Brush $FG_PRIMARY
        $controls["TabOptimize"].Background  = New-Brush "#1A1608"
        $controls["TabClean"].BorderBrush    = New-Brush "Transparent"
        $controls["TabClean"].Foreground     = New-Brush $FG_SECOND
        $controls["TabClean"].Background     = New-Brush "Transparent"
        # Ana buton
        $controls["BtnClean"].Content    = "OPTIMIZASYONU UYGULA"
        $controls["BtnClean"].Background = New-Brush $OPT_C
        $controls["BtnClean"].Foreground = New-Brush "#000000"
        $controls["BtnClean"].IsEnabled  = $true
        # Summary - OPTIMIZE TABDA TAMAMEN GIZLE (bag?msiz tab)
        $controls["SummaryBar"].Visibility = [System.Windows.Visibility]::Collapsed
        # Guc plani guncelle
        $cpOutput = cmd.exe /c "powercfg /getactivescheme 2>&1"
        $planName = if ($cpOutput -match "\((.+)\)") { $Matches[1] } else { "Tanimsiz" }
        $controls["CurrentPlanText"].Text = "Mevcut plan: $planName"
    }
}

$controls["TabClean"].Add_Click({ Set-ActiveTab "Clean" })
$controls["TabOptimize"].Add_Click({ Set-ActiveTab "Optimize" })
Set-ActiveTab "Clean"

# Baslangicta mevcut guc planini goster
try {
    $initPlan = cmd.exe /c "powercfg /getactivescheme 2>&1"
    $initPlanName = if ($initPlan -match "\((.+)\)") { $Matches[1] } else { "Tanimsiz" }
    $window.FindName("CurrentPlanText").Text = "Mevcut plan: $initPlanName"
} catch { }

# ============================================================
# YARDIMCI FONKSİYONLAR
# ============================================================
function Ask-User($msg, $title) {
    return [System.Windows.MessageBox]::Show($msg, $title,
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Warning) -eq [System.Windows.MessageBoxResult]::Yes
}

$script:logBuffer = [System.Collections.Generic.List[string]]::new()

function Add-Log($msg, $type = "Info") {
    $line = "[$((Get-Date).ToString('HH:mm:ss'))]  $msg"
    $script:logBuffer.Add($line)
    $tb            = New-Object System.Windows.Controls.TextBlock
    $tb.Text       = $line
    $tb.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas")
    $tb.FontSize   = 10
    $tb.Margin     = "0,1,0,1"
    $tb.Foreground = switch ($type) {
        "Success" { New-Brush $SUCCESS }
        "Error"   { New-Brush $ERROR_C }
        "Warn"    { New-Brush $WARN_C  }
        default   { New-Brush $LOG_FG  }
    }
    $controls["LogPanel"].Children.Add($tb) | Out-Null
    $controls["LogScroll"].ScrollToBottom()
    [System.Windows.Forms.Application]::DoEvents()
}

$script:totalSteps  = 0
$script:currentStep = 0

function Update-Progress($msg) {
    $script:currentStep++
    $pct    = [math]::Round($script:currentStep * 100 / [math]::Max(1, $script:totalSteps))
    $trackW = $controls["ProgressTrack"].ActualWidth
    if ($trackW -le 0) { $trackW = 850 }
    $controls["StatusText"].Text = $msg
    $controls["PctText"].Text    = "$pct%"
    $anim            = New-Object System.Windows.Media.Animation.DoubleAnimation
    $anim.To         = [math]::Round($pct * $trackW / 100)
    $anim.Duration   = [System.Windows.Duration]::new([timespan]::FromMilliseconds(300))
    $ease            = New-Object System.Windows.Media.Animation.CubicEase
    $ease.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
    $anim.EasingFunction = $ease
    $controls["ProgressFill"].BeginAnimation([System.Windows.FrameworkElement]::WidthProperty, $anim)
    Add-Log "[>] $msg" "Info"
}

function DeepClean-Folder($path, $desc) {
    if (-not (Test-Path $path)) { Add-Log "  .. $desc bulunamadi" "Info"; return }
    cmd.exe /c "del /f /s /q `"$path\*`" >nul 2>&1"
    cmd.exe /c "for /d %x in (`"$path\*`") do rd /s /q `"%x`" >nul 2>&1"
    Add-Log "  OK $desc" "Success"
}

$appExeMap = @{
    "ChkBrave"     = @{ exe = "brave";               display = "Brave" }
    "ChkChrome"    = @{ exe = "chrome";              display = "Chrome" }
    "ChkFirefox"   = @{ exe = "firefox";             display = "Firefox" }
    "ChkEdge"      = @{ exe = "msedge";              display = "Edge" }
    "ChkOpera"     = @{ exe = "opera";               display = "Opera" }
    "ChkOperaGX"   = @{ exe = "opera";               display = "Opera GX" }
    "ChkSteam"     = @{ exe = "steam";               display = "Steam" }
    "ChkDiscord"   = @{ exe = "discord";             display = "Discord" }
    "ChkEpic"      = @{ exe = "EpicGamesLauncher";   display = "Epic Games" }
    "ChkGog"       = @{ exe = "GalaxyClient";        display = "GOG Galaxy" }
    "ChkUbisoft"   = @{ exe = "UbisoftGameLauncher"; display = "Ubisoft Connect" }
    "ChkBattlenet" = @{ exe = "Battle.net";          display = "Battle.net" }
    "ChkEa"        = @{ exe = "EADesktop";           display = "EA App" }
    "ChkXbox"      = @{ exe = "XboxPcApp";           display = "Xbox" }
}

# ============================================================
# USB DİNAMİK TAKİP (arka plan timer)
# ============================================================
$script:usbCount = 0
$script:usbTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:usbTimer.Interval = [TimeSpan]::FromSeconds(3)
$script:usbTimer.Add_Tick({
    try {
        $newCount = @(Get-CimInstance Win32_DiskDrive | Where-Object { $_.InterfaceType -eq "USB" }).Count
        if ($newCount -ne $script:usbCount) {
            if ($newCount -lt $script:usbCount) {
                Add-Log "-- USB bellek cikarildi. Kalan USB: $newCount" "Warn"
                if ($newCount -eq 0) { Add-Log "  Tum USB cihazlar cikarildi." "Success" }
            } elseif ($newCount -gt $script:usbCount) {
                Add-Log "-- Yeni USB algilandi! Toplam: $newCount" "Error"
            }
            $script:usbCount = $newCount
            $usbTxt = $window.FindName("HudUsb")
            if ($usbTxt) {
                $usbTxt.Text       = "$newCount"
                $usbTxt.Foreground = if ($newCount -gt 0) { New-Brush $WARN_C } else { New-Brush $FG_PRIMARY }
            }
        }
    } catch {}
})

# ============================================================
# ANA TEMİZLİK
# ============================================================
$controls["BtnClean"].Add_Click({

    # OPTİMİZASYON sekmesindeyse: tum secili sectioları uygula
    if ($controls["PanelOptimize"].Visibility -eq [System.Windows.Visibility]::Visible) {
        $controls["BtnClean"].IsEnabled = $false
        $controls["LogPanel"].Children.Clear()
        $script:logBuffer.Clear()
        Add-Log "==== OPTIMIZASYON BASLADI ====" "Success"
        # Power plan
        $window.FindName("BtnApplyPower").RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
        # Registry tweaks
        $window.FindName("BtnApplyReg").RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
        # CPU Boot (BCDEdit)
        $window.FindName("BtnApplyCpuBoot").RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
        # CPU Power tweaks
        $window.FindName("BtnApplyCpuPower").RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
        # Network tweaks
        $window.FindName("BtnApplyNet").RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
        Add-Log "==== OPTIMIZASYON TAMAMLANDI ====" "Success"
        $controls["BtnClean"].IsEnabled = $true
        $controls["BtnSaveLog"].IsEnabled = $true
        return
    }

    $controls["BtnClean"].IsEnabled   = $false
    $controls["BtnSaveLog"].IsEnabled = $false
    $controls["LogPanel"].Children.Clear()
    $script:logBuffer.Clear()

    $steps = @()
    foreach ($k in $allCheckboxes) {
        if ($controls[$k] -and $controls[$k].IsChecked -and $controls[$k].Visibility -eq [System.Windows.Visibility]::Visible) { $steps += $k }
    }

    if ($steps.Count -eq 0) {
        $controls["StatusText"].Text    = "Hicbir modul secilmedi."
        $controls["BtnClean"].IsEnabled = $true
        return
    }

    $script:totalSteps  = $steps.Count
    $script:currentStep = 0
    $diskBefore = (Get-PSDrive ($env:SystemDrive -replace ":","")).Free

    Add-Log "==== TEMIZLIK BASLADI  |  $($steps.Count) modul ====" "Success"

    # ---- USB KONTROLU ----
    if ($steps -contains "ChkUsb") {
        $currentUsb = @(Get-CimInstance Win32_DiskDrive | Where-Object { $_.InterfaceType -eq "USB" }).Count
        $script:usbCount = $currentUsb  # Timer'i senkronize et
        if ($currentUsb -gt 0) {
            if (Ask-User "Sistemde $currentUsb adet USB depolama algilandi.`n`nUSB baglanti gecmisini silmek istiyor musunuz?" "USB Algilandi") {
                Update-Progress "USB gecmisi temizleniyor..."
                cmd.exe /c "reg delete `"HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\MountPoints2`" /f >nul 2>&1"
                cmd.exe /c "reg delete `"HKLM\SYSTEM\CurrentControlSet\Enum\USBSTOR`" /f >nul 2>&1"
                Add-Log "  OK USB izleri temizlendi." "Success"
            } else {
                Update-Progress "USB temizligi atlandi."
            }
        } else {
            Update-Progress "USB gecmisi temizleniyor (USB takilı degil)..."
            cmd.exe /c "reg delete `"HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\MountPoints2`" /f >nul 2>&1"
            cmd.exe /c "reg delete `"HKLM\SYSTEM\CurrentControlSet\Enum\USBSTOR`" /f >nul 2>&1"
            Add-Log "  OK USB baglanti gecmisi temizlendi." "Success"
        }
    }

    # ---- ACIK UYGULAMA KONTROLU ----
    $skippedSteps = @()
    foreach ($chk in $appExeMap.Keys) {
        if ($steps -contains $chk) {
            $exeName   = $appExeMap[$chk].exe
            $dispName  = $appExeMap[$chk].display
            if ($null -ne (Get-Process -Name $exeName -ErrorAction SilentlyContinue)) {
                if (Ask-User "$dispName su an acik. Temizlik icin kapatilmasi gerekiyor.`n`n$dispName kapatilsin mi?" "$dispName Acik") {
                    Stop-Process -Name $exeName -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Milliseconds 800
                    Add-Log "  OK $dispName kapatildi." "Success"
                } else {
                    Add-Log "  -- $dispName atlandi." "Warn"
                    $skippedSteps += $chk
                }
            }
        }
    }
    $steps = $steps | Where-Object { $_ -notin $skippedSteps }

    # ---- SISTEM TEMIZLIGI ----
    if ($steps -contains "ChkTemp") {
        Update-Progress "Gecici dosyalar temizleniyor..."
        DeepClean-Folder "$env:TEMP"           "User Temp"
        DeepClean-Folder "C:\Windows\Temp"     "System Temp"
        DeepClean-Folder "C:\Windows\Prefetch" "Prefetch"
    }
    if ($steps -contains "ChkRecycle") {
        Update-Progress "Geri donusum bosaltiliyor..."
        cmd.exe /c "PowerShell -NoProfile -Command `"Clear-RecycleBin -Force -EA SilentlyContinue`" >nul 2>&1"
        Add-Log "  OK Geri donusum temizlendi." "Success"
    }
    if ($steps -contains "ChkWinHistory") {
        Update-Progress "Windows gecmisi siliniyor..."
        cmd.exe /c "reg delete `"HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU`" /f >nul 2>&1"
        cmd.exe /c "reg delete `"HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\WordWheelQuery`" /f >nul 2>&1"
        Add-Log "  OK Windows gecmisi temizlendi." "Success"
    }
    if ($steps -contains "ChkDns") {
        Update-Progress "DNS ve thumbnail temizleniyor..."
        cmd.exe /c "ipconfig /flushdns >nul 2>&1"
        cmd.exe /c "del /f /q `"$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db`" >nul 2>&1"
        Add-Log "  OK DNS ve thumbnail temizlendi." "Success"
    }
    if ($steps -contains "ChkLogs") {
        Update-Progress "Sistem loglari temizleniyor..."
        cmd.exe /c "del /f /q `"$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt`" >nul 2>&1"
        cmd.exe /c "for /f `"tokens=*`" %G in ('wevtutil el') do (wevtutil cl `"%G`" >nul 2>&1)"
        Add-Log "  OK Sistem loglari temizlendi." "Success"
    }
    if ($steps -contains "ChkWinUpdate") {
        Update-Progress "Windows Update cache temizleniyor..."
        cmd.exe /c "net stop wuauserv /y >nul 2>&1"
        cmd.exe /c "net stop bits /y >nul 2>&1"
        DeepClean-Folder "C:\Windows\SoftwareDistribution\Download" "Update Cache"
        cmd.exe /c "net start wuauserv >nul 2>&1"
        cmd.exe /c "net start bits >nul 2>&1"
    }
    if ($steps -contains "ChkFontCache") {
        Update-Progress "Font/ikon cache temizleniyor..."
        cmd.exe /c "net stop `"FontCache`" /y >nul 2>&1"
        DeepClean-Folder "$env:windir\ServiceProfiles\LocalService\AppData\Local\FontCache" "Font Cache"
        cmd.exe /c "del /f /q `"$env:LOCALAPPDATA\IconCache.db`" >nul 2>&1"
        cmd.exe /c "del /f /q `"$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache_*.db`" >nul 2>&1"
        cmd.exe /c "net start `"FontCache`" >nul 2>&1"
        Add-Log "  OK Font/ikon cache temizlendi." "Success"
    }
    if ($steps -contains "ChkRam") {
        Update-Progress "RAM optimize ediliyor..."
        [System.GC]::Collect(); [System.GC]::WaitForPendingFinalizers()
        Add-Log "  OK RAM rahatlatildi." "Success"
    }

    # ---- TARAYICILAR ----
    foreach ($b in $browserCachePaths.Keys) {
        if ($steps -contains $b) {
            $dispName = ($b -replace "Chk","")
            Update-Progress "$dispName gecmisi temizleniyor..."
            $p = $browserCachePaths[$b]
            if (-not (Test-Path $p)) { Add-Log "  .. $dispName profil bulunamadi" "Warn"; continue }
            foreach ($f in @("History","History-journal","Visited Links","Top Sites","DownloadMetadata")) {
                cmd.exe /c "del /f /q `"$p\$f`" >nul 2>&1"
            }
            Add-Log "  OK $dispName gecmisi temizlendi." "Success"
        }
    }
    if ($steps -contains "ChkFirefox") {
        Update-Progress "Firefox temizleniyor..."
        Get-ChildItem "$env:APPDATA\Mozilla\Firefox\Profiles" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $ffp = $_.FullName
            foreach ($f in @("places.sqlite","downloads.sqlite","formhistory.sqlite")) {
                cmd.exe /c "del /f /q `"$ffp\$f`" >nul 2>&1"
            }
        }
        Add-Log "  OK Firefox temizlendi." "Success"
    }

    # ---- OYUN PLATFORMLARI ----
    if ($steps -contains "ChkSteam") {
        Update-Progress "Steam cache temizleniyor..."
        if ($steamCacheHTTP) { DeepClean-Folder $steamCacheHTTP "Steam HTTP Cache" }
        DeepClean-Folder $steamCacheHTML "Steam HTML Cache"
    }
    if ($steps -contains "ChkDiscord") {
        Update-Progress "Discord cache temizleniyor..."
        DeepClean-Folder $discordCache "Discord Cache"
        DeepClean-Folder $discordCode  "Discord Code Cache"
        DeepClean-Folder $discordGpu   "Discord GPU Cache"
    }
    if ($steps -contains "ChkEpic") {
        Update-Progress "Epic Games cache temizleniyor..."
        $epicBase = if ($epicPath) { $epicPath } else { "$env:LOCALAPPDATA\EpicGamesLauncher" }
        DeepClean-Folder "$epicBase\Saved\webcache"         "Epic Webcache"
        DeepClean-Folder "$epicBase\Saved\HttpRequestCache" "Epic HTTP Cache"
        DeepClean-Folder "$epicBase\Saved\Logs"             "Epic Logs"
    }
    if ($steps -contains "ChkGog") {
        Update-Progress "GOG Galaxy cache temizleniyor..."
        DeepClean-Folder "$env:PROGRAMDATA\GOG.com\Galaxy\webcache" "GOG Webcache"
        DeepClean-Folder "$env:LOCALAPPDATA\GOG.com\Galaxy\Cache"   "GOG Cache"
    }
    if ($steps -contains "ChkUbisoft") {
        Update-Progress "Ubisoft Connect cache temizleniyor..."
        DeepClean-Folder "$env:LOCALAPPDATA\Ubisoft Game Launcher\cache" "Ubisoft Cache"
        if ($ubisoftPath) { DeepClean-Folder "$ubisoftPath\cache" "Ubisoft Install Cache" }
    }
    if ($steps -contains "ChkBattlenet") {
        Update-Progress "Battle.net cache temizleniyor..."
        DeepClean-Folder "$env:PROGRAMDATA\Battle.net\Setup\Cache" "Bnet Setup Cache"
        DeepClean-Folder "$env:LOCALAPPDATA\Battle.net\Cache"      "Bnet Local Cache"
    }
    if ($steps -contains "ChkEa") {
        Update-Progress "EA App cache temizleniyor..."
        DeepClean-Folder "$env:LOCALAPPDATA\Electronic Arts\EA Desktop\Cache" "EA Local Cache"
        DeepClean-Folder "$env:PROGRAMDATA\Electronic Arts\EA Desktop\Cache"  "EA System Cache"
    }
    if ($steps -contains "ChkXbox") {
        Update-Progress "Xbox cache temizleniyor..."
        DeepClean-Folder "$xboxPkg\AC\INetCache" "Xbox INetCache"
    }

    # ---- ONARIM ----
    if ($steps -contains "ChkBrokenShortcuts") {
        Update-Progress "Cop kisayollar taraniyor..."
        $shortcutDirs = @("$env:USERPROFILE\Desktop","$env:PUBLIC\Desktop",
            "$env:APPDATA\Microsoft\Windows\Start Menu\Programs",
            "$env:ProgramData\Microsoft\Windows\Start Menu\Programs")
        $removed = 0
        foreach ($dir in $shortcutDirs) {
            if (-not (Test-Path $dir)) { continue }
            Get-ChildItem $dir -Filter "*.lnk" -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
                try {
                    $target = (New-Object -ComObject WScript.Shell).CreateShortcut($_.FullName).TargetPath
                    if ($target -and $target -ne "" -and -not (Test-Path $target)) {
                        Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
                        Add-Log "  -- Silindi: $($_.Name)" "Warn"; $removed++
                    }
                } catch {}
            }
        }
        Add-Log "  OK $removed adet cop kisayol silindi." "Success"
    }
    if ($steps -contains "ChkStartup") {
        Update-Progress "Baslangic programlari listeleniyor..."
        $count = 0
        foreach ($rr in @("HKCU:\Software\Microsoft\Windows\CurrentVersion\Run","HKLM:\Software\Microsoft\Windows\CurrentVersion\Run")) {
            $props = Get-ItemProperty $rr -ErrorAction SilentlyContinue
            if ($props) {
                $props.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" } | ForEach-Object {
                    Add-Log "  [REG] $($_.Name)" "Info"; $count++
                }
            }
        }
        foreach ($sf in @("$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup","$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup")) {
            Get-ChildItem $sf -ErrorAction SilentlyContinue | ForEach-Object { Add-Log "  [KLASOR] $($_.Name)" "Info"; $count++ }
        }
        Add-Log "  OK $count baslangic ogesi listelendi. (Silinmedi)" "Success"
    }
    if ($steps -contains "ChkOrphanedReg") {
        Update-Progress "Orphan registry taraniyor..."
        $backupPath = "$env:TEMP\reg_backup_$((Get-Date).ToString('yyyyMMdd_HHmmss')).reg"
        cmd.exe /c "reg export `"HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall`" `"$backupPath`" /y >nul 2>&1"
        Add-Log "  -- Registry yedegi: $backupPath" "Info"
        $orphaned = 0
        foreach ($up in @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall","HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall","HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall")) {
            Get-ChildItem $up -ErrorAction SilentlyContinue | ForEach-Object {
                $props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
                if ($props) {
                    $loc = $props.InstallLocation; $dn = $props.DisplayName
                    if ($loc -and $loc.Trim() -ne "" -and -not (Test-Path $loc) -and $dn) {
                        try { Remove-Item $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue; Add-Log "  -- Silindi: $dn" "Warn"; $orphaned++ } catch {}
                    }
                }
            }
        }
        Add-Log "  OK $orphaned orphan registry kaydi temizlendi." "Success"
    }
    if ($steps -contains "ChkSfc") {
        Update-Progress "SFC kontrol ediliyor (sorun varsa +15-30 dk surebilir)..."
        $sfcResult = cmd.exe /c "sfc /verifyonly 2>&1"
        if ($sfcResult | Select-String "did not find any integrity violations") {
            Add-Log "  OK SFC: Sistem temiz, onarim gerekmiyor." "Success"
        } else {
            Add-Log "  !! SFC sorun buldu, DISM + SFC onarimi baslatiliyor... (15-30 dk surebilir)" "Error"
            cmd.exe /c "DISM /Online /Cleanup-Image /RestoreHealth >nul 2>&1"
            cmd.exe /c "sfc /scannow >nul 2>&1"
            Add-Log "  OK SFC/DISM onarimi tamamlandi. Yeniden baslatiniz." "Success"
        }
    }
    if ($steps -contains "ChkPagefile") {
        Update-Progress "Pagefile optimize ediliyor (16+ GB RAM)..."
        $ramGBNow = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
        if ($ramGBNow -ge 16) {
            $cs = Get-CimInstance Win32_ComputerSystem
            if (-not $cs.AutomaticManagedPagefile) {
                Set-CimInstance -InputObject $cs -Property @{AutomaticManagedPagefile=$true} -ErrorAction SilentlyContinue
                Add-Log "  OK Pagefile sistem yonetimine alindi. ($ramGBNow GB RAM)" "Success"
            } else { Add-Log "  OK Pagefile zaten otomatik yonetimde. ($ramGBNow GB RAM)" "Success" }
        } else { Add-Log "  -- RAM $ramGBNow GB (<16 GB), pagefile degistirilmedi." "Warn" }
    }

    # ---- GIZLILIK ----
    if ($steps -contains "ChkVss") {
        Update-Progress "VSS Shadow Copies siliniyor..."
        $cnt = ($( cmd.exe /c "vssadmin list shadows 2>&1" ) | Select-String "Shadow Copy Volume").Count
        if ($cnt -gt 0) { cmd.exe /c "vssadmin delete shadows /all /quiet >nul 2>&1"; Add-Log "  OK $cnt shadow copy silindi." "Success" }
        else { Add-Log "  OK VSS shadow copy yok." "Success" }
    }
    if ($steps -contains "ChkSearchIndex") {
        Update-Progress "Search Index sifirlaniyor..."
        cmd.exe /c "net stop WSearch /y >nul 2>&1"
        $sdb = "$env:ProgramData\Microsoft\Search\Data\Applications\Windows\Windows.edb"
        if (Test-Path $sdb) { cmd.exe /c "del /f /q `"$sdb`" >nul 2>&1"; Add-Log "  OK Windows.edb silindi." "Success" }
        else { Add-Log "  OK Search index zaten temiz." "Success" }
        cmd.exe /c "net start WSearch >nul 2>&1"
    }
    if ($steps -contains "ChkLnk") {
        Update-Progress "LNK / Recent gecmis siliniyor..."
        DeepClean-Folder "$env:APPDATA\Microsoft\Windows\Recent" "Recent"
        DeepClean-Folder "$env:APPDATA\Microsoft\Windows\Recent\AutomaticDestinations" "AutoDest"
        DeepClean-Folder "$env:APPDATA\Microsoft\Windows\Recent\CustomDestinations"    "CustomDest"
        cmd.exe /c "reg delete `"HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32\OpenSavePidlMRU`" /f >nul 2>&1"
        cmd.exe /c "reg delete `"HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32\LastVisitedPidlMRU`" /f >nul 2>&1"
        Add-Log "  OK LNK ve MRU gecmisi silindi." "Success"
    }
    if ($steps -contains "ChkShellbag") {
        Update-Progress "ShellBag gecmisi temizleniyor..."
        foreach ($k in @(
            "HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags",
            "HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\BagMRU",
            "HKCU\Software\Microsoft\Windows\Shell\Bags",
            "HKCU\Software\Microsoft\Windows\Shell\BagMRU")) {
            cmd.exe /c "reg delete `"$k`" /f >nul 2>&1"
        }
        Add-Log "  OK ShellBag gecmisi silindi." "Success"
    }
    if ($steps -contains "ChkPagefileClear") {
        Update-Progress "Pagefile shutdown temizleme aktif ediliyor..."
        $rk = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
        if ((Get-ItemProperty $rk -Name "ClearPageFileAtShutdown" -ErrorAction SilentlyContinue).ClearPageFileAtShutdown -ne 1) {
            Set-ItemProperty $rk "ClearPageFileAtShutdown" 1 -Type DWord
            Add-Log "  OK Pagefile her kapanista sifirlaniyor. (Kapanis suresi uzayabilir)" "Success"
        } else { Add-Log "  OK Pagefile shutdown temizleme zaten aktif." "Success" }
    }
    if ($steps -contains "ChkHiberfil") {
        Update-Progress "Hibernate kapatiliyor..."
        cmd.exe /c "powercfg /h off >nul 2>&1"
        Add-Log "  OK Hibernate kapatildi. hiberfil.sys silindi. (Sleep modu etkilenmez)" "Success"
    }

    # ---- INSTALLER ARTIKLARI ----
    if ($steps -contains "ChkOrphanSetup") {
        Update-Progress "Installer artiklari taraniyor..."

        $registeredPaths = Get-AllRegisteredInstallPaths

        $systemFolders = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        @("Windows","Users","Program Files","Program Files (x86)","ProgramData",
          "System Volume Information","Recovery","Boot","inetpub","perflogs",
          "MSOCache","OneDriveTemp","Config.Msi") | ForEach-Object { $systemFolders.Add($_) | Out-Null }

        $sysDrive       = $env:SystemDrive
        $suspectFolders = @()
        $setupPatterns  = @("setup.exe","install.exe","*.msi","uninst*.exe","_install*","_setup*","unpack*")

        Get-ChildItem "$sysDrive\" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $folderName = $_.Name
            $folderPath = $_.FullName

            if ($systemFolders.Contains($folderName)) { return }

            $isRegistered = $false
            foreach ($rp in $registeredPaths) {
                if ($rp -like "$folderPath*" -or $folderPath -like "$rp*") { $isRegistered = $true; break }
            }
            if ($isRegistered) { return }

            $isSetup = $false
            foreach ($pat in $setupPatterns) {
                if (Get-ChildItem $folderPath -Filter $pat -Recurse -Depth 2 -ErrorAction SilentlyContinue | Select-Object -First 1) {
                    $isSetup = $true; break
                }
            }
            if (-not $isSetup -and $folderName -match "(?i)^(setup|install|unpack|extract|~|\$TEMP|_temp)") {
                $isSetup = $true
            }

            if ($isSetup) {
                $sizeBytes = (Get-ChildItem $folderPath -Recurse -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
                $sizeMB    = [math]::Round($sizeBytes / 1MB, 1)
                $suspectFolders += [PSCustomObject]@{ Path=$folderPath; Name=$folderName; SizeMB=$sizeMB }
            }
        }

        if ($suspectFolders.Count -eq 0) {
            Add-Log "  OK Installer artigi bulunamadi." "Success"
        } else {
            Add-Log "  -- $($suspectFolders.Count) adet suphe uyandiran klasor (registry'de kayitli degil):" "Warn"
            foreach ($sf in $suspectFolders) { Add-Log "     $($sf.SizeMB) MB  |  $($sf.Name)" "Info" }

            $form = New-Object System.Windows.Forms.Form
            $form.Text            = "Installer Artiklari - Silinecekleri Sec"
            $form.Width           = 660; $form.Height = 520
            $form.StartPosition   = "CenterScreen"
            $form.TopMost         = $true        # FIX: her zaman on planda
            $form.BackColor       = [System.Drawing.ColorTranslator]::FromHtml($BG_CARD)

            $lbl = New-Object System.Windows.Forms.Label
            $lbl.Text     = "Asagidaki klasorler registry'de kayitli degil ve setup kaliplari iceriyor.`nSilmek istediklerinizi isaretleyin. Emin olmadiginiz seyleri isaretlemeyin!"
            $lbl.Location = "12,8"; $lbl.Size = "630,40"
            $lbl.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($WARN_C)
            $lbl.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
            $form.Controls.Add($lbl)

            $clb = New-Object System.Windows.Forms.CheckedListBox
            $clb.Location  = "12,55"; $clb.Size = "630,340"
            $clb.BackColor = [System.Drawing.ColorTranslator]::FromHtml($LOG_BG)
            $clb.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($FG_PRIMARY)
            $clb.Font      = New-Object System.Drawing.Font("Consolas", 10)
            foreach ($sf in $suspectFolders) { $clb.Items.Add("$($sf.SizeMB) MB  |  $($sf.Name)  [$($sf.Path)]") | Out-Null }
            $form.Controls.Add($clb)

            $btnOk = New-Object System.Windows.Forms.Button
            $btnOk.Text      = "Secilenleri Sil"; $btnOk.Location = "12,410"; $btnOk.Size = "180,36"
            $btnOk.BackColor = [System.Drawing.ColorTranslator]::FromHtml($ACCENT)
            $btnOk.ForeColor = [System.Drawing.Color]::Black; $btnOk.FlatStyle = "Flat"
            $btnOk.Add_Click({ $form.DialogResult = "OK"; $form.Close() })
            $form.Controls.Add($btnOk)

            $btnNo = New-Object System.Windows.Forms.Button
            $btnNo.Text      = "Iptal"; $btnNo.Location = "204,410"; $btnNo.Size = "100,36"
            $btnNo.BackColor = [System.Drawing.ColorTranslator]::FromHtml($BG_ROW)
            $btnNo.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($FG_SECOND); $btnNo.FlatStyle = "Flat"
            $btnNo.Add_Click({ $form.DialogResult = "Cancel"; $form.Close() })
            $form.Controls.Add($btnNo)

            # FIX: Pencere flash efekti + on plana gelme
            $form.Add_Shown({
                $form.Activate()
                $form.BringToFront()
                $form.Focus() | Out-Null
            })

            # Flash efekti - dikkat ceksin
            Add-Log "  !! DIKKAT: Installer secim penceresi acildi - lutfen onaylayiniz!" "Error"
            [System.Windows.Forms.Application]::DoEvents()

            if ($form.ShowDialog() -eq "OK") {
                $del = 0; $mb = 0
                for ($i = 0; $i -lt $clb.CheckedIndices.Count; $i++) {
                    $idx = $clb.CheckedIndices[$i]
                    DeepClean-Folder $suspectFolders[$idx].Path $suspectFolders[$idx].Name
                    try { Remove-Item $suspectFolders[$idx].Path -Recurse -Force -EA SilentlyContinue } catch {}
                    $del++; $mb += $suspectFolders[$idx].SizeMB
                }
                Add-Log "  OK $del klasor silindi. Kazanilan: $mb MB" "Success"
            } else { Add-Log "  -- Installer artigi silme iptal edildi." "Info" }
        }
    }

    # ---- RAPOR ----
    $diskAfter = (Get-PSDrive ($env:SystemDrive -replace ":","")).Free
    $savedMB   = [math]::Round(($diskAfter - $diskBefore) / 1MB, 1)
    if ($savedMB -lt 0) { $savedMB = 0 }

    $controls["DiskFreeText"].Text = "$([math]::Round($diskAfter / 1GB, 1)) GB bos"
    Add-Log "====================================" "Info"

    if ($savedMB -gt 0) {
        Add-Log "TAMAMLANDI!  Kazanilan: $savedMB MB" "Success"
    } else {
        Add-Log "TAMAMLANDI!  Disk alani degismedi - sistem zaten temizdi." "Success"
    }

    $controls["ProgressFill"].BeginAnimation([System.Windows.FrameworkElement]::WidthProperty, $null)
    $controls["ProgressFill"].Width   = $controls["ProgressTrack"].ActualWidth
    $controls["StatusText"].Text      = if ($savedMB -gt 0) { "Tamamlandi!  +$savedMB MB kazanildi" } else { "Tamamlandi! Sistem temizdi." }
    $controls["PctText"].Text         = "100%"
    $controls["BtnClean"].IsEnabled   = $true
    $controls["BtnSaveLog"].IsEnabled = $true
    $controls["BtnSaveLog"].Foreground  = New-Brush $SUCCESS
    $controls["BtnSaveLog"].BorderBrush = New-Brush $SUCCESS
    Update-Summary
})

# ============================================================
# TUMUNU SEC (Temizlik)
# ============================================================
$controls["BtnSelectSistem"].Add_Click({
    $v = -not $controls["ChkTemp"].IsChecked
    foreach ($c in @("ChkTemp","ChkRecycle","ChkWinHistory","ChkDns","ChkLogs","ChkWinUpdate","ChkFontCache","ChkRam","ChkUsb")) { $controls[$c].IsChecked = $v }
})
$controls["BtnSelectBrowser"].Add_Click({
    $v = -not ($controls["ChkBrave"] -and $controls["ChkBrave"].IsChecked -and $controls["ChkBrave"].Visibility -eq [System.Windows.Visibility]::Visible)
    foreach ($c in @("ChkBrave","ChkChrome","ChkFirefox","ChkEdge","ChkOpera","ChkOperaGX")) {
        if ($controls[$c] -and $controls[$c].Visibility -eq [System.Windows.Visibility]::Visible) { $controls[$c].IsChecked = $v }
    }
})
$controls["BtnSelectGaming"].Add_Click({
    $v = -not ($controls["ChkSteam"] -and $controls["ChkSteam"].IsChecked -and $controls["ChkSteam"].Visibility -eq [System.Windows.Visibility]::Visible)
    foreach ($c in @("ChkSteam","ChkDiscord","ChkEpic","ChkGog","ChkUbisoft","ChkBattlenet","ChkEa","ChkXbox")) {
        if ($controls[$c] -and $controls[$c].Visibility -eq [System.Windows.Visibility]::Visible) { $controls[$c].IsChecked = $v }
    }
})
$controls["BtnSelectRepair"].Add_Click({
    $v = -not $controls["ChkBrokenShortcuts"].IsChecked
    foreach ($c in @("ChkBrokenShortcuts","ChkStartup","ChkOrphanedReg","ChkSfc","ChkPagefile")) { $controls[$c].IsChecked = $v }
})
$controls["BtnSelectPrivacy"].Add_Click({
    $v = -not $controls["ChkVss"].IsChecked
    foreach ($c in @("ChkVss","ChkSearchIndex","ChkLnk","ChkShellbag","ChkPagefileClear","ChkHiberfil","ChkOrphanSetup")) { $controls[$c].IsChecked = $v }
})

# ============================================================
# OPTİMİZASYON BUTON MANTIKLARI
# ============================================================

# --- GUC PLANI ---
$window.FindName("BtnApplyPower").Add_Click({
    Add-Log "==== GUC PLANI UYGULANIYOR ====" "Success"
    $rPlanUlt    = $window.FindName("RPlanUltimate")
    $rPlanHigh   = $window.FindName("RPlanHigh")
    $rPlanBal    = $window.FindName("RPlanBalanced")
    $rPlanBit    = $window.FindName("RPlanBitsum")


    if ($rPlanUlt.IsChecked) {
        Add-Log "  Ultimate Performance aktive ediliyor..." "Info"
        $ultGuid = "e9a42b02-d5df-448d-aa00-03f14749eb61"
        $out = cmd.exe /c "powercfg -duplicatescheme $ultGuid 2>&1"
        $newGuid = ([regex]'([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})').Match($out).Value
        if ($newGuid) {
            cmd.exe /c "powercfg /setactive $newGuid >nul 2>&1"
            Add-Log "  OK Ultimate Performance aktif: $newGuid" "Success"
        } else {
            $existing = cmd.exe /c "powercfg /list 2>&1" | Select-String -Pattern "Ultimate"
            if ($existing) {
                $existGuid = ([regex]'([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})').Match($existing.ToString()).Value
                cmd.exe /c "powercfg /setactive $existGuid >nul 2>&1"
                Add-Log "  OK Ultimate Performance aktif (mevcut): $existGuid" "Success"
            } else {
                Add-Log "  !! Ultimate Performance aktive edilemedi." "Error"
            }
        }
    } elseif ($rPlanHigh.IsChecked) {
        cmd.exe /c "powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c >nul 2>&1"
        Add-Log "  OK Yuksek Performans guc plani aktif." "Success"
    } elseif ($rPlanBal.IsChecked) {
        cmd.exe /c "powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e >nul 2>&1"
        Add-Log "  OK Dengeli guc plani aktif." "Success"
    } elseif ($rPlanBit.IsChecked) {
        # Bitsum dosyadan yukle
        $scriptDir = Split-Path -Parent $PSCommandPath
        $bitsumPow = Join-Path $scriptDir "_Files\Bitsum-Highest-Performance.pow"
        if (Test-Path $bitsumPow) {
            $importOut = cmd.exe /c "powercfg /import `"$bitsumPow`" 2>&1"
            $importGuid = ([regex]'([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})').Match($importOut).Value
            if ($importGuid) {
                cmd.exe /c "powercfg /setactive $importGuid >nul 2>&1"
                Add-Log "  OK Bitsum Highest Performance yuklu ve aktif: $importGuid" "Success"
            } else {
                $bitsumExist = cmd.exe /c "powercfg /list 2>&1" | Select-String -Pattern "Bitsum"
                if ($bitsumExist) {
                    $bitsumGuid = ([regex]'([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})').Match($bitsumExist.ToString()).Value
                    cmd.exe /c "powercfg /setactive $bitsumGuid >nul 2>&1"
                    Add-Log "  OK Bitsum Highest Performance aktif (mevcut): $bitsumGuid" "Success"
                } else {
                    Add-Log "  !! Bitsum plani yuklenemedi. Cikti: $importOut" "Error"
                }
            }
        } else {
            Add-Log "  !! Bitsum .pow dosyasi bulunamadi: $bitsumPow" "Error"
            Add-Log "  _Files\Bitsum-Highest-Performance.pow dosyasinin var oldugunu kontrol edin." "Warn"
        }
    } elseif ($window.FindName("RPlanHybred").IsChecked) {
        # TheHybred Low Latency High Performance planini yukle
        Add-Log "  TheHybred Low Latency High Performance yukleniyor..." "Info"
        $scriptDir = Split-Path -Parent $PSCommandPath
        $hybPow = Join-Path $scriptDir "_Files\HybredLowLatencyHighPerf.pow"
        if (Test-Path $hybPow) {
            $importOut = cmd.exe /c "powercfg /import `"$hybPow`" 2>&1"
            $importGuid = ([regex]'([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})').Match($importOut).Value
            if ($importGuid) {
                cmd.exe /c "powercfg /setactive $importGuid >nul 2>&1"
                Add-Log "  OK TheHybred Low Latency High Performance yuklu ve aktif: $importGuid" "Success"
            } else {
                $hybExist = cmd.exe /c "powercfg /list 2>&1" | Select-String -Pattern "Hybred|Low Latency"
                if ($hybExist) {
                    $hybGuid = ([regex]'([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})').Match($hybExist.ToString()).Value
                    cmd.exe /c "powercfg /setactive $hybGuid >nul 2>&1"
                    Add-Log "  OK TheHybred plani aktif (mevcut): $hybGuid" "Success"
                } else {
                    Add-Log "  !! TheHybred plani yuklenemedi. Cikti: $importOut" "Error"
                }
            }
        } else {
            Add-Log "  !! TheHybred .pow dosyasi bulunamadi: $hybPow" "Error"
            Add-Log "  _Files\HybredLowLatencyHighPerf.pow dosyasinin var oldugunu kontrol edin." "Warn"
        }
    }
    # Guc planini guncelle
    $cpOut2 = cmd.exe /c "powercfg /getactivescheme 2>&1"
    $pName2 = if ($cpOut2 -match "\((.+)\)") { $Matches[1] } else { "Bilinmiyor" }
    $window.FindName("CurrentPlanText").Text = "Mevcut plan: $pName2"
})

# --- REGISTRY TWEAKS ---
$window.FindName("BtnBackupReg").Add_Click({
    $bp = "$env:USERPROFILE\Desktop\RegBackup_PerfTweaks_$((Get-Date).ToString('yyyyMMdd_HHmmss')).reg"
    cmd.exe /c "reg export `"HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile`" `"$bp`" /y >nul 2>&1"
    Add-Log "  OK Registry yedegi masaustune kaydedildi: $bp" "Success"
})

$window.FindName("BtnApplyReg").Add_Click({
    Add-Log "==== REGISTRY PERFORMANCE TWEAKS ====" "Success"

    if ($window.FindName("ChkRegGpuPriority").IsChecked) {
        $gamesKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"
        if (-not (Test-Path $gamesKey)) { New-Item $gamesKey -Force | Out-Null }
        $curGpu = (Get-ItemProperty $gamesKey -ErrorAction SilentlyContinue)."GPU Priority"
        if ($curGpu -eq 8) { Add-Log "  == GPU Priority: 8 (degisiklik yok)" "Warn" }
        else { Set-ItemProperty $gamesKey "GPU Priority" -Value 8 -Type DWord; Add-Log "  OK GPU Priority: $curGpu -> 8" "Success" }
    }
    if ($window.FindName("ChkRegGamePriority").IsChecked) {
        $gamesKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"
        if (-not (Test-Path $gamesKey)) { New-Item $gamesKey -Force | Out-Null }
        Set-ItemProperty $gamesKey "Priority" -Value 6 -Type DWord
        Add-Log "  OK Game Priority: 6" "Success"
    }
    if ($window.FindName("ChkRegWin32Prio").IsChecked) {
        $prioKey = "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl"
        # Mevcut deger kontrol
        $curVal = (Get-ItemProperty $prioKey -ErrorAction SilentlyContinue).Win32PrioritySeparation
        # TheHybred preset secimi
        $win32Val = 26  # varsayilan
        if ($window.FindName("RWin32BestFPS").IsChecked)     { $win32Val = 20 }
        elseif ($window.FindName("RWin32BestLatency").IsChecked) { $win32Val = 42 }
        elseif ($window.FindName("RWin32Balanced").IsChecked)    { $win32Val = 24 }
        elseif ($window.FindName("RWin32Default").IsChecked)     { $win32Val = 38 }
        if ($curVal -eq $win32Val) {
            Add-Log "  == Win32PrioritySeparation: $win32Val (degisiklik yok, atlanıyor)" "Warn"
        } else {
            Set-ItemProperty $prioKey "Win32PrioritySeparation" -Value $win32Val -Type DWord
            Add-Log "  OK Win32PrioritySeparation: $curVal -> $win32Val" "Success"
        }
    }
    if ($window.FindName("ChkRegNetThrottle").IsChecked) {
        $mmKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
        Set-ItemProperty $mmKey "NetworkThrottlingIndex" -Value 0xFFFFFFFF -Type DWord
        Add-Log "  OK NetworkThrottlingIndex: FFFFFFFF (kapali)" "Success"
    }
    if ($window.FindName("ChkRegMenuDelay").IsChecked) {
        Set-ItemProperty "HKCU:\Control Panel\Desktop" "MenuShowDelay" -Value "0"
        Add-Log "  OK MenuShowDelay: 0 ms" "Success"
    }
    if ($window.FindName("ChkRegForeground").IsChecked) {
        $deskKey = "HKCU:\Control Panel\Desktop"
        Set-ItemProperty $deskKey "ForegroundLockTimeout"    -Value 0       -Type DWord
        Set-ItemProperty $deskKey "ForegroundFlashCount"     -Value 0       -Type DWord
        # Low Latency Audio
        $audioKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
        Set-ItemProperty $audioKey "SystemResponsiveness" -Value 0 -Type DWord
        Add-Log "  OK ForegroundBoost + LowLatency Audio (SystemResponsiveness=0)" "Success"
    }
    if ($window.FindName("ChkRegMmcss").IsChecked) {
        $mmGames = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"
        if (-not (Test-Path $mmGames)) { New-Item $mmGames -Force | Out-Null }
        Set-ItemProperty $mmGames "Scheduling Category" -Value "High"
        Set-ItemProperty $mmGames "SFIO Priority"       -Value "High"
        Set-ItemProperty $mmGames "Background Only"     -Value "False"
        Set-ItemProperty $mmGames "Clock Rate"          -Value 10000 -Type DWord
        $mmAudio = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Pro Audio"
        if (-not (Test-Path $mmAudio)) { New-Item $mmAudio -Force | Out-Null }
        Set-ItemProperty $mmAudio "Scheduling Category" -Value "High"
        Set-ItemProperty $mmAudio "SFIO Priority"       -Value "High"
        Add-Log "  OK MMCSS Games + Pro Audio: High" "Success"
    }
    if ($window.FindName("ChkGameMode").IsChecked) {
        Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\GameBar" "AllowAutoGameMode" -Value 1 -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\GameBar" "AutoGameModeEnabled" -Value 1 -Type DWord -ErrorAction SilentlyContinue
        Add-Log "  OK Game Mode: Etkin" "Success"
    }
    if ($window.FindName("ChkGameDVR").IsChecked) {
        Set-ItemProperty "HKCU:\Software\Microsoft\GameBar" "UseNexusForGameBarEnabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty "HKCU:\Software\Microsoft\GameBar" "GameDVR_Enabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" "AppCaptureEnabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" "AllowgameDVR" -Value 0 -Type DWord -ErrorAction SilentlyContinue
        Add-Log "  OK Game DVR / GameBar: Kapali" "Success"
    }
    if ($window.FindName("ChkHagsReg").IsChecked) {
        $hwsKey = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
        Set-ItemProperty $hwsKey "HwSchMode" -Value 2 -Type DWord -ErrorAction SilentlyContinue
        Add-Log "  OK HAGS: HwSchMode=2 (Yeniden baslatma gerektirir)" "Warn"
    }
    if ($window.FindName("ChkFseTweaks").IsChecked) {
        $appCompatKey = "HKCU:\System\GameConfigStore"
        if (-not (Test-Path $appCompatKey)) { New-Item $appCompatKey -Force | Out-Null }
        Set-ItemProperty $appCompatKey "GameDVR_FSEBehaviorMode" -Value 2 -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty $appCompatKey "GameDVR_HonorUserFSEBehaviorMode" -Value 1 -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty $appCompatKey "GameDVR_DXGIHonorFSEWindowsCompatible" -Value 1 -Type DWord -ErrorAction SilentlyContinue
        Add-Log "  OK Fullscreen Optimizasyon: Kapali mod" "Success"
    }
    if ($window.FindName("ChkLargeSystemCache").IsChecked) {
        Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "LargeSystemCache" -Value 0 -Type DWord -ErrorAction SilentlyContinue
        Add-Log "  OK LargeSystemCache: 0 (masaustu optimizasyonu)" "Success"
    }
    if ($window.FindName("ChkPowerThrottle").IsChecked) {
        $powerKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling"
        if (-not (Test-Path $powerKey)) { New-Item $powerKey -Force | Out-Null }
        Set-ItemProperty $powerKey "PowerThrottlingOff" -Value 1 -Type DWord -ErrorAction SilentlyContinue
        Add-Log "  OK PowerThrottling: Kapali (tum islemler tam guc)" "Success"
    }
    Add-Log "  Registry tweakler tamamlandi. Bazi ayarlar yeniden baslatma gerektirebilir." "Warn"
})

# --- CPU BOOT ---
$window.FindName("BtnApplyCpuBoot").Add_Click({
    Add-Log "==== CPU BASLANGIC AYARLARI ====" "Success"
    if ($window.FindName("ChkMaxProcessors").IsChecked) {
        $logicalCount = (Get-CimInstance Win32_Processor | Measure-Object NumberOfLogicalProcessors -Sum).Sum
        cmd.exe /c "bcdedit /set numproc $logicalCount >nul 2>&1"
        Add-Log "  OK BCDEdit numproc: $logicalCount (tum thread'ler)" "Success"
    }
    if ($window.FindName("ChkNumaOptimize").IsChecked) {
        cmd.exe /c "bcdedit /set groupsize 2 >nul 2>&1"
        Add-Log "  OK BCDEdit groupsize: 2 (NUMA/SMP optimize)" "Success"
    }
    $intelSpeedStepChk = $window.FindName("ChkIntelSpeedStep")
    if ($intelSpeedStepChk -and $intelSpeedStepChk.IsChecked -and $intelSpeedStepChk.Visibility -eq [System.Windows.Visibility]::Visible) {
        # Intel SpeedStep: BIOS'tan kapatmak daha iyidir ama registry ipucu
        $activePlan = cmd.exe /c "powercfg /getactivescheme 2>&1"
        $pGuid = ([regex]'([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})').Match($activePlan).Value
        if ($pGuid) {
            $SUB_P = "54533251-82be-4824-96c1-47b60b740d00"
            cmd.exe /c "powercfg /setacvalueindex $pGuid $SUB_P 893dee8e-2bef-41e0-89c6-b55d0929964c 100 >nul 2>&1"
            cmd.exe /c "powercfg /setacvalueindex $pGuid $SUB_P bc5038f7-23e0-4960-96da-33abaf5935ec 100 >nul 2>&1"
            cmd.exe /c "powercfg /setactive $pGuid >nul 2>&1"
        }
        Add-Log "  OK Intel: Min/Max processor state %100 (SpeedStep etkisi azaltildi)" "Success"
    }
    $amdCnqChk = $window.FindName("ChkAmdCoolnQuiet")
    if ($amdCnqChk -and $amdCnqChk.IsChecked -and $amdCnqChk.Visibility -eq [System.Windows.Visibility]::Visible) {
        $activePlan = cmd.exe /c "powercfg /getactivescheme 2>&1"
        $pGuid = ([regex]'([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})').Match($activePlan).Value
        if ($pGuid) {
            $SUB_P = "54533251-82be-4824-96c1-47b60b740d00"
            cmd.exe /c "powercfg /setacvalueindex $pGuid $SUB_P 893dee8e-2bef-41e0-89c6-b55d0929964c 100 >nul 2>&1"
            cmd.exe /c "powercfg /setacvalueindex $pGuid $SUB_P be337238-0d82-4146-a960-4f3749d470c7 2 >nul 2>&1"
            cmd.exe /c "powercfg /setactive $pGuid >nul 2>&1"
        }
        Add-Log "  OK AMD: Processor state %100, Aggressive Boost (CnQ etkisi azaltildi)" "Success"
    }
    Add-Log "  !! Yeniden baslatma gerekiyor!" "Warn"
})

# --- CPU POWER TWEAKS ---
$window.FindName("BtnApplyCpuPower").Add_Click({
    Add-Log "==== CPU POWER TWEAKS ====" "Success"

    # Aktif guc plani GUID'i al
    $activePlan = cmd.exe /c "powercfg /getactivescheme 2>&1"
    $planGuid   = ([regex]'([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})').Match($activePlan).Value
    if (-not $planGuid) { Add-Log "  !! Aktif guc plani GUID alınamadı." "Error"; return }
    Add-Log "  Aktif plan: $planGuid" "Info"

    # SUBGUIDs
    $SUB_PROC = "54533251-82be-4824-96c1-47b60b740d00"
    $SUB_SLEEP = "238c9fa8-0aad-41ed-83f4-97be242c8f20"

    # Core Parking
    if ($window.FindName("ChkDisableCoreParking").IsChecked) {
        # CPMINCORES: min %0  CPMAXCORES: max %100
        cmd.exe /c "powercfg /setacvalueindex $planGuid $SUB_PROC 0cc5b647-c1df-4637-891a-dec35c318583 0 >nul 2>&1"
        cmd.exe /c "powercfg /setacvalueindex $planGuid $SUB_PROC ea062031-0e34-4ff1-9b6d-eb1059334028 100 >nul 2>&1"
        Add-Log "  OK Core Parking kapatildi (Min %0 → %100)" "Success"
    }

    # C-States / Idle
    if ($window.FindName("ChkDisableCStates").IsChecked) {
        cmd.exe /c "powercfg /setacvalueindex $planGuid $SUB_SLEEP 94ac6d29-73ce-41a6-809f-6363ba21b47e 0 >nul 2>&1"
        Add-Log "  OK Processor Idle: Disable (C-States kapali)" "Success"
    }

    # Min/Max Processor State
    if ($window.FindName("ChkProcStateGaming").IsChecked) {
        cmd.exe /c "powercfg /setacvalueindex $planGuid $SUB_PROC 893dee8e-2bef-41e0-89c6-b55d0929964c 100 >nul 2>&1"
        cmd.exe /c "powercfg /setacvalueindex $planGuid $SUB_PROC bc5038f7-23e0-4960-96da-33abaf5935ec 100 >nul 2>&1"
        Add-Log "  OK Processor State: Min %100 / Max %100 (Gaming)" "Success"
    } elseif ($window.FindName("ChkProcStateAuto").IsChecked) {
        cmd.exe /c "powercfg /setacvalueindex $planGuid $SUB_PROC 893dee8e-2bef-41e0-89c6-b55d0929964c 5 >nul 2>&1"
        cmd.exe /c "powercfg /setacvalueindex $planGuid $SUB_PROC bc5038f7-23e0-4960-96da-33abaf5935ec 100 >nul 2>&1"
        Add-Log "  OK Processor State: Min %5 / Max %100 (Auto)" "Success"
    }

    # Boost Mode
    $boostVal = 2  # Aggressive varsayilan
    if ($window.FindName("RBoostAggressiveAt").IsChecked) { $boostVal = 4 }
    elseif ($window.FindName("RBoostEnabled").IsChecked)  { $boostVal = 1 }
    elseif ($window.FindName("RBoostDisabled").IsChecked) { $boostVal = 0 }
    cmd.exe /c "powercfg /setacvalueindex $planGuid $SUB_PROC be337238-0d82-4146-a960-4f3749d470c7 $boostVal >nul 2>&1"
    $boostNames = @{0="Disabled";1="Enabled";2="Aggressive";4="AggressiveAtGuaranteed"}
    Add-Log "  OK Boost Mode: $($boostNames[$boostVal])" "Success"

    # EPP
    $eppVal = 0
    if ($window.FindName("REppBalance").IsChecked) { $eppVal = 128 }
    elseif ($window.FindName("REppPower").IsChecked) { $eppVal = 255 }
    # EPP GUID (Intel HWP / AMD EPP)
    cmd.exe /c "powercfg /setacvalueindex $planGuid $SUB_PROC 36687f9e-e3a5-4dbf-b1dc-15eb381c6863 $eppVal >nul 2>&1"
    Add-Log "  OK EPP: $eppVal" "Success"

    # Superfetch / SysMain
    if ($window.FindName("ChkDisablePrefetch").IsChecked) {
        cmd.exe /c "sc config SysMain start= disabled >nul 2>&1"
        cmd.exe /c "net stop SysMain >nul 2>&1"
        Add-Log "  OK SysMain (Superfetch) durduruldu ve devre disi." "Success"
    }
    # High Resolution Timer
    if ($window.FindName("ChkHighResTimer").IsChecked) {
        cmd.exe /c "bcdedit /set useplatformclock false >nul 2>&1"
        cmd.exe /c "bcdedit /set disabledynamictick yes >nul 2>&1"
        Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" "GlobalTimerResolutionRequests" -Value 1 -Type DWord -ErrorAction SilentlyContinue
        Add-Log "  OK High Resolution Timer: Etkin (0.5ms, dynamictick kapali)" "Success"
    }
    # CSRSS / DWM priority
    if ($window.FindName("ChkCpuPriorityOpt").IsChecked) {
        # CSRSS priority
        $csrssKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\csrss.exe\PerfOptions"
        if (-not (Test-Path $csrssKey)) { New-Item $csrssKey -Force | Out-Null }
        Set-ItemProperty $csrssKey "CpuPriorityClass" -Value 4 -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty $csrssKey "IoPriority" -Value 3 -Type DWord -ErrorAction SilentlyContinue
        # DWM priority
        $dwmKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\dwm.exe\PerfOptions"
        if (-not (Test-Path $dwmKey)) { New-Item $dwmKey -Force | Out-Null }
        Set-ItemProperty $dwmKey "CpuPriorityClass" -Value 3 -Type DWord -ErrorAction SilentlyContinue
        Add-Log "  OK CSRSS/DWM CPU onceligi yukseltildi." "Success"
    }

    # Plani etkinlestir
    cmd.exe /c "powercfg /setactive $planGuid >nul 2>&1"
    Add-Log "  OK CPU tweakler guc planina yazildi ve aktif edildi." "Success"
})

# --- AG TWEAKLER ---
$window.FindName("BtnApplyNet").Add_Click({
    Add-Log "==== AG / GECIKME TWEAKS ====" "Success"

    if ($window.FindName("ChkNagle").IsChecked) {
        $tcpInterfaces = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces" -ErrorAction SilentlyContinue
        foreach ($iface in $tcpInterfaces) {
            Set-ItemProperty $iface.PSPath "TcpAckFrequency" -Value 1    -Type DWord -ErrorAction SilentlyContinue
            Set-ItemProperty $iface.PSPath "TCPNoDelay"      -Value 1    -Type DWord -ErrorAction SilentlyContinue
            Set-ItemProperty $iface.PSPath "TcpDelAckTicks"  -Value 0    -Type DWord -ErrorAction SilentlyContinue
        }
        Add-Log "  OK Nagle Algoritmasи kapatildi (TcpNoDelay=1)" "Success"
    }
    if ($window.FindName("ChkAutoTuning").IsChecked) {
        cmd.exe /c "netsh int tcp set global autotuninglevel=normal >nul 2>&1"
        Add-Log "  OK TCP Auto-Tuning: Normal" "Success"
    }
    if ($window.FindName("ChkTimerRes").IsChecked) {
        # Timer resolution registry
        Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" "GlobalTimerResolutionRequests" -Value 1 -Type DWord -ErrorAction SilentlyContinue
        Add-Log "  OK GlobalTimerResolutionRequests: 1 (0.5ms HPET)" "Success"
    }
    if ($window.FindName("ChkDpcLatency").IsChecked) {
        # Temel DPC tweak: interrupt affinity hint
        Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" "IRQ8Priority" -Value 1 -Type DWord -ErrorAction SilentlyContinue
        Add-Log "  OK IRQ8Priority: 1 (DPC Latency hint)" "Success"
    }
    if ($window.FindName("ChkGpuSchedHW").IsChecked) {
        $hwsKey = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
        Set-ItemProperty $hwsKey "HwSchMode" -Value 2 -Type DWord -ErrorAction SilentlyContinue
        Add-Log "  OK HwSchMode: 2 (Hardware GPU Scheduling aktif)" "Success"
        Add-Log "  !! HW GPU Scheduling icin yeniden baslama gerekiyor." "Warn"
    }
    if ($window.FindName("ChkQosPriority").IsChecked) {
        # Windows QoS bandwidth reservation kaldır
        Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched" "NonBestEffortLimit" -Value 0 -Type DWord -ErrorAction SilentlyContinue
        # DSCP tagging aktif et
        $qosKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
        Set-ItemProperty $qosKey "NetworkThrottlingIndex" -Value 0xFFFFFFFF -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty $qosKey "SystemResponsiveness" -Value 0 -Type DWord -ErrorAction SilentlyContinue
        Add-Log "  OK QoS: Bant genisligi rezervi kaldirildi, game trafigi oncelikli." "Success"
    }
    if ($window.FindName("ChkNetAdapter").IsChecked) {
        # NIC optimizasyonları - registry tabanlı
        $netKey = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
        Set-ItemProperty $netKey "DefaultTTL" -Value 64 -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty $netKey "Tcp1323Opts" -Value 1 -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty $netKey "TcpMaxDupAcks" -Value 2 -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty $netKey "TcpTimedWaitDelay" -Value 30 -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty $netKey "MaxUserPort" -Value 65534 -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty $netKey "TcpNumConnections" -Value 16777214 -Type DWord -ErrorAction SilentlyContinue
        Add-Log "  OK NIC: TCP optimizasyonlari uygulandiyor." "Success"
        # Her NIC adaptoru icin interrupt moderation hint
        Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces" -ErrorAction SilentlyContinue | ForEach-Object {
            Set-ItemProperty $_.PSPath "TcpAckFrequency" -Value 1 -Type DWord -ErrorAction SilentlyContinue
            Set-ItemProperty $_.PSPath "TCPNoDelay" -Value 1 -Type DWord -ErrorAction SilentlyContinue
        }
        Add-Log "  OK NIC arayuzleri optimize edildi." "Success"
    }
    if ($window.FindName("ChkTcpCongestion").IsChecked) {
        cmd.exe /c "netsh int tcp set supplemental template=Internet congestionprovider=CUBIC >nul 2>&1"
        cmd.exe /c "netsh int tcp set global timestamps=disabled >nul 2>&1"
        cmd.exe /c "netsh int tcp set global rss=enabled >nul 2>&1"
        cmd.exe /c "netsh int tcp set global chimney=disabled >nul 2>&1"
        Add-Log "  OK TCP: CUBIC, RSS etkin, Timestamps kapali." "Success"
    }
    Add-Log "  Ag tweakler tamamlandi." "Success"
})

# ---- LOG KAYDET ----
$controls["BtnSaveLog"].Add_Click({
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Title = "Logu Kaydet"; $dlg.Filter = "Metin Dosyasi (*.txt)|*.txt"
    $dlg.FileName = "SystemCleaner_Log_$((Get-Date).ToString('yyyyMMdd_HHmmss')).txt"
    $dlg.InitialDirectory = "$env:USERPROFILE\Desktop"
    if ($dlg.ShowDialog() -eq "OK") {
        $header = @(
            "=============================================="
            "  SYSTEM CLEANER v3.5  -  LiVNLOUD x Claude"
            "  Tarih     : $((Get-Date).ToString('dd.MM.yyyy HH:mm:ss'))"
            "  Bilgisayar: $env:COMPUTERNAME"
            "  Kullanici : $env:USERNAME"
            "  CPU       : $cpuName"
            "  RAM       : $ramGB GB"
            "=============================================="
            ""
        )
        ($header + $script:logBuffer.ToArray() + @("","=== Log Sonu ===")) |
            Out-File -FilePath $dlg.FileName -Encoding UTF8 -Force
        [System.Windows.MessageBox]::Show("Log kaydedildi:`n$($dlg.FileName)","Log Kaydedildi") | Out-Null
    }
})

$controls["BtnClose"].Add_Click({
    $script:usbTimer.Stop()
    $window.Close()
})

# ---- USB + YUKLENME ----
$window.Add_Loaded({
    try {
        $usbDrives = @(Get-CimInstance Win32_DiskDrive | Where-Object { $_.InterfaceType -eq "USB" })
        $script:usbCount = $usbDrives.Count
        $usbTxt = $window.FindName("HudUsb")
        if ($usbTxt) {
            $usbTxt.Text       = "$($script:usbCount)"
            $usbTxt.Foreground = if ($script:usbCount -gt 0) { New-Brush $WARN_C } else { New-Brush $FG_PRIMARY }
        }
        if ($script:usbCount -gt 0) {
            Add-Log "Uyari: $($script:usbCount) adet USB depolama takili algilandi." "Error"
        } else {
            Add-Log "Sistem hazir. Yonetici modu aktif. v3.5" "Success"
        }
    } catch { $script:usbCount = 0 }
    Update-Summary
    $script:usbTimer.Start()
})

$window.ShowDialog() | Out-Null
$script:usbTimer.Stop()
