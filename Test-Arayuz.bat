@echo off
setlocal
set "POWERSHELL_TELEMETRY_OPTOUT=1"
set "DOTNET_CLI_TELEMETRY_OPTOUT=1"
set "LT_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "LT_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%LT_PS%" -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Main.ps1" -DryRun -DataRoot "%~dp0tests\results\ui-data"
set "LT_EXIT=%ERRORLEVEL%"
echo.
echo Exit code: %LT_EXIT%
pause
exit /b %LT_EXIT%
