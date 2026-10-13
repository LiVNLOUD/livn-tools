# v3.5 denetimi — bulgular (Faz 1)

İncelenen sürüm: `main` @ a67902d (3 Mart 2026). Kullanıcının ZIP'i (LivnTools_v3.5.zip)
bu geçmişteki daha eski commit'lerle birebir aynıdır (Main.ps1 = 167b65c, win.ps1 = 84f0a10).
Aşağıdaki satır numaraları v3.5 `Main.ps1` (5.746 satır) içindir.

## 1. Sahte başarı ve hata bastırma (kritik)

| Yer | Sorun |
|---|---|
| `Invoke-Async` (≈2383–2537) | Runspace'in hata akışı hiç okunmuyor; yalnızca `EndInvoke` istisnası loglanıyor. Her iş sonunda koşulsuz "=== … TAMAMLANDI ===" ve yeşil "Tamamlandi!" gösteriliyor. |
| Tüm sayfa işleyicileri | `Set-ItemProperty/Set-Service/Stop-Service … -ErrorAction SilentlyContinue` ardından koşulsuz `Write-Log … 'OK'`. Erişim reddi, olmayan servis, yanlış tür → yine "OK". |
| bcdedit/netsh/powercfg/wevtutil/reg | `2>&1 | Out-Null`; `$LASTEXITCODE` hiç denetlenmiyor (tek istisna olay günlüğü boyutu). |
| `Ensure-RestorePoint` (2367) | `Checkpoint-Computer -ErrorAction SilentlyContinue` → her durumda "oluşturuldu". 24 saat sınırında Windows yeni nokta oluşturmaz, yalnızca uyarı verir. `Enable-ComputerRestore` kullanıcıya sormadan açılıyor. |
| `Backup-Registry` (2116) | `reg export … 2>$null` sonucu denetlenmeden "Yedek alindi". |
| Geri Dön (5119) | `reg import` sonucu denetlenmiyor; `try/catch` yerel komut hatasını yakalamaz. |
| Temizlik `Remove-SafeFolder` (2777) | Bayt silmeden ÖNCE toplanıyor, `Remove-Item -ErrorAction SilentlyContinue` → kilitli dosyalar da "temizlendi" sayılıyor. |
| DISM/SFC (3150–3214) | Çıkış kodları yok sayılıyor; SFC sonucu İngilizce metinle ayrıştırılıyor (Türkçe Windows'ta özet hiç çıkmıyor). |
| `[Environment]::TickCount64` (2317) | .NET Framework 4.x'te (PS 5.1) yok → uptime hiçbir zaman gösterilmiyor (hata sessizce yutuluyor). |

## 2. Yanlış veya etkisiz uygulanan ayarlar

Ayrıntı ve kaynaklar: [TWEAK_AUDIT.md](TWEAK_AUDIT.md). Özet:

- **MSI modu** sürücü sınıf anahtarına yazılıyor (etkisiz); **CFG** yanlış bit (0x200 = ForceRelocateImages);
  **SystemResponsiveness=0** Microsoft'a göre 20'ye sabitleniyor (etkisiz); **NVIDIA "V-Sync"** aslında `PerfLevelSrc`;
  **DMA Protection** var olmayan değer; **PageFile** diğer sürücülerdeki sayfa dosyalarını siliyor;
  **Win32Prio** `ControlSet001`'e de yazıyor; **Nagle/TCPNoDelay** etiketleri karışık ve tüm arayüzlere yazılıyor.
- `bcdedit /enum {current}` tırnaksız: PowerShell `{current}`'i betik bloğu olarak ayrıştırır → komut yanlış argümanla çalışır.

## 3. Tekrarlı uygulama

- Her güç planı tıklaması `.pow` dosyasını yeniden içe aktarıyor / Ultimate şablonunu yeniden kopyalıyor → yinelenen planlar.
- "Ultimate" etkinleştirmesi `powercfg /list` çıktısındaki SON GUID'i alıyor (yanlış planı seçebilir).
- ISLC her uygulamada yeniden başlatılıyor, doğrulanmamış bir `ISLC.ini` yazılıyor.

## 4. Yerelleştirme bağımlılığı

İngilizce metin regex'leri: `netsh int tcp show global` ("Receive Window Auto-Tuning Level"),
`powercfg /getactivescheme` ("Power Scheme GUID"), `bcdedit` değerleri ("Yes"/"No"),
SFC sonucu ("did not find…"), NIC `DisplayName` ("Flow Control", "Green Ethernet").
Türkçe Windows'ta durum taraması yanlış, bazı ayarlar hiç uygulanmıyor.

## 5. Durum ile seçim karışıklığı

Açılışta "zaten uygulanmış" ayarların onay kutuları işaretleniyor ve metne "✓" ekleniyor;
kullanıcı neyin mevcut durum neyin kendi seçimi olduğunu ayıramıyor. Hızlı Temizlik'te kurulu
uygulamaların kutuları otomatik işaretleniyor.

## 6. Güvenlik ve veri kaybı riskleri

- VBS/HVCI/Spectre/CFG tek tık; ek onay yok.
- USB geçmişi: `MountedDevices` içindeki D–Z sürücü harfi kayıtları siliniyor, System olay günlüğü temizleniyor.
- Spotify `Data` (çevrimdışı şarkılar), WhatsApp/Teams/Skype paket `LocalCache` kökleri siliniyor.
- Açık uygulama kapatma: `Launcher`, `Agent` gibi genel süreç adları başka programları kapatabilir.
- Betik Çalıştır: .bat/.cmd içeriği PowerShell betik bloğu olarak çalıştırılıyor.

## 7. Mimari ve bakım

- Tek dosya, 5.746 satır; her ayar üç yerde kopya (sayfa butonu, "Apply All", durum taraması). Kopyalar birbirinden sapmış
  (ör. Apply All'da HPET "zaten" kontrolü yok, sayfa butonunda var; Bing arama tarama/uygulama farklı değerlere bakıyor).
- Tüm başlangıç işleri (donanım WMI sorguları, uygulama tespiti, NIC/netsh/bcdedit durum taraması, klasör boyutu tahmini)
  UI iş parçacığında → açılışta ve "Temizliği Başlat"ta donma. Tahmin için Chrome "User Data" tamamı özyinelemeli tarandı.
- Arka plan kodu `Dispatcher.Invoke` ile UI'ya yazıyor; `$using:` → `$` metin değiştirme ile betik bloğu yeniden oluşturuluyor.
- `AllowsTransparency=True` + `WindowStyle=None`: donanım hızlandırma kapalı, pencere kenarlarından boyutlandırma yok.

## 8. Kurulum (win.ps1)

- `main` dalından sürümsüz indirme; dosya varlığı indirme başarısı sayılıyor (yarım/boş dosya kabul).
- Doğrudan kurulum klasörüne yazma: yarıda kalırsa karışık sürüm. Önceki sürüm saklanmıyor.
- Tüm hata/uyarı akışları global olarak susturuluyor.
- Dosya UTF-8 BOM'suz ve ASCII dışı karakter içeriyor (PS 5.1 `-File` ile bozuk karakter).

## 9. README ile gerçek davranış farkları

| README | Gerçek (v3.5) |
|---|---|
| "Geri Dön: Uygulanan tüm değişiklikleri geri al" | Seçilen tek bir .reg dosyasını içe aktarır; yeni oluşturulan değerleri silmez; servis/BCD/ağ/güç planı kapsanmaz. |
| "Backup sistemi… Uygula'dan önce yedek" | Otomatik yedek yalnızca birkaç anahtar; manuel yedek de sınırlı anahtar listesi. |
| "Timer Resolution 0.5ms" | Çözünürlüğü ayarlamaz; `GlobalTimerResolutionRequests` yalnızca Win11'de global isteği etkinleştirir. |
| "Congestion (CTCP)" | Kod CUBIC ayarlar. |
| `Win32Prio_*.reg` dosyaları özellik olarak listeleniyor | Kod bunları hiç kullanmıyor. |
| "License: MIT" rozeti | Depoda LICENSE dosyası yok. |
| "DMA Protection", NVIDIA/AMD ayarları | Etkisiz veya yanlış değerler (bkz. TWEAK_AUDIT). |

## 10. Başlangıç doğrulama durumu (değişiklikten önce)

- PSScriptAnalyzer 1.23 (Main.ps1 + win.ps1, Error+Warning): **216 bulgu, 0 Error**
  (118 PSAvoidGlobalVars, 44 PSAvoidUsingEmptyCatchBlock, 21 PSUseDeclaredVarsMoreThanAssignments,
  10 PSReviewUnusedParameter, 10 PSUseShouldProcess…, 1 PSUseBOMForUnicodeEncodedFile).
- Test yoktu.
