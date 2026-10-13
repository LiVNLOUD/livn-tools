# Pagefile sağlayıcısı — geliştirme kontrol noktası

Temel: r3 / 7aefb5b. Push, tag ve sürüm yayını yapılmadı.

## Yapılan değişiklik
`mem.pagefile-auto` artık Registry yerine Pagefile sağlayıcısını kullanır. Uygulama yalnızca Win32_ComputerSystem.AutomaticManagedPagefile=True yazar. Yedek, otomatik yönetim bayrağını, tüm Win32_PageFileSetting ad/başlangıç/azami boyut kayıtlarını ve PagingFiles registry değerinin varlık/tür/veri bilgisini içerir.

Geri alma otomatik yönetimi geçici kapatır, kayıtları dosya adına göre uzlaştırır, eski bayrağı ve ham kaydı geri yükler. Sonrasında motor bayrak, bütün boyutlar ve ham kaydı karşılaştırır. Geri alma tamamlanamazsa hata ve ledger kaydı korunur. Bu bir atomik Windows işlemi değildir; yarım kalma journal/kurtarma akışıyla ele alınır.

Anlık çalışan pagefile boyutunu değiştirdiği iddia edilmez. Arayüz detayları yapılandırmayı gösterir; yeniden başlatma gereksinimi korunur. Evrensel Windows varsayılanı tanımlanmadı; önceki ayara dönüş vardır. Hazır seçimlere eklenmedi.

Eski Registry tabanlı `mem.pagefile-auto` ledger kaydı varken yeni uygulama engellenir. Değişiklik Geçmişi / Önceki ayara dön ile eski kayıt geri alınabilir. Eski kayıtta bulunmayan otomatik yönetim bilgisi tahmin edilmez.

## Testler ve sınırlamalar
10 Pester regresyon testi eklendi: çoklu disk/özel boyut geri alma; tekrar uygulama; zaten otomatik; sessiz yazma hatası; kısmi uygulama hatası; geri alma hatasında ledger; olmayan registry değeri; eski kayıt geçişi; varsayılan/preset sınırı; tek disk boyutu farkı.

Bu ortamda PowerShell yok. Pester, PSScriptAnalyzer, Windows 5.1 ve gerçek CIM sağlayıcısı ÇALIŞTIRILMADI. r2 test sonuçları bu paket için geçerli sayılmaz. CIM yazma/silme komutları DryRun yapısal koruma taramasına eklendi. Memory dalı gerçek CIM çağrısı yapmaz.

Yapılan statik doğrulama: git diff --check; XAML XML; UTF-8 BOM/ASCII kuralları; 70 benzersiz katalog kimliği; 25 manifest dosyasının boyut ve SHA-256 eşleşmesi; ZIP bütünlüğü. Bu kontroller PowerShell sözdizimi veya çalışma testi yerine geçmez.

## Windows VM kabul testi
1. Anlık görüntülü Windows 11 VM'de `powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Invoke-Tests.ps1` çalıştırın.
2. Windows Sanal Bellek ekranında otomatik yönetimi kapatıp C: ve ikinci test diskinde farklı özel boyutlar belirleyin; gerekirse yeniden başlatın.
3. Uygulamadan önce aşağıdaki salt okunur çıktıları kaydedin. Windows Sanal Bellek ekranının görüntüsünü de alın.
4. Livn Tools ile yalnızca pagefile otomatik yönetimini uygulayın. Otomatik bayrağını bağımsız komutla okuyun; yeniden başlatmadan çalışan dosya boyutunun değişmesini beklemeyin.
5. Önceki ayara dönün. Bayrağı, iki diskin özel boyutlarını ve ham registry değerini önceki kayıtla karşılaştırın. Yeniden başlatınca Sanal Bellek ekranı ve Win32_PageFileUsage ile kontrol edin.
6. Zaten otomatik yönetim, pagefile tanımı bulunmaması, eski ledger geçişi ve geri almaya erişim hatası senaryolarını ayrıca doğrulayın.

```powershell
Get-CimInstance Win32_ComputerSystem | Select-Object AutomaticManagedPagefile
Get-CimInstance Win32_PageFileSetting | Select-Object Name,InitialSize,MaximumSize
Get-CimInstance Win32_PageFileUsage | Select-Object Name,AllocatedBaseSize,CurrentUsage,PeakUsage
Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Name PagingFiles
```

Kaynaklar:
- https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-computersystem
- https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-pagefilesetting

Kalan inceleme işleri: HAGS/MSI yetenek ve aygıt seçimi, NIC toplu işlem, SPI, hibernation, CFG çakışması, Windows Update ayrıştırma, UI tasarımı. Bu teslim bu işlerin tamamlandığı anlamına gelmez.
