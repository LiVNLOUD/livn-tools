# Kullanım rehberi

[← Ana sayfa](../README.md)

## Livn Tools v4 neyi farklı yapıyor?

- **Doğru raporlama.** Her değişiklik uygulandıktan sonra sistemden yeniden okunur. Sonuçlar
  ayrı gösterilir: *Başarılı*, *Zaten uygulanmış*, *Atlandı*, *Desteklenmiyor* (nedeniyle),
  *Başarısız* (hata ve çıkış koduyla), *Kısmen* ve *Yeniden başlatma gerekli*.
- **Gerçek geri alma.** Her değişiklikten önce özgün değer (değerin **olmaması** ve türü dahil)
  diske yazılır. İki ayrı işlem vardır: **Önceki ayara dön** (sizin değeriniz) ve
  **Windows varsayılanı** (belgelenmiş varsayılan). Uygulama yarıda kapanırsa bir sonraki
  açılışta kurtarma önerilir.
- **Önce önizleme.** "Önizle ve uygula…" hiçbir şeyi değiştirmeden her ayar için
  *mevcut değer → hedef değer* listesini gösterir.
- **Denetlenmiş ayarlar.** Etkisiz veya yanlış uygulanan eski ayarlar düzeltildi ya da
  kaldırıldı ([docs/TWEAK_AUDIT.md](TWEAK_AUDIT.md)). Hiçbir açıklama ölçüm olmadan
  FPS/gecikme kazancı vaat etmez.
- **Güvenlik özellikleri korunur.** VBS, HVCI, CFG ve Spectre/Meltdown azaltmalarını kapatan
  seçenekler hiçbir hazır seçime girmez ve açık onay olmadan uygulanmaz.
- **Tekrar uygulamak güvenli.** Güç planları sabit GUID ile bir kez oluşturulur; görevler tek
  adla kaydedilir; zaten uygulanmış ayara dokunulmaz.

## 🚀 Kurulum

Sürüme sabit kurulum için ana README içindeki GitHub adresini kullanın. livn.tr/win yönlendirmesinin v4 hedefi bu yayın kapsamında doğrulanmamıştır.

PowerShell'i açın ve yapıştırın:

```powershell
irm livn.tr/win | iex
```

- Dosyalar **sürüme sabitlenmiş** git etiketinden indirilir, her birinin **boyutu ve SHA-256**
  özeti doğrulanır; hepsi doğrulanmadan mevcut kurulum değiştirilmez.
- Yeni kurulum: `%LOCALAPPDATA%\LivnTools\app`; Başlat menüsüne **Livn Tools** kısayolu eklenir.
  Kullanıcı verileri (günlük, geri alma kayıtları, yedekler): `%LOCALAPPDATA%\LivnTools\data` — güncellemede **silinmez**.
  Daha önce `Belgeler\LivnTools` altına kurduysanız (v4 veya v3.5) güncelleme orada yapılır; geçmiş kayıtlar taşınmaz, yerinde kalır.
  Belgeler artık varsayılan değil: Denetimli klasör erişimi ve OneDrive eşitlemesi yazmayı engelleyebiliyordu.
- PowerShell 7, ISE veya 32-bit PowerShell'den çalıştırsanız da uygulama 64-bit Windows PowerShell 5.1 ile açılır.
- Önceki sürüm `app.prev` olarak saklanır. Geri dönmek için:
  `& ([scriptblock]::Create((irm livn.tr/win))) -Rollback`
- v3.5 kurulumunuz varsa `.reg` yedekleriniz `data\legacy-v3.5\Backups` altına taşınır; hiçbir şey silinmez.

> **Checksum ≠ imza.** SHA-256 kontrolü kesilmiş/bozuk indirmeleri ve etiketteki içeriğin
> beklenenden farklı olmasını yakalar. Betik de aynı kaynaktan (GitHub, HTTPS) geldiği için
> **yayıncı kimliğini kanıtlamaz**; projede kod imzalama (Authenticode) altyapısı yoktur.

### Manuel kullanım (ZIP / git)

1. Depoyu indirin ve bir klasöre açın.
2. `LivnTools.bat` dosyasına çift tıklayın (yönetici onayı istenir).
   Veriler bu durumda `<klasör>\data` altında tutulur.
   Başlatıcı önce engelleyen ilkeleri denetler: AppLocker/WDAC kısıtlı dil modu, yalnız imzalı betik (AllSigned)
   veya RemoteSigned + internetten indirildi işareti varsa nedenini yazar ve bekler. İşaretli ZIP için:
   ZIP'e sağ tık > Özellikler > Engellemeyi kaldır, sonra yeniden çıkarın.

### Kuru çalışma (sisteme dokunmadan deneme)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -STA -File .\Main.ps1 -DryRun
```
Bellek içi sahte bir sistemle açılır; registry, servis, BCD, ağ ayarlarına **dokunulmaz**.
Temizlik/bakım işlemleri yalnızca **simüle edilir** (dosya silinmez, uygulama kapatılmaz, DISM/SFC
vb. çalışmaz); betik çalıştırma, .reg içe aktarma ve Explorer yeniden başlatma devre dışıdır.
Bu koruma arayüzde değil motorun alt katmanındadır ve testlerle zorunlu tutulur.

## 🛠 Özellikler

| Sayfa | İçerik |
|---|---|
| **Sistem Kontrolü** (açılış sayfası) | Salt okunur kontrol: eksik/hatalı sürücüler, temel görüntü sürücüsü, ekran yenileme hızı, RAM hızı/kanal, disk sağlığı/TRIM/boş alan, son 14 günün mavi ekran / beklenmedik kapanma / WHEA kayıtları, bekleyen yeniden başlatma, Windows Update, bağlantı türü, oyun ayarları, başlangıç sayısı. Öneri + ilgili ekran düğmesi, rapor kaydetme, **Oyuncu modunu hazırla** |
| **Kurtarma Kiti** | **Formattan önce** USB belleğe: üçüncü taraf sürücüler (ağ önce), kurulu uygulama listesi, Livn kopyası ve ayarları, isteğe bağlı Wi-Fi ve oyun kayıtları. **Formattan sonra** internet yokken kitteki Livn'i açın: önce ağ sürücüsü, sonra diğerleri, Wi-Fi, uygulamalar, ayarlar, kayıtlar (var olan dosyanın üstüne yazmaz). Kit oluşturma sistem ayarı değiştirmez |
| **Hızlı Temizlik** | %TEMP%, Windows\Temp, Prefetch, Geri Dönüşüm Kutusu, küçük resim/yazı tipi önbelleği; Chrome/Edge/Brave/Vivaldi/Opera/Firefox/Tor önbellekleri; Discord/Slack/Teams/Zoom/Telegram/WhatsApp/Spotify; Steam/Epic/GOG/Battle.net/EA/Ubisoft/Rockstar/Xbox/Riot/Minecraft; DNS, çökme dökümleri, olay günlükleri, Windows Update ve Teslim İyileştirme önbellekleri |
| **Gelişmiş Temizlik** | DISM bileşen temizliği (/ResetBase ayrı ve uyarılı), SFC, DISM RestoreHealth, Disk Temizleme, bağlı olmayan USB depolama kayıtları |
| **Performans** | Güç planı (Dengeli, Yüksek Perf., Nihai, Bitsum, Hybred ×2), platform saati (HPET) zorlamasını kaldırma, dinamik tick, global zamanlayıcı istekleri (Win11), MMCSS oyun önceliği, Win32PrioritySeparation, SysMain/Windows Search, Windows Update erteleme, Oyun Modu, ISLC otomatik başlatma, bekleme/değiştirilmiş bellek listesi temizliği |
| **Ağ** | Bağlantı ölçümü (modem / internet / oyun sunucusu: ping, dalgalanma, kayıp, önceki ölçümle karşılaştırma), DNS hız testi, DNS seçimi (Cloudflare/Google/Quad9, geri alınabilir), AutoTuning, RSS, ECN, RSC, CUBIC, NetworkThrottlingIndex, TcpAckFrequency, Flow Control, EEE/Green Ethernet, Adaptive IFS, LLMNR, mDNS, TCP/IP-Winsock sıfırlama |
| **Güvenlik ve Giriş** | VBS, HVCI, Spectre/Meltdown, CFG (**ileri düzey, güvenliği azaltır**), disk belleği yönetimi, kapanışta disk belleğini temizleme, fare ivmesi |
| **GPU ve MSI** | Oyun başına yüksek performanslı GPU tercihi (iki GPU'lu sistemler), HAGS açık tercihi (Windows 10 2004+ ve sürücü desteği sorgusu olumsuz değilse), listeden seçilen tek ekran kartı veya ağ kartı için MSI tercihi (yalnız aygıt donanım olarak MSI/MSI-X bildiriyorsa). Aygıt listesinde ad ve kesme desteği görünür; aygıt kimliği gösterilmez. Windows Grafik Ayarları bağlantısı ve salt okunur durum okuma. |
| **Gizlilik** | DiagTrack, dmwappush, Xbox servisleri, tanılama verisi düzeyi, uygulama telemetrisi, WER, etkinlik geçmişi, Cortana, CEIP, tüketici deneyimleri, reklam kimliği, uyarlanmış deneyimler, mürekkep/yazma, Bing önerileri, önerilen uygulamalar, OneDrive kaldırma |
| **Windows Ayarları** | Animasyonlar, saydamlık, koyu mod, JPEG kalitesi, menü gecikmesi, uzantılar, "Bu Bilgisayar", klasik sağ tık (Win11), NumLock, uzun yol, BSOD ayrıntıları, tam bellek dökümü, olay günlüğü boyutu, hazırda bekletme |
| **Başlangıç Uygulamaları** | Açılışta başlayan uygulamaları Görev Yöneticisi yöntemiyle kapatma/açma; uygulama silinmez, geri alınabilir |
| **Değişiklik Geçmişi** | Livn Tools'un değiştirdiği her ayar, özgün değeri ve işlem günlüğü; seçerek geri alma, durum yedeğinden geri yükleme, v3.5 .reg içe aktarma |
| **Betik Çalıştır** | .ps1 / .bat / .cmd içe aktarma ve çalıştırma (geri alma sistemine **dahil değildir**) |

Her ayar satırında: seçim kutusu (ne uygulanacak), **mevcut sistem durumu** rozeti, risk ve
kanıt düzeyi, yeniden başlatma gereksinimi ve — desteklenmiyorsa — nedeni gösterilir.

### Ağ adaptörü seçimi

NIC sürücü ayarları ve ACK için Ağ sayfasından tek bir adaptör seçin. TCP/IP (genel) ayarları sistem genelindedir; RSS hem global hem seçilen adaptör tercihini içerir. Sürücü tercihleri bağlantı yeniden başlatılmadan kaydedilir; etkinleşmeleri için bilgisayarı yeniden başlatın.

### Fare, menü ve pencere animasyonu

Bu üç tercih Windows API'siyle oturumda uygulanır ve yeniden okunur. Menü süresini Windows Ayarları sayfasından seçin. Farklı bir yönetici hesabı veya doğrulanamayan oturum sahibi varsa bu işlemler engellenir. Önceki ayara dönüş, oturum değeriyle kalıcı registry kaydını ayrı geri yükler. Diğer uygulamaların görsel davranışlarını kontrol edin; tüm animasyonları kapatma veya FPS artışı vaat edilmez.

### Hazır seçimler

| Hazır seçim | İçerik |
|---|---|
| **Oyuncu modu** | Maksimum performans'ın tamamı + arka plan oyun kaydı kapalı + eklenen oyunlar için yüksek performanslı GPU. Tek ağ adaptörünü otomatik hedefler ve önizlemeyi doğrudan açar; güvenlik azaltması, servis kapatma, MSI ve DNS içermez |
| **Temel** | Oyun Modu, zorlanmış platform saatini kaldırma, TCP otomatik ayar ve CUBIC (Windows varsayılanları), dosya uzantıları, uzun yollar |
| **Gizlilik** | DiagTrack servisi, telemetri/uygulama uyumluluğu/CEIP ilkeleri, etkinlik geçmişi, Cortana, tüketici deneyimi, reklam kimliği, kişiselleştirme, mürekkep/yazma, Bing araması, öneriler |
| **Görünüm** | Koyu tema, dosya uzantıları, "Bu Bilgisayar", klasik sağ tık (Win11), Widgets/arama simgesi, Görevi sonlandır |
| **Akıcı görünüm** | Animasyonlar, görsel efektler, görev çubuğu animasyonu, saydamlık |
| **Maksimum performans** | Güç planı (Bitsum → Nihai → Yüksek Performans; ilk desteklenen), zamanlayıcı, MMCSS, Win32 önceliği, Oyun Modu, ağ kısıtlaması, HAGS, seçili adaptörde akış denetimi/EEE, fare ivmesi, animasyonlar |

Hazır seçimler yalnızca **işaretler**; uygulamadan önce önizleme gösterilir. Seçimden sonra kaç ayarın
işaretlendiği ve bu sistemde hangilerinin neden atlandığı yazılır. Hiçbiri güvenlik özelliklerini kapatmaz;
yüksek riskli, kanıtı doğrulanmamış, MSI, servis kapatma (DiagTrack hariç), Windows Update ve pagefile
ayarları hazır seçime girmez. Maksimum performans FPS artışı vaat etmez; dizüstünde pil ve ısıyı artırır.

### Geri alınamayan işlemler

Dosya temizliği, DISM/SFC, OneDrive kaldırma, TCP/IP sıfırlama ve kullanıcı betikleri geri alma
kapsamında **değildir**; arayüzde "Geri alınamaz" olarak işaretlenir. Sistem Geri Yükleme
noktası isteğe bağlıdır ve **oluşturulduğu doğrulanmadan başarılı gösterilmez** (Windows 24
saatte bir nokta sınırı uygular).

## ⚙️ Gereksinimler

- Windows 10 22H2 veya Windows 11 (x64). Ayrıntı: [docs/SUPPORT_MATRIX.md](SUPPORT_MATRIX.md)
- Windows PowerShell 5.1 (Windows'ta yerleşik)
- Yönetici yetkisi (kuru çalışma hariç)

## 🧪 Geliştirme ve test

```powershell
# Pester 5 ve PSScriptAnalyzer gerekir
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Invoke-Tests.ps1
```
Testler bellek arka ucunu kullanır ve **gerçek sistem ayarlarına dokunmaz**. Gerçek Windows
doğrulaması: [docs/WINDOWS_TEST_CHECKLIST.md](WINDOWS_TEST_CHECKLIST.md).
Mimari: [docs/ARCHITECTURE.md](ARCHITECTURE.md). Sürüm oluşturma: `tools\Build-Release.ps1`.

## ⚠️ Sorumluluk reddi

Bu araç registry, servis, önyükleme (BCD) ve ağ ayarlarını değiştirir. Değişiklikler geri
alınabilir şekilde kaydedilse de kullanım kendi sorumluluğunuzdadır. Güvenlik özelliklerini
kapatan seçenekleri yalnızca etkilerini biliyorsanız kullanın.

Format sonrası ve oyun odaklı özelliklerin gerekçesi, nasıl çalıştıkları ve bilerek eklenmeyenler:
[docs/KESKE_LISTESI.md](KESKE_LISTESI.md).

Üçüncü taraf dosyalar (Bitsum/TheHybred güç planları, ISLC) ve dağıtım izinleri:
[docs/THIRD_PARTY.md](THIRD_PARTY.md). Depoda henüz bir LICENSE dosyası yoktur.

---

<div align="center">

**[livn.tr](https://livn.tr)** · **[GitHub](https://github.com/LiVNLOUD/livn-tools)**

</div>

### Geliştirme sürümünde kullanıcı ve güncelleme kapsamı

Kullanıcıya özel registry ayarları yalnızca işlem hesabı masaüstü oturumunun sahibiyle eşleştiğinde değiştirilebilir. Yeni yedekler hesap kimliği içerir; başka hesaba ait veya hesap kimliği bulunmayan eski yedekler otomatik geri yüklenmez, kayıtları korunur. Bu koruma kullanıcı betiklerinin veya dış .reg dosyalarının içeriğini denetlemez.

Özellik ve kalite/güvenlik güncellemesi ertelemesi ayrı seçeneklerdir; hazır seçimlere dahil değildir. Eski özellik erteleme GPO yöntemi Windows 11'de kapalıdır. Kalite ertelemesi güvenlik yamalarını da geciktirir. Registry kaydının doğrulanması etkin Windows Update/MDM takviminin doğrulandığı anlamına gelmez.

Bitsum ve iki Hybred plan dosyası kaynak paketin `_Files` klasöründedir; içe aktarmadan önce sabitlenmiş SHA-256 ile doğrulanır, değiştirilmiş dosya içe aktarılmaz. v4.0.1 itibarıyla `win.ps1`, standart ZIP ve `Build-Release.ps1` varsayılanı bu üç planı ve ISLC 1.0.4.8 tam paketini içerir. ISLC otomatik çalıştırılmaz.


### İsteğe bağlı performans araçları

Performans sayfasındaki **Harici performans araçları** alanından ISLC, ParkControl, Process Lasso ve PresentMon'un resmî sayfalarını açabilirsiniz. Bu bağlantılar kurulum yapmaz. ISLC'nin resmî paketini kalıcı bir klasöre çıkarıp uygulama dosyasını seçin; RAM'e göre hesaplanan başlangıç profilini inceleyin ve aşağıdaki otomatik başlatma ayarını önizleyip uygulayın. Profil ölçülmüş optimum değildir; mevcut ISLC timer ayarları korunabilir.

Bitsum veya donanım üreticinizin aracıyla kurulan planlar için **Kurulu planları yenile → planı seç → Seçili kurulu güç planını etkinleştir → Önizle ve uygula** yolunu izleyin. Önceki plan geri alınabilir. Windows güç modları kullanan cihazlar için Windows Ayarları bağlantısı vardır. Ayrıntılar ve doğrulama sınırları: `docs/THIRD_PARTY.md`.


### Format sonrası kişisel kurulum

- **Akıcı görünüm** hazır seçimi: pencere/görev çubuğu animasyonları, menü/açılır liste/ipucu/seçim solması/istemci alanı efektleri ve saydamlık. Yazı yumuşatma ile küçük resim tercihleri korunur; Windows'un bütün görsel efekt kutularına karşılık geldiği iddia edilmez. Ayrıca sola hizalama, arama/Widgets simgesini gizleme ve desteklenen Windows 11 sürümlerinde Görevi sonlandır seçenekleri vardır.
- Ayar sayfalarında istediklerinizi seçip **Format Sonrası > Seçimleri profile kaydet** kullanın. Profil yalnız taşınabilir düşük riskli seçimleri ve kurulum listesini saklar. Menü süresi seçilmişse eklenir. Donanım hedefleri, güvenlik değişiklikleri, temizlik, uygulama kaldırma, SID, dosya yolları ve geri alma geçmişi taşınmaz. Dosyayı format öncesinde başka diske alın.
- **Profil yükle** yalnız seçimleri yükler. **Yüklenen ayarları önizle** yeni bilgisayardaki destek durumunu ve mevcut değerleri okuyarak normal işlem motorunu kullanır; önceki değerler yeni bilgisayardan kaydedilir.
- Kurulum kataloğu 40 uygulama / 9 kategori içerir. Ad, açıklama ve paket kimliğiyle arama; kategori ve **Yalnız seçtiklerim** filtreleri kullanılabilir. Filtre dışında kalan seçimler korunur ve sayılır; profil kaydı ve kaydırılabilir kurulum önizlemesi tüm seçimleri kapsar. Başlangıçta hiçbir uygulama seçili değildir.
- **Seçili uygulamaları kur** WinGet'in tam paket kimlikleriyle ve ayrı onayla çalışır. Kaynak/paket sözleşmeleri onaylanır, kurulu olanlar yükseltilmez; kurulum sonrası envanter kontrol edilir. WinGet'in kurulu olması gerekir; sessiz bootstrap eklenmedi. İptal paketler arasında uygulanır. Paket yükleyicisi pencere açabilir; kurulumlar ayar geri alma günlüğüne dahil değildir.
- Her uygulamanın yanında **Kurulu / Kurulu (WinGet dışı) / Kurulu değil / Durum okunamadı** gösterilir. WinGet'in eşleştiremediği kurulumlar (ör. üreticinin kendi yükleyicisiyle kurulan Brave) Windows "Yüklü uygulamalar" kayıtlarındaki adla tamamlanır; bu kayıt "kurulu değil" kararı vermez, kurulumda da yeniden kurulmaz. Envanter WinGet ile salt okunur alınır: sayfa açıldığında arka planda (en fazla 10 dakikada bir) ve **Kurulum durumunu yenile** ile (en sık 30 saniyede bir). WinGet yoksa veya sorgu başarısızsa uygulamalar "kurulu değil" sayılmaz; neden ve **Yeniden dene** gösterilir. Okuma kurulum, güncelleme veya kaynak sözleşmesi kabulü yapmaz; WinGet kaynak dizinini güncellemek için ağa erişebilir. Arama, kategori ve seçimler korunur; kurulu görünen bir uygulama seçilse de yükseltilmez.
- İsteğe bağlı Windows uygulamalarını önce denetleyip tek tek seçin. Yalnız mevcut kullanıcıdan kaldırılır; Store, framework, sürücüler ve Xbox altyapısı topluca kaldırılmaz. Kaldırma uygulama verilerini silebilir. Store'dan yeniden kurmak veri kurtarma değildir.

### Temizlik önizlemesi

Hızlı ve Gelişmiş Temizlik sayfalarındaki **Önizle (boyut)…** seçili öğeler için dosya sayısını ve tahmini temizlenebilir boyutu, hedef klasörleri, kapsamı (filtre, alt klasör, yaş), korunan verileri ve taranamayan veya güvenlik sınırı dışındaki alanları gösterir. Önizleme dosya silmez veya değiştirmez, uygulama kapatmaz, bakım komutu çalıştırmaz. Silme ile aynı seçim kurallarını kullanır; silme anında yollar, kapsam ve bağlantılar yeniden denetlenir, dosyalar o arada değişmiş olabilir. DISM, SFC, DNS, olay günlüğü, Geri Dönüşüm Kutusu gibi bakım işlemleri için boyut tahmini gösterilmez. Kuru çalışmada gerçek dosya sistemi taranmaz. Temizlik geri alınamaz; önizleme bir geri alma garantisi değildir.

### Launcher temizliği

Başlatıcıların hiçbiri rutin temizliğe otomatik seçilmez. Arka plan yardımcıları dahil ilgili süreç açıkken işlem atlanır; launcher veya genel Java süreci zorla kapatılmaz. Uygun olmayan seçenekler varsayılan filtreyle gizlenir; filtre kaldırıldığında nedenleri görülebilir.

- Steam, Epic ve GOG: web önbelleğinin belirli alt klasörleri; hesap/oturum kökleri korunur. Steam `steamapps`, `userdata`, Workshop ve shadercache silinmez.
- Minecraft: yalnız varsayılan `.minecraft/logs` ve `crash-reports` içinde 7 günden eski dosyalar. Dünyalar, modlar, assets, versions ve hesap dosyaları kapsam dışı; Bedrock ve özel instance'lar desteklenmez. Başka Java uygulaması açıksa da ihtiyat gereği atlanabilir.
- Rockstar: yalnız 7 günden eski mevcut Launcher çökme raporları; profil/Social Club silinmez. `Launcher` süreç adıyla çakışmada ihtiyat gereği atlanır.
- Ubisoft: registry/default yolunda `upc.exe` aranır; bulunmazsa tahmini klasör temizlenmez. HTTP önbelleği ve 7 günden eski loglar; oyun/savegames korunur.
- Riot: belirli istemci cache klasörleri ve 7 günden eski VALORANT logları; Vanguard ve oyun yapılandırması korunur.
- EA: üreticinin **Yardım > App Recovery > Clear cache** akışı kullanılmalı. Xbox için Windows **Onar** seçeneği tercih edilmeli. EA/Xbox/Battle.net otomatik silme mevcut doğrulama kapsamı dışında tutulur.

Bu değişiklikler Linux Memory testleriyle denetlenir; Windows PowerShell 5.1/WPF, gerçek WinGet/Appx davranışı ve güncel launcher dosya yerleşimleri ayrıca kabul testi gerektirir.
