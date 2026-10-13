<div align="center">

# ⚡ LivnTools

### Windows'u hazırla. Ayarlarını taşı. Kontrol sende kalsın.

Format öncesi kurtarma, format sonrası kurulum ve günlük bakım için<br>
**PowerShell + WPF tabanlı kişisel Windows araç kutusu.**

[![Release](https://img.shields.io/github/v/release/LiVNLOUD/livn-tools?color=8b5cf6&label=release)](https://github.com/LiVNLOUD/livn-tools/releases)
[![Windows validation](https://github.com/LiVNLOUD/livn-tools/actions/workflows/validate.yml/badge.svg?branch=main)](https://github.com/LiVNLOUD/livn-tools/actions/workflows/validate.yml)
![Platform](https://img.shields.io/badge/Windows-10%20%2F%2011-0078D4?logo=windows)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1-5391FE?logo=powershell&logoColor=white)

**[İndir](https://github.com/LiVNLOUD/livn-tools/releases/latest)** · **[Başlangıç](#başlangıç)** · **[Kullanım rehberi](docs/USAGE.md)** · **[Değişiklikler](CHANGELOG.md)**

</div>

---

## Tek araç, üç kullanım

| Formattan önce | Formattan sonra | Günlük kullanım |
| :--- | :--- | :--- |
| Ağ ve diğer donanım sürücülerini dışa aktar | Önce ağ sürücüsünü geri yükle | Sistem durumunu ve sorunları incele |
| Uygulama listesini ve taşınabilir seçimlerini kaydet | WinGet ile seçtiğin uygulamaları kur | Temizlenecek alanı silmeden önce gör |
| Livn kopyasını ve seçilen kayıtları USB'ye taşı | Ayarları yeni sistemde önizle ve uygula | Ayarları dene, önceki değerlerine dön |

**85 ayar tanımı · 45 temizlik/bakım işlemi · 40 uygulama · 9 kategori · 6 hazır seçim**

Sayılar katalog kapsamını gösterir; her seçenek her bilgisayarda kullanılabilir değildir. Desteklenmeyen seçeneklerde nedeni gösterilir.

## Başlangıç

### ZIP ile kullan

1. [Son sürümden](https://github.com/LiVNLOUD/livn-tools/releases/latest) **`LivnTools-4.0.0.zip`** dosyasını indir.
2. ZIP'i ayrı bir klasöre çıkar. ZIP içinden çalıştırma.
3. **`LivnTools.bat`** dosyasını aç ve yönetici isteğini onayla.
4. Sistem Kontrolü'nü incele; istediğin işlemleri seç ve **önizlemeyi kontrol ederek** uygula.

Uygulamayı açmak tek başına tweak uygulamaz. Standart ZIP çalışma dosyalarını içerir; geliştirici testleri ve araçları için kaynak depoyu indir.

### PowerShell ile kur

```powershell
irm https://raw.githubusercontent.com/LiVNLOUD/livn-tools/v4.0.0/win.ps1 | iex
```

Kurucu sürüme sabit dosyaları indirir; boyut ve SHA-256 doğrulanmadan mevcut kurulumu değiştirmez.

| Konum | İçerik |
| :--- | :--- |
| `%LOCALAPPDATA%\LivnTools\app` | Kurulan uygulama |
| `%LOCALAPPDATA%\LivnTools\data` | Günlükler, yedekler ve geri alma kayıtları |
| ZIP kullanırken `<klasör>\data` | Taşınabilir kullanım verileri |

Güncelleme kullanıcı verilerini silmez. Önceki uygulama `app.prev` olarak saklanır. Önceki kuruluma dönmek için:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/LiVNLOUD/livn-tools/v4.0.0/win.ps1))) -Rollback
```

> SHA-256 indirme bütünlüğünü denetler; yayıncı imzası değildir. `livn.tr/win` ayrı bir yönlendirmedir. Bu sürüm için yukarıdaki GitHub adresi esas alınır.

### Sisteme dokunmadan dene

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -STA -File .\Main.ps1 -DryRun
```

DryRun bellek içindeki örnek sistemle açılır: gerçek ayarlar değiştirilmez, dosyalar temizlenmez, uygulamalar kurulmaz. Kaynak pakette **`Test-Arayuz.bat`** aynı amaçla kullanılabilir.

## Neler var?

| Alan | Yapabileceklerin |
| :--- | :--- |
| **Sistem Kontrolü** | Sürücü, RAM, disk, yenileme hızı, hata kayıtları ve yeniden başlatma durumunu incele |
| **Kurtarma Kiti** | Sürücüleri, uygulama listesini, Livn kopyasını ve seçilen kayıtları başka diske taşı |
| **Format Sonrası** | Uygulamalarda ara, kurulum durumunu gör, seçimlerini profile kaydet ve yükle |
| **Temizlik ve bakım** | Dosya/alan önizlemesi, desteklenen önbellekler, DISM ve SFC araçları |
| **Performans ve GPU** | Güç planları, oyun tercihleri, donanıma bağlı GPU/MSI ayarları |
| **Ağ** | Ping, dalgalanma, paket kaybı, DNS ölçümü ve seçilen adaptör ayarları |
| **Windows ve gizlilik** | Görünüm, Explorer, oturum tercihleri ve desteklenen gizlilik ayarları |
| **Başlangıç ve geçmiş** | Başlangıç uygulamalarını yönet, ayarları ve geri alma kayıtlarını incele |

**Hazır seçimler:** Oyuncu modu, Temel, Gizlilik, Görünüm, Akıcı görünüm ve Maksimum performans. Bunlar seçim yapar; uygulamadan önce önizleme gösterilir. Güvenliği azaltan ayarlar hazır seçimlere dahil değildir.

## Değişiklikleri nasıl yönetir?

- **Önce gör:** Mevcut değer, hedef değer, risk ve yeniden başlatma gereksinimi gösterilir.
- **Önceki değeri sakla:** Uygulamadan önce ayar durumu diske kaydedilir.
- **Yeniden oku:** İşlem sonrası durum denetlenir; hata ve kısmi sonuçlar ayrı raporlanır.
- **Geri dön:** “Önceki ayara dön” kendi değerini; “Windows varsayılanı” katalogdaki varsayılanı kullanır.

Temizlik, kurulum/kaldırma, sürücü kurulumu ve kullanıcı betikleri ayar geri alma sistemi kapsamında değildir. Birden çok ayarın uygulanması tek bir atomik işlem değildir. [Geri alma kapsamı →](docs/SUPPORT_MATRIX.md#geri-alma-kapsamı)

## v4.0.0 ile gelenler

- Modüler motor, işlem günlüğü ve durum doğrulaması.
- Format öncesi kurtarma kiti ve format sonrası uygulama/profil akışı.
- Eksik kopya ve iptal durumlarını doğru gösteren kit sonuçları.
- IPv4/IPv6 DNS tercihlerini ayrı saklayan geri alma.
- Temizlik önizlemesi, kurulu uygulama envanteri ve hedef aygıt seçimi.
- Sürüme sabit, SHA-256 denetimli kurulum ve otomatik yayın paketi.

## Gereksinimler ve kapsam

- **Windows 10 22H2 / Windows 11, x64** hedeflenir.
- **Windows PowerShell 5.1** ve gerçek işlemler için yönetici yetkisi gerekir.
- Uygulama kurulumu için **WinGet** gerekir; otomatik WinGet kurulumu yapılmaz.
- PowerShell 7 veya 32 bit kabuktan açılışta uygun Windows PowerShell kabuğuna geçilir.

Kurtarma kiti tam disk imajı değildir. Belgeler, fotoğraflar, tarayıcı verileri ve lisans anahtarları ayrıca yedeklenmelidir. Wi-Fi dışa aktarımı seçilirse parolalar kitte düz metin saklanır. Oyun kayıt kapsamı `Saved Games` ve `Belgeler/My Games` ile sınırlıdır.

ISLC ve üçüncü taraf güç planları standart yayın ZIP'ine dahil değildir. Kurulu planlar seçilebilir; üretici bağlantıları arayüzdedir. [Üçüncü taraf kapsamı →](docs/THIRD_PARTY.md)

## Geliştirme ve doğrulama

```powershell
# Pester 5.6.1 ve PSScriptAnalyzer 1.23.0 ile
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Invoke-Tests.ps1

# Windows PowerShell 5.1 / WPF; sistem ayarı uygulamaz
powershell -NoProfile -STA -File .\tools\Invoke-WindowsCheck.ps1

# Dağıtım ZIP'i
powershell -NoProfile -File .\tools\Build-Release.ps1 -Version 4.0.0 -Zip
```

Linux kontrolünde **518 test geçti**, statik analiz **0 hata / 0 uyarı** verdi. Windows PowerShell 5.1, WPF ve paket bütünlüğü GitHub Actions üzerinden ayrıca denetlenir; güncel sonuç üstteki rozetten açılır. Otomatik testler gerçek donanımda bütün ayarların etkisini veya performans artışını kanıtlamaz.

| Belge | İçerik |
| :--- | :--- |
| [Kullanım rehberi](docs/USAGE.md) | Ekranlar, hazır seçimler, profiller ve işlem sınırları |
| [Mimari](docs/ARCHITECTURE.md) | Motor, sağlayıcılar, arayüz ve veri akışı |
| [Destek matrisi](docs/SUPPORT_MATRIX.md) | Platform, donanım ve geri alma koşulları |
| [Windows kontrol listesi](docs/WINDOWS_TEST_CHECKLIST.md) | Görsel ve gerçek sistem kabul adımları |
| [Geliştirme kaydı](docs/DEVELOPMENT_STATUS.md) | Son düzeltmeler ve doğrulama sınırları |

---

<div align="center">

**LiVNLOUD / LivnTools**<br>
Kişisel kullanım için geliştirildi. Ölçülmemiş FPS veya gecikme kazancı vaat etmez.

</div>
