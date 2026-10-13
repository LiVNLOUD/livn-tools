#Requires -Modules Pester
# Hazır seçimler, doğrulanmış güç planı dosyaları ve aygıt seçimine bağlı GPU/MSI ayarları.
# Tümü bellek arka ucunda çalışır; gerçek registry, güç planı veya aygıt değiştirilmez.

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $src = Join-Path $script:RepoRoot 'src/UI'
    . (Join-Path $src 'ViewModels.ps1')
    . (Join-Path $src 'Dialogs.ps1')
    . (Join-Path $src 'App.ps1')
}

Describe 'Hazır seçimler' {
    BeforeEach { $sys = New-LtTestSystem }
    AfterEach { Remove-LtTestSystem $sys }

    It 'Her hazır seçim bu sistemde anlamlı sayıda ayar işaretler' {
        $min = @{ Minimal = 5; Standard = 8; Aggressive = 5; Responsive = 4; MaxPerformance = 10 }
        foreach ($name in (Get-LtPresets).Keys) {
            $r = Resolve-LtPresetSelection -Name $name -Context $sys.Ctx
            @($r.Selected).Count | Should -BeGreaterOrEqual $min[$name] -Because $name
            @($r.Selected | Select-Object -Unique).Count | Should -Be @($r.Selected).Count
        }
    }

    It 'Maksimum performans doğrulanmış Bitsum planını seçer' {
        $r = Resolve-LtPresetSelection -Name MaxPerformance -Context $sys.Ctx
        $r.Selected | Should -Contain 'power.bitsum'
        $r.Selected | Should -Not -Contain 'power.ultimate'
        $r.Choices[0].Id | Should -Be 'power.bitsum'
        $r.Selected | Should -Contain 'gpu.hags'
    }

    It 'Plan dosyası yoksa Nihai Performans planına düşer' {
        $sys.Ctx.AppRoot = $sys.Root
        $r = Resolve-LtPresetSelection -Name MaxPerformance -Context $sys.Ctx
        $r.Selected | Should -Not -Contain 'power.bitsum'
        $r.Selected | Should -Contain 'power.ultimate'
    }

    It 'Modern Bekleme cihazında Dengeli dışı planlar seçilmez ve güç modu önerilir' {
        $sys.Ctx.ModernStandby = $true
        $r = Resolve-LtPresetSelection -Name MaxPerformance -Context $sys.Ctx
        foreach ($id in @('power.bitsum', 'power.ultimate')) { $r.Selected | Should -Not -Contain $id }
        $r.Choices[0].Id | Should -Be 'power.highperf' -Because 'sahte sistemde Yüksek Performans planı listede'
        # Gercek Modern Bekleme cihazlarinda Yuksek Performans plani listelenmez
        $sys.Ctx.PowerSchemes = @($sys.Ctx.PowerSchemes | Where-Object { $_ -ne '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' })
        $r = Resolve-LtPresetSelection -Name MaxPerformance -Context $sys.Ctx
        $grp = @($r.Unsupported | Where-Object { $_.Id -like 'power.bitsum|*' })
        $grp.Count | Should -Be 1
        $grp[0].Reason | Should -Match 'Güç modu'
        foreach ($id in @('power.bitsum', 'power.hybred-hp', 'power.ultimate')) { Get-LtTweakSupport (Get-LtTweak $id) $sys.Ctx | Should -Match 'Modern Bekleme' -Because $id }
        Get-LtTweakSupport (Get-LtTweak 'power.hybred-bal') $sys.Ctx | Should -BeNullOrEmpty
        $sys.Ctx.ModernStandby = $null
        Get-LtTweakSupport (Get-LtTweak 'power.ultimate') $sys.Ctx | Should -BeNullOrEmpty -Because 'okunamayan durum engellemez'
    }

    It 'Seçili adaptör yokken adaptör ayarlarını nedeniyle atlar; seçilince işaretler' {
        $r = Resolve-LtPresetSelection -Name MaxPerformance -Context $sys.Ctx
        $skipped = @($r.Unsupported | Where-Object Id -eq 'nic.flowcontrol-off')
        $skipped.Count | Should -Be 1
        $skipped[0].Reason | Should -Match 'adaptör'
        $sys.Ctx.SelectedNicGuid = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
        (Resolve-LtPresetSelection -Name MaxPerformance -Context $sys.Ctx).Selected | Should -Contain 'nic.flowcontrol-off'
    }

    It 'Bilgi metni sayıyı, seçilen planı ve atlanma nedenlerini söyler' {
        $text = Format-LtPresetInfo (Resolve-LtPresetSelection -Name MaxPerformance -Context $sys.Ctx)
        $text | Should -Match '^Maksimum performans: \d+ ayar işaretlendi'
        $text | Should -Match 'Bitsum'
        $text | Should -Match 'atlanan'
        $text | Should -Match 'Değişiklik yok'
    }

    It 'Bilinmeyen hazır seçim reddedilir' {
        { Resolve-LtPresetSelection -Name 'Yok' -Context $sys.Ctx } | Should -Throw '*Bilinmeyen*'
    }

    It 'Maksimum performans bellek arka ucunda hatasız uygulanır ve önceki ayarlara döner' {
        $r = Resolve-LtPresetSelection -Name MaxPerformance -Context $sys.Ctx
        $plan = Get-LtActivePowerScheme
        $apply = Invoke-LtApply -TweakIds $r.Selected -Context $sys.Ctx
        $apply.Summary.Failed | Should -Be 0 -Because (($apply.Results | Where-Object Status -eq 'Failed' | ForEach-Object { "$($_.Id): $($_.Message)" }) -join ' | ')
        Get-LtActivePowerScheme | Should -Be '4dcd1bfb-1ae5-4c5b-b1dd-891dfb76ed04'
        $revert = Invoke-LtRevert -TweakIds $r.Selected -Context $sys.Ctx -Target Previous
        $revert.Summary.Failed | Should -Be 0 -Because (($revert.Results | Where-Object Status -eq 'Failed' | ForEach-Object { "$($_.Id): $($_.Message)" }) -join ' | ')
        Get-LtActivePowerScheme | Should -Be $plan
    }
}

Describe 'Güç planı dosyaları' {
    BeforeEach { $sys = New-LtTestSystem }
    AfterEach { Remove-LtTestSystem $sys }

    It 'Depodaki plan dosyaları sabitlenmiş SHA-256 değerleriyle eşleşir' {
        foreach ($name in @('Bitsum-Highest-Performance.pow', 'HybredLowLatencyHighPerf.pow', 'HybredLowLatencyBalanced.pow')) {
            Get-LtPowerPlanFileIssue -Ctx $sys.Ctx -Name $name | Should -BeNullOrEmpty -Because $name
        }
        foreach ($id in @('power.bitsum', 'power.hybred-hp', 'power.hybred-bal')) {
            Get-LtTweakSupport (Get-LtTweak $id) $sys.Ctx | Should -BeNullOrEmpty -Because $id
        }
    }

    It 'Değiştirilmiş plan dosyası desteklenmez ve içe aktarılmaz' {
        $app = Join-Path $sys.Root 'app'
        [void](New-Item -ItemType Directory -Path (Join-Path $app '_Files') -Force)
        [IO.File]::WriteAllText((Join-Path $app '_Files/Bitsum-Highest-Performance.pow'), 'tampered')
        $sys.Ctx.AppRoot = $app
        Get-LtTweakSupport (Get-LtTweak 'power.bitsum') $sys.Ctx | Should -Match 'SHA-256'
        (Invoke-LtApply -TweakIds 'power.bitsum' -Context $sys.Ctx).Results[0].Status | Should -Be 'NotSupported'
        (Get-LtPowerSchemes) | Should -Not -Contain '4dcd1bfb-1ae5-4c5b-b1dd-891dfb76ed04'
    }

    It 'İçe aktarma anında içerik yeniden doğrulanır' {
        $file = Join-Path $sys.Root 'swapped.pow'
        [IO.File]::WriteAllText($file, 'swapped after support check')
        $a = @{ Type = 'PowerScheme'; Guid = '4dcd1bfb-1ae5-4c5b-b1dd-891dfb76ed04'; Source = 'Import'; File = $file; Sha256 = 'F8BDD77720170E6521FA0FF533CDA9E4DA8342D16F858159E74E8216BC22A306' }
        { Initialize-LtPowerScheme $a } | Should -Throw '*eşleşmiyor*'
        (Get-LtPowerSchemes) | Should -Not -Contain '4dcd1bfb-1ae5-4c5b-b1dd-891dfb76ed04'
    }

    It 'Hybred planı içe aktarılır, etkinleştirilir ve önceki plana dönülür' {
        $before = Get-LtActivePowerScheme
        (Invoke-LtApply -TweakIds 'power.hybred-hp' -Context $sys.Ctx).Results[0].Status | Should -Be 'Success'
        Get-LtActivePowerScheme | Should -Be 'e559f809-9e1d-4dae-81d4-a2ab04520d2a'
        (Invoke-LtRevert -TweakIds 'power.hybred-hp' -Context $sys.Ctx -Target Previous).Summary.Failed | Should -Be 0
        Get-LtActivePowerScheme | Should -Be $before
    }
}

Describe 'GPU ve MSI: aygıt seçimine bağlı ayarlar' {
    BeforeEach {
        $sys = New-LtTestSystem
        $gpu = @($sys.Ctx.MsiDevices | Where-Object Class -eq 'GPU')[0]
        $nic = @($sys.Ctx.MsiDevices | Where-Object Class -eq 'NIC')[0]
        $msiPath = { param($d) "HKLM\SYSTEM\CurrentControlSet\Enum\$($d.InstanceId)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties" }
    }
    AfterEach { Remove-LtTestSystem $sys }

    It 'Seçili GPU için MSI yazılır, ağ kartı ayarı nedeniyle kapalı kalır ve geri alınır' {
        $sys.Ctx.SelectedMsiInstanceId = $gpu.InstanceId
        Get-LtTweakSupport (Get-LtTweak 'msi.gpu') $sys.Ctx | Should -BeNullOrEmpty
        Get-LtTweakSupport (Get-LtTweak 'msi.nic') $sys.Ctx | Should -Match 'ağ kartı değil'
        (Invoke-LtApply -TweakIds 'msi.gpu' -Context $sys.Ctx).Results[0].Status | Should -Be 'Success'
        $v = Get-LtRegValue (& $msiPath $gpu) 'MSISupported'
        $v.Exists | Should -BeTrue
        [int]$v.Data | Should -Be 1
        (Get-LtRegValue (& $msiPath $nic) 'MSISupported').Exists | Should -BeFalse
        (Invoke-LtRevert -TweakIds 'msi.gpu' -Context $sys.Ctx -Target Previous).Summary.Failed | Should -Be 0
        (Get-LtRegValue (& $msiPath $gpu) 'MSISupported').Exists | Should -BeFalse
    }

    It 'Seçili ağ kartı için MSI yazılır' {
        $sys.Ctx.SelectedMsiInstanceId = $nic.InstanceId
        (Invoke-LtApply -TweakIds 'msi.nic' -Context $sys.Ctx).Results[0].Status | Should -Be 'Success'
        [int](Get-LtRegValue (& $msiPath $nic) 'MSISupported').Data | Should -Be 1
    }

    It 'Donanımı MSI bildirmeyen veya desteği okunamayan aygıta yazmaz' {
        $sys.Ctx.SelectedMsiInstanceId = $gpu.InstanceId
        $gpu.InterruptSupport = 1
        Get-LtTweakSupport (Get-LtTweak 'msi.gpu') $sys.Ctx | Should -Match 'hat tabanlı'
        $gpu.InterruptSupport = $null
        Get-LtTweakSupport (Get-LtTweak 'msi.gpu') $sys.Ctx | Should -Match 'okunamadı'
        (Invoke-LtApply -TweakIds 'msi.gpu' -Context $sys.Ctx).Results[0].Status | Should -Be 'NotSupported'
        (Get-LtRegValue (& $msiPath $gpu) 'MSISupported').Exists | Should -BeFalse
    }

    It 'Listede olmayan veya bozuk aygıt seçimini reddeder' {
        $sys.Ctx.SelectedMsiInstanceId = 'PCI\VEN_FFFF&DEV_0000\1'
        Get-LtTweakSupport (Get-LtTweak 'msi.gpu') $sys.Ctx | Should -Match 'mevcut değil'
        $sys.Ctx.SelectedMsiInstanceId = 'ROOT\BASICDISPLAY\0000'
        Get-LtTweakSupport (Get-LtTweak 'msi.gpu') $sys.Ctx | Should -Match 'mevcut değil'
    }

    It 'HAGS: sürücü desteği bildirildiğinde tercih yazılır ve Windows varsayılanına dönülür' {
        $key = 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
        Get-LtTweakSupport (Get-LtTweak 'gpu.hags') $sys.Ctx | Should -BeNullOrEmpty
        (Invoke-LtApply -TweakIds 'gpu.hags' -Context $sys.Ctx).Results[0].Status | Should -Be 'Success'
        [int](Get-LtRegValue $key 'HwSchMode').Data | Should -Be 2
        (Invoke-LtRevert -TweakIds 'gpu.hags' -Context $sys.Ctx -Target Default).Summary.Failed | Should -Be 0
        (Get-LtRegValue $key 'HwSchMode').Exists | Should -BeFalse
    }

    It 'HAGS: sürücü desteklemiyorsa veya Windows eskiyse kapalı; sorgu okunamazsa engellemez' {
        $sys.Ctx.Hags = @{ Supported = $false; Enabled = $false; Detail = 'x' }
        Get-LtTweakSupport (Get-LtTweak 'gpu.hags') $sys.Ctx | Should -Match 'desteği bildirmiyor'
        $sys.Ctx.Hags = @{ Supported = $null; Enabled = $null; Detail = 'okunamadı' }
        Get-LtTweakSupport (Get-LtTweak 'gpu.hags') $sys.Ctx | Should -BeNullOrEmpty
        $sys.Ctx.Build = 18363
        Get-LtTweakSupport (Get-LtTweak 'gpu.hags') $sys.Ctx | Should -Match '19041'
    }

    It 'Aygıt listesi ve durum metni aygıt kimliğini göstermez' {
        $sys.Ctx.MsiDevices = @($sys.Ctx.MsiDevices) + @(@{ Class = 'GPU'; Name = 'Sahte NVIDIA GPU'; InstanceId = 'PCI\VEN_10DE&DEV_2684\4&2'; InterruptSupport = $null })
        $choices = @(Get-LtMsiDeviceChoices $sys.Ctx)
        $choices.Count | Should -Be 3
        foreach ($c in $choices) {
            $c.Label | Should -Not -Match 'PCI\\|VEN_|DEV_'
            $c.InstanceId | Should -Match '^PCI\\'
        }
        $choices[0].Label | Should -Be 'Ekran kartı — Sahte NVIDIA GPU · donanım: MSI'
        $choices[1].Label | Should -Be 'Ağ kartı — Sahte Ethernet · donanım: MSI ve MSI-X'
        $choices[2].Label | Should -Be 'Ekran kartı — Sahte NVIDIA GPU (2) · MSI desteği okunamadı'
        foreach ($n in @(Get-LtNetworkDeviceChoices $sys.Ctx)) { $n.Label | Should -Not -Match '[0-9a-f]{8}-[0-9a-f]{4}' }
        $text = Format-LtGraphicsStateText -Hags (Get-LtGraphicsConfiguration) -Msi (Get-LtMsiDeviceConfiguration -Context $sys.Ctx -InstanceId $gpu.InstanceId)
        $text | Should -Not -Match 'PCI\\|VEN_'
        $text | Should -Match 'Sürücü desteği: destekleniyor'
        $text | Should -Match 'Donanım desteği: MSI'
    }
}
