# AGENTS.md — markdown-reader

## 仓库位置（重要）

本项目的**唯一权威位置**是：

```
D:\GitHub\markdown-reader
```

早期它曾在 `D:\My Documents\GitHub\markdown-reader`（OneDrive 同步的「文档」目录下）。
**那个路径已经废弃**，现在是一个空目录，里面没有任何项目文件。任何指向它的路径、脚本或
记忆都是过时的，请一律以 `D:\GitHub\markdown-reader` 为准。

> DSH 的工作区注册表里的 `markdown-reader` 记录可能仍然指向旧路径（workspace 的 `path`
> 在设计上是创建时固定的、不可修改）。如果某个会话的默认工作目录被解析成了旧的
> `D:\My Documents\GitHub\markdown-reader`，那个目录是空的——请改用绝对路径
> `D:\GitHub\markdown-reader\...`，或在 shell 里先 `cd D:\GitHub\markdown-reader`。
> 彻底修法是在 DSH GUI 里重新「添加工作区」指向新路径（见下）。

## 项目要点

单文件、纯离线的 Markdown 阅读器：`index.html` 是**构建产物**，双击即用。

- `src/part1.html`（head + CSS + 静态骨架）、`src/app.js`（全部逻辑）是**源**；
  `src/part2~4.html` 是拼接用的「缝」。
- **改完 `src/` 必须重建 `index.html`，两者一起提交**（构建命令见 `README.md` 末尾）。
- 动手前先读 `DESIGN.md`——它有架构图、函数索引和「修改速查表」。
- UI 文案一律走 `tr(key)` / `data-i18n`，中英两套都要补（见 `DESIGN.md` §4.4）。
- 自测：`node --check src/app.js`，然后浏览器打开 `index.html#selftest`。
