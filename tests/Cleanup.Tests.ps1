#Requires -Modules Pester
# Temizlik: yalnizca gercekten silinen baytlar sayilir, baglantilar izlenmez,
# guvensiz yollar reddedilir, hata/kismi durumlar dogru raporlanir.

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
}

Describe 'Klasor icerigi silme' {
    BeforeEach {
        $sys = New-LtTestSystem
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ('lt-clean-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $tmp 'cache/a/b') -Force | Out-Null
        Set-Content -Path (Join-Path $tmp 'cache/1.tmp') -Value ('x' * 1000) -NoNewline
        Set-Content -Path (Join-Path $tmp 'cache/a/2.tmp') -Value ('y' * 500) -NoNewline
        Set-Content -Path (Join-Path $tmp 'cache/a/b/3.log') -Value ('z' * 250) -NoNewline
        Set-LtCleanupTestRoot $tmp
    }
    AfterEach {
        Set-LtCleanupTestRoot $null
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        Remove-LtTestSystem $sys
    }

    It 'Tum dosyalari siler, gercek bayt sayisini dondurur ve kok klasoru korur' {
        $r = Remove-LtFolderContents -Path (Join-Path $tmp 'cache')
        $r.Bytes | Should -Be 1750
        $r.Files | Should -Be 3
        $r.Failed | Should -Be 0
        Test-Path (Join-Path $tmp 'cache') | Should -BeTrue
        @(Get-ChildItem (Join-Path $tmp 'cache') -Recurse -Force).Count | Should -Be 0
    }

    It 'Filtre ve yinelemesiz mod yalnizca eslesenleri siler' {
        $r = Remove-LtFolderContents -Path (Join-Path $tmp 'cache') -Filter '*.tmp' -Recurse $false
        $r.Files | Should -Be 1
        Test-Path (Join-Path $tmp 'cache/a/2.tmp') | Should -BeTrue
    }

    It 'Sembolik baglanti/junction hedefine inmez' -Skip:($IsWindows -ne $false) {
        $outside = Join-Path $tmp 'korunan'
        New-Item -ItemType Directory -Path $outside | Out-Null
        Set-Content -Path (Join-Path $outside 'onemli.txt') -Value 'veri'
        New-Item -ItemType SymbolicLink -Path (Join-Path $tmp 'cache/link') -Target $outside | Out-Null
        [void](Remove-LtFolderContents -Path (Join-Path $tmp 'cache'))
        Test-Path (Join-Path $outside 'onemli.txt') | Should -BeTrue
    }

    It 'Test kokunun disindaki yol reddedilir' {
        { Remove-LtFolderContents -Path ([IO.Path]::GetTempPath()) } | Should -Throw '*Güvenlik*'
    }

    It 'Olmayan klasor hata degil, sifir sonuc' {
        $r = Remove-LtFolderContents -Path (Join-Path $tmp 'yok')
        $r.Exists | Should -BeFalse
        $r.Bytes | Should -Be 0
    }

    It 'Temizlik ogesi sonucu: basari, desteklenmiyor ve hata ayrimi' {
        $cache = Join-Path $tmp 'cache'
        $ok = @{ Id = 't.ok'; Title = 'ok'; Paths = [scriptblock]::Create("@(@{ Path = '$cache'; Label = 'c' })") }
        $r = Invoke-LtCleanupItem -Item $ok -Context $sys.Ctx
        $r.Status | Should -Be 'Success'; $r.BytesFreed | Should -Be 1750

        $r2 = Invoke-LtCleanupItem -Item $ok -Context $sys.Ctx
        $r2.Status | Should -Be 'Success'; $r2.Message | Should -Match 'yoktu'

        $ns = @{ Id = 't.ns'; Title = 'ns'; Run = { throw 'NOTSUPPORTED:Bu sistemde yok.' } }
        (Invoke-LtCleanupItem -Item $ns -Context $sys.Ctx).Status | Should -Be 'NotSupported'

        $fail = @{ Id = 't.f'; Title = 'f'; Run = { throw 'komut başarısız (çıkış kodu 5)' } }
        $rf = Invoke-LtCleanupItem -Item $fail -Context $sys.Ctx
        $rf.Status | Should -Be 'Failed'; $rf.Message | Should -Match 'çıkış kodu 5'

        $part = @{ Id = 't.p'; Title = 'p'; Run = { @{ Bytes = 10; Failed = 2; Message = 'x' } } }
        (Invoke-LtCleanupItem -Item $part -Context $sys.Ctx).Status | Should -Be 'Partial'

        $unsafe = @{ Id = 't.u'; Title = 'u'; Paths = { @(@{ Path = '/'; Label = 'root' }) } }
        $ru = Invoke-LtCleanupItem -Item $unsafe -Context $sys.Ctx
        $ru.Status | Should -Be 'Failed'; $ru.Message | Should -Match 'Güvenlik'
    }

    It 'Kurulu olmayan uygulamanin temizligi Desteklenmiyor olur' {
        $it = @{ Id = 't.app'; Title = 'app'; Detect = @{ Names = @('Hic Olmayan Uygulama 123'); Paths = @('/yok/yok') }; Paths = { @() } }
        (Invoke-LtCleanupItem -Item $it -Context $sys.Ctx).Status | Should -Be 'NotSupported'
    }
}

Describe 'Temizlik katalogu' {
    It 'Kimlikler benzersiz; tum ogeler Paths veya Run iceriyor' {
        $c = @(Get-LtCleanupCatalog -Refresh)
        @($c.Id | Select-Object -Unique).Count | Should -Be $c.Count
        foreach ($i in $c) { ($i.ContainsKey('Paths') -or $i.ContainsKey('Run')) | Should -BeTrue -Because $i.Id }
    }
    It 'Tehlikeli eski davranislar geri gelmedi (Spotify Data, WhatsApp LocalCache kokü, MountedDevices)' {
        $src = Get-Content (Join-Path $script:RepoRoot 'src/Cleanup.ps1') -Raw
        $src | Should -Not -Match 'Spotify\\Data'
        $src | Should -Not -Match 'MountedDevices''\s*\)'
        $src | Should -Not -Match 'WhatsAppDesktop_cv1g1gvanyjgm\\LocalCache"'
    }
}
