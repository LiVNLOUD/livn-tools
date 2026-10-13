# Mimari

PowerShell 5.1 + WPF korunmuştur (framework değişikliği için somut gerekçe yok).
Tek dosyalık 5.746 satırlık yapı, sorumluluklarına göre ayrılmıştır:

```
Main.ps1                 Giriş: yetki (UAC), STA, veri klasörü, modül yükleme, -DryRun
LivnTools.bat            Başlatıcı (taşınabilir ve kurulum düzeninde çalışır)
win.ps1                  Kurulum/güncelleme (sürüme sabit, SHA-256, atomik değişim, geri dönüş)
src/
  LivnTools.psm1         Modül kökü (UI ve arka plan runspace'i ayrı ayrı yükler)
  Core/Common.ps1        Sonuç modeli (Success/AlreadyApplied/Skipped/NotSupported/Failed/Partial),
                         günlük (dosya + iş parçacığı güvenli kuyruk), harici komut çalıştırıcı
                         (çıkış kodu, zaman aşımı, süreç ağacı sonlandırma), yol korumaları,
                         kuru çalışma kapısı (Assert-LtLiveSystem / Assert-LtDeletePermitted)
  Core/SideEffects.ps1   Arka uç dışındaki TÜM yan etkili ilkeller (süreç kapatma, dosya silme,
                         Geri Dönüşüm Kutusu, araç başlatma, Explorer, kullanıcı betiği, .reg);
                         her biri önce kuru çalışma kapısından geçer
  Core/Backend.ps1       Sistem ilkelleri — iki arka uç: Windows (gerçek) ve Memory (test/kuru çalışma)
  Core/Providers.ps1     Eylem sağlayıcıları: Registry, Service, Bcd, PowerScheme, TcpGlobal,
                         NicProperty, EventLogSize, Mitigation, ScheduledTask, Hibernate
                         (her biri: Key, Capture, IsDesired, Apply, Restore, Default, Format)
  Core/Journal.ps1       journal (işlem başına JSONL, WriteThrough) + ledger (özgün değerler)
  Core/SystemInfo.ps1    Sistem bağlamı, yerel API (CPU/RAM/uptime, bellek listesi), geri yükleme noktası
  Core/Demo.ps1          Bellek arka ucu için gerçekçi sahte sistem
  Catalog/Tweaks.ps1     HER AYARIN TEK TANIMI + hazır seçimler
  Engine.ps1             Durum, önizleme, uygula/doğrula/geri sar, önceki ayar, Windows varsayılanı,
                         kurtarma, durum yedeği
  Cleanup.ps1            Geri alınamaz temizlik/bakım işlemleri
  UI/MainWindow.xaml     Ana pencere (WindowChrome, veri şablonları)
  UI/ViewModels.ps1      INotifyPropertyChanged görünüm modelleri (C# 5, Add-Type)
  UI/Dialogs.ps1         Önizleme/sonuç/onay pencereleri
  UI/App.ps1             Olay bağlama, arka plan iş hattı, sayfa mantığı
tests/                   Pester 5 (bellek arka ucu; gerçek sisteme dokunmaz)
tools/                   Invoke-Tests, Build-Release, Repair-Encoding
docs/                    Denetim, destek matrisi, üçüncü taraf, Windows test listesi
```

## Bir ayarın yaşam döngüsü

```
Katalog tanımı ──► Get-LtTweakStatus (salt okunur: her eylem için Capture + IsDesired)
                ──► Get-LtPlan (önizleme; hiçbir yazma yok — testle doğrulanır)
                ──► Invoke-LtApply
                      her ayar için:
                        1. tüm eylemlerin mevcut durumunu oku (hiç değişiklik yok)
                        2. hepsi hedefteyse → AlreadyApplied
                        3. her eylem: journal 'change' (önceki durum, diske zorla yazılır)
                                      ledger'a özgün değer (yoksa)
                                      Apply → yeniden oku → hedefte değilse HATA
                                      journal 'applied'
                        4. hata → bu ayarın yaptığı her şey ters sırada geri yüklenir ve doğrulanır
                      journal 'end'
```

- **Önceki ayara dön**: ledger'daki özgün değer (Livn Tools'un ilk dokunuşundan önceki hâl).
  Aynı ayar tekrar uygulansa bile özgün değer ezilmez.
- **Windows varsayılanı**: katalogdaki belgelenmiş varsayılan; tanımsızsa "Desteklenmiyor".
- **Kurtarma**: `end` kaydı olmayan journal = yarım işlem. Açılışta bant gösterilir; her hedef
  işlemdeki İLK "önceki" değerine döndürülür veya işlem "olduğu gibi bırakıldı" olarak kapatılır.

## Kuru çalışma (bellek arka ucu) yalıtımı

- `-DryRun` ve testler `Memory` arka ucunu kullanır. Bu modda:
  - Ayar sağlayıcıları sahte sisteme yazar (Backend.ps1'deki her ilkelin Memory dalı).
  - Temizlik öğeleri **simüle edilir**; `Paths`/`Run`/`Processes` hiç değerlendirilmez.
  - Harici komut, dosya silme, süreç kapatma, betik, .reg, Explorer → `Assert-LtLiveSystem`
    istisna fırlatır ve `Get-LtBlockedOperations`'a kaydeder. Koruma UI'da değil bu katmandadır.
  - Gerçek dosya silme yalnızca `Set-LtCleanupTestRoot` ile açıkça ayrılmış geçici `lt-*`
    klasöründe mümkündür (yalnızca testler).
- Kural testle zorunludur (`tests/DryRunIsolation.Tests.ps1`): `src/` altında yan etkili
  cmdlet/metot çağrıları yalnızca korumalı fonksiyonlarda bulunabilir.
- Salt okunur istisnalar: donanım çubuğu gerçek CPU/RAM/çalışma süresini gösterir (yazma yok).

## İş parçacıkları

- UI iş parçacığı yalnızca görünümü günceller. Sistem okuyan/yazan her iş tek bir kalıcı
  arka plan runspace'inde çalışır (modül bir kez yüklenir).
- Arka plan kodu UI'ya dokunmaz: günlük `ConcurrentQueue`'ya, ilerleme senkronize hashtable'a
  yazılır; UI bunları 150 ms'lik `DispatcherTimer` ile okur. `Dispatcher.Invoke` kullanılmaz.
- Aynı anda tek iş çalışır; durum yenilemeleri kuyruklanır. Modal pencere açıkken zamanlayıcı
  iş tamamlama işlemine yeniden girmez.
- İptal: yalnızca ayarlar/temizlik öğeleri ARASINDA değerlendirilir (yarım ayar bırakılmaz).
  Kullanıcı betikleri geri alma dışında olduğu için boru hattı durdurulabilir.
- İkincil iş yuvası (`Start-LtSideJob`): yalnız salt okunur işler için (şu an WinGet envanteri).
  Ayrı, kısa ömürlü runspace'te çalışır; ana iş kuyruğunu bloklamaz. Tek yuva vardır; sonuç
  aynı 150 ms zamanlayıcıyla toplanır. Uygulama kurulumu sürerken envanter başlatılmaz, bitince
  yenilenir.

## Veri klasörü

`<kök>\data` (kurulum) veya `<uygulama>\data` (taşınabilir), `LIVNTOOLS_DATA` ile değiştirilebilir:

```
data\journal\<işlem>.jsonl   değişiklik günlüğü (salt ekleme)
data\state\ledger.json       özgün değerler (atomik yazma: geçici dosya + File.Replace; Replace
                             yapılamazsa .bak ile değiştirme, hata olursa özgün dosya geri konur;
                             yarım kalmış .bak okunurken kurtarılır)
data\backups\*.json          "Durum yedeği al" çıktıları
data\logs\LivnTools_*.log    metin günlüğü
data\legacy-v3.5\            v3.5'ten taşınan .reg yedekleri ve loglar
```


## Format profili ve isteğe bağlı uygulamalar

`Setup.ps1` sürüm 1 JSON şemasını ve sabit uygulama kimliklerini doğrular. Profil istenen seçimlerden oluşur; journal/ledger, SID, komut, kurulum argümanı, kayıt defteri yolu ve donanım hedefi içeremez. İçe aktarma uygulama başlatmaz. Ayarlar mevcut Engine üzerinden yeniden önizlenir; yeni sistemin özgün değerleri saklanır. Kurulum/kaldırma ayrı sonuç listesi ve onay kullanır; geri alma vaadi yoktur.

Sistem yan etkileri `SideEffects.ps1` içindedir. WinGet envanteri kısa ömürlü JSON dosyasıyla okunur ve finally'de temizlenir. Kurulu paket atlanır; başarılı exit code sonrası envanter yeniden kontrol edilir. Format Sonrası envanteri (`Get-LtSetupInventory`) aynı export'u kaynak sözleşmesi kabul etmeden okur; durumlar Installed / NotInstalled / Unknown'dır ve okuma hatası hiçbir zaman NotInstalled sayılmaz. Appx kaldırma exact allowlist ve mevcut kullanıcı kapsamındadır; framework/resource/non-removable paketler reddedilir. Tüm doğrudan ilkellerde Memory koruması vardır; SetupBatch Memory'de ilkellere ulaşmadan simüle eder. WinGet kurulum işlemleri yalnız kullanıcı onayından sonra başlar; salt okunur envanter (`winget export`) Format Sonrası sayfası açıldığında en fazla 10 dakikada bir veya kullanıcı isteğiyle çalışır ve kaynak dizinini güncellemek için ağa erişebilir.

VisualEffects beş SPI boolean'ını tek eylem olarak yakalar. Geri alma etkin değerleri API ile kalıcı geri yazar. Paylaşılan UserPreferencesMask'ın tamamını kopyalamaz; başka tercihlerin bitlerini eski bir maskeyle ezmez. Bu eylem için registry değerinin önceki var/yok durumu ve ikili biçimi birebir geri yükleme iddiası yoktur; semantik beş tercih geri alınır.

Launcher temizliğinde RequireClosed yardımcı/arka plan süreçlerini de denetler. CloseApps bu kuralı geçersiz kılamaz. OlderThanDays=7 kullanan log hedefleri UTC son yazım zamanına göre süzülür. Filtre yalnız görünümü etkiler; silme yetkisi ve yol/junction korumaları motordadır.

## Temizlik önizlemesi

`Get-LtCleanupPreview` → `Get-LtCleanupItemPreview` → `Measure-LtFolderContents`. Ölçüm, `Remove-LtFolderContents` ile aynı filtre/alt klasör/yaş kurallarını ve `Get-LtDeleteScopeIssue` üzerinden aynı yol ve bağlantı sınırlarını kullanır; hiçbir dosyayı değiştirmez. Run blokları (bakım komutları) çalıştırılmaz; dosya hedefi bilinen bakım öğeleri için katalogda isteğe bağlı `PreviewPaths` vardır (Windows Update indirme önbelleği, yazı tipi önbelleği, MEMORY.DMP). Silme sırasında hedefler yeniden numaralandırılır ve her dosya için `Assert-LtDeletePermitted` tekrar çalışır; önizleme sonucu silmeye girdi olarak verilmez. Memory modunda (test kökü yoksa) önizleme gerçek dosya sistemini taramaz.

