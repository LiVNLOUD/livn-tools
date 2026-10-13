# Livn Tools - Core/Journal.ps1
# Kalici degisiklik gunlugu (journal) ve ozgun deger defteri (ledger).
#
# journal\<opId>.jsonl  : islem basina, yalniz-ekleme (append-only) JSON satirlari.
#                         Her degisiklikten ONCE eski durum diske yazilir (WriteThrough).
#                         'end' satiri olmayan dosya = yarim kalmis islem (kurtarma).
# state\ledger.json     : Livn Tools'un ilk kez degistirdigi her hedefin ozgun degeri.
#                         "Onceki ayara don" bu kaydi kullanir; ayni ayar tekrar
#                         uygulansa bile ozgun deger ezilmez.

Set-StrictMode -Version 2.0

$script:LtDataRoot = $null

function Initialize-LtDataRoot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    foreach ($d in @($Path, (Join-Path $Path 'journal'), (Join-Path $Path 'state'), (Join-Path $Path 'logs'), (Join-Path $Path 'backups'))) {
        if (-not (Test-Path -LiteralPath $d)) { $null = New-Item -ItemType Directory -Path $d -Force }
    }
    $script:LtDataRoot = (Resolve-Path -LiteralPath $Path).ProviderPath
}

function Get-LtDataRoot {
    if (-not $script:LtDataRoot) { throw 'Veri klasörü başlatılmadı (Initialize-LtDataRoot).' }
    return $script:LtDataRoot
}

function Get-LtJournalPath([string]$OperationId) { Join-Path (Join-Path (Get-LtDataRoot) 'journal') "$OperationId.jsonl" }
function Get-LtLedgerPath { Join-Path (Join-Path (Get-LtDataRoot) 'state') 'ledger.json' }

function Add-LtJournalEntry {
    <# Satiri diske yazar ve isletim sistemi arabellegini bosaltir (WriteThrough). #>
    param([Parameter(Mandatory)][string]$OperationId, [Parameter(Mandatory)][hashtable]$Entry)
    $Entry['time'] = (Get-Date).ToString('o')
    $json = ConvertTo-Json -InputObject $Entry -Depth 12 -Compress
    $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($json + "`n")
    $fs = New-Object System.IO.FileStream((Get-LtJournalPath $OperationId), [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read, 4096, [System.IO.FileOptions]::WriteThrough)
    try { $fs.Write($bytes, 0, $bytes.Length); $fs.Flush($true) } finally { $fs.Dispose() }
}

function New-LtOperation {
    <# Yeni islem kimligi olusturur ve 'begin' kaydini yazar. #>
    param([Parameter(Mandatory)][ValidateSet('Apply','RevertPrevious','RevertDefault','RestoreBackup','Recovery')][string]$Kind, [string[]]$TweakIds = @(), [string]$Note = '')
    $id = '{0}_{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
    Add-LtJournalEntry -OperationId $id -Entry @{
        t = 'begin'; kind = $Kind; tweaks = @($TweakIds); note = $Note
        user = [Environment]::UserName; machine = [Environment]::MachineName
        os = [string][Environment]::OSVersion.Version; backend = (Get-LtBackend); version = $script:LtVersion
    }
    return $id
}

function Complete-LtOperation {
    param([Parameter(Mandatory)][string]$OperationId, [string]$Outcome = 'completed', [hashtable]$Summary = @{})
    Add-LtJournalEntry -OperationId $OperationId -Entry @{ t = 'end'; outcome = $Outcome; summary = $Summary }
}

function Read-LtJournal {
    param([Parameter(Mandatory)][string]$OperationId)
    $path = Get-LtJournalPath $OperationId
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    $entries = New-Object System.Collections.ArrayList
    foreach ($line in [System.IO.File]::ReadAllLines($path, [System.Text.Encoding]::UTF8)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            [void]$entries.Add((ConvertTo-LtHashtable (ConvertFrom-Json $line)))
        } catch {
            # Kesilmis son satir (guc kesintisi) yoksayilir; oncekiler gecerli kalir
            Write-LtLog "Journal satırı okunamadı ($OperationId): bozuk satır atlandı." 'WARN'
        }
    }
    return @($entries)
}

function Get-LtOperations {
    $dir = Join-Path (Get-LtDataRoot) 'journal'
    $ops = foreach ($f in (Get-ChildItem -LiteralPath $dir -Filter '*.jsonl' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $id = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        $entries = @(Read-LtJournal $id)
        $begin = $entries | Where-Object { $_.t -eq 'begin' } | Select-Object -First 1
        $end   = $entries | Where-Object { $_.t -eq 'end' } | Select-Object -Last 1
        [pscustomobject]@{
            Id         = $id
            Kind       = if ($begin) { $begin.kind } else { '?' }
            Started    = if ($begin) { $begin.time } else { $null }
            Completed  = [bool]$end
            Outcome    = if ($end) { $end.outcome } else { 'incomplete' }
            Changes    = @($entries | Where-Object { $_.t -eq 'change' }).Count
            Entries    = $entries
        }
    }
    return @($ops)
}

function Get-LtIncompleteOperations {
    return @(Get-LtOperations | Where-Object { -not $_.Completed -and $_.Changes -gt 0 })
}

# ---------------------------------------------------------------------------
# LEDGER
# ---------------------------------------------------------------------------
function Read-LtLedger {
    $path = Get-LtLedgerPath
    # Yarida kalmis atomik yazimdan kalan .bak: ozgun degerler sessizce kaybolmasin
    if (Restore-LtAtomicWriteBackup -Path $path) { Write-LtLog "Ledger yarım kalmış bir yazımdan kurtarıldı: $path.bak → $path" 'WARN' }
    if (-not (Test-Path -LiteralPath $path)) { return @{ version = 1; entries = @{} } }
    $raw = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    if ([string]::IsNullOrWhiteSpace($raw)) { return @{ version = 1; entries = @{} } }
    try {
        $h = ConvertTo-LtHashtable (ConvertFrom-Json $raw)
    } catch {
        # Bozuk ledger silinmez; yedeklenir ve kullaniciya bildirilir
        $bad = "$path.corrupt-$(Get-Date -Format 'yyyyMMddHHmmss')"
        Copy-Item -LiteralPath $path -Destination $bad -Force
        throw "Ledger dosyası okunamadı; kopyası saklandı: $bad"
    }
    if (-not $h.ContainsKey('entries') -or $null -eq $h.entries) { $h.entries = @{} }
    return $h
}

function Save-LtLedger([hashtable]$Ledger) {
    Write-LtFileAtomic -Path (Get-LtLedgerPath) -Content (ConvertTo-Json -InputObject $Ledger -Depth 14)
}

function Add-LtLedgerOriginal {
    <#
      Hedef icin ozgun deger kaydi yoksa ekler. Donus: $true = yeni kayit eklendi.
      Varsa yalnizca sahip ayar listesine ekler (ozgun deger KORUNUR).
    #>
    param([Parameter(Mandatory)][string]$Key, [Parameter(Mandatory)][hashtable]$Action, [Parameter(Mandatory)]$Snapshot, [string]$TweakId = '', [string]$OperationId = '')
    $l = Read-LtLedger
    if ($l.entries.ContainsKey($Key)) {
        $e = $l.entries[$Key]
        if ($Action.Type -eq 'Registry') { Assert-LtRegistrySnapshotOwner $Action $e.original }
        $owners = @($e.tweakIds)
        if ($TweakId -and $owners -notcontains $TweakId) { $e.tweakIds = @($owners + $TweakId); Save-LtLedger $l }
        return $false
    }
    $l.entries[$Key] = @{ key = $Key; action = $Action; original = $Snapshot; tweakIds = @($TweakId); opId = $OperationId; time = (Get-Date).ToString('o') }
    Save-LtLedger $l
    return $true
}

function Get-LtLedgerEntry([string]$Key) {
    $l = Read-LtLedger
    if ($l.entries.ContainsKey($Key)) { return $l.entries[$Key] }
    return $null
}

function Remove-LtLedgerEntry([string]$Key) {
    $l = Read-LtLedger
    if ($l.entries.ContainsKey($Key)) { $l.entries.Remove($Key); Save-LtLedger $l }
}

function Get-LtLedgerEntries {
    $l = Read-LtLedger
    return @($l.entries.Values)
}
