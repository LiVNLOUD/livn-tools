# 13 Ekim 2026 — geliştirme (4.0.0, henüz etiketlenmedi)

- Kurtarma kitinde başarısız/eksik Livn kopyası artık başarılı raporlanmaz; zorunlu uygulama dosyaları denetlenir.
- İptal, kısmi başarı ve hata kit.json, KIT_OKU.txt ve arayüzde görünür; iptal sonrası yeni bölümler başlamaz.
- Kopyalamada eksik kaynak, iç içe kaynak/hedef ve bağlantı noktaları denetlenir; var olan oyun kayıtları korunur.
- DNS geri alma IPv4/IPv6 otomatik/statik tercihlerini ayrı saklar. Eski günlükler eski şemayla okunur.
- Yayın oluşturma LICENSE yokken çalışır; lisans üretmez/değiştirmez, varsa pakete ekler. CheckOnly eski manifesti reddeder.
- Uygulama sayısı 40 / kategori sayısı 9 olarak düzeltildi. Windows 5.1/WPF otomatik doğrulama akışı eklendi.

## Kurtarma Kiti (formattan önce / sonra) — 2 Ekim 2026

- Yeni **Kurtarma Kiti** sayfası. **Formattan önce:** seçilen USB belleğe/diske üçüncü taraf sürücü paketleri (ağ, diğer donanım; ekran kartı isteğe bağlı), kurulu uygulama listesi, Livn Tools'un kendisi ve uygulanmış Livn ayarları, isteğe bağlı Wi-Fi profilleri (parola düz metin uyarısıyla) ve oyun kayıtları (Saved Games, Belgeler\My Games) kopyalanır. Sistem sürücüsü hedef olarak reddedilir. Kit oluşturma hiçbir sistem ayarını değiştirmez.
- **Formattan sonra:** kitteki `LivnTools\LivnTools.bat` internetsiz çalışır; Livn kiti kendiliğinden bulur ve sayfayı açar. Sıra: ① sürücüler (önce ağ, sonra diğerleri, ekran kartı ayrıca sorulur; öncesinde geri yükleme noktası) → ② Wi-Fi → ③ uygulamalar Format Sonrası'nda seçili gelir → ④ Livn ayarları önizlemeyle uygulanır → ⑤ oyun kayıtları var olan dosyaların üstüne yazılmadan geri kopyalanır. `KIT_OKU.txt` Livn çalışmazsa elle `pnputil` komutunu içerir.
- Kit dosyası güvenilmeyen girdi sayılır: şema, kit dışına çıkan yollar, bilinmeyen ayar/uygulama kimlikleri ve bu PC'ye özgü (adaptör, MSI, DNS, başlangıç) ayarlar atılır. Kuru çalışmada oluşturulan kit **DENEME** olarak işaretlenir, gerçek modda reddedilir.
- Windows doğrulayıcısı artık ağ/MSI aygıt seçimini **gerçek WPF ComboBox olaylarıyla** sınar (2 Ekim seçim hatası türünü yakalamak için) ve Kurtarma Kiti panelini ölçer.

## Düzeltme: adaptör seçimi görülmüyordu — 2 Ekim 2026

- Düzeltildi: Ağ sayfasında adaptör seçilse de DNS ve adaptör ayarları "Önce ağ sayfasından tek bir adaptör seçin" nedeniyle Desteklenmiyor kalabiliyordu. Seçim, WPF'te SelectionChanged anında henüz güncellenmemiş olabilen `SelectedValue` yerine `SelectedItem`'den okunuyor. Aynı düzeltme MSI aygıtı, kurulu güç planı ve harici araç listelerine uygulandı; arayüzde `SelectedValue` okunması testle yasaklandı.
- Seçili hedef artık listenin altında yeşil "Seçili hedef: …" satırıyla görünür; seçilmemişse sarı uyarı. Tek fiziksel adaptör varsa otomatik hedeflenir (ayar uygulamaz); sistem bilgisi yenilenince önceki seçim GUID ile geri yüklenir.
- Hedef seçilmemiş ayarların nedeni "Destek kontrolü yapılamadı" hatası yerine açık yönlendirme olarak gösterilir.

## Kullanıcı gözüyle: Sistem Kontrolü, bağlantı ölçümü, başlangıç, Oyuncu modu — 2 Ekim 2026

- Yeni açılış sayfası **Sistem Kontrolü** (salt okunur): sürücüler, ekran kartı sürücüsü, yenileme hızı, RAM hızı/kanal, sistem diski, son 14 günün çökme/WHEA kayıtları, bekleyen yeniden başlatma, Windows Update, bağlantı türü, oyun ayarları, başlangıç sayısı; öneri ve sabit listeden ekran/sayfa/ayar düğmeleri; rapor kaydetme.
- Ağ: **bağlantı ölçümü** (modem / internet / oyun sunucusu; ping, dalgalanma, kayıp; yorum ve önceki ölçümle karşılaştırma), **DNS hız testi**, **DNS seçimi** (Cloudflare / Google / Quad9; önceki elle DNS veya DHCP'ye dönüş).
- Yeni **Başlangıç Uygulamaları** sayfası (Görev Yöneticisi yöntemi, geri alınabilir).
- GPU: oyun başına yüksek performanslı GPU tercihi. Performans: arka plan oyun kaydı kapalı.
- Format Sonrası: Visual C++ x64/x86, DirectX çalışma zamanı, .NET Masaüstü 8 (DirectX dosyadan algılanır).
- Yeni hazır seçim **Oyuncu modu**: Maksimum performans + arka plan kaydı + oyun GPU tercihi; tek adaptörü otomatik hedefler ve önizlemeyi doğrudan açar. Güvenlik azaltması, servis kapatma, MSI, DNS içermez.
- Düzeltildi: yeni modüller ağdan kurulum bildirimine eklendi; bildirimin tüm kaynak dosyaları içerdiği artık testle zorunlu.
- Linux PS 7.4.6: 471 test geçti, 0 başarısız; PSSA 25 dosya, 0 hata/uyarı. Windows'ta çalıştırılmadı. Ayrıntı: docs/KESKE_LISTESI.md.

## Uyumluluk ve WinGet sağlamlaştırması — 2 Ekim 2026

- Düzeltildi: `net.ackfreq` Windows'un `{GUID}` biçimiyle `Interfaces\{{GUID}}` gibi var olmayan bir anahtara yazıp başarılı görünüyordu.
- Uygulama her zaman 64-bit Windows PowerShell 5.1 ile açılır (32-bit kabuk, PowerShell 7, ISE yeniden başlatılır). Yükseltilmiş yeniden başlatmada konsol penceresi gizli; sonda `\` olan `-DataRoot` bozulmaz.
- `LivnTools.bat`: kısıtlı dil modu, GPO AllSigned ve RemoteSigned + indirildi işareti için görünür ön kontrol.
- Kurulum: yeni kurulumlar `%LOCALAPPDATA%\LivnTools` (Belgeler'deki mevcut kurulum yerinde güncellenir), Başlat menüsü kısayolu, kökteki başlatıcı uygulamanın kendi başlatıcısıdır.
- Süreç ve Explorer kapatma yalnız bu oturum; Explorer'ı Winlogon başlatır. Farklı yönetici hesabıyla kullanıcı profili temizliği atlanır.
- Boş Geri Dönüşüm Kutusu hata sayılmaz; harici komutlara girdi verilmez (pause beklemez) ve kullanıcı betikleri iptal edilebilir; konsol kod sayfası doğru seçilir; içe aktarılan betiğin kodlaması tahmin edilir; `x..y` adlı klasörler tüm öğeyi düşürmez; yönlendirilmiş Masaüstü ve makine genelindeki OneDrive dikkate alınır.
- Windows 11 UCPD: Widgets simgesi değeri korunuyorsa denenmez; yeni "Widgets kapalı (ilke)" seçeneği ve Görünüm hazır seçiminde otomatik geçiş.
- Modern Bekleme (S0): Bitsum/Ultimate/Hybred HighPerf desteklenmiyor olarak gösterilir, Windows güç modu önerilir. Bozuk performans sayaçlarında bellek listesi temizliği yine yapılır.
- Bağlantılar ve Ayarlar kullanıcının kabuğu üzerinden açılır (yönetici tarayıcı yok).
- WinGet: PATH dışı yol bulma, ≥1.6 sürüm kontrolü, hata kodlarının Türkçe açıklaması (zaten kurulu → atlandı, yeniden başlatma → başarı + uyarı), toplu kurulumda tek envanter, "WinGet'i edinin / güncelleyin" düğmesi (Store veya Microsoft Learn; otomatik indirme yok).
- Linux PS 7.4.6: 434 test geçti, 0 başarısız; PSSA 22 dosya, 0 hata/uyarı. Windows'ta çalıştırılmadı.

## Hazır seçimler, güç planı dosyaları, GPU/MSI ve uygulama algılama — 1 Ekim 2026

- Hazır seçimler genişletildi (Temel 6, Gizlilik 12, Görünüm 7, Akıcı görünüm 4 ayar) ve **Maksimum performans** eklendi. Seçimden sonra işaretlenen sayı, seçilen güç planı ve bu sistemde atlananlar nedenleriyle yazılır. Güvenlik azaltması, yüksek risk, doğrulanmamış kanıt, MSI, Windows Update, pagefile ve genel servis kapatma hiçbir hazır seçime girmez (testle zorunlu).
- Bitsum ve iki Hybred plan dosyası kullanıcının v3.5 paketinden `_Files` altına geri kondu; SHA-256 değerleri sabitlendi, destek kontrolünde ve içe aktarma anında doğrulanır. Lisans durumu açık; `win.ps1`/Build-Release varsayılanı dosyaları hâlâ içermez.
- GPU ve MSI: HAGS tercihi (Windows 10 2004+, sürücü WDDM 2.7 yetenek sorgusu) ve listeden seçilen aygıt için MSI tercihi etkinleştirildi. MSI yalnız aygıt donanım olarak MSI/MSI-X bildiriyorsa yazılır; yüksek riskli kalır ve hazır seçimlere girmez. Aygıt listesi ve durum metni aygıt kimliği göstermez. Durum okuma sürücünün bildirdiği HAGS desteği ve etkin durumunu gösterir.
- Format Sonrası: WinGet'in eşleştiremediği kurulumlar (ör. Brave) Windows "Yüklü uygulamalar" kayıtlarındaki adla "Kurulu (WinGet dışı)" görünür ve yeniden kurulmaz. WinGet okunamazsa bu kayıtta olmayanlar yine "durum okunamadı" kalır.
- Linux PS 7.4.6: 404 test geçti, 0 başarısız; PSSA 22 dosya, 0 hata/uyarı. Windows/WPF, gerçek HAGS/MSI/güç planı davranışı ve performans etkisi doğrulanmadı.

## r3 bağımsız denetim, envanter ve temizlik önizlemesi — 1 Ekim 2026

- Düzeltildi: `Write-LtFileAtomic` hiç atomik değiştirme yapmıyordu (`$null` → `""`); geri dönüş yolundaki hata ledger dosyasını kaybettirebiliyordu. Yarım kalmış `.bak` artık okunurken kurtarılır.
- Düzeltildi: Ayar uygulanırken journal yazımı da başarısız olursa geri sarma atlanıyor ve önceki eylemler sistemde kalıyordu. Geri sarma artık her durumda çalışır; kayıt hatası ayrıca bildirilir.
- Önceki ayara dönüş önizlemesi, Livn uyguladıktan sonra değişmiş değerleri işaretler.
- Format Sonrası: 36 uygulama için kurulu / kurulu değil / durum okunamadı göstergesi; arka planda, sınırlı sıklıkta, elle yenilenebilir; hata ve yeniden deneme açık. Kurulu uygulamalar yükseltilmez.
- Temizlik: salt okunur önizleme (dosya sayısı, tahmini boyut, kapsam, korunan veri, taranamayan alanlar). Bakım işlemleri için sayı uydurulmaz. Önizleme geri alma garantisi değildir.
- Testler dağıtılmayan üçüncü taraf ikililerine bağlı değil.
- Düzeltildi: Gelişmiş Temizlik sonunda "toplam 0 B silindi" yazıyordu; DISM/SFC/USB gibi işlemler açılan alanı ölçmediği hâlde 0 olarak toplanıyordu. Artık ölçülen ve ölçülmeyen işlemler ayrı raporlanır; Disk Temizleme boş alan farkını ve farkın olmadığını açıkça bildirir.

## Windows test teslimi — 29 Eylül 2026

- Linux PS 7.4.6 doğrulaması: 307 test geçti, 0 başarısız/atlandı (48.33 s); PSSA 22 dosya, 0 hata/uyarı; parser 44 dosya. Windows davranışı doğrulanmadı.
- Test-Windows.bat ve tools/Invoke-WindowsCheck.ps1: yönetici yetkisi istemeden SmokeOnly kontrolü; transcript ve hata ayrıntıları tests/results altında. Modül indirme/kurma yok. -Full yalnız mevcut Pester/PSSA ile tam paketi çalıştırır.
- Test-Arayuz.bat yalnız -DryRun ile açar; kayıtları tests/results/ui-data altında tutar. Normal başlatıcı değiştirilmedi. Yeni kontrol betiği analiz listesine eklendi.
- Kullanıcıda gerçek Windows doğrulaması için tek test ZIP'i hazırlanıyor; release oluşturucu kullanılmadı, etiket/push yok. Üçüncü taraf _Files içerikleri dağıtılmıyor. Windows doğrulaması bu ortamda yapılmadı.

## Windows kabul aracı — 28 Eylül 2026

- Gizli yardımcı panellerin layout kontrolü dışında kaldığı tespit edildi. Windows doğrulayıcı artık yedi paneli ayrı ayrı görünür yapıp 980×620 ve 1240×820 boyutlarında ölçüyor. Format Sonrası listeleri Memory kataloglarıyla dolduruluyor; ilk seçili satırın oluşturulması ve panellerin sıfır olmayan boyutları denetleniyor. Native ayar yazımı ve uygulama işçileri başlatılmıyor.
- Değişen betik PS 7.4.6 parser ve PS 5.1 uyumluluk analizinden hatasız geçti. Linux'ta Windows kontrolünün başlamadan reddedildiği doğrulandı. WPF senaryoları burada çalıştırılmadı; görsel/DPI/binding kabulü tamamlandı iddiası yok. Ürün kodu değişmedi; önceki 305 test sonucu aynı ürün commit'ine aittir, bu tur tam paket tekrar çalıştırılmadı.
- Kontrol listesi güncellendi. ZIP/push/release yok; sonraki zorunlu aşama gerçek Windows PowerShell 5.1 çalıştırması.

## Format sonrası kurulum ve launcher temizliği — 28 Eylül 2026

- Format Sonrası sayfası: izinli kullanıcı ayarları ve uygulama kimliklerini JSON profiline kaydetme/yükleme. Yükleme yalnız seçim yapar; uygulama ayrı önizleme/onayla hedef bilgisayarın önceki değerlerini kaydeder. Donanım ayarları, ledger, komutlar ve dosya yolları taşınmaz.
- Akıcı görünüm hazır seçimi; beş SPI animasyon efekti, görev çubuğu hizası, arama/Widgets simgelerini gizleme ve desteklenen Windows 11 sürümünde Görevi sonlandır seçeneği. Yazı yumuşatma korunur; beş efektin etkin değerleri geri alınır, ortak UserPreferencesMask bütünü kopyalanmaz.
- Seçili uygulamaları WinGet üzerinden kurma (mevcut olanı yükseltmeden atlama, kurulum sonrası envanter doğrulama); sınırlı isteğe bağlı Appx listesini yalnız mevcut kullanıcıdan kaldırma. Ayrı açık onay, Memory yalıtımı ve paketler arasında iptal. Kurulum/kaldırma için işlem geri alma garantisi yok; kaldırma uygulama verisini silebilir.
- On launcher girdisi korundu; varsayılan seçili değiller ve açık launcher varsa işlem atlanır. Java dahil süreçler zorla kapatılmaz. Steam/Epic/GOG web temizliği Cache/Code Cache/GPUCache ile sınırlı; hesap verileri korunur. Minecraft yalnız yedi günden eski log/çökme raporları. Rockstar kapsamı daraltıldı; Ubisoft kurulum yolu doğrulanır. EA/Battle.net/Xbox otomatik temizliği doğrulanmış kapsam oluşana kadar devre dışı. Kullanılabilir öğe filtresi eklendi.
- Linux PowerShell 7.4.6: **305 geçti / 0 başarısız / 0 atlandı** (61.96 s); PSSA **21 ürün dosyası / 0 hata / 0 uyarı**, parser 43 dosya. Gerçek geçici dosya testleri hesap verisinin korunmasını ve yaş filtresini sınadı; Windows sistem çağrıları Memory/mock ile sınandı. C# yardımcı kodu .NET üzerinde C# 5 dil düzeyinde derlendi; Windows PowerShell 5.1/WPF doğrulaması değildir.
- Windows/WPF, native SPI, gerçek WinGet/Appx, launcher sürüm/yol davranışı ve performans ölçümü bekliyor; kontrol listesi güncellendi. ZIP/bundle, push, tag veya release yok.

## İsteğe bağlı performans araçları — 28 Eylül 2026

- Linux PS 7.4.6: 274 test geçti, 0 başarısız/atlandı; PSSA 20 dosya, 0 hata/uyarı. Windows doğrulaması değildir.

- Performans sayfasına resmî araç bağlantıları, ISLC dosya seçimi/başlangıç profili ve kurulu güç planı seçimi eklendi. Yeni binary veya ZIP üretilmedi; kaynak ISLC 1.0.3.7 değiştirilmedi.
- ISLC görevi artık sabit RAM/2 yerine sınırlı %10 başlangıç eşiği kullanır (512–4096 MB); gerçek MB algılanır, eksik donanımda tahmin yapılmaz. Parametreler görünür; mevcut config/timer ayarları değiştirilmez. Performans optimumu iddiası yok.
- Kurulu plan GUID ile doğrulanır, içe aktarılmadan etkinleştirilir ve önceki plana dönülebilir. DryRun resmî bağlantılardan bile uygulama başlatmaz.
- Otomatik indirme, 1.0.4.8 ikili/CLI doğrulaması, gerçek Windows/WPF ve performans ölçümü açık. Process Lasso/PresentMon için yalnız resmî bağlantı, otomatik kontrol yok.

## Yayın oluşturucu doğruluğu — 26 Eylül 2026

- Build-Release artık zorunlu dosyaları (LICENSE dahil) eksik/boşsa atlamaz; manifest değişmeden hata verir. İstenen sürümün modüldeki LtVersion ile eşleşmesini, repo adını ve tek manifest bloğunu doğrular. Manifest yol metinlerinde tek tırnak kaçışlanır.
- -CheckOnly salt okunur yapı kontrolüdür; manifest/ZIP üretmez ve -Zip ile birlikte kullanılamaz. Gerçek depoda LICENSE eksikliği nedeniyle beklendiği gibi reddedildi. Lisans kullanıcı adına seçilmedi. Bu kontrol test veya üçüncü taraf izin onayı yerine geçmez.
- ZIP önce ayrı geçici arşive yazılır; sıkıştırma başarısızsa önceki ZIP korunur. Paketleme kopyalarının hash/boyutu kontrol edilir; geçici dosyalar finally ile temizlenir. Manifest güncellemesi ZIP işleminden önce gerçekleşir; tüm işlemin tek atomik transaction olduğu iddia edilmez.
- 7 davranış testi eklendi (salt okunur kontrol, gerçek manifest hashleri, eksik dosya, sürüm uyuşmazlığı, yinelenen manifest, çelişen seçenekler, sıkıştırma hatası). Bunlar yalnız geçici fixture kullanır; proje release paketi üretilmedi.
- Linux PowerShell 7.4.6: **259 geçti / 0 başarısız / 0 atlandı** (45.35 s); PSSA **20 dosya / 0 hata / 0 uyarı**. Son paketleme dosyası ayrıca analiz edildi, bulgu yok. Önceki Windows/WPF sınırları değişmedi.
- Kalan: gerçek Windows kabulü, görsel UI kontrolü, proje lisansı kararı, üçüncü taraf dağıtım kapsamı. Push/tag/release yok.

## Arayüz düzenlemesi — ilk uygulama

- Koyu tema nötr yüzeyler ve lavanta vurgularla düzenlendi. Temel metin/zemin çiftleri hesaplandı: ikincil metin 6.15:1, açıklama 8.80:1, ana düğme 5.49:1, seçim etiketi 7.05:1. Bunlar tüm UI için erişilebilirlik sertifikası değildir.
- Ayar kartında başlık/seçim ve mevcut durum üstte; açıklama ortada; risk, kanıt düzeyi, yeniden başlatma ve önceki ayar kaydı ayrı alt alanda. Seçim etiketi yalnız işlem seçimini belirtir; uygulanmış olduğunu iddia etmez. Desteklenmeyen kartın tamamını soldurma kaldırıldı.
- Hazır seçimler WrapPanel ile dar pencereye sığacak şekilde sarmalanır. Tüm sayfalarda önizleme ikincil düğmedir; sayfa uygulaması ana düğme olarak kalır. Yönerge metni güncellendi; adaptör/aygıt seçicileri mevcut genişliğe yayılır.
- Ana ve rapor pencerelerinin renkleri uyumlandı; sayfa başlıkları büyütüldü. Katalog/işlem motoru değiştirilmedi. DryRun etiketi kullanıcıya DENEME MODU olarak gösterilir.
- Doğrulama: Linux PowerShell 7.4.6 Pester **250 geçti / 0 başarısız / 0 atlandı** (44.31 s). PSSA **20 dosya / 0 hata / 0 uyarı**. 75 uygulama kontrolü tekil; şablon tetikleyici hedefleri yerel ad alanında mevcut; XML geçerli.
- WPF görsel render alınmadı; gerçek Windows pencere, binding, DPI ve klavye doğrulaması bekliyor. Bu birinci tasarım uygulamasıdır, görsel kabul tamamlanmış değildir. Windows kontrol listesine özel senaryolar eklendi.
- Ara paket, mockup dosyası, push veya release üretilmedi.

## Çalıştırılmış doğrulama — 25 Eylül 2026

- Microsoft paket deposundan PowerShell 7.4.6; PowerShell Gallery üzerinden Pester 5.6.1 ve PSScriptAnalyzer 1.23.0 edinildi. Linux ortamında testler artık gerçekten çalıştırıldı. Önceki bölümlerdeki çalıştırılmadı notları o tarihteki durumu anlatır; Windows sınırı hâlâ geçerlidir.
- İlk çalıştırma ui.menu-delay ActionsFrom tanımındaki eksik dış hashtable kapanışını buldu. Düzeltildi. Bu hata önceki basit statik kontroller tarafından yakalanmamıştı.
- Tam Pester paketi: **248 geçti, 0 başarısız, 0 atlandı**, 83.9 saniye. NUnit XML sayıları ayrıca kontrol edildi. DryRun, journal/ledger, rollback, pagefile, NIC, SPI, hibernation, CFG, kullanıcı kimliği, Update ayrımı, yerel kurulum ve gerçek runspace üzerinden UI mantığı testlerini kapsar. Sistem davranışları Memory arka ucunda test edilir.
- Düzeltilmiş kaynak üzerinde PSScriptAnalyzer: **19 ürün dosyası, 0 hata, 0 uyarı**; PS 5.1 uyumluluk profili açık. Ayrıştırıcı: 37 PowerShell dosyası hatasız.
- PowerCapabilities, UserSettings ve ViewModels C# kaynakları PowerShell 7/.NET ortamında hem normal derleyiciyle hem /langversion:5 ile derlendi. PowerCapabilities yapısı 76 bayt. Native Windows API'leri çağrılmadı; .NET Framework/WinPS 5.1 derlemesi veya WPF açılışı doğrulanmış sayılmaz.
- Test çalıştırıcısı artık analiz/import öncesi tüm PowerShell dosyalarını ayrıştırır. Pester sonucu Passed değilse veya hiç test yoksa başarısız çıkar. Ayrı geçici kopyaya kasıtlı sözdizimi hatası eklenerek parser kapısının exit 1 ile durduğu doğrulandı.
- Kalan yayın engelleri: gerçek Windows PowerShell 5.1, WPF/DPI/klavye, native API ve gerçek değişiklik/geri alma, kullanıcı hesabı senaryoları, Türkçe Windows, GitHub üzerinden kurulum; UI tasarımı ve önceki lisans/üçüncü taraf kararları. Yayına hazır iddiası yok.
- Kullanıcıya verilen yaklaşık ilerleme: %70 (iş kapsamı tahmini; test kapsamı yüzdesi değildir). Ara ZIP/bundle, push, tag veya release yapılmadı.

## Windows Update ayrımı ve kullanıcı hesabı kapsamı (geliştirme)

- wu.defer artık yalnızca özellik güncellemesi ertelemesini değiştirir. Eski GPO yolunun Windows 11 desteği resmî belgede kaldırıldığı için bu yöntem Windows 10 1607+ istemcilerle sınırlı. Windows Server özellik güncellemesi için sunulmaz.
- Kalite/güvenlik güncellemelerinin 7 günlük ertelemesi ayrı wu.quality-defer seçeneğidir (High risk); iki seçenek de hiçbir hazır seçime dahil değildir. Yeniden başlatma engelleme kaydı artık bu işlemlerle yazılmaz. Eski birleşik ledger önceki ayara dönüşle kaldırılabilir; yeni işlem eski birleşik kayıtla karıştırılmaz.
- Erteleme kayıtlarının okunması, etkin güncelleme takviminin ya da MDM/GPO önceliğinin doğrulanması değildir. Kurumsal yönetim algılama/çatışma çözümü eklenmedi. Bu seçenekler performans kazancı vaat etmez.
- Registry sağlayıcısı HKCU yedeklerine UserSid ekler; geri yükleme, karşılaştırma ve ledger birleştirme hesap kimliğini denetler. Eski kimliksiz kayıtlar otomatik olarak sahiplenilmez; geri yükleme reddedilir ve ledger korunur.
- HKCU oluşturma/yazma/silme ilkelleri de aynı oturumdaki Explorer sahibinin işlem hesabıyla eşleşmesini ister. Farklı yönetici hesabı, Explorer olmayan veya belirsiz oturum reddedilir. HKLM işlemleri bu kullanıcı kontrolünden bağımsızdır. Bu kapsam uygulamanın registry sağlayıcısı/ilkelleridir; kullanıcı betikleri, dış .reg dosyaları ve bütün temizlik yolları için genel bir hesap izolasyonu iddiası değildir.
- SPI geri alma da ham registry alt kayıtlarının sahibini oturum değerini değiştirmeden önce doğrular. Önceki geliştirme sürümünün kimliksiz ham alt kayıtları otomatik geri yüklenmez.
- 11 regresyon testi eklendi. PowerShell/Pester/PSSA, C# ve gerçek Windows çalıştırılmadı. Statik XML, kodlama, katalog ve manifest tutarlılığı kontrol edildi. Katalog 71 öğedir.
- Windows kabulü: aynı/farklı UAC hesabı; Explorer olmayan oturum; eski HKCU ledger/yedek; başka kullanıcıdan yedek; normal/default/previous/recovery akışları. Güncelleme: Windows 10/11/Home/Server destek sınırları, özellik ve kalite ertelemesinin bağımsızlığı, eski birleşik geri alma, etkin Windows Update ilkeleri ve MDM önceliği.
- Kaynaklar: https://learn.microsoft.com/en-us/windows/deployment/update/waas-configure-wufb ; https://learn.microsoft.com/en-us/windows/deployment/update/waas-restart
- Ara paket/push/release yok. Sıradaki zorunlu iş: biriken PowerShell testlerini çalıştırılabilir ortamda doğrulamak ve Windows kabul testleri; ardından UI tasarımı.

## Hazırda bekletme ve CFG geri alma (geliştirme)

- Hazırda bekletme kaydı artık API'den okunan dosya türünü (None/Reduced/Full) ve HiberFileSizePercent varlık/tür/verisini içerir. GetPwrCapabilities için SDK yapısının 76 baytlık yerleşimi kullanılır; bilinmeyen durum değişiklikten önce hata verir.
- Geri alma powercfg ile boyutu sıfırlar, önceki türü seçer, tam dosyanın özel boyutunu uygular ve boyut tercihinin varlığını geri yükler. Silinen hiberfil.sys içeriği/oturumu yedeklenmez. Evrensel hazırda bekletme varsayılanı kaldırıldı.
- Eski yalnızca Enabled içeren yedekler otomatik geri alınmaz; yeni uygulama da engellenir, ledger saklanır. Bu kayıtlar mevcut yapılandırmayla birlikte elle değerlendirilmelidir.
- CFG geri alma yalnızca adlandırılmış mitigasyon API'sini kullanır. Diğer mitigasyon bitleri eski ham kayıtla ezilmez. Önceki ayara dönüşte sonradan değişmiş CFG tercihiyle çakışma varsa işlem reddedilir ve ledger korunur. Bu kontrol tüm sağlayıcılar için genel eşzamanlılık kilidi değildir.
- 8 hazırda bekletme testi ve 1 CFG çakışma testi eklendi; önceki CFG testi diğer bitlerin korunmasını sınar. PowerShell/Pester/PSSA ve C# derleme/Windows testleri ÇALIŞTIRILMADI. Statik manifest, kodlama, XAML ve diff kontrolleri yapıldı.
- Windows kabulü: Full (otomatik/özel boyut), Reduced, kapalı durum; uygula/önceki ayar sonrası API ve yeniden başlatma kontrolü; komutun ortada başarısızlığı; eski yedek; CFG harici mitigasyon ve aynı CFG tercihi çakışması. C# yapı boyutu ve byte alanları Windows SDK ile doğrulanmalı.
- Kaynaklar: https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/powercfg-command-line-options ; https://microsoft.github.io/windows-docs-rs/doc/windows/Win32/System/Power/struct.SYSTEM_POWER_CAPABILITIES.html ; https://learn.microsoft.com/en-us/powershell/module/processmitigations/set-processmitigation
- Ara paket/push/release yok. Sonraki işler: Windows Update ayrıştırma, genel HKCU kullanıcı kapsamı, Windows testleri ve UI.

## Kullanıcı tercihleri — SPI sağlayıcısı (geliştirme)

- Fare ivmesi/eşikleri, alt menü gecikmesi ve pencere küçültme/büyütme animasyonu SystemParametersInfoW GET/SET işlemlerine taşındı. C# interop API başarısızlığını Win32Exception ile bildirir; motor sonrasında etkin değeri API'den ve kalıcı kaydı registry'den tekrar okur.
- Uygulama SPIF_UPDATEINIFILE | SPIF_SENDCHANGE kullanır. Geri alma önce etkin oturum değerini kalıcı yazmadan geri yükler, sonra ham registry varlık/tür/veri bilgisini geri koyar. Böylece farklı veya eksik eski kayıtlar tahmin edilmez.
- API sağlayıcısı güncel işlem SID'sini aynı oturumdaki Explorer sahip SID'siyle karşılaştırır. Explorer yoksa/okunamıyorsa veya farklı yönetici hesabı kullanılıyorsa işlem engellenir. Bu kontrol yalnızca yeni üç sağlayıcıya uygulanır; diğer HKCU ayarlarının genel hesabı sorunu henüz çözülmüş sayılmaz.
- Windows Ayarları sayfasında menü gecikmesi 0/100/200/400/800 ms seçeneklerinden açıkça seçilir. Diğer iki tercihin kapsamı dar tutuldu: işaretçi hızı, raw input, görev çubuğu ve tüm uygulama animasyonları değiştirilmez.
- Eski registry ledger kaydı varsa önce önceki ayara dönüş istenir; legacy dönüş sonucu oturum kapatma gerektirir. Yeni kayıtlar kullanıcı SID'si içerir; farklı kullanıcıya geri yükleme reddedilir. Sayısal evrensel varsayılan uydurulmadı.
- Memory dalı API'yi derlemez/çağırmaz. 9 regresyon testi eklendi: üç ayarda geri alma, ham/etkin değer farkı, API no-op, kısmi kalıcılık hatası, farklı yönetici, farklı kullanıcı yedeği, süre seçimi, native izolasyon ve eski kayıt geçişi.
- Doğrulama: XML/kontrol adları, UTF-8 BOM, katalog kimlikleri, manifest ve git diff kontrolleri yapıldı. PowerShell/Pester/PSSA ve C# DERLEME / WPF / gerçek Windows API testleri ÇALIŞTIRILMADI; bunlar yayın öncesi zorunlu doğrulama kalemidir.
- Windows VM kabulü: normal ve farklı yönetici hesabı; özel fare eşikleri; mevcut/olmayan MenuShowDelay ve MinAnimate; üç tercihte uygula/geri al sonrası API ve Denetim Masası karşılaştırması; oturum kapat/aç sonrası kalıcılık; yüksek DPI; eski ledger dönüşü. UI değişikliği algılamayan uygulamalar ayrıca kontrol edilmeli.
- Kaynaklar: https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-systemparametersinfow ; https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/getownersid-method-in-class-win32-process
- Ara paket/push/release yok. Kalan işler: hibernation ayrıntılı geri alma, CFG çakışmaları, Windows Update ayrıştırma, genel HKCU kullanıcı kapsamı, kapsamlı Windows testleri ve UI tasarımı.

## Ağ adaptörü kapsamı — devam eden geliştirme

- Ağ sayfasında açık kullanıcı seçimi gerektiren adaptör listesi var. Seçim yapılmadan NIC/ACK/RSS karma işlemleri uygulanmaz. Adaptör seçimi değiştirilince eski seçim kutuları temizlenir ve durum yenilenir.
- NIC işlemleri ve önceki ayara dönüş InterfaceGuid ile güncel adı çözer. Kimlik kayıpsa aynı ada sahip başka aygıta geçmez. ACK yalnızca seçilen arayüzün registry anahtarını hedefler.
- Sürücü özellikleri tam RegistryKeyword eşleşmesiyle okunur ve bulunan CIM nesnesiyle yazılır; *RSS gibi anahtarlar joker olarak genişletilmez.
- Apply/default/restore için Set-NetAdapterAdvancedProperty -NoRestart kullanılır. Tercihler tek tek doğrulanır; otomatik bağlantı kesme/yeniden başlatma yapılmaz. Kullanıcıya bilgisayarı yeniden başlatması gerektiği bildirilir. Kayıtlı tercih, etkin çalışma durumu olarak sunulmaz.
- RSS global tercihi hâlâ sistem genelindedir; yalnız sürücü tarafı seçilen adaptöre sınırlıdır. Diğer TCP/IP (genel) ayarları da global kalır, UI bunu açıklar.
- 7 regresyon testi eklendi (seçimsiz işlem, tek hedef, yeniden adlandırma, kaybolan kimlik, ACK kapsamı, belirsiz kimlik, NoRestart). Önceki NIC testi açık hedef seçecek şekilde güncellendi.
- PowerShell/Pester ve Windows testleri çalıştırılmadı; statik XML/kontrol adları, kodlama, manifest/katalog ve diff kontrolleri yapıldı. Windows'ta iki adaptör, ad değişikliği, kaldırılan aygıt, birden fazla EEE anahtarı, geri alma ve yeniden başlatma sonrası etkin değerler doğrulanmalı.
- Kaynak: https://learn.microsoft.com/en-us/powershell/module/netadapter/set-netadapteradvancedproperty
- Ara paket veya yayın oluşturulmadı.

## Grafik/MSI incelemesi — devam eden geliştirme

- Önceki D3DKMT_WDDM_2_7_CAPS önerisi yeniden değerlendirildi: Microsoft sayfası "Reserved for system use. Do not use." diyor. Bu nedenle destek tespiti için üretim API'si olarak eklenmedi.
- Yeni HAGS registry zorlaması kapalı. Windows Grafik Ayarları düğmesi eklendi; bu ekranda yapılan değişiklikler uygulamanın ledger kapsamı dışında. Memory modunda düğmenin motor işlevi de işlem başlatmaz.
- MSI için tek GPU/NIC seçilerek yalnızca mevcut MSISupported değeri okunur. Değer 1 olsa bile sürücü desteği/etkin MSI doğrulanmış sayılmaz. Destek doğrulanamadığı için yeni MSI zorlaması kapalı; bu işlevin tamamlandığı iddia edilmiyor.
- gpu.hags, msi.gpu ve msi.nic kimlikleri korunuyor. Eski ledger/journal içindeki Registry eylemleri Değişiklik Geçmişi üzerinden geri alınabilir.
- 8 regresyon testi eklendi. PowerShell/Pester/PSScriptAnalyzer ve WPF/Windows çalıştırılmadı. XML, kontrol adları, kodlama, katalog/manifest tutarlılığı statik olarak kontrol edildi.
- Windows kontrolü: panel/tek aygıt seçimi, hata durumunda eski sonucun temizlenmesi, Memory modunda Ayarlar açılmaması ve eski HAGS/MSI kayıtlarının geri alınması.
- Kaynaklar: https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/d3dkmdt/ns-d3dkmdt-d3dkmt_wddm_2_7_caps ; https://learn.microsoft.com/en-us/windows/apps/develop/launch/launch-settings ; https://learn.microsoft.com/en-us/windows-hardware/drivers/kernel/enabling-message-signaled-interrupts-in-the-registry
- Ara ZIP/bundle üretilmedi; kullanıcı isteğiyle çalışma aynı dalda sürüyor.

## Pagefile sağlayıcısı — test bekleyen geliştirme

CIM yönetimi, kapsamlı önceki yapılandırma yedeği, eski ledger koruması ve 10 regresyon testi eklendi. PowerShell/Windows testleri çalıştırılmadı. Ayrıntılar: [docs/REVIEW_PAGEFILE.md](docs/REVIEW_PAGEFILE.md).

## r3 geliştirme — doğrulama bekliyor

İlk düzeltme paketi ve çalıştırılmayan testler: [docs/REVIEW_R3.md](docs/REVIEW_R3.md). r2 test sonuçları bu revizyon için yeniden doğrulanmadı.

# Değişiklik günlüğü

## 4.0.0 — yayımlanmadı (dev/v4-hardening)

### Kuru çalışma (DryRun) yalıtımı — düzeltme
- **Hata:** Kuru çalışmada temizlik akışı gerçek temizlik motorunu çağırıyordu; açık uygulamayı
  kapatma, dosya silme ve bakım komutları (DISM, SFC, netsh, wevtutil, cleanmgr…) gerçek sisteme
  ulaşabiliyordu. Betik, .reg içe aktarma ve Explorer korumaları yalnızca arayüzdeydi.
- Koruma motorun alt katmanına taşındı: `Assert-LtLiveSystem` / `Assert-LtDeletePermitted`.
  Her harici komut (`Invoke-LtNative`), dosya silme, süreç kapatma, Geri Dönüşüm Kutusu, Teslim
  İyileştirme, araç başlatma, Explorer, kullanıcı betiği ve .reg içe aktarma bu kapıdan geçer
  (`src/Core/SideEffects.ps1`). Motor fonksiyonları doğrudan çağrılsa da geçerlidir.
- Kuru çalışmada temizlik öğeleri **simüle edilir**: yollar, komut blokları ve süreç listesi hiç
  değerlendirilmez; sonuç "Atlandı — kuru çalışma: simüle edildi" olarak raporlanır.
  Uygulama tespiti gerçek dosya sistemini/süreç listesini yoklamaz (sahte sistem kullanılır).
- Gerçek dosya silme testleri yalnızca sistemin geçici klasörü altındaki, var olan, `lt-*`
  adlı ayrı test kökünde çalışabilir (`Set-LtCleanupTestRoot` bunu zorunlu kılar).
- Yapısal test: `src/` altında süreç kapatma, dosya silme, süreç başlatma vb. yalnızca korumalı
  fonksiyonlardan yapılabilir; katalog blokları bu cmdlet'leri doğrudan çağıramaz.
- Ayrıca düzeltildi: ledger (özgün değer defteri) yazımı başarısız olursa, değişiklik geri
  alınmış olsa bile sonuç yanlışlıkla "GERİ ALMA TAM YAPILAMADI" gösteriliyordu.

### Doğruluk ve raporlama
- Tüm işlemler ortak sonuç modeli kullanır: Başarılı / Zaten uygulanmış / Atlandı /
  Desteklenmiyor (nedenli) / Başarısız / Kısmen + yeniden başlatma türü.
- Her değişiklik uygulandıktan sonra sistemden yeniden okunur; okunamayan veya farklı çıkan
  değer "Başarısız" olur ve o ayarın yaptığı değişiklikler geri alınır.
- Harici komutların (sc, bcdedit, powercfg, netsh, wevtutil, dism, sfc, pnputil, ipconfig,
  reg) çıkış kodları denetlenir; zaman aşımında süreç ağacı sonlandırılır.
- Yerelleştirilmiş komut çıktısına dayanan kararlar kaldırıldı (BCD registry'den, TCP/NIC CIM
  ve RegistryKeyword'den, güç planı GUID'den okunur).
- `[Environment]::TickCount64` (PS 5.1'de yok) yerine yerel API; CPU/RAM için WMI/yerelleştirilmiş
  performans sayacı yerine `GetSystemTimes`/`GlobalMemoryStatusEx`.

### Yedekleme ve geri alma
- İşlem kimlikli, yalnız-ekleme journal (WriteThrough) + özgün değer defteri (ledger).
- "Önceki ayara dön" ve "Windows varsayılanı" ayrı işlemler.
- Önceden olmayan registry değerleri geri almada silinir; Livn Tools'un oluşturduğu boş
  anahtarlar da kaldırılır. Değer türü (DWORD/SZ/MULTI_SZ/BINARY…) birebir geri yüklenir.
- Servis (başlangıç türü + çalışma durumu), BCD, etkin güç planı, TCP, NIC, olay günlüğü boyutu,
  CFG, zamanlanmış görev ve hazırda bekletme kapsama alındı.
- Yarım kalan işlem açılışta algılanır ve geri alınabilir/bırakılabilir.
- "Backup" butonları yerine "Durum yedeği al" (olmayan değerler dahil JSON) ve geri yükleme.
- Geri yükleme noktası oluşturulduğu doğrulanmadan başarılı gösterilmez; 24 saat sınırı raporlanır.

### Ayarlar (ayrıntı: docs/TWEAK_AUDIT.md)
- Düzeltildi: MSI modu (donanım anahtarı), CFG (doğru API), MMCSS SystemResponsiveness (10),
  güç planları (sabit GUID, yinelenme yok), HPET (değerleri silme), Win32PrioritySeparation
  (yalnızca CurrentControlSet), Windows Update ertelemesi (geçerli ilkeler, Home'da desteklenmiyor),
  telemetri düzeyi (sürüme göre), PageFile (tüm sürücüler için sistem yönetimli), ISLC (tek görev),
  bellek listesi temizliği (ayrıcalık etkinleştirme), Bing araması, AppCompat ilkesi, NIC ayarları
  (RegistryKeyword + geçerli değer denetimi), TcpAckFrequency (yalnızca fiziksel adaptörler).
- Kaldırıldı (etkisiz/yanlış/belgelenmemiş): DMA Protection, NVIDIA/AMD registry ayarları,
  MSI IRQ önceliği, NVMe MSI, Large Pages, DX Contiguous Memory, Raw Input, fare/klavye tampon
  boyutu, MarkC eğrileri, Nagle/TcpNoDelay, TcpDelAckTicks, DNS önbellek "optimizasyonu",
  Interrupt Moderation "Adaptive", Giga Lite, tscsyncpolicy, CppcEnable/EnergyPerfPreference,
  kullanılmayan `Win32Prio_*.reg` dosyaları ve ISLC .pdb.
- Güvenlik özelliklerini kapatan seçenekler hiçbir hazır seçime giremez (testle zorunlu) ve
  önizlemede açık onay ister.

### Temizlik
- Yalnızca gerçekten silinen baytlar raporlanır; kilitli dosyalar "Kısmen".
- Yol korumaları (boş ortam değişkeni, sürücü kökü, sistem klasörleri), junction/symlink izlenmez.
- Veri kaybı riskleri giderildi: Spotify çevrimdışı şarkıları, WhatsApp/Teams paket kökleri,
  USB geçmişinde MountedDevices silme.
- Firefox ve Steam önbellek yolları düzeltildi; genel süreç adlarıyla uygulama kapatma kaldırıldı.
- Hibernation ve "kapanışta disk belleğini temizle" geri alınabilir ayarlara taşındı;
  Advanced Clean'deki SysMain kopyası kaldırıldı.

### Mimari
- 5.746 satırlık tek dosya → `src/` altında Core / Catalog / Engine / Cleanup / UI.
- Her ayarın tek tanımı; sayfa butonları, hazır seçimler, "Tüm sayfaları uygula" ve durum
  taraması aynı motoru kullanır.
- Tek kalıcı arka plan runspace'i; UI kuyruklardan okur (Dispatcher.Invoke yok).

### Arayüz
- XAML ayrı dosyada; yerel pencere çerçevesi (WindowChrome): boyutlandırma, Aero Snap, DPI.
- Seçim ile mevcut sistem durumu ayrı; risk, kanıt düzeyi, yeniden başlatma ve "desteklenmiyor"
  nedeni her satırda.
- Önizleme (değişiklik yapmaz), sonuç penceresi, gerçek ilerleme (n/N) ve güvenli iptal (Esc).
- Değişiklik Geçmişi sayfası; kurtarma bandı; klavye kısayolları (F5, Ctrl+Enter, Esc) ve
  görünür odak çerçevesi; Türkçe karakterler düzeltildi.
- Kuru çalışma modu (`-DryRun`).
- Kaldırılan küçük öğeler: saat, kullanıcı@bilgisayar etiketi, USB sayacı ve temizlik öncesi
  USB uyarısı (temizlik USB'yi etkilemez), "Adaptörleri Tara"/"GPU Algıla" butonları
  (bilgiler sayfada otomatik gösterilir).

### Kurulum
- Sürüme sabit etiket, dosya başına boyut + SHA-256, geçici klasöre indirme, atomik klasör
  değişimi, `app.prev` ve `-Rollback`, v3.5 düzeninden taşıma, kullanıcı verisini koruma.
- win.ps1 yalnızca ASCII (irm | iex ile BOM/kodlama sorunu yok).

### Test
- Pester 5: motor (uygula/doğrula/geri al, eksik değer, başarısız komut, sahte başarı, yinelenen
  uygulama, kurtarma), katalog/preset kuralları, temizlik, kurulum (yarım/bozuk indirme),
  arayüz mantığı (gerçek arka plan runspace'i), statik kodlama/XAML denetimleri.
- PSScriptAnalyzer: Windows PowerShell 5.1 uyumluluk kuralları.

## 3.5
- Önceki sürüm (tek dosya). Bulgular: docs/AUDIT.md
