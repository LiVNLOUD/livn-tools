# Windows doğrulama kontrol listesi

Bu sürüm Linux üzerinde geliştirildi. Birim/entegrasyon testleri **bellek arka ucu**
ile çalıştı; WPF arayüzü ve gerçek sistem değişiklikleri **çalıştırılmadı**. Aşağıdaki
adımlar gerçek doğrulama içindir.

> Sistem değiştiren adımları (Bölüm 3–5) **kendi bilgisayarınızda değil**, anlık
> görüntü (snapshot) alınmış bir **Windows VM**'de yapın.

## İlk deneme — modül kurmadan

- ZIP kullanıyorsanız tamamını yazılabilir bir klasöre çıkartın; ZIP içinden çalıştırmayın.
- `Test-Windows.bat`: yönetici yetkisi ve internet istemeden SmokeOnly kontrolünü çalıştırır.
  Sonuç/hata ayrıntısı `tests/results/windows-check-*.txt` dosyasına yazılır; dosyayı inceleme için paylaşabilirsiniz.
- Başarılı olursa `Test-Arayuz.bat`: arayüzü yalnız DryRun modunda açar; deneme kayıtları
  `tests/results/ui-data` altında tutulur. Başlıkta DENEME MODU bulunmalı.
- Bu ilk denemede normal `LivnTools.bat` başlatıcısını kullanmayın; o gerçek uygulama içindir.
- Tam Pester/PSSA testi, gerekli modüller zaten kuruluysa:
  `powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tools\Invoke-WindowsCheck.ps1 -Full`
  Hiçbir test başlatıcısı kendiliğinden modül indirmez/kurmaz.

## 0. Hazırlık (VM)

```powershell
# Windows 11 23H2/24H2 ve Windows 10 22H2 VM'leri; mümkünse biri Türkçe dil paketli.
# Anlık görüntü alın. Yönetici PowerShell 5.1:
Set-Location C:\LivnTools            # depo/ZIP buraya açıldı
Install-Module Pester -MinimumVersion 5.5 -Scope CurrentUser -Force -SkipPublisherCheck
Install-Module PSScriptAnalyzer -Scope CurrentUser -Force
```

## 1. Otomatik testler (sisteme dokunmaz)

Yeni doğrulama giriş noktası (Windows PowerShell **5.1**, yönetici gerektirmez):

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tools\Invoke-WindowsValidation.ps1
# Pester/PSScriptAnalyzer kurulmadan yalnız C# ve WPF kontrolü:
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tools\Invoke-WindowsValidation.ps1 -SmokeOnly
```

Bu adım gerçek .NET Framework altında üç C# yardımcısını derler; ana/rapor XAML'ini,
kayıtlı kontrolleri ve katalog satır şablonlarını yükler. İki pencere boyutunda temel
içerik alanı layout hesabı doğrudan Content kökünde yapılır; pencere gösterilmez.
Ölçüler pencere çerçevesini içermez. Bağımsız panel hataları biriktirilir; varsa sonuç FAIL olur. Gizli yardımcı paneller sırayla görünür yapılır;
Format Sonrası kurulum/kaldırma listeleri katalogla doldurulur ve seçili satırları oluşturulur.
Bu kontrol taşmayı, renkleri veya bütün binding hatalarını otomatik olarak tespit etmez. Uygula/geri al yalnız Memory arka ucundadır.
Geçici veri klasörü bu çalıştırma için oluşturulup kaldırılır. Normal mod sonunda
Pester ve PSScriptAnalyzer ayrı PowerShell 5.1 işleminde çalışır; SmokeOnly bunları atlar.

**Sınır:** Başarılı olması gerçek UI açılışı, tüm binding'ler, DPI, klavye veya gerçek
Windows ayarı geri almasının geçtiğini göstermez. Aşağıdaki elle VM adımları gereklidir.
Linux/pwsh/MTA ile çağrılırsa açık hata verir; Windows doğrulaması yapılmış sayılmaz.


```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Invoke-Tests.ps1
pwsh       -NoProfile -ExecutionPolicy Bypass -File .\tools\Invoke-Tests.ps1   # PS 7 varsa
```
Beklenen: PSScriptAnalyzer 0 hata; Pester 0 başarısız. Sonuçlar `tests\results\`.

- [ ] PS 5.1'de tüm testler geçti (özellikle `UiLogic.Tests.ps1` — C# görünüm modelleri csc ile derlenir)
- [ ] PS 7'de tüm testler geçti

## 2. Arayüz — kuru çalışma (sisteme dokunmaz, yönetici gerekmez)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -STA -File .\Main.ps1 -DryRun
```
- [ ] Pencere açılıyor; başlıkta "DENEME MODU" rozeti var
- [ ] Kenarlardan boyutlandırma, çift tıkla/sürükle-bırak ekrana yaslama (Aero Snap), ekranı kapla/küçült çalışıyor
- [ ] %125 / %150 / %200 ölçekte metin keskin, taşma yok (Ayarlar > Ekran > Ölçek)
- [ ] Tab/Shift+Tab ile tüm butonlar ve onay kutuları odaklanıyor, odak çerçevesi görünüyor; Boşluk işaretliyor
- [ ] Gezinti listesinde ok tuşları çalışıyor; başlıklar (TEMİZLİK vb.) seçilemiyor
- [ ] Performans sayfasında durum rozetleri "Okunuyor…" → gerçek duruma dönüyor; UI donmuyor
- [ ] Güç planlarından birini seçince diğeri kalkıyor (tek seçim)
- [ ] "Standart" hazır seçimi: hiçbir kırmızı "GÜVENLİĞİ AZALTIR" satırı işaretlenmiyor
- [ ] "Önizle ve uygula…": önizleme penceresinde her satır "mevcut → hedef" gösteriyor; "Vazgeç" hiçbir şey değiştirmiyor
- [ ] Uygula → ilerleme çubuğu (n/N), günlük akıyor, Sonuç penceresi; satırlarda "Son işlem" metni
- [ ] Güvenlik ayarı seçilince önizlemede onay kutusu olmadan "Uygula" pasif
- [ ] Değişiklik Geçmişi: ledger satırları ve işlemler listeleniyor; satır seçip "önceki değere döndür" çalışıyor
- [ ] Esc / İptal: uzun işlemde mevcut ayar bitince duruyor, kalanlar "Atlandı"
- [ ] Günlük Kaydet / Gizle / Temizle çalışıyor; Türkçe karakterler doğru
- [ ] Kuru çalışmada Hızlı Temizlik: Chrome açıkken "kapat" onaylansa bile Chrome **kapanmıyor**;
      `%TEMP%` içine konan bir test dosyası **silinmiyor**; sonuç penceresi "simüle edildi" diyor
- [ ] Kuru çalışmada Gelişmiş Temizlik (SFC/DISM) seçilip çalıştırılınca Görev Yöneticisi'nde
      `sfc.exe`/`dism.exe` **başlamıyor**
- [ ] Kuru çalışmada Betik Çalıştır ve .reg içe aktar reddediliyor (durum çubuğu mesajı)

## İlk gerçek test oturumu — küçük kapsam

Aşağıdaki adımlar geri dönülebilir anlık görüntüsü alınmış Windows 11 test VM'si içindir. Deneme modu bu testin yerine geçmez; ana bilgisayarda toplu uygulama yapılmaz.

1. VM anlık görüntüsü alın. Aynı kullanıcı hesabıyla UAC yükseltmesi kullanın; ilk turda hazır seçim veya Tümünü seç kullanmayın.
2. Başlangıçta aşağıdaki iki salt okunur komutun çıktısını saklayın. Eksik değer hatası da başlangıç durumudur; kendiniz değer oluşturmayın.
   ```powershell
   Get-ItemProperty 'HKCU:\Software\Microsoft\GameBar' -Name AutoGameModeEnabled -ErrorAction Continue
   Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name EnableTransparency -ErrorAction Continue
   ```
3. LivnTools.bat ile normal modda açın. Önce yalnız Oyun Modu ayarını seçip önizleyin. Vazgeç deyip yukarıdaki komutu tekrar çalıştırın: başlangıç aynı kalmalı.
4. Aynı ayarı uygulayın. Komutla hedef değeri doğrulayın; Önceki ayara dön kullanıp başlangıçtaki değer/eksiklik durumuna döndüğünü kontrol edin. Zaten uygulanmış ise bunu kaydedin; bu, değişiklik sonrası geri alma testi geçmiş demek değildir.
5. Aynı döngüyü saydamlık kapatma ayarı için yapın. İlk iki ayarda başarısızlık veya geri alma farkı varsa diğer ayarlara geçmeyin; günlüğü ve öncesi/sonrası çıktıları saklayın.
6. Ardından VM'de yalnız bir uygulamanın WinGet kurulumu/ikinci kez atlanması; sonra tek bir kapalı launcher'ın dar kapsamlı önbellek temizliği ayrı oturumlarda sınanır. Temizlik için geri alma yerine VM anlık görüntüsü kullanılır.

BCD, güvenlik azaltmaları, MSI/NIC, hazırda bekletme ve ISLC görevleri aşağıdaki ayrı kabul senaryolarına aittir. Sanal GPU/NIC davranışı gerçek donanım performans kanıtı değildir.

## 3. Gerçek uygulama — tek ayarlar (VM)

```powershell
# LivnTools.bat'a çift tıklayın (UAC onayı) veya:
powershell -NoProfile -ExecutionPolicy Bypass -STA -File .\Main.ps1
```
Her satır için: uygula → durum "Uygulanmış" → **bağımsız doğrulama komutu** → "Önceki ayara dön" → komut özgün değeri göstermeli.

| Ayar | Bağımsız doğrulama |
|---|---|
| game.mode | `Get-ItemProperty HKCU:\Software\Microsoft\GameBar -Name AutoGameModeEnabled` |
| sched.mmcss-games | `Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'` |
| sched.win32prio-14 | `Get-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl` |
| timer.platformclock-default | `bcdedit /enum '{current}' /v` (önce `bcdedit /set '{current}' useplatformclock yes` ile zorlayın) |
| power.ultimate (2 kez!) | `powercfg /list` → Livn planı **tek** kez görünmeli (`d72c20ca-…`) |
| power.installed (üreticinin kurduğu plan, 2 kez) | `powercfg /list` ve `powercfg /getactivescheme` → plan sayısı değişmez; geri almada önceki etkin GUID gelir |
| power.bitsum (yalnız kullanıcıca sağlanan plan dosyası varsa) | Dosya yokken desteklenmiyor; varsa iki uygulamada sabit GUID ile yalnız bir plan |
| svc.sysmain-off | `Get-Service SysMain | Select Status,StartType` |
| net.ecn-off | `Get-NetTCPSetting -SettingName Internet | Select EcnCapability` |
| nic.flowcontrol-off | `Get-NetAdapterAdvancedProperty -RegistryKeyword '*FlowControl'` |
| net.ackfreq | `Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\{…}'` |
| sec.cfg-off (yalnızca VM) | `Get-ProcessMitigation -System` → CFG Enable: OFF; geri almada önceki değer |
| msi.gpu (yalnızca VM) | `reg query "HKLM\SYSTEM\CurrentControlSet\Enum\<PCI yolu>\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"` |
| mem.islc-autostart (2 kez) | `Get-ScheduledTask -TaskPath \LivnTools\` → tek görev |
| sys.eventlog-size | `Get-WinEvent -ListLog Application | Select MaximumSizeInBytes` |
| sys.hibernate-off | `powercfg /a` ve `Test-Path C:\hiberfil.sys` |
| mem.pagefile-auto | `(Get-CimInstance Win32_ComputerSystem).AutomaticManagedPagefile` (yeniden başlatma sonrası) |
| ui.classic-context | Explorer yeniden başlatma sorusu → sağ tık menüsü |

- [ ] "Windows varsayılanı" butonu en az 3 ayarda belgelenen değeri yazıyor
- [ ] Olmayan registry değerleri geri almada **siliniyor** (ör. game.mode ilk kez uygulanırken değer yoksa)
- [ ] Erişim reddi senaryosu: `sc.exe sdset` ile bir servisi kilitleyin → "Başarısız" ve mesajda çıkış kodu
- [ ] Türkçe dil paketli VM'de güç planı/NIC/TCP durumları doğru okunuyor

## 4. Hata ve kurtarma (VM)

- [ ] Uygulama sırasında (çok ayarlı işlem) Görev Yöneticisi'nden `powershell.exe`'yi sonlandırın → yeniden açınca sarı "Yarım kalmış işlem" bandı; "İşlem öncesine geri al" değerleri geri getiriyor
- [ ] Geri yükleme noktası: 24 saat içinde ikinci deneme "Atlandı" + neden; Sistem Koruması kapalıyken "Başarısız"
- [ ] `data\state\ledger.json` dosyasını bozun → uygulama kopyasını `.corrupt-…` olarak saklayıp hata veriyor (veri silmiyor)

## 5. Temizlik (VM)

- [ ] Açık bir dosyayı `%TEMP%` altında kilitleyin (`$f=[IO.File]::Open("$env:TEMP\kilit.txt",'Create')`) → sonuç "Kısmen", bayt yalnızca silinenler
- [ ] Chrome açıkken Chrome temizliği → kapatma sorusu (Evet/Hayır/İptal)
- [ ] DISM/SFC → çıkış kodu raporlanıyor; iptal isteği uzun komut bitince uygulanıyor
- [ ] USB kayıt temizliği: yalnızca takılı OLMAYAN USBSTOR aygıtları kaldırılıyor

## 6. Kurulum / güncelleme

```powershell
# Yayın öncesi yerel deneme (etiket gerektirmez):
pwsh -File tools\Build-Release.ps1 -Version 4.0.0
& ([scriptblock]::Create((Get-Content .\win.ps1 -Raw))) -InstallRoot "$env:TEMP\LtInstallTest" -SourceOverride (Resolve-Path .).Path -NoLaunch
```
- [ ] `app\`, `data\`, `LivnTools.bat`, `.livntools-root` oluştu; `app\VERSION.json` doğru
- [ ] Bir dosyayı kaynakta bozup tekrar kurun → "bütünlük doğrulanamadı", mevcut `app` DEĞİŞMEDİ
- [ ] İkinci kurulumdan sonra `app.prev` var; `-Rollback` önceki sürüme dönüyor
- [ ] v3.5 kurulu bir `Documents\LivnTools` üzerinde kurulum: `.reg` yedekleri `data\legacy-v3.5\Backups` altında
- [ ] Etiket yayımlandıktan sonra: `irm livn.tr/win | iex` (livn.tr yönlendirmesinin `main`'deki win.ps1'e gittiğini doğrulayın)

## Hazırda bekletme ve CFG — yeni sağlayıcı kabulü

- VM anlık görüntüsü alın. Full otomatik boyut, Full özel yüzde ve Reduced durumlarını ayrı ayrı kapatıp önceki ayara dönün. Dosya türünü API ile, boyut tercihini registry ile ve yeniden başlatma sonrasında kontrol edin.
- Kapatma açık oturum içeriğini korumaz. Eski Enabled-only ledger otomatik geri alma yapmamalı; kayıt silinmemeli.
- powercfg adımlarının ortasında hata üretin; sonuç başarılı olmamalı, journal ve ledger korunmalı.
- CFG uygulamasından sonra başka bir mitigasyonu değiştirin; önceki ayara dönüş o tercihi korumalı. CFG'nin kendisi ON olarak değiştirilirse önceki ayara dönüş çakışma bildirmeli.
- GetPwrCapabilities interop yapısının boyutunu (76), alan ofsetlerini (8,22) ve WinPS 5.1 C# derlemesini doğrulayın.

## Kullanıcı hesabı kapsamı ve güncelleme ayrımı

- HKCU için aynı kullanıcıyla UAC yükseltmesi, farklı yönetici hesabı ve Explorer olmayan oturumu ayrı ayrı deneyin. Son iki durumda yazma/silme olmamalı.
- Başka hesaba ait ve kimliksiz eski yedekleri previous/backup/recovery üzerinden deneyin: işlem reddedilmeli, ledger korunmalı. Varsayılana dönüş ve SPI ham alt kayıtları da kontrol edilmeli.
- Windows 10 desteklenen sürümde özellik ertelemesini uygulayın: kalite ve AU yeniden başlatma anahtarları değişmemeli. Kalite ertelemesini ayrı uygulayıp geri alın: özellik tercihi korunmalı.
- Home, Windows 11 ve Server destek sınırlarını kontrol edin. Eski birleşik wu.defer ledger kaydındaki tüm değerlerin önceki ayara dönüşle geri yüklendiğini doğrulayın. Etkin takvimi Windows Update/ilke raporuyla ayrıca doğrulayın.

## Arayüz düzenlemesi — görsel kabul

- 980×620 ve 1240×820 pencere ölçülerinde hazır seçim düğmeleri sarmalanmalı; yatay taşma olmamalı. %125/%150/%200 DPI ayrıca denenmeli.
- Uzun Türkçe başlık ve açıklamalarda mevcut durum rozeti ile metin çakışmamalı. Risk ve kanıt düzeyi ayrı okunmalı.
- Seçili fakat uygulanmamış, seçili ve zaten uygulanmış, desteklenmeyen, kısmen uygulanmış ve başarısız durumları ayrı ayrı inceleyin. İşlem için seçildi rozeti mevcut durumun yerine geçmemeli.
- Tab/Shift+Tab ve Boşluk ile kart seçimi çalışmalı; desteklenmeyen kartın açıklaması okunur kalmalı. Ana pencere ile önizleme/sonuç penceresinin renkleri uyumlu olmalı.
- Adaptör ve GPU seçicilerinde uzun aygıt adları, menü gecikmesi seçimi ve güncel hazır seçim yönergeleri kontrol edilmeli.

## Yayın ön kontrolü

```powershell
powershell -NoProfile -File .\tools\Build-Release.ps1 -Version 4.0.0 -CheckOnly
```

Bu işlem manifest veya ZIP yazmaz. Zorunlu dosyalar (LICENSE dahil), modül/sürüm eşleşmesi ve manifest yapısı denetlenir. Başarılı olması Windows kabul testlerinin veya üçüncü taraf dağıtım izinlerinin tamamlandığı anlamına gelmez. LICENSE proje sahibinin seçtiği koşulları içermelidir; araç lisans seçmez.


## İsteğe bağlı performans araçları kabulü

1. DryRun'da yeni performans panelini açın: ISLC/ParkControl/Process Lasso/PresentMon ve Windows güç ayarları düğmeleri gerçek tarayıcı/uygulama başlatmamalı. Plan listesi sahte sistemden gelmeli. Seçim tek başına görev/plan değişikliği yapmamalı.
2. Anlık görüntülü Windows VM'de ISLC 1.0.4.8'i resmî paketten kalıcı bir klasöre çıkartın. Kendi arayüzünde timer seçeneğini ve başlangıç davranışını kontrol edin. Uygulama dosyasını seçin; algılanan fiziksel RAM ve önizlemedeki CLI parametrelerini doğrulayın. Yeni sürümün bu parametreleri gerçekten okuduğunu uygulama arayüzünden teyit edin. Görevin çalışma dizini/config kullanımı ayrıca incelenmeli.
3. Otomatik başlatmayı uygulayıp oturumu yeniden açın: tek ISLC örneği, doğru kullanıcı/yetki, doğru eşikler ve görev eylemi. Livn'i yeniden açınca dosya yolu görevden bulunmalı. Önceki ayara dönüş görevi geri yüklemeli/kaldırmalı; çalışan ISLC'nin kendi Exit komutuyla kapatılması gerekebilir. Eski ISLC otomatik başlangıcının ikinci süreç üretmediğini kontrol edin.
4. Bitsum planını üreticinin aracıyla kurun. Planları yenileyin, doğru isim/GUID'yi seçin, önizleyip uygulayın. Plan sayısı artmamalı, önceki etkin plana dönüş doğrulanmalı. Otomatik plan değiştiren başka bir aracı deney sırasında durdurun. Power Modes cihazında zorunlu BHP kurulumu yapılmamalı; Windows güç modu ayrı değerlendirilir.
5. Gerçek donanımda aynı oyun sürümü, sahne, ayarlar, güç kaynağı ve sıcaklık koşullarıyla her seferinde tek değişiklik deneyin. Isınma çalıştırmasından sonra başlangıç/değişiklik/başlangıç sırasıyla tekrarlı PresentMon kayıtları alın. Ortalama FPS kadar kare zamanı dağılımı, takılmalar, sıcaklık ve güç tüketimini karşılaştırın. Ölçülmeyen veya tekrarlanamayan kazancı 'kanıtlanmış' olarak etiketlemeyin.


## Format Sonrası ve launcher kabulü

SmokeOnly, gerçek WPF kontrolleri üzerinde uygulama arama, kategori değiştirme, görünmeyen seçimleri koruma, profil seçimlerini geri yükleme, yalnız seçili filtreleme ve temizleme olaylarını da çalıştırır. WinGet veya uygulama kurulumu başlatmaz. Bunun başarılı olması aşağıdaki görsel/klavye kabulünün yerine geçmez.

- [ ] Koyu seçim kutularında Tab, yön tuşları, Alt+Aşağı ve Esc davranışını kontrol edin. Uzun listede tekerlek, kaydırma tutamacı ve boş kanala tıklama doğru yönde çalışmalı; listeden seçim planı kendiliğinden uygulamamalı.
- [ ] Format Sonrası: Steam seçin, Firefox arayıp onu da seçin. Eşleşmeyen aramada görünür sayı 0, seçili sayı 2 olmalı. Aramayı temizleyip Yalnız seçtiklerim seçeneğini açın; iki satır ve kurulum önizlemesinde iki uygulama görünmeli. Vazgeç işlemi başlatmamalı.
- [ ] Seçimleri JSON profiline kaydedip uygulama seçimlerini temizleyin. Farklı kategori/arama açıkken profili yükleyin: gizli seçimler sayılmalı, filtreler kaldırıldığında seçimler görünmeli. Boş uygulama listeli profil önceki seçimleri temizlemeli.
- [ ] %100/%150/%200 DPI ve küçük pencerede uygulama açıklamaları, seçim sayacı, kurulum önizlemesi ve 80 piksel günlük alanı okunabilir olmalı. Koyu tema ve klavye odağı açılır listede de görünmeli.

- PS 5.1 + WPF: Format Sonrası sayfası, liste seçim rengi, klavye, profil yükle/kaydet ve Akıcı görünüm düğmesini kontrol edin. Profil yüklemek tek başına uygulama kurmamalı/ayar yazmamalı; seçilmiş seçenekler sayfalarda görünmeli.
- Önceden karışık görsel efektler seçilmiş bir test hesabında Akıcı görünüm önizleme/uygula/geri al: beş SPI efekti ve pencere/görev çubuğu tercihleri geri gelmeli; yazı yumuşatma/küçük resim tercihleri korunmalı. Kaynak C# yalnız Linux .NET üzerinde derlendi; gerçek API kabulü yapılmadı.
- Yeni kullanıcı/ayrı VM'ye profil taşıyın; eski SID, registry yedekleri ve dosya yolları taşınmamalı. Uyumsuz sürümde klasik menü/Widgets/End Task destek ve davranışını kontrol edin.
- WinGet ile önceden kurulu bir paketin atlandığını, eksik paketin kurulduğunu ve son envanterden doğrulandığını test edin. Ağ hatası, eksik/eski WinGet, paket sözleşmesi, kurulum hatası, yeniden başlatma gereği ve paketler arası iptal durumlarını kontrol edin. Kurulumlar yalnız anlık görüntülü test VM'sinde yapılmalı.
- Appx listesinde kurulu olmayanlar, kaldırılabilir seçimler ve kurulum sonrası envanter: yalnız test kullanıcısı etkilenmeli. Store, framework ve Xbox/Game Pass altyapısı korunmalı. Kaldırmanın kişisel uygulama verilerini silebileceği uyarısı görünmeli.
- Launcher'lar açıkken (tepsi/yardımcı süreç dahil) temizlik atlanmalı; Minecraft için başka Java uygulaması asla kapatılmamalı. Gerçek kurulum yollarını doğrulayın; son 7 gün logları, oyunlar, modlar, kayıtlar, hesap dosyaları ve oturum verileri korunmalı. Önbellek temizliğinden sonra istemcide yeniden indirme/geçici yavaşlama olup olmadığını kontrol edin.

## Kaydedilen kabul durumu — 30 Eylül 2026

29 Eylül 22:53 SmokeOnly kaydı Windows 10 build 19045 / PowerShell 5.1 üzerinde PASS: koyu kontrol şablonları, gerçek WPF Format Sonrası filtre/seçim/profil olayları, tüm panel içerik ölçümleri ve Memory uygula/geri al geçti. Bu kabul, sonradan eklenen kompakt uygulama düzeni ve kapalı profil bölümünü kapsamaz. Gerçek WinGet, sistem değişiklikleri/geri alma, Windows 11 ve DPI kabulü hâlâ açık.

## 1 Ekim 2026 — envanter, temizlik önizlemesi ve dayanıklılık kabulü

Ana bilgisayarda temizlik veya sistem değişikliği çalıştırmayın; gerçek temizlik ve kurulum adımları anlık görüntülü VM içindir.

- [ ] `Test-Windows.bat` (SmokeOnly): yeni `PASS: setup inventory states and status text` satırı görünmeli. Ardından `tools\Invoke-Tests.ps1` ile tam paket (Pester + PSSA) Windows PowerShell 5.1'de çalıştırılmalı.
- [ ] DryRun (`Test-Arayuz.bat`) Format Sonrası: satırlarda "Kurulu / Kurulu değil" deneme durumu ve "deneme envanteri" notu görünmeli; **Kurulum durumunu yenile** 30 saniye içinde ikinci kez basılınca bekleme süresi bildirilmeli. Arama/kategori/seçimler yenileme sonrası değişmemeli. Hiçbir `winget` süreci başlamamalı (Görev Yöneticisi).
- [ ] Gerçek modda (VM) Format Sonrası açılırken arayüz donmamalı; envanter sürerken başka sayfaya geçip ayar önizlemesi açılabilmeli. Kurulu bir uygulama "Kurulu", eksik olan "Kurulu değil" görünmeli. Kurulum onayında kurulu görünen uygulama "Kurulu görünüyor" satırıyla gelmeli; kurulumdan sonra yükseltme yapılmamalı ve envanter kendiliğinden yenilenmeli.
- [ ] WinGet'i geçici olarak erişilemez yapın (ör. App Installer devre dışı bir test hesabı) ve ağ bağlantısını kesin: durum "Durum okunamadı", açıklama "kurulu olmadığı anlamına gelmez" olmalı; **Yeniden dene** çalışmalı. Kaynak sözleşmesi bekleyen yeni profilde arka plan envanteri sözleşmeyi kabul etmemeli.
- [ ] Temizlik önizlemesi (VM): %TEMP% ve bir tarayıcı önbelleği seçip **Önizle (boyut)…**. Önizleme sırasında Explorer'da dosya sayıları ve değiştirilme zamanları değişmemeli, açık tarayıcı kapanmamalı. Ardından temizlik; silinen boyut önizlemeye yakın olmalı (kullanımdaki dosyalar fark yaratabilir).
- [ ] Önizlemede DNS/SFC/DISM/Geri Dönüşüm Kutusu "Boyut hesaplanmadı" görünmeli; hiçbir komut çalışmamalı. EA/Battle.net/Xbox "Desteklenmiyor" kalmalı.
- [ ] Bir önbellek klasörünü önizlemeden sonra başka bir klasöre işaret eden junction ile değiştirin (`mklink /J`): temizlik o hedefi silmemeli, sonuç "bağlantı" nedeniyle başarısız/kısmen olmalı; junction hedefindeki dosyalar kalmalı.
- [ ] Yetkisi kaldırılmış (ACL deny) bir alt klasör: önizleme "erişim hatası nedeniyle taranamadı" ve "en az" göstermeli.
- [ ] Ledger dayanıklılığı (VM): bir ayar uygulayın; `data\state\ledger.json` dosyasını `ledger.json.bak` olarak yeniden adlandırın; Livn'i açınca Değişiklik Geçmişi kaydı görünmeli ve "Önceki ayara dön" çalışmalı.
- [ ] Gelişmiş Temizlik (VM): DISM/SFC adımlarının satırında "ölçülmedi" görünmeli; özet "toplam 0 B silindi" yerine ölçülen ve ölçülmeyen işlemleri ayrı göstermeli. Disk Temizleme boş alan artışı yoksa bunu söylemeli.

## 1 Ekim 2026 (2) — hazır seçimler, güç planı dosyaları, GPU/MSI, Brave algılama

Gerçek uygulama adımları yalnız anlık görüntülü VM veya ayrılmış test bilgisayarında yapılır.

- [ ] DryRun: her hazır seçim düğmesinden sonra bilgi satırı "N ayar işaretlendi" ve atlanan ayarları nedeniyle göstermeli. Maksimum performans'ta adaptör seçilmemişse akış denetimi/EEE "adaptör seçin" nedeniyle atlanmalı; Ağ sayfasında adaptör seçip düğmeye yeniden basınca işaretlenmeli.
- [ ] Kaynak ZIP'ten açılan kurulumda Performans sayfası: Bitsum ve iki Hybred planı "Plan dosyası bulunamadı" göstermemeli. `_Files` içindeki bir .pow dosyasına bir bayt ekleyin: seçenek SHA-256 nedeniyle desteklenmiyor olmalı. Dosyayı geri koyun.
- [ ] VM: Bitsum planını uygulayın → `powercfg /list` içinde plan bir kez görünmeli ve etkin olmalı; "Önceki ayara dön" önceki planı etkinleştirmeli. Aynı adım Hybred HighPerf/Balanced için.
- [ ] GPU ve MSI: aygıt listesinde `PCI\VEN_...` görünmemeli; satırlar "Ekran kartı — <ad> · donanım: MSI/MSI-X" biçiminde olmalı. Ekran kartı seçilince GPU MSI seçeneği etkinleşmeli, ağ kartı seçeneği "ağ kartı değil" nedeniyle kapalı kalmalı (ve tersi).
- [ ] VM: GPU MSI uygula → yeniden başlat → Aygıt Yöneticisi > Kaynaklar (bağlantıya göre) altında IRQ negatif değer (MSI) görünmeli; aygıt çalışmalı. "Önceki ayara dön" sonrası kayıt eski hâline gelmeli. Ağ kartı için aynısı; bağlantı gelmezse Güvenli Mod'da geri alma da sınanmalı.
- [ ] "HAGS durumunu ... oku" düğmesi: sürücü desteği ve "şu an açık/kapalı" bilgisi Windows Ayarlar > Sistem > Ekran > Grafik > Varsayılan grafik ayarları ekranıyla aynı olmalı. HAGS'ı Livn ile açıp yeniden başlatınca Windows ekranı da açık göstermeli. Desteklemeyen sürücüde (ör. Microsoft Temel Görüntü Bağdaştırıcısı) seçenek kapalı kalmalı.
- [ ] Format Sonrası: WinGet dışı kurulu Brave (ve Chrome/Discord gibi) "Kurulu (WinGet dışı)" görünmeli; seçilse bile kurulum onayında "Kurulu görünüyor" olmalı ve yeniden kurulmamalı. Brave Beta/Nightly yüklüyse kararlı Brave "Kurulu" sayılmamalı.

## 2 Ekim 2026 — farklı kabuk, kurulum yeri, oturum ve WinGet

- [ ] `C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe` (32-bit) içinden `-File Main.ps1 -DryRun`: uygulama tek kez yeniden açılmalı; Görev Yöneticisi'nde süreç 64-bit olmalı. Aynısı PowerShell 7 (`pwsh`) ve ISE'den.
- [ ] `LivnTools.bat`: ZIP'i "Engellemeyi kaldır" yapmadan çıkarın ve test VM'sinde GPO ile ExecutionPolicy RemoteSigned verin → kod 5 mesajı görünmeli. AllSigned → kod 4. Normal sistemde ön kontrol penceresi kısa süre görünüp kapanmalı.
- [ ] `irm livn.tr/win | iex` yerine yerel `win.ps1 -SourceOverride` ile: yeni VM'de kurulum `%LOCALAPPDATA%\LivnTools`'a gitmeli, Başlat menüsünde "Livn Tools" kısayolu olmalı ve çalışmalı. Belgeler'de eski kurulum olan VM'de güncelleme yerinde yapılmalı; Değişiklik Geçmişi korunmalı.
- [ ] İki kullanıcı oturumu (hızlı kullanıcı değiştirme): birinde Explorer yeniden başlatma ve "uygulamayı kapat" ile temizlik → diğer oturumun Explorer'ı ve uygulamaları etkilenmemeli. Explorer yönetici yetkisiyle başlamamalı (Görev Yöneticisi > Ayrıntılar > Yükseltilmiş sütunu).
- [ ] Standart kullanıcı oturumunda başka yönetici hesabıyla UAC onayı: %TEMP% temizliği "Kullanıcıya ait temizlik atlandı" vermeli; açık tarayıcı kapanmamalı.
- [ ] Boş Geri Dönüşüm Kutusu ile Hızlı Temizlik: "Başarısız" görünmemeli.
- [ ] Betik sekmesinde `pause` içeren .bat: hemen bitmeli. `ping -n 60 127.0.0.1` çalışırken İptal: betik birkaç saniye içinde durmalı. ANSI (1254) kaydedilmiş Türkçe .ps1 içe aktarınca karakterler doğru görünmeli.
- [ ] Windows 11 güncel sürüm: Görünüm hazır seçimi Widgets için ilkeyi seçmeli (UCPD etkinse); uygulama sonrası oturum kapatıp açınca Widgets simgesi olmamalı; "Windows varsayılanına dön" sonrası geri gelmeli.
- [ ] Modern Bekleme dizüstü: Maksimum performans'ta Bitsum/Ultimate seçilmemeli, bilgi satırı güç modunu önermeli.
- [ ] WinGet: App Installer'ı kaldırılmış/eski VM'de Format Sonrası "WinGet'i edinin / güncelleyin" düğmesini göstermeli; LTSC'de Microsoft Learn sayfası açılmalı. Açık bir uygulamayı (ör. Notepad++) kurmaya çalışınca "Uygulama açık" metni, ağ kapalıyken kaynak/ağ metni görünmeli. Çoklu kurulumda envanter yalnız başta bir kez okunmalı (günlük).
- [ ] TcpAckFrequency: seçili adaptörde uygulayın; `HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\{guid}` altında değer görünmeli, `{{guid}}` anahtarı oluşmamalı.

## 2 Ekim 2026 (2) — Sistem Kontrolü, bağlantı ölçümü, başlangıç, Oyuncu modu

- [ ] `Test-Windows.bat`: yeni `PASS: content layout HealthPanel` ve `StartupPanel` satırları görünmeli.
- [ ] Gerçek sistemde Sistem Kontrolü (salt okunur): sürücü listesi Aygıt Yöneticisi'ndeki sarı ünlemlerle aynı olmalı; yenileme hızı Ayarlar > Gelişmiş ekran ile aynı olmalı; RAM hızı Görev Yöneticisi > Bellek > Hız ile aynı olmalı; disk türü/TRIM (`fsutil behavior query DisableDeleteNotify`) eşleşmeli; olay sayıları Güvenilirlik İzleyicisi ile tutarlı olmalı. Okunamayan alan "Okunamadı" görünmeli, "Tamam" değil.
- [ ] Düğmeler: İsteğe bağlı sürücüler, Aygıt Yöneticisi, Gelişmiş ekran, Güvenilirlik İzleyicisi ve üretici sürücü sayfası yükseltilmemiş (normal kullanıcı) pencerede açılmalı. "Ayarı işaretle" ilgili sayfaya gidip ayarı işaretlemeli.
- [ ] "Raporu kaydet…": dosyada bilgisayar ve kullanıcı adı olmamalı.
- [ ] Ağ > Ping ölç: modem, 1.1.1.1, 8.8.8.8 değerleri `ping -n 20` ile benzer olmalı; ikinci ölçüm öncekiyle karşılaştırma göstermeli. Geçersiz hedef ("a b", "1.1.1.1; calc") reddedilmeli.
- [ ] DNS hız testi: `Resolve-DnsName -Server` ile benzer sıralama. DNS seçimi (VM): Cloudflare uygula → `Get-DnsClientServerAddress` 1.1.1.1 göstermeli; "Önceki ayara dön" → DHCP; elle DNS'li adaptörde eski adresler birebir dönmeli.
- [ ] Başlangıç Uygulamaları: liste Görev Yöneticisi > Başlangıç ile eşleşmeli; Livn ile kapatılan öğe Görev Yöneticisi'nde "Devre dışı" görünmeli; oturum kapatıp açınca başlamamalı; geri alınca yeniden başlamalı. Run değeri/kısayol silinmemeli.
- [ ] GPU sayfası (iki GPU'lu dizüstü, VM'de değil): oyun ekle → uygula → Ayarlar > Grafik'te oyun "Yüksek performans" görünmeli; Windows varsayılanına dönüşte kaybolmalı.
- [ ] Format Sonrası > Oyun bileşenleri: kurulu VC++/.NET "Kurulu" veya "Kurulu (WinGet dışı)" görünmeli; DirectX kuruluysa (d3dx9_43.dll) kurulu sayılmalı.
- [ ] **Adaptör seçimi (2 Ekim düzeltmesi):** Ağ sayfasında listeden adaptör seçince altında yeşil "Seçili hedef: …" satırı görünmeli; birkaç saniye içinde DNS ve adaptör ayarları "Desteklenmiyor" olmaktan çıkmalı. Tek adaptörlü sistemde açılışta adaptör kendiliğinden seçili gelmeli. Seçimi değiştirince hedef satırı ve durumlar yenilenmeli. Aynısı GPU sayfasında MSI hedefi için.
- [ ] Oyuncu modu (VM, anlık görüntü): tek ağ adaptörlü sistemde adaptör otomatik seçilmeli, önizleme doğrudan açılmalı, atlananlar nedenleriyle bilgi satırında olmalı; önizlemede hiçbir "GÜVENLİĞİ AZALTIR" satırı olmamalı. Uygula → yeniden başlat → Değişiklik Geçmişi'nden toplu geri alma çalışmalı.

## 2 Ekim 2026 (3) — Kurtarma Kiti ve gerçek WPF olay testleri

- [ ] `Test-Windows.bat`: `PASS: real WPF SelectionChanged for adapter/MSI targets`, `PASS: recovery kit defaults, dry-run kit creation and loading` ve `PASS: content layout KitPanel` satırları görünmeli. İlk satır başarısızsa 2 Ekim seçim hatası gerçek WPF'te sürüyor demektir.
- [ ] Kuru çalışmada kit: hedef olarak C:\ altı seçilince "sistem sürücüsünde" uyarısı; USB'de `LivnKurtarma-…-DENEME` klasörü ve KIT_OKU.txt başında DENEME uyarısı olmalı.
- [ ] Gerçek modda (VM, USB veya ikinci sanal disk): "Önizle" sürücü sayıları `pnputil /enum-drivers` içindeki üçüncü taraf paketlerle tutarlı olmalı; ekran kartı varsayılan olarak dahil olmamalı. Kit oluşturma sırasında hiçbir sistem ayarı değişmemeli (Değişiklik Geçmişi boş kalmalı).
- [ ] Kit içeriği: `Drivers\Network\…\*.inf` dosyaları; `LivnTools\LivnTools.bat`; Wi-Fi seçildiyse `WiFi\*.xml` (parola düz metin uyarısı onay penceresinde ve KIT_OKU.txt'de); Saves klasörü.
- [ ] Format sonrası (temiz VM, ağ sürücüsü olmayan sanal NIC türü ideal): kitteki `LivnTools.bat` → Kurtarma Kiti sayfası kendiliğinden açılmalı. ① Sürücüleri kur: önce geri yükleme noktası, sonra ağ; ağ bağlantısı gelmeli. Sonuç penceresinde 259 kodu "zaten uygun sürücü" olarak, 3010 yeniden başlatma olarak görünmeli.
- [ ] ② Wi-Fi: ağlar parolasıyla eklenmeli. ③ Uygulamalar: Format Sonrası sayfasında kitteki uygulamalar seçili gelmeli. ④ Livn ayarları: önizleme açılmalı, bu PC'ye özgü ayarlar (adaptör/MSI/DNS/başlangıç) listede olmamalı. ⑤ Oyun kayıtları: var olan bir kayıt dosyası değişmemeli.
- [ ] Livn açılamazsa: KIT_OKU.txt'deki `pnputil /add-driver` komutu yönetici komut isteminde çalışmalı.
