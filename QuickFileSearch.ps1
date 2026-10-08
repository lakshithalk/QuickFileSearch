# QuickFileSearch - small Windows file search tool (PowerShell + WinForms, no dependencies)
# Search any folder or all drives by name, filtered by basic file type categories.
#
# Optional launch arguments:
#   QuickFileSearch.exe -Path "D:\Projects" -Name "*.pdf" -AutoSearch
param(
    [string]$Path = '',
    [string]$Name = '',
    [switch]$AutoSearch
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ---------------------------------------------------------------- native helpers (shell icons, cue banners, DPI, sorting)
Add-Type -ReferencedAssemblies System.Drawing, System.Windows.Forms -TypeDefinition @'
using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public static class QfsNative {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct SHFILEINFO {
        public IntPtr hIcon; public int iIcon; public uint dwAttributes;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string szDisplayName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 80)] public string szTypeName;
    }
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    static extern IntPtr SHGetFileInfo(string pszPath, uint dwFileAttributes, ref SHFILEINFO psfi, uint cbFileInfo, uint uFlags);
    [DllImport("user32.dll")] static extern bool DestroyIcon(IntPtr hIcon);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern IntPtr SendMessage(IntPtr hWnd, uint msg, IntPtr wParam, string lParam);

    const uint SHGFI_ICON = 0x100, SHGFI_SMALLICON = 0x1, SHGFI_USEFILEATTRIBUTES = 0x10, SHGFI_TYPENAME = 0x400;
    const uint FILE_ATTRIBUTE_NORMAL = 0x80;

    public static Icon GetIcon(string ext, bool large) {
        SHFILEINFO s = new SHFILEINFO();
        SHGetFileInfo("file" + ext, FILE_ATTRIBUTE_NORMAL, ref s, (uint)Marshal.SizeOf(s), SHGFI_ICON | (large ? 0u : SHGFI_SMALLICON) | SHGFI_USEFILEATTRIBUTES);
        if (s.hIcon == IntPtr.Zero) return null;
        Icon ic = (Icon)Icon.FromHandle(s.hIcon).Clone();
        DestroyIcon(s.hIcon);
        return ic;
    }
    public static string GetTypeName(string ext) {
        SHFILEINFO s = new SHFILEINFO();
        SHGetFileInfo("file" + ext, FILE_ATTRIBUTE_NORMAL, ref s, (uint)Marshal.SizeOf(s), SHGFI_TYPENAME | SHGFI_USEFILEATTRIBUTES);
        return s.szTypeName;
    }
    public static void SetCue(TextBox t, string text) { SendMessage(t.Handle, 0x1501, (IntPtr)1, text); }
    public static void SetCue(ComboBox c, string text) { SendMessage(c.Handle, 0x1703, (IntPtr)1, text); }
}

public class QfsSorter : System.Collections.IComparer {
    public int Column = 0; public bool Ascending = true;
    public int Compare(object a, object b) {
        ListViewItem x = (ListViewItem)a, y = (ListViewItem)b;
        if (Column >= x.SubItems.Count || Column >= y.SubItems.Count) return 0;
        ListViewItem.ListViewSubItem sx = x.SubItems[Column], sy = y.SubItems[Column];
        int r;
        if (sx.Tag is long && sy.Tag is long) r = ((long)sx.Tag).CompareTo((long)sy.Tag);
        else r = string.Compare(sx.Text, sy.Text, StringComparison.CurrentCultureIgnoreCase);
        return Ascending ? r : -r;
    }
}
'@

[void][QfsNative]::SetProcessDPIAware()
[System.Windows.Forms.Application]::EnableVisualStyles()

# ---------------------------------------------------------------- DPI scaling (layout below is designed at 100%)
$script:Scale = 1.0
try { $g = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero); $script:Scale = $g.DpiX / 96.0; $g.Dispose() } catch { }
function S([double]$v) { return [int][math]::Round($v * $script:Scale) }
function P($x, $y) { return New-Object System.Drawing.Point((S $x), (S $y)) }
function Z($w, $h) { return New-Object System.Drawing.Size((S $w), (S $h)) }
function Pad($l, $t, $r, $b) { return New-Object System.Windows.Forms.Padding((S $l), (S $t), (S $r), (S $b)) }

# ---------------------------------------------------------------- file type categories (edit freely)
$script:Categories = [ordered]@{
    'Documents'   = @('.doc','.docx','.xls','.xlsx','.ppt','.pptx','.pdf','.txt','.rtf','.odt','.ods','.odp','.csv','.md')
    'Images'      = @('.jpg','.jpeg','.png','.gif','.bmp','.tif','.tiff','.webp','.svg','.ico','.heic','.raw','.psd')
    'Videos'      = @('.mp4','.mkv','.avi','.mov','.wmv','.flv','.webm','.m4v','.mpg','.mpeg','.3gp')
    'Audio'       = @('.mp3','.wav','.flac','.aac','.ogg','.wma','.m4a','.opus','.mid')
    'Archives'    = @('.zip','.rar','.7z','.tar','.gz','.bz2','.xz','.iso','.cab')
    'Code'        = @('.ps1','.py','.js','.ts','.html','.css','.json','.xml','.yaml','.yml','.c','.cpp','.h','.cs','.java','.go','.rs','.php','.sql','.sh','.bat','.cmd','.vb')
    'Executables' = @('.exe','.msi','.dll','.com','.scr','.appx')
}

$script:SizeFilters = [ordered]@{
    'Any size'   = 0
    'Over 1 MB'  = 1MB
    'Over 10 MB' = 10MB
    'Over 100 MB'= 100MB
    'Over 1 GB'  = 1GB
}
$script:DateFilters = [ordered]@{
    'Any time'     = 0
    'Today'        = 1
    'Last 7 days'  = 7
    'Last 30 days' = 30
    'Last year'    = 365
}

# ---------------------------------------------------------------- theme
$Accent     = [System.Drawing.Color]::FromArgb(0, 120, 212)
$AccentDark = [System.Drawing.Color]::FromArgb(0, 90, 160)
$Surface    = [System.Drawing.Color]::White
$Canvas     = [System.Drawing.Color]::FromArgb(243, 243, 243)
$TextMuted  = [System.Drawing.Color]::FromArgb(110, 110, 110)
$RowAlt     = [System.Drawing.Color]::FromArgb(249, 249, 249)
$UiFont     = New-Object System.Drawing.Font('Segoe UI', 10)
$BigFont    = New-Object System.Drawing.Font('Segoe UI', 12)
$SmallFont  = New-Object System.Drawing.Font('Segoe UI', 9)

# ---------------------------------------------------------------- settings persistence
$script:SettingsDir  = Join-Path $env:APPDATA 'QuickFileSearch'
$script:SettingsFile = Join-Path $script:SettingsDir 'settings.json'
function Load-Settings {
    try { if (Test-Path $script:SettingsFile) { return Get-Content $script:SettingsFile -Raw | ConvertFrom-Json } } catch { }
    return $null
}
function Save-Settings($obj) {
    try {
        if (-not (Test-Path $script:SettingsDir)) { New-Item -ItemType Directory -Path $script:SettingsDir | Out-Null }
        $obj | ConvertTo-Json | Set-Content $script:SettingsFile -Encoding UTF8
    } catch { }
}

# ---------------------------------------------------------------- helpers
function Format-Size([long]$bytes) {
    if ($bytes -ge 1GB) { return ('{0:N2} GB' -f ($bytes / 1GB)) }
    if ($bytes -ge 1MB) { return ('{0:N2} MB' -f ($bytes / 1MB)) }
    if ($bytes -ge 1KB) { return ('{0:N1} KB' -f ($bytes / 1KB)) }
    return "$bytes B"
}

$script:IconKeys = @{}
$script:TypeNames = @{}
function Get-IconKey([string]$ext) {
    $k = $ext.ToLower(); if (-not $k) { $k = '.' }
    if (-not $script:IconKeys.ContainsKey($k)) {
        $ic = [QfsNative]::GetIcon($k, ($script:Scale -gt 1.25))
        if ($ic) { $imageList.Images.Add($k, $ic); $script:IconKeys[$k] = $k } else { $script:IconKeys[$k] = '' }
    }
    return $script:IconKeys[$k]
}
function Get-TypeName([string]$ext) {
    $k = $ext.ToLower()
    if (-not $script:TypeNames.ContainsKey($k)) {
        $n = ''
        try { $n = [QfsNative]::GetTypeName($k) } catch { }
        if (-not $n) { if ($k) { $n = $k.TrimStart('.').ToUpper() + ' File' } else { $n = 'File' } }
        $script:TypeNames[$k] = $n
    }
    return $script:TypeNames[$k]
}

function New-FlatButton($text, $x, $y, $w, $h, $primary) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Location = (P $x $y)
    $b.Size = (Z $w $h)
    $b.FlatStyle = 'Flat'
    $b.Font = $UiFont
    $b.Cursor = 'Hand'
    if ($primary) {
        $b.BackColor = $Accent; $b.ForeColor = [System.Drawing.Color]::White
        $b.FlatAppearance.BorderSize = 0
        $b.FlatAppearance.MouseOverBackColor = $AccentDark
    } else {
        $b.BackColor = $Surface; $b.ForeColor = [System.Drawing.Color]::FromArgb(40, 40, 40)
        $b.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(200, 200, 200)
        $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(235, 235, 235)
    }
    return $b
}

# ---------------------------------------------------------------- form
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Quick File Search'
$form.Size = (Z 1100 700)
$form.MinimumSize = (Z 820 520)
$form.StartPosition = 'CenterScreen'
$form.Font = $UiFont
$form.BackColor = $Canvas
$form.KeyPreview = $true
# App icon: embedded in the exe (ps2exe -iconFile), or app.ico next to the script when run from source.
try {
    $icoPath = Join-Path $PSScriptRoot 'app.ico'
    if ($PSScriptRoot -and (Test-Path $icoPath)) { $form.Icon = New-Object System.Drawing.Icon($icoPath) }
    else { $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
} catch { }

# ---- header panel
$header = New-Object System.Windows.Forms.Panel
$header.Dock = 'Top'
$header.Height = (S 168)
$header.BackColor = $Surface
$header.Padding = (Pad 16 12 16 8)

$txtName = New-Object System.Windows.Forms.TextBox
$txtName.Location = (P 16 14)
$txtName.Size = (Z 760 32)
$txtName.Font = $BigFont
$txtName.Anchor = 'Top,Left,Right'
$txtName.Text = $Name

$btnSearch = New-FlatButton 'Search' 786 13 110 32 $true
$btnSearch.Anchor = 'Top,Right'
$btnStop = New-FlatButton 'Stop' 904 13 80 32 $false
$btnStop.Anchor = 'Top,Right'
$btnStop.Enabled = $false
$btnClear = New-FlatButton 'Clear' 992 13 76 32 $false
$btnClear.Anchor = 'Top,Right'

$lblWhere = New-Object System.Windows.Forms.Label
$lblWhere.Text = 'Look in'
$lblWhere.Location = (P 16 60)
$lblWhere.AutoSize = $true
$lblWhere.ForeColor = $TextMuted

$cmbWhere = New-Object System.Windows.Forms.ComboBox
$cmbWhere.Location = (P 80 56)
$cmbWhere.Size = (Z 460 28)
$cmbWhere.DropDownStyle = 'DropDown'
$cmbWhere.Font = $UiFont
[void]$cmbWhere.Items.Add('All drives')
Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match '^[A-Z]:\\$' } | ForEach-Object { [void]$cmbWhere.Items.Add($_.Root) }
foreach ($sp in @('UserProfile','Desktop','MyDocuments')) { [void]$cmbWhere.Items.Add([Environment]::GetFolderPath($sp)) }
[void]$cmbWhere.Items.Add((Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads'))
$cmbWhere.SelectedIndex = 0

$btnBrowse = New-FlatButton 'Browse...' 548 55 100 29 $false

$lblTypes = New-Object System.Windows.Forms.Label
$lblTypes.Text = 'Types'
$lblTypes.Location = (P 16 98)
$lblTypes.AutoSize = $true
$lblTypes.ForeColor = $TextMuted

$flowTypes = New-Object System.Windows.Forms.FlowLayoutPanel
$flowTypes.Location = (P 78 92)
$flowTypes.Size = (Z 1000 34)
$flowTypes.Anchor = 'Top,Left,Right'
$flowTypes.WrapContents = $false
$flowTypes.AutoScroll = $false

function New-TypeToggle($text) {
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text = $text
    $cb.Appearance = 'Button'
    $cb.FlatStyle = 'Flat'
    $cb.AutoSize = $false
    $tw = [System.Windows.Forms.TextRenderer]::MeasureText($text, $UiFont).Width
    $cb.Size = New-Object System.Drawing.Size(($tw + (S 26)), (S 30))
    $cb.TextAlign = 'MiddleCenter'
    $cb.Margin = (Pad 0 0 6 0)
    $cb.Cursor = 'Hand'
    $cb.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(200, 200, 200)
    $cb.FlatAppearance.CheckedBackColor = $Accent
    $cb.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(230, 240, 250)
    $cb.BackColor = $Surface
    $cb.Add_CheckedChanged({
        if ($this.Checked) { $this.ForeColor = [System.Drawing.Color]::White; $this.BackColor = $Accent }
        else { $this.ForeColor = [System.Drawing.Color]::FromArgb(40, 40, 40); $this.BackColor = $Surface }
    })
    return $cb
}

$chkAll = New-TypeToggle 'All types'
$chkAll.Checked = $true
$flowTypes.Controls.Add($chkAll)
$script:TypeChecks = @()
foreach ($catName in $script:Categories.Keys) {
    $cb = New-TypeToggle $catName
    $flowTypes.Controls.Add($cb)
    $script:TypeChecks += $cb
}
$script:SyncingTypes = $false
$chkAll.Add_CheckedChanged({
    if ($script:SyncingTypes) { return }
    if ($chkAll.Checked) { $script:SyncingTypes = $true; foreach ($c in $script:TypeChecks) { $c.Checked = $false }; $script:SyncingTypes = $false }
    elseif (-not ($script:TypeChecks | Where-Object Checked)) { $chkAll.Checked = $true }
})
foreach ($c in $script:TypeChecks) {
    $c.Add_CheckedChanged({
        if ($script:SyncingTypes) { return }
        $script:SyncingTypes = $true
        if ($this.Checked) { $chkAll.Checked = $false }
        elseif (-not ($script:TypeChecks | Where-Object Checked)) { $chkAll.Checked = $true }
        $script:SyncingTypes = $false
    })
}

# ---- options row
$chkSubfolders = New-Object System.Windows.Forms.CheckBox
$chkSubfolders.Text = 'Include subfolders'
$chkSubfolders.Location = (P 80 134)
$chkSubfolders.AutoSize = $true
$chkSubfolders.Checked = $true

$chkSkipSystem = New-Object System.Windows.Forms.CheckBox
$chkSkipSystem.Text = 'Skip Windows, Program Files and hidden folders'
$chkSkipSystem.Location = (P 240 134)
$chkSkipSystem.AutoSize = $true
$chkSkipSystem.Checked = $true

$lblSize = New-Object System.Windows.Forms.Label
$lblSize.Text = 'Size'; $lblSize.ForeColor = $TextMuted; $lblSize.AutoSize = $true
$lblSize.Location = (P 620 136)
$cmbSize = New-Object System.Windows.Forms.ComboBox
$cmbSize.DropDownStyle = 'DropDownList'
$cmbSize.Location = (P 656 132)
$cmbSize.Size = (Z 130 26)
foreach ($k in $script:SizeFilters.Keys) { [void]$cmbSize.Items.Add($k) }
$cmbSize.SelectedIndex = 0

$lblDate = New-Object System.Windows.Forms.Label
$lblDate.Text = 'Modified'; $lblDate.ForeColor = $TextMuted; $lblDate.AutoSize = $true
$lblDate.Location = (P 800 136)
$cmbDate = New-Object System.Windows.Forms.ComboBox
$cmbDate.DropDownStyle = 'DropDownList'
$cmbDate.Location = (P 866 132)
$cmbDate.Size = (Z 130 26)
foreach ($k in $script:DateFilters.Keys) { [void]$cmbDate.Items.Add($k) }
$cmbDate.SelectedIndex = 0

$header.Controls.AddRange(@($txtName, $btnSearch, $btnStop, $btnClear, $lblWhere, $cmbWhere, $btnBrowse, $lblTypes, $flowTypes, $chkSubfolders, $chkSkipSystem, $lblSize, $cmbSize, $lblDate, $cmbDate))

# ---- results
$imageList = New-Object System.Windows.Forms.ImageList
$imageList.ColorDepth = 'Depth32Bit'
$imageList.ImageSize = (Z 16 16)

$lv = New-Object System.Windows.Forms.ListView
$lv.Dock = 'Fill'
$lv.View = 'Details'
$lv.FullRowSelect = $true
$lv.MultiSelect = $false
$lv.HideSelection = $false
$lv.BorderStyle = 'None'
$lv.SmallImageList = $imageList
$lv.Font = $UiFont
[void]$lv.Columns.Add('Name', (S 320))
[void]$lv.Columns.Add('Type', (S 150))
[void]$lv.Columns.Add('Size', (S 100), 'Right')
[void]$lv.Columns.Add('Modified', (S 140))
[void]$lv.Columns.Add('Folder', (S 420))
$script:Sorter = New-Object QfsSorter
$lv.ListViewItemSorter = $script:Sorter
$lv.Sorting = 'None'

$lvHost = New-Object System.Windows.Forms.Panel
$lvHost.Dock = 'Fill'
$lvHost.Padding = (Pad 16 10 16 10)
$lvHost.BackColor = $Canvas
$lvHost.Controls.Add($lv)

$emptyLabel = New-Object System.Windows.Forms.Label
$emptyLabel.Text = "Type part of a file name, choose where to look and which types, then press Search.`r`nWildcards work too:  *.pdf   inv??ce*   report_2024*"
$emptyLabel.ForeColor = $TextMuted
$emptyLabel.Font = $UiFont
$emptyLabel.TextAlign = 'MiddleCenter'
$emptyLabel.Dock = 'Fill'
$emptyLabel.BackColor = $Surface
$lv.Controls.Add($emptyLabel)

# ---- context menu
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$miOpen   = $menu.Items.Add('Open')
$miFolder = $menu.Items.Add('Open containing folder')
[void]$menu.Items.Add('-')
$miCopy   = $menu.Items.Add('Copy full path')
$miCopyNm = $menu.Items.Add('Copy file name')
$lv.ContextMenuStrip = $menu

# ---- status bar
$status = New-Object System.Windows.Forms.StatusStrip
$status.SizingGrip = $false
$status.BackColor = $Surface
$statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusLabel.Text = 'Ready'
$statusLabel.Spring = $true
$statusLabel.TextAlign = 'MiddleLeft'
$progress = New-Object System.Windows.Forms.ToolStripProgressBar
$progress.Style = 'Marquee'
$progress.Visible = $false
$progress.Size = (Z 140 16)
$status.Items.AddRange(@($statusLabel, $progress))

$form.Controls.Add($lvHost)
$form.Controls.Add($header)
$form.Controls.Add($status)
$form.AcceptButton = $btnSearch

# ---------------------------------------------------------------- actions
function Get-SelectedPath { if ($lv.SelectedItems.Count -eq 0) { return $null }; return $lv.SelectedItems[0].Tag }
$openItem   = { $p = Get-SelectedPath; if ($p -and (Test-Path -LiteralPath $p)) { try { Start-Process -FilePath $p } catch { } } }
$openFolder = { $p = Get-SelectedPath; if ($p -and (Test-Path -LiteralPath $p)) { Start-Process explorer.exe -ArgumentList "/select,`"$p`"" } }
$copyPath   = { $p = Get-SelectedPath; if ($p) { [System.Windows.Forms.Clipboard]::SetText($p) } }
$copyName   = { $p = Get-SelectedPath; if ($p) { [System.Windows.Forms.Clipboard]::SetText([IO.Path]::GetFileName($p)) } }

$lv.Add_DoubleClick($openItem)
$miOpen.Add_Click($openItem)
$miFolder.Add_Click($openFolder)
$miCopy.Add_Click($copyPath)
$miCopyNm.Add_Click($copyName)
$lv.Add_KeyDown({
    if ($_.KeyCode -eq 'Return') { & $openItem; $_.Handled = $true }
    if ($_.Control -and $_.KeyCode -eq 'C') { & $copyPath }
})
$lv.Add_ColumnClick({
    if ($script:Sorter.Column -eq $_.Column) { $script:Sorter.Ascending = -not $script:Sorter.Ascending }
    else { $script:Sorter.Column = $_.Column; $script:Sorter.Ascending = $true }
    $lv.Sort()
})
$btnBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Choose a folder to search'
    if ($dlg.ShowDialog($form) -eq 'OK') { $cmbWhere.Text = $dlg.SelectedPath }
})
$btnClear.Add_Click({ $lv.Items.Clear(); $emptyLabel.Visible = $true; $statusLabel.Text = 'Ready' })
$form.Add_KeyDown({
    if ($_.KeyCode -eq 'Escape' -and $btnStop.Enabled) { $btnStop.PerformClick(); $_.Handled = $true }
    elseif ($_.KeyCode -eq 'F5') { $btnSearch.PerformClick(); $_.Handled = $true }
    elseif ($_.Control -and $_.KeyCode -eq 'F') { $txtName.Focus(); $txtName.SelectAll(); $_.Handled = $true }
})

# ---------------------------------------------------------------- background search
$script:Runspace = $null; $script:PS = $null
$script:Results = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
$script:State = [hashtable]::Synchronized(@{ Stop = $false; Scanned = 0; Done = $false })
$script:Found = 0

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 150

$searchBlock = {
    param($Roots, $Pattern, $Exts, $Recurse, $SkipSystem, $MinSize, $MinDate, $Queue, $State)

    $skipNames = @('Windows', 'Program Files', 'Program Files (x86)', 'ProgramData', '$Recycle.Bin', 'System Volume Information', 'AppData', 'node_modules', '.git')
    if ($Pattern -match '[\*\?]') { $filter = $Pattern } else { $filter = "*$Pattern*" }
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
                if ($MinSize -gt 0 -and $f.Length -lt $MinSize) { continue }
                if ($MinDate -and $f.LastWriteTime -lt $MinDate) { continue }
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
    if ($script:PS) { try { $script:PS.Stop() } catch { }; try { $script:PS.Dispose() } catch { }; $script:PS = $null }
    if ($script:Runspace) { try { $script:Runspace.Close(); $script:Runspace.Dispose() } catch { }; $script:Runspace = $null }
    $btnSearch.Enabled = $true
    $btnStop.Enabled = $false
    $progress.Visible = $false
}

function Start-Search {
    $where = $cmbWhere.Text.Trim()
    if ($where -eq 'All drives' -or $where -eq '') {
        $roots = @(Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match '^[A-Z]:\\$' -and (Test-Path $_.Root) } | ForEach-Object { $_.Root })
    } elseif (Test-Path -LiteralPath $where) {
        $roots = @($where)
    } else {
        [System.Windows.Forms.MessageBox]::Show($form, "Folder not found:`n$where", 'Quick File Search', 'OK', 'Warning') | Out-Null
        return
    }
    $exts = @()
    if (-not $chkAll.Checked) {
        foreach ($cb in $script:TypeChecks) { if ($cb.Checked) { $exts += $script:Categories[$cb.Text] } }
    }
    $minSize = [long]$script:SizeFilters[$cmbSize.SelectedItem]
    $days = [int]$script:DateFilters[$cmbDate.SelectedItem]
    $minDate = $null
    if ($days -gt 0) { if ($days -eq 1) { $minDate = (Get-Date).Date } else { $minDate = (Get-Date).AddDays(-$days) } }

    $lv.Items.Clear()
    $emptyLabel.Visible = $false
    $script:Results = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
    $script:State = [hashtable]::Synchronized(@{ Stop = $false; Scanned = 0; Done = $false })
    $script:Found = 0
    $script:StartTime = Get-Date

    $script:Runspace = [runspacefactory]::CreateRunspace()
    $script:Runspace.ApartmentState = 'MTA'
    $script:Runspace.Open()
    $script:PS = [powershell]::Create()
    $script:PS.Runspace = $script:Runspace
    [void]$script:PS.AddScript($searchBlock).AddArgument($roots).AddArgument($txtName.Text.Trim()).AddArgument($exts).AddArgument($chkSubfolders.Checked).AddArgument($chkSkipSystem.Checked).AddArgument($minSize).AddArgument($minDate).AddArgument($script:Results).AddArgument($script:State)
    [void]$script:PS.BeginInvoke()

    $btnSearch.Enabled = $false
    $btnStop.Enabled = $true
    $progress.Visible = $true
    $statusLabel.Text = 'Searching...'
    $timer.Start()
}

$timer.Add_Tick({
    $lv.BeginUpdate()
    $item = $null; $batch = 0
    while ($batch -lt 400 -and $script:Results.TryDequeue([ref]$item)) {
        $li = New-Object System.Windows.Forms.ListViewItem($item.Name)
        $li.ImageKey = Get-IconKey $item.Ext
        [void]$li.SubItems.Add((Get-TypeName $item.Ext))
        $s = $li.SubItems.Add((Format-Size $item.Size)); $s.Tag = [long]$item.Size
        $d = $li.SubItems.Add($item.Modified.ToString('yyyy-MM-dd HH:mm')); $d.Tag = [long]$item.Modified.Ticks
        [void]$li.SubItems.Add($item.Dir)
        $li.Tag = $item.Path
        $li.ToolTipText = $item.Path
        if (($script:Found % 2) -eq 1) { $li.BackColor = $RowAlt }
        [void]$lv.Items.Add($li)
        $script:Found++; $batch++
    }
    $lv.EndUpdate()
    $elapsed = ((Get-Date) - $script:StartTime).TotalSeconds
    if ($script:State.Done -and $script:Results.IsEmpty) {
        Stop-Search
        $statusLabel.Text = ('Done: {0:N0} file(s) found, {1:N0} scanned in {2:N1}s' -f $script:Found, $script:State.Scanned, $elapsed)
        if ($script:Found -eq 0) { $emptyLabel.Text = 'No files matched. Try a shorter name, another location, or "All types".'; $emptyLabel.Visible = $true }
    } else {
        $statusLabel.Text = ('Searching... {0:N0} found, {1:N0} scanned ({2:N0}s)' -f $script:Found, $script:State.Scanned, $elapsed)
    }
})

$btnSearch.Add_Click({ Start-Search })
$btnStop.Add_Click({ Stop-Search; $statusLabel.Text = ('Stopped: {0:N0} file(s) found.' -f $script:Found) })

# ---------------------------------------------------------------- settings load / save
$form.Add_Load({
    $s = Load-Settings
    if ($s) {
        try {
            if ($s.Where) { $cmbWhere.Text = $s.Where }
            if ($s.Types -and $s.Types.Count -gt 0) { foreach ($c in $script:TypeChecks) { $c.Checked = ($s.Types -contains $c.Text) } }
            if ($null -ne $s.Subfolders) { $chkSubfolders.Checked = [bool]$s.Subfolders }
            if ($null -ne $s.SkipSystem) { $chkSkipSystem.Checked = [bool]$s.SkipSystem }
            $dpi = [int]$form.CreateGraphics().DpiX
            if ($s.Dpi -eq $dpi -and $s.Width -ge 820 -and $s.Height -ge 520) { $form.Size = New-Object System.Drawing.Size([int]$s.Width, [int]$s.Height) }
        } catch { }
    }
    if ($Path) { $cmbWhere.Text = $Path }
    [QfsNative]::SetCue($txtName, 'Search file name...  e.g. report, *.pdf, invoice_2024*')
    [QfsNative]::SetCue($cmbWhere, 'Folder or drive')
})
$form.Add_Shown({
    # When launched from a hidden console (the .cmd launcher), Windows applies that hidden
    # state to the first window shown. Force the form visible and in front.
    [void][QfsNative]::ShowWindow($form.Handle, 5)   # SW_SHOW
    [void][QfsNative]::SetForegroundWindow($form.Handle)
    $form.Activate()
    $txtName.Focus()
    if ($AutoSearch) { Start-Search }
})
$form.Add_FormClosing({
    Stop-Search
    Save-Settings ([pscustomobject]@{
        Where = $cmbWhere.Text
        Types = @($script:TypeChecks | Where-Object Checked | ForEach-Object Text)
        Subfolders = $chkSubfolders.Checked
        SkipSystem = $chkSkipSystem.Checked
        Width = $form.Width; Height = $form.Height
        Dpi = [int]$form.CreateGraphics().DpiX
    })
})

[void]$form.ShowDialog()
