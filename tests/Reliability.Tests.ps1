#Requires -Modules Pester
# r3 bağımsız denetim bulguları için regresyon testleri:
# - Write-LtFileAtomic: PowerShell $null -> "" dönüşümü yüzünden File.Replace hiç çalışmıyordu;
#   geri dönüş yolunda ikinci taşıma başarısız olursa ledger.json kayboluyordu.
# - Invoke-LtTweakApply: hata bloğunda journal yazımı da başarısız olursa geri sarma hiç
#   çalışmıyor, önceki eylemler sistemde kalıyordu ("Beklenmeyen hata").
# - Önceki ayara dönüş önizlemesi, Livn'den sonra değişmiş değeri ayrıca belirtmiyordu.

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
}

Describe 'Atomik dosya yazımı ve ledger dayanıklılığı' {
    BeforeEach { $sys = New-LtTestSystem }
    AfterEach { Remove-LtTestSystem $sys }

    It 'Var olan dosya File.Replace ile değiştirilir; geri dönüş yolu (Move-Item) kullanılmaz' {
        $p = Join-Path $sys.Root 'state/atomik.json'
        Write-LtFileAtomic -Path $p -Content 'eski'
        Mock -ModuleName LivnTools -CommandName Move-Item -MockWith { throw 'geri dönüş yolu kullanıldı' }
        Write-LtFileAtomic -Path $p -Content 'yeni'
        [IO.File]::ReadAllText($p) | Should -Be 'yeni'
        Should -Invoke -ModuleName LivnTools -CommandName Move-Item -Times 0 -Exactly
        @(Get-ChildItem -LiteralPath (Split-Path -Parent $p) | Where-Object { $_.Name -ne 'atomik.json' -and $_.Name -like 'atomik.json*' }).Count | Should -Be 0
    }

    It 'Replace yapılamaz ve ikinci taşıma başarısız olursa özgün dosya geri konur' {
        $p = Join-Path $sys.Root 'state/atomik.json'
        Write-LtFileAtomic -Path $p -Content 'ozgun'
        Mock -ModuleName LivnTools -CommandName Invoke-LtFileReplace -MockWith { throw 'Replace desteklenmiyor' }
        $script:moves = 0
        Mock -ModuleName LivnTools -CommandName Move-Item -MockWith {
            $script:moves++
            if ($script:moves -eq 2) { throw 'AV kilidi' }
            Microsoft.PowerShell.Management\Move-Item -LiteralPath $LiteralPath -Destination $Destination -Force
        }
        { Write-LtFileAtomic -Path $p -Content 'yeni' } | Should -Throw '*AV kilidi*'
        [IO.File]::ReadAllText($p) | Should -Be 'ozgun'
        Test-Path -LiteralPath "$p.bak" | Should -BeFalse
        @(Get-ChildItem -LiteralPath (Split-Path -Parent $p) | Where-Object { $_.Name -like 'atomik.json.tmp-*' }).Count | Should -Be 0
    }

    It 'Yarıda kalmış yazımdan kalan ledger.json.bak okunurken kurtarılır (özgün değerler kaybolmaz)' {
        [void](Invoke-LtApply -TweakIds 'game.mode' -Context $sys.Ctx)
        $p = Get-LtLedgerPath
        Move-Item -LiteralPath $p -Destination "$p.bak"
        @(Get-LtLedgerEntries).Count | Should -Be 1
        Test-Path -LiteralPath $p | Should -BeTrue
        (Invoke-LtRevert -TweakIds 'game.mode' -Context $sys.Ctx -Target Previous).Results[0].Status | Should -Be 'Success'
    }
}

Describe 'Uygulama hatasında günlük/ledger yazılamazsa geri sarma' {
    BeforeEach { $sys = New-LtTestSystem }
    AfterEach { Remove-LtTestSystem $sys }

    It 'İkinci eylemin günlüğü yazılamazsa birinci eylem yine geri alınır ve doğru raporlanır' {
        $actions = @(Resolve-LtTweakActions (Get-LtTweak 'priv.activity-off') $sys.Ctx)
        $actions.Count | Should -BeGreaterThan 1
        $before = Get-LtActionSnapshot $actions[0]
        Mock -ModuleName LivnTools -CommandName Add-LtJournalEntry -ParameterFilter { $Entry.t -in @('failed', 'rolledback') -or ($Entry.t -eq 'change' -and $Entry.cid -ge 2) } -MockWith { throw 'Disk dolu' }
        $r = (Invoke-LtApply -TweakIds 'priv.activity-off' -Context $sys.Ctx).Results[0]
        $r.Status | Should -Be 'Failed'
        $r.Message | Should -Not -Match 'Beklenmeyen hata'
        $r.Message | Should -Match 'geri alındı'
        $r.Message | Should -Match 'Kayıt uyarısı'
        Test-LtSnapshotEqual $actions[0] (Get-LtActionSnapshot $actions[0]) $before | Should -BeTrue
        @(Get-LtLedgerEntries).Count | Should -Be 0
    }

    It 'Hiç uygulanmamış eylem için geri sarma sisteme yazmaz' {
        Mock -ModuleName LivnTools -CommandName Add-LtJournalEntry -ParameterFilter { $Entry.t -eq 'change' } -MockWith { throw 'Disk dolu' }
        $sys.Mem.Calls.Clear()
        $r = (Invoke-LtApply -TweakIds 'game.mode' -Context $sys.Ctx).Results[0]
        $r.Status | Should -Be 'Failed'
        $r.Message | Should -Not -Match 'TAM YAPILAMADI'
        @($sys.Mem.Calls | Where-Object { $_ -like 'Registry.Set*' -or $_ -like 'Registry.Delete*' -or $_ -like 'Registry.CreateKey*' }).Count | Should -Be 0
    }
}

Describe 'Uygulamadan sonra değişen değer ve önceki ayara dönüş' {
    BeforeEach { $sys = New-LtTestSystem }
    AfterEach { Remove-LtTestSystem $sys }

    It 'Önizleme sonradan değişmiş değeri açıkça işaretler' {
        [void](Invoke-LtApply -TweakIds 'game.mode' -Context $sys.Ctx)
        $a = @(Resolve-LtTweakActions (Get-LtTweak 'game.mode') $sys.Ctx)[0]
        [void](Set-LtRegValue -Path $a.Path -Name $a.Name -Kind DWord -Data 7)
        $plan = @(Get-LtPlan -TweakIds 'game.mode' -Context $sys.Ctx -Mode RevertPrevious)[0]
        $plan.Outcome | Should -Be 'WillChange'
        $plan.Changes[0].Drifted | Should -BeTrue
        $plan.Changes[0].From | Should -Match 'sonra değişmiş'
        $plan.Message | Should -Match 'özgün değerle değiştirilir'
    }

    It 'Değişmemiş değer için uyarı gösterilmez' {
        [void](Invoke-LtApply -TweakIds 'game.mode' -Context $sys.Ctx)
        $plan = @(Get-LtPlan -TweakIds 'game.mode' -Context $sys.Ctx -Mode RevertPrevious)[0]
        $plan.Changes[0].Drifted | Should -BeFalse
        $plan.Message | Should -BeNullOrEmpty
    }
}

Describe 'Temizlik boyut raporu: ölçülmeyen boyut 0 B gösterilmez' {
    BeforeEach { $sys = New-LtTestSystem; Set-LtCleanupTestRoot $sys.Root }
    AfterEach { Set-LtCleanupTestRoot $null; Remove-LtTestSystem $sys }

    It 'Kullanıcı senaryosu: Gelişmiş Temizlik (DISM x3, SFC, Disk Temizleme, USB) "toplam 0 B silindi" demez' {
        # Gerçek komut çalıştırılmaz: sahte çıkış kodu 0, sahte boş alan, sahte bağlı olmayan USB aygıtı
        Mock -ModuleName LivnTools -CommandName Invoke-LtNative -MockWith { [pscustomobject]@{ ExitCode = 0; StdOut = 'The operation completed successfully.'; StdErr = ''; TimedOut = $false; Command = 'fake' } }
        Mock -ModuleName LivnTools -CommandName Start-LtProcessAndWait -MockWith { @{ Exited = $true; ExitCode = 0 } }
        Mock -ModuleName LivnTools -CommandName Get-LtSystemDriveFreeBytes -MockWith { [long]100GB }
        Mock -ModuleName LivnTools -CommandName Get-LtGhostUsbStorage -MockWith { @([pscustomobject]@{ InstanceId = 'USBSTOR\FAKE' }) }
        $ids = @('adv.dism-restore', 'adv.component-resetbase', 'adv.sfc', 'adv.cleanmgr', 'adv.usb-ghosts', 'adv.component-cleanup')
        $r = Invoke-LtCleanup -Ids $ids -Context $sys.Ctx
        @($r.Results | Where-Object Status -ne 'Success').Count | Should -Be 0
        foreach ($id in @('adv.dism-restore', 'adv.component-resetbase', 'adv.sfc', 'adv.usb-ghosts', 'adv.component-cleanup')) {
            ($r.Results | Where-Object Id -eq $id).SizeMeasured | Should -BeFalse -Because $id
        }
        ($r.Results | Where-Object Id -eq 'adv.component-cleanup').Message | Should -Match 'ölçülmedi'
        ($r.Results | Where-Object Id -eq 'adv.cleanmgr').SizeMeasured | Should -BeTrue
        ($r.Results | Where-Object Id -eq 'adv.cleanmgr').Message | Should -Match 'ölçülebilir artış olmadı'
        $r.TotalText | Should -Match '5 işlemin açtığı alan ölçülmedi'
        $r.TotalText | Should -Not -Match '^toplam 0 B'
    }

    It 'Yalnız ölçülmeyen işlemler: sayı uydurulmaz' {
        $rs = @((New-LtResult -Id a -Title 'DISM' -Status Success), (New-LtResult -Id b -Title 'SFC' -Status Success))
        $t = Get-LtCleanupTotalText -Results $rs
        $t | Should -Match 'boyut ölçülmedi'
        $t | Should -Not -Match '0 B'
    }

    It 'Ölçülen ve ölçülmeyen karışık; kuru çalışma ve atlananlar sayılmaz' {
        $rs = @((New-LtResult -Id a -Title 'Temp' -Status Success -BytesFreed 2048 -SizeMeasured $true),
                (New-LtResult -Id b -Title 'DISM' -Status Success),
                (New-LtResult -Id c -Title 'Chrome' -Status Skipped -SizeMeasured $true),
                (New-LtResult -Id d -Title 'Sim' -Status Skipped -Simulated $true))
        $t = Get-LtCleanupTotalText -Results $rs
        $t | Should -Match 'ölçülen toplam 2 KB \(1 öğe\)'
        $t | Should -Match '1 işlemin açtığı alan ölçülmedi \(DISM\)'
        Get-LtCleanupTotalText -Results @($rs[0]) | Should -Not -Match 'ölçülmedi'
    }

    It 'Dosya hedefli öğe ölçülmüş, ölçüm bildirmeyen Run ölçülmemiş sayılır' {
        $c = Join-Path $sys.Root 'cache'; [void](New-Item -ItemType Directory -Path $c)
        [IO.File]::WriteAllText((Join-Path $c 'a.tmp'), 'xxxx')
        $files = @{ Id = 't.f'; Title = 'f'; Paths = [scriptblock]::Create("@(@{ Path = '$c'; Label = 'c' })") }
        (Invoke-LtCleanupItem -Item $files -Context $sys.Ctx).SizeMeasured | Should -BeTrue
        $maint = @{ Id = 't.m'; Title = 'm'; Run = { param($ctx, $cancel) @{ Bytes = 0; Message = 'bakım' } } }
        (Invoke-LtCleanupItem -Item $maint -Context $sys.Ctx).SizeMeasured | Should -BeFalse
        $meas = @{ Id = 't.r'; Title = 'r'; Run = { param($ctx, $cancel) @{ Bytes = 10; Measured = $true; Message = 'ölçüldü' } } }
        (Invoke-LtCleanupItem -Item $meas -Context $sys.Ctx).SizeMeasured | Should -BeTrue
    }
}
