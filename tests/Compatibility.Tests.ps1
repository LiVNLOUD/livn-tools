#Requires -Modules Pester
# Farklı Windows yapılarında kırılgan yollar: oturum kapsamı, farklı yönetici hesabı,
# boş Geri Dönüşüm Kutusu, girdi bekleyen betikler, kod sayfaları, UCPD korumalı değerler.
# Gerçek sistem komutu çalıştırılmaz; canlı dallar mock ile sınanır.

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    # Linux'ta Windows profil degiskenleri yok; Windows benzeri degerler (testten sonra geri alinir)
    $script:savedEnv = @{}
    foreach ($kv in @{ USERPROFILE = 'C:\Users\kaan'; LOCALAPPDATA = 'C:\Users\kaan\AppData\Local'; APPDATA = 'C:\Users\kaan\AppData\Roaming'; TEMP = 'C:\Users\kaan\AppData\Local\Temp' }.GetEnumerator()) {
        $script:savedEnv[$kv.Key] = [Environment]::GetEnvironmentVariable($kv.Key)
        [Environment]::SetEnvironmentVariable($kv.Key, $kv.Value)
    }
    # Windows'a özgü cmdlet'ler Linux'ta yok; mock'lanabilmeleri için yer tutucu
    if (-not (Get-Command Clear-RecycleBin -ErrorAction SilentlyContinue)) { function global:Clear-RecycleBin { param([switch]$Force) } }
    function New-LtFakeRecycleBin([int]$Count) {
        $items = @(1..$Count | Where-Object { $Count -gt 0 } | ForEach-Object { [pscustomobject]@{ Size = 100 } })
        $ns = [pscustomobject]@{ List = $items }
        $ns | Add-Member -MemberType ScriptMethod -Name Items -Value { $this.List }
        $shell = [pscustomobject]@{ Ns = $ns }
        $shell | Add-Member -MemberType ScriptMethod -Name NameSpace -Value { param($n) $this.Ns }
        return $shell
    }
}

Describe 'Oturum kapsamı ve farklı yönetici hesabı' {
    BeforeEach { $sys = New-LtTestSystem }
    AfterEach { Remove-LtTestSystem $sys }

    It 'Süreç araması yalnız bu oturumun süreçlerini döndürür' {
        $mine = [Diagnostics.Process]::GetCurrentProcess().SessionId
        Mock -ModuleName LivnTools Test-LtLiveSystem { $true }
        Mock -ModuleName LivnTools Get-Process {
            @([pscustomobject]@{ ProcessName = 'chrome'; Id = 10; SessionId = $mine; MainWindowHandle = [IntPtr]1 },
              [pscustomobject]@{ ProcessName = 'chrome'; Id = 11; SessionId = $mine + 1; MainWindowHandle = [IntPtr]1 })
        }
        $found = @(Get-LtProcessesByName -Names 'chrome')
        $found.Count | Should -Be 1
        $found[0].Id | Should -Be 10
    }

    It 'Explorer yalnız bu oturumda kapatılır; Winlogon yeniden başlatırsa Livn başlatmaz' {
        $mine = [Diagnostics.Process]::GetCurrentProcess().SessionId
        $script:explorerCalls = 0
        Mock -ModuleName LivnTools Test-LtLiveSystem { $true }
        Mock -ModuleName LivnTools Start-Sleep { }
        Mock -ModuleName LivnTools Get-Process {
            $script:explorerCalls++
            $other = [pscustomobject]@{ ProcessName = 'explorer'; Id = 21; SessionId = $mine + 1 }
            if ($script:explorerCalls -eq 1) { return @([pscustomobject]@{ ProcessName = 'explorer'; Id = 20; SessionId = $mine }, $other) }
            if ($script:explorerCalls -eq 2) { return @($other) }
            return @([pscustomobject]@{ ProcessName = 'explorer'; Id = 22; SessionId = $mine }, $other)
        }
        $script:stopped = New-Object System.Collections.ArrayList
        Mock -ModuleName LivnTools Stop-Process { foreach ($i in @($Id)) { [void]$script:stopped.Add($i) } }
        Mock -ModuleName LivnTools Start-Process { throw 'Livn Explorer başlatmamalı' }
        Restart-LtExplorerShell
        @($script:stopped) | Should -Be @(20)
        Should -Invoke -ModuleName LivnTools Start-Process -Times 0 -Exactly
    }

    It 'Farklı yönetici hesabıyla kullanıcıya ait temizlik atlanır; uygulama kapatılmaz, dosya silinmez' {
        $sys.Mem.UserSettings.SessionOwnerSid = 'S-1-5-21-asil-kullanici'
        Mock -ModuleName LivnTools Test-LtLiveSystem { $true }
        Mock -ModuleName LivnTools Remove-LtFolderContents { throw 'silinmemeli' }
        Mock -ModuleName LivnTools Stop-LtProcessSafe { throw 'kapatılmamalı' }
        Mock -ModuleName LivnTools Get-LtRunningProcessesFor { throw 'süreç denetimine gelinmemeli' }
        $r = Invoke-LtCleanupItem -Item (Get-LtCleanupItem 'clean.temp-user') -Context $sys.Ctx -CloseApps
        $r.Status | Should -Be 'NotSupported'
        $r.Message | Should -Match 'Kullanıcıya ait temizlik atlandı'
        Should -Invoke -ModuleName LivnTools Remove-LtFolderContents -Times 0 -Exactly
    }

    It 'Kullanıcı kapsamı: profil yolları ve uygulama kapatan öğeler işaretlenir, sistem öğeleri işaretlenmez' {
        Test-LtCleanupUserScoped (Get-LtCleanupItem 'clean.temp-user') | Should -BeTrue
        Test-LtCleanupUserScoped (Get-LtCleanupItem 'clean.thumbcache') | Should -BeTrue
        Test-LtCleanupUserScoped (Get-LtCleanupItem 'clean.temp-system') | Should -BeFalse
        Test-LtCleanupUserScoped (Get-LtCleanupItem 'clean.recyclebin') | Should -BeFalse
        $withApp = @(Get-LtCleanupDefinitions | Where-Object { @(Get-LtProp $_ 'Processes' @()).Count -gt 0 })[0]
        Test-LtCleanupUserScoped $withApp | Should -BeTrue
        Get-LtCleanupUserScopeIssue (Get-LtCleanupItem 'clean.temp-user') | Should -BeNullOrEmpty -Because 'bellek arka ucunda kapı uygulanmaz (kuru çalışma zaten simüle eder)'
    }
}

Describe 'Geri Dönüşüm Kutusu' {
    BeforeEach {
        Mock -ModuleName LivnTools Test-LtLiveSystem { $true }
    }
    It 'Zaten boşsa Clear-RecycleBin çağrılmaz ve başarı sayılır' {
        $script:bin = New-LtFakeRecycleBin 0
        Mock -ModuleName LivnTools New-LtShellApplication { $script:bin }
        Mock -ModuleName LivnTools Clear-RecycleBin { throw 'Sistem belirtilen yolu bulamıyor.' }
        Clear-LtRecycleBin | Should -Be 0
        Should -Invoke -ModuleName LivnTools Clear-RecycleBin -Times 0 -Exactly
    }
    It 'Hata sonrası kutu boşsa başarı; hâlâ doluysa hata iletilir' {
        $script:bin = New-LtFakeRecycleBin 2
        Mock -ModuleName LivnTools New-LtShellApplication { $script:bin }
        Mock -ModuleName LivnTools Clear-RecycleBin { $script:bin.Ns.List = @(); throw 'kısmi hata' }
        Clear-LtRecycleBin | Should -Be 200
        $script:bin = New-LtFakeRecycleBin 2
        Mock -ModuleName LivnTools Clear-RecycleBin { throw 'erişim engellendi' }
        { Clear-LtRecycleBin } | Should -Throw '*erişim engellendi*'
    }
}

Describe 'Harici komutlar: girdi ve iptal' -Skip:($IsWindows -or -not (Test-Path '/bin/sh')) {
    BeforeEach { Mock -ModuleName LivnTools Test-LtLiveSystem { $true } }
    It 'Girdi bekleyen komut kapalı girdiyle hemen devam eder' {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $r = Invoke-LtNative -FilePath '/bin/sh' -Arguments @('-c', 'read x; echo bitti') -TimeoutSec 20
        $sw.Elapsed.TotalSeconds | Should -BeLessThan 10
        $r.ExitCode | Should -Be 0
        $r.StdOut | Should -Match 'bitti'
        $r.Cancelled | Should -BeFalse
    }
    It 'İptal istenince uzun süren komut sonlandırılır' {
        $cancel = [hashtable]::Synchronized(@{ Requested = $true })
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $r = Invoke-LtNative -FilePath '/bin/sh' -Arguments @('-c', 'sleep 30') -TimeoutSec 60 -Cancel $cancel
        $sw.Elapsed.TotalSeconds | Should -BeLessThan 15
        $r.Cancelled | Should -BeTrue
        $r.TimedOut | Should -BeFalse
        $r.ExitCode | Should -Be -1
    }
}

Describe 'Metin ve yol uyumluluğu' {
    BeforeAll { $tmp = Join-Path ([IO.Path]::GetTempPath()) ('lt-enc-' + [guid]::NewGuid().ToString('N')); [void](New-Item -ItemType Directory -Path $tmp) }
    AfterAll { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }

    It 'İçe aktarılan betiğin kodlaması tahmin edilir (BOM, UTF-8, ANSI 1254, OEM 857)' {
        $text = 'echo Masaüstü ğışçö'
        $p1 = Join-Path $tmp 'bom.ps1'; [IO.File]::WriteAllText($p1, $text, (New-Object Text.UTF8Encoding($true)))
        $p2 = Join-Path $tmp 'utf8.ps1'; [IO.File]::WriteAllText($p2, $text, (New-Object Text.UTF8Encoding($false)))
        (Read-LtTextFileAuto $p1).Text | Should -BeExactly $text
        (Read-LtTextFileAuto $p2).Text | Should -BeExactly $text
        $old = [Threading.Thread]::CurrentThread.CurrentCulture
        try {
            [Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo('tr-TR')
            $p3 = Join-Path $tmp 'ansi.ps1'; [IO.File]::WriteAllBytes($p3, [Text.Encoding]::GetEncoding(1254).GetBytes($text))
            $p4 = Join-Path $tmp 'oem.bat'; [IO.File]::WriteAllBytes($p4, [Text.Encoding]::GetEncoding(857).GetBytes($text))
            $r3 = Read-LtTextFileAuto $p3
            $r3.Text | Should -BeExactly $text
            $r3.Encoding | Should -Match '1254'
            $r4 = Read-LtTextFileAuto $p4
            $r4.Text | Should -BeExactly $text
            $r4.Encoding | Should -Match '857'
        } finally { [Threading.Thread]::CurrentThread.CurrentCulture = $old }
    }

    It 'Silme yolu kontrolü yalnız ".." parçasını reddeder' {
        Test-LtSafeDeletePath 'C:\Users\kaan\AppData\Local\Temp\x..y' | Should -BeTrue
        Test-LtSafeDeletePath 'C:\Users\kaan\AppData\Local\Temp\..\..\Windows' | Should -BeFalse
        Test-LtSafeDeletePath 'C:\Users\kaan\AppData\Local\Temp\..' | Should -BeFalse
    }

    It 'Masaüstü yolu boş dönmez' {
        Get-LtDesktopPath | Should -Not -BeNullOrEmpty
        (Get-LtCleanupItem 'clean.tor').Detect.Paths | Where-Object { $_ -like '\*' } | Should -BeNullOrEmpty
    }
}

Describe 'Windows 11 korumalı değerler (UCPD)' {
    BeforeEach { $sys = New-LtTestSystem }
    AfterEach { Remove-LtTestSystem $sys }

    It 'UCPD etkinse Widgets simgesi değeri yazılmaz; hazır seçim ilkeye geçer' {
        Get-LtTweakSupport (Get-LtTweak 'ui.widgets-hide') $sys.Ctx | Should -BeNullOrEmpty
        (Resolve-LtPresetSelection -Name Aggressive -Context $sys.Ctx).Selected | Should -Contain 'ui.widgets-hide'
        [void](Set-LtRegValue 'HKLM\SYSTEM\CurrentControlSet\Services\UCPD' 'Start' -Kind DWord -Data 1)
        Get-LtTweakSupport (Get-LtTweak 'ui.widgets-hide') $sys.Ctx | Should -Match 'UCPD'
        $r = Resolve-LtPresetSelection -Name Aggressive -Context $sys.Ctx
        $r.Selected | Should -Contain 'ui.widgets-off-policy'
        $r.Selected | Should -Not -Contain 'ui.widgets-hide'
        [void](Set-LtRegValue 'HKLM\SYSTEM\CurrentControlSet\Services\UCPD' 'Start' -Kind DWord -Data 4)
        Get-LtTweakSupport (Get-LtTweak 'ui.widgets-hide') $sys.Ctx | Should -BeNullOrEmpty -Because 'devre dışı UCPD korumaz'
    }
    It 'Widgets ilkesi uygulanır ve Windows varsayılanına döner' {
        (Invoke-LtApply -TweakIds 'ui.widgets-off-policy' -Context $sys.Ctx).Results[0].Status | Should -Be 'Success'
        [int](Get-LtRegValue 'HKLM\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests').Data | Should -Be 0
        (Invoke-LtRevert -TweakIds 'ui.widgets-off-policy' -Context $sys.Ctx -Target Default).Summary.Failed | Should -Be 0
        (Get-LtRegValue 'HKLM\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests').Exists | Should -BeFalse
    }
}

AfterAll {
    foreach ($k in $script:savedEnv.Keys) { [Environment]::SetEnvironmentVariable($k, $script:savedEnv[$k]) }
}
