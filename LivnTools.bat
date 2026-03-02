@echo off
:: ─────────────────────────────────────────────
::  Livn Tools v3.5 — Launcher
::  Sag tiklayip "Yonetici olarak calistir"
:: ─────────────────────────────────────────────

:: Admin değilse UAC ile kendini yeniden başlat
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:: Main.ps1 ile aynı klasörde çalış
cd /d "%~dp0"

:: PowerShell penceresini başlat, bu CMD penceresini kapat
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Main.ps1"
exit
