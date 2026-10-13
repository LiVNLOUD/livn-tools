# r3 — İlk düzeltme paketi (2026-09-24)

Temel: r2 / 5a2ea40. Dal: dev/r3-tweak-review. Push, tag ve yayın yapılmadı.

## Uygulandı
- Test kökü önek karşılaştırması dizin sınırına bağlandı; Linux'ta büyük/küçük harf ayrımı korundu.
- Silme hedefinin ve üst dizinlerinin reparse point olması reddediliyor. Test kökü de aynı kontrolden geçiyor. Silme sırasında dosya/dizin hedefleri yeniden kontrol ediliyor. Bu kontroller, başka bir sürecin kontrol ile silme arasında yolu değiştirdiği yarış durumuna karşı atomik güvence değildir.
- Durdurulması istenen servis çalışıyorsa hedefe ulaşılmış sayılmıyor. Durdurma/başlatma hataları yutulmuyor; motor hata ve geri alma akışını kullanıyor. Geri alma doğrulaması çalışma durumunu da karşılaştırıyor (varsayılan dönüşün Unknown durumu hariç).
- MMCSS yalnızca SystemResponsiveness=10 deneyini içeriyor; Games Priority, High kategorisi ve SFIO yazmaları kaldırıldı. Kimlik korundu: eski ledger içindeki eylemler önceki değere dönüşte kullanılabilir.
- Temel / Gizlilik / Görünüm hazır seçimleri birbirinden bağımsız. HAGS, MSI, NIC, servis, Windows Update ve zamanlayıcı değişiklikleri bu seçimlerde yok; manuel katalogda duruyor.
- Olay günlükleri için her sistemde 20 MB olduğu varsayılan dönüş kaldırıldı. Önceki kayıtlı değere dönüş korunuyor.
- 9 yeni regresyon testi eklendi. Eski çoklu eylem geri alma testi MMCSS yerine iki eylemli koyu mod ayarıyla aynı hata senaryosunu sınar.

MMCSS kaynağı: https://learn.microsoft.com/en-us/windows/win32/procthread/multimedia-class-scheduler-service

## Doğrulama durumu
- Yapıldı: git diff --check, XAML XML ayrıştırma, manifest dosya boyutu/SHA-256 kontrolü, katalogda 70 benzersiz kimlik, ZIP bütünlüğü.
- ÇALIŞTIRILMADI: PowerShell/Pester/PSScriptAnalyzer. Bu ortamda pwsh yok; erişim denemeleri zaman aşımına uğradı. r2'nin 171 başarılı test sonucu r3 için geçerli test sonucu olarak sunulmaz.
- ÇALIŞTIRILMADI: Windows PowerShell 5.1, WPF, gerçek servis/registry işlemleri ve performans ölçümleri.
- Windows doğrulama: önce anlık görüntülü VM'de tools/Invoke-Tests.ps1, sonra docs/WINDOWS_TEST_CHECKLIST.md. Yeni regresyon testinde Windows'ta junction oluşturulur, Linux'ta symlink kullanılır.

## Sıradaki işler — uygulanmış sayılmamalı
1. Pagefile CIM sağlayıcısı ve çoklu özel pagefile geri alma.
2. HAGS donanım yetenek/etkin durum sorgusu; MSI tek aygıt seçimi.
3. NIC kimlikle hedefleme, toplu uygulama ve tek yeniden başlatma.
4. SPI kullanıcı ayarları, hibernation ayrıntılı yedeği, CFG geri alma çakışmaları.
5. Windows Update tercihlerinin ayrıştırılması, yönetilen cihaz kontrolleri.
6. UI tasarımı ve gerçek Windows doğrulaması.

Bu paket ilk uygulanmış dilimdir; 70 ayarlık incelemenin tamamının kod karşılığı değildir.

# r3 bağımsız denetim — 1 Ekim 2026

Kaynak: `LivnTools_v4_Test_20261001.zip` (paket notu: 7fe4439, `dev/r3-tweak-review`). ZIP Git geçmişi içermiyordu;
denetim yerel bir temel commit üzerinde yapıldı. Push, merge, tag ve yayın yapılmadı.

## Doğrulanmış hatalar ve düzeltmeler

| # | Dosya / fonksiyon | Yeniden üretilebilir senaryo | Düzeltme | Regresyon testi |
|---|---|---|---|---|
| 1 | `Core/Common.ps1` `Write-LtFileAtomic` | PowerShell `$null` değerini .NET `string` parametresine `""` olarak geçirir; `[IO.File]::Replace($tmp, $Path, $null)` her çağrıda "path boş olamaz" hatası verir ve kod her zaman atomik olmayan yola düşer. Bu yolda ikinci taşıma başarısız olursa (AV kilidi, kesinti) `ledger.json` yok olur, `.bak` okunmaz; özgün değerler sessizce "kayıt yok" görünür. Linux PS 7.4.6'da yeniden üretildi (ikinci `Move-Item` hatası → ledger 1 → 0 kayıt). | `[NullString]::Value`; geri dönüş yolunda hata olursa özgün dosya geri konur; `Read-LtLedger` yarım kalmış `.bak` dosyasını geri alır. | `Reliability.Tests.ps1` (3 test) |
| 2 | `Engine.ps1` `Invoke-LtTweakApply` | Çok eylemli ayarda ikinci eylemin journal satırı yazılamazsa (disk dolu) hata bloğundaki `failed` kaydı da istisna atar; geri sarma hiç çalışmaz. Birinci eylem sistemde kalır, sonuç yalnız "Beklenmeyen hata: Disk dolu" olur (`priv.activity-off` ile yeniden üretildi). | Hata bloğunda kayıt yazımları ayrı korunur; geri sarma her zaman çalışır, hiç uygulanmamış eylem için yazma yapılmaz; kayıt hatası "Kayıt uyarısı" olarak ayrıca raporlanır. | `Reliability.Tests.ps1` (2 test) |
| 4 | `Cleanup.ps1` `Invoke-LtCleanup`, DISM/SFC/USB Run blokları; `UI/App.ps1` sonuç başlığı | Kullanıcının Windows 10 çalıştırması (1 Ekim 10:07): 6 Gelişmiş Temizlik işlemi çıkış kodu 0 ile tamamlandı, özet "toplam 0 B silindi" dedi. DISM/SFC/USB adımları açılan alanı hiç ölçmüyor, sabit `Bytes = 0` döndürüyordu; özet bunları toplayarak ölçülmemiş değeri 0 B olarak gösteriyordu. Disk Temizleme 2 saniyede bitti ve boş alan artışı ölçmedi (Hızlı Temizlik ve /ResetBase önceden çalıştığı için kalan öğe olmaması olası). | Sonuçlara `SizeMeasured`; yalnız dosya silme ve ölçüm bildiren adımlar toplanır, diğerleri "ölçülmedi" diye ayrıca sayılır; Disk Temizleme farkı yoksa bunu açıkça yazar. | `Reliability.Tests.ps1` (4 test, kullanıcı senaryosu dahil) |
| 3 | Testler (`Engine`, `ExternalTools`) | Paket `_Files` içermediği için 3 test dağıtılmayan Bitsum `.pow` / ISLC ikililerine bağlı kalıp başarısız oluyordu (başlangıç ölçümü 323/3). Ürün hatası değil, test bağımlılığı. | Yer tutucu fikstür (`New-LtThirdPartyFixture`): sürüm bilgisi taşıyan boş derleme, çalıştırılmaz. | Mevcut 3 test |

## İncelenen davranış (hata olarak değil, açıklık için düzeltildi)

- **Uygulamadan sonra değer değişirse "Önceki ayara dön":** kullanıcı veya başka yazılım Livn'in yazdığı değeri değiştirdikten sonra geri alma, yeni değeri sessizce özgün değerle eziyordu; önizleme farkı göstermiyordu (`game.mode`: 1 uygulandı → başka program 7 yazdı → önizleme yalnız "7 → yok"). Önizleme artık bu satırları `[Livn uyguladıktan sonra değişmiş]` olarak işaretler ve uyarı gösterir. CFG için mevcut çakışma reddi korunur. Diğer sağlayıcılar için otomatik reddetme eklenmedi; karar onay penceresinde kullanıcıdadır.
- **Kullanıcı ayarı yedeklerinin sahipliği:** HKCU yedekleri SID taşır; farklı/eski kimlikli kayıt geri yükleme, ledger birleştirme ve kurtarmada reddedilir (mevcut testler). Bu turda yeni açık bulunmadı.
- **DryRun kaçışı:** Yeni envanter ve önizleme kodu dahil `src/` yapısal kuralı geçiyor; Memory modunda winget çalıştırılmaz, önizleme gerçek dosya sistemini taramaz.
- **Temizlik yol sınırları:** Silme anında her dosya ve üst dizinleri için reparse/yol kontrolü mevcut. Önizleme aynı kuralları kullanır; önizleme ile silme arasında hedef bağlantıya çevrilirse silme reddedilir (test edildi). Bu, eşzamanlı başka süreçlere karşı atomik güvence değildir.
- **Yerelleştirme / PS 5.1:** Karar veren kod GUID, CIM ve registry okur; komut metni yalnız günlük içindir. `[NullString]` PS 3+ ile uyumludur. Windows PowerShell 5.1'de bu turun kodu çalıştırılmadı.

## Eklenen özellikler

- **Format Sonrası uygulama envanteri:** Kurulu / Kurulu değil / Durum okunamadı. WinGet yokluğu veya sorgu hatası "kurulu değil" sayılmaz. Ayrı salt okunur runspace'te, en fazla 10 dakikada bir otomatik, elle en sık 30 saniyede bir. Arka plan envanteri kaynak sözleşmesini kullanıcı adına kabul etmez. Kurulum davranışı (exact ID, `winget` kaynağı, `--no-upgrade`, kurulum anında yeniden denetim) değişmedi.
- **Temizlik önizlemesi:** Dosya sayısı ve tahmini boyut, hedef ve kapsam, korunan veri, taranamayan / sınır dışı alanlar. Uygulama kapatmaz, bakım komutu çalıştırmaz, dosya değiştirmez. Boyutu güvenilir hesaplanamayan bakım işlemleri için sayı gösterilmez. EA / Battle.net / Xbox taranmaz.


## Kullanıcı geri bildirimi turu — 1 Ekim 2026 (2)

| Bildirilen | Neden | Değişiklik | Test |
|---|---|---|---|
| Hazır seçimler 2–3 ayar işaretliyor, etkisiz görünüyor | Hazır seçimler gerçekten 2–4 kimlikten oluşuyordu | Genişletildi, Maksimum performans eklendi, atlananlar nedenleriyle gösteriliyor | `PresetsDevices`, `ReviewR3` politika testleri |
| Bitsum/Hybred "Plan dosyası bulunamadı" | Paket `_Files` içermiyordu | Üç `.pow` geri kondu, SHA-256 sabitlendi (destek + içe aktarma anı) | `PresetsDevices` (eşleşme, değiştirilmiş dosya, içe aktarma anı, uygula/geri al) |
| GPU/MSI seçenekleri aygıt seçilse de kapalı; kimlik görünüyor | Önceki tur yazımı tamamen kapatmıştı; seçim bağlama aktarılmıyordu | Seçim `SelectedMsiInstanceId`; MSI donanım yeteneğine, HAGS sürücü sorgusuna bağlı; etiketlerde kimlik yok | `PresetsDevices`, `GraphicsSafety` |
| Brave kurulu ama "Kurulu değil" | `winget export` yalnız eşleştirilen paketleri listeler | Windows Uninstall adlarıyla tamamlama, "Kurulu (WinGet dışı)" | `SetupInventory`, `Setup` |

Güvenlik azaltmaları, MSI, Windows Update ve pagefile hazır seçimlere girmez. MSI yüksek riskli ve tek aygıtla sınırlıdır. Lisans durumu açık olan `.pow` dosyaları ağdan kurulum bildirimine eklenmedi.

## Uyumluluk denetimi — 2 Ekim 2026

| Öncelik | Bulgu | Durum |
|---|---|---|
| Yüksek | `net.ackfreq` `{{GUID}}` anahtarına yazıyor, doğrulama aynı yanlış anahtarı okuduğu için başarılı görünüyor | Düzeltildi + regresyon testi |
| Yüksek | 32-bit PowerShell'den açılınca bcdedit/DISM/SFC çalışmaz | 64-bit 5.1'e yeniden başlatma, başlatıcılar Sysnative |
| Orta | PowerShell 7 / ISE kabuğu | Yeniden başlatma; kurulum sonrası başlatma da 5.1 |
| Orta | İlke engellerinde sessiz kapanma | Başlatıcı ön kontrolü + Main.ps1 CLM kontrolü |
| Orta | Explorer/uygulama kapatma tüm oturumlarda; yükseltilmiş Explorer | Oturum filtresi; Winlogon / düşük güven düzeyi |
| Orta | Farklı yönetici hesabıyla yanlış profil temizliği ve kullanıcının uygulamalarını kapatma | Kullanıcı kapsamlı öğeler atlanır |
| Orta | Belgeler'de kurulum (CFA / OneDrive) | LocalAppData + mevcut kurulum yerinde |
| Orta | UCPD korumalı TaskbarDa | NotSupported + ilke seçeneği |
| Orta | Boş Geri Dönüşüm Kutusu hata sayılabilir | Sayım + hata sonrası doğrulama |
| Orta | `pause` içeren betik bir saat kilitler, iptal yok | stdin kapalı, iptal ağacı sonlandırır |
| Düşük | Kod sayfası, betik kodlaması, `..` alt dizgi, Masaüstü yönlendirmesi, OneDrive makine geneli, yükseltilmiş tarayıcı, sondaki `\`, Modern Bekleme, performans sayaçları | Düzeltildi |
| Düşük | UI iş parçacığında kullanılabilirlik yoklaması | Açık |

## Kullanıcı gözüyle özellik turu — 2 Ekim 2026 (2)

Gerekçe ve kapsam: [KESKE_LISTESI.md](KESKE_LISTESI.md). Yeni yazma yolları yalnız motor üzerinden (önizleme, günlük, geri alma): DNS seçimi, başlangıç onay kayıtları, oyun GPU tercihi, arka plan kaydı. Diğer her şey salt okunur. Oyuncu modu politika testlerine (güvenlik/High/Unverified/svc/msi/wu yok) tabidir.
