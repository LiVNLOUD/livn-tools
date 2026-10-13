<#
.SYNOPSIS
    Capture Windows validation output; no module installation or live tuning.
#>
[CmdletBinding()]
param([switch]$Full)
$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'Windows is required. No validation was performed.'
}
$root = Split-Path -Parent $PSScriptRoot
$output = Join-Path $root 'tests/results'
[void](New-Item -ItemType Directory -Path $output -Force)
$log = Join-Path $output ('windows-check-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8) + '.txt')
$code = 1
$transcribing = $false
try {
    [void](Start-Transcript -LiteralPath $log -ErrorAction Stop)
    $transcribing = $true
    Write-Host ('PowerShell: {0}; Edition: {1}; OS: {2}; Mode: {3}' -f $PSVersionTable.PSVersion, $PSVersionTable.PSEdition, [Environment]::OSVersion.Version, $(if ($Full) {'Full'} else {'SmokeOnly'}))
    & (Join-Path $PSScriptRoot 'Invoke-WindowsValidation.ps1') -SmokeOnly:(-not $Full)
    Write-Host 'RESULT: PASS. Visual and live-system acceptance remain pending.'
    $code = 0
} catch {
    Write-Host 'RESULT: FAIL' -ForegroundColor Red
    Write-Host ($_ | Format-List * -Force | Out-String)
    Write-Host $_.ScriptStackTrace
} finally {
    if ($transcribing) { [void](Stop-Transcript) }
}
Write-Host "Report: $log"
exit $code
