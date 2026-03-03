@echo off
:: ─────────────────────────────────────────────
::  Livn Tools v3.5 — Launcher
::  Sag tiklayip "Yonetici olarak calistir"
:: ─────────────────────────────────────────────

:: Main.ps1 ile ayni klasorde calis
cd /d "%~dp0"

:: Main.ps1 kendi admin kontrolunu yapiyor, direkt calistir
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Main.ps1"
