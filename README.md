<div align="center">

# ⚡ Livn Tools v3.5

**Windows 10/11 için sistem optimizasyon aracı**

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue?logo=powershell)](https://github.com/PowerShell/PowerShell)
[![Windows](https://img.shields.io/badge/Windows-10%2F11-0078D4?logo=windows)](https://www.microsoft.com/windows)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)
[![Version](https://img.shields.io/badge/Version-3.5-purple)](https://github.com/LiVNLOUD/livn-tools/releases)

</div>

---

## 🚀 Hızlı Kurulum

PowerShell'i **Yönetici olarak** açın ve yapıştırın:

```powershell
irm livn.tr/win | iex
```

> Araç `Documents\LivnTools` klasörüne kurulur ve otomatik başlar.

---

## 📸 Ekran Görüntüsü

> *(screenshot burada)*

---

## 🗂 Dosya Yapısı

```
LivnTools/
├── Main.ps1                            ← Ana script (XAML UI + Backend)
├── LivnTools.bat                       ← Manuel başlatıcı (Admin olarak çalıştır)
├── win.ps1                             ← Uzak yükleyici (irm livn.tr/win | iex)
├── _Files/
│   ├── Backups/                        ← Otomatik Registry yedekleri (.reg)
│   ├── Logs/                           ← Terminal log dosyaları (.txt)
│   ├── Bitsum-Highest-Performance.pow  ← Guc plani
│   ├── EmptyStandbyList.exe            ← RAM optimizasyonu (isteğe bağlı)
│   └── Win32Prio_*.reg                 ← Win32PrioritySeparation tweak dosyaları
└── README.md
```

---

## 🛠 Ozellikler

### 🧹 Temizlik
| Sekme | İçerik |
|-------|--------|
| **Quick Clean** | %TEMP%, Prefetch, RecycleBin, Browser cache, DNS flush |
| **Advanced Clean** | WinSxS, SFC/DISM, RAM standby list, Hibernation |

### ⚡ Optimizasyon
| Sekme | İçerik |
|-------|--------|
| **Performance** | HPET, CPU Priority, Guc plani (Bitsum/Ultimate), Win32PrioritySeparation |
| **Network** | TCP AutoTuning, Nagle, RSS, ECN, NIC adapter tweaks |
| **Kernel & Input** | VBS, Spectre mitigations, Mouse/Keyboard buffer (MarkC) |
| **GPU & MSI** | MSI Mode, NVIDIA latency tweaks, AMD Anti-Lag/Chill |

### 🔒 Gizlilik & Sistem
| Sekme | İçerik |
|-------|--------|
| **Privacy & Telemetry** | DiagTrack, Cortana, Bing Search, Xbox services, OneDrive |
| **Windows Tweaks** | Animasyonlar, Dark Mode, Explorer ayarları, Context menu |
| **Run Script** | .ps1 / .bat / .cmd import et ve çalıştır |

---

## 🎛 Global Presets

| Preset | Aciklama |
|--------|----------|
| **Minimal** | Sadece temel, risksiz temizlik ve stabilite |
| **Standard** | Gaming + Streaming icin dengeli ayarlar |
| **Aggressive** | Maksimum performans, latency odakli |
| **Get Installed** | Sistemi tara, mevcut ayarlari terminal'e yaz |

---

## ⚙️ Gereksinimler

- Windows 10 veya Windows 11
- PowerShell 5.1+
- Yönetici (Administrator) yetkisi

---

## 📋 Manuel Kullanim

`irm` komutunu kullanmak istemiyorsanız:

1. Bu repoyu ZIP olarak indirin
2. `LivnTools.bat` dosyasına sağ tıklayın → **Yönetici olarak çalıştır**

---

## ⚠️ Sorumluluk Reddi

Bu araç registry ve sistem ayarlarında değişiklik yapar. Uygulama öncesi otomatik yedek alınır (`_Files\Backups`). Kullanım tamamen kendi sorumluluğunuzdadır.

---

<div align="center">

**[livn.tr](https://livn.tr)** · **[GitHub](https://github.com/LiVNLOUD/livn-tools)**

</div>
