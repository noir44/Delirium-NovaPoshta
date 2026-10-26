param($base, $logo, $out)
Add-Type -AssemblyName System.Drawing
$src = [Drawing.Bitmap]::FromFile($logo)
# trim transparent padding
$minX=$src.Width; $minY=$src.Height; $maxX=0; $maxY=0
for ($y=0; $y -lt $src.Height; $y+=1) { for ($x=0; $x -lt $src.Width; $x+=1) {
  if ($src.GetPixel($x,$y).A -gt 8) { if($x -lt $minX){$minX=$x}; if($x -gt $maxX){$maxX=$x}; if($y -lt $minY){$minY=$y}; if($y -gt $maxY){$maxY=$y} } } }
$rect = New-Object Drawing.Rectangle $minX,$minY,($maxX-$minX+1),($maxY-$minY+1)
$lg = $src.Clone($rect, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
$lgM = $lg.Clone(); $lgM.RotateFlip([Drawing.RotateFlipType]::RotateNoneFlipX)
$aspect = $lg.Width / $lg.Height
"logo bbox $rect aspect $aspect"

$b = [Drawing.Bitmap]::FromFile($base)
$S = 2
$dst = New-Object Drawing.Bitmap ($b.Width*$S), ($b.Height*$S), ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [Drawing.Graphics]::FromImage($dst)
$g.InterpolationMode = 'HighQualityBicubic'; $g.PixelOffsetMode = 'HighQuality'; $g.SmoothingMode = 'HighQuality'
$g.DrawImage($b, 0, 0, $dst.Width, $dst.Height)

function Put($img, $x, $y, $w) { $h = $w / $aspect; $g.DrawImage($img, [single]($x*$S), [single]($y*$S), [single]($w*$S), [single]($h*$S)) }
$w = 172; $h = $w / $aspect
Put $lg  18 (185 - $h/2) $w        # right side (normal)
Put $lgM 18 (56  - $h/2) $w        # left side (mirrored strip)
$rw = 76; Put $lg (450 - $rw/2) (211 - ($rw/$aspect)/2) $rw   # rear doors
$g.Dispose()
$dst.Save($out, [Drawing.Imaging.ImageFormat]::Png)
