# Livn Tools - Core/Common.ps1
# Sonuc modeli, loglama, harici komut calistirici, yol korumalari ve JSON yardimcilari.
# PowerShell 5.1 uyumlu yazilmistir (?? / ternary / -AsHashtable KULLANILMAZ).

Set-StrictMode -Version 2.0

# ---------------------------------------------------------------------------
# Durum sabitleri
# ---------------------------------------------------------------------------
# Success        : Degisiklik yapildi ve sonradan okunarak dogrulandi.
# AlreadyApplied : Sistem zaten hedef durumdaydi; hicbir sey degistirilmedi.
# Skipped        : Kullanici iptali / secilmedi / geri alinacak kayit yok.
# NotSupported   : Bu sistemde uygulanamaz (neden Message alaninda).
# Failed         : Hata olustu (degisiklikler mumkunse geri alindi).
# Partial        : (Yalniz temizlik) bazi ogeler silinemedi.
$script:LtStatus = @{
    Success        = 'Success'
    AlreadyApplied = 'AlreadyApplied'
    Skipped        = 'Skipped'
    NotSupported   = 'NotSupported'
    Failed         = 'Failed'
    Partial        = 'Partial'
}

$script:LtStatusText = @{
    Success        = 'Başarılı'
    AlreadyApplied = 'Zaten uygulanmış'
    Skipped        = 'Atlandı'
    NotSupported   = 'Desteklenmiyor'
    Failed         = 'Başarısız'
    Partial        = 'Kısmen'
}

function New-LtResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][ValidateSet('Success','AlreadyApplied','Skipped','NotSupported','Failed','Partial')][string]$Status,
        [string]$Title = '',
        [string]$Message = '',
        [bool]$RestartRequired = $false,
        [string]$RestartKind = 'None',
        [object[]]$Details = @(),
        [long]$BytesFreed = 0,
        [bool]$Simulated = $false,
        # Temizlik: BytesFreed gercekten olculdu mu? (DISM/SFC gibi islemler boyut bildirmez)
        [bool]$SizeMeasured = $false
    )
    [pscustomobject]@{
        Id              = $Id
        Title           = $Title
        Status          = $Status
        StatusText      = $script:LtStatusText[$Status]
        Message         = $Message
        RestartRequired = $RestartRequired
        RestartKind     = $RestartKind
        Details         = @($Details)
        BytesFreed      = $BytesFreed
        Simulated       = $Simulated
        SizeMeasured    = $SizeMeasured
        Time            = (Get-Date).ToString('s')
    }
}

function Get-LtStatusText([string]$Status) {
    if ($script:LtStatusText.ContainsKey($Status)) { return $script:LtStatusText[$Status] }
    return $Status
}

# ---------------------------------------------------------------------------
# Loglama
# ---------------------------------------------------------------------------
# Log hem dosyaya hem de (varsa) thread-safe bir kuyruga yazilir. UI kuyrugu
# kendi DispatcherTimer'i ile okur; arka plan is parcacigi hicbir zaman
# Dispatcher.Invoke cagirmaz (kilitlenme riski yok).
$script:LtLogFile  = $null
$script:LtLogQueue = $null
$script:LtLogLock  = New-Object object

function Set-LtLogTarget {
    [CmdletBinding()]
    param([string]$File, [object]$Queue)
    $script:LtLogFile  = $File
    $script:LtLogQueue = $Queue
}

function Write-LtLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][AllowEmptyString()][string]$Message,
        [Parameter(Position = 1)][ValidateSet('INFO','OK','WARN','ERROR','RUN','DEBUG')][string]$Level = 'INFO'
    )
    $line = '{0}  [{1,-5}]  {2}' -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message
    if ($script:LtLogQueue) {
        try { $script:LtLogQueue.Enqueue([pscustomobject]@{ Level = $Level; Line = $line }) } catch { $null = $_ }
    }
    if ($script:LtLogFile) {
        [System.Threading.Monitor]::Enter($script:LtLogLock)
        try {
            [System.IO.File]::AppendAllText($script:LtLogFile, $line + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
        } catch {
            $null = $_   # log dosyasina yazilamamasi islemi durdurmamali
        } finally {
            [System.Threading.Monitor]::Exit($script:LtLogLock)
        }
    }
}

# ---------------------------------------------------------------------------
# Kuru calisma / bellek arka ucu yalitimi
# ---------------------------------------------------------------------------
# Gercek sisteme yan etkisi olan HER ilkel islem (harici komut, dosya silme,
# surec kapatma, kullanici betigi, .reg ice aktarma...) once bu kapidan gecer.
# Arka uc 'Windows' degilse islem CALISTIRILMAZ: istisna firlatilir ve kayda
# gecer. Koruma arayuz dugmesinde degil, motorun en alt katmanindadir; motor
# fonksiyonlari dogrudan cagrilsa da gecerlidir. (Arka uc varsayilani ve
# Set-LtBackend: Backend.ps1)
$script:LtBlockedOps = New-Object System.Collections.ArrayList

function Test-LtLiveSystem {
    <# $true yalnizca gercek Windows arka ucunda. Bellek arka ucu = kuru calisma/test. #>
    return ($script:LtBackend -eq 'Windows')
}

function Assert-LtLiveSystem {
    <#
      Gercek sisteme yan etkisi olan islemden HEMEN ONCE cagrilir.
      Bellek arka ucunda islemi reddeder (istisna) ve Get-LtBlockedOperations'a kaydeder.
    #>
    param([Parameter(Mandatory)][string]$Operation)
    if (Test-LtLiveSystem) { return }
    [void]$script:LtBlockedOps.Add($Operation)
    throw "KURU ÇALIŞMA: '$Operation' gerçek sistemde çalıştırılmadı (bellek arka ucu etkin)."
}

function Get-LtBlockedOperations { return @($script:LtBlockedOps) }
function Clear-LtBlockedOperations { $script:LtBlockedOps.Clear() }

# ---------------------------------------------------------------------------
# Harici komut calistirici
# ---------------------------------------------------------------------------
# Cikis kodu, stdout ve stderr birlikte dondurulur. Metin CIKTISI SADECE log
# icin kullanilir; karar verirken yerellestirilmis metne DAYANILMAZ.
function ConvertTo-LtArgumentString {
    param([string[]]$Arguments)
    $parts = foreach ($a in $Arguments) {
        if ($null -eq $a) { continue }
        if ($a -eq '') { '""'; continue }
        if ($a -notmatch '[\s"]') { $a; continue }
        # Windows CommandLineToArgvW kurallarina gore tirnakla
        $escaped = $a -replace '(\\*)"', '$1$1\"'
        $escaped = $escaped -replace '(\\+)$', '$1$1'
        '"' + $escaped + '"'
    }
    return ($parts -join ' ')
}

function Get-LtConsoleEncoding {
    <#
      Konsol araclarinin yazdigi kod sayfasi: bolge bicimi (CurrentCulture) degil, sistemin
      konsol kod sayfasi (ornek 857, 437 veya 'Beta: UTF-8' ile 65001).
    #>
    try {
        $e = [Console]::OutputEncoding
        if ($e -and $e.CodePage -gt 0) { return $e }
    } catch { $null = $_ }
    try { return [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage) }
    catch { return [System.Text.Encoding]::Default }
}

function Invoke-LtNative {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$Arguments = @(),
        [int]$TimeoutSec = 600,
        [ValidateSet('Oem','Unicode','Utf8')][string]$OutputEncoding = 'Oem',
        $Cancel = $null
    )
    # Kuru calismada hicbir harici surec baslatilmaz (sc, bcdedit, dism, netsh, cmd...)
    Assert-LtLiveSystem -Operation "Harici komut: $FilePath $($Arguments -join ' ')"
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = $FilePath
    $psi.Arguments              = ConvertTo-LtArgumentString $Arguments
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    # Girdi bos verilir: pause / set /p / Read-Host gizli konsolda sonsuza dek beklemez
    $psi.RedirectStandardInput  = $true
    switch ($OutputEncoding) {
        'Unicode' { $enc = [System.Text.Encoding]::Unicode }
        'Utf8'    { $enc = New-Object System.Text.UTF8Encoding($false) }
        default   { $enc = Get-LtConsoleEncoding }
    }
    $psi.StandardOutputEncoding = $enc
    $psi.StandardErrorEncoding  = $enc

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    try {
        [void]$proc.Start()
    } catch {
        return [pscustomobject]@{ ExitCode = -1; StdOut = ''; StdErr = $_.Exception.Message; TimedOut = $false; Cancelled = $false; Command = "$FilePath $($psi.Arguments)" }
    }
    try { $proc.StandardInput.Close() } catch { $null = $_ }
    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $errTask = $proc.StandardError.ReadToEndAsync()
    # Kisa dilimlerle bekle: iptal istegi surec agacini sonlandirir
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSec)
    $cancelled = $false
    while (-not $proc.WaitForExit(250)) {
        if ($null -ne $Cancel -and $Cancel.Requested) { $cancelled = $true; break }
        if ([DateTime]::UtcNow -ge $deadline) { break }
    }
    $timedOut = (-not $proc.HasExited) -and -not $cancelled
    if ($timedOut -or $cancelled) {
        # Surec agacini sonlandir (alt surecler boruyu acik tutabilir)
        $killedTree = $false
        if ($env:SystemRoot -and (Test-Path -LiteralPath "$env:SystemRoot\System32\taskkill.exe")) {
            try {
                $tk = Start-Process -FilePath "$env:SystemRoot\System32\taskkill.exe" -ArgumentList @('/PID', $proc.Id, '/T', '/F') -WindowStyle Hidden -PassThru -Wait
                $killedTree = ($tk.ExitCode -eq 0)
            } catch { $null = $_ }
        }
        if (-not $killedTree) { try { $proc.Kill() } catch { $null = $_ } }
        [void]$proc.WaitForExit(5000)
    } else {
        $proc.WaitForExit()   # async okuyucularin bitmesini bekle
    }
    $stdout = ''; $stderr = ''
    # Okuyucular icin sinirli bekleme: kopmus alt surec boruyu tutsa bile kilitlenme olmaz
    try { if ($outTask.Wait(5000)) { $stdout = $outTask.Result } } catch { $null = $_ }
    try { if ($errTask.Wait(5000)) { $stderr = $errTask.Result } } catch { $null = $_ }
    $code = -1
    if (-not $timedOut -and -not $cancelled) { $code = $proc.ExitCode }
    $proc.Dispose()
    [pscustomobject]@{
        ExitCode = $code
        StdOut   = ($stdout -replace "`0", '')
        StdErr   = ($stderr -replace "`0", '')
        TimedOut = $timedOut
        Cancelled = $cancelled
        Command  = "$FilePath $($psi.Arguments)"
    }
}

function Read-LtTextFileAuto {
    <#
      Kullanicinin sectigi metin dosyasini kodlamasini tahmin ederek okur: BOM (UTF-8/16),
      gecerli UTF-8, aksi halde .bat/.cmd icin OEM (ornek 857), digerleri icin ANSI (ornek 1254).
      Donus: @{ Text; Encoding }
    #>
    param([Parameter(Mandatory)][string]$Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { return @{ Text = [Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3); Encoding = 'UTF-8 (BOM)' } }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { return @{ Text = [Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2); Encoding = 'UTF-16 LE' } }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) { return @{ Text = [Text.Encoding]::BigEndianUnicode.GetString($bytes, 2, $bytes.Length - 2); Encoding = 'UTF-16 BE' } }
    try {
        $strict = New-Object Text.UTF8Encoding($false, $true)
        return @{ Text = $strict.GetString($bytes); Encoding = 'UTF-8' }
    } catch { $null = $_ }
    $culture = [Globalization.CultureInfo]::CurrentCulture.TextInfo
    $cp = if ($Path -match '\.(bat|cmd)$') { $culture.OEMCodePage } else { $culture.ANSICodePage }
    try { $enc = [Text.Encoding]::GetEncoding($cp) } catch { $enc = [Text.Encoding]::GetEncoding(1254) }
    return @{ Text = $enc.GetString($bytes); Encoding = "Kod sayfası $($enc.CodePage)" }
}

# Komutu calistirir; cikis kodu izin verilenler disindaysa aciklayici bir hata firlatir.
function Invoke-LtNativeChecked {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$Arguments = @(),
        [int[]]$SuccessCodes = @(0),
        [int]$TimeoutSec = 600
    )
    $r = Invoke-LtNative -FilePath $FilePath -Arguments $Arguments -TimeoutSec $TimeoutSec
    if ($r.TimedOut) { throw "Zaman aşımı ($TimeoutSec sn): $($r.Command)" }
    if ($SuccessCodes -notcontains $r.ExitCode) {
        $txt = (($r.StdErr + ' ' + $r.StdOut) -replace '\s+', ' ').Trim()
        if ($txt.Length -gt 300) { $txt = $txt.Substring(0, 300) + '...' }
        throw "Komut başarısız (çıkış kodu $($r.ExitCode)): $($r.Command) :: $txt"
    }
    return $r
}

# ---------------------------------------------------------------------------
# Yol korumalari (temizlik icin)
# ---------------------------------------------------------------------------
$script:LtCleanupTestRoot = $null

function Set-LtCleanupTestRoot {
    <#
      YALNIZCA TESTLER ICIN: silme islemlerini bu kok klasorle sinirlar. $null = normal mod.
      Kok, sistemin gecici klasorunun ALTINDA, var olan ve 'lt-' ile baslayan ayri bir
      klasor olmalidir (yanlislikla %TEMP% kokunu veya kullanici klasorunu acmayi engeller).
      Bellek arka ucunda gercek dosya silme YALNIZCA bu kok ayarlanmissa ve hedef bu
      kokun icindeyse mumkundur.
    #>
    param([AllowNull()][string]$Path)
    if (-not $Path) { $script:LtCleanupTestRoot = $null; return }
    $sep = [System.IO.Path]::DirectorySeparatorChar
    $full = [System.IO.Path]::GetFullPath($Path).TrimEnd($sep)
    $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd($sep)
    if (-not $full.StartsWith($tempRoot + $sep, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Test kökü sistemin geçici klasörü altında olmalı: '$full'"
    }
    if (-not (Split-Path -Leaf $full).StartsWith('lt-')) { throw "Test kökü adı 'lt-' ile başlamalı: '$full'" }
    if (-not [System.IO.Directory]::Exists($full)) { throw "Test kökü mevcut değil: '$full'" }
    Assert-LtNoReparsePath -Path $full
    $script:LtCleanupTestRoot = $full
}

function Test-LtCleanupSandbox {
    <# Acikca ayrilmis gecici test koku etkin mi? #>
    return [bool]$script:LtCleanupTestRoot
}

function Assert-LtDeletePermitted {
    <#
      Dosya/klasor silmeden HEMEN ONCE cagrilir.
      - Bellek arka ucu + test koku YOK  -> reddedilir (kuru calisma).
      - Test koku VAR                    -> yalnizca kokun icindeki yollar.
      - Gercek arka uc                   -> Test-LtSafeDeletePath kurallari.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Path)
    if (-not (Test-LtLiveSystem) -and -not (Test-LtCleanupSandbox)) {
        Assert-LtLiveSystem -Operation "Dosya silme: $Path"
    }
    if (-not (Test-LtSafeDeletePath $Path)) { throw "Güvenlik: silme hedefi reddedildi: '$Path'" }
    Assert-LtNoReparsePath -Path $Path
}
function Assert-LtNoReparsePath {
    param([Parameter(Mandatory)][string]$Path)
    $current = [System.IO.Path]::GetFullPath($Path)
    while ($current) {
        if ([System.IO.File]::Exists($current) -or [System.IO.Directory]::Exists($current)) {
            $attrs = [System.IO.File]::GetAttributes($current)
            if (($attrs -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Güvenlik: bağlantı üzerinden silme reddedildi: '$current'"
            }
        }
        $parent = [System.IO.Path]::GetDirectoryName($current)
        if ($parent -eq $current) { break }
        $current = $parent
    }
}

function Test-LtSafeDeletePath {
    <#
      Silme hedefinin guvenli olup olmadigini kontrol eder:
      - Mutlak, surucu harfiyle baslayan yol olmali
      - Surucu koku, Windows, Program Files, Users kokleri OLMAMALI
      - En az 3 seviye derinlikte olmali (C:\A\B)
      - Bos ortam degiskeninden dogan yollar ('\Temp', 'C:\\Temp') reddedilir
    #>
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    # Test ortami: yalnizca acikca izin verilen gecici kok altinda (bkz. Set-LtCleanupTestRoot)
    if ($script:LtCleanupTestRoot) {
        $full = [System.IO.Path]::GetFullPath($Path)
        $prefix = $script:LtCleanupTestRoot + [System.IO.Path]::DirectorySeparatorChar
        $comparison = if ([System.IO.Path]::DirectorySeparatorChar -eq '/') { [StringComparison]::Ordinal } else { [StringComparison]::OrdinalIgnoreCase }
        return $full.StartsWith($prefix, $comparison)
    }
    if ($Path -notmatch '^[A-Za-z]:\\[^\\]') { return $false }
    # '..' yalniz yol PARCASI olarak reddedilir ('x..y' gibi gecerli adlar degil)
    if ($Path -match '\\\\' -or $Path -match '(^|\\)\.\.(\\|$)') { return $false }
    $norm = $Path.TrimEnd('\')
    $segments = $norm.Split('\') | Where-Object { $_ -ne '' }
    if (@($segments).Count -lt 3) {
        # C:\Windows\Temp gibi 3 parcali yollar izinli; 2 parcali (C:\Windows) degil
        return $false
    }
    $forbidden = @(
        $env:SystemRoot, "$env:SystemRoot\System32", "$env:SystemRoot\SysWOW64",
        $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData,
        $env:USERPROFILE, $env:APPDATA, $env:LOCALAPPDATA, "$env:SystemDrive\Users"
    ) | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') }
    foreach ($f in $forbidden) {
        if ($norm -ieq $f) { return $false }
    }
    return $true
}

# ---------------------------------------------------------------------------
# JSON / dosya yardimcilari (PS 5.1'de -AsHashtable yok)
# ---------------------------------------------------------------------------
function ConvertTo-LtHashtable {
    param([Parameter(ValueFromPipeline)]$InputObject)
    process {
        if ($null -eq $InputObject) { return $null }
        if ($InputObject -is [string] -or $InputObject -is [ValueType]) { return $InputObject }
        if ($InputObject -is [System.Collections.IDictionary]) {
            $h = @{}
            foreach ($k in $InputObject.Keys) { $h[$k] = ConvertTo-LtHashtable $InputObject[$k] }
            return $h
        }
        if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
            $h = @{}
            foreach ($p in $InputObject.PSObject.Properties) { $h[$p.Name] = ConvertTo-LtHashtable $p.Value }
            return $h
        }
        if (($InputObject -is [System.Collections.IEnumerable]) -and -not ($InputObject -is [string])) {
            $list = @(foreach ($i in $InputObject) { ,(ConvertTo-LtHashtable $i) })
            return ,$list
        }
        return $InputObject
    }
}

function Write-LtFileAtomic {
    <#
      Icerigi once gecici dosyaya yazar, sonra hedefle degistirir (yarim dosya kalmaz).
      NOT: PowerShell, .NET string parametresine verilen $null degerini "" olarak gecirir;
      File.Replace bos yedek adini reddeder. Gercek null icin [NullString]::Value kullanilir.
      Replace yapilamazsa: hedef .bak olur, gecici dosya hedefe tasinir; ikinci adim
      basarisiz olursa ozgun dosya geri konur (ledger/journal kaybolmaz).
    #>
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][AllowEmptyString()][string]$Content)
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
    $tmp = "$Path.tmp-$([guid]::NewGuid().ToString('N'))"
    try {
        [System.IO.File]::WriteAllText($tmp, $Content, (New-Object System.Text.UTF8Encoding($false)))
    } catch {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        throw
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        Move-Item -LiteralPath $tmp -Destination $Path -Force
        return
    }
    try {
        Invoke-LtFileReplace -Source $tmp -Destination $Path
        return
    } catch {
        $null = $_   # Replace bazi dosya sistemlerinde desteklenmez; korumali geri donus asagida
    }
    $bak = "$Path.bak"
    Move-Item -LiteralPath $Path -Destination $bak -Force
    try {
        Move-Item -LiteralPath $tmp -Destination $Path -Force
    } catch {
        $moveError = $_
        try { Move-Item -LiteralPath $bak -Destination $Path -Force } catch { $null = $_ }
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        throw $moveError
    }
    Remove-Item -LiteralPath $bak -Force -ErrorAction SilentlyContinue
}

function Invoke-LtFileReplace {
    <# File.Replace, yedek dosyasiz. $null yerine [NullString]::Value (bkz. Write-LtFileAtomic). #>
    param([Parameter(Mandatory)][string]$Source, [Parameter(Mandatory)][string]$Destination)
    [System.IO.File]::Replace($Source, $Destination, [NullString]::Value)
}

function Restore-LtAtomicWriteBackup {
    <#
      Write-LtFileAtomic geri donus yolunda iki tasima arasinda surec kesildiyse hedef
      yoktur ama "<hedef>.bak" vardir. Bu durumda .bak hedefe geri tasinir.
      Donus: $true = kurtarildi.
    #>
    param([Parameter(Mandatory)][string]$Path)
    $bak = "$Path.bak"
    if ((Test-Path -LiteralPath $Path) -or -not (Test-Path -LiteralPath $bak)) { return $false }
    Move-Item -LiteralPath $bak -Destination $Path -Force
    return $true
}

function Format-LtBytes([long]$Bytes) {
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N0} KB' -f ($Bytes / 1KB)) }
    return "$Bytes B"
}
