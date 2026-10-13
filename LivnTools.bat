@echo off
:: ---------------------------------------------------------------
::  Livn Tools - baslatici
::  Main.ps1 yonetici yetkisini kendisi ister (UAC).
::  Kuru calisma (sisteme dokunmaz):  LivnTools.bat -DryRun
::  Her zaman 64-bit Windows PowerShell 5.1 kullanilir (32-bit veya
::  PowerShell 7 ile acilmaz). Baslamayi engelleyen ilke durumlari
::  gizli pencere acilmadan once burada gosterilir.
:: ---------------------------------------------------------------
setlocal
set "MAIN=%~dp0Main.ps1"
if not exist "%MAIN%" set "MAIN=%~dp0app\Main.ps1"
if not exist "%MAIN%" (
    echo [!] Main.ps1 bulunamadi. Livn Tools'u win.ps1 ile yeniden kurun.
    pause
    exit /b 1
)
set "LT_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "LT_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%LT_PS%" (
    echo [!] Windows PowerShell 5.1 bulunamadi: %LT_PS%
    pause
    exit /b 1
)
set "LT_MAIN=%MAIN%"
"%LT_PS%" -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') { exit 3 }; $p = @((Get-ExecutionPolicy -Scope MachinePolicy), (Get-ExecutionPolicy -Scope UserPolicy)); if ($p -contains 'AllSigned') { exit 4 }; if (($p -contains 'RemoteSigned') -and (Get-Item -LiteralPath $env:LT_MAIN -Stream Zone.Identifier -ErrorAction SilentlyContinue)) { exit 5 }; exit 0"
set "LT_PRE=%ERRORLEVEL%"
if "%LT_PRE%"=="0" goto run
echo.
if "%LT_PRE%"=="3" echo [!] PowerShell kisitli dil modunda (AppLocker/WDAC). Livn Tools bu bilgisayarda calisamaz; BT yoneticinize danisin.
if "%LT_PRE%"=="4" echo [!] Grup Ilkesi yalnizca imzali betiklere izin veriyor (AllSigned). Livn Tools imzali degil; BT yoneticinize danisin.
if "%LT_PRE%"=="5" echo [!] Dosyalar internetten indirildi olarak isaretli ve Grup Ilkesi RemoteSigned. ZIP dosyasina sag tiklayip Ozellikler ^> Engellemeyi kaldir deyip yeniden cikarin.
if not "%LT_PRE%"=="3" if not "%LT_PRE%"=="4" if not "%LT_PRE%"=="5" echo [!] On kontrol calistirilamadi (kod %LT_PRE%).
pause
exit /b 1
:run
start "" "%LT_PS%" -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%MAIN%" %*
exit /b 0
