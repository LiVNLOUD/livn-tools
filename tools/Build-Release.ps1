<#
.SYNOPSIS
    Surum bildirimini (dosya listesi + boyut + SHA-256) win.ps1 icine yazar ve
    istege bagli olarak dagitim ZIP'i uretir.
.DESCRIPTION
    Yayin akisi (PUSH/RELEASE KULLANICI ONAYIYLA yapilir):
      1. src/LivnTools.psm1 icindeki surumu ve CHANGELOG'u guncelleyin.
      2. pwsh -File tools/Build-Release.ps1 -Version 4.0.0
      3. Testleri calistirin (tools/Invoke-Tests.ps1) ve degisiklikleri commit edin.
      4. Ayni commit'i etiketleyin: git tag v4.0.0   (etiket = win.ps1'deki BaseUrl)
      5. Onaydan sonra: git push origin main --tags
    Salt okunur kontrol: -Version 4.0.0 -CheckOnly (manifest/ZIP yazmaz).
    .gitattributes "* -text" oldugu icin calisma agacindaki baytlar git'teki baytlarla aynidir.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version,
    [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')][string]$Repo = 'LiVNLOUD/livn-tools',
    [switch]$Zip,
    [switch]$CheckOnly,
    [switch]$IncludeThirdParty = $true
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if ($CheckOnly -and $Zip) { throw 'CheckOnly ve Zip birlikte kullanilamaz.' }

# Validate before changing the installer or creating a distribution archive.
foreach ($required in @('Main.ps1','LivnTools.bat','README.md','CHANGELOG.md','src/LivnTools.psm1','win.ps1')) {
    $path = Join-Path $root $required
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -eq 0) {
        throw "Zorunlu yayin dosyasi eksik veya bos: $required. Manifest degistirilmedi."
    }
}
$moduleText = [IO.File]::ReadAllText((Join-Path $root 'src/LivnTools.psm1'))
$match = [regex]::Match($moduleText, '(?m)^\$script:LtVersion = ''([^'']+)''')
if (-not $match.Success -or $match.Groups[1].Value -ne $Version) {
    throw 'Istenen surum src/LivnTools.psm1 icindeki LtVersion ile eslesmiyor.'
}

# Dagitima giren dosyalar (testler, araclar ve dokumanlar haric)
$include = @('Main.ps1', 'LivnTools.bat', 'README.md', 'CHANGELOG.md')
# A missing license is not a build failure or permission to redistribute.
# Preserve a supplied license verbatim; never invent one for the project owner.
$licensePath = Join-Path $root 'LICENSE'
if (Test-Path -LiteralPath $licensePath -PathType Leaf) {
    if ((Get-Item -LiteralPath $licensePath).Length -eq 0) { throw 'LICENSE dosyasi bos.' }
    $include += 'LICENSE'
}
foreach ($notice in @('docs/THIRD_PARTY.md', 'docs/DEVELOPMENT_STATUS.md', 'docs/USAGE.md', 'docs/ARCHITECTURE.md', 'docs/SUPPORT_MATRIX.md', 'docs/WINDOWS_TEST_CHECKLIST.md', 'docs/KESKE_LISTESI.md', 'docs/TWEAK_AUDIT.md', 'docs/REVIEW_PAGEFILE.md', 'docs/REVIEW_R3.md')) {
    if (Test-Path -LiteralPath (Join-Path $root $notice) -PathType Leaf) { $include += $notice }
}
$include += @(Get-ChildItem -Path (Join-Path $root 'src') -Recurse -File | ForEach-Object { $_.FullName.Substring($root.Length + 1) -replace '\\', '/' })
if ($IncludeThirdParty -and (Test-Path -LiteralPath (Join-Path $root '_Files') -PathType Container)) {
    # Explicit packaging choice; this switch does not establish redistribution rights.
    $include += @(Get-ChildItem -Path (Join-Path $root '_Files') -Recurse -File | Where-Object { $_.Name -ne '.gitkeep' } | ForEach-Object { $_.FullName.Substring($root.Length + 1) -replace '\\', '/' })
}

$files = foreach ($rel in ($include | Sort-Object -Unique)) {
    $full = Join-Path $root $rel
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Dagitim dosyasi bulunamadi: $rel" }
    $i = Get-Item -LiteralPath $full
    [pscustomobject]@{ Path = ($rel -replace '\\', '/'); Size = $i.Length; Sha256 = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash }
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# BEGIN RELEASE MANIFEST')
$lines.Add('$LtRelease = @{')
$lines.Add("    Version = '$Version'")
$lines.Add("    Tag     = 'v$Version'")
$lines.Add("    BaseUrl = 'https://raw.githubusercontent.com/$Repo/v$Version'")
$lines.Add('    Files   = @(')
foreach ($f in $files) { $safePath = $f.Path.Replace("'", "''"); $lines.Add(("        @{{ Path = '{0}'; Size = {1}; Sha256 = '{2}' }}" -f $safePath, $f.Size, $f.Sha256)) }
$lines.Add('    )')
$lines.Add('}')
$lines.Add('# END RELEASE MANIFEST')

$winPath = Join-Path $root 'win.ps1'
$text = [IO.File]::ReadAllText($winPath)
$originalText = $text
$pattern = '(?s)# BEGIN RELEASE MANIFEST.*?# END RELEASE MANIFEST'
if ([regex]::Matches($text, $pattern).Count -ne 1) { throw 'win.ps1 içinde manifest işaretleri bulunamadı.' }
$nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
$text = [regex]::Replace($text, $pattern, [System.Text.RegularExpressions.MatchEvaluator] { param($m) ($lines -join $nl) })
# win.ps1 'irm | iex' ile calisir: BOM iex'i bozar, ANSI/UTF-8 farki PS 5.1'de karakterleri bozar.
# Bu yuzden dosya YALNIZCA ASCII ve BOM'suz tutulur (Turkce karakterler $([char]0x..) ile yazilir).
if ($text -match '[^\x00-\x7F]') { throw 'win.ps1 ASCII dışı karakter içeriyor; irm|iex için yalnızca ASCII kullanın.' }
if ($CheckOnly) {
    if ($text -cne $originalText) { throw 'Yayin manifesti guncel degil. Build-Release.ps1 ile yeniden olusturun.' }
    Write-Host "Yapi kontrolu tamam: $($files.Count) dosya, surum $Version. Dosya degistirilmedi."
    Write-Host 'Bu kontrol Windows testleri veya ucuncu taraf dagitim izinlerinin onayi degildir.'
    return
}
[IO.File]::WriteAllText($winPath, $text, [Text.Encoding]::ASCII)
Write-Host "win.ps1 manifest güncellendi: $($files.Count) dosya, sürüm $Version"

if ($Zip) {
    $out = Join-Path $root "dist/LivnTools-$Version.zip"
    New-Item -ItemType Directory -Path (Split-Path $out) -Force | Out-Null
    $stage = Join-Path ([IO.Path]::GetTempPath()) ("lt-zip-" + [guid]::NewGuid().ToString('N'))
    $pendingZip = Join-Path (Split-Path $out) ('.pending-' + [guid]::NewGuid().ToString('N') + '.zip')
    try {
        foreach ($f in $files) {
            $d = Join-Path $stage $f.Path
            New-Item -ItemType Directory -Path (Split-Path $d) -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $root $f.Path) -Destination $d
            if ((Get-Item -LiteralPath $d).Length -ne $f.Size -or (Get-FileHash -LiteralPath $d -Algorithm SHA256).Hash -ne $f.Sha256) {
                throw "Paketleme sirasinda dosya degisti: $($f.Path)"
            }
        }
        Copy-Item -LiteralPath $winPath -Destination (Join-Path $stage 'win.ps1')
        Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $pendingZip
        Move-Item -LiteralPath $pendingZip -Destination $out -Force
        Write-Host "ZIP: $out  SHA-256: $((Get-FileHash $out -Algorithm SHA256).Hash)"
    } finally {
        if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
        if (Test-Path -LiteralPath $pendingZip) { Remove-Item -LiteralPath $pendingZip -Force }
    }
}
