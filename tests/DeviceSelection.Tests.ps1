#Requires -Modules Pester
# Kullanıcı hatası (2 Ekim): Ağ sayfasında adaptör seçildiği hâlde DNS ve adaptör ayarları
# "Önce ağ sayfasından tek bir adaptör seçin" nedeniyle Desteklenmiyor kalıyordu.
# Kök neden: SelectionChanged sırasında ComboBox.SelectedValue henüz güncellenmemiş olabilir;
# seçim artık SelectedItem'den okunur, görünür yazılır ve tek adaptör otomatik hedeflenir.

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $src = Join-Path $script:RepoRoot 'src/UI'
    . (Join-Path $src 'ViewModels.ps1')
    . (Join-Path $src 'Dialogs.ps1')
    . (Join-Path $src 'App.ps1')
    function New-FakeCombo { [pscustomobject]@{ ItemsSource = $null; SelectedItem = $null; SelectedValue = $null; Text = ''; Foreground = '' } }
    function New-FakeText { [pscustomobject]@{ Text = ''; Foreground = '' } }
}

Describe 'Aygıt seçimi arayüzden bağlama doğru aktarılır' {
    BeforeEach {
        $sys = New-LtTestSystem
        Initialize-LtViewModels
        $script:Ui = @{
            Ctx = $sys.Ctx; CurrentPage = 'Network'; StateLoaded = @{}; Job = $null; RefreshQueue = (New-Object System.Collections.ArrayList)
            C = @{ CmbNetworkDevice = (New-FakeCombo); CmbMsiDevice = (New-FakeCombo); TxtNetworkTarget = (New-FakeText); TxtMsiTarget = (New-FakeText); TxtStatus = (New-FakeText) }
        }
        New-LtTweakItems
        function Update-LtPageState { param($Page) $script:refreshed = $Page }
    }
    AfterEach { Remove-LtTestSystem $sys }

    It 'SelectedValue güncellenmemişken bile seçilen adaptör DNS ve adaptör ayarlarını açar' {
        $sys.Mem.DemoContext.Nics += @{ Name = 'Wi-Fi'; InterfaceGuid = '{bbbbbbbb-bbbb-cccc-dddd-eeeeeeeeeeee}'; Description = 'Sahte Wi-Fi'; LinkSpeed = '866 Mbps'; InstanceId = 'PCI\WIFI\1' }
        $sys.Ctx.Nics = $sys.Mem.DemoContext.Nics
        $combo = $script:Ui.C.CmbNetworkDevice
        $combo.ItemsSource = @(Get-LtNetworkDeviceChoices $sys.Ctx)
        foreach ($id in @('dns.cloudflare', 'net.ackfreq')) { Get-LtTweakSupport (Get-LtTweak $id) $sys.Ctx | Should -Match 'Hedef adaptör seçilmedi' }
        # WPF: SelectionChanged anında SelectedItem yeni, SelectedValue hâlâ eski (null)
        $combo.SelectedItem = $combo.ItemsSource[1]
        $combo.SelectedValue = $null
        Set-LtNetworkTargetFromUi -Refresh
        $sys.Ctx.SelectedNicGuid | Should -Be '{bbbbbbbb-bbbb-cccc-dddd-eeeeeeeeeeee}'
        Get-LtTweakSupport (Get-LtTweak 'dns.cloudflare') $sys.Ctx | Should -BeNullOrEmpty
        Get-LtTweakSupport (Get-LtTweak 'net.ackfreq') $sys.Ctx | Should -BeNullOrEmpty
        $script:Ui.C.TxtNetworkTarget.Text | Should -Match '^Seçili hedef: Wi-Fi'
        $script:refreshed | Should -Be 'Network'
        (Invoke-LtApply -TweakIds 'dns.cloudflare' -Context $sys.Ctx).Results[0].Status | Should -Be 'Success'
    }

    It 'Seçim yokken nedeni açıkça yazar (istisna mesajı değil)' {
        $script:Ui.C.CmbNetworkDevice.ItemsSource = @(Get-LtNetworkDeviceChoices $sys.Ctx)
        Set-LtNetworkTargetFromUi
        $script:Ui.C.TxtNetworkTarget.Text | Should -Match '^Hedef seçilmedi'
        $why = Get-LtTweakSupport (Get-LtTweak 'dns.google') $sys.Ctx
        $why | Should -Match 'Hedef adaptör'
        $why | Should -Not -Match 'Destek kontrolü yapılamadı'
        Get-LtTweakSupport (Get-LtTweak 'nic.flowcontrol-off') $sys.Ctx | Should -Not -Match 'Destek kontrolü yapılamadı'
    }

    It 'Tek adaptör otomatik hedeflenir; sistem bilgisi yenilenince önceki seçim korunur' {
        Set-LtDeviceChoicesView -Ctx $sys.Ctx
        $sys.Ctx.SelectedNicGuid | Should -Be $sys.Ctx.Nics[0].InterfaceGuid
        $script:Ui.C.TxtNetworkTarget.Text | Should -Match '^Seçili hedef'
        # Iki adaptorlu sistem: otomatik secim yok, onceki secim GUID ile geri gelir
        $nics = @($sys.Ctx.Nics) + @(@{ Name = 'Wi-Fi'; InterfaceGuid = '{bbbbbbbb-bbbb-cccc-dddd-eeeeeeeeeeee}'; Description = 'x'; LinkSpeed = '' })
        $fresh = @{ Nics = $nics; MsiDevices = @($sys.Ctx.MsiDevices) }
        $script:Ui.Ctx = $fresh
        $script:Ui.C.CmbNetworkDevice.SelectedItem = $null
        Set-LtDeviceChoicesView -Ctx $fresh -PreviousNic '{bbbbbbbb-bbbb-cccc-dddd-eeeeeeeeeeee}' -PreviousMsi ($sys.Ctx.MsiDevices[0].InstanceId)
        $fresh.SelectedNicGuid | Should -Be '{bbbbbbbb-bbbb-cccc-dddd-eeeeeeeeeeee}'
        $fresh.SelectedMsiInstanceId | Should -Be $sys.Ctx.MsiDevices[0].InstanceId
        $script:Ui.C.TxtMsiTarget.Text | Should -Match '^Seçili MSI hedefi'
        $script:Ui.Ctx = @{ Nics = $nics; MsiDevices = @() }
        $script:Ui.C.CmbNetworkDevice.SelectedItem = $null
        Set-LtDeviceChoicesView -Ctx $script:Ui.Ctx
        $script:Ui.Ctx.SelectedNicGuid | Should -BeNullOrEmpty -Because 'birden çok adaptörde tahmin yapılmaz'
    }

    It 'MSI seçimi de SelectedItem üzerinden okunur' {
        $combo = $script:Ui.C.CmbMsiDevice
        $combo.ItemsSource = @(Get-LtMsiDeviceChoices $sys.Ctx)
        $combo.SelectedItem = $combo.ItemsSource[0]
        Set-LtMsiTargetFromUi -Refresh
        Get-LtTweakSupport (Get-LtTweak 'msi.gpu') $sys.Ctx | Should -BeNullOrEmpty
    }

    It 'Arayüz kodu seçimi hiçbir yerde SelectedValue ile okumaz' {
        $app = [IO.File]::ReadAllText((Join-Path $script:RepoRoot 'src/UI/App.ps1'))
        [regex]::Matches($app, '\.SelectedValue\b(?!Path)').Count | Should -Be 0
    }
}
