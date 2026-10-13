#Requires -Modules Pester
# Statik kontroller: PowerShell 5.1 dosya kodlamasi, sozdizimi, XAML butunlugu,
# sessiz hata bastirma kaliplari.

BeforeDiscovery {
    $repo = Split-Path -Parent $PSScriptRoot
    $script:psFiles = @(Get-ChildItem -Path $repo -Recurse -Include *.ps1, *.psm1, *.psd1 -File |
        Where-Object { $_.FullName -notmatch '[\\/](\.git|tests[\\/]results|dist)[\\/]' } |
        ForEach-Object { @{ Path = $_.FullName; Name = $_.FullName.Substring($repo.Length + 1) } })
}

BeforeAll { $repo = Split-Path -Parent $PSScriptRoot }

Describe 'Kodlama ve sozdizimi: <Name>' -ForEach $psFiles {
    It 'Hatasiz ayristirilir' {
        $tokens = $null; $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
        @($errors).Count | Should -Be 0 -Because (($errors | ForEach-Object { "$($_.Extent.StartLineNumber): $($_.Message)" }) -join '; ')
    }
    It 'ASCII disi karakter iceriyorsa UTF-8 BOM ile kaydedilmis (Windows PowerShell 5.1 BOM olmadan ANSI okur)' {
        $bytes = [IO.File]::ReadAllBytes($Path)
        $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
        $nonAscii = @($bytes | Where-Object { $_ -gt 127 }).Count -gt 0
        if ($nonAscii) { $hasBom | Should -BeTrue }
    }
}

Describe 'Uzaktan kurulum betigi' {
    It 'win.ps1 yalnizca ASCII ve BOM icermez (irm | iex BOM ile bozulur)' {
        $b = [IO.File]::ReadAllBytes((Join-Path $repo 'win.ps1'))
        ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB) | Should -BeFalse
        @($b | Where-Object { $_ -gt 127 }).Count | Should -Be 0
    }
    It 'win.ps1 metin olarak Invoke-Expression ile calistirilabilir (otomatik calisma kapaliyken)' {
        $t = [IO.File]::ReadAllText((Join-Path $repo 'win.ps1'))
        $env:LIVNTOOLS_INSTALLER_NOAUTORUN = '1'
        try { { Invoke-Expression $t } | Should -Not -Throw } finally { Remove-Item Env:LIVNTOOLS_INSTALLER_NOAUTORUN }
    }
}

Describe 'Baslatici ve XAML' {
    It 'LivnTools.bat yalnizca ASCII ve CRLF satir sonlari' {
        $b = [IO.File]::ReadAllBytes((Join-Path $repo 'LivnTools.bat'))
        @($b | Where-Object { $_ -gt 127 }).Count | Should -Be 0
        $text = [Text.Encoding]::ASCII.GetString($b)
        ($text -replace "`r`n", '') | Should -Not -Match "`n"
    }
    It 'Baslaticilar 32-bit kabukta da 64-bit Windows PowerShell 5.1 secer' {
        foreach ($bat in @('LivnTools.bat', 'Test-Arayuz.bat', 'Test-Windows.bat')) {
            $text = [IO.File]::ReadAllText((Join-Path $repo $bat))
            $text | Should -Match 'Sysnative\\WindowsPowerShell\\v1\.0\\powershell\.exe' -Because $bat
            $text | Should -Not -Match '(?m)^start "" powershell\.exe' -Because $bat
        }
        $launcher = [IO.File]::ReadAllText((Join-Path $repo 'LivnTools.bat'))
        foreach ($code in '3', '4', '5') { $launcher | Should -Match ('"%LT_PRE%"=="' + $code + '" echo') }
    }
    It 'Main.ps1 yeniden baslatmada kabuk seceneklerini -File oncesine koyar ve dogru kabugu zorlar' {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'Main.ps1'), [ref]$null, [ref]$null)
        $calls = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Start-Process' }, $true))
        $calls.Count | Should -BeGreaterOrEqual 3
        foreach ($c in $calls) {
            $text = $c.Extent.Text
            $text | Should -Match '-FilePath \$exe' -Because $text
            $text | Should -Match '-ArgumentList \(\$hostArgs \+' -Because $text
        }
        $main = [IO.File]::ReadAllText((Join-Path $repo 'Main.ps1'))
        $main | Should -Match "PSEdition -eq 'Core'"
        $main | Should -Match 'Is64BitProcess'
        $main | Should -Match 'LIVNTOOLS_HOSTFIX'
        $main | Should -Match "\`$Host\.Name -ne 'ConsoleHost'" -Because 'ISE / VS Code kabuğu da yeniden başlatılmalı'
    }
    It 'Main.ps1 sonda ters egik cizgi olan yolu komut satirinda bozmaz' {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'Main.ps1'), [ref]$null, [ref]$null)
        $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'ConvertTo-LtArgument' }, $true)
        . ([scriptblock]::Create($fn.Extent.Text))
        ConvertTo-LtArgument 'D:\x\' | Should -BeExactly '"D:\x\\"'
        ConvertTo-LtArgument 'C:\Users\Kaan Akdağ\LivnTools' | Should -BeExactly '"C:\Users\Kaan Akdağ\LivnTools"'
    }
    It 'MainWindow.xaml gecerli XML ve App.ps1 icindeki tum x:Name ogeleri mevcut' {
        [xml]$x = Get-Content (Join-Path $repo 'src/UI/MainWindow.xaml') -Raw -Encoding UTF8
        $ns = @{ x = 'http://schemas.microsoft.com/winfx/2006/xaml' }
        $names = @(Select-Xml -Xml $x -XPath '//*[@x:Name]' -Namespace $ns | ForEach-Object { $_.Node.GetAttribute('Name', $ns.x) })
        $app = Get-Content (Join-Path $repo 'src/UI/App.ps1') -Raw
        $m = [regex]::Match($app, '(?s)\$names = @\((.*?)\)\s*\r?\n\s*\$controls')
        $m.Success | Should -BeTrue
        $wanted = [regex]::Matches($m.Groups[1].Value, "'([A-Za-z0-9]+)'") | ForEach-Object { $_.Groups[1].Value }
        foreach ($w in $wanted) { $names | Should -Contain $w }
    }
    It 'Diyalog XAML gecerli XML' {
        $d = Get-Content (Join-Path $repo 'src/UI/Dialogs.ps1') -Raw
        $m = [regex]::Match($d, "(?s)\`$script:LtReportXaml = @'\r?\n(.*?)\r?\n'@")
        $m.Success | Should -BeTrue
        { [xml]$m.Groups[1].Value } | Should -Not -Throw
    }
}

Describe 'Sessiz hata bastirma kaliplari' {
    It 'Backend Windows yazma komutlari hatayi bastirmaz (SilentlyContinue yok)' {
        $lines = Get-Content (Join-Path $repo 'src/Core/Backend.ps1')
        $bad = @($lines | Where-Object { $_ -match '^\s*(Set-|Stop-Service|Start-Service|Register-|Unregister-|Remove-ItemProperty|New-ItemProperty)' -and $_ -match 'SilentlyContinue' })
        $bad.Count | Should -Be 0 -Because ($bad -join ' | ')
    }
    It 'Harici komutlar cikis kodu denetimli calistirici ile cagrilir (2>&1 | Out-Null yok)' {
        foreach ($f in @('src/Core/Backend.ps1', 'src/Engine.ps1', 'src/Cleanup.ps1', 'src/Core/Providers.ps1')) {
            (Get-Content (Join-Path $repo $f) -Raw) | Should -Not -Match '2>&1\s*\|\s*Out-Null' -Because $f
        }
    }
}
