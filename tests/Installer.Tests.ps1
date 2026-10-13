#Requires -Modules Pester
# win.ps1: yarim/bozuk indirme, butunluk dogrulamasi, atomik degistirme,
# kullanici verisini koruma, v3.5 duzeninden gecis ve geri donus.

BeforeAll {
    $env:LIVNTOOLS_INSTALLER_NOAUTORUN = '1'
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'win.ps1')

    function New-FakeRelease([string]$Dir, [hashtable]$Contents) {
        New-Item -ItemType Directory -Path $Dir -Force | Out-Null
        $files = foreach ($k in $Contents.Keys) {
            $p = Join-Path $Dir ($k -replace '/', [IO.Path]::DirectorySeparatorChar)
            New-Item -ItemType Directory -Path (Split-Path $p) -Force | Out-Null
            [IO.File]::WriteAllText($p, $Contents[$k])
            @{ Path = $k; Size = (Get-Item $p).Length; Sha256 = (Get-FileHash $p -Algorithm SHA256).Hash }
        }
        return @{ Version = '9.9.9'; Tag = 'v9.9.9'; BaseUrl = $Dir; Files = @($files) }
    }
}
AfterAll { Remove-Item Env:LIVNTOOLS_INSTALLER_NOAUTORUN -ErrorAction SilentlyContinue }

Describe 'Kurulum ve guncelleme' {
    BeforeEach {
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ('lt-inst-' + [guid]::NewGuid().ToString('N'))
        $root = Join-Path $tmp 'install'
        $src1 = Join-Path $tmp 'src1'
        $LtRelease = New-FakeRelease $src1 @{ 'Main.ps1' = 'Write-Host v1'; 'src/LivnTools.psm1' = '# modul v1'; '_Files/a b.pow' = 'POW1' }
        $LtDownloaderOverride = $null
    }
    AfterEach { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }

    It 'Varsayilan kok: yeni kurulum LocalAppData; mevcut Belgeler kurulumu (v4 veya v3.5) yerinde kalir' {
        $docs = Join-Path $tmp 'Docs'; $local = Join-Path $tmp 'Local'
        Get-LtInstallRoot -Documents $docs -LocalAppData $local | Should -Be (Join-Path $local 'LivnTools')
        New-Item -ItemType Directory -Path (Join-Path $docs 'LivnTools') -Force | Out-Null
        Get-LtInstallRoot -Documents $docs -LocalAppData $local | Should -Be (Join-Path $local 'LivnTools') -Because 'bos klasor kurulum sayilmaz'
        Set-Content -LiteralPath (Join-Path $docs 'LivnTools/Main.ps1') -Value 'v3.5'
        Get-LtInstallRoot -Documents $docs -LocalAppData $local | Should -Be (Join-Path $docs 'LivnTools')
        Remove-Item -LiteralPath (Join-Path $docs 'LivnTools/Main.ps1')
        Set-Content -LiteralPath (Join-Path $docs 'LivnTools/.livntools-root') -Value 'v4'
        Get-LtInstallRoot -Documents $docs -LocalAppData $local | Should -Be (Join-Path $docs 'LivnTools')
        Get-LtInstallRoot -Requested 'X:\ozel' -Documents $docs -LocalAppData $local | Should -Be 'X:\ozel'
    }

    It 'Kok baslatici uygulamanin kendi baslaticisinin kopyasidir; yoksa 64-bit PowerShell kullanan yedek yazilir' {
        $LtRelease = New-FakeRelease $src1 @{ 'Main.ps1' = 'Write-Host v1'; 'LivnTools.bat' = "@echo off`r`nrem app launcher`r`n" }
        [void](Invoke-LtInstall -InstallRoot $root -NoLaunch -SourceOverride $src1)
        [IO.File]::ReadAllText((Join-Path $root 'LivnTools.bat')) | Should -Match 'rem app launcher'
        $root2 = Join-Path $tmp 'install2'
        $LtRelease = New-FakeRelease (Join-Path $tmp 'src3') @{ 'Main.ps1' = 'Write-Host v1' }
        [void](Invoke-LtInstall -InstallRoot $root2 -NoLaunch -SourceOverride (Join-Path $tmp 'src3'))
        $bat = [IO.File]::ReadAllText((Join-Path $root2 'LivnTools.bat'))
        $bat | Should -Match 'Sysnative'
        $bat | Should -Match '%~dp0app\\Main.ps1'
    }

    It 'Temiz kurulum: dosyalar dogrulanir, baslatici ve veri klasoru olusur' {
        $r = Invoke-LtInstall -InstallRoot $root -NoLaunch -SourceOverride $src1
        $r.Status | Should -Be 'Installed'
        Get-Content (Join-Path $root 'app/Main.ps1') -Raw | Should -Be 'Write-Host v1'
        Test-Path (Join-Path $root 'app/_Files/a b.pow') | Should -BeTrue
        Test-Path (Join-Path $root 'app/VERSION.json') | Should -BeTrue
        Test-Path (Join-Path $root 'LivnTools.bat') | Should -BeTrue
        Test-Path (Join-Path $root '.livntools-root') | Should -BeTrue
        Test-Path (Join-Path $root 'data') | Should -BeTrue
        @(Get-ChildItem $root -Filter '.staging-*' -Force).Count | Should -Be 0
    }

    It 'Yarim kalan indirme: kurulum DEGISMEZ, gecici klasor silinir' {
        [void](Invoke-LtInstall -InstallRoot $root -NoLaunch -SourceOverride $src1)
        $src2 = Join-Path $tmp 'src2'
        $LtRelease = New-FakeRelease $src2 @{ 'Main.ps1' = 'Write-Host v2 uzun icerik'; 'src/LivnTools.psm1' = '# modul v2'; '_Files/a b.pow' = 'POW2' }
        $LtDownloaderOverride = {
            param($Url, $Dest)
            $b = [IO.File]::ReadAllBytes($Url)
            [IO.File]::WriteAllBytes($Dest, $b[0..([math]::Max(0, [int]($b.Length / 2) - 1))])   # kesilmis dosya
        }
        { Invoke-LtInstall -InstallRoot $root -NoLaunch -SourceOverride $src2 } | Should -Throw '*nl*k do*rulanamad*'
        Get-Content (Join-Path $root 'app/Main.ps1') -Raw | Should -Be 'Write-Host v1'
        @(Get-ChildItem $root -Filter '.staging-*' -Force).Count | Should -Be 0
        Test-Path (Join-Path $root 'app.prev') | Should -BeFalse
    }

    It 'Ayni boyutta ama farkli icerik (ozet uyusmazligi) reddedilir' {
        $LtDownloaderOverride = { param($Url, $Dest) $b = [IO.File]::ReadAllBytes($Url); $b[0] = $b[0] -bxor 1; [IO.File]::WriteAllBytes($Dest, $b) }
        { Invoke-LtInstall -InstallRoot $root -NoLaunch -SourceOverride $src1 } | Should -Throw
        Test-Path (Join-Path $root 'app') | Should -BeFalse
    }

    It 'Indirme istisnasi (ag hatasi) kurulumu degistirmez' {
        [void](Invoke-LtInstall -InstallRoot $root -NoLaunch -SourceOverride $src1)
        $LtDownloaderOverride = { param($Url, $Dest) throw 'Bağlantı kesildi' }
        { Invoke-LtInstall -InstallRoot $root -NoLaunch -SourceOverride $src1 } | Should -Throw '*Bağlantı kesildi*'
        Get-Content (Join-Path $root 'app/Main.ps1') -Raw | Should -Be 'Write-Host v1'
    }

    It 'Guncelleme onceki surumu app.prev olarak saklar, kullanici verisine dokunmaz; geri donus calisir' {
        [void](Invoke-LtInstall -InstallRoot $root -NoLaunch -SourceOverride $src1)
        Set-Content -Path (Join-Path $root 'data/ledger-test.json') -Value 'KULLANICI VERISI'
        $src2 = Join-Path $tmp 'src2'
        $LtRelease = New-FakeRelease $src2 @{ 'Main.ps1' = 'Write-Host v2'; 'src/LivnTools.psm1' = '# modul v2'; '_Files/a b.pow' = 'POW2' }
        [void](Invoke-LtInstall -InstallRoot $root -NoLaunch -SourceOverride $src2)
        Get-Content (Join-Path $root 'app/Main.ps1') -Raw | Should -Be 'Write-Host v2'
        Get-Content (Join-Path $root 'app.prev/Main.ps1') -Raw | Should -Be 'Write-Host v1'
        Get-Content (Join-Path $root 'data/ledger-test.json') -Raw | Should -Match 'KULLANICI VERISI'
        [void](Invoke-LtInstall -InstallRoot $root -Rollback)
        Get-Content (Join-Path $root 'app/Main.ps1') -Raw | Should -Be 'Write-Host v1'
        Get-Content (Join-Path $root 'app.prev/Main.ps1') -Raw | Should -Be 'Write-Host v2'
    }

    It 'v3.5 duzeninden gecis: .reg yedekleri ve loglar data altina tasinir, hicbir sey silinmez' {
        New-Item -ItemType Directory -Path (Join-Path $root '_Files/Backups') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root '_Files/Logs') -Force | Out-Null
        Set-Content (Join-Path $root 'Main.ps1') 'eski'
        Set-Content (Join-Path $root '_Files/Backups/Auto_Perf.reg') 'REG'
        Set-Content (Join-Path $root '_Files/Logs/l.txt') 'LOG'
        [void](Invoke-LtInstall -InstallRoot $root -NoLaunch -SourceOverride $src1)
        Test-Path (Join-Path $root 'data/legacy-v3.5/Backups/Auto_Perf.reg') | Should -BeTrue
        Test-Path (Join-Path $root 'data/legacy-v3.5/Logs/l.txt') | Should -BeTrue
        Test-Path (Join-Path $root 'Main.ps1') | Should -BeFalse
        @(Get-ChildItem $root -Directory -Filter 'legacy-v3.5-app-*').Count | Should -Be 1
        Get-Content (Join-Path $root 'app/Main.ps1') -Raw | Should -Be 'Write-Host v1'
    }

    It 'Bos surum bildirimi ile kurulum yapilmaz' {
        $LtRelease = @{ Version = '0'; Tag = 'x'; BaseUrl = $src1; Files = @() }
        { Invoke-LtInstall -InstallRoot $root -NoLaunch } | Should -Throw '*bildirimi boş*'
    }

    It 'Dosyanin var olmasi basari sayilmaz (bos dosya reddedilir)' {
        $f = Join-Path $tmp 'empty.bin'; New-Item -ItemType File -Path $f | Out-Null
        Test-LtFileIntegrity -Path $f -Size 10 -Sha256 ('0' * 64) | Should -BeFalse
    }
}

Describe 'Depodaki win.ps1 surum bildirimi' {
    It 'Bildirim doluysa her dosyanin boyutu ve SHA-256 degeri depodaki dosyayla eslesir' {
        $repo = Split-Path -Parent $PSScriptRoot
        $text = Get-Content (Join-Path $repo 'win.ps1') -Raw
        $entries = [regex]::Matches($text, "@\{ Path = '([^']+)'; Size = (\d+); Sha256 = '([0-9A-F]{64})' \}")
        if ($entries.Count -eq 0) { Set-ItResult -Skipped -Because 'bildirim henüz üretilmemiş (tools/Build-Release.ps1)'; return }
        foreach ($e in $entries) {
            $p = Join-Path $repo $e.Groups[1].Value
            Test-Path -LiteralPath $p | Should -BeTrue -Because $e.Groups[1].Value
            (Get-Item -LiteralPath $p).Length | Should -Be ([long]$e.Groups[2].Value) -Because $e.Groups[1].Value
            (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash | Should -Be $e.Groups[3].Value -Because $e.Groups[1].Value
        }
    }
    It 'Uygulamanin yukledigi her kaynak dosya bildirimde var (ag kurulumunda eksik modul olmaz)' {
        $repo = Split-Path -Parent $PSScriptRoot
        $text = Get-Content (Join-Path $repo 'win.ps1') -Raw
        $listed = @([regex]::Matches($text, "@\{ Path = '([^']+)';") | ForEach-Object { $_.Groups[1].Value })
        if ($listed.Count -eq 0) { Set-ItResult -Skipped -Because 'bildirim henüz üretilmemiş'; return }
        $src = Join-Path $repo 'src'
        foreach ($f in @(Get-ChildItem -LiteralPath $src -Recurse -File | Where-Object { $_.Extension -in @('.ps1', '.psm1', '.xaml') })) {
            $rel = 'src/' + $f.FullName.Substring($src.Length + 1).Replace('\', '/')
            $listed | Should -Contain $rel
        }
        foreach ($f in @('Main.ps1', 'LivnTools.bat')) { $listed | Should -Contain $f }
    }
}
