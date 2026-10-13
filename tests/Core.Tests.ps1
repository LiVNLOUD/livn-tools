#Requires -Modules Pester
# Cekirdek yardimcilar: komut calistirici, yol korumasi, registry veri donusumleri,
# yerellestirilmis cikti ayristirma, geri yukleme noktasi dogrulamasi.

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
}

Describe 'Harici komut calistirici' {
    It 'Cikis kodunu yakalar ve basarisiz kodda Invoke-LtNativeChecked hata firlatir' -Skip:($IsWindows -ne $false) {
        $r = Invoke-LtNative -FilePath '/bin/sh' -Arguments @('-c', 'echo merhaba; exit 3')
        $r.ExitCode | Should -Be 3
        $r.StdOut | Should -Match 'merhaba'
        { Invoke-LtNativeChecked -FilePath '/bin/sh' -Arguments @('-c', 'exit 5') } | Should -Throw '*çıkış kodu 5*'
        { Invoke-LtNativeChecked -FilePath '/bin/sh' -Arguments @('-c', 'exit 1') -SuccessCodes 0, 1 } | Should -Not -Throw
    }
    It 'Zaman asiminda sureci sonlandirir' -Skip:($IsWindows -ne $false) {
        $r = Invoke-LtNative -FilePath '/bin/sh' -Arguments @('-c', 'sleep 30') -TimeoutSec 1
        $r.TimedOut | Should -BeTrue
        $r.ExitCode | Should -Be -1
    }
    It 'Olmayan dosya icin -1 ve hata metni dondurur (istisna yerine)' {
        $r = Invoke-LtNative -FilePath 'bu-dosya-yok-12345.exe'
        $r.ExitCode | Should -Be -1
        $r.StdErr | Should -Not -BeNullOrEmpty
    }
    It 'Argumanlari Windows kurallarina gore tirnaklar' {
        ConvertTo-LtArgumentString @('/set', '{current}', 'useplatformclock', 'no') | Should -Be '/set {current} useplatformclock no'
        ConvertTo-LtArgumentString @('/import', 'C:\Program Files\x y.pow') | Should -Be '/import "C:\Program Files\x y.pow"'
        ConvertTo-LtArgumentString @('a"b') | Should -Be '"a\"b"'
        ConvertTo-LtArgumentString @('') | Should -Be '""'
    }
}

Describe 'Yerellestirmeden bagimsiz cikti ayristirma' {
    It 'bcdedit ciktisinda alan adlari Turkce/Almanca olsa da ilk GUID alinir' {
        $tr = "Windows Önyükleme Yükleyicisi`r`n-------------------`r`ntanımlayıcı             {4A1B2C3D-1111-2222-3333-444455556666}`r`ncihaz                   partition=C:`r`nresumeobject            {99999999-1111-2222-3333-444455556666}"
        ConvertFrom-LtBcdEnumOutput $tr | Should -Be '{4a1b2c3d-1111-2222-3333-444455556666}'
        $de = "Windows-Startladeprogramm`r`nBezeichner              {aaaaaaaa-1111-2222-3333-444455556666}"
        ConvertFrom-LtBcdEnumOutput $de | Should -Be '{aaaaaaaa-1111-2222-3333-444455556666}'
        { ConvertFrom-LtBcdEnumOutput 'Erişim reddedildi.' } | Should -Throw
    }
    It 'powercfg ciktisindan plan adina bakmadan GUID listesi cikarir' {
        $tr = "Varolan Güç Düzenleri (* Etkin)`r`n-----------------------------------`r`nGüç Düzeni GUID'si: 381b4222-f694-41f0-9685-ff5bb260df2e  (Dengeli) *`r`nGüç Düzeni GUID'si: 8C5E7FDA-E8BF-4A96-9A85-A6E23A8C635C  (Yüksek performans)"
        $g = @(ConvertFrom-LtPowercfgOutput $tr)
        $g.Count | Should -Be 2
        $g[1] | Should -Be '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
    }
}

Describe 'Yol korumasi' {
    BeforeAll { Set-LtCleanupTestRoot $null }
    It 'Tehlikeli veya bos ortam degiskeninden dogan yollari reddeder' {
        foreach ($p in @('', '   ', '\Temp', 'C:\', 'C:\Windows', 'D:\', 'C:\\Temp', 'C:\Users\x\..\..\Windows', 'relative\path', '\\server\share\x')) {
            Test-LtSafeDeletePath $p | Should -BeFalse -Because "'$p'"
        }
    }
    It 'Normal onbellek yollarina izin verir' {
        Test-LtSafeDeletePath 'C:\Windows\Temp' | Should -BeTrue
        Test-LtSafeDeletePath 'C:\Users\kaan\AppData\Local\Temp' | Should -BeTrue
    }
}

Describe 'Registry veri donusumleri' {
    BeforeEach { $sys = New-LtTestSystem }
    AfterEach { Remove-LtTestSystem $sys }

    It 'DWORD 0xFFFFFFFF (PowerShell''de -1) isaretsiz olarak saklanir ve karsilastirilir' {
        [void](Set-LtRegValue 'HKLM\SOFTWARE\T' 'X' -Kind DWord -Data 0xFFFFFFFF)
        (Get-LtRegValue 'HKLM\SOFTWARE\T' 'X').Data | Should -Be 4294967295
        Test-LtRegDataEqual 4294967295 (ConvertTo-LtRegData -Value (ConvertFrom-LtRegData -Data -1 -Kind DWord) -Kind DWord) 'DWord' | Should -BeTrue
        { ConvertFrom-LtRegData -Data 4294967296 -Kind DWord } | Should -Throw
    }
    It 'MultiString, Binary ve varsayilan (adsiz) deger gidip gelir' {
        [void](Set-LtRegValue 'HKCU\T' 'M' -Kind MultiString -Data @('a', 'b c'))
        @((Get-LtRegValue 'HKCU\T' 'M').Data) | Should -Be @('a', 'b c')
        $b64 = [Convert]::ToBase64String([byte[]](1, 2, 255))
        [void](Set-LtRegValue 'HKCU\T' 'B' -Kind Binary -Data $b64)
        (Get-LtRegValue 'HKCU\T' 'B').Data | Should -Be $b64
        [void](Set-LtRegValue 'HKCU\T' '' -Kind String -Data '')
        $d = Get-LtRegValue 'HKCU\T' ''
        $d.Exists | Should -BeTrue; $d.Data | Should -Be ''
    }
    It 'Yol bicimlerini normalize eder' {
        (ConvertTo-LtRegPath 'HKLM:\SOFTWARE\X').Full | Should -Be 'HKLM\SOFTWARE\X'
        (ConvertTo-LtRegPath 'HKEY_CURRENT_USER\Software').Full | Should -Be 'HKCU\Software'
        (ConvertTo-LtRegPath 'Registry::HKEY_LOCAL_MACHINE\A').Full | Should -Be 'HKLM\A'
        { ConvertTo-LtRegPath 'HKXX\A' } | Should -Throw
    }
    It 'Bos olmayan anahtar silinmez' {
        [void](Set-LtRegValue 'HKCU\K\Alt' 'V' -Kind DWord -Data 1)
        Remove-LtRegKeyIfEmpty 'HKCU\K' | Should -BeFalse
        Remove-LtRegValue 'HKCU\K\Alt' 'V'
        Remove-LtRegKeyIfEmpty 'HKCU\K\Alt' | Should -BeTrue
        Remove-LtRegKeyIfEmpty 'HKCU\K' | Should -BeTrue
    }
}

Describe 'Geri yukleme noktasi' {
    BeforeEach { $sys = New-LtTestSystem }
    AfterEach { Remove-LtTestSystem $sys }
    It 'Windows 24 saat sinirina takilirsa Basarili degil Atlandi raporlanir' {
        $sys.Mem.RestoreThrottled = $true
        $r = New-LtRestorePoint -Description 'test'
        $r.Status | Should -Be 'Skipped'
        $r.Message | Should -Match '24 saat'
    }
    It 'Olusturulup dogrulanirsa Basarili' {
        (New-LtRestorePoint -Description 'test2').Status | Should -Be 'Success'
    }
}

Describe 'Sistem baglami' {
    It 'Home, Pro, Enterprise ve Server surumlerini ayirt eder' {
        $s = New-LtTestSystem -Edition 'Core'; try { $s.Ctx.EditionId | Should -Be 'Core'; $s.Ctx.IsWin11 | Should -BeTrue } finally { Remove-LtTestSystem $s }
        $s = New-LtTestSystem -Edition 'ServerStandard' -Build '20348' -Server; try { $s.Ctx.IsServer | Should -BeTrue; $s.Ctx.IsWin11 | Should -BeFalse } finally { Remove-LtTestSystem $s }
        $s = New-LtTestSystem -Build '19045'; try { $s.Ctx.IsWin11 | Should -BeFalse } finally { Remove-LtTestSystem $s }
    }
}
