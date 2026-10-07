$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

Write-Output '--- corner/center alpha check ---'
$imgs = @(
  'e:\Code\Dart-Code\share_link\assets\app_icon.png',
  'e:\Code\Dart-Code\share_link\macos\Runner\Assets.xcassets\AppIcon.appiconset\app_icon_256.png',
  'e:\Code\Dart-Code\share_link\macos\Runner\Assets.xcassets\AppIcon.appiconset\app_icon_1024.png'
)
foreach ($p in $imgs) {
  $b = [System.Drawing.Bitmap]::FromFile($p)
  $w = $b.Width
  $c0 = $b.GetPixel(0, 0)
  $c1 = $b.GetPixel(1, 1)
  $ce = $b.GetPixel([int]($w / 2), [int]($w / 2))
  $edge = $b.GetPixel([int]($w / 2), 0)
  Write-Output ('{0} size={1} corner(0,0)=A{2} corner(1,1)=A{3} topMid=A{4} center=A{5}' -f (Split-Path $p -Leaf), $w, $c0.A, $c1.A, $edge.A, $ce.A)
  $b.Dispose()
}

Write-Output ''
Write-Output '--- ICO structural check ---'
foreach ($p in @('e:\Code\Dart-Code\share_link\assets\app_icon.ico', 'e:\Code\Dart-Code\share_link\windows\runner\resources\app_icon.ico')) {
  $b = [System.IO.File]::ReadAllBytes($p)
  $len = $b.Length
  $count = [BitConverter]::ToUInt16($b, 4)
  $ok = $true
  for ($i = 0; $i -lt $count; $i++) {
    $o = 6 + 16 * $i
    $bytes = [BitConverter]::ToUInt32($b, $o + 8)
    $off = [BitConverter]::ToUInt32($b, $o + 12)
    if (($off + $bytes) -gt $len) { $ok = $false }
  }
  try { $ico = New-Object System.Drawing.Icon($p); $ico.Dispose() } catch { $ok = $false; Write-Output ('  load failed: ' + $_.Exception.Message) }
  Write-Output ('  ' + (Split-Path $p -Leaf) + ' len=' + $len + ' frames=' + $count + ' bounds=' + $ok)

  # check alpha of the 32x32 frame (index 3) top-left pixel
  $ico2 = New-Object System.Drawing.Icon($p, 32, 32)
  $bm = $ico2.ToBitmap()
  $tl = $bm.GetPixel(0, 0)
  Write-Output ('    32x32 frame topLeft alpha=' + $tl.A + ' center alpha=' + $bm.GetPixel(16, 16).A)
  $bm.Dispose()
  $ico2.Dispose()
}
