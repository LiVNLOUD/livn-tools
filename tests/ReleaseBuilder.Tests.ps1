#Requires -Modules Pester
BeforeAll { $repo = Split-Path -Parent $PSScriptRoot }
Describe 'Release builder validation' {
    BeforeEach {
        $fixture = Join-Path ([IO.Path]::GetTempPath()) ('lt-release-' + [guid]::NewGuid().ToString('N'))
        foreach ($dir in @('tools','src','_Files')) { [void](New-Item -ItemType Directory -Path (Join-Path $fixture $dir) -Force) }
        $builder = Join-Path $fixture 'tools/Build-Release.ps1'
        Copy-Item -LiteralPath (Join-Path $repo 'tools/Build-Release.ps1') -Destination $builder
        foreach ($file in @('Main.ps1','LivnTools.bat','README.md','CHANGELOG.md','LICENSE')) {
            [IO.File]::WriteAllText((Join-Path $fixture $file), 'test fixture only')
        }
        [IO.File]::WriteAllText((Join-Path $fixture 'src/LivnTools.psm1'), '$script:LtVersion = ''9.9.9''')
        $installer = Join-Path $fixture 'win.ps1'
        $original = "# BEGIN RELEASE MANIFEST`n# old fixture`n# END RELEASE MANIFEST`n"
        [IO.File]::WriteAllText($installer, $original)
    }
    AfterEach { Remove-Item -LiteralPath $fixture -Recurse -Force }
    It 'CheckOnly does not mutate the installer or create an archive' {
        & $builder -Version 9.9.9
        $built = [IO.File]::ReadAllText($installer)
        & $builder -Version 9.9.9 -CheckOnly
        [IO.File]::ReadAllText($installer) | Should -Be $built
        Test-Path (Join-Path $fixture 'dist') | Should -BeFalse
    }
    It 'Writes a manifest whose hashes and version match the inputs' {
        & $builder -Version 9.9.9
        . $installer
        $LtRelease.Version | Should -Be '9.9.9'
        @($LtRelease.Files).Count | Should -Be 6
        foreach ($file in $LtRelease.Files) {
            $path = Join-Path $fixture $file.Path
            $file.Size | Should -Be (Get-Item -LiteralPath $path).Length
            $file.Sha256 | Should -Be (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        }
    }
    It 'Includes bundled third-party files by default and retains source files' {
        $optional = Join-Path $fixture '_Files/vendor.exe'
        [IO.File]::WriteAllText($optional, 'fixture executable, not runnable')
        & $builder -Version 9.9.9
        . $installer
        @($LtRelease.Files | Where-Object { $_.Path -like '_Files/*' }).Count | Should -Be 1
        Test-Path $optional | Should -BeTrue
    }
    It 'Allows an explicit minimal package without bundled files' {
        [IO.File]::WriteAllText((Join-Path $fixture '_Files/vendor.exe'), 'fixture')
        & $builder -Version 9.9.9 -IncludeThirdParty:$false
        . $installer
        @($LtRelease.Files | Where-Object { $_.Path -eq '_Files/vendor.exe' }).Count | Should -Be 0
    }
    It 'Builds the default manifest without an optional files directory' {
        Remove-Item (Join-Path $fixture '_Files') -Recurse -Force
        & $builder -Version 9.9.9
        { & $builder -Version 9.9.9 -CheckOnly } | Should -Not -Throw
    }
    It 'Missing required files stop before any mutation' {
        Remove-Item -LiteralPath (Join-Path $fixture 'Main.ps1')
        { & $builder -Version 9.9.9 } | Should -Throw '*Main.ps1*'
        [IO.File]::ReadAllText($installer) | Should -Be $original
    }
    It 'Builds without inventing a license when no license was supplied' {
        Remove-Item -LiteralPath (Join-Path $fixture 'LICENSE')
        & $builder -Version 9.9.9
        . $installer
        @($LtRelease.Files | Where-Object Path -eq 'LICENSE').Count | Should -Be 0
        Test-Path (Join-Path $fixture 'LICENSE') | Should -BeFalse
    }
    It 'Stale manifest verification fails without changing the installer' {
        & $builder -Version 9.9.9
        $built = [IO.File]::ReadAllText($installer)
        [IO.File]::AppendAllText((Join-Path $fixture 'Main.ps1'), 'changed')
        { & $builder -Version 9.9.9 -CheckOnly } | Should -Throw '*manifesti guncel degil*'
        [IO.File]::ReadAllText($installer) | Should -Be $built
    }
    It 'Version mismatch is rejected' {
        { & $builder -Version 4.0.0 } | Should -Throw '*LtVersion*'
        [IO.File]::ReadAllText($installer) | Should -Be $original
    }
    It 'Ambiguous manifest markers are rejected' {
        [IO.File]::WriteAllText($installer, ($original + $original))
        { & $builder -Version 9.9.9 } | Should -Throw
        [IO.File]::ReadAllText($installer) | Should -Be ($original + $original)
    }
    It 'Conflicting modes are rejected without writing' {
        { & $builder -Version 9.9.9 -CheckOnly -Zip } | Should -Throw
        [IO.File]::ReadAllText($installer) | Should -Be $original
    }
    It 'Compression failure preserves an existing archive and removes pending files' {
        [void](New-Item -ItemType Directory -Path (Join-Path $fixture 'dist'))
        $archive = Join-Path $fixture 'dist/LivnTools-9.9.9.zip'
        [IO.File]::WriteAllText($archive, 'previous archive')
        Mock Compress-Archive { throw 'injected compression failure' }
        { & $builder -Version 9.9.9 -Zip } | Should -Throw '*injected*'
        [IO.File]::ReadAllText($archive) | Should -Be 'previous archive'
        @(Get-ChildItem (Join-Path $fixture 'dist') -Force).Count | Should -Be 1
    }
}
