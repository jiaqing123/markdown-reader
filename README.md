# 📖 Markdown 浏览器（单文件 HTML）

双击 **`index.html`** 即可使用。无需安装、无需服务器、无需网络——`marked` 与 `DOMPurify` 已内嵌在页面中，纯本地运行。

## 使用方法

1. 双击打开 `index.html`（用 Chrome / Edge / Firefox 等现代浏览器）。
2. 点击 **「打开文件夹」** 选择一个本地目录（支持子文件夹），页面会自动列出其中全部 Markdown 文件（`.md` / `.markdown` / `.mdown` / `.mkd` / `.mdx`）。
3. 也可以点 **「打开文件」** 多选单个文件，或直接把文件夹 / 文件**拖进页面**。
4. 点击左侧文件即可浏览渲染后的内容。

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
| `DESIGN.md` | 📐 **软件设计文档**：架构图、数据模型、核心流程、函数索引、修改速查表（改代码前建议先读） |

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
