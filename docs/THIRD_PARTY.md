# Varsayılan dağıtım kapsamı

**1 Ekim 2026 güncellemesi:** Kullanıcının açık isteğiyle üç güç planı dosyası (`Bitsum-Highest-Performance.pow`, `HybredPowerPlans/HybredLowLatencyHighPerf.pow`, `HybredPowerPlans/HybredLowLatencyBalanced.pow`) kullanıcının kendi v3.5 paketinden kaynak projeye geri kondu. SHA-256 değerleri aşağıdaki tablodaki kayıtlarla birebir aynıdır ve kodda sabitlenmiştir: destek kontrolünde ve içe aktarma anında yeniden hesaplanır; eşleşmeyen dosya içe aktarılmaz. Web'den yeni veya "daha iyi" plan dosyası indirilmedi/eklenmedi. ISLC ikilisi geri konmadı.

Lisans/yeniden dağıtım izni **hâlâ doğrulanmadı**. Bu nedenle `Build-Release.ps1` varsayılanı ve `win.ps1` bildirimi `_Files` içermemeye devam eder; kaynak ZIP içerir. Yayın öncesi aşağıdaki karar maddeleri kapatılmalıdır.

Plan dosyaları yoksa Bitsum/Hybred içe aktarma seçenekleri gerekçesiyle desteklenmiyor görünür. Yeni kurulu plan seçimi dosya dağıtımı gerektirmez. ISLC uygulaması resmî paketten ayrıca seçilebilir. Windows yerleşik güç planları ile uygulamanın diğer işlevleri kullanılabilir.

Dağıtım kapsamı ayrıca kararlaştırılırsa `Build-Release.ps1 -IncludeThirdParty` dosyaları pakete katabilir. Bu seçenek izinlerin doğrulandığı anlamına gelmez. Aşağıdaki izin değerlendirmeleri açık kalmaktadır.

# Üçüncü taraf dosyalar

Depoda ve dağıtımda bulunan, Livn Tools'a ait olmayan dosyalar. Dağıtım izinleri
**bu denetimde doğrulanamadı**; aşağıdaki açık maddeler yayın öncesi proje sahibi
tarafından kapatılmalıdır.

| Dosya | Kaynak / sürüm | SHA-256 | Lisans / dağıtım izni |
|---|---|---|---|
| `_Files/Bitsum-Highest-Performance.pow` | Bitsum (ParkControl / Process Lasso ile dağıtılan güç planı dışa aktarımı). Depoya 2026-02-28'de eklendi; orijinal indirme kaynağı kayıtlı değil. | `f8bdd77720170e6521fa0ff533cda9e4da8342d16f858159e74e8216bc22a306` | **Belirsiz.** bitsum.com/bhp sayfasında üçüncü taraf dağıtımına dair ifade yok. |
| `_Files/HybredPowerPlans/HybredLowLatencyHighPerf.pow` | TheHybred güç planı. Kaynak depo/URL kayıtlı değil. | `5fa32b2853aa59140133c64458d112eab4eb3eddf31fe6e73c802cbdc8af7fc3` | **Belirsiz.** |
| `_Files/HybredPowerPlans/HybredLowLatencyBalanced.pow` | aynı | `1f0c1b3c17cb60a038486e02a849759106547169a4bd42f905ba7b6c639e16ad` | **Belirsiz.** |
| `_Files/ISLC/Intelligent standby list cleaner ISLC.exe` | Wagnardsoft ISLC **1.0.3.7** (dosya sürüm kaynağından). Güncel sürüm 1.0.4.8. İçinde Newtonsoft.Json 13.0.3 (MIT) gömülü. | `7dec67fe3bb34b605e6c2de69ddeeb5b2d2d968ee555ad6ef797dfd982063ed0` | **Belirsiz.** wagnardsoft.com ISLC sayfasında ve ReadMe'de lisans/yeniden dağıtım metni yok. |
| `_Files/ISLC/ReadMe_ISLC.txt` | Wagnardsoft | `6e8557e10a26bb94bc042a281463b78d0da8a810c69c6bc4f88bbb0359c52d97` | ISLC ile aynı |

Kaldırılanlar: `_Files/ISLC/…ISLC.pdb` (hata ayıklama sembolleri; çalışma için gerekmez)
ve `_Files/Win32Prio_*.reg` (kod tarafından hiç kullanılmıyordu).

## Livn Tools'un bağımlılığı

- Standby/modified liste temizliği artık ISLC GEREKTİRMEZ (yerel API). ISLC yalnızca
  "oturum açılışında ISLC'yi başlat" seçeneği için kullanılır; dosya yoksa seçenek
  gerekçesiyle "Desteklenmiyor" gösterilir.
- Güç planı dosyaları yoksa ilgili seçenekler "Desteklenmiyor" olur; diğer planlar
  (Dengeli, Yüksek Performans, Nihai Performans) Windows'un kendi şablonlarıdır.

## Önerilen karar (proje sahibi)

1. Bitsum, TheHybred ve Wagnardsoft'tan yeniden dağıtım izni alın veya
2. Dosyaları dağıtımdan çıkarıp kullanıcıya resmî indirme bağlantısı gösterin
   (Livn Tools dosya yoksa zaten "Desteklenmiyor" + neden gösterir; kod değişikliği gerekmez,
   yalnızca `tools/Build-Release.ps1` dahil listesinden `_Files` çıkarılır).


## İsteğe bağlı entegrasyon — 28 Eylül 2026

Performans sayfasında üretici bağlantıları, ISLC dosya seçimi ve kurulu güç planı listesi bulunur. Hiçbir araç sessizce indirilmez/kurulmaz; ticari özelliklerin lisansı üreticide kalır. Resmî sayfayı açmak da Memory modunda engellenir.

- **ISLC:** Resmî sürüm sayfası 1.0.4.8'i listeliyor. Kaynaktaki 1.0.3.7 dosyası değiştirilmedi ve varsayılan pakete eklenmedi. Kullanıcı paketi kalıcı bir klasöre çıkarıp asıl `Intelligent standby list cleaner ISLC.exe` dosyasını seçer. Dosya adı ve PE sürümü (1.0.3.7–1.0.4.8 aralığı) kontrol edilir; **bu özgünlük/imza doğrulaması değildir**. Seçim tek başına dosyayı çalıştırmaz veya görev oluşturmaz. Görev uygulandığında yol journal/ledger üzerinden kaydedilir; sonraki açılışta mevcut görevden bulunabilir.
- **Başlangıç profili:** Algılanan fiziksel RAM MB'sinin %10'u, 512–4096 MB sınırında serbest bellek eşiğidir. Liste eşiği 1024 MB, sorgulama aralığı 1000 ms. Bu Livn Tools'un sınırlı **sezgisel başlangıç seçimi**, üreticinin optimum tavsiyesi veya ölçülmüş performans kazanımı değildir. CPU/GPU modeline göre sahte parametre türetilmez. RAM okunamazsa işlem desteklenmez. CLI bayrakları kaynak paketteki üretici ReadMe'sinde belgeli; yeni 1.0.4.8 ikilisi/CLI davranışı Windows'ta ayrıca doğrulanmalıdır.
- ISLC config dosyasına yazılmaz; var olan timer ayarları devralınabilir. Timer'ın kapalı olduğu iddia edilmez. Kullanıcı ISLC içinde kontrol etmelidir. ISLC kapatılmış performans sayaçlarını açabilir (üretici ReadMe notu). Livn görevini geri almak çalışan ISLC'yi kapatmaz veya ISLC'nin kendi değişikliklerini geri almaz.
- **Bitsum / ParkControl:** BHP'yi üreticinin aracıyla kurup `Kurulu planları yenile` üzerinden seçin; ardından `Seçili kurulu güç planını etkinleştir` ayarını uygulayın. GUID esas alınır; yerelleştirilmiş isim yalnız görüntülenir. Önceki etkin plan geri alınabilir; planın iç ayarları değişmez. Üretici, Power Modes kullanan cihazlarda BHP'nin gerekli olmadığını belirtiyor. Windows güç modları düğmesi yalnız Ayarlar'ı açar; oradaki değişiklikler Livn günlüğüne girmez.
- **Process Lasso:** Resmî siteye erişim eklendi, otomatik yapılandırma/kurulum yapılmadı. ProBalance CPU rekabetinde arka plan süreçlerinin önceliğini geçici düşürür; her oyunda FPS artışı anlamına gelmez. Livn genel affinity, E-core veya X3D çekirdek kuralları dayatmaz. Otomatik güç planı değiştiren bir araç Livn'in seçimini sonradan değiştirebilir.
- **PresentMon:** Resmî kaynak bağlantısı bir önce/sonra ölçüm seçeneğidir, FPS artırıcı değildir; otomatik yakalama/sonuç analizi henüz yoktur.

Resmî kaynaklar: [ISLC 1.0.4.8](https://www.wagnardsoft.com/content/Download-Intelligent-standby-list-cleaner-ISLC-1048), [Bitsum Power Modes](https://bitsum.com/power/only-balanced/), [ProBalance](https://bitsum.com/apps/process-lasso/docs/algorithms/probalance/), [PresentMon](https://github.com/GameTechDev/PresentMon).

Açık kalanlar: ISLC forum/indirme erişimi bu ortamda 403; güncel paketin imza/hash kontrolüne dayalı otomatik indirilmesi eklenmedi. Windows'ta 1.0.4.8 CLI, görev çalışma dizini/config davranışı, gerçek geri alma, performans etkisi ve yeni WPF kontrolleri doğrulanmadı. Kaynak depodaki eski üçüncü taraf dosyalarının dağıtım izinleri hâlâ açık.
