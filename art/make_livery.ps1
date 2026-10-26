# Builds a vehicle shell texture (1024) from a vanilla shell + logo placements.
#
# The vanilla shell's body is alpha 0: the multiuv shader paints the random
# color there. With -paint the body is filled with that color instead and the
# texture is fully opaque, for a *_NoRandom model (fixed-color livery). The
# body detail hidden under alpha 0 (roof ribs, brightness steps) is kept as
# shading: paint * (luma / local mean luma).
# Without -paint the body stays transparent (random color, logo opaque).
#
# GDI+ only draws the logo layer: it drops RGB under alpha 0, so everything
# touching the shell is done by ffmpeg, which keeps the channels.
#
#   make_livery.ps1 -base vehicle_stepvanshell.png -logo logo.png -out x.png -layout stepvan [-paint EBEBEB]
param($base, $logo, $out, $layout, $paint)
Add-Type -AssemblyName System.Drawing

# placements in 512-px shell coordinates: x, center y, width, mirrored
$layouts = @{
    # two sides (top strip mirrored, like vanilla Zippee) + rear doors
    stepvan = @( @(18, 56, 172, $true), @(18, 185, 172, $false), @(412, 211, 76, $false) )
    # two sides (bottom strip mirrored, like vanilla LectroMax), cargo area
    van     = @( @(95, 68, 170, $false), @(95, 168, 170, $true) )
}
$S = 2
$N = 512 * $S

$src = [Drawing.Bitmap]::FromFile($logo)
$minX=$src.Width; $minY=$src.Height; $maxX=0; $maxY=0
for ($y=0; $y -lt $src.Height; $y++) { for ($x=0; $x -lt $src.Width; $x++) {
    if ($src.GetPixel($x,$y).A -gt 8) { if($x -lt $minX){$minX=$x}; if($x -gt $maxX){$maxX=$x}; if($y -lt $minY){$minY=$y}; if($y -gt $maxY){$maxY=$y} } } }
$rect = New-Object Drawing.Rectangle $minX,$minY,($maxX-$minX+1),($maxY-$minY+1)
$lg = $src.Clone($rect, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
$lgM = $lg.Clone(); $lgM.RotateFlip([Drawing.RotateFlipType]::RotateNoneFlipX)
$aspect = $lg.Width / $lg.Height

$layer = New-Object Drawing.Bitmap $N, $N, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
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

if ($paint) {
    # shade = 128 * luma / blurred luma (flat areas -> 1.0, ribs and steps keep their contrast)
    $fc = "[0]scale=${N}:${N}:flags=lanczos,format=rgba,split=2[o][c];" +
          "[c]format=gray,split=2[l1][l2];[l2]boxblur=24:2[lb];" +
          "[l1][lb]blend=all_expr='clip(128*A/max(B\,1)\,0\,255)',format=rgb24[sh];" +
          "color=c=0x${paint}:s=${N}x${N},format=rgb24[p];" +
          "[p][sh]blend=all_expr='clip(A*B/128\,0\,255)'[body];" +
          "[body][o]overlay=format=auto[b];[b][1]overlay=format=auto,format=rgba,colorchannelmixer=aa=1"
} else {
    $fc = "[0]scale=${N}:${N}:flags=lanczos,format=rgba[b];[b][1]overlay=format=auto,format=rgba"
}
& ffmpeg -v error -y -i $base -i $tmp -filter_complex $fc -frames:v 1 $out
Remove-Item $tmp
