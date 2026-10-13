# Ortak test yardimcilari. TUM testler Memory arka ucunu kullanir:
# gercek registry/BCD/servis/ag ayarlarina ASLA dokunulmaz.

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $script:RepoRoot 'src/LivnTools.psm1') -Force

function New-LtTestSystem {
    param([string]$Edition = 'Professional', [string]$Build = '22631', [switch]$Server)
    $root = Join-Path ([IO.Path]::GetTempPath()) ('lt-test-' + [guid]::NewGuid().ToString('N'))
    Initialize-LivnTools -DataRoot $root -Backend Memory
    $m = Initialize-LtMemoryDemo -Edition $Edition -Build $Build -Server:$Server
    $ctx = Get-LtSystemContext -AppRoot $script:RepoRoot
    return [pscustomobject]@{ Root = $root; Ctx = $ctx; Mem = $m }
}

function Remove-LtTestSystem($Sys) {
    if ($Sys -and $Sys.Root -and (Test-Path -LiteralPath $Sys.Root)) { Remove-Item -LiteralPath $Sys.Root -Recurse -Force -ErrorAction SilentlyContinue }
}

function New-LtThirdPartyFixture {
    <#
      Dağıtılmayan üçüncü taraf dosyaların (Bitsum .pow, ISLC) YER TUTUCULARI.
      Paket _Files içermez; testler depodaki ikililere bağlı kalmamalı. ISLC sürüm
      kontrolü için yalnız AssemblyFileVersion içeren boş bir derleme üretilir
      (gerçek ISLC değildir, çalıştırılmaz). Döndürülen klasör Ctx.AppRoot olarak kullanılır.
    #>
    param([Parameter(Mandatory)][string]$Root, [string]$IslcVersion = '1.0.4.8')
    $app = Join-Path $Root 'app-fixture'
    $files = Join-Path $app '_Files'
    [void](New-Item -ItemType Directory -Path (Join-Path $files 'ISLC') -Force)
    # Depodaki dogrulanmis plan dosyasi varsa kopyalanir (sabit SHA-256 kontrolu gecmeli); yoksa yer tutucu
    $realPow = Join-Path $script:RepoRoot '_Files/Bitsum-Highest-Performance.pow'
    if (Test-Path -LiteralPath $realPow) { Copy-Item -LiteralPath $realPow -Destination (Join-Path $files 'Bitsum-Highest-Performance.pow') }
    else { [IO.File]::WriteAllText((Join-Path $files 'Bitsum-Highest-Performance.pow'), 'test fixture, not a power plan') }
    $exe = Join-Path $files 'ISLC/Intelligent standby list cleaner ISLC.exe'
    $type = 'LtIslcFixture' + [guid]::NewGuid().ToString('N')
    Add-Type -TypeDefinition "[assembly: System.Reflection.AssemblyFileVersion(`"$IslcVersion`")] public class $type {}" -OutputAssembly ($exe + ".dll") -OutputType Library
    Move-Item -LiteralPath ($exe + ".dll") -Destination $exe
    return $app
}
