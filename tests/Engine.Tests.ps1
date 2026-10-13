#Requires -Modules Pester
# Uygula -> dogrula -> geri al, eksik registry degeri, basarisiz komut,
# yinelenen uygulama, kismi hata geri sarma, journal kurtarma.

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
}

Describe 'Registry ayari: uygula / dogrula / geri al' {
    BeforeEach { $sys = New-LtTestSystem }
    AfterEach { Remove-LtTestSystem $sys }

    It 'Onceden OLMAYAN degeri uygular, sonra "onceki ayar" ile degeri ve olusturulan anahtarlari siler' {
        $key = 'HKCU\Software\Microsoft\GameBar'
        (Test-LtRegKey $key) | Should -BeFalse
        $hadParent = Test-LtRegKey 'HKCU\Software\Microsoft'
        $r = Invoke-LtApply -TweakIds 'game.mode' -Context $sys.Ctx
        $r.Results[0].Status | Should -Be 'Success'
        (Get-LtRegValue $key 'AutoGameModeEnabled').Data | Should -Be 1

        $rv = Invoke-LtRevert -TweakIds 'game.mode' -Context $sys.Ctx -Target Previous
        $rv.Results[0].Status | Should -Be 'Success'
        (Get-LtRegValue $key 'AutoGameModeEnabled').Exists | Should -BeFalse
        (Test-LtRegKey $key) | Should -BeFalse -Because 'Livn Tools tarafindan olusturulan bos anahtar da kaldirilmali'
        (Test-LtRegKey 'HKCU\Software\Microsoft') | Should -Be $hadParent -Because 'önceden var olan üst anahtar silinmemeli; Livn oluşturduysa kaldırılmalı'
    }

    It 'Farkli TURDEKI mevcut degeri (REG_SZ) birebir geri yukler' {
        $k = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
        [void](Set-LtRegValue $k 'NetworkThrottlingIndex' -Kind String -Data '10')
        (Invoke-LtApply -TweakIds 'net.throttling-off' -Context $sys.Ctx).Results[0].Status | Should -Be 'Success'
        $v = Get-LtRegValue $k 'NetworkThrottlingIndex'
        $v.Kind | Should -Be 'DWord'
        $v.Data | Should -Be 4294967295
        (Invoke-LtRevert -TweakIds 'net.throttling-off' -Context $sys.Ctx -Target Previous).Results[0].Status | Should -Be 'Success'
        $v2 = Get-LtRegValue $k 'NetworkThrottlingIndex'
        $v2.Kind | Should -Be 'String'
        $v2.Data | Should -Be '10'
    }

    It 'Tekrar uygulama degisiklik yapmaz ve ozgun degeri EZMEZ' {
        $k = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
        [void](Set-LtRegValue $k 'SystemResponsiveness' -Kind DWord -Data 20)
        (Invoke-LtApply -TweakIds 'sched.mmcss-games' -Context $sys.Ctx).Results[0].Status | Should -Be 'Success'
        $callsBefore = $sys.Mem.Calls.Count
        $r2 = Invoke-LtApply -TweakIds 'sched.mmcss-games' -Context $sys.Ctx
        $r2.Results[0].Status | Should -Be 'AlreadyApplied'
        @($sys.Mem.Calls | Select-Object -Skip $callsBefore | Where-Object { $_ -like 'Registry.Set*' }).Count | Should -Be 0
        $entries = Read-LtJournal $r2.OperationId
        @($entries | Where-Object { $_.t -eq 'change' }).Count | Should -Be 0
        (Get-LtLedgerEntry "Registry|$k|SystemResponsiveness").original.Data | Should -Be 20
    }

    It 'Windows varsayilanina donus, kullanicinin onceki degerinden farkli olabilir' {
        $k = 'HKLM\SYSTEM\CurrentControlSet\Control\PriorityControl'
        [void](Set-LtRegValue $k 'Win32PrioritySeparation' -Kind DWord -Data 0x28)   # kullanicinin ozel degeri
        (Invoke-LtApply -TweakIds 'sched.win32prio-14' -Context $sys.Ctx).Results[0].Status | Should -Be 'Success'
        (Invoke-LtRevert -TweakIds 'sched.win32prio-14' -Context $sys.Ctx -Target Default).Results[0].Status | Should -Be 'Success'
        (Get-LtRegValue $k 'Win32PrioritySeparation').Data | Should -Be 2
        # Varsayilandan sonra "onceki ayar" hala kullanicinin ozgun degerine doner
        (Invoke-LtRevert -TweakIds 'sched.win32prio-14' -Context $sys.Ctx -Target Previous).Results[0].Status | Should -Be 'Success'
        (Get-LtRegValue $k 'Win32PrioritySeparation').Data | Should -Be 0x28
    }

    It 'Varsayilani tanimsiz ayar icin "Windows varsayilani" Desteklenmiyor dondurur' {
        (Invoke-LtApply -TweakIds 'priv.adid-off' -Context $sys.Ctx).Results[0].Status | Should -Be 'Success'
        (Invoke-LtRevert -TweakIds 'priv.adid-off' -Context $sys.Ctx -Target Default).Results[0].Status | Should -Be 'NotSupported'
    }

    It 'Degistirilmemis ayar icin "onceki ayar" Atlandi dondurur' {
        (Invoke-LtRevert -TweakIds 'ui.darkmode' -Context $sys.Ctx -Target Previous).Results[0].Status | Should -Be 'Skipped'
    }
}

Describe 'Hata isleme ve geri sarma' {
    BeforeEach { $sys = New-LtTestSystem }
    AfterEach { Remove-LtTestSystem $sys }

    It 'Coklu eylemde ikinci eylem basarisiz olursa birinci geri alinir' {
        $k = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
        $sys.Mem.Faults["Registry.Set:$k|SystemUsesLightTheme"] = 'Erişim reddedildi'
        $r = Invoke-LtApply -TweakIds 'ui.darkmode' -Context $sys.Ctx
        $r.Results[0].Status | Should -Be 'Failed'
        $r.Results[0].Message | Should -Match 'Erişim reddedildi'
        $r.Results[0].Message | Should -Match 'geri alındı'
        (Get-LtRegValue $k 'AppsUseLightTheme').Exists | Should -BeFalse
        @(Get-LtLedgerEntries).Count | Should -Be 0 -Because 'geri alinan degisikligin ozgun kaydi silinmeli'
        $j = Read-LtJournal $r.OperationId
        @($j | Where-Object { $_.t -eq 'rolledback' }).Count | Should -BeGreaterThan 0
        @($j | Where-Object { $_.t -eq 'end' }).Count | Should -Be 1
    }

    It 'Ledger yazimi basarisiz olursa degisiklik yapilmaz ve sonuc dogru raporlanir (yanlis "geri alma tam yapilamadi" yok)' {
        Mock -ModuleName LivnTools -CommandName Add-LtLedgerOriginal -MockWith { throw 'Disk dolu' }
        $r = Invoke-LtApply -TweakIds 'game.mode' -Context $sys.Ctx
        $r.Results[0].Status | Should -Be 'Failed'
        $r.Results[0].Message | Should -Match 'Disk dolu'
        $r.Results[0].Message | Should -Match 'geri alındı'
        $r.Results[0].Message | Should -Not -Match 'TAM YAPILAMADI'
        (Get-LtRegValue 'HKCU\Software\Microsoft\GameBar' 'AutoGameModeEnabled').Exists | Should -BeFalse
    }

    It 'Komut basarili gorunup degisiklik yapmazsa dogrulama yakalar (sahte basari yok)' {
        $sys.Ctx.MenuDelayMs = 0
        $sys.Mem.NoOps['UserParameter.Set:MenuDelay'] = $true
        $r = Invoke-LtApply -TweakIds 'ui.menu-delay' -Context $sys.Ctx
        $r.Results[0].Status | Should -Be 'Failed'
        $r.Results[0].Message | Should -Match 'Doğrulama başarısız'
    }

    It 'Servis erisim hatasi Basarisiz olarak raporlanir; diger ayarlar calismaya devam eder' {
        $sys.Mem.Faults['Service.SetStartType:DiagTrack'] = 'sc.exe: Erişim reddedildi (5)'
        $r = Invoke-LtApply -TweakIds @('priv.diagtrack-off', 'ui.show-ext') -Context $sys.Ctx
        ($r.Results | Where-Object Id -eq 'priv.diagtrack-off').Status | Should -Be 'Failed'
        ($r.Results | Where-Object Id -eq 'ui.show-ext').Status | Should -Be 'Success'
        $r.Summary.Failed | Should -Be 1
        (Get-LtServiceInfo 'DiagTrack').StartType | Should -Be 'Automatic'
    }

    It 'Servisi kapatir, durdurur; geri alinca baslangic turunu ve calisma durumunu geri getirir' {
        (Invoke-LtApply -TweakIds 'svc.wsearch-off' -Context $sys.Ctx).Results[0].Status | Should -Be 'Success'
        $i = Get-LtServiceInfo 'WSearch'
        $i.StartType | Should -Be 'Disabled'; $i.Status | Should -Be 'Stopped'
        (Invoke-LtRevert -TweakIds 'svc.wsearch-off' -Context $sys.Ctx -Target Previous).Results[0].Status | Should -Be 'Success'
        $i2 = Get-LtServiceInfo 'WSearch'
        $i2.StartType | Should -Be 'AutomaticDelayed'; $i2.Status | Should -Be 'Running'
    }

    It 'Olmayan servis Desteklenmiyor olur' {
        $sys.Mem.Registry.Remove('hklm\system\currentcontrolset\services\sysmain')
        (Invoke-LtApply -TweakIds 'svc.sysmain-off' -Context $sys.Ctx).Results[0].Status | Should -Be 'NotSupported'
    }

    It 'Destek kosulu saglanmayan ayar Desteklenmiyor ve nedeni ile doner' {
        $homeSys = New-LtTestSystem -Edition 'Core'
        try {
            $r = Invoke-LtApply -TweakIds 'wu.defer' -Context $homeSys.Ctx
            $r.Results[0].Status | Should -Be 'NotSupported'
            $r.Results[0].Message | Should -Match 'Home'
        } finally { Remove-LtTestSystem $homeSys }
    }

    It 'Iptal istegi ayarlar arasinda uygulanir; kalanlar Atlandi olur' {
        $cancel = [hashtable]::Synchronized(@{ Requested = $true })
        $r = Invoke-LtApply -TweakIds @('ui.show-ext', 'ui.darkmode') -Context $sys.Ctx -Cancel $cancel
        @($r.Results | Where-Object Status -eq 'Skipped').Count | Should -Be 2
        (Get-LtRegValue 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'HideFileExt').Exists | Should -BeFalse
    }

    It 'Ayni ozel gruptan iki secenek: ikincisi Atlandi' {
        $r = Invoke-LtApply -TweakIds @('sched.win32prio-14', 'sched.win32prio-18') -Context $sys.Ctx
        ($r.Results | Where-Object Id -eq 'sched.win32prio-18').Status | Should -Be 'Skipped'
        (Get-LtRegValue 'HKLM\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation').Data | Should -Be 0x14
    }
}

Describe 'Guc plani: yinelenen plan olusturmaz' {
    BeforeEach { $sys = New-LtTestSystem }
    AfterEach { Remove-LtTestSystem $sys }

    It 'Ultimate iki kez uygulandiginda tek kopya olusur; geri alma onceki planı etkinlestirir' {
        $before = @(Get-LtPowerSchemes).Count
        (Invoke-LtApply -TweakIds 'power.ultimate' -Context $sys.Ctx).Results[0].Status | Should -Be 'Success'
        (Invoke-LtApply -TweakIds 'power.balanced' -Context $sys.Ctx).Results[0].Status | Should -Be 'Success'
        (Invoke-LtApply -TweakIds 'power.ultimate' -Context $sys.Ctx).Results[0].Status | Should -Be 'Success'
        @(Get-LtPowerSchemes).Count | Should -Be ($before + 1)
        @($sys.Mem.Calls | Where-Object { $_ -like 'Power.Duplicate*' }).Count | Should -Be 1
        (Invoke-LtRevert -TweakIds 'power.ultimate' -Context $sys.Ctx -Target Previous).Results[0].Status | Should -Be 'Success'
        Get-LtActivePowerScheme | Should -Be '381b4222-f694-41f0-9685-ff5bb260df2e'
    }

    It '.pow iceren planlar sabit GUID ile bir kez ice aktarilir' {
        $sys.Ctx.AppRoot = New-LtThirdPartyFixture -Root $sys.Root
        (Invoke-LtApply -TweakIds 'power.bitsum' -Context $sys.Ctx).Results[0].Status | Should -Be 'Success'
        (Invoke-LtApply -TweakIds 'power.balanced' -Context $sys.Ctx).Results[0].Status | Should -Be 'Success'
        (Invoke-LtApply -TweakIds 'power.bitsum' -Context $sys.Ctx).Results[0].Status | Should -Be 'Success'
        @($sys.Mem.Calls | Where-Object { $_ -like 'Power.Import*' }).Count | Should -Be 1
    }

    It 'Sistemde olmayan yerlesik plan Desteklenmiyor olur' {
        $sys.Ctx.PowerSchemes = @('381b4222-f694-41f0-9685-ff5bb260df2e')
        (Invoke-LtApply -TweakIds 'power.highperf' -Context $sys.Ctx).Results[0].Status | Should -Be 'NotSupported'
    }
}

Describe 'BCD, NIC, mitigasyon, gorev saglayicilari' {
    BeforeEach { $sys = New-LtTestSystem }
    AfterEach { Remove-LtTestSystem $sys }

    It 'Zorlanmis useplatformclock silinir, geri alinca Yes olarak geri gelir' {
        Get-LtBcdElement 'useplatformclock' | Should -Be 'Yes'
        (Invoke-LtApply -TweakIds 'timer.platformclock-default' -Context $sys.Ctx).Results[0].Status | Should -Be 'Success'
        Get-LtBcdElement 'useplatformclock' | Should -Be 'Absent'
        (Invoke-LtRevert -TweakIds 'timer.platformclock-default' -Context $sys.Ctx -Target Previous).Results[0].Status | Should -Be 'Success'
        Get-LtBcdElement 'useplatformclock' | Should -Be 'Yes'
    }

    It 'NIC: gecerli degeri kabul eden adaptorde uygular; gecersiz degerde eylem uretmez' {
        $sys.Ctx.SelectedNicGuid = $sys.Ctx.Nics[0].InterfaceGuid
        (Invoke-LtApply -TweakIds 'nic.flowcontrol-off' -Context $sys.Ctx).Results[0].Status | Should -Be 'Success'
        (Get-LtNicProperty 'Ethernet' '*FlowControl').Value | Should -Be '0'
        (Invoke-LtApply -TweakIds 'nic.adaptiveifs-off' -Context $sys.Ctx).Results[0].Status | Should -Be 'NotSupported'
        (Invoke-LtRevert -TweakIds 'nic.flowcontrol-off' -Context $sys.Ctx -Target Previous).Results[0].Status | Should -Be 'Success'
        (Get-LtNicProperty 'Ethernet' '*FlowControl').Value | Should -Be '3'
    }

    It 'CFG: geri alma sonradan degisen diger mitigasyon bitlerini korur' {
        $raw = [Convert]::ToBase64String([byte[]](0, 1, 0, 0, 0, 0, 0, 0, 9, 9, 9, 9))
        [void](Set-LtRegValue 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' 'MitigationOptions' -Kind Binary -Data $raw)
        Get-LtSystemMitigation 'CFG' | Should -Be 'NOTSET'
        (Invoke-LtApply -TweakIds 'sec.cfg-off' -Context $sys.Ctx).Results[0].Status | Should -Be 'Success'
        Get-LtSystemMitigation 'CFG' | Should -Be 'OFF'
        $key = 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel'
        $changed = [Convert]::FromBase64String((Get-LtRegValue $key 'MitigationOptions').Data)
        $changed[0] = 17
        $changed[5] = [byte](0xA0 -bor 2)
        [void](Set-LtRegValue $key 'MitigationOptions' -Kind Binary -Data ([Convert]::ToBase64String($changed)))
        (Invoke-LtRevert -TweakIds 'sec.cfg-off' -Context $sys.Ctx -Target Previous).Results[0].Status | Should -Be 'Success'
        Get-LtSystemMitigation 'CFG' | Should -Be 'NOTSET'
        $changed[5] = 0xA0
        (Get-LtRegValue $key 'MitigationOptions').Data | Should -Be ([Convert]::ToBase64String($changed))
    }

    It 'CFG previous restore rejects a conflicting later CFG preference' {
        [void](Invoke-LtApply -TweakIds 'sec.cfg-off' -Context $sys.Ctx)
        Set-LtSystemMitigation CFG ON
        (Invoke-LtRevert -TweakIds 'sec.cfg-off' -Context $sys.Ctx -Target Previous).Results[0].Status | Should -Be 'Failed'
        Get-LtSystemMitigation CFG | Should -Be 'ON'
        @(Get-LtLedgerEntries | Where-Object { $_.key -eq 'Mitigation|System|CFG' }).Count | Should -Be 1
    }

    It 'ISLC gorevi tekrar uygulandiginda yinelenmez ve geri almada kaldirilir' {
        $sys.Ctx.AppRoot = New-LtThirdPartyFixture -Root $sys.Root
        (Invoke-LtApply -TweakIds 'mem.islc-autostart' -Context $sys.Ctx).Results[0].Status | Should -Be 'Success'
        (Invoke-LtApply -TweakIds 'mem.islc-autostart' -Context $sys.Ctx).Results[0].Status | Should -Be 'AlreadyApplied'
        $sys.Mem.Tasks.Count | Should -Be 1
        (Invoke-LtRevert -TweakIds 'mem.islc-autostart' -Context $sys.Ctx -Target Previous).Results[0].Status | Should -Be 'Success'
        $sys.Mem.Tasks.Count | Should -Be 0
    }

    It 'Hazirda bekletme kapatilir ve geri acilir' {
        (Invoke-LtApply -TweakIds 'sys.hibernate-off' -Context $sys.Ctx).Results[0].Status | Should -Be 'Success'
        Get-LtHibernateEnabled | Should -BeFalse
        (Invoke-LtRevert -TweakIds 'sys.hibernate-off' -Context $sys.Ctx -Target Previous).Results[0].Status | Should -Be 'Success'
        Get-LtHibernateEnabled | Should -BeTrue
    }

    It 'Olay gunlugu zaten buyukse kucultmez' {
        $sys.Mem.EventLogSize['Application'] = 209715200; $sys.Mem.EventLogSize['System'] = 209715200; $sys.Mem.EventLogSize['Security'] = 209715200
        (Invoke-LtApply -TweakIds 'sys.eventlog-size' -Context $sys.Ctx).Results[0].Status | Should -Be 'AlreadyApplied'
    }
}

Describe 'Journal ve kurtarma' {
    BeforeEach { $sys = New-LtTestSystem }
    AfterEach { Remove-LtTestSystem $sys }

    It 'Yarim kalan islemi (end kaydi yok) bulur ve islem oncesi duruma dondurur' {
        # Uygulamanin degisiklik ortasinda kapanmasini simule et: journal + ledger + degisiklik, 'end' yok
        $a = New-LtRegAction -Path 'HKCU\Control Panel\Desktop' -Name 'MenuShowDelay' -Kind String -Value '0'
        [void](Set-LtRegValue 'HKCU\Control Panel\Desktop' 'MenuShowDelay' -Kind String -Data '400')
        $op = New-LtOperation -Kind Apply -TweakIds 'ui.menu-delay'
        $before = Get-LtActionSnapshot $a
        Add-LtJournalEntry -OperationId $op -Entry @{ t = 'change'; cid = 1; mode = 'Apply'; tweak = 'ui.menu-delay'; key = (Get-LtActionKey $a); action = $a; before = $before }
        [void](Add-LtLedgerOriginal -Key (Get-LtActionKey $a) -Action $a -Snapshot $before -TweakId 'ui.menu-delay' -OperationId $op)
        Invoke-LtActionApply $a

        $inc = @(Get-LtIncompleteOperations)
        $inc.Count | Should -Be 1
        $inc[0].Id | Should -Be $op
        $res = Invoke-LtRecovery -OperationId $op -Mode Revert
        @($res | Where-Object Status -eq 'Success').Count | Should -Be 1
        (Get-LtRegValue 'HKCU\Control Panel\Desktop' 'MenuShowDelay').Data | Should -Be '400'
        @(Get-LtIncompleteOperations).Count | Should -Be 0
        @(Get-LtLedgerEntries).Count | Should -Be 0
    }

    It 'Kesilmis son journal satiri okunur, onceki kayitlar kaybolmaz' {
        $op = New-LtOperation -Kind Apply -TweakIds 'x'
        Add-Content -LiteralPath (Get-LtJournalPath $op) -Value '{"t":"change","cid":1,"key":"yar' -NoNewline
        $e = @(Read-LtJournal $op)
        $e.Count | Should -Be 1
        $e[0].t | Should -Be 'begin'
    }

    It '"Birak" modu degisikligi korur, islemi kapatir ve ozgun degeri ledger''da tutar' {
        $op = New-LtOperation -Kind Apply -TweakIds 'ui.show-ext'
        $a = New-LtRegAction -Path 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'HideFileExt' -Value 0
        $b = Get-LtActionSnapshot $a
        Add-LtJournalEntry -OperationId $op -Entry @{ t = 'change'; cid = 1; tweak = 'ui.show-ext'; key = (Get-LtActionKey $a); action = $a; before = $b }
        [void](Add-LtLedgerOriginal -Key (Get-LtActionKey $a) -Action $a -Snapshot $b -TweakId 'ui.show-ext' -OperationId $op)
        Invoke-LtActionApply $a
        [void](Invoke-LtRecovery -OperationId $op -Mode Keep)
        @(Get-LtIncompleteOperations).Count | Should -Be 0
        (Invoke-LtRevert -TweakIds 'ui.show-ext' -Context $sys.Ctx -Target Previous).Results[0].Status | Should -Be 'Success'
        (Get-LtRegValue 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'HideFileExt').Exists | Should -BeFalse
    }

    It 'Durum yedegi disa aktarilir ve geri yuklenir (eksik degerler dahil)' {
        $bk = Export-LtStateBackup -TweakIds @('ui.show-ext', 'ui.darkmode') -Context $sys.Ctx -Label 'test'
        Test-Path $bk.Path | Should -BeTrue
        [void](Invoke-LtApply -TweakIds @('ui.show-ext', 'ui.darkmode') -Context $sys.Ctx)
        $rr = Restore-LtStateBackup -Path $bk.Path
        $rr.Summary.Failed | Should -Be 0
        (Get-LtRegValue 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'HideFileExt').Exists | Should -BeFalse
        (Get-LtRegValue 'HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'AppsUseLightTheme').Exists | Should -BeFalse
    }
}

Describe 'Onizleme degisiklik yapmaz' {
    BeforeEach { $sys = New-LtTestSystem }
    AfterEach { Remove-LtTestSystem $sys }

    It 'Get-LtPlan hicbir yazma cagrisi yapmaz ve degisecekleri listeler' {
        $n = $sys.Mem.Calls.Count
        $plan = Get-LtPlan -TweakIds @('ui.show-ext', 'timer.platformclock-default', 'power.ultimate') -Context $sys.Ctx
        @($sys.Mem.Calls | Select-Object -Skip $n | Where-Object { $_ -notlike '*.Get*' }).Count | Should -Be 0
        ($plan | Where-Object Id -eq 'ui.show-ext').Outcome | Should -Be 'WillChange'
        ($plan | Where-Object Id -eq 'ui.show-ext').Changes[0].From | Should -Be 'yok'
        @(Get-ChildItem (Join-Path $sys.Root 'journal')).Count | Should -Be 0
    }
}
