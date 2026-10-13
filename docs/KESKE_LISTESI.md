# "Keşke olsaydı" listesi — kullanıcı gözüyle Livn Tools

Bakış açısı: Windows'u yeni kurmuş, oyun oynayan bir kullanıcı. Beklentisi kararlı bir
sistem, eksiksiz sürücüler, yüksek performans ve düşük/sabit ping. Bu belge, o kullanıcının
Livn Tools'ta aradığı şeyleri, bu sürümde nelerin yapıldığını ve bilerek nelerin
yapılmadığını açıklar. Bu tur gerçek Windows'ta çalıştırılmadı; kabul adımları
[WINDOWS_TEST_CHECKLIST.md](WINDOWS_TEST_CHECKLIST.md) "2 Ekim 2026 (2)" bölümündedir.

## 1. "Format sonrası her şey yolunda mı?" → **Sistem Kontrolü** (yeni açılış sayfası)

Salt okunurdur; hiçbir ayarı değiştirmez. Her bulgu için durum (Sorun / Uyarı / Bilgi /
Tamam / Okunamadı), öneri ve düğme vardır. Düğmeler yalnız sabit bir listeden Windows
ekranı açar (Aygıt Yöneticisi, İsteğe bağlı sürücüler, Gelişmiş ekran, Güvenilirlik
İzleyicisi, NVIDIA/AMD/Intel sürücü sayfaları), Livn'de bir sayfaya gider veya ilgili
ayarı işaretler. Okunamayan bilgi hiçbir zaman "Tamam" sayılmaz.

| Kontrol | Nasıl okunur | Neden önemli |
|---|---|---|
| Sürücüsü eksik/hatalı aygıt | `Win32_PnPEntity.ConfigManagerErrorCode` (28 = sürücü yok, 43, 52 …) | Format sonrası en sık sorun |
| Ekran kartı temel sürücüde mi | `Win32_VideoController.InfFilename = display.inf`; sürücü tarihi > 18 ay | Temel sürücüde oyun, yüksek Hz ve HAGS çalışmaz |
| Yenileme hızı | `EnumDisplaySettings`: mevcut Hz ile aynı çözünürlükte desteklenen en yüksek Hz | 144 Hz monitörün 60 Hz'de kalması çok yaygın |
| RAM | `Win32_PhysicalMemory`: çalışma hızı, modül hızı, tür, modül sayısı | XMP/EXPO kapalı veya tek kanal; Livn BIOS'a dokunmaz, yalnız bildirir |
| Sistem diski | Disk türü/sağlığı (`Get-PhysicalDisk`), sıcaklık/aşınma (varsa), boş alan, TRIM (`fsutil`) | Az alan, HDD, kapalı TRIM, yıpranan SSD |
| Kararlılık | Son 14 gün: WHEA donanım hatası, Kernel-Power 41, BugCheck 1001 | Kararsız XMP/OC, ısınma, sürücü çökmeleri |
| Bekleyen yeniden başlatma | CBS / Windows Update / PendingFileRenameOperations kayıtları | Ayar ve sürücü kurmadan önce |
| Windows Update | `wuauserv` devre dışı veya `NoAutoUpdate` ilkesi | Güvenlik ve sürücü düzeltmeleri gelmez |
| Bağlantı türü | Fiziksel bağdaştırıcı: Wi-Fi / kablolu, bağlantı hızı | Wi-Fi'de dalgalanma; 100 Mb/s'de kalmış kablo |
| Oyun ayarları | Oyun Modu, arka plan kaydı, Güç Tasarrufu planı, HAGS, VBS/HVCI | VBS yalnız bilgi olarak gösterilir; kapatılması önerilmez |
| Başlangıç uygulamaları | Açık başlangıç öğesi sayısı | Açılış süresi ve arka plan yükü |

Rapor düz metin olarak kaydedilir (bilgisayar ve kullanıcı adı yazılmaz). Destek isterken paylaşılabilir.

## 2. "Ping'im neden yüksek/dalgalı?" → **Bağlantı ölçümü** (Ağ sayfası)

- Modeme (varsayılan ağ geçidi), 1.1.1.1, 8.8.8.8 ve isteğe bağlı oyun sunucusuna 20'şer
  ICMP yankısı: ortalama/en düşük/en yüksek, dalgalanma (ardışık farkların ortalaması), kayıp.
- Yorum: modem kötü → ev içi ağ (Wi-Fi, kablo, aynı anda indirme); modem iyi ama internet
  kötü → hat/servis sağlayıcı; oyun sunucusu genel hedeflerden belirgin yüksek → mesafe/bölge.
- Her ölçüm saklanır (son 30); yeni ölçüm bir öncekiyle karşılaştırılır. Ayar değiştirmeden
  önce ve sonra ölçmek için tasarlandı.
- Hedef kutusuna yalnız IP adresi veya alan adı yazılabilir; komut kabul edilmez.

## 3. "DNS değiştirmeli miyim?" → **DNS hız testi** ve **DNS seçimi**

- Hız testi: mevcut DNS, Cloudflare, Google ve Quad9'a 4 alan adı × 3 sorgu; medyan süre.
- Seçim: seçili adaptörde Cloudflare / Google / Quad9 (IPv4 + IPv6). "Önceki ayara dön"
  elle girilmiş eski DNS'i birebir, "Windows varsayılanı" otomatik (DHCP) DNS'i geri getirir.
- Dürüst not: DNS ad çözümleme süresini etkiler; **oyun içi ping'i değiştirmez**. Bu yüzden
  Oyuncu modu DNS'e dokunmaz.

## 4. "Açılışta bir sürü şey başlıyor" → **Başlangıç Uygulamaları** sayfası

- Kayıt (kullanıcı, tüm kullanıcılar, 32-bit) ve Başlangıç klasörleri listelenir.
- Kapatma/açma Görev Yöneticisi ile aynı `StartupApproved` kaydıyla yapılır; uygulama veya
  kısayol silinmez. İşlem önizleme + onayla, günlüğe yazılarak yapılır ve geri alınabilir.
- Görev Zamanlayıcı görevleri ve servisler bu sürümde listelenmez.

## 5. "Oyun dahili ekran kartında çalışıyor" → **Oyun GPU tercihi** (GPU sayfası)

- "Oyun ekle (.exe)" ile seçilen oyunlar için Ayarlar > Grafik'teki "Yüksek performans"
  tercihi yazılır (`HKCU\Software\Microsoft\DirectX\UserGpuPreferences`).
- Tek GPU'lu sistemde desteklenmez (gereksiz). Yalnız yerel sürücüdeki `.exe` yolları kabul edilir.

## 6. "Oyun sırasında arka planda video kaydediliyor" → **Arka plan kaydı kapalı**

- Xbox Game Bar "Olanları kaydet" (`HistoricalCaptureEnabled`) kapatılır. Windows'ta varsayılan
  kapalıdır; açıksa değişir. Ekran görüntüsü ve elle kayıt çalışır.

## 7. "MSVCP140.dll bulunamadı" → **Oyun bileşenleri** (Format Sonrası)

- Visual C++ 2015–2022 x64 ve x86, DirectX çalışma zamanı (eski D3DX/XAudio/XInput), .NET
  Masaüstü Çalışma Zamanı 8 — WinGet ile, kurulu olanlar atlanarak.
- DirectX Windows uygulama listesinde görünmez; `System32\d3dx9_43.dll` ile algılanır.

## 8. "Tek tıkla hazırla" → **Oyuncu modu**

- Hazır seçimlerin başında ve Sistem Kontrolü sayfasında.
- İçerik: Maksimum performans'ın tamamı (güç planı: Bitsum → Nihai → Yüksek Performans,
  zamanlayıcı, MMCSS, Win32 önceliği, Oyun Modu, ağ kısıtlaması, TCP otomatik ayar/CUBIC,
  seçili adaptörde akış denetimi/EEE, HAGS, fare ivmesi, animasyon/saydamlık) + arka plan
  kaydı kapalı + eklenen oyunlar için yüksek performanslı GPU.
- Kolaylık: tek fiziksel ağ adaptörü varsa otomatik hedeflenir; seçimden sonra önizleme
  doğrudan açılır. Bu sistemde uygulanamayanlar (ör. Windows 10'da global zamanlayıcı,
  Modern Bekleme'de Bitsum, oyun eklenmemişse GPU tercihi) nedenleriyle yazılır.
- İçermez: güvenlik azaltmaları (VBS/HVCI/Spectre/CFG), servis kapatma, MSI, Windows Update,
  pagefile, DNS. Uygulama her zaman önizleme penceresindeki onayla yapılır; geri yükleme
  noktası önerilir.

## 9. "Formattan sonra internet yok, ağ sürücüsü yok" → **Kurtarma Kiti**

- Formattan önce USB belleğe: üçüncü taraf sürücüler (ağ ayrı klasörde), kurulu uygulama
  listesi, Livn'in kendisi ve uygulanmış ayarları, isteğe bağlı Wi-Fi ve oyun kayıtları.
- Formattan sonra kitteki Livn internetsiz açılır, kiti kendiliğinden bulur; önce ağ sürücüsü
  kurulur. Uygulamalar ve ayarlar yine önizleme/onayla; kayıtlar üstüne yazılmadan döner.
- Bilerek yok: kişisel dosya yedeği (Belgeler/Resimler — boyut ve güvenilirlik), tarayıcı
  profilleri (eşitleme daha güvenli), lisans anahtarları.

## Bilerek yapılmayanlar

| İstek | Neden yok |
|---|---|
| "FPS paketi": Defender, VBS, Spectre azaltmalarını otomatik kapatma | Güvenliği azaltır; yalnız Güvenlik sayfasında, açık onayla |
| Nagle/TcpNoDelay, "ping düşüren" registry değerleri | Modern oyunların çoğunda etkisi gösterilmemiş; ölçülemeyen vaat |
| Ping'i garanti düşürme | Ping'i bağlantı türü, mesafe, hat ve modem yükü belirler; Livn ölçer ve sorunun yerini gösterir |
| BIOS'ta XMP/EXPO açma | Yazılımdan güvenle yapılamaz; yalnız tespit ve öneri |
| Sürücüleri üçüncü taraf kaynaktan otomatik indirme | Güvenilirlik/lisans; yalnız Windows Update ve üretici sayfası |
| Bufferbloat düzeltmesi | Modem/yönlendirici (SQM) tarafında yapılır; Livn ölçümle gösterir |

## Sıradaki adaylar

- Yük altında ping (indirme sırasında dalgalanma) ölçümü.
- Görev Zamanlayıcı başlangıç görevleri ve isteğe bağlı servislerin listesi (salt okunur).
- PresentMon ile oyun içi önce/sonra kare süresi kaydı.
- Sistem Kontrolü'nün kullanılabilirlik denetimlerini tamamen arka planda yenileme.
