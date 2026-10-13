# Livn Tools - Startup.ps1
# Baslangic uygulamalari: Run anahtarlari ve Baslangic klasorleri. Kapatma/acma, Gorev
# Yoneticisi'nin kullandigi StartupApproved kaydiyla yapilir (ilk bayt: cift = acik, tek = kapali).
# Girdinin kendisi (Run degeri, kisayol) SILINMEZ; islem motor uzerinden gunluge yazilir ve
# Degisiklik Gecmisi'nden geri alinabilir.

Set-StrictMode -Version 2.0

$script:LtApprovedRoot = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
$script:LtStartupSources = @(
    @{ Scope = 'UserRun';      Location = 'Kayıt (kullanıcı)';                 Path = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';             Approved = "HKCU\$script:LtApprovedRoot\Run" }
    @{ Scope = 'MachineRun';   Location = 'Kayıt (tüm kullanıcılar)';          Path = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run';             Approved = "HKLM\$script:LtApprovedRoot\Run" }
    @{ Scope = 'MachineRun32'; Location = 'Kayıt (32-bit, tüm kullanıcılar)';  Path = 'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Approved = "HKLM\$script:LtApprovedRoot\Run32" }
    @{ Scope = 'UserFolder';   Location = 'Başlangıç klasörü (kullanıcı)';     Folder = 'Startup';       Approved = "HKCU\$script:LtApprovedRoot\StartupFolder" }
    @{ Scope = 'CommonFolder'; Location = 'Başlangıç klasörü (tüm kullanıcılar)'; Folder = 'CommonStartup'; Approved = "HKLM\$script:LtApprovedRoot\StartupFolder" }
)

function Get-LtStartupFolderEntries {
    <# Baslangic klasorundeki ogeler (ad + tam yol). Memory: Mem.StartupFolders[<Folder>]. #>
    param([Parameter(Mandatory)][ValidateSet('Startup', 'CommonStartup')][string]$Folder)
    if ((Get-LtBackend) -eq 'Memory') {
        $m = Get-LtMemoryState
        if ($m.ContainsKey('StartupFolders') -and $m.StartupFolders -and $m.StartupFolders.ContainsKey($Folder)) {
            return @($m.StartupFolders[$Folder] | ForEach-Object { @{ Name = [string]$_; Path = "C:\Sahte\$Folder\$_" } })
        }
        return @()
    }
    $dir = [Environment]::GetFolderPath($Folder)
    if (-not $dir -or -not [IO.Directory]::Exists($dir)) { return @() }
    return @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ine 'desktop.ini' } | ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } })
}

function Test-LtStartupApprovedEnabled {
    <# StartupApproved verisi: yoksa acik; ilk bayt tekse (0x03, 0x07) kapali. #>
    param($Value)
    if (-not $Value.Exists) { return $true }
    try {
        [byte[]]$bytes = if ($Value.Data -is [byte[]]) { $Value.Data } else { [Convert]::FromBase64String([string]$Value.Data) }
        if ($bytes.Length -eq 0) { return $true }
        return (($bytes[0] -band 1) -eq 0)
    } catch { return $true }
}

function Get-LtStartupApprovedData([bool]$Enabled) {
    <# Gorev Yoneticisi bicimi: 12 bayt; 0x02 acik, 0x03 kapali (zaman damgasi sifir). #>
    $b = New-Object byte[] 12
    $b[0] = if ($Enabled) { 2 } else { 3 }
    return [Convert]::ToBase64String($b)
}

function Get-LtStartupItems {
    <# Donus: @{ Id; Name; Command; Location; Scope; Enabled; ApprovedPath; ApprovedName } #>
    $items = New-Object System.Collections.ArrayList
    foreach ($src in $script:LtStartupSources) {
        $entries = @()
        if ($src.ContainsKey('Path')) {
            foreach ($n in @(Get-LtRegValueNames $src.Path)) {
                if ([string]::IsNullOrEmpty($n)) { continue }
                $v = Get-LtRegValue $src.Path $n
                $entries += @{ Name = [string]$n; Command = [string]$v.Data }
            }
        } else {
            foreach ($e in @(Get-LtStartupFolderEntries -Folder $src.Folder)) { $entries += @{ Name = $e.Name; Command = $e.Path } }
        }
        foreach ($e in $entries) {
            $approved = Get-LtRegValue $src.Approved $e.Name
            [void]$items.Add([pscustomobject]@{
                Id = "$($src.Scope)|$($e.Name)"; Name = $e.Name; Command = $e.Command; Location = $src.Location; Scope = $src.Scope
                Enabled = (Test-LtStartupApprovedEnabled $approved); ApprovedPath = $src.Approved; ApprovedName = $e.Name
                StateText = $(if (Test-LtStartupApprovedEnabled $approved) { 'Açık' } else { 'Kapalı' })
            })
        }
    }
    return @($items | Sort-Object @{ Expression = { -not $_.Enabled } }, Name)
}

function New-LtStartupActions {
    <# Secili ogeler icin StartupApproved eylemleri. Varsayilan: deger yok (= acik). #>
    param([Parameter(Mandatory)]$Ctx, [Parameter(Mandatory)][bool]$Enabled)
    $ids = @(Get-LtProp $Ctx 'StartupSelection' @())
    if ($ids.Count -eq 0) { throw 'Önce Başlangıç sayfasından uygulama seçin.' }
    $all = @(Get-LtStartupItems)
    foreach ($id in $ids) {
        $item = @($all | Where-Object { $_.Id -eq $id }) | Select-Object -First 1
        if (-not $item) { throw "Başlangıç öğesi artık yok: $id" }
        New-LtRegAction -Path $item.ApprovedPath -Name $item.ApprovedName -Kind Binary -Value (Get-LtStartupApprovedData $Enabled) -Default 'Absent'
    }
}
