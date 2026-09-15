<#
  把 Markdown Reader 注册进当前用户的「打开方式」列表。
  只写 HKEY_CURRENT_USER\Software\Classes，不需要管理员权限，也不改动系统默认关联。

  安装：双击 tools\install-open-with.cmd
  卸载：双击 tools\uninstall-open-with.cmd

  安装时会做三件事：
    1. 现画一个图标  %LOCALAPPDATA%\MarkdownReader\MarkdownReader.ico
    2. 用系统自带的 csc.exe 把 tools\MarkdownReaderLauncher.cs 编译成
       %LOCALAPPDATA%\MarkdownReader\MarkdownReader.exe
       —— 必须有自己的 exe：Windows 的「打开方式」菜单显示的名字取自命令里那个
          可执行文件的版本信息；若借用 wscript.exe，菜单里就会显示成
          「Microsoft ® Windows Based Script Host」，而 HKLM 里的
          Applications\wscript.exe 是系统级的，不能去改（会污染全系统）。
    3. 写注册表：ProgID + Applications\MarkdownReader.exe + 各扩展名的 OpenWithProgids

  万一 csc 不可用，会自动回退到用 open-with.vbs 启动：功能完全一样，
  只是菜单里显示的名字是脚本宿主（.vbs 保留至今就是为了这条退路）。

  ⚠ 本文件必须保存为 UTF-8 **带 BOM**：Windows PowerShell 5.1 会把无 BOM 的 UTF-8
     当作 ANSI/GBK 解析，中文注释会乱码并直接导致语法错误（改完请确认 BOM 还在）。
#>
[CmdletBinding()]
param([switch]$Uninstall)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$ToolsDir    = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot    = Split-Path -Parent $ToolsDir
$IndexHtml   = Join-Path $RepoRoot 'index.html'
$Ps1         = Join-Path $ToolsDir 'open-with.ps1'
$Vbs         = Join-Path $ToolsDir 'open-with.vbs'
$CsSrc       = Join-Path $ToolsDir 'MarkdownReaderLauncher.cs'
$Wscript     = Join-Path $env:SystemRoot 'System32\wscript.exe'
$DataDir     = Join-Path $env:LOCALAPPDATA 'MarkdownReader'
$IconFile    = Join-Path $DataDir 'MarkdownReader.ico'
$LauncherExe = Join-Path $DataDir 'MarkdownReader.exe'
$ProgId      = 'MarkdownReader.md'
$AppKey      = 'MarkdownReader.exe'          # Applications 下的键名 = 启动器 exe 的文件名
$DisplayName = 'Markdown Reader'
$Exts        = @('.md', '.markdown', '.mdown', '.mkd', '.mdx')

function Find-Browser {
  $cands = @(
    (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
    (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe'),
    (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
    (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
  )
  foreach ($c in $cands) { if ($c -and (Test-Path -LiteralPath $c)) { return $c } }
  return $null
}

function Find-Csc {
  $cands = @(
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
  )
  foreach ($c in $cands) { if (Test-Path -LiteralPath $c) { return $c } }
  return $null
}

# 手写一个 32bpp（BGRA，带 alpha）的 .ico。
# ⚠ 不要改用 Icon.FromHandle($bmp.GetHicon()).Save()：GDI+ 会把图标写成 4bpp +
#   Windows 固定的 16 色调色板，自定义的底色会被量化掉——#2563EB 被换成纯蓝
#   #0000FF、#3399CC 被换成青色 #008080，怎么调都是那几种死板的颜色（这正是
#   图标「丑」的根源）。自己拼 ICO 容器，颜色和 alpha 才能原样保留。
function Write-Icon32bpp {
  param([System.Drawing.Bitmap]$Bitmap, [string]$Path)

  $w = $Bitmap.Width
  $h = $Bitmap.Height
  $stride     = $w * 4                                   # 32bpp：每行天然 4 字节对齐
  $maskStride = [int]([Math]::Ceiling($w / 32.0) * 4)     # AND 掩码：每行 1 位、补齐到 4 字节
  $xor  = New-Object byte[] ($stride * $h)
  $and  = New-Object byte[] ($maskStride * $h)

  for ($y = 0; $y -lt $h; $y++) {
    $srcY = $h - 1 - $y                                 # DIB 的像素是自下而上存放的
    $row  = $y * $stride
    for ($x = 0; $x -lt $w; $x++) {
      $c = $Bitmap.GetPixel($x, $srcY)
      $p = $row + $x * 4
      $xor[$p]     = $c.B
      $xor[$p + 1] = $c.G
      $xor[$p + 2] = $c.R
      $xor[$p + 3] = $c.A
      if ($c.A -eq 0) {                                 # 掩码里 1 = 透明（照顾不看 alpha 的老路径）
        # ⚠ 必须用 Floor：PowerShell 的 [int] 是四舍五入而非截断，[int](63/8) 会得到
        #   8 而不是 7，最后一行就会越界（Index was outside the bounds of the array）。
        $i = $y * $maskStride + [int][Math]::Floor($x / 8)
        $and[$i] = $and[$i] -bor (0x80 -shr ($x % 8))
      }
    }
  }

  $imgBytes = 40 + $xor.Length + $and.Length
  $ms = New-Object System.IO.MemoryStream
  $bw = New-Object System.IO.BinaryWriter -ArgumentList $ms

  $bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]1)          # ICONDIR：0 / 图标 / 1 张
  $bw.Write([byte]$w); $bw.Write([byte]$h); $bw.Write([byte]0); $bw.Write([byte]0)
  $bw.Write([uint16]1);  $bw.Write([uint16]32)                             # planes / 位深
  $bw.Write([uint32]$imgBytes); $bw.Write([uint32]22)                      # 数据长度 / 偏移

  $bw.Write([uint32]40); $bw.Write([int32]$w); $bw.Write([int32]($h * 2))  # BITMAPINFOHEADER（高度要含掩码）
  $bw.Write([uint16]1);  $bw.Write([uint16]32)
  $bw.Write([uint32]0);  $bw.Write([uint32]($xor.Length + $and.Length))
  $bw.Write([int32]0);   $bw.Write([int32]0)
  $bw.Write([uint32]0);  $bw.Write([uint32]0)
  $bw.Write($xor); $bw.Write($and)

  $bw.Flush()
  [System.IO.File]::WriteAllBytes($Path, $ms.ToArray())
  $bw.Dispose(); $ms.Dispose()
}

# 现画一个 64x64 图标：圆角湖水蓝底 + 白色 M↓（Markdown）。失败不影响安装。
function New-AppIcon {
  try {
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    $size = 64
    # 底色：柔和湖水蓝 #3399CC（原先的深蓝 #2563EB 偏暗偏艳，观感发闷）。
    # 白字与它的对比度 3.2:1，够图标里的 M↓ 看清。
    $plate = [System.Drawing.Color]::FromArgb(255, 51, 153, 204)
    $bmp  = New-Object System.Drawing.Bitmap -ArgumentList $size, $size
    $g    = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $g.Clear([System.Drawing.Color]::Transparent)

    $r    = 13
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc(0, 0, $r * 2, $r * 2, 180, 90)
    $path.AddArc($size - $r * 2, 0, $r * 2, $r * 2, 270, 90)
    $path.AddArc($size - $r * 2, $size - $r * 2, $r * 2, $r * 2, 0, 90)
    $path.AddArc(0, $size - $r * 2, $r * 2, $r * 2, 90, 90)
    $path.CloseFigure()
    $bg = New-Object System.Drawing.SolidBrush -ArgumentList $plate
    $g.FillPath($bg, $path)

    $font = New-Object System.Drawing.Font -ArgumentList 'Segoe UI', 28, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
    $fg   = New-Object System.Drawing.SolidBrush -ArgumentList ([System.Drawing.Color]::White)
    $fmt  = New-Object System.Drawing.StringFormat
    $fmt.Alignment     = [System.Drawing.StringAlignment]::Center
    $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
    $rect = New-Object System.Drawing.RectangleF -ArgumentList 0, 0, $size, $size
    $g.DrawString('M↓', $font, $fg, $rect, $fmt)

    Write-Icon32bpp -Bitmap $bmp -Path $IconFile
    $g.Dispose(); $bmp.Dispose()
    return $true
  } catch {
    Write-Host ("  ⚠ 图标生成失败（不影响使用）：" + $_.Exception.Message) -ForegroundColor Yellow
    return $false
  }
}

function Build-Launcher {
  $csc = Find-Csc
  if (-not $csc) { Write-Host '  ⚠ 找不到 csc.exe（.NET Framework 编译器），改用 .vbs' -ForegroundColor Yellow; return $null }
  if (-not (Test-Path -LiteralPath $CsSrc)) { Write-Host "  ⚠ 找不到 $CsSrc，改用 .vbs" -ForegroundColor Yellow; return $null }

  $out = Join-Path $DataDir 'MarkdownReader.new.exe'
  Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue
  $cscArgs = @('/nologo', '/target:winexe', '/optimize+', '/codepage:65001', ('/out:' + $out))
  if (Test-Path -LiteralPath $IconFile) { $cscArgs += ('/win32icon:' + $IconFile) }
  $cscArgs += $CsSrc

  $log = & $csc @cscArgs 2>&1
  if (-not (Test-Path -LiteralPath $out)) {
    Write-Host ("  ⚠ 编译失败，改用 .vbs：" + ($log -join ' ')) -ForegroundColor Yellow
    return $null
  }
  try {
    Move-Item -LiteralPath $out -Destination $LauncherExe -Force
  } catch {
    # 旧 exe 正在运行（文件被占用）：代码没变，直接用旧的
    Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path -LiteralPath $LauncherExe)) { Write-Host "  ⚠ 无法写入 $LauncherExe，改用 .vbs" -ForegroundColor Yellow; return $null }
  }
  return $LauncherExe
}

if ($Uninstall) {
  Remove-Item -LiteralPath "HKCU:\Software\Classes\$ProgId" -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath "HKCU:\Software\Classes\Applications\$AppKey" -Recurse -Force -ErrorAction SilentlyContinue
  foreach ($e in $Exts) {
    $k = "HKCU:\Software\Classes\$e\OpenWithProgids"
    if (Test-Path -LiteralPath $k) {
      Remove-ItemProperty -Path $k -Name $ProgId -ErrorAction SilentlyContinue
      $left = @((Get-Item -LiteralPath $k).Property)
      if ($left.Count -eq 0) { Remove-Item -LiteralPath $k -Force -ErrorAction SilentlyContinue }
    }
  }
  Write-Host ''
  Write-Host '✅ 已从「打开方式」中移除 Markdown Reader。' -ForegroundColor Green
  Write-Host '   （右键菜单里可能还残留一条失效项，注销或重启后消失；文件关联本身没有被改动。）'
  Write-Host "   生成的文件留在 $DataDir（含阅读器的浏览器配置，删掉会丢主题与「恢复上次」缓存）。"
  Write-Host ''
  exit 0
}

if (-not (Test-Path -LiteralPath $IndexHtml)) { throw "找不到 $IndexHtml（仓库是否被移动了？）" }
if (-not (Test-Path -LiteralPath $Ps1))       { throw "找不到 $Ps1" }
if (-not (Test-Path -LiteralPath $Vbs))       { throw "找不到 $Vbs" }

$browser = Find-Browser
if (-not $browser) { throw '没找到 Microsoft Edge 或 Google Chrome，请先安装其中之一。' }

if (-not (Test-Path -LiteralPath $DataDir)) { New-Item -ItemType Directory -Path $DataDir -Force | Out-Null }

Write-Host ''
Write-Host '正在准备启动器…'
$hasIcon = New-AppIcon
$exe = Build-Launcher

if ($exe) {
  $command  = '"{0}" "{1}" "%1"' -f $exe, $Ps1
  $mode     = 'MarkdownReader.exe（菜单里显示 Markdown Reader）'
  $iconPath = if ($hasIcon) { $IconFile } else { $browser }
  Write-Host "  ✅ 已编译启动器：$exe" -ForegroundColor Green
  Write-Host "     版本信息里的名字：$((Get-Item -LiteralPath $exe).VersionInfo.FileDescription)"
} else {
  $command  = '"{0}" "{1}" "%1"' -f $Wscript, $Vbs
  $mode     = 'open-with.vbs（回退模式：菜单里会显示脚本宿主）'
  $iconPath = if ($hasIcon) { $IconFile } else { $browser }
  Write-Host '  ⚠ 编译不可用，改用 .vbs 启动（功能相同，仅菜单名字不同）' -ForegroundColor Yellow
}

$base = "HKCU:\Software\Classes\$ProgId"
New-Item -Path $base -Force | Out-Null
Set-ItemProperty  -Path $base -Name '(Default)' -Value $DisplayName
New-ItemProperty  -Path $base -Name 'FriendlyTypeName' -Value $DisplayName -PropertyType String -Force | Out-Null

New-Item -Path "$base\DefaultIcon" -Force | Out-Null
Set-ItemProperty -Path "$base\DefaultIcon" -Name '(Default)' -Value ($iconPath + ',0')

New-Item -Path "$base\shell\open\command" -Force | Out-Null
Set-ItemProperty -Path "$base\shell\open\command" -Name '(Default)' -Value $command

foreach ($e in $Exts) {
  $k = "HKCU:\Software\Classes\$e\OpenWithProgids"
  New-Item -Path $k -Force | Out-Null
  New-ItemProperty -Path $k -Name $ProgId -Value '' -PropertyType String -Force | Out-Null
}

# 把启动器登记成一个「应用」：菜单和「选择其他应用」才会用它自己的名字与图标
if ($exe) {
  $app = "HKCU:\Software\Classes\Applications\$AppKey"
  New-Item -Path $app -Force | Out-Null
  New-ItemProperty -Path $app -Name 'FriendlyAppName' -Value $DisplayName -PropertyType String -Force | Out-Null
  New-Item -Path "$app\DefaultIcon" -Force | Out-Null
  Set-ItemProperty -Path "$app\DefaultIcon" -Name '(Default)' -Value ($iconPath + ',0')
  New-Item -Path "$app\shell\open\command" -Force | Out-Null
  Set-ItemProperty -Path "$app\shell\open\command" -Name '(Default)' -Value $command
  foreach ($e in $Exts) { New-Item -Path "$app\SupportedTypes\$e" -Force | Out-Null }
}

Write-Host ''
Write-Host '✅ 安装完成：Markdown Reader 已加入「打开方式」列表。' -ForegroundColor Green
Write-Host ''
Write-Host "   ProgID     : $ProgId"
Write-Host "   启动方式   : $mode"
Write-Host "   启动命令   : $command"
Write-Host "   图标       : $(if ($hasIcon) { $IconFile } else { $browser + '（未生成图标，借用浏览器图标）' })"
Write-Host "   适用扩展   : $($Exts -join ' ')"
Write-Host ''
Write-Host '用法：在资源管理器里右键任意 .md → 打开方式 → Markdown Reader。' -ForegroundColor Cyan
Write-Host '     想让它变成双击默认程序：右键 → 打开方式 → 选择其他应用 → 选 Markdown Reader'
Write-Host '     → 勾选「始终使用此应用打开 .md 文件」。'
Write-Host ''
Write-Host '卸载：双击 tools\uninstall-open-with.cmd'
Write-Host ''
