# Livn Tools - Catalog/Tweaks.ps1
# HER AYARIN TEK TANIMI. UI, presetler, "Tumunu uygula", durum taramasi ve geri
# alma bu listeyi kullanir; baska yerde ayar kodu yoktur.
#
# Alanlar:
#   Id, Page, Group, Title, Description
#   Risk      : Low | Medium | High | Security   (Security asla presete girmez)
#   Evidence  : Documented (birincil kaynak) | Community (topluluk bilgisi) | Unverified
#   Sources   : kaynak URL'leri (docs/TWEAK_AUDIT.md ile ayni)
#   Restart   : None | Explorer | Logoff | Reboot
#   Exclusive : ayni gruptan yalniz biri secilebilir (guc plani, Win32Prio)
#   Supported : { param($ctx) ... }  -> $null = destekleniyor, metin = neden desteklenmedigi
#   Actions   : sabit eylem listesi   veya   ActionsFrom : { param($ctx) ... } (donanima gore)
#   Warning   : uygulamadan once kullaniciya gosterilecek uyari
#
# NOT: Olcum olmadan FPS/gecikme kazanci vaat edilmez. Aciklamalar ne degistigini anlatir.

Set-StrictMode -Version 2.0

$script:LtSrc = @{
    MMCSS      = 'https://learn.microsoft.com/en-us/windows/win32/procthread/multimedia-class-scheduler-service'
    BcdEdit    = 'https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/bcdedit--set'
    BcdBitLk   = 'https://learn.microsoft.com/en-us/windows/security/operating-system-security/data-protection/bitlocker/bcd-settings-and-bitlocker'
    TimerBlog  = 'https://randomascii.wordpress.com/2020/10/04/windows-timer-resolution-the-great-rule-change/'
    Powercfg   = 'https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/powercfg-command-line-options'
    Hags       = 'https://devblogs.microsoft.com/directx/hardware-accelerated-gpu-scheduling/'
    Msi        = 'https://learn.microsoft.com/en-us/windows-hardware/drivers/kernel/enabling-message-signaled-interrupts-in-the-registry'
    TcpSetting = 'https://learn.microsoft.com/en-us/powershell/module/nettcpip/set-nettcpsetting'
    Cubic      = 'https://techcommunity.microsoft.com/t5/networking-blog/windows-transport-converges-on-two-congestion-providers-cubic/ba-p/339819'
    AckFreq    = 'https://learn.microsoft.com/en-us/troubleshoot/windows-server/networking/registry-entry-control-tcp-acknowledgment-behavior'
    NicEnum    = 'https://learn.microsoft.com/en-us/windows-hardware/drivers/network/enumeration-keywords'
    NicPower   = 'https://learn.microsoft.com/en-us/windows-hardware/drivers/network/standardized-inf-keywords-for-power-management'
    Telemetry  = 'https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-system'
    Consumer   = 'https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-experience'
    Hvci       = 'https://learn.microsoft.com/en-us/windows/security/hardware-security/enable-virtualization-based-protection-of-code-integrity'
    Spectre    = 'https://support.microsoft.com/en-us/topic/kb4072698-windows-server-and-azure-stack-hci-guidance-to-protect-against-silicon-based-microarchitectural-and-speculative-execution-side-channel-vulnerabilities-2f965763-00e2-8f98-b632-0d96f30c8c8e'
    ProcMitig  = 'https://learn.microsoft.com/en-us/powershell/module/processmitigations/set-processmitigation'
    CrashDump  = 'https://learn.microsoft.com/en-us/troubleshoot/windows-server/performance/memory-dump-file-options'
    LongPath   = 'https://learn.microsoft.com/en-us/windows/win32/fileio/maximum-file-path-limitation'
}

$script:LtPowerGuid = @{
    Balanced = '381b4222-f694-41f0-9685-ff5bb260df2e'
    HighPerf = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
    UltimateBase = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
    # Livn Tools'a ozgu SABIT hedef GUID'ler (tekrar uygulamada yinelenen plan olusmaz)
    Ultimate = 'd72c20ca-2d2d-4ba7-b818-ababadb4ef63'
    Bitsum   = '4dcd1bfb-1ae5-4c5b-b1dd-891dfb76ed04'
    HybredHP = 'e559f809-9e1d-4dae-81d4-a2ab04520d2a'
    HybredBal = '34add588-ef49-43fa-98e7-4b1491abb150'
}

# Projeye eklenen ucuncu taraf plan dosyalarinin SABIT SHA-256 degerleri (docs/THIRD_PARTY.md).
# Icerigi degismis bir .pow dosyasi ice aktarilmaz.
$script:LtPowerPlanFileHash = @{
    'Bitsum-Highest-Performance.pow' = 'F8BDD77720170E6521FA0FF533CDA9E4DA8342D16F858159E74E8216BC22A306'
    'HybredLowLatencyHighPerf.pow'   = '5FA32B2853AA59140133C64458D112EAB4EB3EDDF31FE6E73C802CBDC8AF7FC3'
    'HybredLowLatencyBalanced.pow'   = '1F0C1B3C17CB60A038486E02A849759106547169A4BD42F905BA7B6C639E16AD'
}

function Get-LtPowerPlanFile {
    param($Ctx, [string]$Name)
    if (-not $Ctx.AppRoot) { return $null }
    $f = Get-ChildItem -LiteralPath (Join-Path $Ctx.AppRoot '_Files') -Recurse -Filter $Name -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { return $f.FullName }
    return $null
}

function Get-LtModernStandbyPlanIssue {
    <# Modern Bekleme cihazlari yalniz Dengeli ve ondan turetilen planlara izin verir (Microsoft Learn: Power Policy Settings). #>
    param($Ctx)
    if ($true -eq (Get-LtProp $Ctx 'ModernStandby' $null)) {
        return 'Modern Bekleme (S0) cihazı: Windows yalnız Dengeli ve ondan türetilen planlara izin verir. Bunun yerine Ayarlar > Sistem > Güç > Güç modu: "En iyi performans" kullanın.'
    }
    return $null
}

function Get-LtPowerPlanFileIssue {
    <# $null = dosya var ve sabit SHA-256 ile eslesiyor; aksi halde neden. #>
    param($Ctx, [string]$Name)
    $path = Get-LtPowerPlanFile $Ctx $Name
    if (-not $path) { return "Plan dosyası bulunamadı: _Files\$Name" }
    $expected = $script:LtPowerPlanFileHash[$Name]
    if ($expected -and (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $expected) {
        return "Plan dosyası beklenen içerikle eşleşmiyor (SHA-256): $Name. Değiştirilmiş dosya içe aktarılmaz."
    }
    return $null
}

function Get-LtTweakDefinitions {
    $K  = 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel'
    $MM = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
    $MEM = 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
    $DG = 'HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard'
    $ADV = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    $PERS = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    $CC = 'HKLM\SYSTEM\CurrentControlSet\Control\CrashControl'
    $WU = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'

    $defs = @(
        # =====================================================================
        # PERFORMANS — GUC PLANI (ozel secim: yalnizca biri)
        # =====================================================================
        @{ Id = 'power.balanced'; Page = 'Performance'; Group = 'Güç planı'; Exclusive = 'power-plan'
           Title = 'Dengeli (Windows varsayılanı)'
           Description = 'Windows''un yerleşik Dengeli planını etkinleştirir.'
           Risk = 'Low'; Evidence = 'Documented'; Sources = @($script:LtSrc.Powercfg); Restart = 'None'
           Actions = @(@{ Type = 'PowerScheme'; Guid = $script:LtPowerGuid.Balanced; Source = 'Builtin'; Default = $script:LtPowerGuid.Balanced }) }

        @{ Id = 'power.highperf'; Page = 'Performance'; Group = 'Güç planı'; Exclusive = 'power-plan'
           Title = 'Yüksek Performans (yerleşik)'
           Description = 'Yerleşik Yüksek Performans planını etkinleştirir. Güç tüketimi artar. Modern Bekleme (S0) cihazlarında bu plan bulunmayabilir.'
           Risk = 'Low'; Evidence = 'Documented'; Sources = @($script:LtSrc.Powercfg); Restart = 'None'
           Supported = { param($c) if (@($c.PowerSchemes).Count -gt 0 -and @($c.PowerSchemes) -notcontains $script:LtPowerGuid.HighPerf) { 'Yüksek Performans planı bu sistemde yok (Modern Bekleme cihazlarında gizlidir).' } }
           Actions = @(@{ Type = 'PowerScheme'; Guid = $script:LtPowerGuid.HighPerf; Source = 'Builtin'; Default = $script:LtPowerGuid.Balanced }) }

        @{ Id = 'power.ultimate'; Page = 'Performance'; Group = 'Güç planı'; Exclusive = 'power-plan'
           Title = 'Nihai Performans (Ultimate)'
           Description = 'Windows''un gizli Ultimate Performance şablonundan SABİT GUID ile bir kez kopya oluşturur ve etkinleştirir; tekrar uygulandığında yeni kopya oluşturmaz. Güç tüketimi ve ısı artar.'
           Risk = 'Medium'; Evidence = 'Documented'; Sources = @($script:LtSrc.Powercfg); Restart = 'None'
           Supported = { param($c) Get-LtModernStandbyPlanIssue $c }
           Actions = @(@{ Type = 'PowerScheme'; Guid = $script:LtPowerGuid.Ultimate; Source = 'Duplicate'; BaseGuid = $script:LtPowerGuid.UltimateBase; Default = $script:LtPowerGuid.Balanced }) }

        @{ Id = 'power.installed'; Page = 'Performance'; Group = 'Güç planı'; Exclusive = 'power-plan'
           Title = 'Seçili kurulu güç planını etkinleştir'
           Description = 'ParkControl/Process Lasso veya üretici tarafından kurulan planı yukarıdaki listeden seçin. Plan kopyalanmaz veya değiştirilmez. Önceki etkin plana geri dönülebilir. Güç modları kullanan cihazlarda Windows güç ayarlarını tercih edin.'
           Warning = 'Yüksek performans planları ısı ve güç tüketimini artırabilir. Process Lasso gibi bir araç otomatik plan değiştiriyorsa bu seçimi sonradan değiştirebilir.'
           Risk = 'Medium'; Evidence = 'Documented'; Sources = @($script:LtSrc.Powercfg, 'https://bitsum.com/power/only-balanced/'); Restart = 'None'
           Supported = { param($c) try { [void](Get-LtSelectedPowerPlan $c) } catch { $_.Exception.Message } }
           ActionsFrom = { param($c) @(@{ Type = 'PowerScheme'; Guid = (Get-LtSelectedPowerPlan $c); Source = 'Builtin'; Default = $script:LtPowerGuid.Balanced }) } }

        @{ Id = 'power.bitsum'; Page = 'Performance'; Group = 'Güç planı'; Exclusive = 'power-plan'
           Title = 'Bitsum Highest Performance'
           Description = 'Bitsum''un plan dosyasını (_Files) sabit GUID ile bir kez içe aktarır ve etkinleştirir. Çekirdek park etme kapalı, yüksek güç tüketimi. Üçüncü taraf dosyadır (bkz. docs/THIRD_PARTY.md).'
           Risk = 'Medium'; Evidence = 'Community'; Sources = @('https://bitsum.com/bhp/'); Restart = 'None'
           Supported = { param($c) $ms = Get-LtModernStandbyPlanIssue $c; if ($ms) { return $ms }; Get-LtPowerPlanFileIssue $c 'Bitsum-Highest-Performance.pow' }
           ActionsFrom = { param($c) @(@{ Type = 'PowerScheme'; Guid = $script:LtPowerGuid.Bitsum; Source = 'Import'; File = (Get-LtPowerPlanFile $c 'Bitsum-Highest-Performance.pow'); Sha256 = $script:LtPowerPlanFileHash['Bitsum-Highest-Performance.pow']; Default = $script:LtPowerGuid.Balanced }) } }

        @{ Id = 'power.hybred-hp'; Page = 'Performance'; Group = 'Güç planı'; Exclusive = 'power-plan'
           Title = 'Hybred Low Latency — High Performance'
           Description = 'TheHybred plan dosyasını sabit GUID ile bir kez içe aktarır ve etkinleştirir. Üçüncü taraf dosyadır (bkz. docs/THIRD_PARTY.md).'
           Risk = 'Medium'; Evidence = 'Community'; Sources = @(); Restart = 'None'
           Supported = { param($c) $ms = Get-LtModernStandbyPlanIssue $c; if ($ms) { return $ms }; Get-LtPowerPlanFileIssue $c 'HybredLowLatencyHighPerf.pow' }
           ActionsFrom = { param($c) @(@{ Type = 'PowerScheme'; Guid = $script:LtPowerGuid.HybredHP; Source = 'Import'; File = (Get-LtPowerPlanFile $c 'HybredLowLatencyHighPerf.pow'); Sha256 = $script:LtPowerPlanFileHash['HybredLowLatencyHighPerf.pow']; Default = $script:LtPowerGuid.Balanced }) } }

        @{ Id = 'power.hybred-bal'; Page = 'Performance'; Group = 'Güç planı'; Exclusive = 'power-plan'
           Title = 'Hybred Low Latency — Balanced'
           Description = 'TheHybred dengeli düşük gecikme plan dosyasını sabit GUID ile bir kez içe aktarır ve etkinleştirir. Üçüncü taraf dosyadır.'
           Risk = 'Medium'; Evidence = 'Community'; Sources = @(); Restart = 'None'
           Supported = { param($c) Get-LtPowerPlanFileIssue $c 'HybredLowLatencyBalanced.pow' }
           ActionsFrom = { param($c) @(@{ Type = 'PowerScheme'; Guid = $script:LtPowerGuid.HybredBal; Source = 'Import'; File = (Get-LtPowerPlanFile $c 'HybredLowLatencyBalanced.pow'); Sha256 = $script:LtPowerPlanFileHash['HybredLowLatencyBalanced.pow']; Default = $script:LtPowerGuid.Balanced }) } }

        # =====================================================================
        # PERFORMANS — ZAMANLAYICI
        # =====================================================================
        @{ Id = 'timer.platformclock-default'; Page = 'Performance'; Group = 'Zamanlayıcı (BCD)'
           Title = 'Platform saati zorlamasını kaldır (HPET zorlaması)'
           Description = 'BCD''deki useplatformclock/useplatformtick değerlerini siler; Windows zamanlayıcı kaynağını kendisi seçer (varsayılan). Microsoft bu seçeneklerin yalnızca hata ayıklama için kullanılmasını belirtir. Değerler zaten yoksa hiçbir şey değişmez. BitLocker doğrulama profilinde yer almaz.'
           Risk = 'Low'; Evidence = 'Documented'; Sources = @($script:LtSrc.BcdEdit, $script:LtSrc.BcdBitLk); Restart = 'Reboot'
           Actions = @((New-LtBcdAction -Element 'useplatformclock' -Value 'Absent'), (New-LtBcdAction -Element 'useplatformtick' -Value 'Absent')) }

        @{ Id = 'timer.dynamictick-off'; Page = 'Performance'; Group = 'Zamanlayıcı (BCD)'
           Title = 'Dinamik tick''i kapat (disabledynamictick)'
           Description = 'Boşta işlemci zamanlayıcı kesmelerinin seyreltilmesini kapatır. Microsoft bu seçeneğin yalnızca hata ayıklama için kullanılmasını belirtir; güç tüketimi artar (dizüstünde pil ömrü düşer). Ölçülmüş bir kazanç garantisi yoktur.'
           Risk = 'High'; Evidence = 'Documented'; Sources = @($script:LtSrc.BcdEdit, $script:LtSrc.BcdBitLk); Restart = 'Reboot'
           Warning = 'Microsoft bu BCD seçeneğini yalnızca hata ayıklama için önerir.'
           Actions = @((New-LtBcdAction -Element 'disabledynamictick' -Value 'Yes')) }

        @{ Id = 'timer.global-resolution'; Page = 'Performance'; Group = 'Zamanlayıcı (BCD)'
           Title = 'Global zamanlayıcı çözünürlüğü isteklerini etkinleştir (Win11)'
           Description = 'GlobalTimerResolutionRequests=1: Windows 10 2004 öncesi davranışı geri getirir; bir işlemin timeBeginPeriod isteği tüm sistemi etkiler. Çözünürlüğü kendisi 0,5 ms yapmaz. Yalnızca Windows 11 / Server 2022+ tarafından dikkate alındığı bildirilir (resmî Microsoft belgesi yok). Güç tüketimi artabilir.'
           Risk = 'Medium'; Evidence = 'Community'; Sources = @($script:LtSrc.TimerBlog); Restart = 'Reboot'
           Supported = { param($c) if (-not ($c.Build -ge 22000 -or ($c.IsServer -and $c.Build -ge 20348))) { 'Yalnızca Windows 11 veya Server 2022 ve sonrası bu değeri dikkate alır.' } }
           Actions = @((New-LtRegAction -Path $K -Name 'GlobalTimerResolutionRequests' -Value 1 -Default 'Absent')) }

        # =====================================================================
        # PERFORMANS — CPU ZAMANLAMASI
        # =====================================================================
        @{ Id = 'sched.mmcss-games'; Page = 'Performance'; Group = 'CPU zamanlaması'
           Title = 'MMCSS CPU payı deneyi (SystemResponsiveness = 10)'
           Description = 'Yalnızca SystemResponsiveness değerini 10 yapar. Games görev önceliklerini değiştirmez. Mekanizma belgelenmiştir; oyun performansı kazancı doğrulanmamıştır. Tek ayar değiştirerek önce/sonra ölçümü yapın.'
           Risk = 'Medium'; Evidence = 'Documented'; Sources = @($script:LtSrc.MMCSS); Restart = 'Reboot'
           Actions = @((New-LtRegAction -Path $MM -Name 'SystemResponsiveness' -Value 10 -Default @('DWord', 20))) }

        @{ Id = 'sched.win32prio-26'; Page = 'Performance'; Group = 'Win32PrioritySeparation'; Exclusive = 'win32prio'
           Title = '0x26 — kısa, değişken quantum, 3:1 ön plan artırımı'
           Description = 'İstemci Windows''un varsayılan davranışının (değer 2) açık yazılmış eşdeğeridir. Yalnızca CurrentControlSet''e yazılır.'
           Risk = 'Low'; Evidence = 'Community'; Sources = @(); Restart = 'None'
           Actions = @((New-LtRegAction -Path 'HKLM\SYSTEM\CurrentControlSet\Control\PriorityControl' -Name 'Win32PrioritySeparation' -Value 0x26 -Default @('DWord', 2))) }

        @{ Id = 'sched.win32prio-18'; Page = 'Performance'; Group = 'Win32PrioritySeparation'; Exclusive = 'win32prio'
           Title = '0x18 — uzun, sabit quantum, ön plan artırımı yok'
           Description = 'Eski "Balanced (0x18)" seçeneği. Ön plan işlemine ek quantum verilmez. Etkisi iş yüküne bağlıdır; ölçüm yapmadan kazanç beklemeyin.'
           Risk = 'Medium'; Evidence = 'Community'; Sources = @(); Restart = 'None'
           Actions = @((New-LtRegAction -Path 'HKLM\SYSTEM\CurrentControlSet\Control\PriorityControl' -Name 'Win32PrioritySeparation' -Value 0x18 -Default @('DWord', 2))) }

        @{ Id = 'sched.win32prio-14'; Page = 'Performance'; Group = 'Win32PrioritySeparation'; Exclusive = 'win32prio'
           Title = '0x14 — uzun, değişken quantum, ön plan artırımı yok'
           Description = 'Eski "BestFPS (0x14)" seçeneği. Bit çözümlemesine göre ön plan artırımı yoktur; "en düşük gecikme" iddiası doğrulanmamıştır.'
           Risk = 'Medium'; Evidence = 'Community'; Sources = @(); Restart = 'None'
           Actions = @((New-LtRegAction -Path 'HKLM\SYSTEM\CurrentControlSet\Control\PriorityControl' -Name 'Win32PrioritySeparation' -Value 0x14 -Default @('DWord', 2))) }

        # =====================================================================
        # PERFORMANS — SERVISLER VE WINDOWS
        # =====================================================================
        @{ Id = 'game.mode'; Page = 'Performance'; Group = 'Servisler ve Windows'
           Title = 'Oyun Modu açık'
           Description = 'Ayarlar > Oyun > Oyun Modu anahtarını açar (Windows''ta varsayılan olarak açıktır).'
           Risk = 'Low'; Evidence = 'Community'; Sources = @(); Restart = 'None'
           Actions = @((New-LtRegAction -Path 'HKCU\Software\Microsoft\GameBar' -Name 'AutoGameModeEnabled' -Value 1 -Default 'Absent')) }

        @{ Id = 'game.bgrecord-off'; Page = 'Performance'; Group = 'Servisler ve Windows'
           Title = 'Arka plan oyun kaydı ("Olanları kaydet") kapalı'
           Description = 'Xbox Game Bar''ın oyun sırasında son dakikaları sürekli video olarak kaydetmesini kapatır. Açıkken GPU/CPU sürekli video kodlar. Ekran görüntüsü ve elle kayıt çalışmaya devam eder. Windows''ta varsayılan olarak kapalıdır; açıksa değişir.'
           Risk = 'Low'; Evidence = 'Community'; Sources = @(); Restart = 'None'
           Actions = @((New-LtRegAction -Path 'HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR' -Name 'HistoricalCaptureEnabled' -Value 0)) }

        @{ Id = 'startup.disable-selected'; Page = 'Performance'; Group = 'Başlangıç'; Hidden = $true
           Title = 'Seçili başlangıç uygulamalarını kapat'
           Description = 'Başlangıç sayfasında seçilen uygulamaların Windows açılışında başlamasını, Görev Yöneticisi ile aynı yöntemle kapatır. Uygulama veya kısayol silinmez.'
           Risk = 'Low'; Evidence = 'Community'; Sources = @(); Restart = 'Logoff'
           Supported = { param($c) if (@(Get-LtProp $c 'StartupSelection' @()).Count -eq 0) { 'Önce Başlangıç sayfasından uygulama seçin.' } }
           ActionsFrom = { param($c) @(New-LtStartupActions -Ctx $c -Enabled $false) } }

        @{ Id = 'startup.enable-selected'; Page = 'Performance'; Group = 'Başlangıç'; Hidden = $true
           Title = 'Seçili başlangıç uygulamalarını yeniden aç'
           Description = 'Başlangıç sayfasında seçilen uygulamaların açılışta başlamasına yeniden izin verir.'
           Risk = 'Low'; Evidence = 'Community'; Sources = @(); Restart = 'Logoff'
           Supported = { param($c) if (@(Get-LtProp $c 'StartupSelection' @()).Count -eq 0) { 'Önce Başlangıç sayfasından uygulama seçin.' } }
           ActionsFrom = { param($c) @(New-LtStartupActions -Ctx $c -Enabled $true) } }

        @{ Id = 'svc.sysmain-off'; Page = 'Performance'; Group = 'Servisler ve Windows'
           Title = 'SysMain (SuperFetch) servisini kapat'
           Description = 'Uygulama ön yükleme/bellek önbelleği servisini devre dışı bırakır. HDD''li sistemlerde açılış süreleri uzayabilir; SSD''de kazanç ölçülmemiştir.'
           Risk = 'Medium'; Evidence = 'Unverified'; Sources = @(); Restart = 'None'
           Actions = @((New-LtServiceAction -Name 'SysMain' -StartType 'Disabled' -Default 'Automatic' -Stop)) }

        @{ Id = 'svc.wsearch-off'; Page = 'Performance'; Group = 'Servisler ve Windows'
           Title = 'Windows Search dizinlemesini kapat'
           Description = 'WSearch servisini devre dışı bırakır. Başlat menüsü/Explorer/Outlook aramaları yavaşlar veya eksik sonuç verir.'
           Risk = 'Medium'; Evidence = 'Unverified'; Sources = @(); Restart = 'None'
           Actions = @((New-LtServiceAction -Name 'WSearch' -StartType 'Disabled' -Default 'AutomaticDelayed' -Stop)) }

        @{ Id = 'wu.defer'; Page = 'Performance'; Group = 'Windows Update'
           Title = 'Özellik güncellemelerini 365 gün ertele (Windows 10 ilkesi)'
           Description = 'Yalnız özellik güncellemesi erteleme kaydını ayarlar. Kalite/güvenlik güncellemelerini ve yeniden başlatmayı değiştirmez. Bu eski GPO yöntemi Windows 11 için kapalıdır; registry doğrulaması etkin güncelleme takviminin doğrulanması değildir.'
           Risk = 'Medium'; Evidence = 'Documented'; Sources = @('https://learn.microsoft.com/en-us/windows/deployment/update/waas-configure-wufb'); Restart = 'None'
           Supported = { param($c)
               if (Test-LtEditionIn $c @('Core*')) { return 'Windows Home bu erteleme ilkelerini desteklemiyor.' }
               if ($c.IsServer -or $c.Build -lt 14393 -or $c.Build -ge 22000) { return 'Bu eski özellik güncellemesi GPO yöntemi yalnız Windows 10 için sunuluyor.' }
               if (@(Get-LtLedgerEntries | Where-Object { @($_.tweakIds) -contains 'wu.defer' -and $_.action.Name -in @('DeferQualityUpdates','DeferQualityUpdatesPeriodInDays','NoAutoRebootWithLoggedOnUsers') }).Count -gt 0) { return 'Eski birleşik güncelleme kaydı var. Önce Önceki ayara dön işlemini tamamlayın.' }
           }
           Actions = @(
               (New-LtRegAction -Path $WU -Name 'DeferFeatureUpdates' -Value 1 -Default 'Absent'),
               (New-LtRegAction -Path $WU -Name 'DeferFeatureUpdatesPeriodInDays' -Value 365 -Default 'Absent')
           ) }

        @{ Id = 'wu.quality-defer'; Page = 'Performance'; Group = 'Windows Update'
           Title = 'Kalite ve güvenlik güncellemelerini 7 gün ertele'
           Description = 'Güvenlik yamaları da 7 gün gecikir. Yalnız kalite güncellemesi erteleme kaydını ayarlar; özellik güncellemelerini ve yeniden başlatmayı değiştirmez. Kurum/MDM ilkeleri üstün gelebilir; kayıt doğrulaması etkin takvimi kanıtlamaz.'
           Risk = 'High'; Evidence = 'Documented'; Sources = @('https://learn.microsoft.com/en-us/windows/deployment/update/waas-configure-wufb'); Restart = 'None'
           Warning = 'Güvenlik açıklarının düzeltmeleri de gecikecek. Bu seçenek bir performans iyileştirmesi değildir.'
           Supported = { param($c)
               if (Test-LtEditionIn $c @('Core*')) { return 'Windows Home bu erteleme ilkelerini desteklemiyor.' }
               if ($c.Build -lt 14393) { return 'Bu güncelleme ilkesi için en az Windows 10 1607 gerekir.' }
               if (@(Get-LtLedgerEntries | Where-Object { @($_.tweakIds) -contains 'wu.defer' -and $_.action.Name -in @('DeferQualityUpdates','DeferQualityUpdatesPeriodInDays','NoAutoRebootWithLoggedOnUsers') }).Count -gt 0) { return 'Önce eski birleşik güncelleme kaydını geri alın; erteleme kayıtları karıştırılmadı.' }
           }
           Actions = @(
               (New-LtRegAction -Path $WU -Name 'DeferQualityUpdates' -Value 1 -Default 'Absent'),
               (New-LtRegAction -Path $WU -Name 'DeferQualityUpdatesPeriodInDays' -Value 7 -Default 'Absent')
           ) }

        # =====================================================================
        # PERFORMANS — BELLEK (ISLC otomatik baslatma; tek seferlik islemler Temizlik'te)
        # =====================================================================
        @{ Id = 'mem.islc-autostart'; Page = 'Performance'; Group = 'Bellek (ISLC)'
           Title = 'ISLC''yi oturum açılışında başlat (Görev Zamanlayıcı)'
           Description = 'ISLC için RAM kapasitesinden sınırlı bir başlangıç profili hesaplar: serbest bellek eşiği %10 (512–4096 MB), liste 1024 MB, tarama 1000 ms. Önizlemede gerçek parametreleri gösterir. Otomatik başlatma oturum açılışında devreye girer; mevcut ISLC ayar dosyası değişmez.'
           Warning = 'Yalnızca resmî kaynaktan edindiğiniz ISLC dosyasını seçin. Dosya adı/sürümü özgünlük kanıtı değildir. ISLC yönetici yetkisiyle çalışır ve kapalı performans sayaçlarını etkinleştirebilir. Mevcut timer çözünürlüğü ayarlarını ISLC içinde kontrol edin. Görevi geri almak çalışan ISLC sürecini durdurmaz. Performans kazancı garanti edilmez.'
           Risk = 'Medium'; Evidence = 'Community'; Sources = @('https://www.wagnardsoft.com/content/Download-Intelligent-standby-list-cleaner-ISLC-1048'); Restart = 'Logoff'
           Supported = { param($c) try { [void](Get-LtIslcFile $c); [void](Get-LtIslcProfile $c) } catch { $_.Exception.Message } }
           ActionsFrom = {
               param($c)
               $file = Get-LtIslcFile $c
               $islcProfile = Get-LtIslcProfile $c
               @(@{ Type = 'ScheduledTask'; TaskPath = '\LivnTools\'; TaskName = 'ISLC'; Execute = $file.Path; Arguments = $islcProfile.Arguments; Default = 'Absent' })
           } }


        # =====================================================================
        # AG
        # =====================================================================
        @{ Id = 'net.autotuning-normal'; Page = 'Network'; Group = 'TCP/IP (genel)'
           Title = 'TCP alma penceresi otomatik ayarı: Normal'
           Description = 'Başka bir araç tarafından kısıtlanmış/kapatılmış auto-tuning''i Windows varsayılanı olan Normal''e döndürür. Zaten Normal ise değişiklik yapılmaz.'
           Risk = 'Low'; Evidence = 'Documented'; Sources = @($script:LtSrc.TcpSetting); Restart = 'None'
           Actions = @((New-LtTcpAction -Setting 'AutoTuningLevel' -Value 'Normal' -Default 'Normal')) }

        @{ Id = 'net.rss-on'; Page = 'Network'; Group = 'TCP/IP (genel)'
           Title = 'Receive-Side Scaling (RSS) açık'
           Description = 'Ağ alım işlemenin birden çok çekirdeğe dağıtılmasını sistem genelinde ve yalnızca seçilen adaptörde (*RSS=1) açar. Windows ve çoğu sürücüde varsayılan olarak açıktır.'
           Risk = 'Low'; Evidence = 'Documented'; Sources = @($script:LtSrc.NicEnum); Restart = 'Reboot'
           Warning = 'Global RSS tercihi tüm sistemi etkiler; sürücü tercihi yalnızca seçilen adaptöre yazılır. Otomatik adaptör yeniden başlatılmaz; etkinleşme için yeniden başlatma gerekir.'
           Supported = { param($c) Get-LtNicSelectionIssue $c }
           ActionsFrom = { param($c) @(@(New-LtTcpAction -Setting 'Rss' -Value 'Enabled' -Default 'Enabled') + @(New-LtNicActions -Ctx $c -Keywords @('*RSS') -Value '1')) } }

        @{ Id = 'net.ecn-off'; Page = 'Network'; Group = 'TCP/IP (genel)'
           Title = 'ECN (Explicit Congestion Notification) kapalı'
           Description = 'ECN desteğini kapatır. ECN''yi hatalı işleyen eski ağ cihazlarıyla sorun yaşanıyorsa faydalıdır; genel bir hız/gecikme kazancı ölçülmemiştir. Windows varsayılanı sürüme göre değişir; yalnızca önceki değer geri yüklenebilir.'
           Risk = 'Low'; Evidence = 'Community'; Sources = @($script:LtSrc.TcpSetting); Restart = 'None'
           Actions = @((New-LtTcpAction -Setting 'EcnCapability' -Value 'Disabled')) }

        @{ Id = 'net.rsc-off'; Page = 'Network'; Group = 'TCP/IP (genel)'
           Title = 'Receive Segment Coalescing (RSC) kapalı'
           Description = 'Gelen segmentlerin birleştirilmesini kapatır. CPU kullanımı artabilir; gecikme kazancı ağ kartına ve iş yüküne bağlıdır ve ölçülmemiştir.'
           Risk = 'Medium'; Evidence = 'Community'; Sources = @($script:LtSrc.TcpSetting); Restart = 'None'
           Actions = @((New-LtTcpAction -Setting 'Rsc' -Value 'Disabled' -Default 'Enabled')) }

        @{ Id = 'net.cubic'; Page = 'Network'; Group = 'TCP/IP (genel)'
           Title = 'Tıkanıklık denetimi: CUBIC'
           Description = 'Internet şablonunun tıkanıklık sağlayıcısını CUBIC yapar. Windows 10 1709 ve sonrası/Windows 11''de zaten varsayılandır; bu sistemlerde değişiklik yapılmaz.'
           Risk = 'Low'; Evidence = 'Documented'; Sources = @($script:LtSrc.Cubic); Restart = 'None'
           Actions = @((New-LtTcpAction -Setting 'CongestionProvider' -Value 'CUBIC')) }

        @{ Id = 'net.throttling-off'; Page = 'Network'; Group = 'TCP/IP (genel)'
           Title = 'NetworkThrottlingIndex kapalı (0xFFFFFFFF)'
           Description = 'MMCSS''in multimedya oynatımı sırasında ağ paket işlemeyi sınırlamasını kapatır (varsayılan 10). Yalnızca MMCSS etkin multimedya akışlarında fark yaratır.'
           Risk = 'Low'; Evidence = 'Community'; Sources = @($script:LtSrc.MMCSS); Restart = 'Reboot'
           Actions = @((New-LtRegAction -Path $MM -Name 'NetworkThrottlingIndex' -Value 0xFFFFFFFF -Default @('DWord', 10))) }

        @{ Id = 'net.ackfreq'; Page = 'Network'; Group = 'Gecikme (arayüz başına)'
           Title = 'TcpAckFrequency = 1 (gecikmeli ACK kapalı)'
           Description = 'Yalnızca seçilen fiziksel adaptörün TCP arayüzünde her segmenti anında onaylar. Microsoft ortam incelenmeden varsayılanın (2) değiştirilmesini önermez; ACK trafiği artar.'
           Risk = 'Medium'; Evidence = 'Documented'; Sources = @($script:LtSrc.AckFreq); Restart = 'Reboot'
           Supported = { param($c) Get-LtNicSelectionIssue $c }
           ActionsFrom = { param($c) @(foreach ($n in @((Get-LtSelectedNic $c))) { New-LtRegAction -Path "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$(([guid]([string]$n.InterfaceGuid)).ToString('B'))" -Name 'TcpAckFrequency' -Value 1 -Default 'Absent' }) } }

        @{ Id = 'nic.flowcontrol-off'; Page = 'Network'; Group = 'Adaptör (sürücü) ayarları'
           Title = 'Flow Control kapalı (*FlowControl = 0)'
           Description = 'Seçilen adaptörde duraklatma çerçevelerini kapatır (istemci varsayılanı 3 = Rx&Tx). Yoğun ağlarda paket kaybı artabilir. Tercih bağlantıyı yeniden başlatmadan kaydedilir. Etkinleşme için yeniden başlatma gerekir.'
           Risk = 'Medium'; Evidence = 'Documented'; Sources = @($script:LtSrc.NicEnum); Restart = 'Reboot'
           Warning = 'Otomatik adaptör yeniden başlatılmaz. Etkinleşme için yeniden başlatma gerekir.'
           Supported = { param($c) $n = Get-LtNicSelectionIssue $c; if ($n) { return $n }; if (@(New-LtNicActions -Ctx $c -Keywords @('*FlowControl') -Value '0').Count -eq 0) { 'Etkin adaptörlerde *FlowControl=0 desteklenmiyor.' } }
           ActionsFrom = { param($c) @(New-LtNicActions -Ctx $c -Keywords @('*FlowControl') -Value '0') } }

        @{ Id = 'nic.eee-off'; Page = 'Network'; Group = 'Adaptör (sürücü) ayarları'
           Title = 'Enerji Verimli Ethernet (EEE / Green Ethernet) kapalı'
           Description = 'Standart *EEE ve bilinen üretici anahtarlarını (EEE, EnableGreenEthernet) 0 yapar. Boşta güç tüketimi biraz artar. Tercih bağlantıyı yeniden başlatmadan kaydedilir. Etkinleşme için yeniden başlatma gerekir.'
           Risk = 'Low'; Evidence = 'Documented'; Sources = @($script:LtSrc.NicPower); Restart = 'Reboot'
           Warning = 'Otomatik adaptör yeniden başlatılmaz. Etkinleşme için yeniden başlatma gerekir.'
           Supported = { param($c) $n = Get-LtNicSelectionIssue $c; if ($n) { return $n }; if (@(New-LtNicActions -Ctx $c -Keywords @('*EEE', 'EEE', 'EnableGreenEthernet') -Value '0').Count -eq 0) { 'Etkin adaptörlerde EEE ayarı bulunamadı.' } }
           ActionsFrom = { param($c) @(New-LtNicActions -Ctx $c -Keywords @('*EEE', 'EEE', 'EnableGreenEthernet') -Value '0') } }

        @{ Id = 'nic.adaptiveifs-off'; Page = 'Network'; Group = 'Adaptör (sürücü) ayarları'
           Title = 'Adaptive Inter-Frame Spacing kapalı (Intel)'
           Description = 'Yalnızca AdaptiveIFS anahtarını sunan (çoğunlukla Intel) sürücülerde uygulanır. Kazanç ölçülmemiştir.'
           Risk = 'Low'; Evidence = 'Community'; Sources = @(); Restart = 'Reboot'
           Supported = { param($c) $n = Get-LtNicSelectionIssue $c; if ($n) { return $n }; if (@(New-LtNicActions -Ctx $c -Keywords @('AdaptiveIFS') -Value '0').Count -eq 0) { 'Etkin adaptörlerde AdaptiveIFS ayarı yok.' } }
           ActionsFrom = { param($c) @(New-LtNicActions -Ctx $c -Keywords @('AdaptiveIFS') -Value '0') } }

        @{ Id = 'dns.cloudflare'; Page = 'Network'; Group = 'DNS sunucusu (seçili adaptör)'; Exclusive = 'dns-provider'
           Title = 'DNS: Cloudflare (1.1.1.1)'
           Description = 'Seçili adaptörün DNS sunucularını Cloudflare yapar (IPv4 + IPv6). Ad çözümleme süresini ve DNS gizliliğini etkiler; oyun içi ping''i DEĞİŞTİRMEZ. Önce Ağ ölçümündeki DNS hız testine bakın. Kurumsal/okul ağlarında iç adlar çözülemeyebilir.'
           Risk = 'Low'; Evidence = 'Documented'; Sources = @('https://developers.cloudflare.com/1.1.1.1/ip-addresses/'); Restart = 'None'
           Supported = { param($c) Get-LtNicSelectionIssue $c }
           ActionsFrom = { param($c) @(New-LtDnsAction -Ctx $c -Provider Cloudflare) } }

        @{ Id = 'dns.google'; Page = 'Network'; Group = 'DNS sunucusu (seçili adaptör)'; Exclusive = 'dns-provider'
           Title = 'DNS: Google (8.8.8.8)'
           Description = 'Seçili adaptörün DNS sunucularını Google Public DNS yapar (IPv4 + IPv6). Oyun içi ping''i değiştirmez. Windows varsayılanına dönüş otomatik (DHCP) DNS''tir.'
           Risk = 'Low'; Evidence = 'Documented'; Sources = @('https://developers.google.com/speed/public-dns/docs/using'); Restart = 'None'
           Supported = { param($c) Get-LtNicSelectionIssue $c }
           ActionsFrom = { param($c) @(New-LtDnsAction -Ctx $c -Provider Google) } }

        @{ Id = 'dns.quad9'; Page = 'Network'; Group = 'DNS sunucusu (seçili adaptör)'; Exclusive = 'dns-provider'
           Title = 'DNS: Quad9 (9.9.9.9, zararlı alan adı engelleme)'
           Description = 'Seçili adaptörün DNS sunucularını Quad9 yapar; bilinen zararlı alan adlarını engeller. Oyun içi ping''i değiştirmez.'
           Risk = 'Low'; Evidence = 'Documented'; Sources = @('https://quad9.net/service/service-addresses-and-features/'); Restart = 'None'
           Supported = { param($c) Get-LtNicSelectionIssue $c }
           ActionsFrom = { param($c) @(New-LtDnsAction -Ctx $c -Provider Quad9) } }

        @{ Id = 'dns.llmnr-off'; Page = 'Network'; Group = 'Ad çözümleme'
           Title = 'LLMNR kapalı (Grup İlkesi)'
           Description = '"Çok noktaya yayın ad çözümlemesini kapat" ilkesi. Yerel ağda ad sahteciliği riskini azaltır; DNS''siz eski yerel ad çözümlemesi çalışmaz.'
           Risk = 'Low'; Evidence = 'Documented'; Sources = @(); Restart = 'None'
           Actions = @((New-LtRegAction -Path 'HKLM\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' -Name 'EnableMulticast' -Value 0 -Default 'Absent')) }

        @{ Id = 'dns.mdns-off'; Page = 'Network'; Group = 'Ad çözümleme'
           Title = 'mDNS kapalı'
           Description = 'DNS İstemcisi''nin mDNS yanıtlayıcısını kapatır. Chromecast, akıllı TV ve ağ yazıcısı keşfi çalışmayabilir.'
           Risk = 'Medium'; Evidence = 'Community'; Sources = @(); Restart = 'Reboot'
           Actions = @((New-LtRegAction -Path 'HKLM\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters' -Name 'EnableMDNS' -Value 0 -Default 'Absent')) }

        # =====================================================================
        # GUVENLIK VE GIRIS (Kernel & Input)
        # =====================================================================
        @{ Id = 'sec.vbs-off'; Page = 'Kernel'; Group = 'Güvenlik özellikleri (ileri düzey)'
           Title = 'Sanallaştırma Tabanlı Güvenlik (VBS) kapalı'
           Description = 'EnableVirtualizationBasedSecurity=0. Kimlik Bilgisi Koruması, HVCI gibi VBS tabanlı korumalar çalışmaz. UEFI kilitli yapılandırmada registry ile kapatılamaz.'
           Risk = 'Security'; Evidence = 'Documented'; Sources = @($script:LtSrc.Hvci); Restart = 'Reboot'
           Warning = 'GÜVENLİĞİ AZALTIR: çekirdek düzeyi saldırılara karşı koruma kapanır.'
           Supported = { param($c)
               $l = Get-LtRegValue 'HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'Locked'
               if ($l.Exists -and [long]$l.Data -eq 1) { return 'VBS UEFI kilidiyle yapılandırılmış; registry ile kapatılamaz.' }
               $p = Get-LtRegValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard' 'EnableVirtualizationBasedSecurity'
               if ($p.Exists) { return 'VBS Grup İlkesi/MDM ile yönetiliyor; önce ilkeyi değiştirin.' } }
           Actions = @((New-LtRegAction -Path $DG -Name 'EnableVirtualizationBasedSecurity' -Value 0)) }

        @{ Id = 'sec.hvci-off'; Page = 'Kernel'; Group = 'Güvenlik özellikleri (ileri düzey)'
           Title = 'Bellek Bütünlüğü (HVCI) kapalı'
           Description = 'Scenarios\HypervisorEnforcedCodeIntegrity\Enabled=0 (Microsoft''un belgelediği kapatma yöntemi). Çekirdek sürücü kod bütünlüğü koruması kapanır.'
           Risk = 'Security'; Evidence = 'Documented'; Sources = @($script:LtSrc.Hvci); Restart = 'Reboot'
           Warning = 'GÜVENLİĞİ AZALTIR: zararlı/imzasız çekirdek kodu yüklenmesi kolaylaşır.'
           Supported = { param($c)
               $l = Get-LtRegValue 'HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Locked'
               if ($l.Exists -and [long]$l.Data -eq 1) { return 'HVCI UEFI kilidiyle yapılandırılmış; registry ile kapatılamaz.' } }
           Actions = @((New-LtRegAction -Path "$DG\Scenarios\HypervisorEnforcedCodeIntegrity" -Name 'Enabled' -Value 0)) }

        @{ Id = 'sec.spectre-off'; Page = 'Kernel'; Group = 'Güvenlik özellikleri (ileri düzey)'
           Title = 'Spectre v2 / Meltdown azaltmaları kapalı'
           Description = 'FeatureSettingsOverride=3, FeatureSettingsOverrideMask=3 (KB4072698). CVE-2017-5715 ve CVE-2017-5754 azaltmaları kapanır.'
           Risk = 'Security'; Evidence = 'Documented'; Sources = @($script:LtSrc.Spectre); Restart = 'Reboot'
           Warning = 'GÜVENLİĞİ AZALTIR: yan kanal saldırılarına karşı koruma kapanır.'
           Actions = @(
               (New-LtRegAction -Path $MEM -Name 'FeatureSettingsOverride' -Value 3 -Default 'Absent'),
               (New-LtRegAction -Path $MEM -Name 'FeatureSettingsOverrideMask' -Value 3 -Default 'Absent')
           ) }

        @{ Id = 'sec.cfg-off'; Page = 'Kernel'; Group = 'Güvenlik özellikleri (ileri düzey)'
           Title = 'Control Flow Guard (CFG) sistem genelinde kapalı'
           Description = 'Set-ProcessMitigation -System -Disable CFG. Eski sürüm yanlış biti (0x200 = zorunlu ASLR) değiştiriyordu; bu düzeltildi. Geri alma, MitigationOptions''ın özgün ham değerini geri yazar.'
           Risk = 'Security'; Evidence = 'Documented'; Sources = @($script:LtSrc.ProcMitig); Restart = 'Reboot'
           Warning = 'GÜVENLİĞİ AZALTIR: bellek bozulması açıklarının istismarı kolaylaşır.'
           Actions = @(@{ Type = 'Mitigation'; Name = 'CFG'; State = 'OFF'; Default = 'NOTSET' }) }

        @{ Id = 'mem.pagefile-auto'; Page = 'Kernel'; Group = 'Bellek'
           Title = 'Disk belleği (pagefile) boyutunu Windows yönetsin'
           Description = 'Win32_ComputerSystem.AutomaticManagedPagefile ile otomatik yönetimi açar. Otomatik yönetim durumu, tüm özel disk/boyut tanımları ve PagingFiles kaydı önce yedeklenir. Sonuç yapılandırmayı doğrular; etkin boyut için yeniden başlatma sonrası kontrol gerekir. FPS artışı vaat edilmez.'
           Risk = 'Medium'; Evidence = 'Documented'; Sources = @('https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-computersystem', 'https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-pagefilesetting'); Restart = 'Reboot'
           Supported = {
               param($ctx)
               $legacy = @(Get-LtLedgerEntries | Where-Object { @($_.tweakIds) -contains 'mem.pagefile-auto' -and $_.action.Type -eq 'Registry' })
               if ($legacy.Count -gt 0) { return 'Eski pagefile işlem kaydı var. Önce Önceki ayara dön işlemini tamamlayın; ardından yeni sağlayıcıyla tekrar uygulayın.' }
               return $null
           }
           Actions = @(@{ Type = 'Pagefile' }) }


        @{ Id = 'mem.clear-pagefile'; Page = 'Kernel'; Group = 'Bellek'
           Title = 'Kapanışta disk belleğini temizle'
           Description = 'Güvenlik ilkesi "Kapat: Sanal bellek disk belleği dosyasını temizle". Gizliliği artırır, kapanma süresi uzar.'
           Risk = 'Low'; Evidence = 'Documented'; Sources = @(); Restart = 'Reboot'
           Actions = @((New-LtRegAction -Path $MEM -Name 'ClearPageFileAtShutdown' -Value 1 -Default @('DWord', 0))) }

        @{ Id = 'input.mouse-accel-off'; Page = 'Kernel'; Group = 'Fare'
           Title = 'Fare ivmesini kapat'
           Description = 'SPI_SETMOUSE ile iki eşik ve ivmeyi 0 yapar; SPI_GETMOUSE ile oturumda yeniden okur. İşaretçi hızını veya oyunların raw input tercihini değiştirmez. Önceki oturum değerleri ve registry kayıtları ayrı saklanır.'
           Risk = 'Low'; Evidence = 'Documented'; Sources = @('https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-systemparametersinfow'); Restart = 'None'
           Supported = { param($c) Get-LtUserParameterSupport 'input.mouse-accel-off' }
           Actions = @(@{ Type='UserParameter'; Setting='Mouse'; Values=@(0,0,0) }) }

        # =====================================================================
        # GPU & MSI
        # =====================================================================
        # IDs remain available so existing ledger/journal entries can be reverted.
        # No new registry writes until device support can be verified reliably.
        @{ Id = 'gpu.app-high-perf'; Page = 'GPU'; Group = 'Oyun GPU tercihi'
           Title = 'Seçili oyunlar yüksek performanslı ekran kartını kullansın'
           Description = 'Ayarlar > Grafik''teki uygulama başına "Yüksek performans" tercihini, aşağıdan eklediğiniz oyunlar için yazar. Dahili + harici GPU''lu dizüstülerde oyunun dahili GPU''da kalmasını önler. Tek GPU''lu sistemlerde gerekmez.'
           Risk = 'Low'; Evidence = 'Community'; Sources = @('https://elevenforum.com/t/change-graphics-performance-preference-for-apps-in-windows-11.5675/'); Restart = 'None'
           Supported = { param($c)
               if (@(Get-LtProp $c 'GpuPreferenceApps' @()).Count -eq 0) { return 'Önce GPU sayfasında "Oyun ekle…" ile oyunun .exe dosyasını seçin.' }
               if (@(Get-LtProp $c 'Gpus' @()).Count -lt 2) { return 'Bu sistemde tek ekran kartı algılandı; uygulama başına GPU tercihi gerekmez.' }
               $null }
           ActionsFrom = { param($c) @(New-LtGpuPreferenceActions -Ctx $c) } }

        @{ Id = 'gpu.hags'; Page = 'GPU'; Group = 'Grafik'
           Title = 'Donanım hızlandırmalı GPU zamanlaması (HAGS) açık'
           Description = 'HwSchMode=2 tercihini yazar (Ayarlar > Grafik''teki anahtarla aynı kayıt). Windows bunu yalnız ekran sürücüsü destekliyorsa etkinleştirir; destek sürücüye sorularak kontrol edilir. Yeniden başlatmadan sonra etkin durumu "oku" düğmesiyle veya Windows Grafik Ayarları''ndan doğrulayın. Kazanç oyuna ve sürücüye göre değişir; ölçmeden varsayılmaz.'
           Risk = 'Medium'; Evidence = 'Documented'; Sources = @($script:LtSrc.Hags); Restart = 'Reboot'
           Supported = { param($c)
               if ([int](Get-LtProp $c 'Build' 0) -lt 19041) { return 'HAGS için Windows 10 2004 (derleme 19041) veya sonrası gerekir.' }
               $h = Get-LtProp $c 'Hags' $null
               if ($h -and ($false -eq (Get-LtProp $h 'Supported' $null))) { return 'Ekran sürücüsü HAGS desteği bildirmiyor. Sürücüyü güncelledikten sonra yeniden deneyin.' }
               $null }
           Actions = @((New-LtRegAction -Path 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'HwSchMode' -Value 2 -Default 'Absent')) }

        @{ Id = 'msi.gpu'; Page = 'GPU'; Group = 'MSI (Message Signaled Interrupts)'
           Title = 'Seçili ekran kartında MSI kesme modu tercihi'
           Description = 'Listeden seçilen ekran kartı için MSISupported=1 tercihini yazar. Yalnız aygıt donanım olarak MSI/MSI-X bildiriyorsa etkinleşir. Güncel NVIDIA/AMD sürücülerinin çoğu MSI''yi zaten kullanır; bu durumda değişiklik görünmez. Sürücü güncellemesi tercihi sıfırlayabilir.'
           Risk = 'High'; Evidence = 'Documented'; Sources = @($script:LtSrc.Msi); Restart = 'Reboot'
           Warning = 'Sürücüsü MSI ile sorun yaşayan aygıt açılışta çalışmayabilir. Sorun olursa Güvenli Mod''da "Önceki ayara dön" ile geri alın.'
           Supported = { param($c) Get-LtMsiSupportIssue -Ctx $c -Class GPU }
           ActionsFrom = { param($c) @(New-LtMsiAction -Ctx $c -Class GPU) } }

        @{ Id = 'msi.nic'; Page = 'GPU'; Group = 'MSI (Message Signaled Interrupts)'
           Title = 'Seçili ağ kartında MSI kesme modu tercihi'
           Description = 'Listeden seçilen ağ kartı için MSISupported=1 tercihini yazar. Yalnız aygıt donanım olarak MSI/MSI-X bildiriyorsa etkinleşir. Çoğu modern ağ sürücüsü MSI/MSI-X''i zaten kullanır.'
           Risk = 'High'; Evidence = 'Documented'; Sources = @($script:LtSrc.Msi); Restart = 'Reboot'
           Warning = 'Sorunlu sürücüde ağ bağlantısı açılışta gelmeyebilir. Sorun olursa "Önceki ayara dön" ile geri alın.'
           Supported = { param($c) Get-LtMsiSupportIssue -Ctx $c -Class NIC }
           ActionsFrom = { param($c) @(New-LtMsiAction -Ctx $c -Class NIC) } }

        # =====================================================================
        # GIZLILIK
        # =====================================================================
        @{ Id = 'priv.diagtrack-off'; Page = 'Privacy'; Group = 'Servisler'
           Title = 'Bağlı Kullanıcı Deneyimleri ve Telemetri (DiagTrack) kapalı'
           Description = 'DiagTrack servisini devre dışı bırakır. Tanılama verisi yüklemesi durur; Geri Bildirim Merkezi/Insider özellikleri etkilenebilir.'
           Risk = 'Low'; Evidence = 'Community'; Sources = @(); Restart = 'None'
           Actions = @((New-LtServiceAction -Name 'DiagTrack' -StartType 'Disabled' -Default 'Automatic' -Stop)) }

        @{ Id = 'priv.dmwappush-off'; Page = 'Privacy'; Group = 'Servisler'
           Title = 'dmwappushservice kapalı'
           Description = 'WAP anında ileti yönlendirme servisini kapatır. MDM (Intune vb.) ile yönetilen cihazlarda KULLANMAYIN.'
           Risk = 'Medium'; Evidence = 'Community'; Sources = @(); Restart = 'None'
           Actions = @((New-LtServiceAction -Name 'dmwappushservice' -StartType 'Disabled' -Default 'Manual' -Stop)) }

        @{ Id = 'priv.xbox-off'; Page = 'Privacy'; Group = 'Servisler'
           Title = 'Xbox Live servisleri kapalı'
           Description = 'XblAuthManager, XblGameSave, XboxNetApiSvc devre dışı. Game Pass/Xbox uygulaması oyunları ve bulut kayıtları çalışmaz. Xbox aksesuar servisi (XboxGipSvc) kumandaları etkilediği için değiştirilmez.'
           Risk = 'Medium'; Evidence = 'Community'; Sources = @(); Restart = 'None'
           Actions = @(
               (New-LtServiceAction -Name 'XblAuthManager' -StartType 'Disabled' -Default 'Manual' -Stop),
               (New-LtServiceAction -Name 'XblGameSave' -StartType 'Disabled' -Default 'Manual' -Stop),
               (New-LtServiceAction -Name 'XboxNetApiSvc' -StartType 'Disabled' -Default 'Manual' -Stop)
           ) }

        @{ Id = 'priv.telemetry-min'; Page = 'Privacy'; Group = 'İlkeler'
           Title = 'Tanılama verisi: en düşük izin verilen düzey'
           Description = 'AllowTelemetry ilkesi. Enterprise/Education/Server''da 0 (Güvenlik) yazılır; Home/Pro''da Microsoft 0''ı 1 (Gerekli) olarak uyguladığı için doğrudan 1 yazılır.'
           Risk = 'Low'; Evidence = 'Documented'; Sources = @($script:LtSrc.Telemetry); Restart = 'None'
           ActionsFrom = { param($c)
               $v = 1; if ($c.IsServer -or (Test-LtEditionIn $c @('Enterprise*', 'Education*', 'IoTEnterprise*'))) { $v = 0 }
               @(New-LtRegAction -Path 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Name 'AllowTelemetry' -Value $v -Default 'Absent') } }

        @{ Id = 'priv.appcompat'; Page = 'Privacy'; Group = 'İlkeler'
           Title = 'Uygulama telemetrisi ve Envanter Toplayıcı kapalı'
           Description = 'AITEnable=0 ve DisableInventory=1 ilkeleri. (Eski sürümdeki "DisableProgramTelemetry" geçerli bir ilke değildi; kaldırıldı.)'
           Risk = 'Low'; Evidence = 'Documented'; Sources = @(); Restart = 'None'
           Actions = @(
               (New-LtRegAction -Path 'HKLM\SOFTWARE\Policies\Microsoft\Windows\AppCompat' -Name 'AITEnable' -Value 0 -Default 'Absent'),
               (New-LtRegAction -Path 'HKLM\SOFTWARE\Policies\Microsoft\Windows\AppCompat' -Name 'DisableInventory' -Value 1 -Default 'Absent')
           ) }

        @{ Id = 'priv.wer-off'; Page = 'Privacy'; Group = 'İlkeler'
           Title = 'Windows Hata Raporlama kapalı'
           Description = 'Windows Error Reporting\Disabled=1. Çökme raporları Microsoft''a gönderilmez; uygulama sorunlarının çözümü zorlaşabilir.'
           Risk = 'Low'; Evidence = 'Documented'; Sources = @(); Restart = 'None'
           Actions = @((New-LtRegAction -Path 'HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting' -Name 'Disabled' -Value 1 -Default 'Absent')) }

        @{ Id = 'priv.activity-off'; Page = 'Privacy'; Group = 'İlkeler'
           Title = 'Etkinlik geçmişi kapalı'
           Description = 'EnableActivityFeed=0, PublishUserActivities=0, UploadUserActivities=0 ilkeleri.'
           Risk = 'Low'; Evidence = 'Documented'; Sources = @(); Restart = 'None'
           Actions = @(
               (New-LtRegAction -Path 'HKLM\SOFTWARE\Policies\Microsoft\Windows\System' -Name 'EnableActivityFeed' -Value 0 -Default 'Absent'),
               (New-LtRegAction -Path 'HKLM\SOFTWARE\Policies\Microsoft\Windows\System' -Name 'PublishUserActivities' -Value 0 -Default 'Absent'),
               (New-LtRegAction -Path 'HKLM\SOFTWARE\Policies\Microsoft\Windows\System' -Name 'UploadUserActivities' -Value 0 -Default 'Absent')
           ) }

        @{ Id = 'priv.cortana-off'; Page = 'Privacy'; Group = 'İlkeler'
           Title = 'Cortana kapalı (ilke)'
           Description = 'AllowCortana=0. Yeni Windows 11 sürümlerinde Cortana kaldırıldığından etkisi olmayabilir.'
           Risk = 'Low'; Evidence = 'Documented'; Sources = @(); Restart = 'None'
           Actions = @((New-LtRegAction -Path 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search' -Name 'AllowCortana' -Value 0 -Default 'Absent')) }

        @{ Id = 'priv.ceip-off'; Page = 'Privacy'; Group = 'İlkeler'
           Title = 'Müşteri Deneyimini Geliştirme Programı (CEIP) kapalı'
           Description = 'SQMClient\Windows\CEIPEnable=0 ilkesi.'
           Risk = 'Low'; Evidence = 'Documented'; Sources = @(); Restart = 'None'
           Actions = @((New-LtRegAction -Path 'HKLM\SOFTWARE\Policies\Microsoft\SQMClient\Windows' -Name 'CEIPEnable' -Value 0 -Default 'Absent')) }

        @{ Id = 'priv.consumer-off'; Page = 'Privacy'; Group = 'İlkeler'
           Title = 'Microsoft tüketici deneyimleri kapalı'
           Description = 'DisableWindowsConsumerFeatures=1. Microsoft bu ilkeyi yalnızca Enterprise/Education/IoT Enterprise''da destekler.'
           Risk = 'Low'; Evidence = 'Documented'; Sources = @($script:LtSrc.Consumer); Restart = 'None'
           Supported = { param($c) if (-not ($c.IsServer -or (Test-LtEditionIn $c @('Enterprise*', 'Education*', 'IoTEnterprise*')))) { "Bu ilke $($c.EditionId) sürümünde desteklenmez (yalnızca Enterprise/Education)." } }
           Actions = @((New-LtRegAction -Path 'HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name 'DisableWindowsConsumerFeatures' -Value 1 -Default 'Absent')) }

        @{ Id = 'priv.adid-off'; Page = 'Privacy'; Group = 'Kullanıcı ayarları'
           Title = 'Reklam kimliği kapalı'
           Description = 'Ayarlar > Gizlilik > Genel''deki reklam kimliği anahtarı (bu kullanıcı).'
           Risk = 'Low'; Evidence = 'Community'; Sources = @(); Restart = 'None'
           Actions = @((New-LtRegAction -Path 'HKCU\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' -Name 'Enabled' -Value 0)) }

        @{ Id = 'priv.tailored-off'; Page = 'Privacy'; Group = 'Kullanıcı ayarları'
           Title = 'Uyarlanmış deneyimler kapalı'
           Description = 'Tanılama verisine dayalı kişiselleştirilmiş ipuçları/reklamlar (bu kullanıcı).'
           Risk = 'Low'; Evidence = 'Community'; Sources = @(); Restart = 'None'
           Actions = @((New-LtRegAction -Path 'HKCU\Software\Microsoft\Windows\CurrentVersion\Privacy' -Name 'TailoredExperiencesWithDiagnosticDataEnabled' -Value 0)) }

        @{ Id = 'priv.inking-off'; Page = 'Privacy'; Group = 'Kullanıcı ayarları'
           Title = 'Mürekkep ve yazma kişiselleştirmesi kapalı'
           Description = 'Örtük mürekkep/metin toplama ve kişi toplama kapatılır (bu kullanıcı).'
           Risk = 'Low'; Evidence = 'Community'; Sources = @(); Restart = 'None'
           Actions = @(
               (New-LtRegAction -Path 'HKCU\Software\Microsoft\InputPersonalization' -Name 'RestrictImplicitInkCollection' -Value 1),
               (New-LtRegAction -Path 'HKCU\Software\Microsoft\InputPersonalization' -Name 'RestrictImplicitTextCollection' -Value 1),
               (New-LtRegAction -Path 'HKCU\Software\Microsoft\InputPersonalization\TrainedDataStore' -Name 'HarvestContacts' -Value 0),
               (New-LtRegAction -Path 'HKCU\Software\Microsoft\Personalization\Settings' -Name 'AcceptedPrivacyPolicy' -Value 0)
           ) }

        @{ Id = 'priv.websearch-off'; Page = 'Privacy'; Group = 'Kullanıcı ayarları'
           Title = 'Başlat menüsünde Bing/web önerileri kapalı'
           Description = 'DisableSearchBoxSuggestions=1 (kullanıcı ilkesi) ve BingSearchEnabled=0. Explorer yeniden başlatılınca etkinleşir.'
           Risk = 'Low'; Evidence = 'Community'; Sources = @(); Restart = 'Explorer'
           Actions = @(
               (New-LtRegAction -Path 'HKCU\Software\Policies\Microsoft\Windows\Explorer' -Name 'DisableSearchBoxSuggestions' -Value 1 -Default 'Absent'),
               (New-LtRegAction -Path 'HKCU\Software\Microsoft\Windows\CurrentVersion\Search' -Name 'BingSearchEnabled' -Value 0 -Default 'Absent')
           ) }

        @{ Id = 'priv.suggestions-off'; Page = 'Privacy'; Group = 'Kullanıcı ayarları'
           Title = 'Önerilen uygulamalar ve sessiz uygulama yüklemeleri kapalı'
           Description = 'ContentDeliveryManager: SystemPaneSuggestionsEnabled, SilentInstalledAppsEnabled, SubscribedContent-338388Enabled = 0 (bu kullanıcı).'
           Risk = 'Low'; Evidence = 'Community'; Sources = @(); Restart = 'None'
           Actions = @(
               (New-LtRegAction -Path 'HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'SystemPaneSuggestionsEnabled' -Value 0),
               (New-LtRegAction -Path 'HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'SilentInstalledAppsEnabled' -Value 0),
               (New-LtRegAction -Path 'HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'SubscribedContent-338388Enabled' -Value 0)
           ) }

        # =====================================================================
        # WINDOWS AYARLARI
        # =====================================================================
        @{ Id = 'ui.animations-off'; Page = 'WinTweaks'; Group = 'Görsel'
           Title = 'Pencere küçültme/büyütme animasyonunu kapat'
           Description = 'SPI_SETANIMATION ile oturumda uygular ve API üzerinden yeniden okur. Yalnız pencere küçültme/büyütme animasyonunu kapsar; tüm uygulama animasyonlarını kapatmaz.'
           Risk = 'Low'; Evidence = 'Documented'; Sources = @('https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-systemparametersinfow'); Restart = 'None'
           Supported = { param($c) Get-LtUserParameterSupport 'ui.animations-off' }
           Actions = @(@{ Type='UserParameter'; Setting='Animation'; Values=@(0) }) }

        @{ Id = 'ui.effects-off'; Page = 'WinTweaks'; Group = 'Görsel'
           Title = 'Menü ve arayüz geçiş efektlerini azalt'
           Description = 'Menü, açılır liste, ipucu, seçim solması ve istemci alanı animasyonlarını Windows API ile kapatır. Yazı yumuşatma ve küçük resimleri korur. Performans Seçenekleri ekranındaki bütün kutuları kapattığı iddia edilmez.'
           Risk = 'Low'; Evidence = 'Documented'; Sources = @('https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-systemparametersinfow'); Restart = 'None'
           Supported = { param($c) Get-LtUserParameterSupport 'ui.effects-off' }
           Actions = @(@{ Type='UserParameter'; Setting='VisualEffects'; Values=@(0,0,0,0,0) }) }

        @{ Id = 'ui.taskbar-left'; Page = 'WinTweaks'; Group = 'Explorer'
           Title = 'Görev çubuğu simgelerini sola hizala'
           Description = 'Windows 11 görev çubuğu hizalaması; kullanıcı tercihi.'
           Risk = 'Low'; Evidence = 'Community'; Sources = @(); Restart = 'Explorer'
           Supported = { param($c) if (-not $c.IsWin11) { 'Windows 11 gerekli.' } }
           Actions = @((New-LtRegAction -Path $ADV -Name 'TaskbarAl' -Value 0 -Default @('DWord',1))) }

        @{ Id = 'ui.search-hide'; Page = 'WinTweaks'; Group = 'Explorer'
           Title = 'Görev çubuğundaki arama alanını gizle'
           Description = 'Arama hizmetini kapatmaz; yalnız görev çubuğu görünümünü değiştirir. Başlat menüsünden arama kullanılabilir.'
           Risk = 'Low'; Evidence = 'Community'; Sources = @('https://github.com/ChrisTitusTech/winutil/blob/main/config/tweaks.json'); Restart = 'Explorer'
           Actions = @((New-LtRegAction -Path 'HKCU\Software\Microsoft\Windows\CurrentVersion\Search' -Name 'SearchboxTaskbarMode' -Value 0 -Default 'Absent')) }

        @{ Id = 'ui.widgets-hide'; Page = 'WinTweaks'; Group = 'Explorer'
           Title = 'Widgets görev çubuğu simgesini gizle'
           Description = 'Windows 11 görev çubuğu simgesini gizler. Widgets paketini veya arka plan işlemlerini kaldırmaz; sürüm ve ilkelere göre görünüm değişebilir.'
           Risk = 'Low'; Evidence = 'Community'; Sources = @(); Restart = 'Explorer'
           Supported = { param($c)
               if (-not $c.IsWin11) { return 'Windows 11 gerekli.' }
               # UCPD (User Choice Protection Driver) etkinse TaskbarDa yazimi reddedilir
               $u = Get-LtServiceInfo -Name 'UCPD'
               if ($u.Exists -and $u.StartType -ne 'Disabled') { return 'Windows bu değeri koruyor (UCPD); yazım reddedilir. Yerine "Widgets kapalı (ilke)" seçeneğini kullanın.' }
               $null }
           Actions = @((New-LtRegAction -Path $ADV -Name 'TaskbarDa' -Value 0 -Default 'Absent')) }

        @{ Id = 'ui.widgets-off-policy'; Page = 'WinTweaks'; Group = 'Explorer'
           Title = 'Widgets kapalı (ilke)'
           Description = 'Windows 11 "Pencere öğelerine izin ver" ilkesini kapatır (AllowNewsAndInterests=0). Widgets panosu ve görev çubuğu simgesi kapanır; arka plan Widgets işlemleri başlamaz. Windows''un kullanıcı tercihi korumasından (UCPD) etkilenmez.'
           Risk = 'Low'; Evidence = 'Documented'; Sources = @('https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-newsandinterests'); Restart = 'Logoff'
           Supported = { param($c) if (-not $c.IsWin11) { 'Windows 11 gerekli.' } }
           Actions = @((New-LtRegAction -Path 'HKLM\SOFTWARE\Policies\Microsoft\Dsh' -Name 'AllowNewsAndInterests' -Value 0 -Default 'Absent')) }

        @{ Id = 'ui.end-task'; Page = 'WinTweaks'; Group = 'Explorer'
           Title = 'Görev çubuğunda Görevi sonlandır seçeneği'
           Description = 'Desteklenen Windows 11 sürümlerinde görev çubuğu sağ tık menüsüne Görevi sonlandır ekler. Kullanıldığında kaydedilmemiş çalışma kaybolabilir.'
           Risk = 'Low'; Evidence = 'Community'; Sources = @('https://github.com/builtbybel/FluentTweaker/blob/main/docs/features.md'); Restart = 'Explorer'
           Supported = { param($c) if (-not $c.IsWin11 -or $c.Build -lt 22631) { 'Windows 11 23H2 veya sonrası gerekli; gerçek menü davranışını kontrol edin.' } }
           Actions = @((New-LtRegAction -Path "$ADV\TaskbarDeveloperSettings" -Name 'TaskbarEndTask' -Value 1 -Default 'Absent')) }

        @{ Id = 'ui.taskbar-anim-off'; Page = 'WinTweaks'; Group = 'Görsel'
           Title = 'Görev çubuğu animasyonları kapalı'
           Description = 'Explorer\Advanced\TaskbarAnimations = 0.'
           Risk = 'Low'; Evidence = 'Community'; Sources = @(); Restart = 'Explorer'
           Actions = @((New-LtRegAction -Path $ADV -Name 'TaskbarAnimations' -Value 0 -Default 'Absent')) }

        @{ Id = 'ui.transparency-off'; Page = 'WinTweaks'; Group = 'Görsel'
           Title = 'Saydamlık efektleri kapalı'
           Description = 'Ayarlar > Kişiselleştirme > Renkler > Saydamlık efektleri.'
           Risk = 'Low'; Evidence = 'Community'; Sources = @(); Restart = 'None'
           Actions = @((New-LtRegAction -Path $PERS -Name 'EnableTransparency' -Value 0 -Default @('DWord', 1))) }

        @{ Id = 'ui.darkmode'; Page = 'WinTweaks'; Group = 'Görsel'
           Title = 'Koyu mod (uygulamalar ve sistem)'
           Description = 'AppsUseLightTheme=0, SystemUsesLightTheme=0.'
           Risk = 'Low'; Evidence = 'Community'; Sources = @(); Restart = 'None'
           Actions = @(
               (New-LtRegAction -Path $PERS -Name 'AppsUseLightTheme' -Value 0 -Default @('DWord', 1)),
               (New-LtRegAction -Path $PERS -Name 'SystemUsesLightTheme' -Value 0 -Default @('DWord', 1))
           ) }

        @{ Id = 'ui.jpeg-quality'; Page = 'WinTweaks'; Group = 'Görsel'
           Title = 'Masaüstü arka planı JPEG kalitesi %100'
           Description = 'JPEGImportQuality = 100. Bir sonraki arka plan ayarlanışında etkili olur.'
           Risk = 'Low'; Evidence = 'Community'; Sources = @(); Restart = 'None'
           Actions = @((New-LtRegAction -Path 'HKCU\Control Panel\Desktop' -Name 'JPEGImportQuality' -Value 100 -Default 'Absent')) }

        @{ Id = 'ui.menu-delay'; Page = 'WinTweaks'; Group = 'Explorer'
           Title = 'Alt menü gösterim gecikmesi (seçilen süre)'
           Description = 'Windows Ayarları sayfasındaki süreyi SPI_SETMENUSHOWDELAY ile uygular. Bu kişisel kullanım tercihidir; FPS kazancı değildir. Uygulamalar sistem tercihini farklı ele alabilir.'
           Risk = 'Low'; Evidence = 'Documented'; Sources = @('https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-systemparametersinfow'); Restart = 'None'
           Supported = {
               param($c)
               $reason = Get-LtUserParameterSupport 'ui.menu-delay'
               if ($reason) { return $reason }
               [void](Get-LtMenuDelayChoice $c)
           }
           ActionsFrom = { param($c) @(@{ Type='UserParameter'; Setting='MenuDelay'; Values=@((Get-LtMenuDelayChoice $c)) }) } }

        @{ Id = 'ui.show-ext'; Page = 'WinTweaks'; Group = 'Explorer'
           Title = 'Dosya uzantılarını göster'
           Description = 'HideFileExt = 0.'
           Risk = 'Low'; Evidence = 'Community'; Sources = @(); Restart = 'Explorer'
           Actions = @((New-LtRegAction -Path $ADV -Name 'HideFileExt' -Value 0 -Default @('DWord', 1))) }

        @{ Id = 'ui.explorer-thispc'; Page = 'WinTweaks'; Group = 'Explorer'
           Title = 'Explorer "Bu Bilgisayar" ile açılsın'
           Description = 'LaunchTo = 1.'
           Risk = 'Low'; Evidence = 'Community'; Sources = @(); Restart = 'None'
           Actions = @((New-LtRegAction -Path $ADV -Name 'LaunchTo' -Value 1 -Default 'Absent')) }

        @{ Id = 'ui.classic-context'; Page = 'WinTweaks'; Group = 'Explorer'
           Title = 'Klasik sağ tık menüsü (Windows 11)'
           Description = 'HKCU\Software\Classes\CLSID\{86ca1aa0-...}\InprocServer32 boş varsayılan değer. Geri alındığında oluşturulan anahtarlar da silinir.'
           Risk = 'Low'; Evidence = 'Community'; Sources = @(); Restart = 'Explorer'
           Supported = { param($c) if (-not $c.IsWin11) { 'Yalnızca Windows 11''de anlamlıdır.' } }
           Actions = @((New-LtRegAction -Path 'HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' -Name '' -Kind String -Value '' -Default 'Absent')) }

        @{ Id = 'ui.numlock'; Page = 'WinTweaks'; Group = 'Explorer'
           Title = 'NumLock oturum açılışında açık'
           Description = 'InitialKeyboardIndicators = 2 (bu kullanıcı).'
           Risk = 'Low'; Evidence = 'Community'; Sources = @(); Restart = 'Logoff'
           Actions = @((New-LtRegAction -Path 'HKCU\Control Panel\Keyboard' -Name 'InitialKeyboardIndicators' -Kind String -Value '2')) }

        @{ Id = 'sys.longpaths'; Page = 'WinTweaks'; Group = 'Sistem'
           Title = 'Uzun yol desteği (260 karakter sınırı)'
           Description = 'LongPathsEnabled = 1. Uygulamanın da uzun yolları desteklemesi gerekir.'
           Risk = 'Low'; Evidence = 'Documented'; Sources = @($script:LtSrc.LongPath); Restart = 'None'
           Actions = @((New-LtRegAction -Path 'HKLM\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -Value 1 -Default @('DWord', 0))) }

        @{ Id = 'sys.bsod-detail'; Page = 'WinTweaks'; Group = 'Sistem'
           Title = 'Mavi ekranda otomatik yeniden başlatma kapalı + parametreleri göster'
           Description = 'AutoReboot = 0, DisplayParameters = 1. Çökmede bilgisayar mavi ekranda kalır; uzaktan/sunucu kullanımda uygun değildir.'
           Risk = 'Medium'; Evidence = 'Documented'; Sources = @($script:LtSrc.CrashDump); Restart = 'Reboot'
           Actions = @(
               (New-LtRegAction -Path $CC -Name 'AutoReboot' -Value 0 -Default @('DWord', 1)),
               (New-LtRegAction -Path $CC -Name 'DisplayParameters' -Value 1 -Default 'Absent')
           ) }

        @{ Id = 'sys.crashdump-full'; Page = 'WinTweaks'; Group = 'Sistem'
           Title = 'Tam bellek dökümü (Complete memory dump)'
           Description = 'CrashDumpEnabled = 1. Sayfa dosyası en az RAM + 257 MB olmalıdır; aksi halde döküm yazılamaz. Diskte RAM boyutu kadar yer kaplar.'
           Risk = 'Medium'; Evidence = 'Documented'; Sources = @($script:LtSrc.CrashDump); Restart = 'Reboot'
           Actions = @((New-LtRegAction -Path $CC -Name 'CrashDumpEnabled' -Value 1 -Default @('DWord', 7))) }

        @{ Id = 'sys.eventlog-size'; Page = 'WinTweaks'; Group = 'Sistem'
           Title = 'Olay günlüğü boyutu: Application/System/Security en az 100 MB'
           Description = 'wevtutil ile en büyük boyutu ayarlar; mevcut boyut zaten büyükse değiştirilmez.'
           Risk = 'Low'; Evidence = 'Documented'; Sources = @(); Restart = 'None'
           Actions = @(
               @{ Type = 'EventLogSize'; Log = 'Application'; Bytes = 104857600 },
               @{ Type = 'EventLogSize'; Log = 'System'; Bytes = 104857600 },
               @{ Type = 'EventLogSize'; Log = 'Security'; Bytes = 104857600 }
           ) }

        @{ Id = 'sys.hibernate-off'; Page = 'WinTweaks'; Group = 'Sistem'
           Title = 'Hazırda bekletmeyi kapat (hiberfil.sys silinir)'
           Description = 'powercfg /hibernate off. Hızlı Başlangıç da kapanır. Önceki ayara dönüş dosya türünü ve boyut tercihini geri yükler; silinen hazırda bekletme oturumunun içeriğini kurtarmaz.'
           Risk = 'Low'; Evidence = 'Documented'; Sources = @($script:LtSrc.Powercfg); Restart = 'None'
           Supported = { param($c)
               $legacy = @(Get-LtLedgerEntries | Where-Object { $_.key -eq 'Hibernate|System' -and (Get-LtProp $_.original 'Version') -ne 2 })
               if ($legacy.Count -gt 0) { return 'Eski hazirda bekletme kaydi dosya turunu ve boyutunu icermiyor. Kayit korunuyor; yeni islemden once mevcut yapilandirma elle incelenmeli.' }
           }
           Actions = @(@{ Type = 'Hibernate'; Enabled = $false }) }
    )
    return $defs
}

# ---------------------------------------------------------------------------
# PRESETLER — yalnizca SECIM yapar; kullanici onizleyip onayladiktan sonra uygulanir.
# Risk = 'Security' ve 'High' riskli (disabledynamictick, MSI) ogeler Standard'a girmez;
# Security hicbir presete girmez (test ile dogrulanir).
# ---------------------------------------------------------------------------
function Get-LtPresets {
    <#
      Hazir secimler yalnizca ISARETLER; uygulama her zaman onizleme + onayla yapilir.
      OneOf: listedeki ilk DESTEKLENEN ayar secilir (ornek: guc plani tercih sirasi).
      Kurallar (testle zorunlu): hicbir hazir secim guvenlik azaltmasi (Security),
      yuksek riskli (High) veya kaniti dogrulanmamis (Unverified) ayar icermez;
      Windows Update, MSI, servis kapatma ve pagefile elle secilir.
    #>
    $maxPerfIds = @('timer.platformclock-default', 'timer.global-resolution', 'sched.mmcss-games', 'sched.win32prio-26', 'game.mode',
                    'net.autotuning-normal', 'net.cubic', 'net.throttling-off', 'nic.flowcontrol-off', 'nic.eee-off', 'gpu.hags',
                    'input.mouse-accel-off', 'ui.animations-off', 'ui.effects-off', 'ui.taskbar-anim-off', 'ui.transparency-off')
    $powerOrder = @(, @('power.bitsum', 'power.ultimate', 'power.highperf'))
    return [ordered]@{
        Gamer = @{ Title = 'Oyuncu modu'
            Description = 'Oyun için hazırlık: Maksimum performans''taki tüm ayarlar + arka plan oyun kaydı kapalı + eklediğiniz oyunlar için yüksek performanslı GPU. Tek ağ adaptörü varsa otomatik hedeflenir ve önizleme doğrudan açılır. Güvenlik azaltması, servis kapatma, MSI ve DNS değişikliği İÇERMEZ (DNS oyun içi ping''i değiştirmez). FPS/ping kazancı vaat edilmez; önce–sonra ölçün.'
            OneOf = $powerOrder
            Ids = @($maxPerfIds + @('game.bgrecord-off', 'gpu.app-high-perf')) }
        Minimal = @{ Title = 'Temel'
            Description = 'Düşük riskli temel düzeltmeler: Oyun Modu, zorlanmış platform saatini kaldırma, TCP otomatik ayar ve CUBIC (Windows varsayılanları), dosya uzantıları, uzun yollar.'
            Ids = @('game.mode', 'timer.platformclock-default', 'net.autotuning-normal', 'net.cubic', 'ui.show-ext', 'sys.longpaths') }
        Standard = @{ Title = 'Gizlilik'
            Description = 'Telemetri servisi ve ilkeleri, etkinlik geçmişi, reklam/öneri ve Bing araması tercihleri. Performans vaadi içermez.'
            Ids = @('priv.diagtrack-off', 'priv.telemetry-min', 'priv.appcompat', 'priv.activity-off', 'priv.cortana-off', 'priv.ceip-off', 'priv.consumer-off', 'priv.adid-off', 'priv.tailored-off', 'priv.inking-off', 'priv.websearch-off', 'priv.suggestions-off') }
        Aggressive = @{ Title = 'Görünüm'
            Description = 'Koyu tema, dosya uzantıları, Explorer "Bu Bilgisayar", klasik sağ tık menüsü (Win11), arama simgesini gizleme, Widgets (simge gizleme; Windows bunu koruyorsa Widgets ilkesi), görev çubuğunda Görevi sonlandır.'
            OneOf = @(, @('ui.widgets-hide', 'ui.widgets-off-policy'))
            Ids = @('ui.darkmode', 'ui.show-ext', 'ui.explorer-thispc', 'ui.classic-context', 'ui.search-hide', 'ui.end-task') }
        Responsive = @{ Title = 'Akıcı görünüm'
            Description = 'Animasyonlar ve saydamlık kapalı; yazı yumuşatma ve küçük resimler korunur.'
            Ids = @('ui.animations-off', 'ui.effects-off', 'ui.taskbar-anim-off', 'ui.transparency-off') }
        MaxPerformance = @{ Title = 'Maksimum performans'
            Description = 'Güç planı (Bitsum > Nihai > Yüksek Performans, ilk desteklenen), zamanlayıcı/MMCSS/öncelik, Oyun Modu, ağ kısıtlaması, HAGS, seçili adaptörde akış denetimi/EEE, fare ivmesi ve animasyonlar. Dizüstünde pil süresini ve ısıyı artırır. Güvenlik azaltması, servis kapatma, MSI ve yüksek riskli ayar İÇERMEZ. FPS kazancı vaat edilmez; önce–sonra ölçün.'
            OneOf = $powerOrder
            Ids = $maxPerfIds }
    }
}
