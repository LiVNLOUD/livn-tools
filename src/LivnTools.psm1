# Livn Tools - modul koku
# UI hem ana is parcaciginda hem arka plan runspace'inde bu modulu yukler.

Set-StrictMode -Version 2.0

$script:LtVersion = '4.0.0'

$here = $PSScriptRoot
foreach ($f in @(
    'Core\Common.ps1',
    'Core\SideEffects.ps1',
    'Core\Backend.ps1',
    'Core\Providers.ps1',
    'Core\Journal.ps1',
    'Core\SystemInfo.ps1',
    'Core\Demo.ps1',
    'Catalog\Helpers.ps1',
    'Catalog\Tweaks.ps1',
    'Engine.ps1',
    'Cleanup.ps1',
    'Setup.ps1',
    'Network.ps1',
    'Startup.ps1',
    'Health.ps1',
    'RecoveryKit.ps1'
)) {
    . (Join-Path $here ($f -replace '\\', [IO.Path]::DirectorySeparatorChar))
}

function Get-LtVersion { $script:LtVersion }

function Initialize-LivnTools {
    <#
      Modulu kullanima hazirlar. Her runspace'te (UI ve arka plan) ayri ayri cagrilir.
      -Backend Memory yalnizca test/kuru calistirma icindir; gercek sisteme dokunmaz.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DataRoot,
        [ValidateSet('Windows','Memory')][string]$Backend = 'Windows',
        [object]$LogQueue = $null,
        [string]$LogFile = ''
    )
    Set-LtBackend -Name $Backend
    Initialize-LtDataRoot -Path $DataRoot
    if (-not $LogFile) { $LogFile = Join-Path (Join-Path (Get-LtDataRoot) 'logs') ("LivnTools_{0}.log" -f (Get-Date -Format 'yyyyMMdd')) }
    Set-LtLogTarget -File $LogFile -Queue $LogQueue
}

Export-ModuleMember -Function *-Lt*, *-LivnTools, Get-LtVersion
