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
├── Main.ps1                                    ← Ana script (XAML UI + Backend)
├── LivnTools.bat                               ← Manuel başlatıcı (Admin olarak çalıştır)
├── win.ps1                                     ← Uzak yükleyici (irm livn.tr/win | iex)
├── _Files/
│   ├── Backups/                                ← Manuel Registry yedekleri (.reg)
│   ├── Logs/                                   ← Terminal log dosyaları (.txt)
│   ├── Bitsum-Highest-Performance.pow          ← Bitsum güç planı
│   ├── HybredPowerPlans/
│   │   ├── HybredLowLatencyHighPerf.pow        ← Hybred HighPerf güç planı
│   │   └── HybredLowLatencyBalanced.pow        ← Hybred Balanced güç planı
│   ├── Win32Prio_BestFPS_TheHybred.reg         ← Win32Priority tweak (0x14)
│   ├── Win32Prio_Balanced_TheHybred.reg        ← Win32Priority tweak (0x18)
│   ├── Win32Prio_Default_TheHybred.reg         ← Win32Priority tweak (0x26)
│   └── EmptyStandbyList.exe                    ← RAM optimizasyonu (isteğe bağlı)
└── README.md
```

---

## 🛠 Özellikler

### 🧹 Temizlik
| Sekme | İçerik |
|-------|--------|
| **Quick Clean** | %TEMP%, System Temp, Prefetch, RecycleBin, Thumbnail cache, Font cache, DNS flush, Tarayıcı cache (Chrome/Edge/Firefox/Brave/Opera/Vivaldi/Tor), İletişim uygulamaları (Discord/Telegram/Slack/Zoom/Teams), Oyun launcher'ları (Steam/Epic/GOG/Ubisoft/EA/Xbox/Battle.net/Rockstar/Riot/Minecraft), Event Logs, Crash Dumps, WinUpdate cache |
| **Advanced Clean** | WinSxS (DISM), SFC/DISM restore, RAM standby list (EmptyStandbyList.exe), Hibernation, PageFile cleanup |

### ⚡ Optimizasyon
| Sekme | İçerik |
|-------|--------|
| **Performance** | HPET (bcdedit), CPU Priority Boost, SysMain/WSearch kapatma, Game Mode, HW GPU Scheduling, **Güç planı seçimi** (Bitsum / Hybred HighPerf / Hybred Balanced / Ultimate / Balanced / Default), **Win32PrioritySeparation** (BestFPS / Balanced / Default) |
| **Network** | TCP AutoTuning, ECN, RSC, Congestion (CTCP), Nagle/TCPNoDelay/TcpAckFrequency, RSS, NIC adapter tweaks (Flow Control, Interrupt Moderation, Green Ethernet), DNS Prefetch, LLMNR/mDNS kapatma |
| **Kernel & Input** | VBS, DMA Protection, Spectre/Meltdown mitigation, HVCI, Large Pages, DX Contiguous Memory, SecondLevelDataCache, Mouse/Keyboard buffer (MarkC Fix), Raw Input boost, Mouse Smoothing/Acceleration kapatma |
| **GPU & MSI** | GPU algılama, MSI Mode (GPU/NVMe/NIC), IRQ Priority, NVIDIA latency tweaks (PreRender/Power/VSync/FastSync), AMD Anti-Lag/Chill/Power tweaks |

### 🔒 Gizlilik & Sistem
| Sekme | İçerik |
|-------|--------|
| **Privacy & Telemetry** | DiagTrack, dmwappushservice, CEIP, Telemetry Level 0, App Compat, Error Reporting, Activity History, Cortana, Advertising ID, Tailored Experiences, OneDrive kaldırma, Xbox Services, Bing Search, Suggested Apps, Consumer Experience |
| **Windows Tweaks** | Animasyon kapatma, JPEG kalite, MenuShowDelay, Taskbar animasyonları, BSOD detay, Explorer This PC, NumLock, Dosya uzantıları görünür, Long Path, Eski sağ tık menüsü (Win11), Dark Mode |
| **Run Script** | .ps1 / .bat / .cmd dosyası import et ve çalıştır |

---

## 🎛 Global Presets

| Preset | Açıklama |
|--------|----------|
| **Minimal** | Sadece temel, risksiz temizlik ve stabilite |
| **Standard** | Gaming + Streaming için dengeli ayarlar |
| **Aggressive** | Maksimum performans, latency odaklı |
| **Get Installed** | Sistemi tara — uygulanan tweak'leri tespit et, ilgili buton/checkbox'ları aktif göster |

---

## 💾 Backup Sistemi

Her optimizasyon sayfasında **Backup** butonu bulunur. Uygula'ya basmadan önce yedek almak için Backup butonuna tıklayın. Yedekler `_Files\Backups` klasörüne `.reg` formatında kaydedilir.

Yedek geri yüklemek için sol paneldeki **Yedek Geri Yükle** butonunu kullanın.

> ⚠️ **v3.4 ile fark:** Önceki sürümde her uygulama otomatik yedek alıyordu. v3.5'te yedekleme **manueldir** — Backup butonuna siz tıklarsınız.

---

## 📊 Temizlik Progress Bar

Quick Clean çalışırken animasyonlu bir ilerleme çubuğu gösterilir. Temizlik tamamlandığında kaç MB temizlendiği raporlanır.

---

## ⚙️ Gereksinimler

- Windows 10 veya Windows 11
- PowerShell 5.1+
- Yönetici (Administrator) yetkisi

---

## 📋 Manuel Kullanım

`irm` komutunu kullanmak istemiyorsanız:

1. Bu repoyu ZIP olarak indirin veya `LivnTools_v3.5.rar` dosyasını çıkartın
2. `LivnTools.bat` dosyasına sağ tıklayın → **Yönetici olarak çalıştır**

---

## ⚠️ Sorumluluk Reddi

Bu araç registry ve sistem ayarlarında değişiklik yapar. **Uygulama öncesi ilgili sayfadaki Backup butonuna tıklamanız önerilir.** Yedekler `_Files\Backups` klasörüne kaydedilir. Kullanım tamamen kendi sorumluluğunuzdadır.

---

<div align="center">

**[livn.tr](https://livn.tr)** · **[GitHub](https://github.com/LiVNLOUD/livn-tools)**

</div>
