# Livn Tools - UI/Dialogs.ps1
# Onizleme / sonuc / onay pencereleri. Hepsi UI is parcaciginda, modal calisir.

$script:LtReportXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="860" Height="640" MinWidth="620" MinHeight="420" WindowStartupLocation="CenterOwner"
        Background="#151820" FontFamily="Segoe UI" FontSize="13" ShowInTaskbar="False" ResizeMode="CanResizeWithGrip">
    <Window.Resources>
        <BooleanToVisibilityConverter x:Key="B2V"/>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#232936"/>
            <Setter Property="Foreground" Value="#F0F2F7"/>
            <Setter Property="BorderBrush" Value="#414B60"/>
            <Setter Property="Padding" Value="16,7"/>
            <Setter Property="Margin" Value="8,0,0,0"/>
            <Setter Property="MinWidth" Value="110"/>
        </Style>
        <DataTemplate x:Key="RowTemplate">
            <Border x:Name="bd" Background="#1B1F29" BorderBrush="#303747" BorderThickness="1" CornerRadius="8" Padding="12,8" Margin="0,0,0,6">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <StackPanel>
                        <TextBlock Text="{Binding Title}" FontWeight="SemiBold" Foreground="#F0F2F7" TextWrapping="Wrap"/>
                        <TextBlock Text="{Binding Message}" Foreground="#B5BECE" FontSize="12" TextWrapping="Wrap" Margin="0,3,0,0"/>
                        <TextBlock Text="{Binding Changes}" Foreground="#C9C9DD" FontSize="12" FontFamily="Cascadia Mono, Consolas" TextWrapping="Wrap" Margin="0,4,0,0"
                                   Visibility="{Binding HasChanges, Converter={StaticResource B2V}}"/>
                    </StackPanel>
                    <Border x:Name="badge" Grid.Column="1" CornerRadius="10" Padding="8,2" Margin="10,0,0,0" VerticalAlignment="Top" Background="#252C39">
                        <TextBlock x:Name="badgeTxt" Text="{Binding KindText}" FontSize="11" Foreground="#B5BECE"/>
                    </Border>
                </Grid>
            </Border>
            <DataTemplate.Triggers>
                <DataTrigger Binding="{Binding Kind}" Value="WillChange"><Setter TargetName="badge" Property="Background" Value="#3A2F66"/><Setter TargetName="badgeTxt" Property="Foreground" Value="#DCD0FF"/></DataTrigger>
                <DataTrigger Binding="{Binding Kind}" Value="Success"><Setter TargetName="badge" Property="Background" Value="#16301C"/><Setter TargetName="badgeTxt" Property="Foreground" Value="#7FD686"/></DataTrigger>
                <DataTrigger Binding="{Binding Kind}" Value="Failed"><Setter TargetName="badge" Property="Background" Value="#3A1C22"/><Setter TargetName="badgeTxt" Property="Foreground" Value="#FFB4AC"/><Setter TargetName="bd" Property="BorderBrush" Value="#8A3A3A"/></DataTrigger>
                <DataTrigger Binding="{Binding Kind}" Value="Error"><Setter TargetName="badge" Property="Background" Value="#3A1C22"/><Setter TargetName="badgeTxt" Property="Foreground" Value="#FFB4AC"/></DataTrigger>
                <DataTrigger Binding="{Binding Kind}" Value="Partial"><Setter TargetName="badge" Property="Background" Value="#33260F"/><Setter TargetName="badgeTxt" Property="Foreground" Value="#FFC266"/></DataTrigger>
                <DataTrigger Binding="{Binding Kind}" Value="NotSupported"><Setter TargetName="badge" Property="Background" Value="#33260F"/><Setter TargetName="badgeTxt" Property="Foreground" Value="#FFC266"/></DataTrigger>
                <DataTrigger Binding="{Binding Risk}" Value="Security"><Setter TargetName="bd" Property="BorderBrush" Value="#C24A4A"/></DataTrigger>
            </DataTemplate.Triggers>
        </DataTemplate>
    </Window.Resources>
    <Grid Margin="18">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <StackPanel Grid.Row="0" Margin="0,0,0,12">
            <TextBlock x:Name="TxtHead" FontSize="18" FontWeight="SemiBold" Foreground="#F0F2F7" TextWrapping="Wrap"/>
            <TextBlock x:Name="TxtIntro" Foreground="#B5BECE" TextWrapping="Wrap" Margin="0,6,0,0"/>
        </StackPanel>
        <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
            <ItemsControl x:Name="Rows" ItemTemplate="{StaticResource RowTemplate}"/>
        </ScrollViewer>
        <StackPanel Grid.Row="2" Margin="0,10,0,0">
            <CheckBox x:Name="ChkRestorePoint" Foreground="#F0F2F7" Margin="0,0,0,6" Content="Uygulamadan önce Sistem Geri Yükleme noktası oluştur (oluşturulduğu doğrulanır)"/>
            <CheckBox x:Name="ChkConsent" Foreground="#FFB4AC" Content="Güvenlik özelliklerini kapatacağını ve sistemin korumasının azalacağını anlıyorum."/>
        </StackPanel>
        <DockPanel Grid.Row="3" Margin="0,12,0,0" LastChildFill="False">
            <TextBlock x:Name="TxtFoot" DockPanel.Dock="Left" Foreground="#939FB2" FontSize="12" VerticalAlignment="Center" TextWrapping="Wrap" MaxWidth="520"/>
            <Button x:Name="BtnCancel" DockPanel.Dock="Right" Content="Vazgeç" IsCancel="True"/>
            <Button x:Name="BtnOk" DockPanel.Dock="Right" Content="Uygula" IsDefault="True" Background="#6950B5" BorderBrush="#9F89D5" FontWeight="SemiBold"/>
        </DockPanel>
    </Grid>
</Window>
'@

function New-LtReportRow {
    param([string]$Title, [string]$Kind, [string]$KindText, [string]$Message, [string]$Changes = '', [string]$Risk = '')
    $r = New-Object LivnTools.UI.ReportRow
    $r.Title = $Title; $r.Kind = $Kind; $r.KindText = $KindText; $r.Message = $Message; $r.Changes = $Changes; $r.Risk = $Risk
    return $r
}

function Show-LtReportDialog {
    <#
      -Mode Confirm : Uygula/Vazgec. Donus @{ Confirmed; RestorePoint }
      -Mode Info    : yalnizca Kapat.
    #>
    param(
        $Owner, [string]$Title, [string]$Head, [string]$Intro, [object[]]$Rows,
        [ValidateSet('Confirm', 'Info')][string]$Mode = 'Info',
        [string]$OkText = 'Uygula', [switch]$ShowRestorePoint, [bool]$RestorePointDefault = $true,
        [switch]$RequireConsent, [string]$Foot = '', [bool]$OkEnabled = $true
    )
    $w = [Windows.Markup.XamlReader]::Parse($script:LtReportXaml)
    $w.Title = $Title
    if ($Owner) { $w.Owner = $Owner }
    $w.FindName('TxtHead').Text = $Head
    $w.FindName('TxtIntro').Text = $Intro
    $w.FindName('TxtFoot').Text = $Foot
    $list = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
    foreach ($r in @($Rows)) { $list.Add($r) }
    $w.FindName('Rows').ItemsSource = $list
    $chkRp = $w.FindName('ChkRestorePoint'); $chkConsent = $w.FindName('ChkConsent')
    $btnOk = $w.FindName('BtnOk'); $btnCancel = $w.FindName('BtnCancel')
    $chkRp.Visibility = if ($ShowRestorePoint -and $Mode -eq 'Confirm') { 'Visible' } else { 'Collapsed' }
    $chkRp.IsChecked = $RestorePointDefault
    $chkConsent.Visibility = if ($RequireConsent -and $Mode -eq 'Confirm') { 'Visible' } else { 'Collapsed' }
    $result = @{ Confirmed = $false; RestorePoint = $false }
    if ($Mode -eq 'Info') {
        $btnOk.Visibility = 'Collapsed'
        $btnCancel.Content = 'Kapat'
    } else {
        $btnOk.Content = $OkText
        $update = {
            $ok = $OkEnabled
            if ($RequireConsent -and -not $chkConsent.IsChecked) { $ok = $false }
            $btnOk.IsEnabled = $ok
        }.GetNewClosure()
        $chkConsent.Add_Checked($update); $chkConsent.Add_Unchecked($update)
        & $update
        $btnOk.Add_Click({ $w.DialogResult = $true }.GetNewClosure())
    }
    $dr = $w.ShowDialog()
    if ($dr -eq $true) { $result.Confirmed = $true; $result.RestorePoint = [bool]$chkRp.IsChecked -and $ShowRestorePoint }
    return $result
}

function Show-LtMessage {
    param($Owner, [string]$Text, [string]$Caption = 'Livn Tools', [ValidateSet('OK', 'YesNo', 'YesNoCancel')][string]$Buttons = 'OK', [ValidateSet('Information', 'Warning', 'Error', 'Question')][string]$Icon = 'Information')
    $b = [System.Windows.MessageBoxButton]$Buttons
    $i = [System.Windows.MessageBoxImage]$Icon
    if ($Owner) { return [System.Windows.MessageBox]::Show($Owner, $Text, $Caption, $b, $i).ToString() }
    return [System.Windows.MessageBox]::Show($Text, $Caption, $b, $i).ToString()
}

function ConvertTo-LtPlanRows {
    param([object[]]$Plan)
    $kindText = @{ WillChange = 'Değişecek'; NoChange = 'Değişiklik yok'; NotSupported = 'Desteklenmiyor'; Conflict = 'Çakışma'; NoRecord = 'Kayıt yok'; NoDefault = 'Varsayılan tanımsız'; Error = 'Okunamadı' }
    $riskText = @{ Low = ''; Medium = 'Orta risk. '; High = 'YÜKSEK RİSK. '; Security = 'GÜVENLİĞİ AZALTIR. ' }
    foreach ($p in @($Plan)) {
        $changes = (@($p.Changes) | ForEach-Object { "• $($_.Target): $($_.From)  →  $($_.To)" }) -join "`n"
        $msg = [string]$riskText[[string]$p.Risk]
        if ($p.Message) { $msg += $p.Message + ' ' }
        if ($p.Warning -and $p.Outcome -eq 'WillChange') { $msg += "⚠ $($p.Warning) " }
        $rt = Get-LtRestartText ([string]$p.Restart)
        if ($rt -and $p.Outcome -eq 'WillChange') { $msg += "($rt)" }
        New-LtReportRow -Title $p.Title -Kind $p.Outcome -KindText $kindText[[string]$p.Outcome] -Message $msg.Trim() -Changes $changes -Risk ([string]$p.Risk)
    }
}

function ConvertTo-LtResultRows {
    param([object[]]$Results)
    foreach ($r in @($Results)) {
        $msg = [string]$r.Message
        if ($r.BytesFreed -gt 0 -and $msg -notmatch [regex]::Escape((Format-LtBytes $r.BytesFreed))) { $msg += " ($(Format-LtBytes $r.BytesFreed))" }
        New-LtReportRow -Title $r.Title -Kind $r.Status -KindText $r.StatusText -Message $msg -Changes ((@($r.Details) | ForEach-Object { "• $_" }) -join "`n")
    }
}
