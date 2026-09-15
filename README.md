# 📖 Markdown 浏览器（单文件 HTML）

双击 **`index.html`** 即可使用。无需安装、无需服务器、无需网络——`marked` 与 `DOMPurify` 已内嵌在页面中，纯本地运行。

## 使用方法

1. 双击打开 `index.html`（用 Chrome / Edge / Firefox 等现代浏览器）。
2. 点击 **「打开文件夹」** 选择一个本地目录（支持子文件夹），页面会自动列出其中全部 Markdown 文件（`.md` / `.markdown` / `.mdown` / `.mkd` / `.mdx`）。
3. 也可以点 **「打开文件」** 多选单个文件，或直接把文件夹 / 文件**拖进页面**。
4. 点击左侧文件即可浏览渲染后的内容。

## 右键「打开方式」打开 .md（Windows）

在资源管理器里右键 `.md` → **打开方式 → Markdown Reader**，直接用它打开。只需安装一次：

1. 双击 **`tools\install-open-with.cmd`**（卸载：双击 `tools\uninstall-open-with.cmd`）。
   只写 `HKEY_CURRENT_USER`，**不需要管理员权限**，也不改动系统默认关联。
2. 之后右键任意 `.md` / `.markdown` / `.mdown` / `.mkd` / `.mdx` → 打开方式 → **Markdown Reader**。
3. 想让它变成双击的默认程序：右键 → 打开方式 → 选择其他应用 → 选 **Markdown Reader**
   → 勾选「始终使用此应用打开 .md 文件」。

### 为什么不直接把 index.html 关联过去

浏览器出于安全限制，**`file://` 页面默认读不到任何本地文件**（实测：不加启动参数时，
页面里 `fetch` / `XHR` 读本地文件一律失败）。所以中间需要一个启动器把文件路径递进去：

1. `tools/open-with.vbs`（隐藏窗口，不闪黑框）收到资源管理器传来的路径，转交 `tools/open-with.ps1`。
2. 脚本把「要打开的文件 + 它所在目录（含子目录）的全部 Markdown 清单」写成一个会话脚本：
   `%LOCALAPPDATA%\MarkdownReader\sessions\session-*.js`。
3. 用 Edge（优先）或 Chrome，以**专用配置目录 + 应用模式窗口**打开
   `index.html#session=<会话脚本绝对路径>`，并加上 `--allow-file-access-from-files`。
4. 页面启动时用 `<script src>` 载入会话脚本（`file://` 页面加载同协议脚本不受 CORS 限制），
   再按绝对路径读取正文；正文里的相对图片被改写成绝对 `file://` 地址交给 `<img>`
   （图片加载本身不需要任何额外权限）。

### 菜单里的名字与图标

「打开方式」菜单里显示的名字，取自**命令行中那个可执行文件自己的版本信息**——所以不能直接让
`wscript.exe` 去跑脚本：那样菜单里会显示成「Microsoft ® Windows Based Script Host」，而
`HKLM\...\Applications\wscript.exe` 是系统级键，改了会连带污染全系统的脚本宿主名称；菜单里那一行的
图标同理也来自可执行文件。

因此安装时会用系统自带的 `csc.exe`（.NET Framework 编译器），把 `tools/MarkdownReaderLauncher.cs`
编译成一个二十来行的小外壳 `%LOCALAPPDATA%\MarkdownReader\MarkdownReader.exe`（GUI 子系统，
不会闪黑框），它的程序集标题就是 `Markdown Reader`；同时用 `System.Drawing` 现画一个 `M↓` 图标
`MarkdownReader.ico`（也用作 `.md` 的文件图标）。这些只写 `%LOCALAPPDATA%`，不需要管理员权限。
若 `csc.exe` 不可用，安装会自动回退到 `open-with.vbs`（功能完全一样，只是菜单里显示脚本宿主）。

请留意：

- 阅读器窗口用的是**独立浏览器配置目录** `%LOCALAPPDATA%\MarkdownReader\profile`，
  与你日常浏览的窗口互不干扰；`--allow-file-access-from-files` 也只在这个目录里生效，
  **不要用它上网**。
- 侧栏文件树以「被打开文件所在目录」为根（含子目录），只列 Markdown 文件。
- 「打开方式」启动的会话**不写入 IndexedDB 缓存**，不会覆盖你平时「打开文件夹」的「恢复上次」记录。
- 出问题先看日志 `%LOCALAPPDATA%\MarkdownReader\open-with.log`；
  手动排查可用 `powershell -File tools\open-with.ps1 "D:\docs\a.md" -DryRun`
  （只生成会话并打印 URL，不启动浏览器）。
- 依赖 Windows 自带的 PowerShell 与 Edge（或 Chrome）——`index.html` 本身依旧是纯静态单文件，
  双击照常可用。

## 功能

- **文件树**：按目录层级展示，可折叠；侧栏宽度可拖拽调整
- **搜索**：文件名过滤；勾选「全文」后可在所有已加载文件中搜索，显示行号与上下文摘要，点击结果自动跳转并高亮
- **Markdown 渲染**：标题、表格、任务列表、代码块、引用、链接、图片等（GFM 风格）
- **代码一键复制**：每个代码块右上角提供「复制」按钮（悬停出现，触屏设备常显），点击即可复制整段代码
- **相对路径资源**：文中引用的相对路径图片（同一文件夹内）可直接显示
- **站内跳转**：点击指向其他 `.md` 的相对链接可直接切换阅读
- **目录（TOC）**：自动提取标题生成目录面板，点击平滑跳转
- **快捷浏览**：`←` / `→` 在文件间切换；工具栏提供上一个 / 下一个、源文本视图、复制原文
- **编码自适应**：自动识别 UTF-8，失败时回退 GBK（常见于中文旧文件）
- **主题切换**：🌙 / ☀️ 深色浅色，记住你的选择
- **多语言界面**：🌐 一键切换中文 / English，默认中文；选择会被记住（只翻译界面，不翻译正文）
- **离线缓存**：打开文件夹时内容自动存入 IndexedDB；下次打开页面可在左侧「恢复上次」一键继续浏览（无需重新选目录）

## 注意事项

- 浏览器出于安全限制无法记住文件夹的访问权限：修改过的文件需重新点一次「打开文件夹」即可刷新内容（同路径文件自动替换）。
- 页面完全离线工作，文件内容不会上传到任何地方。
- 若浏览器阻止了 IndexedDB / localStorage（极少数情况），缓存与主题记忆功能会静默降级，其余功能不受影响。

## 文件说明

| 文件 | 说明 |
| --- | --- |
| `index.html` | **成品**，单文件，直接使用 |
| `src/part1~4.html`、`src/app.js` | 页面源码（构建时与库拼接） |
| `libs/` | 内嵌的 `marked`（MIT）与 `DOMPurify`（Apache-2.0 / MPL-2.0）及许可证 |
| `tools/install-open-with.cmd` | 双击安装「打开方式」注册表项（HKCU，免管理员）——只是一层双击外壳 |
| `tools/uninstall-open-with.cmd` | 双击卸载（同一个脚本，加 `-Uninstall`） |
| `tools/install-open-with.ps1` | 安装/卸载的实际实现：生成图标、编译启动器、写 / 删注册表项 |
| `tools/MarkdownReaderLauncher.cs` | 启动外壳源码（编译成 `MarkdownReader.exe`，菜单里显示的名字就取自它） |
| `tools/open-with.ps1` | 启动器实现：写会话文件 + 拉起浏览器应用窗口（`-DryRun` 可排查） |
| `tools/open-with.vbs` | 备用外壳：只有 `csc.exe` 不可用、编译不出 exe 时才会用到 |
| `DESIGN.md` | 📐 **软件设计文档**：架构图、数据模型、核心流程、函数索引、修改速查表（改代码前建议先读） |

> `tools/` 下的文件对编码有硬要求（否则中文乱码甚至语法报错）：
> `*.ps1` 必须存成 **UTF-8 带 BOM**（Windows PowerShell 5.1 会把无 BOM 的 UTF-8 当 GBK 解析），
> `*.vbs` 必须存成 **UTF-16LE**（WScript 默认按 ANSI 解析），`*.cmd` 的注释放 ASCII 最稳。
> 每个文件头部都写了各自的角色，详见 `DESIGN.md` §12。

重新构建 `index.html`（PowerShell）：

```powershell
node --check src/app.js
$p1 = Get-Content -Raw 'src/part1.html'; $p2 = Get-Content -Raw 'src/part2.html'
$p3 = Get-Content -Raw 'src/part3.html'; $p4 = Get-Content -Raw 'src/part4.html'
$app = Get-Content -Raw 'src/app.js'
$mk  = (Get-Content -Raw 'libs/marked.umd.js').Replace('</script','<\/script')
$pu  = (Get-Content -Raw 'libs/purify.min.js').Replace('</script','<\/script')
[System.IO.File]::WriteAllText((Join-Path $PWD 'index.html'), ($p1+$mk+$p2+$pu+$p3+$app+$p4), (New-Object System.Text.UTF8Encoding($false)))
```

> 自测：在浏览器地址栏给 `index.html` 加 `#selftest` 后缀可自动渲染一段示例 Markdown 并生成目录，便于快速验证页面正常。
