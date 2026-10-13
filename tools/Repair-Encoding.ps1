<#
.SYNOPSIS
    PowerShell dosyalarini UTF-8 BOM ile, .bat dosyalarini ASCII+CRLF ile yeniden kaydeder.
.DESCRIPTION
    Windows PowerShell 5.1, BOM'suz .ps1 dosyalarini sistemin ANSI kod sayfasiyla
    (Turkce Windows'ta 1254) okur; Turkce karakterler bozulur. Bu arac depo
    genelinde kodlamayi duzeltir. Icerik degistirilmez; yalnizca BOM eklenir.
#>
$root = Split-Path -Parent $PSScriptRoot
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
$files = Get-ChildItem -Path $root -Recurse -Include *.ps1, *.psm1, *.psd1 -File | Where-Object { $_.FullName -notmatch '[\\/](\.git|dist)[\\/]' }
foreach ($f in $files) {
    $b = [IO.File]::ReadAllBytes($f.FullName)
    if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { continue }
    if (@($b | Where-Object { $_ -gt 127 }).Count -eq 0) { continue }   # yalnizca ASCII: BOM gerekmez (win.ps1 irm|iex icin BOM'suz kalmali)
    $text = (New-Object System.Text.UTF8Encoding($false, $true)).GetString($b)   # gecersiz UTF-8 -> hata
    [IO.File]::WriteAllText($f.FullName, $text, $utf8Bom)
    Write-Host "BOM eklendi: $($f.FullName.Substring($root.Length + 1))"
}
foreach ($bat in (Get-ChildItem -Path $root -Recurse -Filter *.bat -File | Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' })) {
    $t = [IO.File]::ReadAllText($bat.FullName)
    $n = ($t -replace "`r`n", "`n") -replace "`n", "`r`n"
    if ($n -ne $t) { [IO.File]::WriteAllText($bat.FullName, $n, [Text.Encoding]::ASCII); Write-Host "CRLF: $($bat.Name)" }
}
