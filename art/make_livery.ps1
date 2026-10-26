# Builds a vehicle shell texture: vanilla shell scaled x2 + logo placements.
# The vanilla shell's body is alpha 0 (the multiuv shader paints the random
# color there); the logo is opaque, so it stays as drawn on any body color.
# GDI+ only draws the logo layer: it drops RGB under alpha 0, so scaling and
# compositing over the shell is done by ffmpeg, which keeps the channels.
#
#   make_livery.ps1 -base vehicle_stepvanshell.png -logo logo.png -out x.png -layout stepvan
param($base, $logo, $out, $layout)
Add-Type -AssemblyName System.Drawing

# placements in 512-px shell coordinates: x, center y, width, mirrored
$layouts = @{
    # two sides (top strip mirrored, like vanilla Zippee) + rear doors
    stepvan = @( @(18, 56, 172, $true), @(18, 185, 172, $false), @(412, 211, 76, $false) )
    # two sides (bottom strip mirrored, like vanilla LectroMax), cargo area
    van     = @( @(95, 68, 170, $false), @(95, 168, 170, $true) )
}
$S = 2

$src = [Drawing.Bitmap]::FromFile($logo)
$minX=$src.Width; $minY=$src.Height; $maxX=0; $maxY=0
for ($y=0; $y -lt $src.Height; $y++) { for ($x=0; $x -lt $src.Width; $x++) {
    if ($src.GetPixel($x,$y).A -gt 8) { if($x -lt $minX){$minX=$x}; if($x -gt $maxX){$maxX=$x}; if($y -lt $minY){$minY=$y}; if($y -gt $maxY){$maxY=$y} } } }
$rect = New-Object Drawing.Rectangle $minX,$minY,($maxX-$minX+1),($maxY-$minY+1)
$lg = $src.Clone($rect, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
$lgM = $lg.Clone(); $lgM.RotateFlip([Drawing.RotateFlipType]::RotateNoneFlipX)
$aspect = $lg.Width / $lg.Height

$layer = New-Object Drawing.Bitmap (512*$S), (512*$S), ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [Drawing.Graphics]::FromImage($layer)
$g.InterpolationMode = 'HighQualityBicubic'; $g.PixelOffsetMode = 'HighQuality'; $g.SmoothingMode = 'HighQuality'
foreach ($p in $layouts[$layout]) {
    $w = $p[2]; $h = $w / $aspect
    $img = if ($p[3]) { $lgM } else { $lg }
    $g.DrawImage($img, [single]($p[0]*$S), [single](($p[1] - $h/2)*$S), [single]($w*$S), [single]($h*$S))
}
$g.Dispose()
$tmp = [IO.Path]::GetTempFileName() + '.png'
$layer.Save($tmp, [Drawing.Imaging.ImageFormat]::Png)

& ffmpeg -v error -y -i $base -i $tmp -filter_complex "[0]scale=$(512*$S):$(512*$S):flags=lanczos,format=rgba[b];[b][1]overlay=format=auto,format=rgba" -frames:v 1 $out
Remove-Item $tmp
