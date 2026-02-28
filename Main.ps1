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
$ErrorActionPreference = 'SilentlyContinue'
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
                        <TextBlock Text="&#xE9F0;" FontFamily="Segoe MDL2 Assets" FontSize="12"
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

                <!-- Clock -->
                <StackPanel Grid.Column="3" VerticalAlignment="Center" HorizontalAlignment="Right" Margin="0,0,4,0">
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
                <Button x:Name="BtnPresetScan" Style="{StaticResource BtnSuccess}"
                        Padding="8,4" Margin="0,0,5,0" Height="26" ToolTip="Sistemi tara, mevcut ayarlari oku">
                    <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                        <TextBlock Text="&#xE72E;" FontFamily="Segoe MDL2 Assets" FontSize="11" VerticalAlignment="Center" Margin="0,2,0,0"/>
                        <TextBlock Text=" Get Installed" FontSize="11" VerticalAlignment="Center" Margin="3,0,0,0"/>
                    </StackPanel>
                </Button>

                <Separator Width="1" Height="20" Background="#2A2B4A" Margin="8,0"/>

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
                    <ScrollViewer DockPanel.Dock="Top" VerticalScrollBarVisibility="Auto">
                        <TreeView x:Name="NavTree" Background="Transparent" BorderThickness="0"
                                  Margin="8,0">

                            <!-- TEMIZLIK -->
                            <TreeViewItem Style="{StaticResource NavItem}" FontSize="12">
                                <TreeViewItem.Header>
                                    <Grid UseLayoutRounding="True" SnapsToDevicePixels="True">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="20"/>
                                            <ColumnDefinition Width="*"/>
                                        </Grid.ColumnDefinitions>
                                        <Border Grid.Column="0" Width="16" Height="16" HorizontalAlignment="Center" VerticalAlignment="Center">
                                        <TextBlock Text="&#xECCE;" FontFamily="Segoe MDL2 Assets" FontSize="14" Foreground="#9898B0" HorizontalAlignment="Center" VerticalAlignment="Center" LineHeight="14" Padding="0" Margin="0,1,0,0"/>
                                    </Border>
                                        <TextBlock Grid.Column="1" Text=" Temizlik" FontSize="12" FontWeight="SemiBold" Foreground="#9898B0" VerticalAlignment="Center" LineHeight="14" Padding="0"/>
                                    </Grid>
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
                                        <TextBlock Text="&#xE9E9;" FontFamily="Segoe MDL2 Assets" FontSize="14" Foreground="#FF9800" HorizontalAlignment="Center" VerticalAlignment="Center" LineHeight="14" Padding="0" Margin="0,1,0,0"/>
                                    </Border>
                                        <TextBlock Grid.Column="1" Text="  Advanced Clean" FontSize="12" VerticalAlignment="Center" LineHeight="14" Padding="0"/>
                                    </Grid>
                                    </TreeViewItem.Header>
                                </TreeViewItem>
                            </TreeViewItem>

                            <!-- OPTIMIZASYON -->
                            <TreeViewItem Style="{StaticResource NavItem}" FontSize="12" Margin="0,4,0,0">
                                <TreeViewItem.Header>
                                    <Grid UseLayoutRounding="True" SnapsToDevicePixels="True">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="20"/>
                                            <ColumnDefinition Width="*"/>
                                        </Grid.ColumnDefinitions>
                                        <Border Grid.Column="0" Width="16" Height="16" HorizontalAlignment="Center" VerticalAlignment="Center">
                                        <TextBlock Text="&#xE9F9;" FontFamily="Segoe MDL2 Assets" FontSize="14" Foreground="#9898B0" HorizontalAlignment="Center" VerticalAlignment="Center" LineHeight="14" Padding="0" Margin="0,1,0,0"/>
                                    </Border>
                                        <TextBlock Grid.Column="1" Text=" Optimizasyon" FontSize="12" FontWeight="SemiBold" Foreground="#9898B0" VerticalAlignment="Center" LineHeight="14" Padding="0"/>
                                    </Grid>
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

                    <!-- Bottom sidebar info -->
                    <Border DockPanel.Dock="Bottom" Margin="8,0,8,8" Padding="10,8"
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
                        <GroupBox Header="TARAYICI &amp; UYGULAMA ONBELLEGI">
                            <WrapPanel>
                                <CheckBox x:Name="ChkChromeCache"  Content="Chrome Cache"     Margin="0,4,20,4" ToolTip="Google Chrome tarayici onbellegini temizler." IsChecked="True"/>
                                <CheckBox x:Name="ChkEdgeCache"    Content="Edge Cache"        Margin="0,4,20,4" ToolTip="Microsoft Edge tarayici onbellegini temizler." IsChecked="True"/>
                                <CheckBox x:Name="ChkFirefoxCache" Content="Firefox Cache"     Margin="0,4,20,4" ToolTip="Mozilla Firefox tarayici onbellegini temizler." IsChecked="False"/>
                                <CheckBox x:Name="ChkSteamCache"   Content="Steam Shader Cache" Margin="0,4,20,4" ToolTip="Steam shader cache dosyalarini temizler." IsChecked="False"/>
                                <CheckBox x:Name="ChkDNSCache"     Content="DNS Cache Flush"   Margin="0,4,20,4" ToolTip="DNS cozumleme onbellegini temizler (ipconfig /flushdns)." IsChecked="True"/>
                            </WrapPanel>
                        </GroupBox>
                        <GroupBox Header="LOG &amp; HATA RAPORLARI">
                            <WrapPanel>
                                <CheckBox x:Name="ChkEventLogs"   Content="Windows Event Logs"       Margin="0,4,20,4" ToolTip="Windows olay gunluklerini temizler. Sorun giderme kayitlari silinir." IsChecked="False"/>
                                <CheckBox x:Name="ChkCrashDumps"  Content="Crash Dumps (*.dmp)"       Margin="0,4,20,4" ToolTip="Sistem cokme dump dosyalarini (*.dmp) siler." IsChecked="True"/>
                                <CheckBox x:Name="ChkWinUpdCache" Content="Windows Update Cache"      Margin="0,4,20,4" ToolTip="Windows Update indirme onbellegini temizler. Guncelleme yeniden indirilir." IsChecked="False"/>
                                <CheckBox x:Name="ChkDeliveryOpt" Content="Delivery Optimization Files" Margin="0,4,20,4" ToolTip="Windows Delivery Optimization dosyalarini temizler." IsChecked="True"/>
                            </WrapPanel>
                        </GroupBox>
                        <!-- Space at bottom for terminal -->
                        <Border Height="12"/>
                    </StackPanel>

                    <!-- ===== ADVANCED CLEAN PAGE ===== -->
                    <StackPanel x:Name="PageAdvancedClean" Visibility="Collapsed">
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
                                    <TextBlock Text="&#xE9E9;" FontFamily="Segoe MDL2 Assets" FontSize="20" Foreground="#FF9800" VerticalAlignment="Center" Margin="0,3,0,0"/>
                                    <TextBlock Text="  Advanced Clean" FontSize="20" FontWeight="Bold" Foreground="#E8E8F0" VerticalAlignment="Center"/>
                                </StackPanel>
                        <TextBlock Text="Gelismis sistem temizligi. Bazi islemler yeniden baslatma gerektirebilir."
                                   FontSize="12" Foreground="#FF9800" Margin="0,0,0,16"/>

                        <WrapPanel>
                            <Button x:Name="BtnRunAdvClean" 
                                    Style="{StaticResource BtnAccent}" Margin="0,0,10,0" Height="36" FontSize="13">
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock Text="&#xE9E9;" FontFamily="Segoe MDL2 Assets" FontSize="12" VerticalAlignment="Center" LineHeight="14" Padding="0" Margin="0,2,0,0"/>
                                <TextBlock Text=" Gelismis Temizligi Baslat" FontSize="12" VerticalAlignment="Center" Margin="4,0,0,0"/>
                            </StackPanel>
                        </Button>
                        </WrapPanel>

                        <GroupBox Header="WINSxS &amp; COMPONENT STORE" Margin="0,14,0,0">
                            <WrapPanel>
                                <CheckBox x:Name="ChkWinSxS"      Content="WinSxS Cleanup (DISM)"  Margin="0,4,20,4" ToolTip="DISM ile WinSxS Component Store temizligi yapar. Zaman alabilir." IsChecked="False"/>
                                <CheckBox x:Name="ChkSuperFetch"   Content="Disable SuperFetch/SysMain" Margin="0,4,20,4" ToolTip="SysMain servisini devre disi birakir. HDD sistemlerde faydali." IsChecked="False"/>
                                <CheckBox x:Name="ChkHibernation"  Content="Hibernation Dosyasi (hiberfil.sys)" Margin="0,4,20,4" ToolTip="Hibernation dosyasini siler (hiberfil.sys). Disk alani kazanir." IsChecked="False"/>
                                <CheckBox x:Name="ChkPageFile"     Content="PageFile Temizle (Shutdown)" Margin="0,4,20,4" ToolTip="Kapanista PageFile dosyasini temizler. Gizlilik icin onerilir." IsChecked="False"/>
                            </WrapPanel>
                        </GroupBox>
                        <GroupBox Header="SFC &amp; DISK CHECK">
                            <WrapPanel>
                                <CheckBox x:Name="ChkSFC"          Content="SFC /scannow"          Margin="0,4,20,4" ToolTip="System File Checker calistirir (sfc /scannow). Bozuk dosyalari onarir." IsChecked="False"/>
                                <CheckBox x:Name="ChkDISM"         Content="DISM Health Restore"   Margin="0,4,20,4" ToolTip="DISM Health Restore calistirir. Sistem imajini onarir." IsChecked="False"/>
                                <CheckBox x:Name="ChkDiskCleanup"  Content="Disk Cleanup (cleanmgr)" Margin="0,4,20,4" ToolTip="Windows Disk Cleanup aracini calistirir (cleanmgr)." IsChecked="True"/>
                            </WrapPanel>
                        </GroupBox>
                        <GroupBox Header="RAM OPTIMIZASYONU">
                            <WrapPanel>
                                <CheckBox x:Name="ChkEmptyRAM"     Content="Standby List Temizle"  Margin="0,4,20,4" ToolTip="RAM standby listesini temizler. Anlik bellek kullanimini dusurebilir." IsChecked="True"/>
                                <CheckBox x:Name="ChkModifiedRAM"  Content="Modified List Temizle" Margin="0,4,20,4" ToolTip="Degistirilmis bellek sayfalarini temizler." IsChecked="True"/>
                            </WrapPanel>
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
                        </WrapPanel>

                        <GroupBox Header="GUC PLANI" Margin="0,14,0,0">
                            <StackPanel>
                                <WrapPanel Margin="0,0,0,8">
                                    <Button x:Name="BtnPlanBitsum"     Style="{StaticResource BtnAccent}" Margin="0,0,8,0" Height="30" FontSize="11">
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock Text="&#xE945;" FontFamily="Segoe MDL2 Assets" FontSize="12" VerticalAlignment="Center" LineHeight="14" Padding="0" Margin="0,2,0,0"/>
                                <TextBlock Text=" Bitsum Highest" FontSize="12" VerticalAlignment="Center" Margin="4,0,0,0"/>
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
                                <CheckBox x:Name="ChkWUpdate"     Content="Windows Update Gecikmeli"    Margin="0,4,20,4" ToolTip="ChkWUpdate ayarini degistirir." IsChecked="False"/>
                                <CheckBox x:Name="ChkGameMode"    Content="Game Mode Etkin"             Margin="0,4,20,4" ToolTip="Windows Game Mode aktiflestirilir. Oyun sirasinda arka plan kisitlanir." IsChecked="True"/>
                                <CheckBox x:Name="ChkHwAccel"     Content="Hardware-Accelerated GPU Scheduling" Margin="0,4,20,4" ToolTip="Hardware-Accelerated GPU Scheduling aktiflestirilir. Guncel GPU gerektirir." IsChecked="True"/>
                            </WrapPanel>
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
                                    Style="{StaticResource BtnDanger}" Height="36">
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock Text="&#xE72C;" FontFamily="Segoe MDL2 Assets" FontSize="12" VerticalAlignment="Center" LineHeight="14" Padding="0" Margin="0,2,0,0"/>
                                <TextBlock Text=" TCP/IP Sifirla" FontSize="12" VerticalAlignment="Center" Margin="4,0,0,0"/>
                            </StackPanel>
                        </Button>
                        </WrapPanel>

                        <GroupBox Header="TCP/IP OPTIMIZASYONU" Margin="0,14,0,0">
                            <WrapPanel>
                                <CheckBox x:Name="ChkAutoTuning"   Content="Autotuning Kapat (Normal→Disabled)" Margin="0,4,20,4" ToolTip="TCP Receive Window Auto-Tuning devre disi birakilir." IsChecked="True"/>
                                <CheckBox x:Name="ChkECN"          Content="ECN Capability Kapat"               Margin="0,4,20,4" ToolTip="ECN (Explicit Congestion Notification) devre disi birakilir." IsChecked="True"/>
                                <CheckBox x:Name="ChkRSC"          Content="RSC (Receive Segment Coalescing) Kapat" Margin="0,4,20,4" ToolTip="Receive Segment Coalescing devre disi birakilir. Latency duser." IsChecked="True"/>
                                <CheckBox x:Name="ChkCongestion"   Content="CUBIC → CTCP (Compound TCP)"        Margin="0,4,20,4" ToolTip="TCP congestion algoritmasi CTCP olarak optimize edilir." IsChecked="True"/>
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
                                <CheckBox x:Name="ChkIntMod"      Content="Interrupt Moderation Kapat"          Margin="0,4,20,4" ToolTip="Interrupt Moderation devre disi birakilir. CPU kullanimi artar, latency duser." IsChecked="True"/>
                                <CheckBox x:Name="ChkGreenEth"    Content="Green Ethernet / EEE Kapat"          Margin="0,4,20,4" ToolTip="Green Ethernet guc tasarrufu devre disi birakilir." IsChecked="True"/>
                                <CheckBox x:Name="ChkGigaLite"    Content="Giga Lite Kapat"                     Margin="0,4,20,4" ToolTip="Gigabit Lite modu devre disi birakilir." IsChecked="True"/>
                                <CheckBox x:Name="ChkAdaptInter"  Content="Adaptive Inter-Frame Spacing Kapat"  Margin="0,4,20,4" ToolTip="ChkAdaptInter ayarini degistirir." IsChecked="False"/>
                                <TextBlock x:Name="TxtAdapterInfo" Text="Adaptor bilgisi icin 'Adaptorleri Tara' tikla."
                                           FontSize="10" Foreground="#9898B0" Margin="0,6,0,0"/>
                            </StackPanel>
                        </GroupBox>

                        <GroupBox Header="DNS">
                            <WrapPanel>
                                <CheckBox x:Name="ChkDNSPrefetch" Content="DNS Prefetch Etkin"       Margin="0,4,20,4" ToolTip="ChkDNSPrefetch ayarini degistirir." IsChecked="True"/>
                                <CheckBox x:Name="ChkMDNS"        Content="mDNS Kapat"               Margin="0,4,20,4" ToolTip="mDNS devre disi birakilir." IsChecked="False"/>
                                <CheckBox x:Name="ChkLLMNR"       Content="LLMNR Kapat"              Margin="0,4,20,4" ToolTip="LLMNR devre disi birakilir. Ag guvenligi artar." IsChecked="True"/>
                            </WrapPanel>
                        </GroupBox>
                        <Border Height="12"/>
                    </StackPanel>

                    <!-- ===== KERNEL & INPUT PAGE ===== -->
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
                        </WrapPanel>

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
                                <CheckBox x:Name="ChkSecondLevelCache" Content="SecondLevelDataCache Optimize"   Margin="0,4,20,4" ToolTip="CPU L2/L3 onbellek boyutu registry ile eslestirilerek bellek optimize edilir." IsChecked="True"/>
                                <CheckBox x:Name="ChkPagingFiles"   Content="PageFile Optimize"                  Margin="0,4,20,4" ToolTip="ChkPagingFiles ayarini degistirir." IsChecked="False"/>
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

                    <!-- ===== GPU & MSI PAGE ===== -->
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
                                    Style="{StaticResource BtnAccent}" Height="36">
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock Text="&#xE74E;" FontFamily="Segoe MDL2 Assets" FontSize="12" VerticalAlignment="Center" LineHeight="14" Padding="0" Margin="0,2,0,0"/>
                                <TextBlock Text=" Uygula" FontSize="12" VerticalAlignment="Center" Margin="4,0,0,0"/>
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
                                <TextBlock x:Name="TxtGPUInfo" Text="GPU algilanmadi. 'GPU Algila' butonuna tikla."
                                           FontSize="12" Foreground="#E8E8F0" Margin="0,6,0,0"/>
                            </StackPanel>
                        </Border>

                        <GroupBox Header="MSI MODE (Message Signaled Interrupts)" Margin="0,8,0,0">
                            <StackPanel>
                                <TextBlock Text="MSI Mode, PCIe cihazlarinin (GPU, NVMe, NIC) interrupt islemlerini optimize eder. DPC/ISR gecikmelerini azaltir."
                                           FontSize="10" Foreground="#9898B0" TextWrapping="Wrap" Margin="0,0,0,8"/>
                                <WrapPanel>
                                    <CheckBox x:Name="ChkMSIGPU"    Content="GPU MSI Mode"      Margin="0,4,20,4" ToolTip="GPU icin MSI modu aktiflestirilir. DPC/ISR latency duser." IsChecked="True"/>
                                    <CheckBox x:Name="ChkMSINVMe"   Content="NVMe MSI Mode"     Margin="0,4,20,4" ToolTip="NVMe SSD icin MSI modu aktiflestirilir." IsChecked="True"/>
                                    <CheckBox x:Name="ChkMSINIC"    Content="NIC MSI Mode"      Margin="0,4,20,4" ToolTip="ChkMSINIC ayarini degistirir." IsChecked="False"/>
                                    <CheckBox x:Name="ChkMSIPrio"   Content="MSI IRQ Priority Yukselt" Margin="0,4,20,4" ToolTip="MSI Interrupt Priority HIGH olarak ayarlanir." IsChecked="True"/>
                                </WrapPanel>
                            </StackPanel>
                        </GroupBox>

                        <GroupBox Header="NVIDIA LATENCY OPTIMIZASYONU">
                            <WrapPanel>
                                <CheckBox x:Name="ChkNvPrerender"   Content="Max Pre-Rendered Frames = 1"      Margin="0,4,20,4" ToolTip="NVIDIA pre-rendered frame sayisi 1e dusurulur. Input latency azalir." IsChecked="True"/>
                                <CheckBox x:Name="ChkNvPower"       Content="Prefer Max Performance"           Margin="0,4,20,4" ToolTip="NVIDIA GPU maksimum performans moduna kilitlenir." IsChecked="True"/>
                                <CheckBox x:Name="ChkNvSync"        Content="V-Sync Kapat (Driver)"            Margin="0,4,20,4" ToolTip="NVIDIA V-Sync (driver) devre disi birakilir." IsChecked="True"/>
                                <CheckBox x:Name="ChkNvShaderCache" Content="Shader Cache Etkin"               Margin="0,4,20,4" ToolTip="ChkNvShaderCache ayarini degistirir." IsChecked="True"/>
                                <CheckBox x:Name="ChkNvTexFilter"   Content="Texture Filter Quality = High Perf" Margin="0,4,20,4" ToolTip="ChkNvTexFilter ayarini degistirir." IsChecked="False"/>
                                <CheckBox x:Name="ChkNvFastSync"    Content="Ultra Low Latency Mode"           Margin="0,4,20,4" ToolTip="NVIDIA frame delay optimizasyonu uygulanir." IsChecked="True"/>
                            </WrapPanel>
                        </GroupBox>

                        <GroupBox Header="AMD LATENCY OPTIMIZASYONU">
                            <WrapPanel>
                                <CheckBox x:Name="ChkAMDAntiLag"   Content="Anti-Lag Etkin (Registry)"    Margin="0,4,20,4" ToolTip="AMD Anti-Lag aktiflestirilir. Input latency azalir." IsChecked="True"/>
                                <CheckBox x:Name="ChkAMDChill"     Content="AMD Chill Kapat"               Margin="0,4,20,4" ToolTip="AMD Chill dinamik kare hizi kontrolu devre disi birakilir." IsChecked="True"/>
                                <CheckBox x:Name="ChkAMDPower"     Content="Profile: Max Performance"      Margin="0,4,20,4" ToolTip="AMD GPU guc performans modu optimize edilir." IsChecked="True"/>
                            </WrapPanel>
                        </GroupBox>
                        <Border Height="12"/>
                    </StackPanel>

                    <!-- ===== PRIVACY & TELEMETRY PAGE ===== -->
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
                        </WrapPanel>

                        <GroupBox Header="TELEMETRI &amp; TANI" Margin="0,14,0,0">
                            <WrapPanel>
                                <CheckBox x:Name="ChkDiagTrack"      Content="DiagTrack Servisi Kapat"               Margin="0,4,20,4" ToolTip="Connected User Experiences and Telemetry servisi devre disi birakilir." IsChecked="True"/>
                                <CheckBox x:Name="ChkDMWAppSupport"  Content="dmwappushsvc Kapat"                    Margin="0,4,20,4" ToolTip="dmwappushservice (telemetri) servisi devre disi birakilir." IsChecked="True"/>
                                <CheckBox x:Name="ChkCEIP"           Content="CEIP Kapat"                             Margin="0,4,20,4" ToolTip="ChkCEIP ayarini degistirir." IsChecked="True"/>
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
                        </WrapPanel>

                        <GroupBox Header="GORSEL &amp; UI OPTIMIZASYONU" Margin="0,14,0,0">
                            <WrapPanel>
                                <CheckBox x:Name="ChkAnimations"   Content="Animasyonlari Kapat"                  Margin="0,4,20,4" ToolTip="Windows arayuz animasyonlarini devre disi birakir. Daha hizli hissettiren arayuz." IsChecked="True"/>
                                <CheckBox x:Name="ChkTransparency" Content="Transparency Kapat"                   Margin="0,4,20,4" ToolTip="Arayuz seffafligini devre disi birakir. Hafif performans kazanimi." IsChecked="False"/>
                                <CheckBox x:Name="ChkJPEGQuality"  Content="JPEG Kalite %100 (Desktop BG)"        Margin="0,4,20,4" ToolTip="ChkJPEGQuality ayarini degistirir." IsChecked="True"/>
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
                                <CheckBox x:Name="ChkLaunchTo"     Content="Explorer: This PC'de Ac"             Margin="0,4,20,4" ToolTip="Explorer This PCde acilar (Hizli Erisim yerine)." IsChecked="True"/>
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
$BtnPresetScan       = Get-Ctrl 'BtnPresetScan'
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
$BtnPlanBitsum      = Get-Ctrl 'BtnPlanBitsum'
$BtnPlanUlti        = Get-Ctrl 'BtnPlanUlti'
$BtnPlanBalanced    = Get-Ctrl 'BtnPlanBalanced'
$BtnPlanDefault     = Get-Ctrl 'BtnPlanDefault'
$BtnW32BestFPS      = Get-Ctrl 'BtnW32BestFPS'
$BtnW32Balanced     = Get-Ctrl 'BtnW32Balanced'
$BtnW32Default      = Get-Ctrl 'BtnW32Default'
$BtnApplyNetwork    = Get-Ctrl 'BtnApplyNetwork'
$BtnResetNetwork    = Get-Ctrl 'BtnResetNetwork'
$BtnScanAdapters    = Get-Ctrl 'BtnScanAdapters'
$TxtAdapterInfo     = Get-Ctrl 'TxtAdapterInfo'
$BtnApplyKernel     = Get-Ctrl 'BtnApplyKernel'
$BtnDetectGPU       = Get-Ctrl 'BtnDetectGPU'
$TxtGPUInfo         = Get-Ctrl 'TxtGPUInfo'
$BtnApplyGPU        = Get-Ctrl 'BtnApplyGPU'
$BtnApplyPrivacy    = Get-Ctrl 'BtnApplyPrivacy'
$BtnApplyWinTweaks  = Get-Ctrl 'BtnApplyWinTweaks'
$BtnImportScript    = Get-Ctrl 'BtnImportScript'
$BtnRunImported     = Get-Ctrl 'BtnRunImported'
$BtnClearEditor     = Get-Ctrl 'BtnClearEditor'
$ScriptEditor       = Get-Ctrl 'ScriptEditor'

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
$cpuName  = (Get-WmiObject Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1).Name
$osCapt   = (Get-WmiObject Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption
$totalRAM = [math]::Round((Get-WmiObject Win32_ComputerSystem -ErrorAction SilentlyContinue).TotalPhysicalMemory / 1GB, 1)
$TxtCpuName.Text  = if ($cpuName)  { $cpuName -replace '\s+', ' ' } else { 'CPU bilgisi yok' }
$TxtUserPC.Text   = " $env:USERNAME @ $env:COMPUTERNAME"
$TxtOS.Text       = if ($osCapt) { $osCapt } else { 'Windows' }

$HWTimer = [System.Windows.Threading.DispatcherTimer]::new()
$HWTimer.Interval = [TimeSpan]::FromSeconds(2)
$HWTimer.Add_Tick({
    # CPU
    try {
        $cpuVal = [math]::Round($global:CpuCounter.NextValue(), 1)
        $TxtCpuPct.Text   = " $cpuVal%"
        $ProgCpu.Value    = $cpuVal
    } catch {}

    # RAM
    try {
        $os     = Get-WmiObject Win32_OperatingSystem -ErrorAction SilentlyContinue
        $usedGB = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 1)
        $pct    = [math]::Round($usedGB / $totalRAM * 100, 0)
        $TxtRamPct.Text    = " $pct%"
        $ProgRam.Value     = $pct
        $TxtRamDetail.Text = "$usedGB / $totalRAM GB"
    } catch {}

    # Clock + Uptime
    $TxtClock.Text = Get-Date -Format 'HH:mm:ss'
    $TxtDate.Text  = Get-Date -Format 'dd.MM.yyyy'
    try {
        $os2 = Get-WmiObject Win32_OperatingSystem -ErrorAction SilentlyContinue
        $up  = (Get-Date) - $os2.ConvertToDateTime($os2.LastBootUpTime)
        $TxtUptime.Text = "Uptime: $($up.Days)g $($up.Hours)s $($up.Minutes)d"
    } catch {}
})
$HWTimer.Start()

# ─── ASYNC RUNNER ─────────────────────────────────────────────────────────────
# Runs a scriptblock on a background thread, logging output to terminal
function Invoke-Async {
    param([scriptblock]$Block, [string]$TaskName = 'Gorev')
    Set-Busy $true
    Set-Status "$TaskName calisiyor..."
    Write-Log "=== $TaskName BASLADI ===" 'RUN'
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'STA'; $rs.ThreadOptions = 'ReuseThread'; $rs.Open()
    $rs.SessionStateProxy.SetVariable('LogFile',    $global:LogFile)
    $rs.SessionStateProxy.SetVariable('BackupPath', $global:BackupPath)
    $rs.SessionStateProxy.SetVariable('RootPath',   $global:RootPath)
    $rs.SessionStateProxy.SetVariable('Window',     $Window)
    $rs.SessionStateProxy.SetVariable('Terminal',   $Terminal)

    # Pass the Write-Log function as text
    $logFuncDef = ${function:Write-Log}.ToString()

    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript({
        param($logFuncDef, $block, $taskName, $logFile, $backupPath, $rootPath, $win, $term)
        . ([scriptblock]::Create("function Write-Log { $logFuncDef }"))
        & $block
    }).AddArgument($logFuncDef).AddArgument($Block).AddArgument($TaskName).AddArgument($global:LogFile).AddArgument($global:BackupPath).AddArgument($global:RootPath).AddArgument($Window).AddArgument($Terminal)

    $handle = $ps.BeginInvoke()

    # Watch for completion
    $watchTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $watchTimer.Interval = [TimeSpan]::FromMilliseconds(300)
    $watchTimer.Add_Tick({
        if ($handle.IsCompleted) {
            $watchTimer.Stop()
            try { $ps.EndInvoke($handle) } catch {}
            $ps.Dispose(); $rs.Close(); $rs.Dispose()
            Set-Busy $false
            Set-Status "$TaskName tamamlandi."
            Write-Log "=== $TaskName TAMAMLANDI ===" 'OK'
        }
    })
    $watchTimer.Start()
}

# ─── BACKEND: QUICK CLEAN ─────────────────────────────────────────────────────
function Get-CheckVal([string]$name) {
    $c = $Window.FindName($name)
    return ($c -ne $null -and $c.IsChecked -eq $true)
}

$BtnSelectAllQC.Add_Click({
    @('ChkTempWin','ChkTempSys','ChkPrefetch','ChkRecycleBin','ChkThumb','ChkFontCache',
      'ChkChromeCache','ChkEdgeCache','ChkFirefoxCache','ChkSteamCache','ChkDNSCache',
      'ChkEventLogs','ChkCrashDumps','ChkWinUpdCache','ChkDeliveryOpt') | ForEach-Object {
        $c = $Window.FindName($_); if ($c) { $c.IsChecked = $true }
    }
})
$BtnDeselectAllQC.Add_Click({
    @('ChkTempWin','ChkTempSys','ChkPrefetch','ChkRecycleBin','ChkThumb','ChkFontCache',
      'ChkChromeCache','ChkEdgeCache','ChkFirefoxCache','ChkSteamCache','ChkDNSCache',
      'ChkEventLogs','ChkCrashDumps','ChkWinUpdCache','ChkDeliveryOpt') | ForEach-Object {
        $c = $Window.FindName($_); if ($c) { $c.IsChecked = $false }
    }
})

$BtnRunQuickClean.Add_Click({
    # Capture checkbox state on UI thread
    $opts = @{
        TempWin    = (Get-CheckVal 'ChkTempWin')
        TempSys    = (Get-CheckVal 'ChkTempSys')
        Prefetch   = (Get-CheckVal 'ChkPrefetch')
        Recycle    = (Get-CheckVal 'ChkRecycleBin')
        Thumb      = (Get-CheckVal 'ChkThumb')
        FontCache  = (Get-CheckVal 'ChkFontCache')
        Chrome     = (Get-CheckVal 'ChkChromeCache')
        Edge       = (Get-CheckVal 'ChkEdgeCache')
        Firefox    = (Get-CheckVal 'ChkFirefoxCache')
        Steam      = (Get-CheckVal 'ChkSteamCache')
        DNS        = (Get-CheckVal 'ChkDNSCache')
        EventLogs  = (Get-CheckVal 'ChkEventLogs')
        CrashDumps = (Get-CheckVal 'ChkCrashDumps')
        WinUpdCache = (Get-CheckVal 'ChkWinUpdCache')
        DelivOpt   = (Get-CheckVal 'ChkDeliveryOpt')
    }

    Invoke-Async -TaskName 'Quick Clean' -Block {
        function Remove-SafeFolder([string]$path) {
            if (Test-Path $path) {
                try {
                    Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue |
                        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                    Write-Log "Temizlendi: $path" 'OK'
                } catch { Write-Log "Temizlenemedi: $path" 'WARN' }
            } else { Write-Log "Bulunamadi (atliyor): $path" 'INFO' }
        }

        if ($using:opts.TempWin)   { Remove-SafeFolder $env:TEMP }
        if ($using:opts.TempSys)   { Remove-SafeFolder "$env:SystemRoot\Temp" }
        if ($using:opts.Prefetch)  { Remove-SafeFolder "$env:SystemRoot\Prefetch" }
        if ($using:opts.Recycle) {
            Clear-RecycleBin -Force -ErrorAction SilentlyContinue
            Write-Log "Geri Donusum Kutusu temizlendi" 'OK'
        }
        if ($using:opts.Thumb) {
            $thumbPaths = @(
                "$env:LocalAppData\Microsoft\Windows\Explorer\thumbcache_*.db",
                "$env:LocalAppData\Microsoft\Windows\Explorer\iconcache_*.db"
            )
            foreach ($p in $thumbPaths) { Remove-Item $p -Force -ErrorAction SilentlyContinue }
            Write-Log "Thumbnail cache temizlendi" 'OK'
        }
        if ($using:opts.FontCache) {
            Stop-Service 'FontCache'   -Force -ErrorAction SilentlyContinue
            Stop-Service 'FontCache3.0.0.0' -Force -ErrorAction SilentlyContinue
            Remove-Item "$env:LocalAppData\FontCache\*" -Force -Recurse -ErrorAction SilentlyContinue
            Remove-Item "$env:WinDir\ServiceProfiles\LocalService\AppData\Local\FontCache\*" -Force -Recurse -ErrorAction SilentlyContinue
            Start-Service 'FontCache' -ErrorAction SilentlyContinue
            Write-Log "Font cache temizlendi" 'OK'
        }
        if ($using:opts.Chrome)   { Remove-SafeFolder "$env:LocalAppData\Google\Chrome\User Data\Default\Cache" }
        if ($using:opts.Edge)     { Remove-SafeFolder "$env:LocalAppData\Microsoft\Edge\User Data\Default\Cache" }
        if ($using:opts.Firefox) {
            $ffProfiles = "$env:AppData\Mozilla\Firefox\Profiles"
            if (Test-Path $ffProfiles) {
                Get-ChildItem $ffProfiles -Directory | ForEach-Object {
                    Remove-SafeFolder "$($_.FullName)\cache2"
                    Remove-SafeFolder "$($_.FullName)\thumbnails"
                }
            }
        }
        if ($using:opts.Steam)    { Remove-SafeFolder "$env:LocalAppData\Steam\htmlcache" }
        if ($using:opts.DNS) {
            ipconfig /flushdns | Out-Null
            Write-Log "DNS cache temizlendi" 'OK'
        }
        if ($using:opts.EventLogs) {
            try {
                Get-EventLog -List -ErrorAction SilentlyContinue | ForEach-Object {
                    Clear-EventLog -LogName $_.Log -ErrorAction SilentlyContinue
                }
                Write-Log "Event Logs temizlendi" 'OK'
            } catch { Write-Log "Event Logs temizlenemedi: $_" 'WARN' }
        }
        if ($using:opts.CrashDumps) {
            Remove-Item "$env:SystemRoot\*.dmp"  -Force -ErrorAction SilentlyContinue
            Remove-Item "$env:SystemRoot\Minidump\*.dmp" -Force -Recurse -ErrorAction SilentlyContinue
            Remove-Item "$env:LocalAppData\CrashDumps\*.dmp" -Force -ErrorAction SilentlyContinue
            Write-Log "Crash dump dosyalari temizlendi" 'OK'
        }
        if ($using:opts.WinUpdCache) {
            Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
            Remove-SafeFolder "$env:SystemRoot\SoftwareDistribution\Download"
            Start-Service wuauserv -ErrorAction SilentlyContinue
        }
        if ($using:opts.DelivOpt) {
            Remove-SafeFolder "$env:SystemRoot\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache"
        }

        # Disk space report
        $drive = Get-PSDrive C -ErrorAction SilentlyContinue
        if ($drive) {
            $freeGB = [math]::Round($drive.Free / 1GB, 2)
            Write-Log "C:\ Bos Alan: $freeGB GB" 'OK'
        }
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
        EmptyRAM    = (Get-CheckVal 'ChkEmptyRAM')
        ModifiedRAM = (Get-CheckVal 'ChkModifiedRAM')
    }
    Invoke-Async -TaskName 'Advanced Clean' -Block {
        if ($using:opts.WinSxS) {
            Write-Log "DISM WinSxS cleanup baslatiliyor..." 'RUN'
            Dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase 2>&1 | ForEach-Object { Write-Log $_ }
        }
        if ($using:opts.SuperFetch) {
            Set-Service 'SysMain' -StartupType Disabled -ErrorAction SilentlyContinue
            Stop-Service 'SysMain' -Force -ErrorAction SilentlyContinue
            Write-Log "SysMain (SuperFetch) devre disi birakildi" 'OK'
        }
        if ($using:opts.Hibernation) {
            powercfg /h off 2>&1 | Out-Null
            Write-Log "Hibernation kapatildi, hiberfil.sys silindi" 'OK'
        }
        if ($using:opts.PageFile) {
            $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
            Set-ItemProperty -Path $regPath -Name 'ClearPageFileAtShutdown' -Value 1 -ErrorAction SilentlyContinue
            Write-Log "PageFile shutdown temizleme aktif" 'OK'
        }
        if ($using:opts.SFC) {
            Write-Log "SFC /scannow calistiriliyor..." 'RUN'
            sfc /scannow 2>&1 | ForEach-Object { Write-Log $_ }
        }
        if ($using:opts.DISM) {
            Write-Log "DISM RestoreHealth calistiriliyor..." 'RUN'
            DISM /Online /Cleanup-Image /RestoreHealth 2>&1 | ForEach-Object { Write-Log $_ }
        }
        if ($using:opts.DiskCleanup) {
            Write-Log "Disk Cleanup baslatiliyor..." 'RUN'
            # Silent disk cleanup
            $sageset = 65535
            $regClean = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
            @('Active Setup Temp Folders','Downloaded Program Files','Internet Cache Files',
              'Old ChkDsk Files','Recycle Bin','Setup Log Files','Temporary Files',
              'Temporary Setup Files','Thumbnail Cache','Update Cleanup') | ForEach-Object {
                $key = "$regClean\$_"
                if (Test-Path $key) { Set-ItemProperty -Path $key -Name "StateFlags$sageset" -Value 2 -ErrorAction SilentlyContinue }
            }
            Start-Process cleanmgr.exe -ArgumentList "/sagerun:$sageset" -Wait -ErrorAction SilentlyContinue
            Write-Log "Disk Cleanup tamamlandi" 'OK'
        }
        if ($using:opts.EmptyRAM -or $using:opts.ModifiedRAM) {
            # Use EmptyStandbyList if available
            $esPath = Join-Path $using:RootPath "_Files\EmptyStandbyList.exe"
            if (Test-Path $esPath) {
                if ($using:opts.EmptyRAM)    { & $esPath standbylist 2>&1 | ForEach-Object { Write-Log $_ } }
                if ($using:opts.ModifiedRAM) { & $esPath modifiedpagelist 2>&1 | ForEach-Object { Write-Log $_ } }
            } else {
                Write-Log "EmptyStandbyList.exe bulunamadi. RAM optimizasyonu atlandi." 'WARN'
                Write-Log "Indirme: https://wj32.org/wp/software/empty-standby-list/" 'INFO'
            }
        }
    }
})

# ─── BACKEND: PERFORMANCE ─────────────────────────────────────────────────────
$BtnApplyPerf.Add_Click({
    $opts = @{
        HPET         = (Get-CheckVal 'ChkHPET')
        TimerRes     = (Get-CheckVal 'ChkTimerRes')
        CpuPrio      = (Get-CheckVal 'ChkCpuPriority')
        SysMain      = (Get-CheckVal 'ChkSysMain')
        WSearch      = (Get-CheckVal 'ChkWSearch')
        GameMode     = (Get-CheckVal 'ChkGameMode')
        HwAccel      = (Get-CheckVal 'ChkHwAccel')
    }
    Invoke-Async -TaskName 'Performance' -Block {
        Backup-Registry 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'Perf_MemMgmt'

        if ($using:opts.HPET) {
            bcdedit /set useplatformclock false 2>&1 | Out-Null
            bcdedit /set disabledynamictick yes 2>&1 | Out-Null
            bcdedit /deletevalue useplatformtick 2>&1 | Out-Null
            Write-Log "HPET devre disi birakildi (bcdedit)" 'OK'
        }
        if ($using:opts.CpuPrio) {
            $mmPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
            Set-ItemProperty -Path $mmPath -Name 'SystemResponsiveness' -Value 0 -ErrorAction SilentlyContinue
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
        }
        if ($using:opts.SysMain) {
            Set-Service 'SysMain' -StartupType Disabled -ErrorAction SilentlyContinue
            Stop-Service 'SysMain' -Force -ErrorAction SilentlyContinue
            Write-Log "SysMain kapatildi" 'OK'
        }
        if ($using:opts.WSearch) {
            Set-Service 'WSearch' -StartupType Disabled -ErrorAction SilentlyContinue
            Stop-Service 'WSearch' -Force -ErrorAction SilentlyContinue
            Write-Log "Windows Search kapatildi" 'OK'
        }
        if ($using:opts.GameMode) {
            $gmPath = 'HKCU:\Software\Microsoft\GameBar'
            if (-not (Test-Path $gmPath)) { New-Item -Path $gmPath -Force | Out-Null }
            Set-ItemProperty -Path $gmPath -Name 'AllowAutoGameMode' -Value 1 -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $gmPath -Name 'AutoGameModeEnabled' -Value 1 -ErrorAction SilentlyContinue
            Write-Log "Game Mode etkinlestirildi" 'OK'
        }
        if ($using:opts.HwAccel) {
            $hwPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
            Set-ItemProperty -Path $hwPath -Name 'HwSchMode' -Value 2 -Type DWord -ErrorAction SilentlyContinue
            Write-Log "Hardware-Accelerated GPU Scheduling etkinlestirildi" 'OK'
        }
    }
})

# Win32 Priority Buttons
$BtnW32BestFPS.Add_Click({
    Invoke-Async -TaskName 'Win32PrioritySeparation BestFPS' -Block {
        Backup-Registry 'HKLM:\SYSTEM\ControlSet001\Control\PriorityControl' 'Win32Prio'
        Set-ItemProperty -Path 'HKLM:\SYSTEM\ControlSet001\Control\PriorityControl' -Name 'Win32PrioritySeparation' -Value 0x14 -ErrorAction SilentlyContinue
        Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' -Name 'Win32PrioritySeparation' -Value 0x14 -ErrorAction SilentlyContinue
        Write-Log "Win32PrioritySeparation = 0x14 (BestFPS) uygulandi" 'OK'
    }
})
$BtnW32Balanced.Add_Click({
    Invoke-Async -TaskName 'Win32PrioritySeparation Balanced' -Block {
        Backup-Registry 'HKLM:\SYSTEM\ControlSet001\Control\PriorityControl' 'Win32Prio'
        Set-ItemProperty -Path 'HKLM:\SYSTEM\ControlSet001\Control\PriorityControl' -Name 'Win32PrioritySeparation' -Value 0x18 -ErrorAction SilentlyContinue
        Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' -Name 'Win32PrioritySeparation' -Value 0x18 -ErrorAction SilentlyContinue
        Write-Log "Win32PrioritySeparation = 0x18 (Balanced) uygulandi" 'OK'
    }
})
$BtnW32Default.Add_Click({
    Invoke-Async -TaskName 'Win32PrioritySeparation Default' -Block {
        Backup-Registry 'HKLM:\SYSTEM\ControlSet001\Control\PriorityControl' 'Win32Prio'
        Set-ItemProperty -Path 'HKLM:\SYSTEM\ControlSet001\Control\PriorityControl' -Name 'Win32PrioritySeparation' -Value 0x26 -ErrorAction SilentlyContinue
        Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' -Name 'Win32PrioritySeparation' -Value 0x26 -ErrorAction SilentlyContinue
        Write-Log "Win32PrioritySeparation = 0x26 (Default) uygulandi" 'OK'
    }
})

# Power Plans
$BtnPlanBitsum.Add_Click({
    Invoke-Async -TaskName 'Guc Plani - Bitsum Highest' -Block {
        $planPath = Join-Path $using:RootPath '_Files\Bitsum-Highest-Performance.pow'
        if (Test-Path $planPath) {
            $guid = powercfg /import $planPath 2>&1 | Where-Object { $_ -match '[0-9a-f]{8}-' } | ForEach-Object { ($_ -split ' ')[-1] }
            if ($guid) {
                powercfg /setactive $guid 2>&1 | Out-Null
                Write-Log "Bitsum Highest Performance plani aktif edildi (GUID: $guid)" 'OK'
            } else {
                Write-Log "Guc plani GUID alinamadi." 'WARN'
            }
        } else {
            # Try to activate Ultimate Performance built-in
            $existing = powercfg /list | Where-Object { $_ -match 'e9a42b02-d5df-448d-aa00-03f14749eb61' }
            if ($existing) {
                powercfg /setactive e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1 | Out-Null
                Write-Log "Ultimate Performance plani aktif edildi (built-in)" 'OK'
            } else {
                powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1 | Out-Null
                $guid2 = powercfg /list | Where-Object { $_ -match 'e9a42b02' } | ForEach-Object { ($_ -split ' ')[-1] }
                if ($guid2) { powercfg /setactive $guid2 2>&1 | Out-Null }
                Write-Log "Bitsum .pow bulunamadi. Ultimate Performance etkinlestirildi." 'WARN'
            }
        }
    }
})
$BtnPlanUlti.Add_Click({
    Invoke-Async -TaskName 'Guc Plani - Ultimate Performance' -Block {
        powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1 | Out-Null
        $guid = powercfg /list 2>&1 | Where-Object { $_ -match 'e9a42b02' } | ForEach-Object { ($_ -split ' ')[-1] } | Select-Object -First 1
        if ($guid) { powercfg /setactive $guid 2>&1 | Out-Null; Write-Log "Ultimate Performance aktif: $guid" 'OK' }
        else { Write-Log "Ultimate Performance plani bulunamadi" 'WARN' }
    }
})
$BtnPlanBalanced.Add_Click({
    Invoke-Async -TaskName 'Guc Plani - Balanced' -Block {
        powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e 2>&1 | Out-Null
        Write-Log "Balanced guc plani aktif" 'OK'
    }
})
$BtnPlanDefault.Add_Click({
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
    $opts = @{
        AutoTuning  = (Get-CheckVal 'ChkAutoTuning')
        ECN         = (Get-CheckVal 'ChkECN')
        RSC         = (Get-CheckVal 'ChkRSC')
        Congestion  = (Get-CheckVal 'ChkCongestion')
        NetThrottle = (Get-CheckVal 'ChkNetThrottle')
        Nagle       = (Get-CheckVal 'ChkNagle')
        TCPNoDelay  = (Get-CheckVal 'ChkTCPNoDelay')
        TCPACKFreq  = (Get-CheckVal 'ChkTCPACKFreq')
        RSS         = (Get-CheckVal 'ChkRSS')
        FlowCtrl    = (Get-CheckVal 'ChkFlowCtrl')
        IntMod      = (Get-CheckVal 'ChkIntMod')
        GreenEth    = (Get-CheckVal 'ChkGreenEth')
        GigaLite    = (Get-CheckVal 'ChkGigaLite')
        DNSPrefetch = (Get-CheckVal 'ChkDNSPrefetch')
        MDNS        = (Get-CheckVal 'ChkMDNS')
        LLMNR       = (Get-CheckVal 'ChkLLMNR')
    }
    Invoke-Async -TaskName 'Network Tweaks' -Block {
        Backup-Registry 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' 'Network_TCP'

        if ($using:opts.AutoTuning) {
            netsh int tcp set global autotuninglevel=disabled 2>&1 | Out-Null
            Write-Log "TCP AutoTuning kapatildi" 'OK'
        }
        if ($using:opts.ECN) {
            netsh int tcp set global ecncapability=disabled 2>&1 | Out-Null
            Write-Log "ECN kapatildi" 'OK'
        }
        if ($using:opts.RSC) {
            netsh int tcp set global rsc=disabled 2>&1 | Out-Null
            Write-Log "RSC kapatildi" 'OK'
        }
        if ($using:opts.Congestion) {
            netsh int tcp set supplemental template=internet congestionprovider=ctcp 2>&1 | Out-Null
            netsh int tcp set supplemental template=internetcustom congestionprovider=ctcp 2>&1 | Out-Null
            Write-Log "Congestion Provider: CTCP (Compound TCP)" 'OK'
        }
        if ($using:opts.NetThrottle) {
            $mmPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
            Set-ItemProperty -Path $mmPath -Name 'NetworkThrottlingIndex' -Value 0xFFFFFFFF -ErrorAction SilentlyContinue
            Write-Log "NetworkThrottlingIndex = 0xFFFFFFFF (kapali)" 'OK'
        }
        if ($using:opts.Nagle -or $using:opts.TCPNoDelay -or $using:opts.TCPACKFreq) {
            $tcpPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
            if (Test-Path $tcpPath) {
                Get-ChildItem $tcpPath | ForEach-Object {
                    $iface = $_.PSPath
                    if ($using:opts.Nagle)      { Set-ItemProperty -Path $iface -Name 'TcpNoDelay'      -Value 1 -ErrorAction SilentlyContinue }
                    if ($using:opts.TCPNoDelay) { Set-ItemProperty -Path $iface -Name 'TcpDelAckTicks'  -Value 0 -ErrorAction SilentlyContinue }
                    if ($using:opts.TCPACKFreq) { Set-ItemProperty -Path $iface -Name 'TcpAckFrequency' -Value 1 -ErrorAction SilentlyContinue }
                }
            }
            Write-Log "Nagle / TCPNoDelay / TcpAckFrequency uygulandi" 'OK'
        }

        # NIC Adapter tweaks via advanced properties
        if ($using:opts.FlowCtrl -or $using:opts.IntMod -or $using:opts.RSS -or $using:opts.GreenEth -or $using:opts.GigaLite) {
            $adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' }
            foreach ($adapter in $adapters) {
                Write-Log "Adaptor isleniyor: $($adapter.Name)" 'RUN'
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

                if ($using:opts.FlowCtrl)  { Set-NicProp 'Flow Control' 'Disabled' }
                if ($using:opts.IntMod)    { Set-NicProp 'Interrupt Moderation' 'Disabled' }
                if ($using:opts.RSS) {
                    try { Enable-NetAdapterRss -Name $adapter.Name -ErrorAction SilentlyContinue; Write-Log "  RSS etkin: $($adapter.Name)" 'OK' } catch {}
                }
                if ($using:opts.GreenEth) {
                    Set-NicProp 'Green Ethernet' 'Disabled'
                    Set-NicProp 'Energy-Efficient Ethernet' 'Disabled'
                    Set-NicProp 'EEE' 'Disabled'
                }
                if ($using:opts.GigaLite)  { Set-NicProp 'Giga Lite' 'Disabled' }
            }
        }

        if ($using:opts.LLMNR) {
            $dnPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'
            if (-not (Test-Path $dnPath)) { New-Item -Path $dnPath -Force | Out-Null }
            Set-ItemProperty -Path $dnPath -Name 'EnableMulticast' -Value 0 -ErrorAction SilentlyContinue
            Write-Log "LLMNR kapatildi" 'OK'
        }
        if ($using:opts.MDNS) {
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
    $opts = @{
        VBS         = (Get-CheckVal 'ChkVBS')
        DMAProtect  = (Get-CheckVal 'ChkDMAProtect')
        Spectre     = (Get-CheckVal 'ChkSpectre')
        CFG         = (Get-CheckVal 'ChkCFG')
        HVCI        = (Get-CheckVal 'ChkHVCI')
        LargePages  = (Get-CheckVal 'ChkLargePages')
        ContMem     = (Get-CheckVal 'ChkContMem')
        SecLvlCache = (Get-CheckVal 'ChkSecondLevelCache')
        MouseBuf    = (Get-CheckVal 'ChkMouseBuffer')
        KbBuf       = (Get-CheckVal 'ChkKbBuffer')
        RawInput    = (Get-CheckVal 'ChkRawInput')
        MouseSmooth = (Get-CheckVal 'ChkMouseSmooth')
        MouseAccel  = (Get-CheckVal 'ChkMouseAccel')
    }
    Invoke-Async -TaskName 'Kernel & Input' -Block {
        Backup-Registry 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'Kernel_DevGuard'

        if ($using:opts.VBS) {
            $dgPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'
            Set-ItemProperty -Path $dgPath -Name 'EnableVirtualizationBasedSecurity' -Value 0 -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $dgPath -Name 'RequirePlatformSecurityFeatures'   -Value 0 -ErrorAction SilentlyContinue
            Write-Log "VBS / Core Isolation devre disi. Yeniden baslatma gerekli." 'WARN'
        }
        if ($using:opts.DMAProtect) {
            Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' -Name 'EnableKernelDmaProtection' -Value 0 -ErrorAction SilentlyContinue
            Write-Log "DMA Protection devre disi" 'WARN'
        }
        if ($using:opts.Spectre) {
            $featurePath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
            Set-ItemProperty -Path $featurePath -Name 'FeatureSettingsOverride'     -Value 3 -Type DWord -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $featurePath -Name 'FeatureSettingsOverrideMask' -Value 3 -Type DWord -ErrorAction SilentlyContinue
            Write-Log "Spectre/Meltdown mitigasyonlari devre disi. Guvenlik riski!" 'WARN'
        }
        if ($using:opts.HVCI) {
            $ciPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity'
            if (-not (Test-Path $ciPath)) { New-Item -Path $ciPath -Force | Out-Null }
            Set-ItemProperty -Path $ciPath -Name 'Enabled' -Value 0 -ErrorAction SilentlyContinue
            Write-Log "HVCI devre disi" 'WARN'
        }
        if ($using:opts.ContMem) {
            $dxPath = 'HKLM:\SOFTWARE\Microsoft\DirectX'
            if (-not (Test-Path $dxPath)) { New-Item -Path $dxPath -Force | Out-Null }
            Set-ItemProperty -Path $dxPath -Name 'D3D12_ENABLE_UNSAFE_COMMAND_BUFFER_REUSE' -Value 1 -ErrorAction SilentlyContinue
            # Contiguous memory for legacy DX
            $gpuPrefsPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
            Set-ItemProperty -Path $gpuPrefsPath -Name 'DpiMapIommuContiguous' -Value 1 -ErrorAction SilentlyContinue
            Write-Log "DirectX Contiguous Memory Allocation etkin" 'OK'
        }
        if ($using:opts.SecLvlCache) {
            $memPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
            $cpu = Get-WmiObject Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
            $cacheKB = if ($cpu) { [math]::Max($cpu.L2CacheSize, $cpu.L3CacheSize) } else { 512 }
            Set-ItemProperty -Path $memPath -Name 'SecondLevelDataCache' -Value $cacheKB -ErrorAction SilentlyContinue
            Write-Log "SecondLevelDataCache = ${cacheKB}KB" 'OK'
        }
        # Mouse & Keyboard Buffer (MarkC Fix logic)
        if ($using:opts.MouseBuf) {
            $mousePath = 'HKLM:\SYSTEM\CurrentControlSet\Services\mouclass\Parameters'
            Set-ItemProperty -Path $mousePath -Name 'MouseDataQueueSize' -Value 16 -ErrorAction SilentlyContinue
            Write-Log "Mouse buffer = 16 (MarkC optimized)" 'OK'
        }
        if ($using:opts.KbBuf) {
            $kbPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\kbdclass\Parameters'
            Set-ItemProperty -Path $kbPath -Name 'KeyboardDataQueueSize' -Value 16 -ErrorAction SilentlyContinue
            Write-Log "Keyboard buffer = 16" 'OK'
        }
        if ($using:opts.RawInput) {
            $rawPath = 'HKCU:\Control Panel\Mouse'
            Set-ItemProperty -Path $rawPath -Name 'MouseSensitivity' -Value '10' -ErrorAction SilentlyContinue
            Write-Log "Raw Input ayarlandi" 'OK'
        }
        if ($using:opts.MouseSmooth) {
            $cpMouse = 'HKCU:\Control Panel\Mouse'
            Set-ItemProperty -Path $cpMouse -Name 'SmoothMouseXCurve' -Value ([byte[]](0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xC0,0xCC,0x0C,0x00,0x00,0x00,0x00,0x00,0x80,0x99,0x19,0x00,0x00,0x00,0x00,0x00,0x40,0x66,0x26,0x00,0x00,0x00,0x00,0x00,0x00,0x33,0x33,0x00,0x00,0x00,0x00,0x00)) -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $cpMouse -Name 'SmoothMouseYCurve' -Value ([byte[]](0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x38,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x70,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xA8,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xE0,0x00,0x00,0x00,0x00,0x00)) -ErrorAction SilentlyContinue
            Write-Log "Mouse Smoothing devre disi (MarkC Fix curves)" 'OK'
        }
        if ($using:opts.MouseAccel) {
            $cpMouse = 'HKCU:\Control Panel\Mouse'
            Set-ItemProperty -Path $cpMouse -Name 'MouseSpeed'     -Value '0' -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $cpMouse -Name 'MouseThreshold1' -Value '0' -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $cpMouse -Name 'MouseThreshold2' -Value '0' -ErrorAction SilentlyContinue
            Write-Log "Mouse Acceleration (EPP) kapatildi" 'OK'
        }
    }
})

# ─── BACKEND: GPU & MSI ───────────────────────────────────────────────────────
$BtnDetectGPU.Add_Click({
    $gpus = Get-WmiObject Win32_VideoController -ErrorAction SilentlyContinue
    if ($gpus) {
        $info = ($gpus | ForEach-Object { "► $($_.Name) | Driver: $($_.DriverVersion)" }) -join "`n"
        $TxtGPUInfo.Text = $info
        Write-Log "GPU algilandi:`n$info" 'OK'
    } else {
        $TxtGPUInfo.Text = "GPU bilgisi alinamadi."
        Write-Log "GPU bilgisi alinamadi" 'WARN'
    }
})

$BtnApplyGPU.Add_Click({
    $opts = @{
        MSIGPU    = (Get-CheckVal 'ChkMSIGPU')
        MSINVMe   = (Get-CheckVal 'ChkMSINVMe')
        MSIPRIO   = (Get-CheckVal 'ChkMSIPrio')
        NvPrerender  = (Get-CheckVal 'ChkNvPrerender')
        NvPower      = (Get-CheckVal 'ChkNvPower')
        NvSync       = (Get-CheckVal 'ChkNvSync')
        NvFastSync   = (Get-CheckVal 'ChkNvFastSync')
        AMDAntiLag   = (Get-CheckVal 'ChkAMDAntiLag')
        AMDChill     = (Get-CheckVal 'ChkAMDChill')
    }
    Invoke-Async -TaskName 'GPU & MSI' -Block {
        Backup-Registry 'HKLM:\SYSTEM\CurrentControlSet\Enum' 'GPU_MSI_Enum'

        # MSI Mode for GPU (PCI\VEN_... devices)
        if ($using:opts.MSIGPU -or $using:opts.MSINVMe) {
            $pciPath = 'HKLM:\SYSTEM\CurrentControlSet\Enum'
            Get-ChildItem -Path $pciPath -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
                $devName = $_.PSChildName
                $intPath = "$($_.PSPath)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
                $isGPU   = $devName -match 'PCI'
                $isNVMe  = $devName -match 'NVMe|SCSI'

                if (($using:opts.MSIGPU -and $isGPU) -or ($using:opts.MSINVMe -and $isNVMe)) {
                    if (-not (Test-Path $intPath)) {
                        try { New-Item -Path $intPath -Force -ErrorAction SilentlyContinue | Out-Null } catch {}
                    }
                    Set-ItemProperty -Path $intPath -Name 'MSISupported' -Value 1 -Type DWord -ErrorAction SilentlyContinue
                    if ($using:opts.MSIPRIO) {
                        $affinityPath = "$($_.PSPath)\Device Parameters\Interrupt Management\Affinity Policy"
                        if (-not (Test-Path $affinityPath)) {
                            try { New-Item -Path $affinityPath -Force -ErrorAction SilentlyContinue | Out-Null } catch {}
                        }
                        Set-ItemProperty -Path $affinityPath -Name 'DevicePriority' -Value 3 -Type DWord -ErrorAction SilentlyContinue
                    }
                }
            }
            Write-Log "MSI Mode uygulandi (GPU/NVMe). Yeniden baslatma gerekli." 'OK'
        }

        # NVIDIA Registry tweaks
        $nvPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
        if ($using:opts.NvPrerender -or $using:opts.NvPower -or $using:opts.NvSync -or $using:opts.NvFastSync) {
            if (Test-Path $nvPath) {
                Get-ChildItem $nvPath | Where-Object { $_.PSChildName -match '^\d{4}$' } | ForEach-Object {
                    $subkey = $_.PSPath
                    $driverDesc = (Get-ItemProperty -Path $subkey -Name 'DriverDesc' -ErrorAction SilentlyContinue).DriverDesc
                    if ($driverDesc -match 'NVIDIA') {
                        if ($using:opts.NvPrerender)  { Set-ItemProperty -Path $subkey -Name 'RMDxgkNDDSwapChainAcquireToHwCursorLatency' -Value 0 -ErrorAction SilentlyContinue }
                        if ($using:opts.NvPower)      { Set-ItemProperty -Path $subkey -Name 'DisableDynamicPstate' -Value 1 -ErrorAction SilentlyContinue }
                        if ($using:opts.NvFastSync)   { Set-ItemProperty -Path $subkey -Name 'RMVSyncDelayFrameCount' -Value 0 -ErrorAction SilentlyContinue }
                        Write-Log "NVIDIA latency tweaks uygulandi: $driverDesc" 'OK'
                    }
                }
            }
        }

        # AMD tweaks
        $amdPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
        if ($using:opts.AMDAntiLag -or $using:opts.AMDChill) {
            if (Test-Path $amdPath) {
                Get-ChildItem $amdPath | Where-Object { $_.PSChildName -match '^\d{4}$' } | ForEach-Object {
                    $subkey = $_.PSPath
                    $driverDesc = (Get-ItemProperty -Path $subkey -Name 'DriverDesc' -ErrorAction SilentlyContinue).DriverDesc
                    if ($driverDesc -match 'AMD|Radeon|ATI') {
                        if ($using:opts.AMDAntiLag) { Set-ItemProperty -Path $subkey -Name 'KMD_EnableAntiLag' -Value 1 -ErrorAction SilentlyContinue }
                        if ($using:opts.AMDChill)   { Set-ItemProperty -Path $subkey -Name 'KMD_EnableChill'   -Value 0 -ErrorAction SilentlyContinue }
                        Write-Log "AMD tweaks uygulandi: $driverDesc" 'OK'
                    }
                }
            }
        }
    }
})

# ─── BACKEND: PRIVACY & TELEMETRY ─────────────────────────────────────────────
$BtnApplyPrivacy.Add_Click({
    $opts = @{
        DiagTrack    = (Get-CheckVal 'ChkDiagTrack')
        DMWApp       = (Get-CheckVal 'ChkDMWAppSupport')
        TelemetryReg = (Get-CheckVal 'ChkTelemetryReg')
        AppCompat    = (Get-CheckVal 'ChkAppCompat')
        ErrReport    = (Get-CheckVal 'ChkErrorReport')
        ActHist      = (Get-CheckVal 'ChkActivityHist')
        Cortana      = (Get-CheckVal 'ChkCortana')
        AdID         = (Get-CheckVal 'ChkAdID')
        Tailored     = (Get-CheckVal 'ChkTailored')
        Typing       = (Get-CheckVal 'ChkTyping')
        OneDrive     = (Get-CheckVal 'ChkOneDrive')
        XboxSvc      = (Get-CheckVal 'ChkXboxServices')
        BingSearch   = (Get-CheckVal 'ChkBingSearch')
        SuggestApps  = (Get-CheckVal 'ChkSuggestApps')
        ConsumerExp  = (Get-CheckVal 'ChkConsumerExp')
    }
    Invoke-Async -TaskName 'Privacy & Telemetry' -Block {
        Backup-Registry 'HKLM:\SOFTWARE\Policies\Microsoft\Windows' 'Privacy_Policies'

        if ($using:opts.DiagTrack) {
            Stop-Service 'DiagTrack'  -Force -ErrorAction SilentlyContinue
            Set-Service 'DiagTrack' -StartupType Disabled -ErrorAction SilentlyContinue
            Write-Log "DiagTrack kapatildi" 'OK'
        }
        if ($using:opts.DMWApp) {
            Stop-Service 'dmwappushservice' -Force -ErrorAction SilentlyContinue
            Set-Service 'dmwappushservice' -StartupType Disabled -ErrorAction SilentlyContinue
            Write-Log "dmwappushservice kapatildi" 'OK'
        }
        if ($using:opts.TelemetryReg) {
            $telPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
            if (-not (Test-Path $telPath)) { New-Item -Path $telPath -Force | Out-Null }
            Set-ItemProperty -Path $telPath -Name 'AllowTelemetry' -Value 0 -ErrorAction SilentlyContinue
            Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' -Name 'AllowTelemetry' -Value 0 -ErrorAction SilentlyContinue
            Write-Log "Telemetry Level = 0 (Security)" 'OK'
        }
        if ($using:opts.AppCompat) {
            $schPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat'
            if (-not (Test-Path $schPath)) { New-Item -Path $schPath -Force | Out-Null }
            Set-ItemProperty -Path $schPath -Name 'DisableInventory'     -Value 1 -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $schPath -Name 'DisableProgramTelemetry' -Value 1 -ErrorAction SilentlyContinue
            Write-Log "App Compat telemetri kapatildi" 'OK'
        }
        if ($using:opts.ErrReport) {
            $wePath = 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting'
            Set-ItemProperty -Path $wePath -Name 'Disabled' -Value 1 -ErrorAction SilentlyContinue
            Set-Service 'WerSvc' -StartupType Disabled -ErrorAction SilentlyContinue
            Write-Log "Windows Error Reporting kapatildi" 'OK'
        }
        if ($using:opts.ActHist) {
            $ahPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
            if (-not (Test-Path $ahPath)) { New-Item -Path $ahPath -Force | Out-Null }
            Set-ItemProperty -Path $ahPath -Name 'EnableActivityFeed' -Value 0 -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $ahPath -Name 'PublishUserActivities' -Value 0 -ErrorAction SilentlyContinue
            Write-Log "Activity History kapatildi" 'OK'
        }
        if ($using:opts.Cortana) {
            $corPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'
            if (-not (Test-Path $corPath)) { New-Item -Path $corPath -Force | Out-Null }
            Set-ItemProperty -Path $corPath -Name 'AllowCortana' -Value 0 -ErrorAction SilentlyContinue
            Write-Log "Cortana kapatildi" 'OK'
        }
        if ($using:opts.AdID) {
            $adPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo'
            if (-not (Test-Path $adPath)) { New-Item -Path $adPath -Force | Out-Null }
            Set-ItemProperty -Path $adPath -Name 'Enabled' -Value 0 -ErrorAction SilentlyContinue
            Write-Log "Advertising ID kapatildi" 'OK'
        }
        if ($using:opts.Tailored) {
            $tePath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy'
            if (-not (Test-Path $tePath)) { New-Item -Path $tePath -Force | Out-Null }
            Set-ItemProperty -Path $tePath -Name 'TailoredExperiencesWithDiagnosticDataEnabled' -Value 0 -ErrorAction SilentlyContinue
            Write-Log "Tailored Experiences kapatildi" 'OK'
        }
        if ($using:opts.BingSearch) {
            $bingPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'
            Set-ItemProperty -Path $bingPath -Name 'BingSearchEnabled'    -Value 0 -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $bingPath -Name 'CortanaConsent'        -Value 0 -ErrorAction SilentlyContinue
            Write-Log "Bing Search Start Menu'dan kapatildi" 'OK'
        }
        if ($using:opts.SuggestApps) {
            Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'SystemPaneSuggestionsEnabled' -Value 0 -ErrorAction SilentlyContinue
            Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'SilentInstalledAppsEnabled'    -Value 0 -ErrorAction SilentlyContinue
            Write-Log "Suggested Apps kapatildi" 'OK'
        }
        if ($using:opts.ConsumerExp) {
            $cePath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
            if (-not (Test-Path $cePath)) { New-Item -Path $cePath -Force | Out-Null }
            Set-ItemProperty -Path $cePath -Name 'DisableWindowsConsumerFeatures' -Value 1 -ErrorAction SilentlyContinue
            Write-Log "Consumer Experience kapatildi" 'OK'
        }
        if ($using:opts.XboxSvc) {
            @('XblAuthManager','XblGameSave','XboxNetApiSvc','XboxGipSvc') | ForEach-Object {
                Set-Service -Name $_ -StartupType Disabled -ErrorAction SilentlyContinue
                Stop-Service -Name $_ -Force -ErrorAction SilentlyContinue
                Write-Log "Xbox servisi kapatildi: $_" 'OK'
            }
        }
        if ($using:opts.OneDrive) {
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
    $opts = @{
        Animations   = (Get-CheckVal 'ChkAnimations')
        JPEGQuality  = (Get-CheckVal 'ChkJPEGQuality')
        MenuDelay    = (Get-CheckVal 'ChkMenuDelay')
        TaskbarAnims = (Get-CheckVal 'ChkTaskbarAnims')
        BSODDetail   = (Get-CheckVal 'ChkBSODDetail')
        LaunchTo     = (Get-CheckVal 'ChkLaunchTo')
        NumLock      = (Get-CheckVal 'ChkNumlock')
        HideExt      = (Get-CheckVal 'ChkHideExt')
        LongPaths    = (Get-CheckVal 'ChkLongPaths')
        ContextMenu  = (Get-CheckVal 'ChkContextMenu')
        DarkMode     = (Get-CheckVal 'ChkDarkMode')
    }
    Invoke-Async -TaskName 'Windows Tweaks' -Block {
        Backup-Registry 'HKCU:\Control Panel\Desktop' 'WinTweaks_Desktop'

        if ($using:opts.Animations) {
            $visPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
            Set-ItemProperty -Path $visPath -Name 'VisualFXSetting' -Value 2 -ErrorAction SilentlyContinue
            $deskPath = 'HKCU:\Control Panel\Desktop\WindowMetrics'
            Set-ItemProperty -Path $deskPath -Name 'MinAnimate' -Value '0' -ErrorAction SilentlyContinue
            SystemParametersInfo 0x1002 0 $null 3 2>$null  # SPI_SETANIMATION off
            Write-Log "Animasyonlar kapatildi" 'OK'
        }
        if ($using:opts.JPEGQuality) {
            $jpgPath = 'HKCU:\Control Panel\Desktop'
            Set-ItemProperty -Path $jpgPath -Name 'JPEGImportQuality' -Value 100 -ErrorAction SilentlyContinue
            Write-Log "JPEG Kalite = 100 (tam)" 'OK'
        }
        if ($using:opts.MenuDelay) {
            Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'MenuShowDelay' -Value '0' -ErrorAction SilentlyContinue
            Write-Log "MenuShowDelay = 0ms" 'OK'
        }
        if ($using:opts.TaskbarAnims) {
            Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'TaskbarAnimations' -Value 0 -ErrorAction SilentlyContinue
            Write-Log "Taskbar animasyonlari kapatildi" 'OK'
        }
        if ($using:opts.BSODDetail) {
            $crashPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl'
            Set-ItemProperty -Path $crashPath -Name 'AutoReboot' -Value 0 -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $crashPath -Name 'DisplayParameters' -Value 1 -ErrorAction SilentlyContinue
            Write-Log "BSOD AutoReboot kapatildi, detayli hata kodu aktif" 'OK'
        }
        if ($using:opts.LaunchTo) {
            Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'LaunchTo' -Value 1 -ErrorAction SilentlyContinue
            Write-Log "Explorer This PC'de acilacak sekilde ayarlandi" 'OK'
        }
        if ($using:opts.NumLock) {
            Set-ItemProperty -Path 'HKCU:\Control Panel\Keyboard' -Name 'InitialKeyboardIndicators' -Value '2' -ErrorAction SilentlyContinue
            Write-Log "NumLock baslangicta acik" 'OK'
        }
        if ($using:opts.HideExt) {
            Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'HideFileExt' -Value 0 -ErrorAction SilentlyContinue
            Write-Log "Dosya uzantilari gorunur" 'OK'
        }
        if ($using:opts.LongPaths) {
            Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -Value 1 -ErrorAction SilentlyContinue
            Write-Log "Long Path Support etkin" 'OK'
        }
        if ($using:opts.ContextMenu) {
            $cmdPath = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'
            if (-not (Test-Path $cmdPath)) { New-Item -Path $cmdPath -Force | Out-Null }
            Set-ItemProperty -Path $cmdPath -Name '(default)' -Value '' -ErrorAction SilentlyContinue
            Write-Log "Eski sag tik menusu aktif (Win11). Explorer yeniden baslatiliyor..." 'OK'
            Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 800
            Start-Process explorer
        }
        if ($using:opts.DarkMode) {
            Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'AppsUseLightTheme'   -Value 0 -ErrorAction SilentlyContinue
            Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'SystemUsesLightTheme' -Value 0 -ErrorAction SilentlyContinue
            Write-Log "Dark Mode etkinlestirildi" 'OK'
        }
        # Restart Explorer to apply visual changes
        Write-Log "Explorer yeniden baslatiliyor..." 'RUN'
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
        Start-Process explorer
        Write-Log "Explorer yeniden baslatildi" 'OK'
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
    Invoke-Async -TaskName 'Custom Script' -Block {
        try {
            $sb = [scriptblock]::Create($using:code)
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
    ChkHPET=$false; ChkCpuPriority=$false; ChkSysMain=$false; ChkWSearch=$false
    ChkGameMode=$true; ChkHwAccel=$false
    # Network - safe
    ChkAutoTuning=$false; ChkECN=$false; ChkRSC=$false; ChkCongestion=$false
    ChkNetThrottle=$false; ChkNagle=$false; ChkRSS=$true
    ChkFlowCtrl=$false; ChkIntMod=$false; ChkGreenEth=$false; ChkGigaLite=$false
    # Kernel - nothing risky
    ChkVBS=$false; ChkDMAProtect=$false; ChkSpectre=$false; ChkCFG=$false; ChkHVCI=$false
    ChkMouseAccel=$false; ChkMouseSmooth=$false; ChkMouseBuffer=$false; ChkKbBuffer=$false
    # Privacy - safe
    ChkDiagTrack=$true; ChkTelemetryReg=$true; ChkAdID=$true; ChkBingSearch=$true
    ChkOneDrive=$false; ChkXboxServices=$false
    # Tweaks - safe
    ChkAnimations=$false; ChkMenuDelay=$true; ChkBSODDetail=$true; ChkHideExt=$true; ChkLongPaths=$true
}

$PresetStandard = @{
    ChkTempWin=$true; ChkTempSys=$true; ChkPrefetch=$true; ChkRecycleBin=$true
    ChkThumb=$true; ChkChromeCache=$true; ChkEdgeCache=$true; ChkDNSCache=$true
    ChkCrashDumps=$true; ChkDeliveryOpt=$true
    ChkHPET=$true; ChkCpuPriority=$true; ChkGameMode=$true; ChkHwAccel=$true
    ChkSysMain=$false; ChkWSearch=$false
    ChkAutoTuning=$true; ChkECN=$true; ChkRSC=$true; ChkCongestion=$true
    ChkNetThrottle=$true; ChkNagle=$true; ChkTCPNoDelay=$true; ChkTCPACKFreq=$true
    ChkRSS=$true; ChkFlowCtrl=$true; ChkIntMod=$true; ChkGreenEth=$true; ChkGigaLite=$true
    ChkVBS=$false; ChkSpectre=$false
    ChkContMem=$true; ChkSecondLevelCache=$true
    ChkMouseBuffer=$true; ChkKbBuffer=$true; ChkMouseSmooth=$true; ChkMouseAccel=$true
    ChkMSIGPU=$true; ChkMSINVMe=$true; ChkMSIPrio=$true
    ChkNvPrerender=$true; ChkNvPower=$true; ChkNvSync=$true; ChkNvFastSync=$true
    ChkDiagTrack=$true; ChkTelemetryReg=$true; ChkAdID=$true; ChkBingSearch=$true
    ChkCortana=$true; ChkSuggestApps=$true; ChkConsumerExp=$true
    ChkAnimations=$true; ChkMenuDelay=$true; ChkBSODDetail=$true
    ChkHideExt=$true; ChkLongPaths=$true; ChkNumlock=$true
}

$PresetAggressive = @{
    ChkTempWin=$true; ChkTempSys=$true; ChkPrefetch=$true; ChkRecycleBin=$true
    ChkThumb=$true; ChkFontCache=$true; ChkChromeCache=$true; ChkEdgeCache=$true
    ChkDNSCache=$true; ChkCrashDumps=$true; ChkWinUpdCache=$false; ChkDeliveryOpt=$true
    ChkWinSxS=$false
    ChkHPET=$true; ChkCpuPriority=$true; ChkGameMode=$true; ChkHwAccel=$true
    ChkSysMain=$true; ChkWSearch=$true
    ChkAutoTuning=$true; ChkECN=$true; ChkRSC=$true; ChkCongestion=$true
    ChkNetThrottle=$true; ChkNagle=$true; ChkTCPNoDelay=$true; ChkTCPACKFreq=$true
    ChkRSS=$true; ChkFlowCtrl=$true; ChkIntMod=$true; ChkGreenEth=$true; ChkGigaLite=$true
    ChkLLMNR=$true; ChkMDNS=$true
    ChkVBS=$false; ChkSpectre=$false; ChkDMAProtect=$false
    ChkContMem=$true; ChkSecondLevelCache=$true
    ChkMouseBuffer=$true; ChkKbBuffer=$true; ChkMouseSmooth=$true; ChkMouseAccel=$true; ChkRawInput=$true
    ChkMSIGPU=$true; ChkMSINVMe=$true; ChkMSIPrio=$true
    ChkNvPrerender=$true; ChkNvPower=$true; ChkNvSync=$true; ChkNvFastSync=$true
    ChkAMDAntiLag=$true; ChkAMDChill=$true; ChkAMDPower=$true
    ChkDiagTrack=$true; ChkDMWAppSupport=$true; ChkTelemetryReg=$true; ChkAppCompat=$true
    ChkErrorReport=$true; ChkActivityHist=$true; ChkAdID=$true; ChkCortana=$true
    ChkTailored=$true; ChkTyping=$true; ChkBingSearch=$true; ChkSuggestApps=$true; ChkConsumerExp=$true
    ChkXboxServices=$true; ChkOneDrive=$false
    ChkAnimations=$true; ChkTransparency=$true; ChkMenuDelay=$true; ChkTaskbarAnims=$true
    ChkBSODDetail=$true; ChkHideExt=$true; ChkLongPaths=$true; ChkNumlock=$true
    ChkLaunchTo=$true
}

$BtnPresetMinimal.Add_Click({
    Apply-PresetCheckboxes $PresetMinimal
    Write-Log "Preset uygulandi: Minimal (Safe)" 'OK'
    Set-Status "Preset: Minimal"
})
$BtnPresetStandard.Add_Click({
    Apply-PresetCheckboxes $PresetStandard
    Write-Log "Preset uygulandi: Standard (Balanced)" 'OK'
    Set-Status "Preset: Standard"
})
$BtnPresetAggressive.Add_Click({
    Apply-PresetCheckboxes $PresetAggressive
    Write-Log "Preset uygulandi: Aggressive (Gaming)" 'OK'
    Set-Status "Preset: Aggressive"
})

# Get Installed (Scan system for existing tweaks)
$BtnPresetScan.Add_Click({
    Invoke-Async -TaskName 'Get Installed (System Scan)' -Block {
        Write-Log "Sistem taraniyor..." 'RUN'

        # Win32PrioritySeparation
        $prio = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' -ErrorAction SilentlyContinue).Win32PrioritySeparation
        Write-Log "Win32PrioritySeparation = $prio (0x$([Convert]::ToString($prio,16)))" 'INFO'

        # HPET
        $hpet = (bcdedit /enum {current} 2>&1) | Where-Object { $_ -match 'useplatformclock|disabledynamictick' }
        Write-Log "HPET/HighRes Status: $($hpet -join ' | ')" 'INFO'

        # Power plan
        $active = powercfg /getactivescheme 2>&1
        Write-Log "Aktif Guc Plani: $active" 'INFO'

        # VBS
        $vbs = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' -ErrorAction SilentlyContinue).EnableVirtualizationBasedSecurity
        Write-Log "VBS: $vbs" 'INFO'

        # Telemetry
        $tel = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -ErrorAction SilentlyContinue).AllowTelemetry
        Write-Log "Telemetry Level: $tel" 'INFO'

        # TCP AutoTuning
        $tune = netsh int tcp show global 2>&1 | Where-Object { $_ -match 'Receive Window' }
        Write-Log "TCP Autotuning: $($tune -join ' ')" 'INFO'

        # Services
        @('DiagTrack','SysMain','WSearch','dmwappushservice') | ForEach-Object {
            $svc = Get-Service $_ -ErrorAction SilentlyContinue
            if ($svc) { Write-Log "Servis [$_]: $($svc.StartType) / $($svc.Status)" 'INFO' }
        }

        # NIC Adapters
        Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' } | ForEach-Object {
            Write-Log "Adaptor: $($_.Name) | $($_.LinkSpeed)" 'INFO'
        }

        Write-Log "Sistem taramasi tamamlandi." 'OK'
    }
})

# Apply All
$BtnApplyAll.Add_Click({
    Invoke-Async -TaskName 'Apply All' -Block {
        Write-Log "=== TUM OPTIMIZASYONLAR UYGULANACAK ===" 'RUN'
        Write-Log "Once yedekler aliniyor..." 'INFO'
        Backup-Registry 'HKLM:\SYSTEM\CurrentControlSet\Control' 'ApplyAll_Control'
        Backup-Registry 'HKCU:\Software\Microsoft\Windows\CurrentVersion' 'ApplyAll_HKCU'
        Write-Log "Her sekmedeki secili ayarlar icin lutfen ilgili 'Uygula' butonuna tiklayin." 'WARN'
        Write-Log "'Apply All' sadece aktif checkbox degerlerine gore calisir." 'INFO'
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
Write-Log "Yedek klasoru: $global:BackupPath" 'INFO'
Write-Log "Log dosyasi: $global:LogFile" 'INFO'
Write-Log "─────────────────────────────────────────" 'INFO'

# Select first nav item
$NavQuickClean.IsSelected = $true

# ─── SHOW WINDOW ──────────────────────────────────────────────────────────────
$Window.ShowDialog() | Out-Null
$HWTimer.Stop()
