## Kurtarma Kiti + gerçek WPF olay testleri — 2 Ekim 2026 (4)

- **İstek:** Yol haritasından "Formattan önce kurtarma kiti" seçildi; Faz 0 (gerçek WPF olay testleri) birlikte.
- **Yeni:** `src/RecoveryKit.ps1` (plan/oluşturma/okuma/arama/geri yükleme), Kurtarma Kiti sayfası (`KitPanel`), kitten açılınca otomatik yükleme. Sürücüler `Get-LtWindowsDriverStore` (Get-WindowsDriver, yalnız oemNN.inf) + `pnputil /export-driver`; geri yükleme `pnputil /add-driver /subdirs /install`, ağ → diğer → (sorulursa) ekran kartı. Kayıtlar NoOverwrite. kit.json güvenilmeyen girdi; seçime bağlı ayarlar atılır. Kuru çalışmada kit `-DENEME`, gerçek modda reddedilir/aramada atlanır.
- **Hata yakalandı (test):** eski ledger'daki katalog dışı kimlik kit oluşturmayı düşürüyordu → atlanıyor. Tek Wi-Fi dosyasında dizi açılması → `@(...)`. Kit yolları manifestte `\`; `Join-LtKitPath` ile birleştiriliyor.
- **Faz 0:** aygıt seçimi olayları `Initialize-LtDeviceSelectionView`'a taşındı; Windows doğrulayıcı bunu gerçek ComboBox'larda SelectedIndex/SelectedItem ile sınıyor, kit varsayılanlarını gerçek onay kutularından okuyor, geçici klasöre DENEME kiti yazıp yüklüyor, `KitPanel` ölçülüyor. Linux'ta WPF çalıştırılamadı; doğrulayıcı Windows'ta koşulmadı.
- **Testler:** `tests/RecoveryKit.Tests.ps1` (23): plan, hedef reddi, yapı/kit.json/KIT_OKU, iptal, tahrifat filtreleri, arama, ağ-önce sırası (iş gövdesi), onay/ret, NoOverwrite, pnputil kodları; 5 bilinçli mutasyonun hepsi yakalandı. FolderBrowserDialog PSSA uyumluluk uyarısı giderildi.
- Windows/pnputil/netsh gerçek ortamda çalıştırılmadı. Push/tag/release yok.

## Kullanıcı hatası: seçilen adaptör görülmüyor — 2 Ekim 2026 (3)

- **Bildirim:** Ağ sayfasında adaptör seçildiği hâlde DNS/adaptör ayarları "Destek kontrolü yapılamadı: Önce ağ sayfasından tek bir adaptör seçin" ile Desteklenmiyor.
- **Kök neden (kod incelemesi):** `CmbNetworkDevice.Add_SelectionChanged` içinde seçim `SelectedValue` (SelectedValuePath=InterfaceGuid) ile okunuyordu. WPF'te bu değer SelectionChanged anında henüz güncellenmemiş olabilir; bağlama boş GUID yazılıyor, durum okuması da seçimsiz yapılıyordu. Testler bağlama doğrudan GUID yazdığı için arayüz yolunu hiç sınamıyordu. Windows'ta yeniden üretilmedi; kod yolu ve bilinen WPF davranışına dayanır.
- **Düzeltme:** `Get-LtComboSelectedKey` (SelectedItem), `Select-LtComboItem`, `Set-LtNetworkTargetFromUi`, `Set-LtMsiTargetFromUi`, `Set-LtDeviceChoicesView` (tek adaptörü otomatik hedefleme, önceki seçimi GUID ile geri yükleme). Güç planı ve harici araç listeleri de SelectedItem'e geçti. Görünür "Seçili hedef" satırları (`TxtNetworkTarget`, `TxtMsiTarget`). NIC'e bağlı ayarlar seçim yoksa istisna yerine neden döndürür (`Get-LtNicSelectionIssue`).
- **Testler:** yeni `DeviceSelection.Tests.ps1` (SelectedValue eski/boşken seçim, görünür metin, otomatik/geri yüklenen seçim, MSI, App.ps1'de SelectedValue okuma yasağı); Oyuncu modu testi SelectedItem'e göre güncellendi.

## "Keşke olsaydı" turu — 2 Ekim 2026 (2)

- **İstek:** Kullanıcı gözüyle format sonrası / kararlılık / performans / ping ihtiyaçlarını derleyip uygulamak; ardından "Oyuncu modu" profili ve kolay uygulama.
- **Yeni modüller:** `src/Health.ps1` (bilgi toplama `Get-LtHealthFacts` + saf değerlendirme `Get-LtHealthReport`, user32 EnumDisplaySettings C# yardımcısı, sabit eylem listesi `Open-LtHealthLink`), `src/Network.ps1` (ICMP ölçümü, saf istatistik/yorum, geçmiş `data\network\latency-history.json`, DNS testi, `DnsServers` sağlayıcısı), `src/Startup.ps1` (Run + Başlangıç klasörleri, StartupApproved). psm1 yükleme listesi ve win.ps1 bildirimi güncellendi.
- **Katalog:** `dns.cloudflare/google/quad9` (Exclusive, seçili NIC), `game.bgrecord-off`, `gpu.app-high-perf` (iki GPU + seçili exe), gizli `startup.disable-selected` / `startup.enable-selected` (UI'da grup dışı). Hazır seçim `Gamer` (ilk sırada) = MaxPerformance ⊂ Gamer + iki oyun ayarı.
- **UI:** Sistem Kontrolü açılış sayfası ve otomatik ilk kontrol; Başlangıç sayfası; Ağ'da ölçüm/DNS testi; GPU'da oyun ekleme; Oyuncu modu düğmeleri (hazır seçim çubuğu + Sistem Kontrolü); NIC seçimini programla yaparken durum işinin önizlemeyi engellememesi için `SuppressNicChange`. Windows doğrulayıcı iki yeni paneli ölçer.
- **Sahte sistem:** Sistem Kontrolü bulguları (eksik sürücü, 60/144 Hz, 2133/3200 RAM, 1 beklenmedik kapanma, VBS açık), ağ gecikmeleri, DNS süreleri, 6 başlangıç öğesi; NIC GUID'i süslü parantezli.
- **Ölçüm:** PSSA 25 dosya / 0 hata / 0 uyarı; Pester **471 geçti / 0 başarısız / 0 atlandı**. Yeni `GamingFeatures.Tests.ps1` (27 test) + bildirim bütünlüğü testi. Mutasyon: 8/8 yakalandı (sürücü sorununu gizleme, okunamayanı tamam sayma, jitter, hedef doğrulama, başlangıç baytı, DNS geri yükleme, Oyuncu moduna güvenlik ayarı ekleme, otomatik NIC).
- **Bulunan hata:** yeni modüller ağdan kurulum bildiriminde yoktu (kurulumda modül yüklenemezdi); eklendi ve testle korunuyor.
- **Doğrulanmadı:** Windows'ta hiçbir yeni dal (CIM sorguları, EnumDisplaySettings, Get-PhysicalDisk/StorageReliabilityCounter, Get-WinEvent filtreleri, ICMP, Resolve-DnsName, Set-DnsClientServerAddress, StartupApproved'ın Görev Yöneticisi ile eşleşmesi, WPF görünümü). Kabul: WINDOWS_TEST_CHECKLIST "2 Ekim 2026 (2)".

## Uyumluluk denetimi ve WinGet sağlamlaştırması — 2 Ekim 2026

- **İstek:** Kalanlar, eklenecekler, kırılgan kısımlar, farklı PC/OS uyumu, WinGet yeterliliği; soruları ben sorup geliştirmeye devam etmem istendi.
- **Denetim:** Bağımsız salt okunur denetim (alt ajan) 2 yüksek, 8 orta, 11 düşük bulgu verdi; Türkçe-I, yerelleştirme, registry görünümü, zaman aşımları ve SID kontrolleri sorunsuz bulundu. Yüksek/orta bulguların tamamı ve düşüklerin çoğu düzeltildi.
- **Düzeltilen gerçek hata:** `net.ackfreq` çift süslü parantezli anahtara yazıyordu (Get-NetAdapter GUID'i `{...}` döndürür); sahte NIC artık gerçek biçimi kullanıyor.
- **Kabuk/başlatma:** Main.ps1 her zaman 64-bit Windows PowerShell 5.1 (Sysnative) — bir kez yeniden başlatma koruması (`LIVNTOOLS_HOSTFIX`); kabuk seçenekleri `-File` öncesinde; sondaki `\` ikiye katlanır. Başlatıcı ön kontrolü (CLM=3, AllSigned=4, RemoteSigned+MOTW=5). Test-Arayuz/Test-Windows da Sysnative kullanır.
- **Kurulum:** varsayılan `%LOCALAPPDATA%\LivnTools`; Belgeler'de `.livntools-root` veya v3.5 `Main.ps1` varsa orası. Başlat menüsü kısayolu (hata kurulumu bozmaz). win.ps1 hâlâ yalnız ASCII.
- **Oturum/hesap:** süreç araması ve Explorer kapatma oturum filtreli; Explorer önce Winlogon'a, sonra `runas /trustlevel:0x20000`'e bırakılır, en son yükseltilmiş başlatma + uyarı. Kullanıcı profili yolları veya uygulama kapatan temizlik öğeleri farklı yönetici hesabında NotSupported.
- **Dayanıklılık:** boş Geri Dönüşüm Kutusu; stdin kapalı + iptal (Invoke-LtNative `-Cancel`, `Cancelled`); konsol kod sayfası; `Read-LtTextFileAuto`; `..` yalnız yol parçası olarak reddedilir ve alt klasör hatası yalnız o klasörü atlar; `Get-LtDesktopPath`; OneDrive makine geneli yol; bozuk performans sayaçları; URL'ler `explorer.exe` üzerinden.
- **Windows 11 / donanım:** UCPD etkinse `ui.widgets-hide` NotSupported, yeni `ui.widgets-off-policy` (Dsh\AllowNewsAndInterests=0, Policy CSP) ve Görünüm'de OneOf. Modern Bekleme (GetPwrCapabilities AoAc, ofset 20) → Bitsum/Ultimate/Hybred HP NotSupported, güç modu önerisi (Microsoft Learn: Power Policy Settings).
- **WinGet:** yol (PATH → WindowsApps takma adı → App Installer paketi), sürüm ≥1.6, 29 çıkış kodu eşlemesi (winget-cli returnCodes.md), export hatası metne çevrilir, toplu kurulumda tek envanter, LTSC/Store yoksa Microsoft Learn yönergesi. Otomatik indirme/bootstrap eklenmedi.
- **Ölçüm:** PSSA 22 dosya / 0 hata / 0 uyarı; Pester **434 geçti / 0 başarısız / 0 atlandı**. Yeni `Compatibility.Tests.ps1` (13 test), Installer/Static/NicSelection/Setup/SetupInventory/PresetsDevices genişletildi. Mutasyon: 8 korumanın 8'i yakalandı (host denetimi için test sonradan güçlendirildi).
- **Bilinçli olarak yapılmadı / açık:** UI iş parçacığındaki kullanılabilirlik `Test-Path` yoklaması (çevrimdışı ağ klasörü yönlendirmesinde gecikme) arka plana taşınmadı; Livn kendi kurulumu dışındaki ISLC görevi farklı hesapta hâlâ yükseltilmiş hesaba yazılır (ISLC kendisi yönetici gerektirir); WinGet ile güncelleme listesi henüz yok. Windows'ta hiçbir yeni dal çalıştırılmadı.

## Kullanıcı geri bildirimi: hazır seçimler, .pow, GPU/MSI, Brave — 1 Ekim 2026

- **Geri bildirim:** hazır seçimler 2–4 ayar işaretliyor ve etkisiz görünüyor; Bitsum/Hybred "Plan dosyası bulunamadı"; GPU/MSI seçenekleri aygıt seçilse de etkinleşmiyor ve `PCI\VEN...` kimliği görünüyor; Brave kurulu olduğu hâlde "Kurulu değil". Bahsedilen ekran görüntüsü bu oturuma ulaşmadı.
- **Nedenler:** (1) hazır seçimler gerçekten 2–4 kimlik içeriyordu (yükleme hatası değil); (2) varsayılan paket `_Files` içermiyordu; (3) önceki turda HAGS/MSI bilerek "Supported her zaman neden döndürür, Actions boş" yapılmıştı — aygıt seçimi hiçbir şeyi açmıyordu; (4) `winget export --source winget` yalnız WinGet'in eşleştirdiği paketleri listeler; üreticinin yükleyicisiyle kurulan Brave gibi uygulamalar çıkmaz.
- **Hazır seçimler:** Temel 6, Gizlilik 12, Görünüm 7, Akıcı görünüm 4, yeni **Maksimum performans** 16 + güç planı (OneOf: Bitsum → Nihai → Yüksek Performans). `Resolve-LtPresetSelection` destek kurallarını bu sistem için uygular; arayüz sayıyı, seçilen planı ve atlananları nedenleriyle yazar. Politika testi: güvenlik azaltması, High risk, Unverified kanıt, `sec./msi./svc./wu.`, pagefile, dmwappush, ISLC, power.installed hiçbir hazır seçimde yok; donanım/zamanlayıcı/ağ yalnız Maksimum performans'ta (Temel'de yalnız Windows varsayılanına dönüşler). DiagTrack kapatma Gizlilik'e alındı (önceki r3 kuralından bilinçli sapma; düşük riskli, önizlemede görünür).
- **Güç planı dosyaları:** kullanıcının v3.5 ZIP'inden üç `.pow` geri kondu; SHA-256'lar THIRD_PARTY kayıtlarıyla aynı, kodda sabitlendi; destek kontrolünde ve içe aktarma anında doğrulanır. Web'den dosya indirilmedi; "daha iyi plan" eklenmedi (ölçüm olmadan iddia edilemez). Lisans açık: `win.ps1`/Build-Release varsayılanı dosyaları içermez, kaynak ZIP içerir.
- **GPU/MSI:** `MsiDevices` artık `DEVPKEY_PciDevice_InterruptSupport` (bit 2 MSI, 4 MSI-X) taşır; `msi.gpu`/`msi.nic` yalnız seçili aygıt doğru sınıfta ve MSI/MSI-X bildiriyorsa `MSISupported=1` yazar (High risk, hazır seçim dışı, varsayılan bilinmediği için yalnız önceki ayara dönüş). HAGS: `HwSchMode=2` (varsayılan: değer yok), build ≥ 19041; D3DKMT WDDM 2.7 yetenek sorgusu (KMTQAITYPE 70) "desteklenmiyor" derse kapalı, okunamazsa engellemez. Durum okuma sürücünün bildirdiği destek/etkin durumu gösterir. Aygıt ve adaptör etiketlerinden kimlik/GUID kaldırıldı; aynı adlı aygıtlar (2) ile ayrılır. C# kodu Linux'ta derlendi; Windows'ta çağrılmadı.
- **Format Sonrası:** 36 uygulamanın her biri için Uninstall DisplayName deseni (HKLM, WOW6432Node, HKCU; envanter önbelleği atlar). WinGet ∪ Windows listesi = kurulu; yalnız Windows listesindekiler "Kurulu (WinGet dışı)". WinGet okunamazsa listede olmayanlar "durum okunamadı" kalır. Kurulumda Windows listesinde olan atlanır; kurulum sonrası doğrulama iki kaynaktan birini kabul eder. Desenler gerçek Windows kayıt adlarıyla doğrulanmadı (yalnız bilinen ad örnekleri ve benzer ad negatif testleri).
- **Ölçüm:** Linux PS 7.4.6 — PSSA 22 dosya / 0 hata / 0 uyarı; Pester **404 geçti / 0 başarısız / 0 atlandı**. Yeni `PresetsDevices.Tests.ps1` (18 test); GraphicsSafety, ReviewR3, SetupInventory, Setup güncellendi. Mutasyon: MSI yetenek kontrolü, içe aktarma hash kontrolü, etikette kimlik, hata=kurulu değil, Windows listesiyle kurulum atlama — beşi de testlerce yakalandı.
- **Doğrulanmadı:** Windows PS 5.1/WPF'de bu turun kodu, gerçek `Get-PnpDeviceProperty` ve D3DKMT sorgusu, MSI/HAGS'ın yeniden başlatma sonrası etkisi, powercfg içe aktarma, gerçek Uninstall adları, performans etkisi. Kabul adımları: `docs/WINDOWS_TEST_CHECKLIST.md` → "1 Ekim 2026 (2)".

## Kullanıcı Windows çalıştırması — Gelişmiş Temizlik "0 B" raporu, 1 Ekim 2026

- Kullanıcı günlüğü (10:07–10:08, Windows 10 19045): DISM RestoreHealth, StartComponentCleanup, /ResetBase, SFC, Disk Temizleme ve USB kayıtları çıkış kodu 0 ile tamamlandı; SFC ihlal bulmadı; 1 USB kaydı kaldırıldı. Özet "toplam 0 B silindi" dedi.
- Neden: DISM/SFC/USB adımları açılan alanı ölçmüyor, sabit 0 döndürüyordu; özet ölçülmemiş değerleri 0 B olarak topluyordu (yanıltıcı rapor; işlemler başarısız değildi). Disk Temizleme 2 saniyede bitti; boş alan farkı 0'dı. Hızlı Temizlik (10:06) ve /ResetBase daha önce çalıştığı için temizlenecek öğe kalmamış olması olası; bu, Windows'ta ayrıca doğrulanmadı.
- Düzeltme: sonuçlarda `SizeMeasured`; özet ölçülen toplamı ve ölçülmeyen işlemleri ayrı yazar; DISM/SFC satırları "ölçülmedi" der; Disk Temizleme boş alan farkı yoksa veya okunamazsa bunu açıkça söyler. 4 regresyon testi (kullanıcının 6 öğelik seti sahte komut çıktılarıyla).
- Not (değiştirilmedi): Gelişmiş Temizlik öğeleri seçim sırasına göre değil sabit olmayan sırayla çalışabiliyor; /ResetBase, StartComponentCleanup'ı da kapsar, ikisini birlikte seçmek gereksizdir.
- Linux PS 7.4.6 son ölçüm (bu düzeltme dahil): Parser 48 dosya; PSSA 22 dosya / 0 hata / 0 uyarı; Pester **379 geçti / 0 başarısız / 0 atlandı**. Manifest: aynı 21 dosya, 4 girişin boyut/SHA-256'sı yenilendi. Windows'ta yeniden çalıştırılmadı.

## r3 bağımsız denetim + envanter + temizlik önizlemesi — 1 Ekim 2026

- **Kaynak:** `LivnTools_v4_Test_20261001.zip` (paket notu 7fe4439, `dev/r3-tweak-review`). ZIP Git geçmişi içermiyordu; 7fe4439 yerelde yok. Çalışma, ZIP içeriğinden oluşturulan yerel temel commit üzerinde yapıldı. Push/merge/tag/release yok.
- **Ortam:** Linux, PowerShell 7.4.6, Pester 5.6.1, PSScriptAnalyzer 1.23.0 (PS 5.1 uyumluluk profili). Windows, WPF, WinGet ve gerçek sistem sağlayıcıları bu ortamda yok; hiçbir gerçek temizlik/sistem değişikliği yapılmadı.
- **Başlangıç ölçümü (değişiklik öncesi):** 323 geçti / **3 başarısız**. Üçü de pakette olmayan `_Files` (Bitsum `.pow`, ISLC) dosyalarına bağlı testlerdi; önceki "323 geçti" sonucu `_Files` bulunan çalışma kopyasına aittir.
- **Düzeltilen doğrulanmış hatalar** (ayrıntı ve senaryolar: `docs/REVIEW_R3.md`, son bölüm):
  1. `Write-LtFileAtomic`: `$null` → `""` yüzünden `File.Replace` hiç çalışmıyordu; geri dönüş yolunda ikinci taşıma hatası `ledger.json`'u kaybettiriyordu. `[NullString]::Value`, korumalı geri dönüş, `.bak` kurtarma.
  2. `Invoke-LtTweakApply`: hata bloğunda journal da yazılamazsa geri sarma atlanıyor, önceki eylemler sistemde kalıyordu. Geri sarma her durumda çalışır; kayıt hatası ayrı raporlanır; uygulanmamış eylem için yazma yapılmaz.
  3. Testlerin dağıtılmayan ikililere bağımlılığı → yer tutucu fikstür.
- **Davranış açıklığı:** "Önceki ayara dön" önizlemesi Livn'den sonra değişmiş değerleri işaretler (eskiden sessizce eziliyordu).
- **Özellik — Format Sonrası envanteri:** Kurulu / Kurulu değil / Durum okunamadı; ayrı salt okunur runspace; otomatik ≥10 dk, elle ≥30 sn; hata ve yeniden deneme görünür; WinGet yokluğu/hatası "kurulu değil" sayılmaz; arka plan envanteri kaynak sözleşmesi kabul etmez; kurulum davranışı (exact ID, winget kaynağı, no-upgrade) değişmedi; kurulum sürerken envanter bekler.
- **Özellik — Temizlik önizlemesi:** silmeyle aynı seçim kuralları; dosya sayısı/tahmini boyut, kapsam, korunan veri, taranamayan/sınır dışı alanlar; uygulama kapatmaz, komut çalıştırmaz, dosya değiştirmez; bakım işlemlerinde sayı yok; EA/Battle.net/Xbox taranmaz; DryRun'da gerçek dosya sistemi taranmaz; silme anında kontroller yeniden yapılır.
- **Değişen ürün dosyaları:** `src/Core/{Common,Journal,Backend,Demo,SideEffects}.ps1`, `src/{Engine,Setup,Cleanup}.ps1`, `src/UI/{App.ps1,MainWindow.xaml}`, `win.ps1` (manifest: aynı 21 dosya, 12 girişin boyut/SHA-256'sı yenilendi; `Build-Release` LICENSE olmadığı için doğru biçimde reddediyor, lisans seçilmedi). Araç: `tools/Invoke-WindowsValidation.ps1` (envanter görünümü kontrolü). Testler: yeni `Reliability`, `SetupInventory`, `CleanupPreview`; `TestHelpers`, `Engine`, `ExternalTools`, `DryRunIsolation` güncellendi. Belgeler: README, CHANGELOG, ARCHITECTURE, SUPPORT_MATRIX, WINDOWS_TEST_CHECKLIST, REVIEW_R3.
- **Son ölçüm:** Parser 48 dosya; PSSA **22 dosya / 0 hata / 0 uyarı**; Pester **375 geçti / 0 başarısız / 0 atlandı** (NUnit toplamı doğrulandı; manifest testi çalıştı, atlanmadı), ~88 s.
- **Mutasyon denetimi:** 8 yeni koruma bilerek bozuldu (NullString, geri dönüş geri koyma, geri sarma kayıt koruması, hata=kurulu değil, DryRun önizleme taraması, sınır dışı tarama, bakımda sayı, ana iş meşgulken envanter); her biri en az bir test tarafından yakalandı.
- **Doğrulanmadı:** Windows PowerShell 5.1 / .NET Framework'te bu turun kodu, WPF görünümü/DPI/klavye, gerçek `winget export`, Windows junction/ACL davranışı, Windows 11. Kabul adımları: `docs/WINDOWS_TEST_CHECKLIST.md` → "1 Ekim 2026" bölümü.
- **Sıradaki somut adım:** Kullanıcının Windows 10 makinesinde `Test-Windows.bat` (SmokeOnly) ve ardından `tools\Invoke-Tests.ps1` tam paket; sonra anlık görüntülü VM'de envanter ve önizleme kabul maddeleri.

## Varsayılan dağıtımı harici dosyalardan ayırma — 28 Eylül 2026

- Build-Release varsayılan olarak _Files dizinini paketlemez. -IncludeThirdParty açık seçimiyle eklenebilir; seçenek dağıtım izni kanıtı değildir. Kaynak depodaki dosyalar silinmedi, dolayısıyla kaynak arşivinin kapsamı değişmedi.
- Mevcut geliştirme win.ps1 bildirimi de 5 harici dosya çıkarılarak 20 dosyaya indirildi. LICENSE kararı henüz verilmediği için gerçek yayın üretimi hâlâ engellidir; mevcut bildirim bir yayımlanmış sürüm değildir.
- 3 regresyon testi eklendi: varsayılan hariç tutma, açık dahil etme, _Files dizini hiç yokken kontrol. Ayrıca ayrı Memory denemesinde dört harici bağımlılık seçeneği desteklenmiyor döndü; temel game.mode başarıyla uygulandı.
- Tam paket Linux PowerShell 7.4.6/Pester ile tekrar çalıştırıldı; sonuçlar aşağıda kaydedildi. Gerçek Windows/WPF, native ayar geri alma ve görsel kabul bekliyor. Sıradaki adım kullanıcıyla Windows test ortamını belirlemek; Linux testlerini tekrar çalıştırmak bu kabulün yerine geçmez.
- Ara ZIP, push, tag veya release üretilmedi.

Tests Passed: 262, Failed: 0, Skipped: 0, Inconclusive: 0, NotRun: 0
PSScriptAnalyzer: 20 dosya, 0 hata, 0 uyarı.

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

## Windows doğrulama giriş noktası (hazırlandı, Windows sonucu bekleniyor)

- tools/Invoke-WindowsValidation.ps1 eklendi. Windows PowerShell 5.1 ve STA gerektirir; yönetici istemez. Gerçek sistem ayarları yerine Memory kullanır.
- Gerçek .NET Framework derleyicisinde PowerCapabilities/UserSettings/ViewModels derlemesi, interop boyut/ofsetleri, ana/rapor XAML yükleme, kayıtlı kontrol adları, katalogla doldurulmuş şablonlar, iki boyutta temel layout ve Memory uygula/geri al kontrolü içerir.
- Normal çalıştırma ardından mevcut Pester/PSSA paketini ayrı PS 5.1 işleminde başlatır. -SmokeOnly yalnız C#/WPF/Memory kontrolüdür; tam test paketi yerine geçmez.
- Bu araç Windows üzerinde henüz çalıştırılmadı. Linux'ta doğru biçimde exit 1 ile reddettiği doğrulandı. Pencere gösterilmediği için görsel/DPI/klavye ve gerçek sistem VM kabulü ayrıca gerekir. WPF binding doğrulamasının tamamını kapsamaz.
- Yeni araç ürün analiz listesine dahil edildi. Linux PowerShell 7.4.6: Pester 250 geçti / 0 başarısız / 0 atlandı (85.59 s); PSSA 20 dosya / 0 hata / 0 uyarı; 38 dosya ayrıştırıldı. Ek iki test yeni dosyanın mevcut otomatik sözdizimi/kodlama kontrolleridir, Windows testleri değildir. Ara paket/push/release yok.

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

# WORKLOG — Livn Tools v4

Dal: `dev/v4-hardening` (temel: `main` @ a67902d). **Push / release yapılmadı** (onay bekler).

## Ortam
- Geliştirme: Linux sandbox; pwsh 7.4.6, PSScriptAnalyzer 1.23.0, Pester 5.6.1 (kaynaktan derlendi).
- Windows/WPF YOK → arayüz görsel olarak açılmadı; gerçek registry/BCD/servis/ağ değişikliği yapılmadı.
  Tüm davranış testleri bellek arka ucu (`Set-LtBackend Memory`) ile.
- Yüklenen ZIP (v3.5) = repo geçmişindeki eski commit'ler; `main` daha yeni olduğu için temel alındı.

## Tamamlanan aşamalar
1. **Mevcut durum** — `docs/AUDIT.md` (dosya/fonksiyon düzeyinde bulgular, README farkları, başlangıç PSSA: 216 uyarı / 0 hata).
2. **Doğruluk, yedekleme, geri alma** — sonuç modeli, çıkış kodu denetimi, uygula→oku→doğrula, ayar başına geri sarma,
   journal + ledger, önceki ayar / Windows varsayılanı, yarım işlem kurtarma, doğrulanan geri yükleme noktası.
3. **Modülerleştirme** — `src/` (Core, Catalog, Engine, Cleanup, UI); tek tanımlı katalog (70 ayar, 45 temizlik/bakım/tek seferlik işlem);
   tweak denetimi `docs/TWEAK_AUDIT.md` (birincil kaynaklarla).
4. **Arayüz** — XAML ayrı; WindowChrome; seçim/durum ayrımı; önizleme; ilerleme + iptal; geçmiş; kurtarma bandı; kuru çalışma.
5. **Kurulum/test/doküman** — win.ps1 (sabit etiket, SHA-256, atomik değişim, rollback, v3.5 taşıma), Pester, PSSA,
   README, CHANGELOG, SUPPORT_MATRIX, THIRD_PARTY, WINDOWS_TEST_CHECKLIST, ARCHITECTURE.

## Değişen / eklenen dosyalar
- Yeniden yazıldı: `Main.ps1`, `win.ps1`, `LivnTools.bat`, `README.md`
- Yeni: `src/**`, `tests/**`, `tools/**`, `docs/{AUDIT,TWEAK_AUDIT,SUPPORT_MATRIX,THIRD_PARTY,WINDOWS_TEST_CHECKLIST,ARCHITECTURE}.md`,
  `CHANGELOG.md`, `WORKLOG.md`, `PSScriptAnalyzerSettings.psd1`, `.gitattributes`, `.gitignore`
- Silindi: `_Files/Win32Prio_*.reg` (kullanılmıyordu), `_Files/ISLC/*.pdb`

## Test sonuçları (Linux, pwsh 7.4.6)
- `tools/Invoke-Tests.ps1`: PSScriptAnalyzer (ürün kodu, PS 5.1 uyumluluk profili) **0 hata, 0 uyarı**;
  Pester 5.6.1 — **143 geçti, 0 başarısız, 0 atlandı** (Engine, Catalog, Core, Cleanup, Installer, Static, UiLogic).
- Yerel kurulum benzetimi (`win.ps1 -SourceOverride`, Linux): 24 dosya SHA-256 doğrulandı, kuruldu; bellek arka ucuyla
  `power.bitsum` ve `mem.islc-autostart` uygulama duman testi başarılı.
- Çalıştırılmadı: Windows PowerShell 5.1 (csc ile C# derleme dahil), WPF pencere açılışı, gerçek sistem değişiklikleri,
  Türkçe Windows'ta komut davranışı, BCD kovanı okuma izni, geri yükleme noktası, kurulumun GitHub'dan indirilmesi.

## Açık sorunlar
- Windows üzerinde doğrulama yapılmadı → `docs/WINDOWS_TEST_CHECKLIST.md`.
- Üçüncü taraf dosyaların (Bitsum/TheHybred .pow, ISLC) dağıtım izni doğrulanamadı → `docs/THIRD_PARTY.md`.
- Kuru çalışma yalıtımı Windows'ta da gözle doğrulanmalı (`docs/WINDOWS_TEST_CHECKLIST.md` Bölüm 2 son maddeler).
- Depoda LICENSE yok (eski README MIT diyordu; rozet kaldırıldı) → proje sahibinin kararı.
- `docs/screenshots` v3.5 arayüzünü gösteriyor; Windows'ta yeni ekran görüntüleri alınmalı.
- `v4.0.0` etiketi yok: win.ps1 bu etiketi bekler; yayın akışı `tools/Build-Release.ps1` başlığında.
- UAC ile farklı yönetici hesabı kullanılırsa HKCU ayarları o hesabın profiline yazılır (belgelendi).
- Ubisoft/Rockstar/Xbox önbellek yolları Windows'ta doğrulanmalı.

## Düzeltme turu — Kuru çalışma yalıtımı (inceleme bulgusu)
- Bulgu: `Invoke-LtCleanupFlow` Memory modunda da `Invoke-LtCleanup` çağırıyordu; `Invoke-LtCleanupItem`
  ve `Remove-LtFolderContents` gerçek süreç kapatma / dosya silme / bakım komutlarına ulaşabiliyordu.
- Düzeltme: motor katmanında kapı (`Assert-LtLiveSystem`, `Assert-LtDeletePermitted`); tüm yan etkili
  ilkeller `src/Core/SideEffects.ps1`'de; `Invoke-LtNative` kapıda; temizlik öğeleri kuru çalışmada
  simüle edilir; uygulama tespiti ve süreç listesi sahte sistemden; betik/.reg/Explorer motorda korunur;
  test kökü yalnızca geçici klasör altındaki `lt-*` klasörü.
- Diğer akışlar denetlendi: ayar motoru (uygula/önceki/varsayılan/kurtarma/durum yedeği), geri yükleme
  noktası, bellek listesi → zaten Memory dallıydı; testle doğrulandı. Donanım çubuğu salt okunur.
- Ek hata: ledger yazımı başarısız olunca yanlış "GERİ ALMA TAM YAPILAMADI" raporu → düzeltildi + test.
- Değişen: `src/Core/Common.ps1`, `src/Core/SideEffects.ps1` (yeni), `src/Cleanup.ps1`, `src/UI/App.ps1`,
  `src/Core/Backend.ps1`, `src/Core/Demo.ps1`, `src/Engine.ps1`, `src/LivnTools.psm1`, `win.ps1` (manifest 25 dosya),
  `tests/DryRunIsolation.Tests.ps1` (yeni), `tests/UiLogic.Tests.ps1`, `tests/Engine.Tests.ps1`, belgeler.
- Test: PSSA 19 dosya 0 hata 0 uyarı; Pester **171 geçti / 0 başarısız**. Mutasyon denetimi: 6 koruma tek tek
  bozuldu, her biri en az 2 test tarafından yakalandı.

## Sıradaki somut adım
Windows 11 VM'de `docs/WINDOWS_TEST_CHECKLIST.md` Bölüm 1–2'yi çalıştırmak (sisteme dokunmaz),
ardından VM anlık görüntüsüyle Bölüm 3–6.


## İsteğe bağlı harici performans entegrasyonu — 28 Eylül 2026

- Kullanıcı isteği: lisans belirsiz dosyaları varsayılan dağıtıma koymadan ISLC/güç planları ve faydalı üçüncü taraf araçlarını bağlama.
- Yeni performans paneli: sabit resmî kaynak bağlantıları, ISLC uygulama seçimi ve RAM'e bağlı sınırlı başlangıç profili, kurulu planları yenile/seç. PowerScheme sağlayıcısıyla GUID doğrulama, çoğaltmadan etkinleştirme, önceki plana dönüş. Process Lasso ve PresentMon için yalnız resmî bağlantı eklendi.
- ISLC RAM/2 ve okunamayan RAM için 16 GB varsayımı kaldırıldı. Fiziksel MB algısı; %10 serbest bellek eşiği (512–4096 MB), liste 1024 MB, polling 1000 ms. Sezgisel başlangıç profili olduğu açık; config/timer ayarları değiştirilmez. Dosya/sürüm kontrolü özgünlük doğrulaması değildir. Mevcut görevin yolu sonraki oturumda yeniden bulunur. Önizleme + görev geri alma aynı motoru kullanır.
- Resmî sayfada 1.0.4.8 doğrulandı; forum 403 nedeniyle güncel paket indirilmedi/ikili doğrulanmadı. Kaynak 1.0.3.7 aynen kaldı, dağıtıma eklenmedi. Otomatik indirme/güncelleme yok. Yeni sürüm CLI ve görev config davranışı Windows kabul listesine eklendi.
- İlk testin devamı dış telemetri nedeniyle otomatik inceleme tarafından reddedildi. POWERSHELL_TELEMETRY_OPTOUT=1 ve DOTNET_CLI_TELEMETRY_OPTOUT=1 ile telemetri kapalı yeniden çalıştırma başarılı.
- Linux PS 7.4.6: **274 geçti / 0 başarısız / 0 atlandı**, 44 s. PSSA **20 dosya / 0 hata / 0 uyarı**, parser 40 dosya. XAML XML ve 83 kayıtlı kontrol eşleşmesi doğrulandı; WPF render testi değildir.
- Windows, gerçek performans ölçümü, güncel ISLC imza/hash ve otomatik kurulum açık. Yeni ZIP/paket üretilmedi; push/tag/release yapılmadı.

## Format sonrası kurulum ve launcher temizliği — 28 Eylül 2026

- Format Sonrası sayfası: izinli kullanıcı ayarları ve uygulama kimliklerini JSON profiline kaydetme/yükleme. Yükleme yalnız seçim yapar; uygulama ayrı önizleme/onayla hedef bilgisayarın önceki değerlerini kaydeder. Donanım ayarları, ledger, komutlar ve dosya yolları taşınmaz.
- Akıcı görünüm hazır seçimi; beş SPI animasyon efekti, görev çubuğu hizası, arama/Widgets simgelerini gizleme ve desteklenen Windows 11 sürümünde Görevi sonlandır seçeneği. Yazı yumuşatma korunur; beş efektin etkin değerleri geri alınır, ortak UserPreferencesMask bütünü kopyalanmaz.
- Seçili uygulamaları WinGet üzerinden kurma (mevcut olanı yükseltmeden atlama, kurulum sonrası envanter doğrulama); sınırlı isteğe bağlı Appx listesini yalnız mevcut kullanıcıdan kaldırma. Ayrı açık onay, Memory yalıtımı ve paketler arasında iptal. Kurulum/kaldırma için işlem geri alma garantisi yok; kaldırma uygulama verisini silebilir.
- On launcher girdisi korundu; varsayılan seçili değiller ve açık launcher varsa işlem atlanır. Java dahil süreçler zorla kapatılmaz. Steam/Epic/GOG web temizliği Cache/Code Cache/GPUCache ile sınırlı; hesap verileri korunur. Minecraft yalnız yedi günden eski log/çökme raporları. Rockstar kapsamı daraltıldı; Ubisoft kurulum yolu doğrulanır. EA/Battle.net/Xbox otomatik temizliği doğrulanmış kapsam oluşana kadar devre dışı. Kullanılabilir öğe filtresi eklendi.
- Linux PowerShell 7.4.6: **305 geçti / 0 başarısız / 0 atlandı** (61.96 s); PSSA **21 ürün dosyası / 0 hata / 0 uyarı**, parser 43 dosya. Gerçek geçici dosya testleri hesap verisinin korunmasını ve yaş filtresini sınadı; Windows sistem çağrıları Memory/mock ile sınandı. C# yardımcı kodu .NET üzerinde C# 5 dil düzeyinde derlendi; Windows PowerShell 5.1/WPF doğrulaması değildir.
- Windows/WPF, native SPI, gerçek WinGet/Appx, launcher sürüm/yol davranışı ve performans ölçümü bekliyor; kontrol listesi güncellendi. ZIP/bundle, push, tag veya release yok.

## Windows kabul aracı — 28 Eylül 2026

- Gizli yardımcı panellerin layout kontrolü dışında kaldığı tespit edildi. Windows doğrulayıcı artık yedi paneli ayrı ayrı görünür yapıp 980×620 ve 1240×820 boyutlarında ölçüyor. Format Sonrası listeleri Memory kataloglarıyla dolduruluyor; ilk seçili satırın oluşturulması ve panellerin sıfır olmayan boyutları denetleniyor. Native ayar yazımı ve uygulama işçileri başlatılmıyor.
- Değişen betik PS 7.4.6 parser ve PS 5.1 uyumluluk analizinden hatasız geçti. Linux'ta Windows kontrolünün başlamadan reddedildiği doğrulandı. WPF senaryoları burada çalıştırılmadı; görsel/DPI/binding kabulü tamamlandı iddiası yok. Ürün kodu değişmedi; önceki 305 test sonucu aynı ürün commit'ine aittir, bu tur tam paket tekrar çalıştırılmadı.
- Kontrol listesi güncellendi. ZIP/push/release yok; sonraki zorunlu aşama gerçek Windows PowerShell 5.1 çalıştırması.

## Windows test teslimi — 29 Eylül 2026

- Test-Windows.bat ve tools/Invoke-WindowsCheck.ps1: yönetici yetkisi istemeden SmokeOnly kontrolü; transcript ve hata ayrıntıları tests/results altında. Modül indirme/kurma yok. -Full yalnız mevcut Pester/PSSA ile tam paketi çalıştırır.
- Test-Arayuz.bat yalnız -DryRun ile açar; kayıtları tests/results/ui-data altında tutar. Normal başlatıcı değiştirilmedi. Yeni kontrol betiği analiz listesine eklendi.
- Kullanıcıda gerçek Windows doğrulaması için tek test ZIP'i hazırlanıyor; release oluşturucu kullanılmadı, etiket/push yok. Üçüncü taraf _Files içerikleri dağıtılmıyor. Windows doğrulaması bu ortamda yapılmadı.
- Linux PS 7.4.6 doğrulaması: 307 test geçti, 0 başarısız/atlandı (48.33 s); PSSA 22 dosya, 0 hata/uyarı; parser 44 dosya. Windows davranışı doğrulanmadı.

## Kullanıcı Windows testi — Marshal overload düzeltmesi, 29 Eylül 2026

- Kullanıcının Windows 10 build 19045 / Windows PowerShell 5.1 transcript'i: SmokeOnly, Invoke-WindowsValidation.ps1 satır 40, Marshal.SizeOf çağrısı System.RuntimeType marshalling hatası. WPF aşamasına ulaşılmadı.
- SizeOf(Type) overload'u reflection ile açık seçiliyor; yapı boyutu/ofset kontrolleri (76/8/22) korunuyor. Ürün kodu değiştirilmedi.
- Değişen gerçek kontrol bloğu Linux .NET üzerinde derlenen aynı C# yapısıyla çalıştırıldı: 76/8/22 başarılı. PowerShell analizinde bulgu yok. Windows'ta yeniden çalıştırma bekliyor; test geçildi iddiası yok.
- Kullanıcıya yalnız tools/Invoke-WindowsValidation.ps1 değişim dosyası veriliyor; ZIP/release/push yok.

## İkinci Windows kaydı — görünmeyen pencere layout kontrolü

- Windows PowerShell 5.1 C# derlemesi geçti; önceki Marshal sorunu çözülmüş. İlk panel boyutu sıfır kaldığı için test durdu. Önceki Catalog PASS yalnızca istisna olmamasına dayanıyordu; gerçek layout kanıtı değildi.
- Test artık gösterilmemiş Window yerine Content kökünü ölçüp düzenliyor; kökün sıfır olmayan boyutunu da doğruluyor. Ölçüler içerik alanını temsil eder, pencere çerçevesi/DPI kabulü değildir. WPF kaynak bağlamı: https://github.com/dotnet/wpf/blob/main/src/Microsoft.DotNet.Wpf/src/PresentationFramework/System/Windows/Window.cs
- Bağımsız panel/boyut hataları toplanır; kalan paneller, rapor ve Memory kontrolü çalışabilir. Toplanan hata varsa sonuç yine FAIL olur; kontroller kaldırılmadı.
- Parser ve PSSA hatasız. WPF bu Linux ortamında çalıştırılmadı, kullanıcıda yeniden doğrulama bekliyor. Ürün kodu değişmedi.

## Windows SmokeOnly başarılı — 29 Eylül 2026, 10:05

- Kullanıcı kaydı windows-check-20260929-100551-74e685e8.txt: Windows 10 build 19045, Windows PowerShell 5.1.19041.6456, RESULT PASS.
- C# yardımcıları .NET Framework üzerinde derlendi. Katalog ve yedi yardımcı panel 980x620/1240x820 içerik boyutlarında geçti; rapor içeriği, XAML/kontrol/şablon oluşturma ve Memory uygulama/geri alma geçti. Önceki iki doğrulayıcı hatası bu çalıştırmada tekrarlanmadı.
- Bu SmokeOnly kaydıdır: tam Pester/PSSA paketi Windows'ta çalıştırılmadı. Görünür pencere, etkileşim, DPI, Windows 11 ve gerçek sistem uygulama/geri alma henüz doğrulanmadı. Sonraki adım Test-Arayuz.bat ile DryRun görsel kabulü.

## İlk görünür arayüz incelemesi — 29 Eylül 2026

- Kullanıcı üç DryRun ekran görüntüsü paylaştı: Hızlı Temizlik, Performans, Format Sonrası. Pencere ve sayfalar açılmış, DENEME MODU rozeti görünür. Bu görüntüler tüm etkileşimlerin geçtiği anlamına gelmez.
- Kullanıcı isteği (planlanan): Format Sonrası uygulama kataloğu sığ; kategori ve çeşitlilik artırılmalı. Tarayıcılar, oyun istemcileri, iletişim, medya, ofis/PDF, geliştirici ve sistem araçları grupları; arama/filtre ve kurulu bilgisi ile geniş liste yönetimi değerlendirilecek. Paket kimlikleri ve kurulum davranışları uygulama öncesinde doğrulanacak. Bu tur katalog genişletilmedi.
- Görsel bulgular: Performans ekranında temizlik filtresi/açıklaması kalmış ve günlükte exception stack trace görülüyor; hata başlığı ekran dışında olduğundan tam günlük istenecek. Sayfa geçişi hatasız kabul edilmedi. ComboBox/ScrollBar açık renkleri koyu temadan ayrışıyor. Günlük alanı ve sabit yükseklikteki uygulama listesi kullanılabilir içerik alanını daraltıyor; daha kompakt günlük ve büyüyebilen/kategorili liste düzeni planlanacak.
- Demo işletim sistemi/donanım metinlerinin gerçek CPU/RAM okumalarından açıkça ayrılması görsel iyileştirme notu. Gerçek Windows 11 doğrulaması yapılmış sayılmaz.

## Görünür UI sayfa geçişi — ItemsSource koleksiyon düzeltmesi

- Kullanıcı günlüğü LivnTools_Gunluk_20260929_103627.txt: tekrarlayan Group -> IEnumerable atama hatası. Show-LtPage içindeki if ifadesinin pipeline çıktısı tek gruplu koleksiyonu nesneye indiriyordu. Atama yarıda kaldığından önceki sayfanın filtre/açıklaması ekranda kalabiliyordu.
- TweakGroups ve CleanupGroups atamaları if dallarının içine alındı. Koleksiyon nesnesi aynen korunuyor; sıfır/tek/çok grup WPF ItemsSource sözleşmesine uyuyor. Diğer ItemsSource atamaları da aynı kalıp için tarandı.
- Yeni UiNavigation.Tests.ps1 gerçek Show-LtPage fonksiyonunu, IEnumerable tipli kontrol taklidiyle sınar: 0/1/3 grup, tüm sayfalar ve gerçek katalogda Hızlı Temizlik -> Performans -> Format Sonrası -> Hızlı Temizlik, kullanılabilirlik filtresi açık/kapalı. Eski kodda dört test de başarısız oldu; tek grup ve gerçek katalog testleri kullanıcının hatasını aynen üretti.
- Windows görünür arayüz tekrar denemesi bekliyor. Katalog genişletme ve görsel tema düzenlemesi bu düzeltmeye dahil edilmedi.
- Düzeltme sonrası Linux PS 7.4.6: 313 geçti / 0 başarısız / 0 atlandı (48.21 s); PSSA 22 dosya 0 hata/uyarı, parser 45 dosya. Windows görünür geçiş testi kullanıcıda tekrarlanacak.

## Sayfa geçişi düzeltmesi sonrası görüntü — 29 Eylül 2026, 10:44

- Kullanıcının powershell_0PwvY7je0v.png görüntüsünde Performans sayfası açık: temizlik filtresi/açıklaması artık yok, doğru güç planı/CPU/RAM açıklaması görünüyor. Görünen günlük alanında yalnız başlangıç kaydı var; önceki ItemsSource exception izi görünmüyor. Bu ekran için düzeltme davranışı doğrulandı; tüm sayfa/etkileşimler için genel hata yok iddiası değildir.
- DryRun rozeti ve sahte donanım değerleri görünür. Görsel iyileştirme notları (açık renkli ComboBox/ScrollBar, büyük günlük, üst içerik yoğunluğu) devam ediyor. Uygula/önizle/geri al etkileşimi Windows üzerinde henüz kullanıcı tarafından doğrulanmadı.

## Güç planı listesi düzeltmesi — 29 Eylül 2026

- Kullanıcının son ekranı dört ayarlı önizlemeyi gösteriyor; uygulama/geri alma tamamlandı kanıtı değil. Güç planı ekranındaki uzun kimlikler Memory deneme planlarının GUID değerleriydi.
- Liste açılışta arka planda yüklenir. Dengeli/Yüksek performans/Güç tasarrufu deneme adları; gerçek sistemde yerelleştirilmiş veya özel plan adları gösterilir. Etkin plan işaretlenir, GUID yalnız ipucunda kalır. Listeleme/seçim planı etkinleştirmez.
- İlk durumda seçim ipucu, boş listede ve okuma hatasında açıklama gösterilir; boş/hatalı liste işlem bitiminde yanlışlıkla etkinleşmez. Liste bağlama sırasında seçim olayı bastırılır.
- Linux PS 7.4.6: 317 geçti / 0 başarısız / 0 atlandı (50.76 s); PSSA 22 dosya 0 hata/uyarı, parser 45 dosya. Windows görünür doğrulaması bekliyor.
- Açık renkli ComboBox/ScrollBar teması ve Format Sonrası katalog genişletmesi ayrı kalan işler. Küçük Windows test yaması hazırlanıyor; push/tag/release yok.

## Koyu seçim kutuları ve kompakt günlük — 29 Eylül 2026

- Son kullanıcı görüntüsünde güç planı adları/etkin işareti/GUID ipucu doğru görünüyor; Memory verisi, gerçek güç planı okuma kanıtı değil. Görünen günlükte hata yok.
- ComboBox, ComboBoxItem ve dikey/yatay ScrollBar için koyu WPF şablonları eklendi. Odak, seçim, hover ve disabled durumları tanımlandı; mevcut ComboBox seçme davranışı kullanılıyor. Güç planı ipucu stili ortak öğe stilini temel alıyor.
- Günlük yüksekliği 150 -> 80 piksel; mevcut Gizle/Göster ve Kaydet kontrolleri korundu. İçeriğe 70 piksel kazandırıldı.
- Windows doğrulayıcıya ComboBox PART_Popup ve iki yönlü ScrollBar PART_Track oluşturma/yön kontrolü eklendi. Bu kontrol Linux'ta çalıştırılamadı; görünüm, klavye ve kaydırma için Windows kabulü bekliyor.
- İlk doğrulama girişiminde oturumda Pester/PSSA bulunamadı; test sonucu sayılmadı. Mevcut yerel arşivlerden modüller geri yüklendi. Ardından 97 statik test geçti; değişen Windows doğrulayıcı PSSA bulgusuz. İşlem motoru değişmediğinden tüm davranış paketi tekrar çalıştırılmadı.
- Kurulum manifest özeti güncellendi. Yeni ZIP/push/tag/release yok. Format Sonrası katalog genişletmesi sırada.

## Format Sonrası katalog genişletmesi — 29 Eylül 2026

- 8 -> 36 uygulama, 8 kategori. Açıklama ve paket kimliği ipucu; Türkçe aksan/noktalı-noktasız harf toleranslı düz metin arama; kategori ve yalnız seçili filtreleri eklendi. Listede 280 piksel alan ayrıldı. Başlangıç seçimleri boş.
- Görünümden bağımsız seçim kümesi: filtreleme seçim silmez, görünmeyen seçim sayısı gösterilir. Profil kaydı/yükleme ve kurulum aynı tam seçim kümesini kullanır. Tümünü temizle açık düğmeyle yapılır.
- Kurulum/kaldırma onayı kaydırılabilir mevcut rapor penceresine taşındı; tüm paketler gösterilir. Memory için Simüle et başlığı; vazgeçme iş başlatmaz. Kurulum motorunun kaynak, exact ID, no-upgrade, doğrulama ve Memory yalıtımı korundu.
- Kaynak doğrulaması: Microsoft winget-pkgs resmi deposunun GitHub contents API'sinde 36 paket yolunun tamamı sürüm dizinleriyle mevcut (29 Eylül 2026). Yol biçimi: https://github.com/microsoft/winget-pkgs/tree/master/manifests/{ilk_harf}/{nokta_ile_ayrılmış_kimlik_bileşenleri}. Bu, kurulum çalıştırma veya her sürümün yükleyicisini sınama değildir. CTT uygulama kataloğuna yalnız karşılaştırma için bakıldı; betik/yükleyici kodu alınmadı.
- Tarayıcı: Mozilla.Firefox, Google.Chrome, Brave.Brave, Vivaldi.Vivaldi
- Oyun: Valve.Steam, EpicGames.EpicGamesLauncher, GOG.Galaxy, Ubisoft.Connect, ElectronicArts.EADesktop, Blizzard.BattleNet, PrismLauncher.PrismLauncher
- İletişim: Discord.Discord, Telegram.TelegramDesktop, Mozilla.Thunderbird
- Medya: VideoLAN.VLC, OBSProject.OBSStudio, Audacity.Audacity, HandBrake.HandBrake, ShareX.ShareX
- Ofis ve PDF: TheDocumentFoundation.LibreOffice, SumatraPDF.SumatraPDF, Obsidian.Obsidian
- Dosya ve güvenlik: 7zip.7zip, voidtools.Everything, WinDirStat.WinDirStat, Bitwarden.Bitwarden, KeePassXCTeam.KeePassXC
- Geliştirme: Microsoft.VisualStudioCode, Notepad++.Notepad++, Git.Git, WinSCP.WinSCP
- Sistem araçları: Microsoft.PowerToys, CPUID.CPU-Z, TechPowerUp.GPU-Z, CrystalDewWorld.CrystalDiskInfo, REALiX.HWiNFO
- Tam Linux PS 7.4.6 paketi: 323 geçti, 0 başarısız/atlandı; PSSA 22 dosya 0 hata/uyarı, parser 45 dosya. Sonraki kaydırılabilir onay değişikliği ayrıca 11 UiNavigation testiyle geçti, App.ps1 PSSA bulgusuz. Son iki test tam paketin 323 sayısına dahil değil; tüm paket yeniden çalıştırılmadı.
- Gerçek Windows/WPF, gerçek WinGet kurulumları ve her paket yükleyicisinin güncel davranışı bekliyor. Kurulum listesi, bilgisayarda hangi uygulamaların kurulu olduğunu önceden göstermiyor; mevcut motor kurulum anında kontrol ediyor.
- Yeni ZIP/push/tag/release yok. Kullanıcı doğrulamasında: kategori değiştirerek iki uygulama seç, aramada gizle, sayaç ve yalnız seçili görünümü kontrol et, DryRun önizlemesinde ikisinin de listelendiğini doğrula; profil kaydet/yükle ve Vazgeç davranışını denetle.

## Birleşik arayüz testine hazırlık — 29 Eylül 2026

- Format Sonrası başlangıç/olay bağlantıları Initialize-LtSetupView içinde toplandı; uygulama ve Windows doğrulayıcı aynı yolu kullanır. Profil uygulama seçimleri Set-LtSetupPackageSelection ile geri yüklenir; bilinmeyen kimlik önce reddedilir, eski seçim korunur.
- Windows SmokeOnly gerçek WPF SelectionChanged/TextChanged/Click olaylarıyla gizli seçim, kategori, profil seçimlerini geri yükleme, yalnız seçili satırı kaldırma ve tüm seçimleri temizleme senaryolarını çalıştıracak. Kurulum/indirme yok. Bu ortam Linux olduğu için yeni WPF senaryosu çalıştırılmadı.
- Linux: UiNavigation + Setup + Static toplam 130 geçti, 0 başarısız/atlandı (11.85 s). Analiz, doğrulayıcıdaki otomatik $PROFILE değişken adını yakaladı; $setupProfile olarak düzeltildi. Değişen App.ps1 analizde bulgusuz; doğrulayıcı analizi yeniden çalıştırıldı.
- Görsel/klavye ve %100/%150/%200 DPI kabul adımları kontrol listesine eklendi. cff3e10 sonrası koyu tema/katalog/doğrulayıcı değişiklikleri tek küçük Windows test yamasında birleştiriliyor. Tam kurulum/release değildir. Push/tag/release yok.

## Format Sonrası görünür ekran incelemesi — 29 Eylül 2026, 22:53

- Kullanıcının powershell_J30hJmCxSq.png görüntüsü: 36/36 uygulama, 0 seçim, arama/kategori, koyu ComboBox/ScrollBar ve 80 piksel günlük alanı görünür. Görünen günlükte hata yok. Test-Windows PASS transcript'i bu tur verilmedi; WPF olay/DPI/native testleri tamamlandı sayılmadı.
- Görsel sorun: üstteki uzun profil alanı ve açıklamalar yüzünden uygulama listesinin yalnız ilk iki satırı görünüyordu. Kurulum bölümü öne alındı; profil bölümü aşağıda klavyeyle de açılabilen kapalı Expander içine taşındı. Kurulum düğmesi liste üstüne alındı. Kategori adı satır başlığının sağına taşındı; açıklamalar korundu.
- Sayfa açıklamasındaki belirsiz Arka plan servisi kurulmaz iddiası kaldırıldı (seçilen uygulamaların kendi arka plan bileşenleri olabilir). Memory üst çubuğundaki OS bilgisine Deneme sistemi etiketi eklendi; gerçek CPU/RAM kullanım okumaları değiştirilmedi.
- Windows doğrulayıcı profil bölümünün açık/kapalı layout'unu da ölçecek; Linux'ta WPF çalıştırılmadı. Yeni düzen henüz kullanıcı görüntüsüyle doğrulanmadı.
- Linux PS 7.4.6: Static + UiNavigation 109 geçti / 0 başarısız / 0 atlandı (8.54 s); değişen iki PowerShell dosyasında PSSA 0 bulgu. Kurulum manifesti güncellendi. Yeni ZIP/push/tag/release yok.

## Kullanıcının birleşik Windows testi başarılı — kayıt 29 Eylül 22:53, inceleme 30 Eylül 2026

- windows-check-20260929-225315-07341fdb(1).txt: Windows 10 build 19045, Windows PowerShell 5.1.19041.6456, SmokeOnly, RESULT PASS.
- C# yardımcı derlemesi; koyu ComboBox ve iki yönlü ScrollBar şablonları; gerçek WPF arama/kategori/seçim olayları ve profil seçimlerini geri yükleme; katalog ve yedi panelin 980x620/1240x820 içerik ölçümü; rapor; Memory uygula/geri al geçti.
- Kayıttaki tek True satırı SelectedItems.Remove dönüş değeri; hata değil. Doğrulayıcıda dönüş çıktısı void ile bastırıldı; kontrol korunuyor.
- Bu kayıt 84e7522 ile verilen paketin kabulüdür; sonraki 7cd46d7 kompakt düzen/kapalı profil bölümü değişikliğini kapsamaz. Windows 11, DPI, gerçek kurulum/sistem ayarı ve tam Windows Pester paketi doğrulanmış sayılmaz.
- Son kompakt düzeni içeren birleşik r2 test yaması hazırlanıyor. Kullanıcıdan aynı eski testi tekrar istemek yerine yalnız güncel düzenin kontrolü istenecek. Push/tag/release yok.

## Kompakt arayüz Windows kabulü — 30 Eylül 2026, 19:41

- windows-check-20260930-194112-bf597051.txt: Windows 10 build 19045, PS 5.1.19041.6456, SmokeOnly RESULT PASS. Güncel r2 doğrulayıcı: koyu kontrol şablonları, WPF filtre/seçim/profil olayları, yedi panel ve katalog ölçümleri, rapor, Memory uygula/geri al başarılı. SetupPanel senaryosu güncel doğrulayıcıda profil bölümünün açık/kapalı ölçümünü de içerir. Önceki gereksiz True çıktısı yok.
- powershell_omq9qedmMP.png kullanıcı tarafından bilerek tam ekran alınmış: uygulama kurulumu ilk sırada, düğme liste üstünde, 36 kayıt/sıfır seçim, kompakt satırlar, aşağıda kapalı profil başlığı ve Deneme sistemi etiketi görünür. Görünen günlükte hata yok. Tam ekran genişliğine yayılan satırlar görsel tercih olarak not edildi; görüntüde küçük görünen metin tek başına DPI hatası kanıtı değildir.
- Bu tur kod değişikliği ve yeni paket yok. Windows 11, farklı DPI/klavye görsel kabulü, gerçek WinGet/temizlik/sistem ayarı ve geri alma testleri açık. SmokeOnly tam Windows Pester/PSSA paketi değildir.

## Gerçek Windows kabulüne geçiş — 30 Eylül 2026

- Destek matrisi güncellendi: Windows 10/PS 5.1 SmokeOnly sonucu; farklı UAC hesabında kullanıcı kapsamı engeli; ISLC dosya seçimi; CFG/hibernation geri alma sınırları mevcut kodla eşleştirildi.
- VM kabulü için ilk küçük oturum tanımlandı: başlangıç registry durumunu salt okunur kaydet, Oyun Modu ve saydamlığı tek tek önizle/vazgeç/uygula/önceki ayara dön ile doğrula; sonra ayrı WinGet ve kapalı launcher temizliği. Zaten uygulanmış sonuç geri alma testi sayılmaz.
- Üreticinin kurduğu güç planı için power.installed kabulü eklendi; eski Bitsum dosyası koşullu kaldı. Bu tur ürün kodu değişmedi, test tekrarına veya pakete gerek yok. Windows VM erişimi/varlığı henüz bilinmiyor; gerçek sistem testi çalıştırılmadı.
