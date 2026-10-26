# Cardboard box texture: 512x512 atlas of six faces, matched by the UV layout
# that make_boxes.py writes (keep the two in sync):
#   row 0: +X  -X  +Z(top)      row 1: +Y  -Y  -Z(bottom)
# each cell 512/3 x 256; on side faces "up" is +Z.
# Faces are drawn in millimetres of the real face, so nothing is stretched.
#
#   make_box_texture.ps1 -logo logo.png -out x.png -dx 403.5 -dy 357.6 -dz 212.4 -label "5 кг"
param($logo, $out, [double]$dx, [double]$dy, [double]$dz, [string]$label)
Add-Type -AssemblyName System.Drawing

$src = [Drawing.Bitmap]::FromFile($logo)
$minX=$src.Width; $minY=$src.Height; $maxX=0; $maxY=0
for ($y=0; $y -lt $src.Height; $y++) { for ($x=0; $x -lt $src.Width; $x++) {
    if ($src.GetPixel($x,$y).A -gt 8) { if($x -lt $minX){$minX=$x}; if($x -gt $maxX){$maxX=$x}; if($y -lt $minY){$minY=$y}; if($y -gt $maxY){$maxY=$y} } } }
$lg = $src.Clone((New-Object Drawing.Rectangle $minX,$minY,($maxX-$minX+1),($maxY-$minY+1)), [Drawing.Imaging.PixelFormat]::Format32bppArgb)
$aspect = $lg.Width / $lg.Height

$N = 512; $cw = $N / 3.0; $ch = $N / 2.0
$bmp = New-Object Drawing.Bitmap $N, $N, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [Drawing.Graphics]::FromImage($bmp)
$g.InterpolationMode = 'HighQualityBicubic'; $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'; $g.PixelOffsetMode = 'HighQuality'

$kraft = [Drawing.Color]::FromArgb(255, 190, 150, 100)
$tapeC = [Drawing.Color]::FromArgb(235, 214, 182, 128)
$rnd = New-Object Random 42

function Face($col, $row, [double]$fw, [double]$fh, $kind) {
    $st = $g.Save()
    $g.SetClip((New-Object Drawing.RectangleF ([single]($col*$cw)), ([single]($row*$ch)), ([single]$cw), ([single]$ch)))
    $g.TranslateTransform([single]($col*$cw), [single]($row*$ch))
    $g.ScaleTransform([single]($cw/$fw), [single]($ch/$fh))
    $g.FillRectangle((New-Object Drawing.SolidBrush $kraft), 0, 0, [single]$fw, [single]$fh)
    # cardboard fibres: faint horizontal streaks
    for ($i=0; $i -lt 60; $i++) {
        $a = $rnd.Next(5, 14); $c = if ($rnd.Next(2)) { [Drawing.Color]::FromArgb($a, 120, 85, 45) } else { [Drawing.Color]::FromArgb($a, 230, 200, 150) }
        $yy = $rnd.NextDouble()*$fh; $g.FillRectangle((New-Object Drawing.SolidBrush $c), 0, [single]$yy, [single]$fw, [single]($fh*0.012))
    }
    # worn darker edges
    $e = [Math]::Min($fw,$fh)*0.035
    $pen = New-Object Drawing.Pen ([Drawing.Color]::FromArgb(110, 95, 65, 35)), ([single]$e)
    $g.DrawRectangle($pen, [single]($e/2), [single]($e/2), [single]($fw-$e), [single]($fh-$e))
    $tw = [Math]::Min($dx,$dy)*0.18   # tape width
    switch ($kind) {
        'tapeV' {   # +-X sides: tape runs down the middle, weight label beside it
            $g.FillRectangle((New-Object Drawing.SolidBrush $tapeC), [single](($fw-$tw)/2), 0, [single]$tw, [single]($fh*0.45))
            Label ($fw*0.5) ($fh*0.68) ($fw*0.55) ($fh*0.36)
        }
        'logo' {    # +-Y sides: logo + weight
            $w = $fw*0.78; $h = $w/$aspect
            if ($h -gt $fh*0.42) { $h = $fh*0.42; $w = $h*$aspect }
            $g.DrawImage($lg, [single](($fw-$w)/2), [single]($fh*0.30-$h/2), [single]$w, [single]$h)
            Label ($fw*0.5) ($fh*0.74) ($fw*0.38) ($fh*0.30)
        }
        'top' {     # tape along X, small logo on each half
            $g.FillRectangle((New-Object Drawing.SolidBrush $tapeC), 0, [single](($fh-$tw)/2), [single]$fw, [single]$tw)
            $w = $fw*0.5; $h = $w/$aspect
            $g.DrawImage($lg, [single](($fw-$w)/2), [single]($fh*0.22-$h/2), [single]$w, [single]$h)
        }
    }
    $g.Restore($st)
}

# white sticker with the weight, centred at (cx, cy) in face millimetres
function Label([double]$cx, [double]$cy, [double]$w, [double]$h) {
    $r = New-Object Drawing.RectangleF ([single]($cx-$w/2)), ([single]($cy-$h/2)), ([single]$w), ([single]$h)
    $g.FillRectangle((New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, 245, 243, 236))), $r)
    $g.DrawRectangle((New-Object Drawing.Pen ([Drawing.Color]::FromArgb(255, 218, 41, 28)), ([single]($h*0.06))), $r.X, $r.Y, $r.Width, $r.Height)
    $font = New-Object Drawing.Font 'Arial', ([single]($h*0.62)), ([Drawing.FontStyle]::Bold), ([Drawing.GraphicsUnit]::Pixel)
    $sf = New-Object Drawing.StringFormat; $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
    # fit the text width into the sticker
    $sz = $g.MeasureString($label, $font)
    if ($sz.Width -gt $w*0.92) { $font = New-Object Drawing.Font 'Arial', ([single]($h*0.62*$w*0.92/$sz.Width)), ([Drawing.FontStyle]::Bold), ([Drawing.GraphicsUnit]::Pixel) }
    $g.DrawString($label, $font, (New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, 30, 30, 30))), $r, $sf)
}

Face 0 0 $dy $dz 'tapeV'   # +X
Face 1 0 $dy $dz 'tapeV'   # -X
Face 2 0 $dx $dy 'top'     # +Z
Face 0 1 $dx $dz 'logo'    # +Y
Face 1 1 $dx $dz 'logo'    # -Y
Face 2 1 $dx $dy 'plain'   # -Z
$g.Dispose()
$bmp.Save($out, [Drawing.Imaging.ImageFormat]::Png)
