<#
  右键「打开方式」→ Markdown Reader 的启动器。

  做三件事：
    1. 解析传入的文件（或文件夹），把「要打开的文件 + 同目录 Markdown 清单」
       写成一个临时会话脚本：%LOCALAPPDATA%\MarkdownReader\sessions\session-*.js
    2. 找到 Edge / Chrome，用「专用配置目录 + 应用模式窗口」打开 index.html，
       地址栏 hash 里带上会话脚本的绝对路径
    3. 加 --allow-file-access-from-files，让页面能按绝对路径读取本地 md 正文
       （浏览器出于安全限制默认禁止 file:// 页面读本地文件；该参数只在这个专用
        配置目录里生效，不影响你日常使用的浏览器窗口）

  用法：
    open-with.ps1 "D:\docs\a.md"            正常启动
    open-with.ps1 "D:\docs\a.md" -DryRun    只写会话文件并打印 URL，不启动浏览器
    open-with.ps1 -NoSession                不带文件，单纯打开阅读器

  平时由 tools\open-with.vbs 以隐藏窗口方式调用，不会闪黑框。

  ⚠ 本文件必须保存为 UTF-8 **带 BOM**：Windows PowerShell 5.1 会把无 BOM 的 UTF-8
     当作 ANSI/GBK 解析，中文注释会乱码并直接导致语法错误（改完请确认 BOM 还在）。
#>
[CmdletBinding()]
param(
  [Parameter(ValueFromRemainingArguments = $true)][string[]]$Path,
  [switch]$DryRun,
  [switch]$NoSession
)

$ErrorActionPreference = 'Stop'

$ToolsDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot   = Split-Path -Parent $ToolsDir
$IndexHtml  = Join-Path $RepoRoot 'index.html'
$DataDir    = Join-Path $env:LOCALAPPDATA 'MarkdownReader'
$SessDir    = Join-Path $DataDir 'sessions'
$ProfileDir = Join-Path $DataDir 'profile'
$LogFile    = Join-Path $DataDir 'open-with.log'
$MdExt      = @('.md', '.markdown', '.mdown', '.mkd', '.mdx')
$MaxFiles   = 2000
$KeepDays   = 3

function Write-Log([string]$msg) {
  try {
    if (-not (Test-Path -LiteralPath $DataDir)) { New-Item -ItemType Directory -Path $DataDir -Force | Out-Null }
    Add-Content -LiteralPath $LogFile -Value ('[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg) -Encoding UTF8
  } catch { }
}

# D:\我的 文档\a.md  ->  file:///D:/%E6%88%91%E7%9A%84%20%E6%96%87%E6%A1%A3/a.md
function ConvertTo-FileUrl([string]$abs) {
  $raw  = $abs.Replace('\', '/')
  $unc  = $raw.StartsWith('//')
  $body = (($raw.TrimStart([char[]]@('/')) -split '/') | ForEach-Object {
    [uri]::EscapeDataString($_).Replace('%3A', ':')      # 保留盘符后的冒号
  }) -join '/'
  if ($unc) { return 'file://' + $body }
  return 'file:///' + $body
}

# 生成 JSON/JS 字符串字面量；非 ASCII 一律转 \uXXXX，保证会话文件是纯 ASCII
function ConvertTo-JsonString([string]$s) {
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append('"')
  foreach ($ch in $s.ToCharArray()) {
    $code = [int]$ch
    if ($ch -eq '"')          { [void]$sb.Append('\"') }
    elseif ($ch -eq '\')      { [void]$sb.Append('\\') }
    elseif ($code -eq 8)      { [void]$sb.Append('\b') }
    elseif ($code -eq 9)      { [void]$sb.Append('\t') }
    elseif ($code -eq 10)     { [void]$sb.Append('\n') }
    elseif ($code -eq 12)     { [void]$sb.Append('\f') }
    elseif ($code -eq 13)     { [void]$sb.Append('\r') }
    elseif ($code -lt 32 -or $code -gt 126) { [void]$sb.Append('\u' + $code.ToString('x4')) }
    else                      { [void]$sb.Append($ch) }
  }
  [void]$sb.Append('"')
  return $sb.ToString()
}

# 优先 Edge（Windows 自带），其次 Chrome
function Find-Browser {
  $cands = @(
    (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
    (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe'),
    (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
    (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
  )
  foreach ($c in $cands) {
    if ($c -and (Test-Path -LiteralPath $c)) { return $c }
  }
  return $null
}

function Get-MarkdownFiles([string]$rootPath) {
  # 用 -First 惰性截断，避免超大目录全量枚举。此处不排序：Windows PowerShell(5.1) 与
  # pwsh(7) 的枚举/排序规则不同，而页面会按 rel 重新排序，清单顺序不影响最终结果。
  return @(
    Get-ChildItem -LiteralPath $rootPath -Recurse -File -ErrorAction SilentlyContinue |
      Where-Object { $MdExt -contains $_.Extension.ToLower() } |
      Select-Object -First ($MaxFiles + 1)
  )
}

function Invoke-Launcher {
  if (-not (Test-Path -LiteralPath $IndexHtml)) { throw "找不到 $IndexHtml（仓库是否被移动了？）" }

  # ---------- 1. 解析目标 ----------
  $paths  = @($Path | Where-Object { $_ -and $_.Trim() })
  $target = $null      # 要打开的文件
  $root   = $null      # 文件树根目录
  $extra  = @()        # 多选时额外带上的文件

  if (-not $NoSession -and $paths.Count -gt 0) {
    $first = $paths[0]
    if (Test-Path -LiteralPath $first) {
      $item = Get-Item -LiteralPath $first -Force
      if ($item.PSIsContainer) {
        $root = $item.FullName
        $cand = Get-MarkdownFiles $root
        if ($cand.Count -gt 0) { $target = $cand[0].FullName }
      } else {
        $root   = Split-Path -Parent $item.FullName
        $target = $item.FullName
        $extra  = @($paths | Select-Object -Skip 1)
      }
    } else {
      Write-Log "传入的路径不存在，忽略：$first"
    }
  }

  # ---------- 2. 写会话文件 ----------
  $url = ConvertTo-FileUrl $IndexHtml
  $sessFile = $null

  if ($target -and $root) {
    $rootName = Split-Path -Leaf $root
    if (-not $rootName) { $rootName = $root.TrimEnd('\', '/') }

    $list = @(Get-MarkdownFiles $root)
    $trunc = $false
    if ($list.Count -gt $MaxFiles) { $trunc = $true; $list = @($list | Select-Object -First $MaxFiles) }

    # 保证「要打开的文件」一定在清单里（列表被截断或不在根目录时）
    foreach ($must in (@($target) + $extra)) {
      if (-not $must) { continue }
      if (-not ($list | Where-Object { $_.FullName -eq $must })) {
        $mi = Get-Item -LiteralPath $must -Force -ErrorAction SilentlyContinue
        if ($mi -and -not $mi.PSIsContainer) { $list = @($mi) + @($list) }
      }
    }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('window.__MDR_SESSION__={v:1,root:')
    [void]$sb.Append((ConvertTo-JsonString $root))
    [void]$sb.Append(',open:')
    [void]$sb.Append((ConvertTo-JsonString $target))
    [void]$sb.Append(',trunc:')
    [void]$sb.Append($(if ($trunc) { 'true' } else { 'false' }))
    [void]$sb.Append(',files:[')
    $firstItem = $true
    foreach ($f in $list) {
      if (-not $firstItem) { [void]$sb.Append(',') }
      $firstItem = $false
      if ($f.FullName.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
        $tail = $f.FullName.Substring($root.Length).TrimStart([char[]]@('\', '/')).Replace('\', '/')
        $rel  = $rootName + '/' + $tail
      } else {
        $rel  = $rootName + '/' + $f.Name          # 多选时不在根目录下的文件
      }
      [void]$sb.Append('[' + (ConvertTo-JsonString $rel) + ',' + (ConvertTo-JsonString $f.FullName) + ',' + $f.Length + ']')
    }
    [void]$sb.Append(']};')

    # 结构自检：会话文件必须是合法 JSON 形状，否则宁可报错也不要让页面悄悄打不开
    $js = $sb.ToString()
    if ($js -notmatch '^window\.__MDR_SESSION__=\{v:1,root:".*",open:".*",trunc:(true|false),files:\[.*\]\};$') {
      throw '会话文件生成异常（结构自检未通过）'
    }

    if (-not (Test-Path -LiteralPath $SessDir)) { New-Item -ItemType Directory -Path $SessDir -Force | Out-Null }
    # 文件名每次都不同：避免浏览器复用旧窗口时仍读到上一次的会话
    $sessFile = Join-Path $SessDir ('session-' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss-fff') + '.js')
    [System.IO.File]::WriteAllText($sessFile, $js, (New-Object System.Text.UTF8Encoding($false)))
    $url = $url + '#session=' + [uri]::EscapeDataString($sessFile)

    # 清理过期会话
    try {
      Get-ChildItem -LiteralPath $SessDir -Filter 'session-*.js' -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$KeepDays) } |
        Remove-Item -Force -ErrorAction SilentlyContinue
    } catch { }
  }

  if ($DryRun) {
    Write-Output $url
    return
  }

  # ---------- 3. 启动浏览器 ----------
  $browser = Find-Browser
  if (-not $browser) { throw '没找到 Microsoft Edge 或 Google Chrome，无法启动。' }

  $browserArgs = @(
    ('--app=' + $url),
    '--allow-file-access-from-files',
    ('--user-data-dir=' + $ProfileDir),
    '--no-first-run',
    '--no-default-browser-check',
    '--disable-features=Translate',
    '--window-size=1280,900'
  )

  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName        = $browser
  $psi.UseShellExecute = $false
  $psi.Arguments       = (($browserArgs | ForEach-Object { '"' + $_.Replace('"', '\"') + '"' }) -join ' ')
  [void][System.Diagnostics.Process]::Start($psi)

  Write-Log ("已启动 {0}；会话：{1}" -f (Split-Path -Leaf $browser), $(if ($sessFile) { $sessFile } else { '(无文件)' }))
}

try {
  Invoke-Launcher
  exit 0
} catch {
  Write-Log ("失败：{0}`r`n{1}" -f $_.Exception.Message, $_.ScriptStackTrace)
  if ($DryRun) { Write-Error $_ }
  exit 1
}
