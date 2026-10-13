## Grafik/MSI incelemesi — devam eden geliştirme

- Önceki D3DKMT_WDDM_2_7_CAPS önerisi yeniden değerlendirildi: Microsoft sayfası "Reserved for system use. Do not use." diyor. Bu nedenle destek tespiti için üretim API'si olarak eklenmedi.
- Yeni HAGS registry zorlaması kapalı. Windows Grafik Ayarları düğmesi eklendi; bu ekranda yapılan değişiklikler uygulamanın ledger kapsamı dışında. Memory modunda düğmenin motor işlevi de işlem başlatmaz.
- MSI için tek GPU/NIC seçilerek yalnızca mevcut MSISupported değeri okunur. Değer 1 olsa bile sürücü desteği/etkin MSI doğrulanmış sayılmaz. Destek doğrulanamadığı için yeni MSI zorlaması kapalı; bu işlevin tamamlandığı iddia edilmiyor.
- gpu.hags, msi.gpu ve msi.nic kimlikleri korunuyor. Eski ledger/journal içindeki Registry eylemleri Değişiklik Geçmişi üzerinden geri alınabilir.
- 8 regresyon testi eklendi. PowerShell/Pester/PSScriptAnalyzer ve WPF/Windows çalıştırılmadı. XML, kontrol adları, kodlama, katalog/manifest tutarlılığı statik olarak kontrol edildi.
- Windows kontrolü: panel/tek aygıt seçimi, hata durumunda eski sonucun temizlenmesi, Memory modunda Ayarlar açılmaması ve eski HAGS/MSI kayıtlarının geri alınması.
- Kaynaklar: https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/d3dkmdt/ns-d3dkmdt-d3dkmt_wddm_2_7_caps ; https://learn.microsoft.com/en-us/windows/apps/develop/launch/launch-settings ; https://learn.microsoft.com/en-us/windows-hardware/drivers/kernel/enabling-message-signaled-interrupts-in-the-registry
- Ara ZIP/bundle üretilmedi; kullanıcı isteğiyle çalışma aynı dalda sürüyor.

# Ayar (tweak) teknik denetimi

Bu belge v3.5'teki her optimizasyon seçeneğinin v4'teki karşılığını, kararın
gerekçesini ve kaynağını listeler. Kodla tek kaynak: `src/Catalog/Tweaks.ps1`
(her ayarın `Evidence` ve `Sources` alanları bu tabloyla aynıdır).

**Kanıt düzeyleri**

| Düzey | Anlamı |
|---|---|
| Belgelenmiş | Microsoft (veya ilgili üretici) birincil kaynağında konumu ve anlamı tanımlı. |
| Topluluk | Birincil kaynak bulunamadı; yaygın ve tutarlı topluluk bilgisi var. Arayüzde "Topluluk bilgisi" olarak etiketlenir. |
| Doğrulanmamış fayda | Ayarın kendisi geçerli, ancak performans faydası için ölçüm/kaynak yok. |

**Genel ilke:** Hiçbir açıklama ölçüm olmadan FPS veya gecikme kazancı vaat etmez.
Güvenlik özelliklerini kapatan seçenekler (Risk = Security) hiçbir hazır seçime
giremez (Pester testi ile zorunlu) ve açık onay kutusu olmadan uygulanamaz.

Denetim tarihi: 2026-09-24. Erişilemeyen kaynaklar "doğrulanamadı" olarak işaretlenmiştir.

## Performans

| v3.5 seçeneği | v4 kimliği | Karar | Gerekçe | Kaynak |
|---|---|---|---|---|
| HPET Devre Dışı (bcdedit) | `timer.platformclock-default` | **Düzeltildi** | Eski kod `useplatformclock false` + `disabledynamictick yes` + `deletevalue useplatformtick` yapıyordu ve `bcdedit /enum {current}` tırnaksız olduğu için PowerShell'de hatalı çalışıyordu. Microsoft `useplatformclock`/`useplatformtick` için "yalnızca hata ayıklama" der; doğru "HPET'i zorlamama" hâli bu değerlerin **silinmesidir** (Windows varsayılanı). Okuma HKLM\BCD00000000 kovanından (yerelleştirmeden bağımsız), yazma bcdedit (çıkış kodu denetimli). Bu öğeler BitLocker doğrulama profilinde değil. | [bcdedit /set](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/bcdedit--set), [BCD ve BitLocker](https://learn.microsoft.com/en-us/windows/security/operating-system-security/data-protection/bitlocker/bcd-settings-and-bitlocker) |
| (HPET içinde gizli) disabledynamictick | `timer.dynamictick-off` | **Ayrıldı, Yüksek risk** | Microsoft: yalnızca hata ayıklama için. Güç tüketimini artırır. Hazır seçimlere dahil değil. | aynı |
| Timer Resolution 0.5ms | `timer.global-resolution` | **Düzeltildi ve yeniden adlandırıldı** | `GlobalTimerResolutionRequests=1` çözünürlüğü 0,5 ms YAPMAZ; yalnızca Win10 2004 öncesi "global istek" davranışını geri getirir ve yalnızca Windows 11 / Server 2022+ tarafından dikkate alındığı bildirilir. Resmî Microsoft belgesi bulunamadı. `tscsyncpolicy enhanced` (hata ayıklama seçeneği) kaldırıldı. | [Bruce Dawson — timer rule change](https://randomascii.wordpress.com/2020/10/04/windows-timer-resolution-the-great-rule-change/) (Topluluk) |
| CPU Priority Boost | `sched.mmcss-games` | **Düzeltildi** | Eski kod `SystemResponsiveness=0` yazıyordu. Microsoft'a göre 10'un altındaki değerler **20'ye sabitlenir** → etkisizdi. v4: 10 (belgelenmiş en düşük etkin değer) + Games görevi Priority 6 / Scheduling Category High / SFIO High. Belgelenmemiş `CppcEnable` ve `EnergyPerfPreference` (Control\Power) yazımları kaldırıldı. `NetworkThrottlingIndex` ayrı ayar oldu. | [MMCSS](https://learn.microsoft.com/en-us/windows/win32/procthread/multimedia-class-scheduler-service) |
| Win32Prio BestFPS 0x14 / Balanced 0x18 / Default 0x26 | `sched.win32prio-14/18/26` (tek seçim) | **Düzeltildi** | Eski kod hem `ControlSet001` hem `CurrentControlSet`'e yazıyordu (etkin set 001 değilse yanlış yere yazılır). v4 yalnızca CurrentControlSet. Açıklamalar bit çözümlemesine göre yazıldı (0x14 = uzun, değişken, ön plan artırımı YOK). "En düşük input lag" iddiası kaldırıldı. Windows varsayılanı 2. `_Files\Win32Prio_*.reg` dosyaları hiç kullanılmıyordu ve `ConvertibleSlateMode`'u da değiştiriyordu → silindi. | Topluluk (Microsoft'un Windows 2000 kayıt başvurusu artık erişilemiyor — doğrulanamadı) |
| Güç planı butonları | `power.*` (tek seçim) | **Düzeltildi** | Her tıklama `.pow`'u yeniden içe aktarıyor / Ultimate'ı yeniden kopyalıyordu → **yinelenen planlar**. v4 `powercfg /import <dosya> <GUID>` ve `/duplicatescheme <kaynak> <GUID>` ile SABİT GUID kullanır; plan varsa yalnızca etkinleştirir. "Default" butonu aslında Yüksek Performans'ı etkinleştiriyordu → "Dengeli (Windows varsayılanı)" ve "Yüksek Performans" ayrı ve doğru adlı. Modern Bekleme cihazlarında Yüksek Performans yoksa "Desteklenmiyor". | [powercfg](https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/powercfg-command-line-options) |
| SysMain Kapat | `svc.sysmain-off` | Korundu, Orta risk | Servis ayarı geçerli; SSD'de fayda ölçülmemiş → "Doğrulanmamış fayda". Advanced Clean'deki kopyası (Prefetch'i de siliyordu) kaldırıldı. | — |
| Windows Search Kapat | `svc.wsearch-off` | Korundu, Orta risk | Arama işlevini bozar; açıkça belirtildi. Varsayılan: Otomatik (Gecikmeli). | — |
| Windows Update Gecikmeli | `wu.defer` | **Düzeltildi** | Eski kod `WindowsUpdate\UX\Settings` altına (eski Win10 1607–1703 konumu) ve AU ilkesine `AUOptions=4` yazıyordu; "otomatik yeniden başlatmayı engeller" iddiası yanlıştı. v4: Grup İlkesi değerleri `DeferFeatureUpdatesPeriodInDays=365`, `DeferQualityUpdatesPeriodInDays=7`, `NoAutoRebootWithLoggedOnUsers=1`. **Home sürümünde "Desteklenmiyor"** (ilkeleri uygulamaz). | [Update CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-update) |
| Game Mode | `game.mode` | Korundu | Windows'ta varsayılan açık; zaten açıksa değişiklik yapılmaz. | Topluluk |
| HW-Accelerated GPU Scheduling | `gpu.hags` (GPU sayfası) | Korundu | WDDM 2.7+ ve destekleyen GPU gerekir; Microsoft belirgin performans değişikliği beklemediğini belirtir. Yeniden başlatma gerekir. | [DirectX blog](https://devblogs.microsoft.com/directx/hardware-accelerated-gpu-scheduling/) |
| Standby List Temizle (ISLC -purge) | `mem.purge-standby` (tek seferlik) | **Düzeltildi** | ISLC gerektirmeden `NtSetSystemInformation(SystemMemoryListInformation, MemoryPurgeStandbyList)`; `SeProfileSingleProcessPrivilege` artık gerçekten etkinleştiriliyor (eski yedek kod etkinleştirmiyordu → sessizce başarısız). NTSTATUS denetlenir. Geri alınamaz işlem olarak işaretli. | [Kenji Mouri — NT API](https://mouri.moe/en/2021/11/14/Defrag-memory-with-NT-API/) (Topluluk) |
| Modified List Temizle (ISLC -runonce) | `mem.flush-modified` | **Düzeltildi** | ISLC ReadMe'ye göre `-runonce` "bir kez yokla ve çık"tır, modified list temizlemez. v4: `MemoryFlushModifiedList`. | ISLC ReadMe |
| ISLC otomatik başlatma (ISLC.ini + LaunchOnLogon) | `mem.islc-autostart` | **Düzeltildi** | Eski kod ISLC'nin okuduğu doğrulanmamış bir `ISLC.ini` yazıyor, görev kaydını "ISLC yapar" diyerek doğrulamıyordu. v4: tek adlı `\LivnTools\ISLC` görevi (Register -Force → yinelenmez), geri alınabilir. | ISLC ReadMe |

## Ağ

| v3.5 | v4 | Karar | Gerekçe | Kaynak |
|---|---|---|---|---|
| AutoTuning Normal | `net.autotuning-normal` | Korundu | Windows varsayılanını geri getirir. Durum `Get-NetTCPSetting` ile okunur (eski kod İngilizce netsh çıktısını ayrıştırıyordu; Türkçe Windows'ta çalışmıyordu). | [Set-NetTCPSetting](https://learn.microsoft.com/en-us/powershell/module/nettcpip/set-nettcpsetting) |
| ECN Kapat | `net.ecn-off` | Korundu, fayda doğrulanmamış | Varsayılan sürüme göre değişir → yalnızca "önceki ayar" geri yüklenebilir. | aynı |
| RSC Kapat | `net.rsc-off` | Korundu, Orta risk | CPU yükünü artırabilir; gecikme kazancı ölçülmemiş. | aynı |
| Congestion → CUBIC | `net.cubic` | Korundu | Win10 1709+/Win11'de zaten varsayılan → çoğu sistemde "Zaten uygulanmış". | [CUBIC](https://techcommunity.microsoft.com/t5/networking-blog/windows-transport-converges-on-two-congestion-providers-cubic/ba-p/339819) (sayfa içeriği bu oturumda okunamadı) |
| NetworkThrottlingIndex | `net.throttling-off` | Korundu | Varsayılan 10; yalnızca MMCSS multimedya akışlarında etkili. Microsoft MMCSS sayfasında bu değer geçmiyor → Topluluk. | Topluluk |
| Nagle (TcpNoDelay=1) | — | **Kaldırıldı** | Registry'deki `TcpNoDelay` değerinin güncel Windows TCP yığınında Winsock uygulamalarını etkilediğine dair birincil kaynak yok (Nagle uygulama tarafında `TCP_NODELAY` ile kapatılır). Ayrıca eski kod tüm arayüzlere (sanal/VPN dahil) yazıyordu. | — |
| TCP No Delay (TcpDelAckTicks=0) | — | **Kaldırıldı** | Etiket yanlıştı (TcpDelAckTicks gecikmeli ACK zamanlayıcısıdır, Nagle değil) ve değer yalnızca Windows 2000 belgelerinde geçiyor. | [TcpDelAckTicks (Win2000)](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-2000-server/cc938206(v=technet.10)) |
| TcpAckFrequency=1 | `net.ackfreq` | Düzeltildi, Orta risk | Yalnızca ETKİN FİZİKSEL adaptörlerin arayüz anahtarlarına yazılır (eskisi tüm arayüzlere). Microsoft ortam incelenmeden değiştirilmesini önermez; açıklamada belirtildi. | [KB: TcpAckFrequency](https://learn.microsoft.com/en-us/troubleshoot/windows-server/networking/registry-entry-control-tcp-acknowledgment-behavior) |
| RSS Etkin | `net.rss-on` | Düzeltildi | Global RSS + adaptör `*RSS=1` (standart anahtar kelime). | [Enumeration keywords](https://learn.microsoft.com/en-us/windows-hardware/drivers/network/enumeration-keywords) |
| Flow Control Kapat | `nic.flowcontrol-off` | **Düzeltildi** | Eski kod İngilizce `DisplayName`/`DisplayValue` ile arıyordu (yerelleştirilmiş sürücülerde çalışmaz) ve hatayı bastırıp "OK" logluyordu. v4: `*FlowControl` → `0`, yalnızca sürücü `0`'ı geçerli değer olarak bildiriyorsa. | aynı |
| Interrupt Moderation → Adaptive | — | **Kaldırıldı** | Standart `*InterruptModeration` yalnızca 0/1 kabul eder; "Adaptive" değeri çoğu sürücüde yoktu (işlem sessizce başarısız). Açık (1) zaten varsayılan. | aynı |
| Green Ethernet / EEE Kapat | `nic.eee-off` | Düzeltildi | Standart `*EEE` + bilinen üretici anahtarları; yalnızca `0` geçerliyse. | [Power keywords](https://learn.microsoft.com/en-us/windows-hardware/drivers/network/standardized-inf-keywords-for-power-management) |
| Giga Lite Kapat | — | **Kaldırıldı** | Üreticiye özgü; anahtar kelime doğrulanamadı; eski kod İngilizce görünen ada bakıyordu. | — |
| Adaptive Inter-Frame Spacing | `nic.adaptiveifs-off` | Düzeltildi | Yalnızca `AdaptiveIFS` anahtarını sunan sürücülerde. Eski kod ayrıca ilgisiz "Interrupt Moderation Rate=3" yazıyordu → kaldırıldı. | Topluluk |
| DNS Cache Optimizasyonu | — | **Kaldırıldı** | `MaxCacheTtl=3600` önbelleği KISALTIR, `MaxNegativeCacheTtl=0` olumsuz önbelleği kapatır, `CacheHashTable*` NT4 dönemi değerleri. "Gecikme azalır" iddiasına kaynak yok. | — |
| LLMNR Kapat | `dns.llmnr-off` | Korundu | Grup İlkesi "Turn off multicast name resolution". | — |
| mDNS Kapat | `dns.mdns-off` | Korundu, Orta risk | Cihaz keşfini bozar; açıkça belirtildi. | Topluluk |
| TCP/IP Sıfırla | `net.stack-reset` (tek seferlik) | Korundu | Çıkış kodları denetlenir; geri alınamaz ve yeniden başlatma gerektirir. | — |

## Güvenlik ve giriş (eski "Kernel & Input")

| v3.5 | v4 | Karar | Gerekçe | Kaynak |
|---|---|---|---|---|
| VBS Kapat | `sec.vbs-off` | Korundu, **Security** | `EnableVirtualizationBasedSecurity=0`. UEFI kilidi veya ilke yönetimi varsa "Desteklenmiyor" + neden. | [Memory integrity](https://learn.microsoft.com/en-us/windows/security/hardware-security/enable-virtualization-based-protection-of-code-integrity) |
| HVCI Kapat | `sec.hvci-off` | Korundu, **Security** | Microsoft'un belgelediği `Scenarios\HypervisorEnforcedCodeIntegrity\Enabled=0`. | aynı |
| Spectre/Meltdown Kapat | `sec.spectre-off` | Korundu, **Security** | KB4072698 değerleri (3/3). Varsayılan: değerler yok. | [KB4072698](https://support.microsoft.com/en-us/topic/kb4072698-windows-server-and-azure-stack-hci-guidance-to-protect-against-silicon-based-microarchitectural-and-speculative-execution-side-channel-vulnerabilities-2f965763-00e2-8f98-b632-0d96f30c8c8e) |
| CFG Kapat | `sec.cfg-off` | **Düzeltildi**, **Security** | Eski kod `MitigationOptions |= 0x200` (QWORD) yazıyordu: bu bit CFG değil, "zorunlu ASLR (ForceRelocateImages) her zaman kapalı" bitidir; ayrıca değer normalde REG_BINARY'dir. v4: `Set-ProcessMitigation -System -Disable CFG`; geri alma ham değeri birebir geri yazar. | [Set-ProcessMitigation](https://learn.microsoft.com/en-us/powershell/module/processmitigations/set-processmitigation) |
| DMA Protection Kapat | — | **Kaldırıldı** | `DeviceGuard\EnableKernelDmaProtection` Microsoft'un tanımladığı bir değer değil; Çekirdek DMA Koruması ürün yazılımı/ilke ile yönetilir. Eski seçenek etkisizdi ama "WARN: disabled" logluyordu. | — |
| Large Pages | — | **Kaldırıldı** | `LargePageMinimum=0` uygulamaların large page kullanmasını sağlamaz (uygulama + `SeLockMemoryPrivilege` gerekir). | — |
| DX Contiguous Memory | — | **Kaldırıldı** | `D3D12_ENABLE_UNSAFE_COMMAND_BUFFER_REUSE`, `DpiMapIommuContiguous`: belgelenmemiş değerler, iddia edilen işlevle ilişkisi yok. | — |
| PageFile Optimize | `mem.pagefile-auto` | **Düzeltildi** | Eski kod `PagingFiles = "c:\pagefile.sys 0 0"` yazıp **diğer sürücülerdeki sayfa dosyalarını siliyor**, sistemin yönettiği `ExistingPageFiles`'ı boşaltıyordu. v4: `?:\pagefile.sys` (sistem yönetimli), özgün değer birebir geri yüklenebilir. | Topluluk |
| PageFile Temizle (Advanced Clean) | `mem.clear-pagefile` | Taşındı | Geri alınabilir ayar olduğu için temizlik yerine ayar kataloğunda. | Güvenlik ilkesi |
| Mouse Acceleration Kapat | `input.mouse-accel-off` | Korundu | Denetim Masası'ndaki "İşaretçi hassasiyetini artır" ile aynı üç değer. Oturum yenileme gerekir (eski sürüm bunu belirtmiyordu). | Topluluk |
| Mouse Smoothing (MarkC eğrileri) | — | **Kaldırıldı** | Eğriler yalnızca ivme açıkken kullanılır; ivme kapatma ile birlikte etkisiz. MarkC düzeltmesi DPI ölçeğine özeldir; sabit %100 eğrisi başka ölçeklerde yanlıştır. | — |
| Mouse/Keyboard Buffer = 16 | — | **Kaldırıldı** | Varsayılan 100'dü; fayda kaynağı yok, yüksek yoklama hızlı cihazlarda giriş kaybı riski. | — |
| Raw Input Thread Boost | — | **Kaldırıldı** | `MouseSensitivity=10` zaten varsayılan; `csrss.exe` için IFEO PerfOptions korumalı süreçte riskli/etkisiz; `HidUsb\WaitWakeEnabled` belgelenmemiş. | — |

## GPU ve MSI

| v3.5 | v4 | Karar | Gerekçe | Kaynak |
|---|---|---|---|---|
| GPU/NVMe/NIC MSI Mode | `msi.gpu`, `msi.nic` | **Düzeltildi**, Yüksek risk | Eski kod `Control\Class\{guid}\000x` (SÜRÜCÜ yazılım anahtarı) altına yazıyordu; Windows `MSISupported`'ı aygıtın DONANIM anahtarında (`Enum\PCI\...\Device Parameters\Interrupt Management\...`) okur → **eski ayar hiçbir etki yapmıyordu**. NVMe seçeneği kaldırıldı (stornvme zaten MSI-X kullanır; zorlamak yalnızca risk). | [MSI registry](https://learn.microsoft.com/en-us/windows-hardware/drivers/kernel/enabling-message-signaled-interrupts-in-the-registry) |
| MSI IRQ Priority | — | **Kaldırıldı** | `DevicePriority` güncel "Interrupt Affinity and Priority" belgesinde yok (yalnızca DevicePolicy/AssignmentSetOverride). | [Affinity](https://learn.microsoft.com/en-us/windows-hardware/drivers/kernel/interrupt-affinity-and-priority) |
| NVIDIA: Pre-Rendered Frames / Max Perf / V-Sync / Shader Cache / Texture / ULL | — | **Kaldırıldı** | NVIDIA sürücü ayarları DRS profillerinde tutulur; yazılan değerler belgelenmemiş. "V-Sync kapat" aslında `PerfLevelSrc` (güç yönetimi) yazıyordu; "Pre-rendered frames" başka bir değer yazıyordu. Etki doğrulanamaz. | — |
| AMD: Anti-Lag / Chill / Power | — | **Kaldırıldı** | Belgelenmemiş sürücü anahtarları; AMD Software ayarlarıyla eşleştiği doğrulanamadı. | — |

## Gizlilik

| v3.5 | v4 | Karar | Gerekçe | Kaynak |
|---|---|---|---|---|
| Telemetry Level = 0 | `priv.telemetry-min` | **Düzeltildi** | Microsoft: 0 yalnızca Enterprise/Education/IoT/Server'da geçerli, diğerlerinde 1 olarak uygulanır. v4 sürüme göre 0 veya 1 yazar ve bunu açıklar. | [System CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-system) |
| App Compat Telemetry | `priv.appcompat` | **Düzeltildi** | `DisableProgramTelemetry` geçerli bir AppCompat ilkesi değil → `AITEnable=0` + `DisableInventory=1`. | ADMX (AppCompat) |
| Consumer Experience | `priv.consumer-off` | **Düzeltildi** | Microsoft: yalnızca Enterprise/Education/IoT Enterprise; Pro/Home'da "Desteklenmiyor". | [Experience CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-experience) |
| Bing Search | `priv.websearch-off` | **Düzeltildi** | Durum taraması başka değeri (`DisableSearchBoxSuggestions`) kontrol ederken uygulama `BingSearchEnabled` yazıyordu → hep "uygulanmamış". Artık ikisi birlikte. | Topluluk |
| DiagTrack, dmwappush, CEIP, Activity, Cortana, AdID, Tailored, Inking, WER, Suggested Apps, Xbox | `priv.*` | Korundu | Hata/çıkış kodu kontrolü ve geri alma eklendi. Xbox: `XboxGipSvc` (kumanda aksesuarları) listeden çıkarıldı. | — |
| OneDrive Kaldır | `priv.onedrive-uninstall` (tek seferlik) | Düzeltildi | Çıkış kodu ve kaldırma sonrası dosya kontrolü; geri alınamaz olarak işaretli; hazır seçimlerde yok. | — |

## Windows ayarları

Tüm HKCU/HKLM tercihleri (koyu mod, saydamlık, uzantılar, menü gecikmesi, NumLock,
uzun yol, klasik sağ tık, BSOD, tam döküm, olay günlüğü boyutu) katalogda; her biri
doğrulama + önceki değere dönüş destekler. Düzeltmeler:

- **Animasyonlar**: `FontSmoothing=2` (zaten varsayılan) ve `DragFullWindows=0` (animasyon değil, sürükleme önizlemesi) yazımları kaldırıldı; `VisualFXSetting=2` yalnızca iletişim kutusu tarafından uygulanır, tek başına etkisizdi.
- **Explorer yeniden başlatma**: artık otomatik değil; sonuçta sorulur.
- **Tam bellek dökümü**: sayfa dosyası gereksinimi (RAM + 257 MB) açıklandı. [Kaynak](https://learn.microsoft.com/en-us/troubleshoot/windows-server/performance/memory-dump-file-options)
- **Olay günlüğü boyutu**: mevcut boyut zaten büyükse küçültmez.
- **Hazırda bekletme** (Advanced Clean'den taşındı): geri alınabilir ayar.

## Temizlik (geri alınamaz)

| Konu | Düzeltme |
|---|---|
| Bayt sayımı | Eskiden silmeden ÖNCE toplanıp tümü "temizlendi" sayılıyordu (kilitli dosyalar dahil). Artık yalnızca gerçekten silinen dosyalar; kilitliler "Kısmen". |
| Yol güvenliği | Boş ortam değişkeninden doğan yollar (`\Temp`), sürücü kökü, Windows/Users kökleri reddedilir; junction/symlink izlenmez. |
| Spotify | `Spotify\Data` (ÇEVRİMDIŞI indirilen şarkılar) siliniyordu → yalnızca `Storage`. |
| WhatsApp | Paket `LocalCache` kökü (oturum/mesaj verisi olabilir) siliniyordu → yalnızca masaüstü uygulamasının Cache/Code Cache klasörleri. |
| Skype | Microsoft Skype hizmetini sonlandırdı; öğe kaldırıldı. |
| Ubisoft | Eski yol (`%LOCALAPPDATA%\Ubisoft Game Launcher\cache`) kurulumda bulunmuyordu → kurulum klasöründeki logs ve cache\http. (Yol Windows'ta doğrulanmalı.) |
| Firefox | Önbellek `%LOCALAPPDATA%` altında; eski kod `%APPDATA%`'ya bakıyordu. |
| Steam httpcache | Steam kurulum klasöründe; artık registry'den bulunuyor. |
| Açık uygulama | "Launcher", "Agent" gibi genel süreç adları kaldırıldı (ilgisiz süreçleri öldürebiliyordu). |
| USB geçmişi | `MountedDevices` D–Z silme (dahili sürücü harflerini bozabilir), `USBSTOR` ağaç silme (SYSTEM izni gerekir, sessizce başarısız) ve System günlüğünü silme kaldırıldı → `pnputil /remove-device` ile yalnızca bağlı olmayan USB depolama aygıtları. |
| DISM / SFC | Çıkış kodu denetlenir (3010 = yeniden başlatma); SFC sonucu İngilizce metin ayrıştırmasına dayanmaz. |
| Event logs | Her günlük için `wevtutil cl` çıkış kodu sayılır. |
| WU önbelleği | wuauserv **ve** bits durdurulur, önceki durumlarına döndürülür. |
| Delivery Optimization | `Delete-DeliveryOptimizationCache` (Windows cmdlet'i); yoksa "Desteklenmiyor". |
