# LivnTools — 13 Ekim 2026 geliştirme durumu

Temel: `LivnTools_v4_Test_20261002_r3-7.zip` (SHA-256 `671793f7444512349e2aa9342fe6b1f00146c48b0c08125c52edd7be63d0f3a6`). Eski GitHub kodu geliştirme temeli değildir. Bu çalışma 4.0.0 geliştirme sürümüdür; kararlı sürüm etiketi oluşturulmadı.

## Bu tur

Kurtarma kitinin kopyalama hatası ve iptal sonucu düzeltilmiştir. Başarı yalnız tamamlanan bölümler için raporlanır. Zorunlu başlatıcı, modül ve arayüz dosyaları kaynakta ve hedefte denetlenir. Eksik kaynağın sıfır dosyayla başarılı sayılması, iç içe klasöre sonsuz kopya ve bağlantı noktası üzerinden dosya taşıma engellenir. Kit manifesti, metin yönergesi ve arayüz sonuçları eşleşir.

DNS snapshot yeni kayıtlarda IPv4 ve IPv6 için ayrı otomatik/statik durum içerir. Restore adres ailesine ait CIM nesnesi üzerinden yapılır. Önceki sürümlerin tek bayraklı kayıtları okunmaya devam eder; eski kayıtta hiç saklanmamış aile ayrımı sonradan bulunamaz.

Paketleme mevcut olmayan LICENSE yüzünden durmaz ve proje adına lisans seçmez. Dosya varsa olduğu gibi dahil edilir. Varsayılan dağıtım üçüncü taraf ikililerini/güç planlarını dışarıda tutar. CheckOnly manifestin gerçekten güncel olmasını denetler.

## Doğrulama

Linux PowerShell 7.4.6 / Pester 5.6.1 ile 518/518 test geçti (0 atlandı; 74,96 saniye). Parser 57 dosyada hatasız; PSScriptAnalyzer 1.23.0 ile 26 ürün/araç dosyasında 0 hata, 0 uyarı. Önceki taban 505 testti; 13 regresyon senaryosu eklendi. Testler Memory backend kullanır. Test ortamında PowerShell telemetrisi kapalıdır. Windows sonuçları GitHub Actions üzerinde ayrıca raporlanır.

Windows iş akışı Windows PowerShell 5.1 altında Pester/statik analiz ile gerçek WPF nesne ve şablon oluşturmayı çalıştırır. Hiçbir tweak uygulamaz. Gerçek Windows 10/11 donanımında DNS değişimi/geri alma, sürücü dışa aktarma, USB iptal ve disk dolması, görünür WPF/DPI kabulü ayrıca gereklidir. CI başarısı bunları kanıtlamaz.

## Sonraki kabul

1. Test-Windows.bat ile gerçek Windows makinesinde WPF temel kontrolü.
2. DryRun kitte iptal ve eksik kaynak mesajlarının görsel kontrolü.
3. Gerçek USB üzerinde sürücü/oyun kaydı kopyası, disk dolması ve iptal.
4. IPv4 statik / IPv6 otomatik ve tersinin kontrollü uygulanıp geri alınması.
5. Kabulden sonra sürüm numarası, manifest, tag ve GitHub Release.

DNS API kaynakları: [Get-DnsClientServerAddress](https://learn.microsoft.com/en-us/powershell/module/dnsclient/get-dnsclientserveraddress), [Set-DnsClientServerAddress](https://learn.microsoft.com/en-us/powershell/module/dnsclient/set-dnsclientserveraddress).
