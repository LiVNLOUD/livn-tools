# Destek matrisi

**15 Ekim 2026 CI güncellemesi:** GitHub Windows makinesinde Windows PowerShell 5.1 / .NET Framework ve gerçek WPF nesne, olay ve layout temel doğrulaması geçti. Güncel Pester/statik analiz sonucu [Actions](https://github.com/LiVNLOUD/livn-tools/actions/workflows/validate.yml) üzerinde sürüm commit’iyle eşleştirilir. Bu, fiziksel Windows 10/11 donanım kabulü veya Windows Server için ürün desteği anlamına gelmez. Aşağıdaki eski tarihli kayıtlar kendi kapsamlarıyla korunmuştur.

Durum sütunu: **Hedef** = kod bu platform için yazıldı ve statik olarak denetlendi;
**Test edildi** = yalnız belirtilen kapsam gerçek sistemde çalıştırıldı. 30 Eylül 2026 Windows 10 / PS 5.1 SmokeOnly ve görünür DryRun arayüz kontrolü geçti. Gerçek sistem ayarı/kurulum/geri alma ve Windows 11 kabulü açık (bkz. [WINDOWS_TEST_CHECKLIST.md](WINDOWS_TEST_CHECKLIST.md)).

## Çalışma ortamı

| Bileşen | Destek | Durum |
|---|---|---|
| Windows 11 (22H2, 23H2, 24H2), x64 | Tam | Hedef — Windows'ta test edilmedi |
| Windows 10 22H2 (19045), x64 | Hedef (Win11'e özgü ayarlar "Desteklenmiyor" gösterilir) | PS 5.1 SmokeOnly + görünür DryRun geçti; gerçek ayarlar bekliyor |
| Windows 10 2004–21H2 | Çalışır; bazı ayarlar sürüm denetimiyle kapalı | Hedef — test edilmedi |
| Windows 10 1809 ve öncesi | Desteklenmez (NetTCPIP/ProcessMitigations cmdlet farkları) | — |
| Windows 10/11 LTSC/IoT | Çalışabilir; Microsoft Store ve çoğu zaman WinGet yoktur → Format Sonrası "WinGet'i edinin" yönergesi (Microsoft Learn) gösterir | Test edilmedi |
| Windows Server 2022/2025 | Çalışabilir; sunucu için tasarlanmadı (Geri yükleme noktası yok → gerekçesiyle gösterilir) | Test edilmedi |
| ARM64 | Desteklenmez (test edilmedi; güç planı/NIC davranışı farklı olabilir) | — |
| Windows PowerShell 5.1 (64-bit) | Tek çalışma kabuğu | 5.1.19041.6456: C# derleme, WPF olay/layout ve Memory uygula/geri al geçti |
| 32-bit PowerShell, PowerShell 7.x, ISE, VS Code | Başlangıçta 64-bit Windows PowerShell 5.1 ile yeniden açılır (bcdedit/DISM/SFC 32-bit kabukta çalışmaz) | Statik test; Windows'ta çalıştırılmadı |
| AppLocker/WDAC kısıtlı dil modu, GPO AllSigned | Desteklenmez; başlatıcı nedenini gösterir (sessiz kapanma yok) | Statik test |
| Modern Bekleme (S0) dizüstü | Yalnız Dengeli ve türevleri (Microsoft Learn); Bitsum/Ultimate/Hybred HighPerf yerine Windows güç modu önerilir | Memory testi |
| Denetimli klasör erişimi / OneDrive'a yönlendirilmiş Belgeler | Yeni kurulum `%LOCALAPPDATA%` altına; Masaüstü yolu yönlendirmeyi izler | Installer testi |
| Sistem Kontrolü | CIM (PnP, ekran kartı, bellek, DeviceGuard), user32 EnumDisplaySettings, Storage cmdlet'leri, fsutil, olay günlüğü, registry; her alan ayrı okunur, okunamayan "Okunamadı" | Memory/saf işlev testleri; Windows'ta çalıştırılmadı |
| Bağlantı ölçümü / DNS testi | .NET Ping (ICMP), Get-NetRoute, Resolve-DnsName; ICMP'yi kapatan modem/sunucu "yanıt yok" olarak yorumlanır | Memory testleri; gerçek ağda ölçülmedi |
| DNS seçimi | Set-DnsClientServerAddress (seçili adaptör, IPv4+IPv6); elle DNS kaydı Tcpip/Tcpip6 NameServer'dan okunur | Memory testleri |
| Kurtarma kiti | Dışa aktarma: Get-WindowsDriver -Online (yalnız oemNN.inf), `pnputil /export-driver` (Windows 10 1607+), `netsh wlan export profile key=clear`; geri yükleme: `pnputil /add-driver … /subdirs /install` (0/3010/1641/259 kodları yorumlanır), `netsh wlan add profile user=current`, kayıtlar üstüne yazmadan kopyalanır. Hedef sistem sürücüsü olamaz | Memory testleri ve geçici klasörler; pnputil/netsh Windows'ta çalıştırılmadı |
| Başlangıç uygulamaları | Run (HKCU/HKLM/WOW6432Node) + Başlangıç klasörleri; StartupApproved (Görev Yöneticisi biçimi) | Memory testleri |
| Hızlı kullanıcı değiştirme / RDP (birden çok oturum) | Uygulama/Explorer kapatma yalnız bu oturumda | Mock testi |
| Türkçe / İngilizce / diğer dilde Windows | Karar veren kod yerelleştirilmiş metin ayrıştırmaz | Türkçe/Almanca örnek çıktılarla birim testi var |
| Yönetici yetkisi | Gerekli (kuru çalışma hariç) | — |
| Standart kullanıcı + başka yönetici hesabıyla UAC | Kullanıcı kapsamındaki değişiklikler, WinGet ve kullanıcı profili temizliği kimlik kontrolüyle reddedilir/atlanır | Memory/mock testi var; gerçek farklı hesap testi bekliyor |
| WinGet | ≥ 1.6 (kullanılan bayraklar için muhafazakâr eşik); PATH dışında WindowsApps takma adı ve App Installer klasörü de denenir; hata kodları Türkçe açıklanır | Mock testi; gerçek WinGet çıkış kodları Windows'ta doğrulanmadı |

## Ayar bazında koşullar

| Ayar | Koşul | Koşul sağlanmazsa |
|---|---|---|
| `timer.global-resolution` | Build ≥ 22000 (Win11) veya Server 2022+ | Desteklenmiyor |
| `wu.defer` | Home (Core) dışı sürümler | Desteklenmiyor |
| `priv.consumer-off` | Enterprise / Education / IoT Enterprise / Server | Desteklenmiyor |
| `priv.telemetry-min` | Tüm sürümler; 0 yalnızca Ent/Edu/Server'da, diğerlerinde 1 yazılır | — |
| `gpu.hags` | Build ≥ 19041; sürücü WDDM 2.7 sorgusu "desteklenmiyor" demiyorsa (sorgu okunamazsa izin verilir, etkin durum yeniden başlatma sonrası okunur) | Desteklenmiyor |
| `msi.gpu`, `msi.nic` | GPU ve MSI sayfasında seçilen tek PCI aygıt doğru sınıfta ve `DEVPKEY_PciDevice_InterruptSupport` MSI veya MSI-X bildiriyor | Desteklenmiyor (neden: seçim yok / sınıf farklı / yalnız hat tabanlı / okunamadı) |
| `ui.classic-context` | Windows 11 | Desteklenmiyor |
| `power.highperf` | Yüksek Performans planı mevcut (Modern Bekleme'de gizli) | Desteklenmiyor |
| `power.bitsum`, `power.hybred-*` | `_Files` altında plan dosyası ve sabitlenmiş SHA-256 eşleşmesi | Desteklenmiyor |
| `mem.islc-autostart` | Kullanıcının seçtiği/geçerli görevden bulunan desteklenen ISLC dosyası ve RAM profili doğrulanır | Desteklenmiyor; neden gösterilir |
| `nic.*` | Etkin fiziksel adaptör, anahtar kelime ve değer sürücüde geçerli | Desteklenmiyor |
| `sec.vbs-off`, `sec.hvci-off` | UEFI kilidi yok, ilke ile yönetilmiyor | Desteklenmiyor |
| Servis ayarları | Servis sistemde var | Desteklenmiyor |
| `adv.usb-ghosts` | Build ≥ 19041 (`pnputil /remove-device`) | Desteklenmiyor |
| `clean.deliveryopt` | `Delete-DeliveryOptimizationCache` cmdlet'i mevcut | Desteklenmiyor |
| Uygulama önbellekleri | Uygulama kurulu (registry DisplayName veya yol) | Desteklenmiyor (gri) |

## Geri alma kapsamı

| Tür | Önceki ayara dön | Windows varsayılanı | Not |
|---|---|---|---|
| Registry (değer yok/var, tür dahil) | Evet (birebir) | Katalogda tanımlıysa | Livn'in oluşturduğu boş anahtarlar da silinir |
| Servis başlangıç türü + çalışma durumu | Evet | Katalogda tanımlıysa | |
| BCD öğeleri | Evet | Evet (öğe silinir) | |
| Etkin güç planı | Evet | Dengeli | Oluşturulan plan silinmez (sabit GUID ile yeniden kullanılır) |
| TCP global ayarları | Evet | Bazıları | |
| NIC gelişmiş özellikleri | Evet | Sürücünün bildirdiği varsayılan | |
| Olay günlüğü boyutu | Evet | 20 MB | |
| CFG (sistem mitigasyonu) | Yalnız CFG tercihi; ilgisiz mitigasyonlar korunur | NOTSET | Çakışma denetlenir; ham registry bütünü geri yazılmaz |
| Zamanlanmış görev | Evet | Görev silinir | |
| Hazırda bekletme | Etkinlik, dosya türü ve boyut tercihi | Açık | Silinen hazırda bekletme oturumunun içeriği kurtarılmaz |
| Temizlik / DISM / SFC / OneDrive kaldırma / TCP-IP sıfırlama | **Hayır** | **Hayır** | Arayüzde "Geri alınamaz" etiketi |
| Betik Çalıştır | **Hayır** | **Hayır** | Geri alma sistemine dahil değil |

## 1 Ekim 2026 eklemeleri — doğrulama durumu

| Özellik | Desteklenen davranış | Test edildi | Henüz doğrulanmadı |
|---|---|---|---|
| Format Sonrası envanteri | WinGet `export` (yalnız `winget` kaynağı) + Windows Uninstall kayıtlarında (HKLM, WOW6432Node, HKCU) uygulama başına DisplayName deseni ile Kurulu / Kurulu (WinGet dışı) / Kurulu değil / Durum okunamadı; ayrı runspace; otomatik ≥10 dk, elle ≥30 sn | Linux PS 7.4.6: Memory envanteri, WinGet yok, sorgu hatası, yeniden deneme, büyük/küçük harf, gerçek ikincil runspace ile UI mantığı, sözleşme kabulü ayrımı (mock) | Gerçek `winget export` çıktısı, Microsoft Store/MSI ile kurulmuş uygulamaların eşleşmesi, ağsız ortam, eski App Installer sürümleri, WPF görünümü ve DPI |
| Temizlik önizlemesi | Silmeyle aynı seçim kuralları; dosya sayısı/boyut; kapsam; taranamayan ve sınır dışı alanlar; bakım işlemlerinde sayı yok | Linux PS 7.4.6: ayrılmış geçici test kökünde önizleme = silme sayımı (4 kural), symlink, sınır dışı yol, erişim hatası (mock), önizleme sonrası bağlantıya çevrilen hedef, iptal, tüm katalogda yan etkisizlik, DryRun, Epic hesap verisi | Windows junction/ACL davranışı, gerçek kullanıcı profilinde büyük klasörlerde süre, kilitli dosyalar, WPF rapor penceresi |
| Atomik dosya yazımı | `File.Replace` + korumalı geri dönüş + `.bak` kurtarma | Linux PS 7.4.6 (.NET 8) | Windows PowerShell 5.1 / .NET Framework'te `File.Replace` ve antivirüs kilidi senaryosu |

