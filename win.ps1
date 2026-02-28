# ==========================================
# LiVNLOUD - System Cleaner Firlatici
# ==========================================
Clear-Host
Write-Host "LIVN.TR Sunucusuna Baglaniliyor..." -ForegroundColor Cyan

# 1. Calisma Klasörü (Temp)
$workDir = "$env:TEMP\LiVNLOUD"
if (!(Test-Path $workDir)) { New-Item -ItemType Directory -Path $workDir | Out-Null }

# 2. Senin Ana Scriptinin Raw Linki
$scriptUrl = "https://raw.githubusercontent.com/LiVNLOUD/livn-tools/main/_Files/SystemCleaner.ps1"

# 3. Scripti Indir ve Calistir
Write-Host "[>] Sistem hazirlaniyor..." -ForegroundColor Yellow
Invoke-WebRequest -Uri $scriptUrl -OutFile "$workDir\SystemCleaner.ps1" -ErrorAction SilentlyContinue

# 4. Scripti Atesle
& "$workDir\SystemCleaner.ps1"
