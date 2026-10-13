#Requires -Modules Pester
# Katalog butunlugu ve preset guvenlik kurallari.

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $sys = New-LtTestSystem
    $catalog = @(Get-LtCatalog -Refresh)
    $presets = Get-LtPresets
}
AfterAll { Remove-LtTestSystem $sys }

Describe 'Katalog butunlugu' {
    It 'Kimlikler benzersiz ve zorunlu alanlar dolu' {
        $catalog.Count | Should -BeGreaterThan 40
        @($catalog.Id | Select-Object -Unique).Count | Should -Be $catalog.Count
        foreach ($t in $catalog) {
            $t.Title | Should -Not -BeNullOrEmpty -Because $t.Id
            $t.Description | Should -Not -BeNullOrEmpty -Because $t.Id
            @('Low', 'Medium', 'High', 'Security') | Should -Contain $t.Risk -Because $t.Id
            @('Documented', 'Community', 'Unverified') | Should -Contain $t.Evidence -Because $t.Id
            @('None', 'Explorer', 'Logoff', 'Reboot') | Should -Contain $t.Restart -Because $t.Id
            @('Performance', 'Network', 'Kernel', 'GPU', 'Privacy', 'WinTweaks') | Should -Contain $t.Page -Because $t.Id
            ($t.ContainsKey('Actions') -or $t.ContainsKey('ActionsFrom')) | Should -BeTrue -Because $t.Id
        }
    }

    It 'Her eylem bilinen bir saglayiciya sahip ve anahtari uretilebiliyor' {
        foreach ($t in $catalog) {
            if (Get-LtTweakSupport $t $sys.Ctx) { continue }
            foreach ($a in @(Resolve-LtTweakActions $t $sys.Ctx)) {
                { Get-LtProvider $a.Type } | Should -Not -Throw -Because $t.Id
                (Get-LtActionKey $a) | Should -Not -BeNullOrEmpty -Because $t.Id
                # Eylemler JSON'a yazilabilir olmali (scriptblock icermemeli)
                foreach ($v in $a.Values) { $v | Should -Not -BeOfType [scriptblock] -Because $t.Id }
            }
        }
    }

    It 'Guvenlik ayarlarinda uyari metni var' {
        foreach ($t in @($catalog | Where-Object Risk -eq 'Security')) {
            [string](Get-LtProp $t 'Warning') | Should -Match 'GÜVENLİĞİ AZALTIR' -Because $t.Id
        }
    }

    It 'Kaldirilan etkisiz/yanlis tweakler katalogda yok' {
        $ids = $catalog.Id
        foreach ($bad in @('sec.dma-off', 'nv.prerender', 'nv.vsync', 'mem.largepages', 'input.rawinput', 'msi.priority')) { $ids | Should -Not -Contain $bad }
        # Eski yanlis yazimlar hicbir eylemde kalmamali
        $all = foreach ($t in $catalog) { if (-not (Get-LtTweakSupport $t $sys.Ctx)) { Resolve-LtTweakActions $t $sys.Ctx } }
        @($all | Where-Object { $_.Type -eq 'Registry' -and $_.Path -like '*ControlSet001*' }).Count | Should -Be 0
        @($all | Where-Object { $_.Type -eq 'Registry' -and $_.Name -eq 'PerfLevelSrc' }).Count | Should -Be 0
        @($all | Where-Object { $_.Type -eq 'Registry' -and $_.Name -eq 'EnableKernelDmaProtection' }).Count | Should -Be 0
        @($all | Where-Object { $_.Type -eq 'Registry' -and $_.Name -eq 'SystemResponsiveness' -and [int]$_.Value -lt 10 }).Count | Should -Be 0
        @($all | Where-Object { $_.Type -eq 'Registry' -and $_.Name -eq 'MSISupported' -and $_.Path -like '*\Control\Class\*' }).Count | Should -Be 0
    }
}

Describe 'Preset kurallari' {
    It 'Tum preset kimlikleri katalogda var' {
        foreach ($p in $presets.Values) { foreach ($id in $p.Ids) { $catalog.Id | Should -Contain $id } }
    }
    It 'Hicbir preset Guvenlik (VBS/HVCI/CFG/Spectre) ayari icermez' {
        foreach ($p in $presets.Values) {
            foreach ($id in $p.Ids) { ($catalog | Where-Object Id -eq $id).Risk | Should -Not -Be 'Security' -Because "$($p.Title): $id" }
        }
    }
    It 'Minimal ve Standart yuksek riskli ayar icermez' {
        foreach ($name in @('Minimal', 'Standard')) {
            foreach ($id in $presets[$name].Ids) { ($catalog | Where-Object Id -eq $id).Risk | Should -Not -BeIn @('High', 'Security') -Because "$name/$id" }
        }
    }
    It 'Presetler ayni ozel gruptan birden fazla oge secmez' {
        foreach ($p in $presets.Values) {
            $groups = @($p.Ids | ForEach-Object { Get-LtProp ($catalog | Where-Object Id -eq $_) 'Exclusive' } | Where-Object { $_ })
            @($groups | Select-Object -Unique).Count | Should -Be $groups.Count
        }
    }
    It 'Gorunum preseti bellek arka ucunda hatasiz uygulanir ve tamami geri alinabilir' {
        $s = New-LtTestSystem
        try {
            $r = Invoke-LtApply -TweakIds $presets.Aggressive.Ids -Context $s.Ctx
            $r.Summary.Failed | Should -Be 0 -Because (($r.Results | Where-Object Status -eq 'Failed' | ForEach-Object { "$($_.Id): $($_.Message)" }) -join '; ')
            $applied = @($r.Results | Where-Object Status -eq 'Success' | ForEach-Object Id)
            $rv = Invoke-LtRevert -TweakIds $applied -Context $s.Ctx -Target Previous
            $rv.Summary.Failed | Should -Be 0 -Because (($rv.Results | Where-Object Status -eq 'Failed' | ForEach-Object { "$($_.Id): $($_.Message)" }) -join '; ')
            @(Get-LtLedgerEntries).Count | Should -Be 0
            foreach ($id in $applied) { (Get-LtTweakStatus (Get-LtTweak $id) $s.Ctx).State | Should -Not -Be 'Applied' -Because $id }
        } finally { Remove-LtTestSystem $s }
    }
}
