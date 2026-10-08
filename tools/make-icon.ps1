# Generates app.ico (16/24/32/48/64/128/256 px, PNG-compressed entries) with a magnifier glyph.
# Usage: powershell -ExecutionPolicy Bypass -File .\tools\make-icon.ps1
Add-Type -AssemblyName System.Drawing
$out = Join-Path (Split-Path $PSScriptRoot -Parent) 'app.ico'
$sizes = 16, 24, 32, 48, 64, 128, 256
$pngs = @()
foreach ($s in $sizes) {
    $bmp = New-Object System.Drawing.Bitmap($s, $s, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.Clear([System.Drawing.Color]::Transparent)
    # rounded blue tile
    $r = [math]::Max(2, $s * 0.22)
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $rect = New-Object System.Drawing.RectangleF(0, 0, $s, $s)
    $path.AddArc($rect.X, $rect.Y, $r*2, $r*2, 180, 90)
    $path.AddArc($rect.Right - $r*2, $rect.Y, $r*2, $r*2, 270, 90)
    $path.AddArc($rect.Right - $r*2, $rect.Bottom - $r*2, $r*2, $r*2, 0, 90)
    $path.AddArc($rect.X, $rect.Bottom - $r*2, $r*2, $r*2, 90, 90)
    $path.CloseFigure()
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, [System.Drawing.Color]::FromArgb(0, 132, 232), [System.Drawing.Color]::FromArgb(0, 92, 170), 60)
    $g.FillPath($brush, $path)
    # magnifier
    $pw = [math]::Max(1.5, $s * 0.11)
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, $pw)
    $pen.StartCap = 'Round'; $pen.EndCap = 'Round'
    $cx = $s * 0.44; $cy = $s * 0.44; $rad = $s * 0.22
    $g.DrawEllipse($pen, $cx - $rad, $cy - $rad, $rad*2, $rad*2)
    $g.DrawLine($pen, $cx + $rad*0.72, $cy + $rad*0.72, $s*0.78, $s*0.78)
    $g.Dispose()
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $pngs += ,$ms.ToArray()
    $bmp.Dispose()
}
# write ICO container with PNG entries
$fs = [System.IO.File]::Create($out)
$bw = New-Object System.IO.BinaryWriter($fs)
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $s = $sizes[$i]; $b = if ($s -ge 256) { 0 } else { $s }
    $bw.Write([byte]$b); $bw.Write([byte]$b); $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([uint16]1); $bw.Write([uint16]32)
    $bw.Write([uint32]$pngs[$i].Length); $bw.Write([uint32]$offset)
    $offset += $pngs[$i].Length
}
foreach ($p in $pngs) { $bw.Write($p) }
$bw.Close(); $fs.Close()
"Wrote $out ($((Get-Item $out).Length) bytes)"
