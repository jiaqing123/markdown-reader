'use strict';
/* ============================================================
   Markdown 浏览器 — 应用逻辑（纯前端，无服务器、无网络依赖）
   ============================================================ */
(function () {
  'use strict';

  var $  = function (s) { return document.querySelector(s); };
  var $$ = function (s) { return Array.prototype.slice.call(document.querySelectorAll(s)); };

  var MD_RE = /\.(md|markdown|mdown|mkd|mdx)$/i;
  var MAX_CACHE_TEXT = 4 * 1024 * 1024;   // 单文件缓存上限 4MB
  var MAX_IMG = 4 * 1024 * 1024;          // 图片解析上限 4MB

  var state = {
    files: [],            // [{name, rel, size, file, text, from, error}]
    allFiles: new Map(),  // rel -> File（含图片等非 md 文件，用于解析相对路径图片）
    current: null,
    visible: [],
    filter: '',
    contentSearch: false,
    reading: false,
    rawMode: false,
    imageUrls: new Map()  // rel -> objectURL
  };

  var SANITIZE_CFG = {
    ADD_TAGS: ['input', 'mark'],
    ADD_ATTR: ['checked', 'disabled', 'type', 'target'],
    ALLOWED_URI_REGEXP: /^(?:(?:https?|ftp|mailto|tel|data|blob):|[^a-z]|[a-z+.\-]+(?:[^a-z+.\-:]|$))/i
  };
  function sanitizeHtml(html) {
    if (window.DOMPurify) { try { return DOMPurify.sanitize(html, SANITIZE_CFG); } catch (e) { return html; } }
    return html;
  }

  /* ---------- 小工具 ---------- */
  function sleep(ms) { return new Promise(function (r) { setTimeout(r, ms); }); }

  function esc(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  function toast(msg) {
    var t = $('#toast');
    t.textContent = msg;
    t.classList.add('show');
    clearTimeout(t._h);
    t._h = setTimeout(function () { t.classList.remove('show'); }, 2200);
  }

  function fmtSize(n) {
    if (n >= 1048576) return (n / 1048576).toFixed(1) + 'M';
    if (n >= 1024) return Math.round(n / 1024) + 'K';
    return n + 'B';
  }

  function decode(buf) {
    try { return new TextDecoder('utf-8', { fatal: true }).decode(buf); } catch (e) { /* 尝试其他编码 */ }
    try { return new TextDecoder('gbk').decode(buf); } catch (e) { /* 最后退回 UTF-8 */ }
    return new TextDecoder('utf-8').decode(buf);
  }

  async function readText(file) {
    var buf = await file.arrayBuffer();
    return decode(buf);
  }

  function slugify(t) {
    var s = String(t).trim().toLowerCase().replace(/\s+/g, '-').replace(/[^\w\u4e00-\u9fa5-]+/g, '');
    return s || 'sec';
  }

  function folderName() {
    if (!state.files.length) return '';
    var tops = new Set(state.files.map(function (f) { return f.rel.split('/')[0]; }));
    return tops.size === 1 ? Array.from(tops)[0] : '多个位置';
  }

  /* ---------- IndexedDB 缓存 ---------- */
  function idbOpen() {
    return new Promise(function (resolve, reject) {
      var req;
      try { req = indexedDB.open('markdown-reader', 1); }
      catch (e) { reject(e); return; }
      req.onupgradeneeded = function () { try { req.result.createObjectStore('kv'); } catch (e) { /* 已存在 */ } };
      req.onsuccess = function () { resolve(req.result); };
      req.onerror = function () { reject(req.error); };
    });
  }
  function idbGet(db, key) {
    return new Promise(function (resolve, reject) {
      var tx = db.transaction('kv', 'readonly');
      var q = tx.objectStore('kv').get(key);
      q.onsuccess = function () { resolve(q.result); };
      q.onerror = function () { reject(q.error); };
    });
  }
  function idbPut(db, key, val) {
    return new Promise(function (resolve, reject) {
      var tx = db.transaction('kv', 'readwrite');
      tx.objectStore('kv').put(val, key);
      tx.oncomplete = function () { resolve(); };
      tx.onerror = function () { reject(tx.error); };
    });
  }
  function idbDel(db, key) {
    return new Promise(function (resolve, reject) {
      var tx = db.transaction('kv', 'readwrite');
      tx.objectStore('kv').delete(key);
      tx.oncomplete = function () { resolve(); };
      tx.onerror = function () { reject(tx.error); };
    });
  }

  async function saveCache(metaOnly) {
    try {
      var db = await idbOpen();
      var prev = null;
      try { prev = await idbGet(db, 'last'); } catch (e) { /* 无旧缓存 */ }
      var prevTexts = new Map((prev && prev.files || []).map(function (f) { return [f.rel, f.text]; }));
      var entry = {
        id: 'last',
        savedAt: Date.now(),
        folder: folderName() || (prev && prev.folder) || '',
        files: state.files.map(function (f) {
          var t = (!metaOnly && f.text && f.text.length <= MAX_CACHE_TEXT) ? f.text : prevTexts.get(f.rel);
          return { name: f.name, rel: f.rel, size: f.size, text: t || null };
        })
      };
      await idbPut(db, 'last', entry);
    } catch (e) { /* 缓存失败不影响使用 */ }
    refreshRestoreBanner();
  }

  async function refreshRestoreBanner() {
    try {
      var db = await idbOpen();
      var entry = await idbGet(db, 'last');
      var el = $('#restoreBanner');
      if (!entry || !entry.files || !entry.files.length) { el.hidden = true; return; }
      if (state.files.length) { el.hidden = true; return; }
      var n = entry.files.length;
      el.innerHTML =
        '<div class="rb-title">📂 恢复上次：' + esc(entry.folder || '文件夹') + '</div>' +
        '<div class="rb-meta">' + n + ' 个文件 · 缓存于 ' + esc(new Date(entry.savedAt).toLocaleString()) + '</div>' +
        '<div class="rb-btns"><button id="btnRestore" class="primary small">恢复</button><button id="btnDelCache" class="small">清除缓存</button></div>';
      el.hidden = false;
      $('#btnRestore').onclick = function () {
        state.files = entry.files.map(function (x) {
          return { name: x.name, rel: x.rel, size: x.size, text: x.text, file: null, from: 'cache' };
        });
        state.files.sort(function (a, b) { return a.rel.localeCompare(b.rel, undefined, { numeric: true }); });
        renderTree();
        saveCache();
        toast('已从缓存恢复，重新「打开文件夹」可刷新内容');
        if (state.files.length) openFile(state.files[0]);
      };
      $('#btnDelCache').onclick = async function () {
        try { await idbDel(db, 'last'); } catch (e) { /* 忽略 */ }
        el.hidden = true;
        toast('缓存已清除');
      };
    } catch (e) { /* 浏览器不支持 IndexedDB 时静默降级 */ }
  }

  /* ---------- 打开文件 / 文件夹 ---------- */
  function pickFolder() {
    if (window.showDirectoryPicker) {
      showDirectoryPicker().catch(function (err) {
        if (err && err.name === 'AbortError') return;   // 用户取消
        $('#dirInput').click();                          // 回退到目录选择输入框
      });
      return;
    }
    $('#dirInput').click();
  }

  async function showDirectoryPicker() {
    var dir = await window.showDirectoryPicker({ mode: 'read' });
    var mdList = [];
    async function walk(d, prefix) {
      for await (const [name, h] of d.entries()) {
        if (h.kind === 'directory') { await walk(h, prefix + name + '/'); }
        else {
          var file;
          try { file = await h.getFile(); } catch (e) { continue; }
          var key = prefix + name;
          if (!state.allFiles.has(key)) state.allFiles.set(key, file);
          if (MD_RE.test(name)) mdList.push({ name: name, rel: key, size: file.size, file: file, text: null, from: 'picker' });
        }
      }
    }
    await walk(dir, dir.name + '/');
    await addFiles(mdList);
  }

  async function handleDropped(files) {
    if (!files || !files.length) return;
    var mdList = [];
    var seen = new Set();
    for (var i = 0; i < files.length; i++) {
      var f = files[i];
      var rel = f.webkitRelativePath || f.name;
      if (seen.has(rel)) continue;
      seen.add(rel);
      if (!state.allFiles.has(rel)) state.allFiles.set(rel, f);
      if (MD_RE.test(f.name)) mdList.push({ name: f.name, rel: rel, size: f.size, file: f, text: null, from: 'file' });
    }
    if (mdList.length) await addFiles(mdList);
    else toast('未找到 Markdown 文件');
  }

  async function addFiles(list) {
    if (!list || !list.length) { toast('未找到 Markdown 文件'); return; }
    var freshRels = new Set(list.map(function (f) { return f.rel; }));
    var replaced = state.files.filter(function (f) { return freshRels.has(f.rel); }).length;
    state.files = state.files.filter(function (f) { return !freshRels.has(f.rel); }).concat(list);
    state.files.sort(function (a, b) { return a.rel.localeCompare(b.rel, undefined, { numeric: true }); });
    renderTree();
    saveCache(true);   // 先保存元数据，防止中途关闭丢失

    state.reading = true;
    showProgress();
    var done = 0;
    for (var i = 0; i < list.length; i++) {
      if (!state.reading) break;   // 用户取消：已读取的保留，未读取的稍后可再读
      try { list[i].text = await readText(list[i].file); }
      catch (e) { list[i].text = null; list[i].error = '读取失败'; }
      done++;
      updateProgress(done, list.length, list[i].name);
      await sleep(0);
    }
    state.reading = false;
    hideProgress();
    renderTree();
    saveCache();
    toast((replaced ? '已刷新 ' + replaced + ' 个，' : '') + '加载 ' + list.length + ' 个 Markdown 文件');
    if (!state.current && state.files.length) openFile(state.files[0]);
  }

  /* ---------- 列表渲染 ---------- */
  function currentList(q) {
    if (!q) return state.files;
    return state.files.filter(function (f) {
      return f.name.toLowerCase().includes(q) || f.rel.toLowerCase().includes(q);
    });
  }

  function buildTree(files) {
    var root = { name: '', children: new Map(), files: [] };
    for (var i = 0; i < files.length; i++) {
      var parts = files[i].rel.split('/');
      var node = root;
      for (var j = 0; j < parts.length - 1; j++) {
        if (!node.children.has(parts[j])) node.children.set(parts[j], { name: parts[j], children: new Map(), files: [] });
        node = node.children.get(parts[j]);
      }
      node.files.push(files[i]);
    }
    return root;
  }

  function renderNode(node) {
    var frag = document.createDocumentFragment();
    var dirs = Array.from(node.children.keys()).sort(function (a, b) { return a.localeCompare(b, undefined, { numeric: true }); });
    for (var i = 0; i < dirs.length; i++) {
      var det = document.createElement('details');
      det.open = true;
      var sum = document.createElement('summary');
      sum.textContent = '📁 ' + dirs[i];
      det.appendChild(sum);
      det.appendChild(renderNode(node.children.get(dirs[i])));
      frag.appendChild(det);
    }
    for (var j = 0; j < node.files.length; j++) {
      var f = node.files[j];
      var row = document.createElement('div');
      row.className = 'file-row';
      row.dataset.rel = f.rel;
      row.title = f.rel + (f.error ? '\n' + f.error : '');
      var icon = document.createElement('span');
      icon.textContent = '📄';
      var nm = document.createElement('span');
      nm.className = 'fr-name';
      nm.textContent = f.name;
      var sz = document.createElement('span');
      sz.className = 'fr-size';
      sz.textContent = fmtSize(f.size);
      row.appendChild(icon);
      row.appendChild(nm);
      row.appendChild(sz);
      row.addEventListener('click', (function (ff) { return function () { openFile(ff); }; })(f));
      frag.appendChild(row);
    }
    return frag;
  }

  function renderSearchResults(box, q) {
    var results = [];
    var cap = 300;
    for (var i = 0; i < state.files.length; i++) {
      var f = state.files[i];
      if (!f.text) continue;
      var lines = f.text.split('\n');
      for (var j = 0; j < lines.length; j++) {
        if (lines[j].toLowerCase().indexOf(q) >= 0) {
          results.push({ f: f, line: j + 1, snippet: lines[j].trim().slice(0, 160) });
          if (results.length >= cap) break;
        }
      }
      if (results.length >= cap) break;
    }
    state.visible = results.map(function (r) { return r.f; });
    if (!results.length) {
      box.innerHTML = '<div class="empty">未找到包含「' + esc(q) + '」的内容</div>';
      updateStatus();
      return;
    }
    var phrase = state.filter.trim().slice(0, 60);
    for (var k = 0; k < results.length; k++) {
      var r = results[k];
      var row = document.createElement('div');
      row.className = 'sr-row';
      var head = document.createElement('div');
      head.className = 'sr-head';
      head.textContent = '📄 ' + r.f.rel;
      var sn = document.createElement('div');
      sn.className = 'sr-snip';
      sn.textContent = '第 ' + r.line + ' 行：' + r.snippet;
      row.appendChild(head);
      row.appendChild(sn);
      row.addEventListener('click', (function (ff) { return function () { openFile(ff, phrase); }; })(r.f));
      box.appendChild(row);
    }
    updateStatus('全文搜索：' + results.length + ' 处匹配');
  }

  function renderTree() {
    var box = $('#fileList');
    box.innerHTML = '';
    if (!state.files.length) {
      box.innerHTML = '<div class="empty">尚未打开任何文件夹<br>点击上方「打开文件夹」，<br>或直接把文件夹拖到页面</div>';
      state.visible = [];
      updateStatus();
      return;
    }
    var q = state.filter.trim().toLowerCase();
    if (q && state.contentSearch) { renderSearchResults(box, q); return; }
    var list = currentList(q);
    state.visible = list;
    box.appendChild(renderNode(buildTree(list)));
    updateStatus();
    markActive();
  }

  function markActive() {
    var rel = state.current && state.current.rel;
    $$('#fileList .file-row').forEach(function (r) { r.classList.toggle('active', r.dataset.rel === rel); });
    var el = $('#fileList .file-row.active');
    if (el) el.scrollIntoView({ block: 'nearest' });
  }

  function updateStatus(msg) {
    $('#headerStatus').textContent = state.files.length ? folderName() + ' · ' + state.files.length + ' 个文件' : '';
    $('#sideStatus').textContent = msg || (state.files.length
      ? state.files.length + ' 个 Markdown 文件' + (state.filter ? ' · 显示 ' + state.visible.length : '')
      : '未打开文件夹，可拖入或点击「打开文件夹」');
  }

  /* ---------- 阅读 ---------- */
  async function openFile(f, phrase) {
    if (!f) return;
    state.current = f;
    state.rawMode = false;
    $('#btnRaw').classList.remove('on');
    $('#tocPanel').hidden = true;
    $('#btnToc').classList.remove('on');
    $('#welcome').hidden = true;
    $('#toolbar').hidden = false;
    $('#filePath').textContent = f.rel;
    document.title = f.name + ' · Markdown 浏览器';
    markActive();

    var doc = $('#doc');
    if (f.text == null && !f.file) {
      doc.innerHTML = '<div class="err">该文件内容未缓存。请重新「打开文件夹」后再浏览。</div>';
      updateNav();
      return;
    }
    if (f.text == null && f.file) {
      try { f.text = await readText(f.file); }
      catch (e) { f.text = ''; f.error = '读取失败'; }
    }

    for (var u of state.imageUrls.values()) URL.revokeObjectURL(u);
    state.imageUrls.clear();

    var html;
    try { html = marked.parse(f.text || ''); }
    catch (e) { html = '<div class="err">Markdown 解析失败：' + esc((e && e.message) || e) + '</div>'; }
    html = sanitizeHtml(html);
    html = html.replace(/<a /g, '<a target="_blank" rel="noopener" ');
    doc.innerHTML = html;

    ensureHeadingIds(doc);
    buildToc(doc);
    $('#article').scrollTop = 0;
    resolveImages(doc, f);
    if (phrase) highlightInArticle(doc, phrase);
    updateNav();
  }

  function stepNav(d) {
    var idx = state.visible.indexOf(state.current);
    var nf = state.visible[idx + d];
    if (nf) openFile(nf);
  }

  function updateNav() {
    var idx = state.visible.indexOf(state.current);
    $('#btnPrev').disabled = idx <= 0;
    $('#btnNext').disabled = idx < 0 || idx >= state.visible.length - 1;
    $('#navPos').textContent = idx >= 0 ? (idx + 1) + ' / ' + state.visible.length : '';
  }

  function ensureHeadingIds(doc) {
    var seen = new Map();
    var hs = doc.querySelectorAll('h1,h2,h3,h4,h5,h6');
    for (var i = 0; i < hs.length; i++) {
      var s = slugify(hs[i].textContent);
      var n = (seen.get(s) || 0) + 1;
      seen.set(s, n);
      hs[i].id = n > 1 ? s + '-' + n : s;
    }
  }

  function buildToc(doc) {
    var heads = Array.prototype.map.call(doc.querySelectorAll('h1,h2,h3,h4'), function (h) {
      return { level: +h.tagName[1], id: h.id, text: h.textContent };
    });
    var panel = $('#tocPanel');
    panel.innerHTML = '<h6>目录</h6>';
    if (!heads.length) return;
    var ul = document.createElement('ul');
    for (var i = 0; i < heads.length; i++) {
      var h = heads[i];
      var li = document.createElement('li');
      li.className = 'toc-l' + h.level;
      var a = document.createElement('a');
      a.href = '#' + h.id;
      a.textContent = h.text;
      a.addEventListener('click', function (e) {
        e.preventDefault();
        var el = document.getElementById(h.id);
        if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' });
      });
      li.appendChild(a);
      ul.appendChild(li);
    }
    panel.appendChild(ul);
  }

  async function resolveImages(doc, f) {
    var imgs = Array.prototype.slice.call(doc.querySelectorAll('img'));
    var base = f.rel.split('/').slice(0, -1);
    for (var i = 0; i < imgs.length; i++) {
      var img = imgs[i];
      var src = img.getAttribute('src') || '';
      if (!src || /^(https?:|data:|blob:|#)/i.test(src)) continue;
      var clean = src.split(/[?#]/)[0];
      var segs = base.slice();
      var parts = clean.split('/');
      for (var j = 0; j < parts.length; j++) {
        var p = parts[j];
        if (p === '.' || p === '') continue;
        if (p === '..') segs.pop();
        else segs.push(p);
      }
      var file = state.allFiles.get(segs.join('/'));
      if (!file) continue;
      try {
        var blob = file.getFile ? await file.getFile() : file;
        if (blob.size > MAX_IMG) continue;
        var url = URL.createObjectURL(blob);
        state.imageUrls.set(segs.join('/'), url);
        img.src = url;
      } catch (e) { /* 单个图片失败不影响其余 */ }
      await sleep(0);
    }
  }

  function highlightInArticle(doc, phrase) {
    var q = String(phrase || '').trim();
    if (!q) return;
    var lq = q.toLowerCase();
    var walker = document.createTreeWalker(doc, NodeFilter.SHOW_TEXT);
    var targets = [];
    while (walker.nextNode()) {
      if (walker.currentNode.textContent.toLowerCase().indexOf(lq) >= 0) targets.push(walker.currentNode);
      if (targets.length >= 30) break;
    }
    for (var i = 0; i < targets.length; i++) {
      var t = targets[i];
      var idx = t.textContent.toLowerCase().indexOf(lq);
      if (idx < 0) continue;
      var range = document.createRange();
      range.setStart(t, idx);
      range.setEnd(t, idx + q.length);
      var mark = document.createElement('mark');
      try { range.surroundContents(mark); } catch (e) { /* 跨元素边界时跳过 */ }
    }
    var first = doc.querySelector('mark');
    if (first) first.scrollIntoView({ block: 'center' });
  }

  function toggleRaw() {
    var f = state.current;
    if (!f) return;
    state.rawMode = !state.rawMode;
    $('#btnRaw').classList.toggle('on', state.rawMode);
    var art = $('#article');
    var doc = $('#doc');
    if (state.rawMode) {
      art.dataset.prev = doc.innerHTML;
      doc.innerHTML = '<pre class="rawview">' + esc(f.text == null ? '（无内容）' : f.text) + '</pre>';
    } else if (art.dataset.prev) {
      doc.innerHTML = art.dataset.prev;
      delete art.dataset.prev;
    }
  }

  async function copyRaw() {
    var f = state.current;
    if (!f || f.text == null) { toast('无可复制内容'); return; }
    try {
      await navigator.clipboard.writeText(f.text);
      toast('已复制原文到剪贴板');
    } catch (e) {
      var ta = document.createElement('textarea');
      ta.value = f.text;
      document.body.appendChild(ta);
      ta.select();
      try { document.execCommand('copy'); toast('已复制原文到剪贴板'); }
      catch (e2) { toast('复制失败'); }
      ta.remove();
    }
  }

  /* ---------- 主题 ---------- */
  function applyTheme(t) {
    document.documentElement.dataset.theme = t;
    $('#btnTheme').textContent = t === 'dark' ? '☀️' : '🌙';
    try { localStorage.setItem('mdreader-theme', t); } catch (e) { /* 忽略 */ }
  }

  /* ---------- 进度 ---------- */
  function showProgress() { $('#progress').hidden = false; $('#progressBar i').style.width = '0%'; $('#progressText').textContent = ''; }
  function updateProgress(done, total, name) {
    $('#progressBar i').style.width = (done / total * 100) + '%';
    $('#progressText').textContent = done + ' / ' + total + '：' + name;
  }
  function hideProgress() { $('#progress').hidden = true; }

  /* ---------- 清空 ---------- */
  async function clearAll() {
    if (!state.files.length) { toast('列表为空'); return; }
    if (!confirm('清空当前文件列表？（已保存的缓存也会被删除）')) return;
    state.files = [];
    state.allFiles.clear();
    state.current = null;
    state.visible = [];
    state.filter = '';
    state.contentSearch = false;
    $('#searchInput').value = '';
    $('#searchContent').checked = false;
    for (var u of state.imageUrls.values()) URL.revokeObjectURL(u);
    state.imageUrls.clear();
    $('#doc').innerHTML = '';
    $('#toolbar').hidden = true;
    $('#tocPanel').hidden = true;
    $('#btnToc').classList.remove('on');
    $('#welcome').hidden = false;
    document.title = 'Markdown 浏览器';
    renderTree();
    try { var db = await idbOpen(); await idbDel(db, 'last'); } catch (e) { /* 忽略 */ }
    $('#restoreBanner').hidden = true;
    toast('已清空');
  }

  /* ---------- 事件绑定 ---------- */
  $('#btnDir').addEventListener('click', pickFolder);
  $('#btnFiles').addEventListener('click', function () { $('#fileInput').click(); });
  $('#btnClear').addEventListener('click', clearAll);
  $('#btnTheme').addEventListener('click', function () {
    applyTheme(document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark');
  });
  $('#btnPrev').addEventListener('click', function () { stepNav(-1); });
  $('#btnNext').addEventListener('click', function () { stepNav(1); });
  $('#btnToc').addEventListener('click', function () {
    var p = $('#tocPanel');
    p.hidden = !p.hidden;
    $('#btnToc').classList.toggle('on', !p.hidden);
  });
  $('#btnCopy').addEventListener('click', copyRaw);
  $('#btnRaw').addEventListener('click', toggleRaw);
  $('#btnCancelRead').addEventListener('click', function () { state.reading = false; toast('已停止读取'); });

  var searchTimer = null;
  $('#searchInput').addEventListener('input', function () {
    state.filter = $('#searchInput').value;
    clearTimeout(searchTimer);
    searchTimer = setTimeout(renderTree, state.contentSearch ? 250 : 60);
  });
  $('#searchContent').addEventListener('change', function () {
    state.contentSearch = $('#searchContent').checked;
    renderTree();
  });

  $('#dirInput').addEventListener('change', function (e) {
    var fs = Array.prototype.slice.call(e.target.files || []);
    e.target.value = '';
    handleDropped(fs);
  });
  $('#fileInput').addEventListener('change', function (e) {
    var fs = Array.prototype.slice.call(e.target.files || []);
    e.target.value = '';
    handleDropped(fs);
  });

  document.addEventListener('dragover', function (e) { e.preventDefault(); });
  document.addEventListener('drop', function (e) {
    e.preventDefault();
    var fs = Array.prototype.slice.call((e.dataTransfer && e.dataTransfer.files) || []);
    if (fs.length) handleDropped(fs);
  });

  document.addEventListener('keydown', function (e) {
    var tag = e.target && e.target.tagName;
    if (tag === 'INPUT' || tag === 'TEXTAREA') return;
    if (e.key === 'ArrowLeft') { e.preventDefault(); stepNav(-1); }
    else if (e.key === 'ArrowRight') { e.preventDefault(); stepNav(1); }
    else if (e.key === 'Escape') { $('#tocPanel').hidden = true; $('#btnToc').classList.remove('on'); }
  });

  /* ---------- 启动 ---------- */
  var theme = 'light';
  try { theme = localStorage.getItem('mdreader-theme') || 'light'; } catch (e) { /* 忽略 */ }
  applyTheme(theme);
  updateStatus();
  refreshRestoreBanner();

  /* 自测钩子：地址栏加 #selftest 时自动渲染示例，便于无头测试 */
  if (location.hash === '#selftest') {
    (async function () {
      var sample = '# 标题一\n\n**加粗** 与 `行内代码`\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n- [x] 完成的任务\n- 普通列表项\n\n> 引用一段话\n\n```js\nconst x = 1;\n```\n\n[链接](https://example.com)\n';
      var doc = $('#doc');
      doc.innerHTML = sanitizeHtml(marked.parse(sample));
      ensureHeadingIds(doc);
      buildToc(doc);
      $('#btnToc').click();
      doc.innerHTML += '<p id="selftest-ok">SELFTEST-PASS</p>';
      console.log('[selftest] engines:', typeof marked, typeof DOMPurify);
      $('#headerStatus').textContent = (window.marked && window.DOMPurify) ? '引擎就绪' : '引擎缺失';
    })();
  }
})();
