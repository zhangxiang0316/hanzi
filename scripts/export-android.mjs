#!/usr/bin/env node
/**
 * 把小程序的数据产物导出给 Android 用。
 *
 * 小程序侧的数据是 CommonJS 模块（`module.exports = {...}`），Android 侧
 * 直接读 JSON 最省事：不用在 Kotlin 里模拟 require，也不用额外引依赖。
 *
 * 输出到 android/app/src/main/assets/data/：
 *   catalog.json   册次 / 单元 / 课 / 每课生字
 *   meta.json      字 → 拼音、部首、笔画数、组词、出处
 *   strokes.json   字 → 笔顺 base64（合并所有册，一次读入）
 *
 * 为什么合并 strokes：小程序的三个分包是为了绕开 2MB 上限，Android 没有这个
 * 限制，assets 里可以放 4MB+ 的单文件，合并后省掉「按册懒加载」的一套逻辑。
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const MP = path.join(ROOT, 'miniprogram');
const OUT = path.join(ROOT, 'android/app/src/main/assets/data');

// 复用小程序侧的产物，保证两边内容完全一致
const catalog = require(path.join(MP, 'data/catalog.js'));
const meta = require(path.join(MP, 'data/meta.js'));
const routes = require(path.join(MP, 'utils/routes.js'));

const BOOK_IDS = catalog.books.map((b) => b.id);

function collectStrokes() {
  const merged = {};
  let count = 0;
  for (const book of BOOK_IDS) {
    const pack = routes.packOf(book);
    const file = path.join(MP, pack, 'data', `strokes-${book}.js`);
    if (!fs.existsSync(file)) throw new Error(`缺少笔顺数据: ${file}`);
    const part = require(file);
    for (const [ch, b64] of Object.entries(part)) {
      if (merged[ch]) throw new Error(`字 ${ch} 在多个册里重复出现`);
      merged[ch] = b64;
      count++;
    }
  }
  return { merged, count };
}

function main() {
  const { merged, count } = collectStrokes();

  // 一致性校验：字库里每个字都必须有笔顺，否则 Android 端会点开空白页
  const missing = Object.keys(meta).filter((ch) => !merged[ch]);
  if (missing.length) {
    throw new Error(`有 ${missing.length} 个字缺少笔顺数据: ${missing.slice(0, 20).join('')}`);
  }
  const orphan = Object.keys(merged).filter((ch) => !meta[ch]);
  if (orphan.length) {
    throw new Error(`有 ${orphan.length} 个笔顺数据没有对应的字库条目: ${orphan.slice(0, 20).join('')}`);
  }

  fs.mkdirSync(OUT, { recursive: true });
  const writeJson = (name, obj) => {
    const text = JSON.stringify(obj);
    fs.writeFileSync(path.join(OUT, name), text);
    return Buffer.byteLength(text);
  };

  const sizes = {
    'catalog.json': writeJson('catalog.json', catalog),
    'meta.json': writeJson('meta.json', meta),
    'strokes.json': writeJson('strokes.json', merged),
  };

  const kb = (n) => `${(n / 1024).toFixed(1)} KB`;
  console.log('✓ Android 数据导出完成');
  console.log(`  册次 ${catalog.books.length} 个，课 ${Object.keys(catalog.lessons).length} 课`);
  console.log(`  字库 ${Object.keys(meta).length} 字，笔顺 ${count} 份`);
  console.log('  体积:', Object.entries(sizes).map(([k, v]) => `${k} ${kb(v)}`).join('  '));
  console.log('  合计:', kb(Object.values(sizes).reduce((a, b) => a + b, 0)));
  console.log('  输出:', path.relative(ROOT, OUT));
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main();
