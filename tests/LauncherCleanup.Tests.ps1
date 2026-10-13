BeforeAll { . (Join-Path $PSScriptRoot 'TestHelpers.ps1') }
Describe 'Launcher cleanup boundaries' {
    BeforeEach { $sys=New-LtTestSystem; Set-LtCleanupTestRoot $sys.Root }
    AfterEach { Set-LtCleanupTestRoot $null; Remove-LtTestSystem $sys }
    It 'Does not select launcher caches for routine cleanup or forcibly close any launcher' {
        foreach ($item in @(Get-LtCleanupCatalog | Where-Object Group -eq 'Oyun başlatıcıları')) {
            $item.Default | Should -BeFalse
            $item.RequireClosed | Should -BeTrue
        }
    }
    It 'Blocks cleanup on a background Java process even when CloseApps is requested' {
        $sys.Mem.Processes=@(@{Name='javaw';HasWindow=$false})
        $item=Get-LtCleanupItem clean.minecraft
        $itemCopy=@{}; foreach($key in $item.Keys) { $itemCopy[$key]=$item[$key] }; $itemCopy.Remove('Detect')
        Mock -ModuleName LivnTools Stop-LtProcessSafe { throw 'must not terminate Java' }
        Mock -ModuleName LivnTools Remove-LtFolderContents { throw 'must not delete while running' }
        (Invoke-LtCleanupItem -Item $itemCopy -Context $sys.Ctx -CloseApps).Status | Should -Be Skipped
        Should -Invoke -ModuleName LivnTools Stop-LtProcessSafe -Times 0 -Exactly
        Should -Invoke -ModuleName LivnTools Remove-LtFolderContents -Times 0 -Exactly
    }
    It 'Keeps recent logs while deleting only old files in the chosen folder' {
        $folder=Join-Path $sys.Root 'game-logs'; [void](New-Item -ItemType Directory -Path $folder)
        $old=Join-Path $folder old.log; $new=Join-Path $folder latest.log
        [IO.File]::WriteAllText($old,'old'); [IO.File]::WriteAllText($new,'current')
        [IO.File]::SetLastWriteTimeUtc($old,[DateTime]::UtcNow.AddDays(-14))
        $r=Remove-LtFolderContents -Path $folder -OlderThanDays 7
        $r.Files | Should -Be 1
        Test-Path -LiteralPath $new | Should -BeTrue
        Test-Path -LiteralPath $old | Should -BeFalse
    }
    It 'Never targets Minecraft saves, mods, assets, versions or account files' {
        $item=Get-LtCleanupItem clean.minecraft
        $paths=@(& $item.Paths)
        $paths.Count | Should -Be 2
        foreach($p in $paths) {
            $p.Path | Should -Match '\.minecraft\\(logs|crash-reports)$'
            $p.OlderThanDays | Should -Be 7
        }
    }
    It 'Does not enable unverified whole-cache resets' {
        foreach ($id in @('clean.ea','clean.xbox','clean.battlenet')) {
            (Get-LtCleanupAvailability (Get-LtCleanupItem $id) $sys.Ctx) | Should -Not -BeNullOrEmpty
        }
    }
    It 'Steam cache paths exclude userdata, workshop, shaders and the whole htmlcache root' {
        foreach($p in @(& (Get-LtCleanupItem clean.steam).Paths)) {
            $p.Path | Should -Not -Match '(userdata|steamapps|shadercache|htmlcache$)'
        }
    }
}

Describe 'Epic account-data canaries' {
    BeforeEach { $sys=New-LtTestSystem; Set-LtCleanupTestRoot $sys.Root; $savedLocal=$env:LOCALAPPDATA; $env:LOCALAPPDATA=$sys.Root }
    AfterEach { $env:LOCALAPPDATA=$savedLocal; Set-LtCleanupTestRoot $null; Remove-LtTestSystem $sys }
    It 'Deletes cache leaves while preserving cookies and similarly named backup folders' {
        $base=Join-Path $sys.Root 'EpicGamesLauncher/Saved'
        foreach($path in @('webcache_4430/Cache','webcache_4430/Local Storage','webcache_backup/Cache')) {
            [void](New-Item -ItemType Directory -Path (Join-Path $base $path) -Force)
        }
        $cache=Join-Path $base 'webcache_4430/Cache/temp.bin'
        $cookie=Join-Path $base 'webcache_4430/Cookies'
        $login=Join-Path $base 'webcache_4430/Local Storage/account.bin'
        $backup=Join-Path $base 'webcache_backup/Cache/keep.bin'
        foreach($path in @($cache,$cookie,$login,$backup)) { [IO.File]::WriteAllText($path,'canary') }
        $specs=@(& (Get-LtCleanupItem clean.epic).Paths)
        $item=@{Id='test.epic';Title='Epic';Paths={ $specs }.GetNewClosure()}
        (Invoke-LtCleanupItem -Item $item -Context $sys.Ctx).Status | Should -Be Success
        Test-Path $cache | Should -BeFalse
        foreach($path in @($cookie,$login,$backup)) { Test-Path $path | Should -BeTrue }
    }
}
