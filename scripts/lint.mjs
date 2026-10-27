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
  const reqRe = /require\(\s*['"]([^'"]+)['"]\s*\)/g;
  let r;
  while ((r = reqRe.exec(src))) {
    const spec = r[1];
    if (!spec.startsWith('.')) continue;
    const base = path.resolve(path.dirname(f), spec);
    if (!exists(base) && !exists(base + '.js') && !exists(path.join(base, 'index.js'))) {
      err(`${rel}: require 路径不存在 ${spec}`);
    }
  }
}

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
  const src = read(f).replace(/\/\*[\s\S]*?\*\//g, '');
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
