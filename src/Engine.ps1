# Livn Tools - Engine.ps1
# Ortak islem motoru: durum okuma, onizleme (degisiklik yapmaz), uygulama
# (journal + ledger + dogrulama + ayar basina geri sarma), onceki ayara donme,
# Windows varsayilanina donme, yarim kalan islemi kurtarma, durum yedegi.
# Tekil sayfa butonlari, presetler ve "Tumunu uygula" AYNI fonksiyonlari kullanir.

Set-StrictMode -Version 2.0

$script:LtCatalogCache = $null

function Get-LtCatalog {
    [CmdletBinding()]
    param([switch]$Refresh)
    if ($Refresh -or $null -eq $script:LtCatalogCache) {
        $list = @(Get-LtTweakDefinitions)
        $seen = @{}
        foreach ($t in $list) {
            if ($seen.ContainsKey($t.Id)) { throw "Katalogda yinelenen kimlik: $($t.Id)" }
            $seen[$t.Id] = $true
        }
        $script:LtCatalogCache = $list
    }
    return $script:LtCatalogCache
}

function Get-LtTweak {
    param([Parameter(Mandatory)][string]$Id)
    $t = Get-LtCatalog | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
    if (-not $t) { throw "Bilinmeyen ayar kimliği: $Id" }
    return $t
}

function Get-LtTweakSupport {
    <# $null = destekleniyor; aksi halde Turkce neden metni #>
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$Context)
    $sb = Get-LtProp $Tweak 'Supported'
    if ($null -eq $sb) { return $null }
    try {
        $r = & $sb $Context
        if ($r) { return [string]$r }
        return $null
    } catch {
        return "Destek kontrolü yapılamadı: $($_.Exception.Message)"
    }
}

function Resolve-LtTweakActions {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$Context)
    $from = Get-LtProp $Tweak 'ActionsFrom'
    if ($from) { return @(& $from $Context) }
    return @(Get-LtProp $Tweak 'Actions' @())
}

function Get-LtRestartText([string]$Kind) {
    switch ($Kind) {
        'Reboot'   { 'Yeniden başlatma gerekir' }
        'Logoff'   { 'Oturumu kapatıp açma gerekir' }
        'Explorer' { 'Explorer yeniden başlatılmalı' }
        default    { '' }
    }
}

# ---------------------------------------------------------------------------
# DURUM (salt okunur)
# ---------------------------------------------------------------------------
function Get-LtTweakStatus {
    <#
      State: Applied | NotApplied | Partial | NotSupported | Unknown
      Owned: Livn Tools bu ayarin ozgun degerini kaydetmis mi (Onceki ayara don mumkun mu)
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$Context)
    $reason = Get-LtTweakSupport $Tweak $Context
    $owned = @(Get-LtLedgerEntries | Where-Object { @($_.tweakIds) -contains $Tweak.Id }).Count -gt 0
    if ($reason) {
        return [pscustomobject]@{ Id = $Tweak.Id; State = 'NotSupported'; Reason = $reason; Actions = @(); Owned = $owned; HasDefault = $false }
    }
    try { $actions = @(Resolve-LtTweakActions $Tweak $Context) }
    catch { return [pscustomobject]@{ Id = $Tweak.Id; State = 'Unknown'; Reason = "Eylemler hazırlanamadı: $($_.Exception.Message)"; Actions = @(); Owned = $owned; HasDefault = $false } }
    if ($actions.Count -eq 0) {
        return [pscustomobject]@{ Id = $Tweak.Id; State = 'NotSupported'; Reason = 'Bu sistemde uygulanabilecek hedef bulunamadı.'; Actions = @(); Owned = $owned; HasDefault = $false }
    }
    $rows = New-Object System.Collections.ArrayList
    $inDesired = 0; $errors = 0; $missing = $null
    foreach ($a in $actions) {
        try {
            $s = Get-LtActionSnapshot $a
            if ($a.Type -eq 'Service' -and -not $s.Exists) { $missing = "Servis bu sistemde yok: $($a.Name)" }
            $ok = Test-LtActionDesired $a $s
            if ($ok) { $inDesired++ }
            [void]$rows.Add([pscustomobject]@{ Key = (Get-LtActionKey $a); Target = (Get-LtActionTarget $a); Current = (Format-LtActionState $a $s); Desired = (Format-LtActionDesired $a); InDesired = $ok; Error = $null })
        } catch {
            $errors++
            [void]$rows.Add([pscustomobject]@{ Key = ''; Target = (Get-LtActionTarget $a); Current = 'okunamadı'; Desired = (Format-LtActionDesired $a); InDesired = $false; Error = $_.Exception.Message })
        }
    }
    $hasDefault = @($actions | Where-Object { -not (Test-LtActionHasDefault $_) }).Count -eq 0
    if ($missing) { $state = 'NotSupported'; $reason = $missing }
    elseif ($errors -gt 0) { $state = 'Unknown'; $reason = (@($rows | Where-Object { $_.Error }) | Select-Object -First 1).Error }
    elseif ($inDesired -eq $actions.Count) { $state = 'Applied' }
    elseif ($inDesired -eq 0) { $state = 'NotApplied' }
    else { $state = 'Partial' }
    return [pscustomobject]@{ Id = $Tweak.Id; State = $state; Reason = $reason; Actions = @($rows); Owned = $owned; HasDefault = $hasDefault }
}

# ---------------------------------------------------------------------------
# HAZIR SECIM COZUMLEME (salt okunur; yalniz hangi ayarlarin isaretlenecegini belirler)
# ---------------------------------------------------------------------------
function Resolve-LtPresetSelection {
    <#
      Donus: @{ Name; Title; Description; Selected = [string[]]; Unsupported = @(@{ Id; Title; Reason }); Choices = @(@{ Id; Title }) }
      Destek, katalogdaki Supported kurallariyla bu sistem icin kontrol edilir.
    #>
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)]$Context)
    $presets = Get-LtPresets
    if (-not $presets.Contains($Name)) { throw "Bilinmeyen hazır seçim: $Name" }
    $p = $presets[$Name]
    $selected = New-Object System.Collections.ArrayList
    $unsupported = New-Object System.Collections.ArrayList
    $choices = New-Object System.Collections.ArrayList
    foreach ($group in @(Get-LtProp $p 'OneOf' @())) {
        $picked = $null; $reasons = New-Object System.Collections.ArrayList
        foreach ($id in @($group)) {
            $t = Get-LtTweak $id
            $why = Get-LtTweakSupport $t $Context
            if (-not $why) { $picked = $t; break }
            [void]$reasons.Add("$($t.Title): $why")
        }
        if ($picked) { [void]$selected.Add($picked.Id); [void]$choices.Add([pscustomobject]@{ Id = $picked.Id; Title = $picked.Title }) }
        else { [void]$unsupported.Add([pscustomobject]@{ Id = (@($group) -join '|'); Title = 'Seçenek grubu'; Reason = ($reasons -join ' · ') }) }
    }
    foreach ($id in @($p.Ids)) {
        $t = Get-LtTweak $id
        $why = Get-LtTweakSupport $t $Context
        if ($why) { [void]$unsupported.Add([pscustomobject]@{ Id = $id; Title = $t.Title; Reason = $why }) }
        elseif ($selected -notcontains $id) { [void]$selected.Add($id) }
    }
    return [pscustomobject]@{ Name = $Name; Title = $p.Title; Description = $p.Description; Selected = @($selected); Unsupported = @($unsupported); Choices = @($choices) }
}

# ---------------------------------------------------------------------------
# ONIZLEME (degisiklik yapmaz)
# ---------------------------------------------------------------------------
function Get-LtPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$TweakIds,
        [Parameter(Mandatory)]$Context,
        [ValidateSet('Apply','RevertPrevious','RevertDefault')][string]$Mode = 'Apply'
    )
    $items = New-Object System.Collections.ArrayList
    $groups = @{}
    foreach ($id in $TweakIds) {
        $t = Get-LtTweak $id
        $ex = Get-LtProp $t 'Exclusive'
        if ($Mode -eq 'Apply' -and $ex) {
            if ($groups.ContainsKey($ex)) {
                [void]$items.Add([pscustomobject]@{ Id = $id; Title = $t.Title; Risk = $t.Risk; Outcome = 'Conflict'; Message = "Aynı gruptan yalnızca biri uygulanabilir ($($groups[$ex]) seçili)."; Changes = @(); Restart = 'None'; Warning = '' })
                continue
            }
            $groups[$ex] = $id
        }
        $changes = New-Object System.Collections.ArrayList
        $outcome = 'NoChange'; $msg = ''
        if ($Mode -eq 'RevertPrevious') {
            $entries = @(Get-LtLedgerEntries | Where-Object { @($_.tweakIds) -contains $id })
            if ($entries.Count -eq 0) { $outcome = 'NoRecord'; $msg = 'Livn Tools bu ayarı değiştirmemiş; geri yüklenecek önceki değer kaydı yok.' }
            foreach ($e in $entries) {
                try {
                    $cur = Get-LtActionSnapshot $e.action
                    if (-not (Test-LtSnapshotEqual $e.action $cur $e.original)) {
                        $outcome = 'WillChange'
                        # Mevcut deger Livn'in uyguladigi hedef degilse: uygulamadan sonra kullanici,
                        # baska bir program veya "Windows varsayilani" islemi degistirmistir.
                        # Geri alma bu degeri de ezer; kullanici onaydan once bunu gormeli.
                        $drifted = -not (Test-LtActionDesired $e.action $cur)
                        $from = Format-LtActionState $e.action $cur
                        if ($drifted) {
                            $from += ' [Livn uyguladıktan sonra değişmiş]'
                            $msg = 'Dikkat: bazı değerler Livn''in uyguladığı değer değil; sonradan başka bir program, kullanıcı veya varsayılana dönüş tarafından değiştirilmiş olabilir. Onaylarsanız bu değerler de özgün değerle değiştirilir.'
                        }
                        [void]$changes.Add([pscustomobject]@{ Target = (Get-LtActionTarget $e.action); From = $from; To = (Format-LtActionState $e.action $e.original); Drifted = $drifted })
                    }
                } catch { $outcome = 'Error'; $msg = $_.Exception.Message }
            }
        } else {
            $reason = Get-LtTweakSupport $t $Context
            if ($reason) { $outcome = 'NotSupported'; $msg = $reason }
            else {
                try {
                    foreach ($a in @(Resolve-LtTweakActions $t $Context)) {
                        $cur = Get-LtActionSnapshot $a
                        if ($a.Type -eq 'Service' -and -not $cur.Exists) { $outcome = 'NotSupported'; $msg = "Servis yok: $($a.Name)"; break }
                        if ($Mode -eq 'Apply') {
                            if (-not (Test-LtActionDesired $a $cur)) {
                                $outcome = 'WillChange'
                                [void]$changes.Add([pscustomobject]@{ Target = (Get-LtActionTarget $a); From = (Format-LtActionState $a $cur); To = (Format-LtActionDesired $a) })
                            }
                        } else {
                            if (-not (Test-LtActionHasDefault $a)) {
                                if ($outcome -ne 'WillChange') { $outcome = 'NoDefault' }
                                $msg = 'Windows varsayılanı tanımlı değil (yalnızca "önceki ayar" geri yüklenebilir).'
                                continue
                            }
                            $def = Get-LtActionDefaultSnapshot $a
                            if (-not (Test-LtSnapshotEqual $a $cur $def)) {
                                $outcome = 'WillChange'
                                [void]$changes.Add([pscustomobject]@{ Target = (Get-LtActionTarget $a); From = (Format-LtActionState $a $cur); To = (Format-LtActionState $a $def) + ' (Windows varsayılanı)' })
                            }
                        }
                    }
                } catch { $outcome = 'Error'; $msg = $_.Exception.Message }
            }
        }
        [void]$items.Add([pscustomobject]@{
            Id = $id; Title = $t.Title; Risk = $t.Risk; Outcome = $outcome; Message = $msg
            Changes = @($changes); Restart = $t.Restart; Warning = [string](Get-LtProp $t 'Warning' '')
        })
    }
    return @($items)
}

# ---------------------------------------------------------------------------
# UYGULAMA
# ---------------------------------------------------------------------------
function Update-LtProgress {
    param($Progress, [int]$Done, [int]$Total, [string]$Text)
    if ($null -eq $Progress) { return }
    $Progress.Done = $Done; $Progress.Total = $Total; $Progress.Text = $Text
}

function Test-LtCancelRequested($Cancel) {
    return ($null -ne $Cancel -and [bool]$Cancel.Requested)
}

function Invoke-LtTweakApply {
    <# Tek ayari transaction mantigiyla uygular. Hata -> bu ayarin yaptigi degisiklikler geri alinir. #>
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$Context, [Parameter(Mandatory)][string]$OperationId, [ref]$Seq)
    $id = $Tweak.Id; $title = $Tweak.Title
    $reason = Get-LtTweakSupport $Tweak $Context
    if ($reason) { return New-LtResult -Id $id -Title $title -Status NotSupported -Message $reason }

    try { $actions = @(Resolve-LtTweakActions $Tweak $Context) }
    catch { return New-LtResult -Id $id -Title $title -Status Failed -Message "Eylemler hazırlanamadı: $($_.Exception.Message)" }
    if ($actions.Count -eq 0) { return New-LtResult -Id $id -Title $title -Status NotSupported -Message 'Bu sistemde uygulanabilecek hedef bulunamadı.' }

    # 1) Tum mevcut durumu once oku (hicbir sey degistirmeden)
    $pending = New-Object System.Collections.ArrayList
    foreach ($a in $actions) {
        try {
            $snap = Get-LtActionSnapshot $a
            if ($a.Type -eq 'Registry') {
                $existing = Get-LtLedgerEntry (Get-LtActionKey $a)
                if ($existing) { Assert-LtRegistrySnapshotOwner $a $existing.original }
            }
        }
        catch { return New-LtResult -Id $id -Title $title -Status Failed -Message "Mevcut durum okunamadı ($(Get-LtActionTarget $a)): $($_.Exception.Message). Hiçbir değişiklik yapılmadı." }
        if ($a.Type -eq 'Service' -and -not $snap.Exists) { return New-LtResult -Id $id -Title $title -Status NotSupported -Message "Servis bu sistemde yok: $($a.Name)" }
        if (-not (Test-LtActionDesired $a $snap)) { [void]$pending.Add(@{ Action = $a; Before = $snap; Key = (Get-LtActionKey $a) }) }
    }
    if ($pending.Count -eq 0) {
        return New-LtResult -Id $id -Title $title -Status AlreadyApplied -Message 'Sistem zaten hedef durumda; değişiklik yapılmadı.'
    }

    # 2) Degistir -> dogrula
    $done = New-Object System.Collections.ArrayList
    $details = New-Object System.Collections.ArrayList
    $current = $null
    try {
        foreach ($p in $pending) {
            $current = $p
            $Seq.Value++
            $p.Cid = $Seq.Value
            Add-LtJournalEntry -OperationId $OperationId -Entry @{ t = 'change'; cid = $p.Cid; mode = 'Apply'; tweak = $id; key = $p.Key; action = $p.Action; before = $p.Before }
            $p.LedgerAdded = Add-LtLedgerOriginal -Key $p.Key -Action $p.Action -Snapshot $p.Before -TweakId $id -OperationId $OperationId
            Invoke-LtActionApply $p.Action
            $after = Get-LtActionSnapshot $p.Action
            if (-not (Test-LtActionDesired $p.Action $after)) {
                throw ("Doğrulama başarısız: {0} — beklenen {1}, okunan {2}" -f (Get-LtActionTarget $p.Action), (Format-LtActionDesired $p.Action), (Format-LtActionState $p.Action $after))
            }
            Add-LtJournalEntry -OperationId $OperationId -Entry @{ t = 'applied'; cid = $p.Cid }
            [void]$done.Add($p)
            [void]$details.Add(('{0}: {1} → {2}' -f (Get-LtActionTarget $p.Action), (Format-LtActionState $p.Action $p.Before), (Format-LtActionState $p.Action $after)))
            $current = $null
        }
    } catch {
        $err = $_.Exception.Message
        # Gunluk/ledger yazimi da basarisiz olabilir (disk dolu, erisim). Bu durumda bile
        # geri sarma CALISMALI ve sonuc gercek sistem durumuna gore raporlanmali.
        $recordErrors = New-Object System.Collections.ArrayList
        if ($current -and $current.ContainsKey('Cid')) {
            try { Add-LtJournalEntry -OperationId $OperationId -Entry @{ t = 'failed'; cid = $current.Cid; error = $err } }
            catch { [void]$recordErrors.Add("journal: $($_.Exception.Message)") }
        }
        # Geri sar: basarisiz eylem (kismen uygulanmis olabilir) + tamamlananlar, ters sirada
        $toUndo = New-Object System.Collections.ArrayList
        if ($current -and $current.ContainsKey('Cid')) { [void]$toUndo.Add($current) }
        for ($i = $done.Count - 1; $i -ge 0; $i--) { [void]$toUndo.Add($done[$i]) }
        $undoErrors = New-Object System.Collections.ArrayList
        foreach ($u in $toUndo) {
            try {
                # Sistem zaten ozgun durumdaysa (eylem hic uygulanmadi) yazma yapilmaz
                $chk = Get-LtActionSnapshot $u.Action
                if (-not (Test-LtSnapshotEqual $u.Action $chk $u.Before)) {
                    Restore-LtActionSnapshot $u.Action $u.Before
                    $chk = Get-LtActionSnapshot $u.Action
                    if (-not (Test-LtSnapshotEqual $u.Action $chk $u.Before)) { throw 'geri alma sonrası değer özgün değerle eşleşmiyor' }
                }
            } catch {
                [void]$undoErrors.Add("$(Get-LtActionTarget $u.Action): $($_.Exception.Message)")
                continue
            }
            try { Add-LtJournalEntry -OperationId $OperationId -Entry @{ t = 'rolledback'; cid = $u.Cid } }
            catch { [void]$recordErrors.Add("journal: $($_.Exception.Message)") }
            # Ledger yazimi basarisiz olduysa (disk/erisim) LedgerAdded hic atanmamis olabilir
            if ($u.ContainsKey('LedgerAdded') -and $u.LedgerAdded) {
                try { Remove-LtLedgerEntry $u.Key }
                catch { [void]$recordErrors.Add("ledger: $($_.Exception.Message)") }
            }
        }
        $recordNote = ''
        if ($recordErrors.Count -gt 0) {
            $recordNote = " Kayıt uyarısı: işlem günlüğü/ledger güncellenemedi ($(@($recordErrors | Select-Object -Unique) -join '; ')); değerler sistemden yeniden okunarak doğrulandı."
        }
        if ($undoErrors.Count -gt 0) {
            return New-LtResult -Id $id -Title $title -Status Failed -Message "$err | GERİ ALMA TAM YAPILAMADI: $($undoErrors -join '; '). Journal: $OperationId.$recordNote" -Details @($details)
        }
        return New-LtResult -Id $id -Title $title -Status Failed -Message "$err | Bu ayarın yaptığı değişiklikler geri alındı.$recordNote" -Details @($details)
    }
    $rk = [string](Get-LtProp $Tweak 'Restart' 'None')
    $msg = "$($done.Count) değişiklik uygulandı ve doğrulandı."
    $rt = Get-LtRestartText $rk
    if ($rt) { $msg += " $rt." }
    return New-LtResult -Id $id -Title $title -Status Success -Message $msg -RestartRequired ($rk -ne 'None') -RestartKind $rk -Details @($details)
}

function Invoke-LtApply {
    <#
      Secili ayarlari uygular. Iptal istegi yalnizca ayarlar ARASINDA degerlendirilir;
      bir ayarin ortasinda yarim birakma yapilmaz.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$TweakIds,
        [Parameter(Mandatory)]$Context,
        $Progress = $null,
        $Cancel = $null
    )
    $results = New-Object System.Collections.ArrayList
    $ids = @($TweakIds | Select-Object -Unique)
    $op = New-LtOperation -Kind Apply -TweakIds $ids
    Write-LtLog "İşlem başladı: $op ($($ids.Count) ayar)" 'RUN'
    $seq = 0
    $groups = @{}
    $i = 0
    foreach ($id in $ids) {
        $t = Get-LtTweak $id
        if (Test-LtCancelRequested $Cancel) {
            [void]$results.Add((New-LtResult -Id $id -Title $t.Title -Status Skipped -Message 'Kullanıcı iptal etti; bu ayara dokunulmadı.'))
            continue
        }
        Update-LtProgress $Progress $i $ids.Count "Uygulanıyor: $($t.Title)"
        $ex = Get-LtProp $t 'Exclusive'
        if ($ex -and $groups.ContainsKey($ex)) {
            $r = New-LtResult -Id $id -Title $t.Title -Status Skipped -Message "Aynı gruptan yalnızca biri uygulanabilir ($($groups[$ex]))."
        } else {
            if ($ex) { $groups[$ex] = $id }
            try {
                $r = Invoke-LtTweakApply -Tweak $t -Context $Context -OperationId $op -Seq ([ref]$seq)
            } catch {
                $r = New-LtResult -Id $id -Title $t.Title -Status Failed -Message "Beklenmeyen hata: $($_.Exception.Message)"
            }
        }
        [void]$results.Add($r)
        Write-LtResultLog $r
        $i++
    }
    Update-LtProgress $Progress $ids.Count $ids.Count 'Tamamlandı'
    $summary = Get-LtResultSummary $results
    $outcome = 'completed'
    if (Test-LtCancelRequested $Cancel) { $outcome = 'cancelled' }
    Complete-LtOperation -OperationId $op -Outcome $outcome -Summary $summary
    Write-LtLog ("İşlem bitti: {0} — başarılı {1}, zaten uygulanmış {2}, atlandı {3}, desteklenmiyor {4}, başarısız {5}" -f $op, $summary.Success, $summary.AlreadyApplied, $summary.Skipped, $summary.NotSupported, $summary.Failed) $(if ($summary.Failed -gt 0) { 'WARN' } else { 'OK' })
    return [pscustomobject]@{ OperationId = $op; Results = @($results); Summary = $summary }
}

function Get-LtResultSummary($Results) {
    $s = @{ Success = 0; AlreadyApplied = 0; Skipped = 0; NotSupported = 0; Failed = 0; Partial = 0; Restart = 0; RestartKinds = @() }
    $kinds = @{}
    foreach ($r in @($Results)) {
        $s[$r.Status]++
        if ($r.RestartRequired) { $s.Restart++; $kinds[$r.RestartKind] = $true }
    }
    $s.RestartKinds = @($kinds.Keys)
    return $s
}

function Write-LtResultLog($r) {
    $lvl = switch ($r.Status) { 'Success' { 'OK' } 'AlreadyApplied' { 'INFO' } 'Skipped' { 'INFO' } 'NotSupported' { 'WARN' } 'Partial' { 'WARN' } default { 'ERROR' } }
    Write-LtLog ("[{0}] {1} — {2}" -f $r.StatusText, $r.Title, $r.Message) $lvl
    foreach ($d in @($r.Details)) { Write-LtLog "    $d" 'DEBUG' }
}

# ---------------------------------------------------------------------------
# GERI ALMA
# ---------------------------------------------------------------------------
function Invoke-LtRevert {
    <#
      -Target Previous : Livn Tools'un kaydettigi ozgun degerlere doner (ledger).
      -Target Default  : Katalogdaki belgelenmis Windows varsayilanina doner.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$TweakIds,
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][ValidateSet('Previous','Default')][string]$Target,
        $Progress = $null,
        $Cancel = $null
    )
    $kind = if ($Target -eq 'Previous') { 'RevertPrevious' } else { 'RevertDefault' }
    $ids = @($TweakIds | Select-Object -Unique)
    $op = New-LtOperation -Kind $kind -TweakIds $ids
    $results = New-Object System.Collections.ArrayList
    $seq = 0; $i = 0
    foreach ($id in $ids) {
        $t = Get-LtTweak $id
        if (Test-LtCancelRequested $Cancel) {
            [void]$results.Add((New-LtResult -Id $id -Title $t.Title -Status Skipped -Message 'Kullanıcı iptal etti.'))
            continue
        }
        Update-LtProgress $Progress $i $ids.Count "Geri alınıyor: $($t.Title)"
        try {
            if ($Target -eq 'Previous') { $r = Invoke-LtTweakRevertPrevious -Tweak $t -OperationId $op -Seq ([ref]$seq) }
            else { $r = Invoke-LtTweakRevertDefault -Tweak $t -Context $Context -OperationId $op -Seq ([ref]$seq) }
        } catch {
            $r = New-LtResult -Id $id -Title $t.Title -Status Failed -Message "Beklenmeyen hata: $($_.Exception.Message)"
        }
        [void]$results.Add($r)
        Write-LtResultLog $r
        $i++
    }
    Update-LtProgress $Progress $ids.Count $ids.Count 'Tamamlandı'
    $summary = Get-LtResultSummary $results
    Complete-LtOperation -OperationId $op -Outcome 'completed' -Summary $summary
    return [pscustomobject]@{ OperationId = $op; Results = @($results); Summary = $summary }
}

function Invoke-LtTweakRevertPrevious {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)][string]$OperationId, [ref]$Seq)
    $id = $Tweak.Id
    # En son kaydedilenden en eskiye: olusturulan ic ice anahtarlar dogru sirada temizlenir
    $entries = @(Get-LtLedgerEntries | Where-Object { @($_.tweakIds) -contains $id } | Sort-Object { [string]$_.time } -Descending)
    if ($entries.Count -eq 0) {
        return New-LtResult -Id $id -Title $Tweak.Title -Status Skipped -Message 'Livn Tools bu ayarı değiştirmemiş; geri yüklenecek önceki değer kaydı yok.'
    }
    $changed = 0; $errors = New-Object System.Collections.ArrayList; $details = New-Object System.Collections.ArrayList
    foreach ($e in $entries) {
        $a = $e.action
        try {
            $cur = Get-LtActionSnapshot $a
            if (Test-LtSnapshotEqual $a $cur $e.original) { Remove-LtLedgerEntry $e.key; continue }
            if ($a.Type -eq 'Mitigation' -and $cur.State -ne $a.State) {
                throw 'Mitigasyon tercihi uygulamadan sonra degismis; mevcut tercih ezilmedi ve geri alma kaydi korundu.'
            }
            $Seq.Value++
            Add-LtJournalEntry -OperationId $OperationId -Entry @{ t = 'change'; cid = $Seq.Value; mode = 'RevertPrevious'; tweak = $id; key = $e.key; action = $a; before = $cur }
            Restore-LtActionSnapshot $a $e.original
            $after = Get-LtActionSnapshot $a
            if (-not (Test-LtSnapshotEqual $a $after $e.original)) {
                throw ("doğrulama başarısız — beklenen {0}, okunan {1}" -f (Format-LtActionState $a $e.original), (Format-LtActionState $a $after))
            }
            Add-LtJournalEntry -OperationId $OperationId -Entry @{ t = 'applied'; cid = $Seq.Value }
            Remove-LtLedgerEntry $e.key
            $changed++
            [void]$details.Add(('{0}: {1} → {2}' -f (Get-LtActionTarget $a), (Format-LtActionState $a $cur), (Format-LtActionState $a $after)))
        } catch {
            [void]$errors.Add("$(Get-LtActionTarget $a): $($_.Exception.Message)")
        }
    }
    $rk = [string](Get-LtProp $Tweak 'Restart' 'None')
    if ($id -in @('input.mouse-accel-off','ui.menu-delay','ui.animations-off') -and @($entries | Where-Object { $_.action.Type -eq 'Registry' }).Count -gt 0) { $rk = 'Logoff' }
    if ($errors.Count -gt 0) {
        return New-LtResult -Id $id -Title $Tweak.Title -Status Failed -Message ("$changed değer geri yüklendi; hatalar: " + ($errors -join '; ')) -Details @($details) -RestartRequired ($changed -gt 0 -and $rk -ne 'None') -RestartKind $rk
    }
    if ($changed -eq 0) {
        return New-LtResult -Id $id -Title $Tweak.Title -Status AlreadyApplied -Message 'Değerler zaten önceki haliyle aynıydı; kayıt kapatıldı.'
    }
    $msg = "$changed değer önceki haline döndürüldü ve doğrulandı."
    $rt = Get-LtRestartText $rk; if ($rt) { $msg += " $rt." }
    return New-LtResult -Id $id -Title $Tweak.Title -Status Success -Message $msg -Details @($details) -RestartRequired ($rk -ne 'None') -RestartKind $rk
}

function Invoke-LtTweakRevertDefault {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$Context, [Parameter(Mandatory)][string]$OperationId, [ref]$Seq)
    $id = $Tweak.Id
    $reason = Get-LtTweakSupport $Tweak $Context
    if ($reason) { return New-LtResult -Id $id -Title $Tweak.Title -Status NotSupported -Message $reason }
    $actions = @(Resolve-LtTweakActions $Tweak $Context)
    $withDefault = @($actions | Where-Object { Test-LtActionHasDefault $_ })
    if ($withDefault.Count -eq 0) {
        return New-LtResult -Id $id -Title $Tweak.Title -Status NotSupported -Message 'Bu ayar için belgelenmiş bir Windows varsayılanı yok; "Önceki ayara dön" kullanın.'
    }
    $changed = 0; $errors = New-Object System.Collections.ArrayList; $details = New-Object System.Collections.ArrayList
    foreach ($a in $withDefault) {
        try {
            $cur = Get-LtActionSnapshot $a
            $def = Get-LtActionDefaultSnapshot $a
            if (Test-LtSnapshotEqual $a $cur $def) { continue }
            $key = Get-LtActionKey $a
            $Seq.Value++
            Add-LtJournalEntry -OperationId $OperationId -Entry @{ t = 'change'; cid = $Seq.Value; mode = 'RevertDefault'; tweak = $id; key = $key; action = $a; before = $cur }
            [void](Add-LtLedgerOriginal -Key $key -Action $a -Snapshot $cur -TweakId $id -OperationId $OperationId)
            Invoke-LtActionDefault $a
            $after = Get-LtActionSnapshot $a
            if (-not (Test-LtSnapshotEqual $a $after $def)) {
                throw ("doğrulama başarısız — beklenen {0}, okunan {1}" -f (Format-LtActionState $a $def), (Format-LtActionState $a $after))
            }
            Add-LtJournalEntry -OperationId $OperationId -Entry @{ t = 'applied'; cid = $Seq.Value }
            $changed++
            [void]$details.Add(('{0}: {1} → {2}' -f (Get-LtActionTarget $a), (Format-LtActionState $a $cur), (Format-LtActionState $a $after)))
        } catch {
            [void]$errors.Add("$(Get-LtActionTarget $a): $($_.Exception.Message)")
        }
    }
    $skippedNoDefault = $actions.Count - $withDefault.Count
    $rk = [string](Get-LtProp $Tweak 'Restart' 'None')
    $note = ''
    if ($skippedNoDefault -gt 0) { $note = " ($skippedNoDefault değerin Windows varsayılanı tanımsız, dokunulmadı.)" }
    if ($errors.Count -gt 0) {
        return New-LtResult -Id $id -Title $Tweak.Title -Status Failed -Message ("$changed değer varsayılana döndü; hatalar: " + ($errors -join '; ') + $note) -Details @($details)
    }
    if ($changed -eq 0) { return New-LtResult -Id $id -Title $Tweak.Title -Status AlreadyApplied -Message ('Zaten Windows varsayılanında.' + $note) }
    $msg = "$changed değer Windows varsayılanına döndürüldü ve doğrulandı.$note"
    $rt = Get-LtRestartText $rk; if ($rt) { $msg += " $rt." }
    return New-LtResult -Id $id -Title $Tweak.Title -Status Success -Message $msg -Details @($details) -RestartRequired ($rk -ne 'None') -RestartKind $rk
}

# ---------------------------------------------------------------------------
# KURTARMA (uygulama kapanmis / guc kesilmis / islem yarim kalmis)
# ---------------------------------------------------------------------------
function Invoke-LtRecovery {
    <#
      -Mode Revert : yarim islemde degisen her hedefi islem ONCESI durumuna dondurur.
      -Mode Keep   : degisiklikleri oldugu gibi birakir, islemi kapatir
                     (ozgun degerler ledger'da kalir; sonra "Onceki ayara don" kullanilabilir).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$OperationId, [Parameter(Mandatory)][ValidateSet('Revert','Keep')][string]$Mode)
    $entries = @(Read-LtJournal $OperationId)
    if (@($entries | Where-Object { $_.t -eq 'end' }).Count -gt 0) { throw "İşlem zaten kapatılmış: $OperationId" }
    if ($Mode -eq 'Keep') {
        Complete-LtOperation -OperationId $OperationId -Outcome 'recovered-kept'
        Write-LtLog "Yarım işlem olduğu gibi bırakıldı ve kapatıldı: $OperationId" 'WARN'
        return @()
    }
    $rolled = @{}
    foreach ($e in $entries) { if ($e.t -eq 'rolledback') { $rolled[[string]$e.cid] = $true } }
    # Her hedef icin islemdeki ILK 'once' goruntusu (islem oncesi durum)
    $firstByKey = [ordered]@{}
    foreach ($e in ($entries | Where-Object { $_.t -eq 'change' })) {
        if ($rolled.ContainsKey([string]$e.cid)) { continue }
        if (-not $firstByKey.Contains($e.key)) { $firstByKey[$e.key] = $e }
    }
    $results = New-Object System.Collections.ArrayList
    $keys = @($firstByKey.Keys); [array]::Reverse($keys)
    foreach ($k in $keys) {
        $e = $firstByKey[$k]
        $a = $e.action
        try {
            $cur = Get-LtActionSnapshot $a
            if (-not (Test-LtSnapshotEqual $a $cur $e.before)) {
                Restore-LtActionSnapshot $a $e.before
                $after = Get-LtActionSnapshot $a
                if (-not (Test-LtSnapshotEqual $a $after $e.before)) { throw 'geri yükleme doğrulanamadı' }
            }
            Add-LtJournalEntry -OperationId $OperationId -Entry @{ t = 'recovery-restored'; key = $k }
            $le = Get-LtLedgerEntry $k
            if ($le -and $le.opId -eq $OperationId) { Remove-LtLedgerEntry $k }
            [void]$results.Add((New-LtResult -Id $e.tweak -Title (Get-LtActionTarget $a) -Status Success -Message 'İşlem öncesi değere döndürüldü.'))
        } catch {
            [void]$results.Add((New-LtResult -Id $e.tweak -Title (Get-LtActionTarget $a) -Status Failed -Message $_.Exception.Message))
        }
    }
    $sum = Get-LtResultSummary $results
    Complete-LtOperation -OperationId $OperationId -Outcome 'recovered-reverted' -Summary $sum
    foreach ($r in $results) { Write-LtResultLog $r }
    return @($results)
}

# ---------------------------------------------------------------------------
# DURUM YEDEGI (eski ".reg Backup" butonunun yerine; eksik degerleri de kapsar)
# ---------------------------------------------------------------------------
function Export-LtStateBackup {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$TweakIds, [Parameter(Mandatory)]$Context, [string]$Label = 'yedek')
    $items = New-Object System.Collections.ArrayList
    $skipped = 0
    foreach ($id in $TweakIds) {
        $t = Get-LtTweak $id
        if (Get-LtTweakSupport $t $Context) { $skipped++; continue }
        try {
            foreach ($a in @(Resolve-LtTweakActions $t $Context)) {
                $s = Get-LtActionSnapshot $a
                if ($a.Type -eq 'Service' -and -not $s.Exists) { continue }
                [void]$items.Add(@{ tweak = $id; key = (Get-LtActionKey $a); action = $a; snapshot = $s })
            }
        } catch { $skipped++; Write-LtLog "Yedek: $id okunamadı: $($_.Exception.Message)" 'WARN' }
    }
    $safe = ($Label -replace '[^A-Za-z0-9_-]', '_')
    $path = Join-Path (Join-Path (Get-LtDataRoot) 'backups') ("{0}_{1}.json" -f $safe, (Get-Date -Format 'yyyyMMdd_HHmmss'))
    $doc = @{ format = 'livntools-state-backup'; version = 1; created = (Get-Date).ToString('o'); machine = [Environment]::MachineName; user = [Environment]::UserName; items = @($items) }
    Write-LtFileAtomic -Path $path -Content (ConvertTo-Json -InputObject $doc -Depth 14)
    Write-LtLog "Durum yedeği yazıldı: $path ($($items.Count) değer, $skipped ayar atlandı)" 'OK'
    return [pscustomobject]@{ Path = $path; Count = $items.Count; Skipped = $skipped }
}

function Restore-LtStateBackup {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, $Progress = $null, $Cancel = $null)
    $doc = ConvertTo-LtHashtable (ConvertFrom-Json ([System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)))
    if ($doc.format -ne 'livntools-state-backup') { throw 'Bu dosya bir Livn Tools durum yedeği değil.' }
    $op = New-LtOperation -Kind RestoreBackup -Note $Path
    $results = New-Object System.Collections.ArrayList
    $seq = 0; $i = 0; $n = @($doc.items).Count
    foreach ($it in @($doc.items)) {
        if (Test-LtCancelRequested $Cancel) { [void]$results.Add((New-LtResult -Id $it.tweak -Title $it.key -Status Skipped -Message 'Kullanıcı iptal etti.')); continue }
        Update-LtProgress $Progress $i $n "Yedekten: $($it.key)"
        $a = $it.action
        try {
            $cur = Get-LtActionSnapshot $a
            if (Test-LtSnapshotEqual $a $cur $it.snapshot) {
                [void]$results.Add((New-LtResult -Id $it.tweak -Title (Get-LtActionTarget $a) -Status AlreadyApplied -Message 'Yedekteki değerle aynı.'))
            } else {
                $seq++
                Add-LtJournalEntry -OperationId $op -Entry @{ t = 'change'; cid = $seq; mode = 'RestoreBackup'; tweak = $it.tweak; key = $it.key; action = $a; before = $cur }
                [void](Add-LtLedgerOriginal -Key $it.key -Action $a -Snapshot $cur -TweakId $it.tweak -OperationId $op)
                Restore-LtActionSnapshot $a $it.snapshot
                $after = Get-LtActionSnapshot $a
                if (-not (Test-LtSnapshotEqual $a $after $it.snapshot)) { throw 'geri yükleme doğrulanamadı' }
                Add-LtJournalEntry -OperationId $op -Entry @{ t = 'applied'; cid = $seq }
                [void]$results.Add((New-LtResult -Id $it.tweak -Title (Get-LtActionTarget $a) -Status Success -Message ('{0} → {1}' -f (Format-LtActionState $a $cur), (Format-LtActionState $a $after))))
            }
        } catch {
            [void]$results.Add((New-LtResult -Id $it.tweak -Title $it.key -Status Failed -Message $_.Exception.Message))
        }
        $i++
    }
    $sum = Get-LtResultSummary $results
    Complete-LtOperation -OperationId $op -Outcome 'completed' -Summary $sum
    foreach ($r in $results) { Write-LtResultLog $r }
    return [pscustomobject]@{ OperationId = $op; Results = @($results); Summary = $sum }
}
