#Requires -Modules Pester
# Temizlik önizlemesi: salt okunur sayım/boyut. Silme ile aynı seçim kuralları;
# uygulama kapatmaz, bakım komutu çalıştırmaz, dosya değiştirmez. Silme anında
# yol/kapsam/bağlantı kontrolleri yeniden yapılır. Gerçek dosyalar YALNIZCA ayrılmış
# geçici test kökünde (lt-test-*) oluşturulur.

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')

    function New-LtPreviewTree([string]$Root) {
        $c = Join-Path $Root 'cache'
        foreach ($d in @('a/b', 'old')) { [void](New-Item -ItemType Directory -Path (Join-Path $c $d) -Force) }
        [IO.File]::WriteAllText((Join-Path $c '1.tmp'), ('x' * 100))
        [IO.File]::WriteAllText((Join-Path $c 'a/2.tmp'), ('y' * 50))
        [IO.File]::WriteAllText((Join-Path $c 'a/b/3.log'), ('z' * 25))
        $old = Join-Path $c 'old/4.log'
        [IO.File]::WriteAllText($old, ('w' * 10))
        [IO.File]::SetLastWriteTimeUtc($old, [DateTime]::UtcNow.AddDays(-30))
        return $c
    }
    function Get-LtTreeSnapshot([string]$Root) {
        @(Get-ChildItem -LiteralPath $Root -Recurse -Force | Sort-Object FullName | ForEach-Object {
            '{0}|{1}|{2}' -f $_.FullName, $(if ($_.PSIsContainer) { 'd' } else { $_.Length }), $_.LastWriteTimeUtc.Ticks
        })
    }
    $script:SideEffectFns = @('Remove-LtFolderContents', 'Remove-LtFileSafe', 'Stop-LtProcessSafe', 'Invoke-LtNative', 'Clear-LtRecycleBin',
        'Invoke-LtDeliveryOptimizationCleanup', 'Start-LtProcessAndWait', 'Stop-LtServiceSafe', 'Start-LtServiceSafe', 'Set-LtRegValue', 'Invoke-LtMemoryList')
}

Describe 'Önizleme sayımı silme ile tutarlıdır (test kökü)' {
    BeforeEach { $sys = New-LtTestSystem; Set-LtCleanupTestRoot $sys.Root }
    AfterEach { Set-LtCleanupTestRoot $null; Remove-LtTestSystem $sys }

    It 'Filtre, alt klasör ve yaş kurallarıyla <Name> önizlemesi sonraki silmeyle aynı sayıyı verir ve hiçbir şeyi değiştirmez' -ForEach @(
        @{ Name = 'tüm içerik';      Filter = '*';     Recurse = $true;  Days = 0 }
        @{ Name = 'yalnız *.log';    Filter = '*.log'; Recurse = $true;  Days = 0 }
        @{ Name = 'üst klasör';      Filter = '*';     Recurse = $false; Days = 0 }
        @{ Name = '7 günden eski';   Filter = '*';     Recurse = $true;  Days = 7 }
    ) {
        $cache = New-LtPreviewTree $sys.Root
        $spec = "@(@{ Path = '$cache'; Label = 'c'; Filter = '$Filter'; Recurse = `$$Recurse; OlderThanDays = $Days })"
        $item = @{ Id = 't.prev'; Title = 'prev'; Paths = [scriptblock]::Create($spec) }
        $before = Get-LtTreeSnapshot $sys.Root
        $p = Get-LtCleanupItemPreview -Item $item -Context $sys.Ctx
        Get-LtTreeSnapshot $sys.Root | Should -Be $before
        $p.Status | Should -Be 'Ready'
        $p.Complete | Should -BeTrue
        $r = Invoke-LtCleanupItem -Item $item -Context $sys.Ctx
        $r.BytesFreed | Should -Be $p.Bytes
        $r.Message | Should -Match ("\($($p.Files) dosya\)|yoktu")
        $p.Targets[0].Scope | Should -Match 'bağlantılar'
    }

    It 'Bağlantılar (symlink) sayılmaz ve silmede izlenmez' -Skip:($IsWindows -ne $false) {
        $cache = New-LtPreviewTree $sys.Root
        $outside = Join-Path $sys.Root 'korunan'
        [void](New-Item -ItemType Directory -Path $outside)
        [IO.File]::WriteAllText((Join-Path $outside 'onemli.txt'), ('k' * 999))
        [void](New-Item -ItemType SymbolicLink -Path (Join-Path $cache 'link-dir') -Target $outside)
        $item = @{ Id = 't.link'; Title = 'link'; Paths = [scriptblock]::Create("@(@{ Path = '$cache'; Label = 'c' })") }
        $p = Get-LtCleanupItemPreview -Item $item -Context $sys.Ctx
        $p.Bytes | Should -Be 185
        $p.Targets[0].Note | Should -Match 'bağlantı atlandı'
        [void](Invoke-LtCleanupItem -Item $item -Context $sys.Ctx)
        Test-Path -LiteralPath (Join-Path $outside 'onemli.txt') | Should -BeTrue
    }

    It 'Sınır dışı yol taranmaz, sayılmaz ve öğe eksik olarak işaretlenir' {
        $cache = New-LtPreviewTree $sys.Root
        $outside = Join-Path ([IO.Path]::GetTempPath()) ('lt-outside-' + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $outside)
        try {
            [IO.File]::WriteAllText((Join-Path $outside 'a.tmp'), ('o' * 500))
            $item = @{ Id = 't.oos'; Title = 'oos'; Paths = [scriptblock]::Create("@(@{ Path = '$cache'; Label = 'iç' }, @{ Path = '$outside'; Label = 'dış' })") }
            $p = Get-LtCleanupItemPreview -Item $item -Context $sys.Ctx
            ($p.Targets | Where-Object Label -eq 'dış').State | Should -Be 'OutOfScope'
            ($p.Targets | Where-Object Label -eq 'dış').Note | Should -Match 'güvenlik sınırı'
            $p.Bytes | Should -Be 185
            $p.Complete | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $outside 'a.tmp') | Should -BeTrue
        } finally { Remove-Item -LiteralPath $outside -Recurse -Force }
    }

    It 'Erişim hatası taranamayan alan olarak gösterilir; sayı "en az" kabul edilir' {
        $cache = New-LtPreviewTree $sys.Root
        Mock -ModuleName LivnTools -CommandName Get-LtDirFiles -ParameterFilter { $Directory.Name -eq 'b' } -MockWith { throw [UnauthorizedAccessException]'Erişim engellendi' }
        $item = @{ Id = 't.acl'; Title = 'acl'; Paths = [scriptblock]::Create("@(@{ Path = '$cache'; Label = 'c' })") }
        $p = Get-LtCleanupItemPreview -Item $item -Context $sys.Ctx
        $p.Targets[0].State | Should -Be 'Partial'
        $p.Targets[0].Note | Should -Match 'erişim hatası'
        $p.Bytes | Should -Be 160
        $p.Complete | Should -BeFalse
    }

    It 'Hedef bloğu hata verirse öğe "okunamadı" olur, diğer öğeler sürer' {
        $cache = New-LtPreviewTree $sys.Root
        $bad = @{ Id = 't.bad'; Title = 'bad'; Paths = { throw 'Kayıt defteri okunamadı' } }
        $p = Get-LtCleanupItemPreview -Item $bad -Context $sys.Ctx
        $p.Status | Should -Be 'Error'
        $p.Message | Should -Match 'Kayıt defteri'
    }

    It 'Önizleme ile silme arasında hedef bağlantıya çevrilirse silme reddedilir (yeniden denetim)' -Skip:($IsWindows -ne $false) {
        $cache = New-LtPreviewTree $sys.Root
        $outside = Join-Path $sys.Root 'kisisel'
        [void](New-Item -ItemType Directory -Path $outside)
        [IO.File]::WriteAllText((Join-Path $outside 'belge.txt'), 'kişisel veri')
        $item = @{ Id = 't.race'; Title = 'race'; Paths = [scriptblock]::Create("@(@{ Path = '$cache'; Label = 'c' })") }
        (Get-LtCleanupItemPreview -Item $item -Context $sys.Ctx).Files | Should -Be 4
        Remove-Item -LiteralPath $cache -Recurse -Force
        [void](New-Item -ItemType SymbolicLink -Path $cache -Target $outside)
        $r = Invoke-LtCleanupItem -Item $item -Context $sys.Ctx
        $r.Status | Should -Be 'Failed'
        $r.Message | Should -Match 'bağlantı'
        Test-Path -LiteralPath (Join-Path $outside 'belge.txt') | Should -BeTrue
    }

    It 'Önizlemeden sonra eklenen dosya silme anındaki yeniden taramaya girer (önizleme bağlayıcı değildir)' {
        $cache = New-LtPreviewTree $sys.Root
        $item = @{ Id = 't.new'; Title = 'new'; Paths = [scriptblock]::Create("@(@{ Path = '$cache'; Label = 'c' })") }
        $p = Get-LtCleanupItemPreview -Item $item -Context $sys.Ctx
        [IO.File]::WriteAllText((Join-Path $cache 'sonradan.tmp'), ('n' * 15))
        (Invoke-LtCleanupItem -Item $item -Context $sys.Ctx).BytesFreed | Should -Be ($p.Bytes + 15)
    }

    It 'İptal: kalan öğeler taranmaz ve sonuç eksik işaretlenir' {
        [void](New-LtPreviewTree $sys.Root)
        Mock -ModuleName LivnTools -CommandName Measure-LtFolderContents -MockWith { throw 'taranmamalıydı' }
        $r = Get-LtCleanupPreview -Ids @('clean.temp-user', 'clean.thumbcache') -Context $sys.Ctx -Cancel @{ Requested = $true }
        @($r.Items | Where-Object Status -ne 'Cancelled').Count | Should -Be 0
        $r.Cancelled | Should -BeTrue
        $r.Complete | Should -BeFalse
        Should -Invoke -ModuleName LivnTools -CommandName Measure-LtFolderContents -Times 0 -Exactly
    }

    It 'Tüm katalog önizlemesi: dosya silmez, uygulama kapatmaz, servis/komut/kayıt değiştirmez' {
        $sys.Mem.Processes = @(@{ Name = 'chrome'; HasWindow = $true })
        foreach ($fn in $script:SideEffectFns) { Mock -ModuleName LivnTools -CommandName $fn -MockWith { throw 'YAN ETKİ: önizlemede çağrıldı' } }
        $before = Get-LtTreeSnapshot $sys.Root
        $callsBefore = @($sys.Mem.Calls).Count
        $ids = @(Get-LtCleanupCatalog -Refresh | ForEach-Object { $_.Id })
        $r = Get-LtCleanupPreview -Ids $ids -Context $sys.Ctx
        @($r.Items).Count | Should -Be $ids.Count
        foreach ($fn in $script:SideEffectFns) { Should -Invoke -ModuleName LivnTools -CommandName $fn -Times 0 -Exactly }
        Get-LtTreeSnapshot $sys.Root | Should -Be $before
        @($sys.Mem.Processes | Where-Object Name -eq 'chrome').Count | Should -Be 1
        @(@($sys.Mem.Calls)[$callsBefore..(@($sys.Mem.Calls).Count)] | Where-Object { $_ -and $_ -notlike 'Registry.Get*' }).Count | Should -Be 0
        (($r.Items | Where-Object Id -eq 'clean.chrome').Notes -join ' ') | Should -Match 'Açık: chrome'
    }

    It 'Bakım işlemleri için sayı uydurulmaz' {
        $r = Get-LtCleanupPreview -Ids @('clean.dns', 'clean.recyclebin', 'adv.sfc', 'adv.component-cleanup', 'clean.eventlogs') -Context $sys.Ctx
        foreach ($x in $r.Items) {
            $x.Kind | Should -Be 'Maintenance' -Because $x.Id
            $x.Bytes | Should -Be 0
            $x.Complete | Should -BeFalse
            ($x.Notes -join ' ') | Should -Match 'tahmin gösterilmez'
        }
        $r.Complete | Should -BeFalse
    }

    It 'Doğrulanmış güvenli kapsamı olmayan EA, Battle.net ve Xbox taranmaz' {
        $r = Get-LtCleanupPreview -Ids @('clean.ea', 'clean.battlenet', 'clean.xbox') -Context $sys.Ctx
        foreach ($x in $r.Items) { $x.Status | Should -Be 'NotSupported'; @($x.Targets).Count | Should -Be 0 }
    }
}

Describe 'Başlatıcı hesap verisi önizlemede de korunur' {
    BeforeEach { $sys = New-LtTestSystem; Set-LtCleanupTestRoot $sys.Root; $savedLocal = $env:LOCALAPPDATA; $env:LOCALAPPDATA = $sys.Root }
    AfterEach { $env:LOCALAPPDATA = $savedLocal; Set-LtCleanupTestRoot $null; Remove-LtTestSystem $sys }

    It 'Epic: yalnız Cache/Code Cache/GPUCache sayılır; Cookies ve Local Storage korunur' {
        $base = Join-Path $sys.Root 'EpicGamesLauncher/Saved'
        foreach ($path in @('webcache_4430/Cache', 'webcache_4430/Local Storage', 'webcache_4430/Code Cache')) { [void](New-Item -ItemType Directory -Path (Join-Path $base $path) -Force) }
        [IO.File]::WriteAllText((Join-Path $base 'webcache_4430/Cache/c.bin'), ('c' * 40))
        [IO.File]::WriteAllText((Join-Path $base 'webcache_4430/Code Cache/k.bin'), ('k' * 20))
        [IO.File]::WriteAllText((Join-Path $base 'webcache_4430/Local Storage/session.db'), ('s' * 300))
        [IO.File]::WriteAllText((Join-Path $base 'webcache_4430/Cookies'), ('x' * 700))
        $item = Get-LtCleanupItem 'clean.epic'
        $copy = @{}; foreach ($k in $item.Keys) { $copy[$k] = $item[$k] }; $copy.Remove('Detect')
        $p = Get-LtCleanupItemPreview -Item $copy -Context $sys.Ctx
        $p.Bytes | Should -Be 60
        $p.Keeps | Should -Match 'Cookies'
        [void](Invoke-LtCleanupItem -Item $copy -Context $sys.Ctx)
        Test-Path -LiteralPath (Join-Path $base 'webcache_4430/Local Storage/session.db') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $base 'webcache_4430/Cookies') | Should -BeTrue
    }
}

Describe 'Kuru çalışmada önizleme gerçek dosya sistemini taramaz' {
    BeforeEach { $sys = New-LtTestSystem }
    AfterEach { Remove-LtTestSystem $sys }

    It 'Öğeler "Kuru çalışma" olarak döner; hedef blokları değerlendirilmez, tarama yapılmaz' {
        Mock -ModuleName LivnTools -CommandName Measure-LtFolderContents -MockWith { throw 'taranmamalıydı' }
        $global:LtPreviewProbe = 0
        try {
            $probe = @{ Id = 't.probe'; Title = 'probe'; Paths = { $global:LtPreviewProbe++; @(@{ Path = $env:TEMP; Label = 'x' }) } }
            $p = Get-LtCleanupItemPreview -Item $probe -Context $sys.Ctx
            $p.Status | Should -Be 'Simulated'
            $global:LtPreviewProbe | Should -Be 0
            $r = Get-LtCleanupPreview -Ids @('clean.temp-user', 'clean.chrome', 'clean.dns') -Context $sys.Ctx
            $r.Simulated | Should -BeTrue
            @($r.Items | Where-Object { $_.Status -notin @('Simulated', 'NotSupported') }).Count | Should -Be 0
            Should -Invoke -ModuleName LivnTools -CommandName Measure-LtFolderContents -Times 0 -Exactly
            @(Get-LtBlockedOperations).Count | Should -Be 0
        } finally { Remove-Variable -Name LtPreviewProbe -Scope Global -ErrorAction SilentlyContinue }
    }
}

Describe 'Önizleme arayüz akışı (gerçek arka plan runspace)' {
    BeforeAll {
        $src = Join-Path $script:RepoRoot 'src/UI'
        . (Join-Path $src 'ViewModels.ps1')
        . (Join-Path $src 'Dialogs.ps1')
        . (Join-Path $src 'App.ps1')
        Initialize-LtViewModels
        $script:DialogLog = New-Object System.Collections.ArrayList
        function Show-LtReportDialog { param($Owner, $Title, $Head, $Intro, $Rows, $Mode, $OkText, [switch]$ShowRestorePoint, $RestorePointDefault, [switch]$RequireConsent, $Foot, $OkEnabled)
            [void]$script:DialogLog.Add([pscustomobject]@{ Title = $Title; Head = $Head; Intro = $Intro; Foot = $Foot; Rows = @($Rows); Mode = $Mode })
            return @{ Confirmed = $false } }
    }
    BeforeEach {
        $sys = New-LtTestSystem
        $queue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
        Initialize-LivnTools -DataRoot $sys.Root -Backend Memory -LogQueue $queue
        $controls = @{}
        foreach ($n in @('TxtStatus', 'LogBox', 'ProgressPanel', 'BtnCancel', 'TxtProgress', 'ProgMain')) {
            $o = [pscustomobject]@{ Text = ''; Content = ''; IsEnabled = $true; Visibility = 'Visible'; Value = 0; IsIndeterminate = $false }
            $o | Add-Member -MemberType ScriptMethod -Name AppendText -Value { param($t) $this.Text += $t }
            $o | Add-Member -MemberType ScriptMethod -Name ScrollToEnd -Value { }
            $controls[$n] = $o
        }
        $script:Ui = @{ Window = $null; C = $controls; LogQueue = $queue; DataRoot = (Get-LtDataRoot); AppRoot = $script:RepoRoot
            ModulePath = (Join-Path $script:RepoRoot 'src/LivnTools.psm1'); Job = $null; WorkerRS = $null; Ctx = $sys.Ctx
            RefreshQueue = (New-Object System.Collections.ArrayList); Cleanups = @{}; CleanupGroups = @{}; CleanupInit = $false; CurrentPage = 'QuickClean' }
        New-LtCleanupItems
        foreach ($vm in $script:Ui.Cleanups.Values) { $vm.IsAvailable = $true; $vm.Selected = $false }
        foreach ($id in @('clean.temp-user', 'clean.dns')) { $script:Ui.Cleanups[$id].Selected = $true }
        $script:DialogLog.Clear()
    }
    AfterEach {
        if ($script:Ui.WorkerRS) { $script:Ui.WorkerRS.Dispose() }
        Remove-LtTestSystem $sys
    }

    It 'Kuru çalışmada önizleme penceresi taranmadığını, geri alma garantisi olmadığını açıkça söyler' {
        Invoke-LtCleanupPreviewFlow -Page 'QuickClean'
        $deadline = (Get-Date).AddSeconds(60)
        while ($script:Ui.Job -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 100; Complete-LtJobIfDone }
        $script:DialogLog.Count | Should -Be 1
        $d = $script:DialogLog[0]
        $d.Mode | Should -Be 'Info'
        $d.Head | Should -Match 'Kuru çalışma'
        $d.Intro | Should -Match 'hiçbir dosyayı silmedi'
        $d.Foot | Should -Match 'GERİ ALINAMAZ'
        $d.Foot | Should -Match 'geri alma garantisi değildir'
        @($d.Rows | Where-Object { $_.KindText -eq 'Kuru çalışma' }).Count | Should -Be 2
    }

    It 'Seçim yokken iş başlatılmaz' {
        foreach ($vm in $script:Ui.Cleanups.Values) { $vm.Selected = $false }
        Invoke-LtCleanupPreviewFlow -Page 'QuickClean'
        $script:Ui.Job | Should -BeNullOrEmpty
        $controls.TxtStatus.Text | Should -Match 'seçin'
    }

    It 'Satır biçimi: taranan hedef, kapsam, korunan veri ve sınır dışı alan gösterilir' {
        $item = [pscustomobject]@{ Id = 'x'; Title = 'X'; Kind = 'Files'; Status = 'Ready'; Message = ''; Files = 3; Bytes = [long]2048; Complete = $false; Keeps = 'Hesap'
            Notes = @('Açık: x.'); RunningApps = @('x')
            Targets = @([pscustomobject]@{ Label = 'Cache'; Path = 'p'; Scope = 'alt klasörler dahil'; State = 'Scanned'; Files = 3; Bytes = [long]2048; Note = '' },
                        [pscustomobject]@{ Label = 'Dış'; Path = 'q'; Scope = ''; State = 'OutOfScope'; Files = 0; Bytes = [long]0; Note = 'güvenlik sınırı dışında; taranmadı ve silinmez' }) }
        $row = @(ConvertTo-LtCleanupPreviewRows @($item))[0]
        $row.Kind | Should -Be 'Partial'
        $row.KindText | Should -Match 'en az'
        $row.Changes | Should -Match 'Cache: 3 dosya, 2 KB — alt klasörler dahil'
        $row.Changes | Should -Match 'Dış: güvenlik sınırı'
        $row.Changes | Should -Match 'Korunur: Hesap'
    }
}
