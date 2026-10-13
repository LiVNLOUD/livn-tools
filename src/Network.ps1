# Livn Tools - Network.ps1
# Ag olcumu (salt okunur): gecikme / dalgalanma (jitter) / paket kaybi ve DNS yanit suresi.
# DNS sunucusu secimi (geri alinabilir saglayici). Olcum sonuclari veri klasorunde saklanir;
# once/sonra karsilastirmasi icindir. Hicbir olcum sistem ayari degistirmez.

Set-StrictMode -Version 2.0

$script:LtDnsProviders = [ordered]@{
    Cloudflare = @{ Label = 'Cloudflare'; Servers = @('1.1.1.1', '1.0.0.1', '2606:4700:4700::1111', '2606:4700:4700::1001') }
    Google     = @{ Label = 'Google';     Servers = @('8.8.8.8', '8.8.4.4', '2001:4860:4860::8888', '2001:4860:4860::8844') }
    Quad9      = @{ Label = 'Quad9';      Servers = @('9.9.9.9', '149.112.112.112', '2620:fe::fe', '2620:fe::9') }
}

# ---------------------------------------------------------------------------
# Hedef dogrulama
# ---------------------------------------------------------------------------
function Test-LtNetworkTarget {
    <# IP adresi veya gecerli ana bilgisayar adi; komut/URL kabul edilmez. #>
    param([AllowEmptyString()][string]$Target)
    if ([string]::IsNullOrWhiteSpace($Target)) { return $false }
    $t = $Target.Trim()
    $ip = $null
    if ([System.Net.IPAddress]::TryParse($t, [ref]$ip)) { return $true }
    if ($t.Length -gt 253) { return $false }
    return ($t -match '^(?=.{1,253}$)([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$')
}

function Get-LtDefaultGateway {
    <# IPv4 varsayilan ag gecidi (modem/yonlendirici); bulunamazsa $null. #>
    if ((Get-LtBackend) -eq 'Memory') {
        $m = Get-LtMemoryState
        if ($m.ContainsKey('Network') -and $m.Network -and $m.Network.ContainsKey('Gateway')) { return $m.Network.Gateway }
        return '192.168.1.1'
    }
    try {
        $r = @(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop | Where-Object { $_.NextHop -and $_.NextHop -ne '0.0.0.0' } |
            Sort-Object @{ Expression = { [int]$_.RouteMetric + [int]$_.InterfaceMetric } })
        if ($r.Count -gt 0) { return [string]$r[0].NextHop }
    } catch { $null = $_ }
    return $null
}

# ---------------------------------------------------------------------------
# Gecikme olcumu
# ---------------------------------------------------------------------------
function Get-LtLatencyStats {
    <# Saf islev: ornek listesinden (ms; kayip = $null) istatistik. Jitter: ardisik basarili orneklerin mutlak farki ortalamasi. #>
    param([object[]]$Samples)
    $all = @($Samples)
    $ok = @($all | Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ })
    $sent = $all.Count
    $recv = $ok.Count
    $loss = if ($sent -gt 0) { [math]::Round(100.0 * ($sent - $recv) / $sent, 1) } else { 100 }
    if ($recv -eq 0) { return @{ Sent = $sent; Received = 0; LossPct = $loss; Min = $null; Avg = $null; Max = $null; Jitter = $null } }
    $diffs = @(); for ($i = 1; $i -lt $ok.Count; $i++) { $diffs += [math]::Abs($ok[$i] - $ok[$i - 1]) }
    $jit = if ($diffs.Count -gt 0) { [math]::Round((($diffs | Measure-Object -Average).Average), 1) } else { 0 }
    $stat = $ok | Measure-Object -Minimum -Maximum -Average
    return @{ Sent = $sent; Received = $recv; LossPct = $loss; Min = [math]::Round($stat.Minimum, 1); Avg = [math]::Round($stat.Average, 1); Max = [math]::Round($stat.Maximum, 1); Jitter = $jit }
}

function Measure-LtPing {
    <# ICMP yanki ile olcum (System.Net.NetworkInformation.Ping; harici surec yok). #>
    param([Parameter(Mandatory)][string]$Target, [int]$Count = 20, [int]$TimeoutMs = 1000, [int]$IntervalMs = 200, $Cancel = $null)
    if (-not (Test-LtNetworkTarget $Target)) { throw "Geçersiz hedef: $Target" }
    $samples = New-Object System.Collections.ArrayList
    if ((Get-LtBackend) -eq 'Memory') {
        $m = Get-LtMemoryState
        $spec = $null
        if ($m.ContainsKey('Network') -and $m.Network -and $m.Network.ContainsKey('Latency') -and $m.Network.Latency.ContainsKey($Target)) { $spec = $m.Network.Latency[$Target] }
        if (-not $spec) { $spec = @{ Base = 20; Spread = 2; LossEvery = 0 } }
        for ($i = 0; $i -lt $Count; $i++) {
            if ($spec.LossEvery -gt 0 -and (($i + 1) % $spec.LossEvery) -eq 0) { [void]$samples.Add($null); continue }
            [void]$samples.Add([double]$spec.Base + (($i % 3) - 1) * [double]$spec.Spread)
        }
        return $samples.ToArray()
    }
    $ping = New-Object System.Net.NetworkInformation.Ping
    try {
        for ($i = 0; $i -lt $Count; $i++) {
            if ($null -ne $Cancel -and $Cancel.Requested) { break }
            try {
                $r = $ping.Send($Target.Trim(), $TimeoutMs)
                if ($r.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) { [void]$samples.Add([double]$r.RoundtripTime) } else { [void]$samples.Add($null) }
            } catch { [void]$samples.Add($null) }
            if ($i -lt $Count - 1) { Start-Sleep -Milliseconds $IntervalMs }
        }
    } finally { $ping.Dispose() }
    return $samples.ToArray()
}

function Invoke-LtLatencyTest {
    <# Modem, iki genel DNS hedefi ve istege bagli oyun sunucusu. Donus: @{ Time; Results; Verdict; Wifi } #>
    param([string]$Custom = '', [int]$Count = 20, $Progress = $null, $Cancel = $null, [bool]$Wifi = $false)
    $targets = New-Object System.Collections.ArrayList
    $gw = Get-LtDefaultGateway
    if ($gw) { [void]$targets.Add(@{ Kind = 'Gateway'; Label = 'Modem / yönlendirici'; Address = $gw }) }
    [void]$targets.Add(@{ Kind = 'Internet'; Label = 'Cloudflare (1.1.1.1)'; Address = '1.1.1.1' })
    [void]$targets.Add(@{ Kind = 'Internet'; Label = 'Google (8.8.8.8)'; Address = '8.8.8.8' })
    if ($Custom) {
        if (-not (Test-LtNetworkTarget $Custom)) { throw "Geçersiz hedef: '$Custom'. Yalnız IP adresi veya alan adı yazın." }
        [void]$targets.Add(@{ Kind = 'Custom'; Label = "Hedef ($($Custom.Trim()))"; Address = $Custom.Trim() })
    }
    $results = New-Object System.Collections.ArrayList
    $i = 0
    foreach ($t in $targets) {
        if ($null -ne $Cancel -and $Cancel.Requested) { break }
        if ($Progress) { $Progress.Total = $targets.Count; $Progress.Done = $i; $Progress.Text = "Ölçülüyor: $($t.Label)" }
        $s = Get-LtLatencyStats -Samples @(Measure-LtPing -Target $t.Address -Count $Count -Cancel $Cancel)
        $s.Kind = $t.Kind; $s.Label = $t.Label; $s.Address = $t.Address
        [void]$results.Add($s)
        $i++
    }
    $res = @($results)
    return @{ Time = (Get-Date).ToString('o'); Results = $res; Wifi = $Wifi; Verdict = @(Get-LtLatencyVerdict -Results $res -Wifi $Wifi) }
}

function Get-LtLatencyVerdict {
    <#
      Saf islev: sorunun nerede olabilecegini soyler. Esikler kaba yol gostericidir; tek olcum kesin
      sonuc degildir. Ayni saatte ve ayni kosullarda tekrarlayin.
    #>
    param([object[]]$Results, [bool]$Wifi = $false)
    $out = New-Object System.Collections.ArrayList
    $gw = @($Results | Where-Object { $_.Kind -eq 'Gateway' }) | Select-Object -First 1
    $inet = @($Results | Where-Object { $_.Kind -eq 'Internet' -and $null -ne $_.Avg })
    $localBad = $false
    if (-not $gw) { [void]$out.Add('Modem adresi bulunamadı; yerel ağ ayrıca değerlendirilemedi.') }
    elseif ($gw.Received -eq 0) {
        if ($inet.Count -gt 0) { [void]$out.Add('Modem ping''e yanıt vermiyor (bazı modemler ICMP''yi kapatır); yerel ağ değerlendirilemedi.') }
    } else {
        $avgLimit = if ($Wifi) { 15 } else { 5 }
        $jitLimit = if ($Wifi) { 8 } else { 3 }
        if ([double]$gw.LossPct -gt 0 -or [double]$gw.Avg -gt $avgLimit -or [double]$gw.Jitter -gt $jitLimit) {
            $localBad = $true
            [void]$out.Add("Ev içi ağda sorun belirtisi: modeme gecikme $($gw.Avg) ms, dalgalanma $($gw.Jitter) ms, kayıp %$($gw.LossPct). $(if ($Wifi) { 'Wi-Fi sinyali/kanal kalabalığı olası; kablo veya modeme yakınlık deneyin.' } else { 'Kablo, port veya modem yükü (aynı anda indirme/yayın) olası.' })")
        } else {
            [void]$out.Add("Ev içi ağ temiz görünüyor (modeme $($gw.Avg) ms, dalgalanma $($gw.Jitter) ms).")
        }
    }
    if ($inet.Count -eq 0) { [void]$out.Add('İnternet hedeflerine ulaşılamadı.') }
    else {
        $best = $inet | Sort-Object { [double]$_.Avg } | Select-Object -First 1
        $lossy = @($inet | Where-Object { [double]$_.LossPct -ge 2 })
        $jittery = @($inet | Where-Object { [double]$_.Jitter -gt 10 })
        if (-not $localBad -and ($lossy.Count -gt 0 -or $jittery.Count -gt 0)) {
            [void]$out.Add('Ev içi ağ temizken internette kayıp/dalgalanma var: sorun büyük olasılıkla hatta veya servis sağlayıcıda. Farklı saatlerde tekrarlayıp sonucu servis sağlayıcınıza iletin.')
        } elseif ($lossy.Count -gt 0 -or $jittery.Count -gt 0) {
            [void]$out.Add('İnternette de kayıp/dalgalanma görülüyor; önce ev içi ağ sorununu giderin, sonra yeniden ölçün.')
        } else {
            [void]$out.Add("İnternet bağlantısı kararlı (en düşük ortalama $($best.Avg) ms).")
        }
    }
    $custom = @($Results | Where-Object { $_.Kind -eq 'Custom' }) | Select-Object -First 1
    if ($custom) {
        if ($custom.Received -eq 0) { [void]$out.Add("$($custom.Address) ping'e yanıt vermedi; birçok oyun sunucusu ICMP'yi kapatır. Oyun içi ping göstergesini kullanın.") }
        elseif ($inet.Count -gt 0 -and [double]$custom.Avg -gt ([double]($inet | Sort-Object { [double]$_.Avg } | Select-Object -First 1).Avg + 40)) {
            [void]$out.Add("Oyun sunucusuna gecikme ($($custom.Avg) ms) genel hedeflerden belirgin yüksek: büyük olasılıkla mesafe/yönlendirme kaynaklı; bölge seçimi en etkili çözümdür. Windows ayarı bunu düşürmez.")
        }
    }
    [void]$out.Add('Not: Ping''i en çok bağlantı türü, mesafe ve aynı anda yapılan indirmeler belirler. Windows ayarları bunu ancak sınırlı etkiler; değişiklik öncesi ve sonrası aynı koşullarda ölçün.')
    return @($out)
}

function Get-LtLatencyHistoryPath { Join-Path (Join-Path (Get-LtDataRoot) 'network') 'latency-history.json' }

function Get-LtLatencyHistory {
    $p = Get-LtLatencyHistoryPath
    if (-not (Test-Path -LiteralPath $p)) { return @() }
    try {
        # PS 5.1 emits a JSON array as one pipeline object. Enumerate records explicitly.
        $records = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($p)) -ErrorAction Stop
        foreach ($record in @($records)) { ConvertTo-LtHashtable $record }
    } catch { return @() }
}

function Save-LtLatencyResult {
    <# Son 30 olcum saklanir (veri klasoru; sistem ayari degil). #>
    param([Parameter(Mandatory)]$Result)
    $p = Get-LtLatencyHistoryPath
    $dir = Split-Path -Parent $p
    if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
    $list = @(@(Get-LtLatencyHistory) + @($Result) | Select-Object -Last 30)
    Write-LtFileAtomic -Path $p -Content (ConvertTo-Json -InputObject @($list) -Depth 6)
}

function Compare-LtLatency {
    <# Saf islev: iki olcum arasindaki farklar (ayni adresler icin). #>
    param([Parameter(Mandatory)]$Current, [Parameter(Mandatory)]$Previous)
    $lines = New-Object System.Collections.ArrayList
    foreach ($c in @($Current.Results)) {
        $p = @($Previous.Results | Where-Object { [string]$_.Address -eq [string]$c.Address }) | Select-Object -First 1
        if (-not $p -or $null -eq $c.Avg -or $null -eq $p.Avg) { continue }
        $d = [math]::Round([double]$c.Avg - [double]$p.Avg, 1)
        $j = [math]::Round([double]$c.Jitter - [double]$p.Jitter, 1)
        $l = [math]::Round([double]$c.LossPct - [double]$p.LossPct, 1)
        $fmt = { param($v) if ($v -gt 0) { "+$v" } else { "$v" } }
        [void]$lines.Add("$($c.Label): ortalama $(& $fmt $d) ms, dalgalanma $(& $fmt $j) ms, kayıp $(& $fmt $l) puan")
    }
    return @($lines)
}

function Format-LtLatencyResult {
    param([Parameter(Mandatory)]$Result)
    $rows = foreach ($r in @($Result.Results)) {
        if ($r.Received -eq 0) { "{0}: yanıt yok (kayıp %100)" -f $r.Label }
        else { "{0}: ort {1} ms (min {2} / maks {3}), dalgalanma {4} ms, kayıp %{5}" -f $r.Label, $r.Avg, $r.Min, $r.Max, $r.Jitter, $r.LossPct }
    }
    return (@($rows) + '' + @($Result.Verdict)) -join "`n"
}

# ---------------------------------------------------------------------------
# DNS yanit suresi
# ---------------------------------------------------------------------------
function Measure-LtDnsResolver {
    <# Bir DNS sunucusunun yanit suresi (ms; basarisiz = $null). Salt okunur sorgu. #>
    param([Parameter(Mandatory)][string]$Server, [Parameter(Mandatory)][string]$Name)
    if ((Get-LtBackend) -eq 'Memory') {
        $m = Get-LtMemoryState
        if ($m.ContainsKey('Network') -and $m.Network -and $m.Network.ContainsKey('Dns') -and $m.Network.Dns.ContainsKey($Server)) { return $m.Network.Dns[$Server] }
        return 25.0
    }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        [void](Resolve-DnsName -Name $Name -Server $Server -Type A -DnsOnly -NoHostsFile -QuickTimeout -ErrorAction Stop)
        return [math]::Round($sw.Elapsed.TotalMilliseconds, 1)
    } catch { return $null }
}

function Invoke-LtDnsBenchmark {
    <# Mevcut DNS + Cloudflare/Google/Quad9: her ad 3 kez sorgulanir, medyan alinir. #>
    param([string[]]$Current = @(), $Progress = $null, $Cancel = $null)
    $names = @('www.google.com', 'store.steampowered.com', 'www.microsoft.com', 'discord.com')
    $resolvers = New-Object System.Collections.ArrayList
    foreach ($c in @($Current | Where-Object { $_ -and $_ -notmatch ':' } | Select-Object -First 1)) { [void]$resolvers.Add(@{ Label = "Mevcut ($c)"; Address = $c }) }
    foreach ($k in $script:LtDnsProviders.Keys) {
        $addr = $script:LtDnsProviders[$k].Servers[0]
        if (@($resolvers | Where-Object { $_.Address -eq $addr }).Count -eq 0) { [void]$resolvers.Add(@{ Label = "$($script:LtDnsProviders[$k].Label) ($addr)"; Address = $addr }) }
    }
    $out = New-Object System.Collections.ArrayList
    $i = 0
    foreach ($r in $resolvers) {
        if ($null -ne $Cancel -and $Cancel.Requested) { break }
        if ($Progress) { $Progress.Total = $resolvers.Count; $Progress.Done = $i; $Progress.Text = "DNS ölçülüyor: $($r.Label)" }
        $samples = New-Object System.Collections.ArrayList
        foreach ($n in $names) { for ($k = 0; $k -lt 3; $k++) { [void]$samples.Add((Measure-LtDnsResolver -Server $r.Address -Name $n)) } }
        $ok = @($samples | Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ } | Sort-Object)
        $median = if ($ok.Count -gt 0) { $ok[[int][math]::Floor(($ok.Count - 1) / 2)] } else { $null }
        [void]$out.Add(@{ Label = $r.Label; Address = $r.Address; MedianMs = $median; Failed = ($samples.Count - $ok.Count); Total = $samples.Count })
        $i++
    }
    return @($out | Sort-Object { if ($null -eq $_.MedianMs) { [double]::MaxValue } else { [double]$_.MedianMs } })
}

function Format-LtDnsBenchmark {
    param([object[]]$Results)
    $rows = foreach ($r in @($Results)) {
        if ($null -eq $r.MedianMs) { "{0}: yanıt yok" -f $r.Label } else { "{0}: {1} ms{2}" -f $r.Label, $r.MedianMs, $(if ($r.Failed) { " ($($r.Failed)/$($r.Total) sorgu başarısız)" } else { '' }) }
    }
    return (@($rows) + 'DNS yanıt süresi web sitelerinin ve oyun başlatıcılarının bağlantı kurma süresini etkiler; oyun içi ping''i değiştirmez.') -join "`n"
}

# ---------------------------------------------------------------------------
# DNS sunucusu ayari (secili adaptor) — geri alinabilir saglayici
# ---------------------------------------------------------------------------
function Get-LtNicIndex {
    param([Parameter(Mandatory)][string]$InterfaceGuid)
    $guid = ([guid]$InterfaceGuid).ToString('D')
    $found = @(Get-NetAdapter -ErrorAction Stop | Where-Object { ([string]$_.InterfaceGuid).Trim('{}') -ieq $guid })
    if ($found.Count -ne 1) { throw 'DNS ayarı için adaptör bulunamadı veya kimliği belirsiz.' }
    return [int]$found[0].ifIndex
}

function Get-LtDnsServerConfig {
    <# Donus: @{ Static = [bool]; Servers = [string[]] } #>
    param([Parameter(Mandatory)][string]$InterfaceGuid)
    $key = ([guid]$InterfaceGuid).ToString('D')
    if ((Get-LtBackend) -eq 'Memory') {
        $m = Get-LtMemoryState
        if (-not $m.ContainsKey('Dns')) { $m.Dns = @{} }
        if (-not $m.Dns.ContainsKey($key)) { $m.Dns[$key] = @{ Static = $false; Servers = @('192.168.1.1') } }
        [void](Invoke-LtMemFault 'Dns.Get' $key)
        $snapshot = @{ Static = [bool]$m.Dns[$key].Static; Servers = @($m.Dns[$key].Servers) }
        if ($m.Dns[$key].ContainsKey('Families')) {
            $snapshot.Families = @{}
            foreach ($family in @('IPv4', 'IPv6')) {
                $f = $m.Dns[$key].Families[$family]
                $snapshot.Families[$family] = @{ Static = [bool]$f.Static; Servers = @($f.Servers) }
            }
        }
        return $snapshot
    }
    $idx = Get-LtNicIndex -InterfaceGuid $InterfaceGuid
    $b = ([guid]$InterfaceGuid).ToString('B')
    $families = @{}; $servers = @()
    foreach ($family in @('IPv4', 'IPv6')) {
        $addresses = @(Get-DnsClientServerAddress -InterfaceIndex $idx -AddressFamily $family -ErrorAction Stop | ForEach-Object { $_.ServerAddresses } | Where-Object { $_ })
        $service = if ($family -eq 'IPv4') { 'Tcpip' } else { 'Tcpip6' }
        $reg = Get-LtRegValue "HKLM\SYSTEM\CurrentControlSet\Services\$service\Parameters\Interfaces\$b" 'NameServer'
        $static = $reg.Exists -and -not [string]::IsNullOrWhiteSpace([string]$reg.Data)
        $families[$family] = @{ Static = [bool]$static; Servers = @($addresses) }
        $servers += $addresses
    }
    return @{ Static = [bool]($families.IPv4.Static -or $families.IPv6.Static); Servers = @($servers); Families = $families }
}

function Set-LtDnsServers {
    param([Parameter(Mandatory)][string]$InterfaceGuid, [Parameter(Mandatory)][string[]]$Servers)
    foreach ($s in $Servers) { $ip = $null; if (-not [System.Net.IPAddress]::TryParse($s, [ref]$ip)) { throw "Geçersiz DNS adresi: $s" } }
    $key = ([guid]$InterfaceGuid).ToString('D')
    if ((Get-LtBackend) -eq 'Memory') {
        $m = Get-LtMemoryState
        if (-not $m.ContainsKey('Dns')) { $m.Dns = @{} }
        [void](Invoke-LtMemFault 'Dns.Set' $key)
        [void]$m.Calls.Add("Dns.Set|$key|$($Servers -join ',')")
        $m.Dns[$key] = @{ Static = $true; Servers = @($Servers) }
        return
    }
    $idx = Get-LtNicIndex -InterfaceGuid $InterfaceGuid
    Set-DnsClientServerAddress -InterfaceIndex $idx -ServerAddresses $Servers -ErrorAction Stop
    try { Clear-DnsClientCache -ErrorAction Stop } catch { $null = $_ }
}

function Reset-LtDnsServers {
    param([Parameter(Mandatory)][string]$InterfaceGuid)
    $key = ([guid]$InterfaceGuid).ToString('D')
    if ((Get-LtBackend) -eq 'Memory') {
        $m = Get-LtMemoryState
        if (-not $m.ContainsKey('Dns')) { $m.Dns = @{} }
        [void]$m.Calls.Add("Dns.Reset|$key")
        $m.Dns[$key] = @{ Static = $false; Servers = @('192.168.1.1') }
        return
    }
    $idx = Get-LtNicIndex -InterfaceGuid $InterfaceGuid
    Set-DnsClientServerAddress -InterfaceIndex $idx -ResetServerAddresses -ErrorAction Stop
    try { Clear-DnsClientCache -ErrorAction Stop } catch { $null = $_ }
}

function Restore-LtDnsServerConfig {
    param([Parameter(Mandatory)][string]$InterfaceGuid, [Parameter(Mandatory)]$Snapshot)
    $families = Get-LtProp $Snapshot 'Families' $null
    if (-not $families) {
        # Legacy journals did not retain address-family modes. Preserve their old semantics.
        if ($Snapshot.Static) { Set-LtDnsServers -InterfaceGuid $InterfaceGuid -Servers @($Snapshot.Servers) }
        else { Reset-LtDnsServers -InterfaceGuid $InterfaceGuid }
        return
    }
    if ((Get-LtBackend) -eq 'Memory') {
        $m = Get-LtMemoryState; $key = ([guid]$InterfaceGuid).ToString('D')
        [void](Invoke-LtMemFault 'Dns.Set' $key)
        $copy = @{}
        foreach ($family in @('IPv4', 'IPv6')) { $f = $families[$family]; $copy[$family] = @{ Static = [bool]$f.Static; Servers = @($f.Servers) } }
        $m.Dns[$key] = @{ Static = [bool]$Snapshot.Static; Servers = @($Snapshot.Servers); Families = $copy }
        [void]$m.Calls.Add("Dns.Restore|$key")
        return
    }
    $idx = Get-LtNicIndex -InterfaceGuid $InterfaceGuid
    foreach ($family in @('IPv4', 'IPv6')) {
        $f = $families[$family]
        $inputObjects = @(Get-DnsClientServerAddress -InterfaceIndex $idx -AddressFamily $family -ErrorAction Stop)
        if ($inputObjects.Count -ne 1) { throw "DNS adres ailesi bulunamadı veya belirsiz: $family" }
        if ($f.Static) { Set-DnsClientServerAddress -InputObject $inputObjects[0] -ServerAddresses @($f.Servers) -ErrorAction Stop }
        else { Set-DnsClientServerAddress -InputObject $inputObjects[0] -ResetServerAddresses -ErrorAction Stop }
    }
    try { Clear-DnsClientCache -ErrorAction Stop } catch { $null = $_ }
}

function Test-LtDnsSnapshotEqual {
    param($A, $B)
    $af = Get-LtProp $A 'Families' $null; $bf = Get-LtProp $B 'Families' $null
    if ($af -and $bf) {
        foreach ($family in @('IPv4', 'IPv6')) {
            if (-not (Test-LtDnsSnapshotEqual $af[$family] $bf[$family])) { return $false }
        }
        return $true
    }
    if ([bool]$A.Static -ne [bool]$B.Static) { return $false }
    if (-not $A.Static) { return $true }   # DHCP: sunucular agdan gelir
    return ((@($A.Servers) -join ',') -eq (@($B.Servers) -join ','))
}

$script:LtProviders['DnsServers'] = @{
    Key = { param($a) 'Dns|' + ([guid][string]$a.InterfaceGuid).ToString('D') }
    Capture = { param($a) Get-LtDnsServerConfig -InterfaceGuid $a.InterfaceGuid }
    IsDesired = { param($a, $s) ([bool]$s.Static -and ((@($s.Servers) -join ',') -eq (@($a.Servers) -join ','))) }
    Apply = { param($a) Set-LtDnsServers -InterfaceGuid $a.InterfaceGuid -Servers @($a.Servers) }
    Restore = { param($a, $s) Restore-LtDnsServerConfig -InterfaceGuid $a.InterfaceGuid -Snapshot $s }
    Default = { param($a) Reset-LtDnsServers -InterfaceGuid $a.InterfaceGuid }
    DefaultSnapshot = { param($a) @{ Static = $false; Servers = @() } }
    FormatState = { param($a, $s) if ($s.Static) { 'Elle: ' + (@($s.Servers) -join ', ') } else { 'Otomatik (DHCP)' + $(if (@($s.Servers).Count) { ': ' + (@($s.Servers) -join ', ') } else { '' }) } }
    FormatDesired = { param($a) 'Elle: ' + (@($a.Servers) -join ', ') }
    Target = { param($a) "DNS sunucuları: $($a.Adapter)" }
}

function New-LtDnsAction {
    param([Parameter(Mandatory)]$Ctx, [Parameter(Mandatory)][string]$Provider)
    $nic = Get-LtSelectedNic $Ctx
    @{ Type = 'DnsServers'; InterfaceGuid = ([guid][string]$nic.InterfaceGuid).ToString('D'); Adapter = $nic.Name; Servers = @($script:LtDnsProviders[$Provider].Servers); Default = 'Dhcp' }
}
