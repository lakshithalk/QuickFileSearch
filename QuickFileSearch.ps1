# QuickFileSearch - small Windows file search tool (PowerShell + WinForms, no dependencies)
# Search any folder or all drives by name, filtered by basic file type categories.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ---------------------------------------------------------------- file type categories
$script:Categories = [ordered]@{
    'Documents'   = @('.doc','.docx','.xls','.xlsx','.ppt','.pptx','.pdf','.txt','.rtf','.odt','.ods','.odp','.csv','.md')
    'Images'      = @('.jpg','.jpeg','.png','.gif','.bmp','.tif','.tiff','.webp','.svg','.ico','.heic','.raw','.psd')
    'Videos'      = @('.mp4','.mkv','.avi','.mov','.wmv','.flv','.webm','.m4v','.mpg','.mpeg','.3gp')
    'Audio'       = @('.mp3','.wav','.flac','.aac','.ogg','.wma','.m4a','.opus','.mid')
    'Archives'    = @('.zip','.rar','.7z','.tar','.gz','.bz2','.xz','.iso','.cab')
    'Code'        = @('.ps1','.py','.js','.ts','.html','.css','.json','.xml','.yaml','.yml','.c','.cpp','.h','.cs','.java','.go','.rs','.php','.sql','.sh','.bat','.cmd','.vb')
    'Executables' = @('.exe','.msi','.dll','.com','.scr','.appx')
}

# ---------------------------------------------------------------- helpers
function Format-Size([long]$bytes) {
    if ($bytes -ge 1GB) { return ('{0:N2} GB' -f ($bytes / 1GB)) }
    if ($bytes -ge 1MB) { return ('{0:N2} MB' -f ($bytes / 1MB)) }
    if ($bytes -ge 1KB) { return ('{0:N1} KB' -f ($bytes / 1KB)) }
    return "$bytes B"
}

function Get-CategoryName([string]$ext) {
    foreach ($k in $script:Categories.Keys) {
        if ($script:Categories[$k] -contains $ext) { return $k }
    }
    if ($ext) { return $ext.TrimStart('.').ToUpper() }
    return 'File'
}

# ---------------------------------------------------------------- form
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Quick File Search'
$form.Size = New-Object System.Drawing.Size(1000, 640)
$form.MinimumSize = New-Object System.Drawing.Size(760, 480)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

# Row 1: location
$lblWhere = New-Object System.Windows.Forms.Label
$lblWhere.Text = 'Look in:'
$lblWhere.Location = New-Object System.Drawing.Point(12, 15)
$lblWhere.AutoSize = $true

$cmbWhere = New-Object System.Windows.Forms.ComboBox
$cmbWhere.Location = New-Object System.Drawing.Point(80, 11)
$cmbWhere.Size = New-Object System.Drawing.Size(300, 24)
$cmbWhere.DropDownStyle = 'DropDown'
$cmbWhere.Anchor = 'Top,Left'
[void]$cmbWhere.Items.Add('All drives')
Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match '^[A-Z]:\\$' } | ForEach-Object {
    [void]$cmbWhere.Items.Add($_.Root)
}
[void]$cmbWhere.Items.Add([Environment]::GetFolderPath('UserProfile'))
[void]$cmbWhere.Items.Add([Environment]::GetFolderPath('Desktop'))
[void]$cmbWhere.Items.Add([Environment]::GetFolderPath('MyDocuments'))
[void]$cmbWhere.Items.Add((Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads'))
$cmbWhere.SelectedIndex = 0

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = 'Browse...'
$btnBrowse.Location = New-Object System.Drawing.Point(386, 10)
$btnBrowse.Size = New-Object System.Drawing.Size(80, 26)

# Row 2: search term
$lblName = New-Object System.Windows.Forms.Label
$lblName.Text = 'Name:'
$lblName.Location = New-Object System.Drawing.Point(12, 47)
$lblName.AutoSize = $true

$txtName = New-Object System.Windows.Forms.TextBox
$txtName.Location = New-Object System.Drawing.Point(80, 43)
$txtName.Size = New-Object System.Drawing.Size(300, 24)

$btnSearch = New-Object System.Windows.Forms.Button
$btnSearch.Text = 'Search'
$btnSearch.Location = New-Object System.Drawing.Point(386, 42)
$btnSearch.Size = New-Object System.Drawing.Size(80, 26)

$btnStop = New-Object System.Windows.Forms.Button
$btnStop.Text = 'Stop'
$btnStop.Location = New-Object System.Drawing.Point(472, 42)
$btnStop.Size = New-Object System.Drawing.Size(60, 26)
$btnStop.Enabled = $false

$lblHint = New-Object System.Windows.Forms.Label
$lblHint.Text = 'Tip: partial names work ("report"), wildcards too ("*.pdf", "inv??ce*"). Leave empty to list all files of the chosen types.'
$lblHint.Location = New-Object System.Drawing.Point(80, 70)
$lblHint.AutoSize = $true
$lblHint.ForeColor = [System.Drawing.Color]::Gray

# Type category checkboxes
$grpTypes = New-Object System.Windows.Forms.GroupBox
$grpTypes.Text = 'File types'
$grpTypes.Location = New-Object System.Drawing.Point(550, 8)
$grpTypes.Size = New-Object System.Drawing.Size(420, 82)
$grpTypes.Anchor = 'Top,Right'

$chkAll = New-Object System.Windows.Forms.CheckBox
$chkAll.Text = 'All types'
$chkAll.Location = New-Object System.Drawing.Point(10, 18)
$chkAll.AutoSize = $true
$chkAll.Checked = $true
$grpTypes.Controls.Add($chkAll)

$script:TypeChecks = @()
$i = 0
foreach ($name in $script:Categories.Keys) {
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text = $name
    $cb.AutoSize = $true
    $col = ($i + 1) % 4
    $row = [math]::Floor(($i + 1) / 4)
    $cb.Location = New-Object System.Drawing.Point((10 + $col * 100), (18 + $row * 24))
    $cb.Enabled = $false
    $grpTypes.Controls.Add($cb)
    $script:TypeChecks += $cb
    $i++
}

$chkAll.Add_CheckedChanged({
    foreach ($cb in $script:TypeChecks) { $cb.Enabled = -not $chkAll.Checked }
})

# Options row
$chkSubfolders = New-Object System.Windows.Forms.CheckBox
$chkSubfolders.Text = 'Include subfolders'
$chkSubfolders.Location = New-Object System.Drawing.Point(12, 96)
$chkSubfolders.AutoSize = $true
$chkSubfolders.Checked = $true

$chkSkipSystem = New-Object System.Windows.Forms.CheckBox
$chkSkipSystem.Text = 'Skip Windows / Program Files / hidden folders (faster)'
$chkSkipSystem.Location = New-Object System.Drawing.Point(150, 96)
$chkSkipSystem.AutoSize = $true
$chkSkipSystem.Checked = $true

# Results
$lv = New-Object System.Windows.Forms.ListView
$lv.Location = New-Object System.Drawing.Point(12, 122)
$lv.Size = New-Object System.Drawing.Size(960, 440)
$lv.Anchor = 'Top,Bottom,Left,Right'
$lv.View = 'Details'
$lv.FullRowSelect = $true
$lv.GridLines = $true
$lv.MultiSelect = $false
[void]$lv.Columns.Add('Name', 260)
[void]$lv.Columns.Add('Type', 90)
[void]$lv.Columns.Add('Size', 90, 'Right')
[void]$lv.Columns.Add('Modified', 130)
[void]$lv.Columns.Add('Folder', 380)

# Context menu
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$miOpen = $menu.Items.Add('Open')
$miFolder = $menu.Items.Add('Open containing folder')
$miCopy = $menu.Items.Add('Copy full path')
$lv.ContextMenuStrip = $menu

# Status bar
$status = New-Object System.Windows.Forms.StatusStrip
$statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusLabel.Text = 'Ready'
$statusLabel.Spring = $true
$statusLabel.TextAlign = 'MiddleLeft'
[void]$status.Items.Add($statusLabel)

$form.Controls.AddRange(@($lblWhere, $cmbWhere, $btnBrowse, $lblName, $txtName, $btnSearch, $btnStop, $lblHint, $grpTypes, $chkSubfolders, $chkSkipSystem, $lv, $status))
$form.AcceptButton = $btnSearch

# ---------------------------------------------------------------- actions
function Get-SelectedPath {
    if ($lv.SelectedItems.Count -eq 0) { return $null }
    return $lv.SelectedItems[0].Tag
}

$openItem = {
    $p = Get-SelectedPath
    if ($p -and (Test-Path -LiteralPath $p)) { Start-Process -FilePath $p }
}
$openFolder = {
    $p = Get-SelectedPath
    if ($p -and (Test-Path -LiteralPath $p)) { Start-Process explorer.exe -ArgumentList "/select,`"$p`"" }
}
$copyPath = {
    $p = Get-SelectedPath
    if ($p) { [System.Windows.Forms.Clipboard]::SetText($p) }
}

$lv.Add_DoubleClick($openItem)
$miOpen.Add_Click($openItem)
$miFolder.Add_Click($openFolder)
$miCopy.Add_Click($copyPath)
$lv.Add_KeyDown({
    if ($_.KeyCode -eq 'Return') { & $openItem }
    if ($_.Control -and $_.KeyCode -eq 'C') { & $copyPath }
})

$btnBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Choose a folder to search'
    if ($dlg.ShowDialog() -eq 'OK') { $cmbWhere.Text = $dlg.SelectedPath }
})

# ---------------------------------------------------------------- background search
$script:Runspace = $null
$script:Handle = $null
$script:PS = $null
$script:Results = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
$script:State = [hashtable]::Synchronized(@{ Stop = $false; Scanned = 0; Done = $false; Error = '' })

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 200

$searchBlock = {
    param($Roots, $Pattern, $Exts, $Recurse, $SkipSystem, $Queue, $State)

    $skipNames = @('Windows', 'Program Files', 'Program Files (x86)', 'ProgramData', '$Recycle.Bin', 'System Volume Information', 'AppData', 'node_modules', '.git')
    $useWild = $Pattern -match '[\*\?]'
    if ($useWild) { $filter = $Pattern } else { $filter = "*$Pattern*" }
    $extSet = $null
    if ($Exts -and $Exts.Count -gt 0) {
        $extSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($e in $Exts) { [void]$extSet.Add($e) }
    }

    $stack = [System.Collections.Generic.Stack[string]]::new()
    foreach ($r in $Roots) { if (Test-Path -LiteralPath $r) { $stack.Push($r) } }

    while ($stack.Count -gt 0) {
        if ($State.Stop) { break }
        $dir = $stack.Pop()
        try {
            $di = [System.IO.DirectoryInfo]$dir
            foreach ($f in $di.EnumerateFiles($filter)) {
                $State.Scanned++
                if ($extSet -and -not $extSet.Contains($f.Extension)) { continue }
                $Queue.Enqueue([pscustomobject]@{
                    Name = $f.Name; Ext = $f.Extension; Size = $f.Length
                    Modified = $f.LastWriteTime; Dir = $f.DirectoryName; Path = $f.FullName
                })
            }
            if ($Recurse) {
                foreach ($sub in $di.EnumerateDirectories()) {
                    if ($SkipSystem) {
                        if ($skipNames -contains $sub.Name) { continue }
                        if (($sub.Attributes -band [System.IO.FileAttributes]::Hidden) -or ($sub.Attributes -band [System.IO.FileAttributes]::System)) { continue }
                    }
                    if ($sub.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { continue }
                    $stack.Push($sub.FullName)
                }
            }
        } catch { }
    }
    $State.Done = $true
}

function Stop-Search {
    $script:State.Stop = $true
    $timer.Stop()
    if ($script:PS) {
        try { $script:PS.Stop() } catch { }
        try { $script:PS.Dispose() } catch { }
        $script:PS = $null
    }
    if ($script:Runspace) {
        try { $script:Runspace.Close(); $script:Runspace.Dispose() } catch { }
        $script:Runspace = $null
    }
    $btnSearch.Enabled = $true
    $btnStop.Enabled = $false
}

function Start-Search {
    $where = $cmbWhere.Text.Trim()
    if ($where -eq 'All drives') {
        $roots = @(Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match '^[A-Z]:\\$' -and (Test-Path $_.Root) } | ForEach-Object { $_.Root })
    } elseif (Test-Path -LiteralPath $where) {
        $roots = @($where)
    } else {
        [System.Windows.Forms.MessageBox]::Show("Folder not found:`n$where", 'Quick File Search', 'OK', 'Warning') | Out-Null
        return
    }

    $exts = @()
    if (-not $chkAll.Checked) {
        foreach ($cb in $script:TypeChecks) {
            if ($cb.Checked) { $exts += $script:Categories[$cb.Text] }
        }
        if ($exts.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show('Pick at least one file type, or tick "All types".', 'Quick File Search', 'OK', 'Information') | Out-Null
            return
        }
    }

    $lv.Items.Clear()
    $script:Results = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
    $script:State = [hashtable]::Synchronized(@{ Stop = $false; Scanned = 0; Done = $false })
    $script:Found = 0
    $script:StartTime = Get-Date

    $script:Runspace = [runspacefactory]::CreateRunspace()
    $script:Runspace.ApartmentState = 'MTA'
    $script:Runspace.Open()
    $script:PS = [powershell]::Create()
    $script:PS.Runspace = $script:Runspace
    [void]$script:PS.AddScript($searchBlock).AddArgument($roots).AddArgument($txtName.Text.Trim()).AddArgument($exts).AddArgument($chkSubfolders.Checked).AddArgument($chkSkipSystem.Checked).AddArgument($script:Results).AddArgument($script:State)
    $script:Handle = $script:PS.BeginInvoke()

    $btnSearch.Enabled = $false
    $btnStop.Enabled = $true
    $statusLabel.Text = 'Searching...'
    $timer.Start()
}

$timer.Add_Tick({
    $lv.BeginUpdate()
    $item = $null
    $batch = 0
    while ($batch -lt 500 -and $script:Results.TryDequeue([ref]$item)) {
        $li = New-Object System.Windows.Forms.ListViewItem($item.Name)
        [void]$li.SubItems.Add((Get-CategoryName $item.Ext))
        [void]$li.SubItems.Add((Format-Size $item.Size))
        [void]$li.SubItems.Add($item.Modified.ToString('yyyy-MM-dd HH:mm'))
        [void]$li.SubItems.Add($item.Dir)
        $li.Tag = $item.Path
        [void]$lv.Items.Add($li)
        $script:Found++
        $batch++
    }
    $lv.EndUpdate()

    $elapsed = ((Get-Date) - $script:StartTime).TotalSeconds
    if ($script:State.Done -and $script:Results.IsEmpty) {
        Stop-Search
        $statusLabel.Text = ('Done. {0} file(s) found, {1:N0} scanned in {2:N1}s' -f $script:Found, $script:State.Scanned, $elapsed)
    } else {
        $statusLabel.Text = ('Searching... {0} found, {1:N0} scanned ({2:N0}s)' -f $script:Found, $script:State.Scanned, $elapsed)
    }
})

$btnSearch.Add_Click({ Start-Search })
$btnStop.Add_Click({ Stop-Search; $statusLabel.Text = "Stopped. $($script:Found) file(s) found." })
$form.Add_FormClosing({ Stop-Search })

$form.Add_Shown({ $txtName.Focus() })
[void]$form.ShowDialog()
