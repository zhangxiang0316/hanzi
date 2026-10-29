#!/usr/bin/env node
/**
 * 静态检查：页面完整性、WXML 结构、事件绑定、样式兼容性、数据体积。
 * 不依赖微信开发者工具，可在 CI 中运行。
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const MP = path.join(ROOT, 'miniprogram');
const errors = [];
const warnings = [];

const err = (m) => errors.push(m);
const warn = (m) => warnings.push(m);
const read = (p) => fs.readFileSync(p, 'utf8');
const exists = (p) => fs.existsSync(p);

const app = JSON.parse(read(path.join(MP, 'app.json')));
const pages = app.pages || [];
const subRoots = [];
for (const sp of app.subpackages || app.subPackages || []) {
  subRoots.push(sp.root);
  for (const p of sp.pages || []) {
    const full = `${sp.root.replace(/\/$/, '')}/${p}`;
    pages.push(full);
    if (!fs.existsSync(path.join(MP, full + '.js'))) err(`分包页面不存在: ${full}`);
  }
  // 分包重复页面检查
  const dup = pages.filter((p) => p === `${sp.root.replace(/\/$/, '')}/${sp.pages[0]}`);
  if (dup.length > 1) err(`分包 ${sp.root} 页面重复`);
}

// ---------- 1. 页面文件完整性 ----------
for (const page of pages) {
  for (const ext of ['js', 'json', 'wxml', 'wxss']) {
    const f = path.join(MP, `${page}.${ext}`);
    if (!exists(f)) err(`缺少页面文件 ${page}.${ext}`);
  }
  const jf = path.join(MP, `${page}.json`);
  if (exists(jf)) {
    try {
      JSON.parse(read(jf));
    } catch (e) {
      err(`${page}.json 不是合法 JSON: ${e.message}`);
    }
  }
}

// ---------- 2. tabBar ----------
const tabBar = app.tabBar;
if (tabBar) {
  if ((tabBar.list || []).length < 2 || tabBar.list.length > 5) err('tabBar 需要 2-5 项');
  for (const item of tabBar.list) {
    if (!pages.includes(item.pagePath)) err(`tabBar 页面未注册: ${item.pagePath}`);
    for (const key of ['iconPath', 'selectedIconPath']) {
      if (!item[key]) continue;
      const icon = path.join(MP, item[key]);
      if (!exists(icon)) {
        err(`tabBar 图标不存在: ${item[key]}`);
        continue;
      }
      const size = fs.statSync(icon).size;
      if (size > 40 * 1024) err(`tabBar 图标超过 40KB: ${item[key]} (${size}B)`);
      if (!/\.png$/i.test(item[key])) err(`tabBar 图标必须是 png: ${item[key]}`);
    }
  }
}

// ---------- 3. WXML 结构 ----------
const VOID_TAGS = new Set(['image', 'input', 'icon', 'progress', 'switch', 'slider', 'canvas', 'video', 'map', 'navigator']);
const KNOWN_TAGS = new Set([
  'view', 'text', 'image', 'button', 'input', 'textarea', 'scroll-view', 'swiper', 'swiper-item',
  'block', 'canvas', 'video', 'map', 'navigator', 'switch', 'slider', 'progress', 'icon', 'rich-text',
  'checkbox', 'checkbox-group', 'radio', 'radio-group', 'picker', 'picker-view', 'picker-view-column',
  'label', 'form', 'editor', 'cover-view', 'cover-image', 'movable-area', 'movable-view', 'web-view',
  'audio', 'camera', 'live-player', 'open-data', 'ad', 'official-account', 'page-meta', 'navigation-bar',
  'functional-page-navigator', 'slot', 'template', 'import', 'include', 'wxs', 'grid-view', 'list-view',
]);

function checkWxml(file, jsSource) {
  const src = read(file).replace(/<!--[\s\S]*?-->/g, '');
  const tagRe = /<\/?([a-zA-Z][\w-]*)([^>]*)>/g;
  const stack = [];
  let m;
  while ((m = tagRe.exec(src))) {
    const raw = m[0];
    const tag = m[1];
    const closing = raw.startsWith('</');
    const selfClose = raw.endsWith('/>');
    if (!KNOWN_TAGS.has(tag)) warn(`${path.relative(ROOT, file)}: 未知标签 <${tag}>`);
    if (closing) {
      const top = stack.pop();
      if (!top) err(`${path.relative(ROOT, file)}: 多余的闭合标签 </${tag}>`);
      else if (top !== tag) err(`${path.relative(ROOT, file)}: 标签不匹配，<${top}> 被 </${tag}> 关闭`);
    } else if (!selfClose && !VOID_TAGS.has(tag)) {
      stack.push(tag);
    }
    // 属性引号配对
    const attrs = (m[2] || '').trim();
    if (attrs) {
      const quotes = (attrs.match(/"/g) || []).length;
      if (quotes % 2 !== 0) err(`${path.relative(ROOT, file)}: <${tag}> 属性引号不配对`);
    }
  }
  if (stack.length) err(`${path.relative(ROOT, file)}: 有未闭合标签 ${stack.join(' > ')}`);

  // 插值配对
  const opens = (src.match(/\{\{/g) || []).length;
  const closes = (src.match(/\}\}/g) || []).length;
  if (opens !== closes) err(`${path.relative(ROOT, file)}: {{ }} 数量不匹配 (${opens}/${closes})`);

  // 事件处理函数必须存在
  const handlers = new Set();
  const evtRe = /\b(?:bind|catch|capture-bind|capture-catch):?([a-z]+)="([^"{}]+)"/gi;
  let e;
  while ((e = evtRe.exec(src))) handlers.add(e[2]);
  for (const h of handlers) {
    if (!jsSource) continue;
    const re = new RegExp(`(^|[\\s,{])${h}\\s*[:(]`, 'm');
    if (!re.test(jsSource)) err(`${path.relative(ROOT, file)}: 事件 ${h} 在页面 JS 中不存在`);
  }

  // 顶层数据字段（软检查）
  const js = jsSource || '';
  const mustacheRe = /\{\{([^}]+)\}\}/g;
  const fields = new Set();
  let mm;
  while ((mm = mustacheRe.exec(src))) {
    const expr = mm[1];
    const idRe = /(^|[^.\w'"])([a-zA-Z_$][\w$]*)/g;
    let im;
    while ((im = idRe.exec(expr))) {
      const name = im[2];
      if (['true', 'false', 'null', 'undefined', 'item', 'index', 'unit', 'opt'].includes(name)) continue;
      fields.add(name);
    }
  }
  for (const f of fields) {
    const re = new RegExp(`(^|[\\s,{])${f}\\s*[:=]`, 'm');
    if (!re.test(js)) warn(`${path.relative(ROOT, file)}: 模板用到的 ${f} 未在 JS 中出现`);
  }
}

// ---------- 4. WXSS ----------
const FORBIDDEN = [
  [/\binset\s*:/, 'inset 简写，部分 WebView 不支持'],
  [/\bgap\s*:/, 'gap，建议用 margin 兼容旧机型'],
  [/aspect-ratio\s*:/, 'aspect-ratio，建议用 padding-top 撑高'],
  [/\bposition\s*:\s*sticky/, 'position: sticky，小程序兼容性差'],
];
const wxssFiles = [];
function walk(dir) {
  for (const name of fs.readdirSync(dir)) {
    const p = path.join(dir, name);
    const st = fs.statSync(p);
    if (st.isDirectory()) walk(p);
    else if (name.endsWith('.wxss')) wxssFiles.push(p);
  }
}
walk(MP);

for (const f of wxssFiles) {
  const src = read(f).replace(/\/\*[\s\S]*?\*\//g, '');
  const rel = path.relative(ROOT, f);
  let depth = 0;
  for (const ch of src) {
    if (ch === '{') depth++;
    else if (ch === '}') depth--;
    if (depth < 0) break;
  }
  if (depth !== 0) err(`${rel}: 大括号不配对`);
  for (const [re, msg] of FORBIDDEN) {
    if (re.test(src)) warn(`${rel}: 使用了${msg}`);
  }
  const importRe = /@import\s+["']([^"']+)["']/g;
  let im;
  while ((im = importRe.exec(src))) {
    const target = path.resolve(path.dirname(f), im[1]);
    if (!exists(target)) err(`${rel}: @import 找不到 ${im[1]}`);
  }
}


/** 去掉 JS 注释（保留字符串内容），避免把注释里的 require 当成真引用 */
function stripComments(src) {
  let out = '';
  let i = 0;
  let quote = null;
  while (i < src.length) {
    const c = src[i];
    const n = src[i + 1];
    if (quote) {
      out += c;
      if (c === '\\') {
        out += n === undefined ? '' : n;
        i += 2;
        continue;
      }
      if (c === quote) quote = null;
      i++;
      continue;
    }
    if (c === '"' || c === "'" || c === '`') {
      quote = c;
      out += c;
      i++;
      continue;
    }
    if (c === '/' && n === '/') {
      while (i < src.length && src[i] !== '\n') i++;
      continue;
    }
    if (c === '/' && n === '*') {
      i += 2;
      while (i < src.length && !(src[i] === '*' && src[i + 1] === '/')) i++;
      i += 2;
      continue;
    }
    out += c;
    i++;
  }
  return out;
}

// ---------- 5. JS 语法与 require 路径 ----------
const jsFiles = [];
(function walkJs(dir) {
  for (const name of fs.readdirSync(dir)) {
    const p = path.join(dir, name);
    const st = fs.statSync(p);
    if (st.isDirectory()) walkJs(p);
    else if (name.endsWith('.js')) jsFiles.push(p);
  }
})(MP);

for (const f of jsFiles) {
  const rel = path.relative(ROOT, f);
  try {
    execFileSync(process.execPath, ['--check', f], { stdio: 'pipe' });
  } catch (e) {
    err(`${rel}: 语法错误 ${String(e.stderr || e.message).split('\n').slice(0, 3).join(' ')}`);
  }
  const src = read(f);
  // 跳转 URL 必须指向已注册页面
  const navRe = /url:\s*['"](\/[^'"?]+)/g;
  let nav;
  while ((nav = navRe.exec(src))) {
    const target = nav[1].replace(/^\//, '');
    if (!pages.includes(target)) err(`${rel}: 跳转到未注册页面 ${nav[1]}`);
  }
  const code = stripComments(src);
  const reqRe = /require\(\s*['"]([^'"]+)['"]\s*\)/g;
  let r;
  while ((r = reqRe.exec(code))) {
    const spec = r[1];
    if (!spec.startsWith('.')) continue;
    const base = path.resolve(path.dirname(f), spec);
    if (!exists(base) && !exists(base + '.js') && !exists(path.join(base, 'index.js'))) {
      err(`${rel}: require 路径不存在 ${spec}`);
    }
  }
}

// ---------- 5.4 全局工具类不能被当成页面修饰符 ----------
// 踩过的坑：practice.wxml 用 `book-chip empty` 表示"这册还没学过"，
// 而 app.wxss 里有个全局空状态工具类 `.empty { text-align: center; padding: ... }`。
// 于是芯片文字能居中原先是"借"了 .empty 的 text-align；一旦某册有了学习记录
// （移除 empty 类），文字立刻掉回左对齐。
(function checkGlobalClassCollision() {
  const appWxss = path.join(MP, 'app.wxss');
  if (!fs.existsSync(appWxss)) return;
  const src = stripComments(read(appWxss));

  // 全局工具类 = app.wxss 里单独出现、且会显著影响排版的简单类选择器
  const utilities = new Set();
  // 注意：不要写成 /(^|\})\s*([^{}@]+)\{/ —— 那样上一条规则会吃掉作为前缀的 `}`，
  // 导致紧接着的下一条规则永远匹配不到（`.empty` 就是这样被漏掉的）。
  const ruleRe = /([^{}@]+)\{([^{}]*)\}/g;
  let m;
  while ((m = ruleRe.exec(src))) {
    const body = m[2];
    if (!/(text-align|padding|margin|display|opacity|flex)/.test(body)) continue;
    for (const sel of m[1].split(',')) {
      const t = sel.trim();
      // 只收「单个类名」的选择器，复合选择器（.a.b）不算工具类
      const one = t.match(/^\.([A-Za-z0-9_-]+)$/);
      if (one) utilities.add(one[1]);
    }
  }
  if (!utilities.size) return;

  // 页面 wxss 里出现 `.页面类.工具类` 这种复合选择器 = 把工具类当修饰符用
  const pageWxss = [];
  (function walk(dir) {
    for (const name of fs.readdirSync(dir)) {
      const p = path.join(dir, name);
      if (fs.statSync(p).isDirectory()) walk(p);
      else if (name.endsWith('.wxss') && p !== appWxss) pageWxss.push(p);
    }
  })(MP);

  for (const file of pageWxss) {
    const css = stripComments(read(file));
    const selRe = /([^{}]+)\{/g;
    let r;
    while ((r = selRe.exec(css))) {
      const raw = r[1].trim();
      if (!raw || raw.startsWith('@') || raw.includes('%')) continue;
      for (const part of raw.split(',')) {
        const sel = part.trim();
        if (!sel) continue;
        for (const compound of sel.split(/[\s>+~]+/)) {
          const classes = compound.match(/\.[A-Za-z0-9_-]+/g);
          if (!classes || classes.length < 2) continue;
          const names = classes.map((c) => c.slice(1));
          for (const n of names) {
            if (!utilities.has(n)) continue;
            const other = names.find((x) => x !== n);
            if (!other) continue;
            err(
              path.relative(ROOT, file) + ': 选择器 ".' + other + '.' + n +
                '" 把全局工具类 ".' + n + '" 当修饰符用了，' +
                '会与 app.wxss 的通用样式互相干扰（请换一个专用类名）'
            );
          }
        }
      }
    }
  }
})();

// ---------- 5.4b 笔画条不许横向滚动 ----------
// 认识这个字页面的「按笔顺写」原本是 <scroll-view scroll-x>：23 画的字要横滑才能
// 看到后面的笔画，孩子不会主动发现"这里能滑"，滑的时候还容易误触数字。
// 现在改成 flex-wrap 换行。预览里 scroll-view 会被渲染成 div（横向滚动失效），
// 所以运行时断言看不出来，必须在源码层面卡住。
(function checkStrokeStripNotScrollable() {
  for (const root of subRoots) {
    const file = path.join(MP, root, 'pages/detail/detail.wxml');
    if (!fs.existsSync(file)) continue;
    const src = read(file);
    if (src.indexOf('按笔顺写') < 0) continue;
    if (/scroll-view[^>]*scroll-x/.test(src)) {
      err(
        path.relative(ROOT, file) +
          ': 「按笔顺写」的笔画条用了 scroll-view 横向滚动，' +
          '应当用 flex-wrap 换行（最多 3 行就能放下 23 画）'
      );
    }
  }
})();

// ---------- 5.5 各分包的同名页面必须一致 ----------
// detail/write 两个页面在 packageStrokes 和 packageStrokes3 里各有一份
// wxml/wxss（小程序要求页面文件跟着分包走）。只有 JS 薄壳不同，
// 模板和样式必须逐字节一致，否则改了一份会漏掉另一份。
(function checkDuplicatedPages() {
  const byPage = {};
  for (const root of subRoots) {
    const pagesDir = path.join(MP, root, 'pages');
    if (!fs.existsSync(pagesDir)) continue;
    for (const name of fs.readdirSync(pagesDir)) {
      for (const f of fs.readdirSync(path.join(pagesDir, name))) {
        if (!f.endsWith('.wxml') && !f.endsWith('.wxss')) continue;
        const key = name + '/' + f;
        (byPage[key] = byPage[key] || []).push(path.join(pagesDir, name, f));
      }
    }
  }
  for (const [key, files] of Object.entries(byPage)) {
    if (files.length < 2) continue;
    const first = read(files[0]);
    for (const f of files.slice(1)) {
      if (read(f) !== first) {
        err(`${path.relative(ROOT, f)} 与 ${path.relative(ROOT, files[0])} 内容不一致（同一页面的多份副本必须同步）`);
      }
    }
  }
})();

// ---------- 5.6 preloadRule 的预载总量不能超 2MB ----------
// 微信规定「单个页面通过 preloadRule 预载的分包总量 ≤ 2MB」。
// 加四年级时三个分包合计 2483KB，真机上传直接报 80058，本地 lint 却看不出来。
// 现在改成 routes.preload() 按需预载单册所属分包，这条检查用来防止回退。
(function checkPreloadRuleSize() {
  const rule = app.preloadRule;
  if (!rule) return;
  const nameToRoot = {};
  for (const sp of app.subpackages || []) nameToRoot[sp.name || sp.root] = sp.root;
  const sizes = {};
  const sizeOf = (root) => {
    if (sizes[root] == null) {
      const dir = path.join(MP, root);
      sizes[root] = fs.existsSync(dir) ? dirSize(dir) : 0;
    }
    return sizes[root];
  };
  for (const [page, cfg] of Object.entries(rule)) {
    const packs = cfg.packages || [];
    let sum = 0;
    const unknown = [];
    for (const name of packs) {
      const root = nameToRoot[name] || (name.startsWith('package') ? name : null);
      if (!root) { unknown.push(name); continue; }
      sum += sizeOf(root);
    }
    if (unknown.length) {
      err(`app.json preloadRule[${page}] 引用了不存在的分包: ${unknown.join(', ')}`);
    }
    if (sum > 2 * 1024 * 1024) {
      err(
        `app.json preloadRule[${page}] 预载 ${packs.length} 个分包共 ${(sum / 1024).toFixed(0)}KB，` +
          `超过微信「单个页面预载 ≤ 2MB」限制（真机报 80058）。` +
          `改用 routes.preload(book) 只预载当前册所属的包。`
      );
    }
  }
})();

// ---------- 6. 体积 ----------
function dirSize(dir) {
  let total = 0;
  for (const name of fs.readdirSync(dir)) {
    const p = path.join(dir, name);
    const st = fs.statSync(p);
    total += st.isDirectory() ? dirSize(p) : st.size;
  }
  return total;
}
let mainSize = 0;
let pkgSizes = {};
(function measure(dir) {
  for (const name of fs.readdirSync(dir)) {
    const p = path.join(dir, name);
    if (p === path.join(MP, 'packageStrokes') || subRoots.some((r) => p === path.join(MP, r))) continue;
    const st = fs.statSync(p);
    if (st.isDirectory()) measure(p);
    else mainSize += st.size;
  }
})(MP);
for (const root of subRoots) {
  const dir = path.join(MP, root);
  if (!exists(dir)) { err(`分包目录不存在: ${root}`); continue; }
  const size = dirSize(dir);
  pkgSizes[root] = size;
  if (size > 2 * 1024 * 1024) err(`分包 ${root} 体积 ${(size / 1048576).toFixed(2)}MB 超过 2MB`);
}
const total = dirSize(MP);
if (mainSize > 2 * 1024 * 1024) err(`主包体积 ${(mainSize / 1048576).toFixed(2)}MB 超过 2MB 限制`);
else if (mainSize > 1.8 * 1024 * 1024) warn(`主包体积 ${(mainSize / 1048576).toFixed(2)}MB 接近 2MB 限制`);
if (total > 20 * 1024 * 1024) err(`整体体积 ${(total / 1048576).toFixed(2)}MB 超过 20MB 限制`);
// 分包引用检查：主包不能 require 分包文件
const subPrefixes = subRoots.map((r) => path.join(MP, r));
for (const f of jsFiles) {
  if (subPrefixes.some((pre) => f.startsWith(pre))) continue;
  const src = stripComments(read(f));
  const reqRe = /require\(\s*['"]([^'"]+)['"]\s*\)/g;
  let r;
  while ((r = reqRe.exec(src))) {
    if (!r[1].startsWith('.')) continue;
    const resolved = path.resolve(path.dirname(f), r[1]);
    if (subPrefixes.some((pre) => resolved.startsWith(pre))) {
      err(`${path.relative(ROOT, f)}: 主包不能引用分包模块 ${r[1]}`);
    }
  }
}

// ---------- 输出 ----------
const relTotal = `${(mainSize / 1024).toFixed(0)} KB`;
const relAll = `${(total / 1024).toFixed(0)} KB`;
if (warnings.length) {
  console.log(`⚠ ${warnings.length} 条提示`);
  warnings.slice(0, 40).forEach((w) => console.log('  · ' + w));
}
if (errors.length) {
  console.error(`✗ ${errors.length} 个问题`);
  errors.forEach((e) => console.error('  · ' + e));
  process.exit(1);
}
const subInfo = Object.entries(pkgSizes)
  .map(([k, v]) => `${k} ${(v / 1024).toFixed(0)}KB`)
  .join('，');
console.log(
  `✓ 静态检查通过：${pages.length} 个页面，${jsFiles.length} 个 JS，${wxssFiles.length} 个 WXSS，主包 ${relTotal}（总体积 ${relAll}）` +
    (subInfo ? `，分包 ${subInfo}` : '')
);
