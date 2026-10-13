<#
.SYNOPSIS
    Livn Tools test calistirici: PSScriptAnalyzer + Pester.
.DESCRIPTION
    Testler Memory arka ucunu kullanir; gercek sistem ayarlarina dokunmaz.
    Windows PowerShell 5.1 ve PowerShell 7 ile calisir.
      powershell -NoProfile -ExecutionPolicy Bypass -File tools\Invoke-Tests.ps1
    Gerekli moduller: Pester 5.x, PSScriptAnalyzer 1.2x
      Install-Module Pester -MinimumVersion 5.5 -Scope CurrentUser -Force -SkipPublisherCheck
      Install-Module PSScriptAnalyzer -Scope CurrentUser -Force
#>
[CmdletBinding()]
param([switch]$SkipAnalyzer, [switch]$SkipPester, [string]$OutputDir = '')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $OutputDir) { $OutputDir = Join-Path $root 'tests/results' }
if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }
$exit = 0

# Analyzer warnings alone do not reliably report parser failures. Fail before import.
$parseFiles = @(Get-ChildItem -Path $root -Recurse -File -Include *.ps1, *.psm1, *.psd1)
foreach ($file in $parseFiles) {
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$parseErrors)
    if (@($parseErrors).Count -gt 0) {
        throw ("PowerShell syntax error in {0}: {1}" -f $file.FullName, (($parseErrors | ForEach-Object { $_.Message }) -join '; '))
    }
}
Write-Host ("Parser: {0} files checked" -f $parseFiles.Count)

if (-not $SkipAnalyzer) {
    Import-Module PSScriptAnalyzer -MinimumVersion 1.20 -ErrorAction Stop
    $settings = Join-Path $root 'PSScriptAnalyzerSettings.psd1'
    # Urun kodu analiz edilir (testler Pester 5 soz dizimi kullandigi icin 5.1 uyumluluk kurallarinin disinda)
    $files = @(Get-ChildItem -Path (Join-Path $root 'src') -Recurse -Include *.ps1, *.psm1 -File) +
             @(Get-Item (Join-Path $root 'Main.ps1'), (Join-Path $root 'win.ps1'), (Join-Path $root 'tools/Build-Release.ps1'), (Join-Path $root 'tools/Repair-Encoding.ps1'), (Join-Path $root 'tools/Invoke-WindowsValidation.ps1'), (Join-Path $root 'tools/Invoke-WindowsCheck.ps1'))
    $findings = @(foreach ($f in $files) { Invoke-ScriptAnalyzer -Path $f.FullName -Settings $settings })
    $findings | Select-Object RuleName, Severity, ScriptName, Line, Message | Format-Table -AutoSize | Out-String -Width 250 | Write-Host
    $errs = @($findings | Where-Object Severity -eq 'Error')
    $warn = @($findings | Where-Object Severity -eq 'Warning')
    Write-Host ("PSScriptAnalyzer: {0} dosya, {1} hata, {2} uyari" -f $files.Count, $errs.Count, $warn.Count)
    $findings | Select-Object RuleName, Severity, ScriptName, Line, Message | ConvertTo-Json -Depth 3 | Set-Content (Join-Path $OutputDir 'pssa.json') -Encoding UTF8
    if ($errs.Count -gt 0) { $exit = 1 }
}

if (-not $SkipPester) {
    Import-Module Pester -MinimumVersion 5.3 -ErrorAction Stop
    $cfg = New-PesterConfiguration
    $cfg.Run.Path = (Join-Path $root 'tests')
    $cfg.Run.PassThru = $true
    $cfg.Output.Verbosity = 'Detailed'
    $cfg.TestResult.Enabled = $true
    $cfg.TestResult.OutputFormat = 'NUnitXml'
    $cfg.TestResult.OutputPath = (Join-Path $OutputDir 'pester.xml')
    $r = Invoke-Pester -Configuration $cfg
    Write-Host ("Pester: {0} basarili, {1} basarisiz, {2} atlandi" -f $r.PassedCount, $r.FailedCount, $r.SkippedCount)
    if ($r.Result -ne 'Passed' -or $r.TotalCount -eq 0) { $exit = 1 }
}
exit $exit
