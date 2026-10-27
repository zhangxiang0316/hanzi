#!/usr/bin/env node
/**
 * 数据构建脚本
 * 输入：content/source/*（统编版 1-2 年级识字表、组词、部首、Make Me a Hanzi 笔顺）
 * 输出：miniprogram/data/*.js（小程序可直接 require 的 CommonJS 模块）
 *
 * 笔顺数据采用自定义二进制编码 + base64，压缩后约为原始 JSON 的 1/4。
 * 编码格式（小端）：
 *   u8  version(1)
 *   u8  strokeCount
 *   strokeCount × { u16 byteLength, pathBytes }
 *   pathBytes: [op, coords...]，op: 0=M 1=L 2=Q 3=C 4=Z，坐标 u8 = round(原坐标 / SCALE)
 *   u8  medianCount
 *   medianCount × { u8 pointCount, [x,y] × pointCount }
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const SRC = path.join(ROOT, 'content/source');
const OUT = path.join(ROOT, 'miniprogram/data');
const OUT_STROKES = path.join(ROOT, 'miniprogram/packageStrokes/data');
const BOOK_IDS = ['1a', '1b', '2a', '2b'];
const EXPECT = { '1a': 300, '1b': 400, '2a': 450, '2b': 450 };
const VERSION = 2;
const SCALE = 6; // 坐标量化步长：6/1024 ≈ 0.6%，人眼不可见，体积约省 1/3
const OP = { M: 0, L: 1, Q: 2, C: 3, Z: 4 };
const ARGC = [2, 2, 4, 6, 0];

const readJSON = (p) => JSON.parse(fs.readFileSync(p, 'utf8'));

// ---------- 路径解析 / 编码 ----------
export function parsePath(d) {
  const tokens = d.match(/[A-Za-z]|-?(?:\d+\.?\d*|\.\d+)/g) || [];
  const cmds = [];
  let i = 0;
  while (i < tokens.length) {
    const t = tokens[i++].toUpperCase();
    if (!(t in OP)) throw new Error(`不支持的路径指令 ${t}: ${d.slice(0, 60)}`);
    const n = ARGC[OP[t]];
    const c = [OP[t]];
    for (let k = 0; k < n; k++) c.push(Number(tokens[i++]));
    if (c.some((v, idx) => idx > 0 && !Number.isFinite(v))) throw new Error(`路径坐标异常: ${d.slice(0, 60)}`);
    cmds.push(c);
  }
  if (!cmds.length || cmds[0][0] !== OP.M) throw new Error('路径没有以 M 开头');
  if (cmds[cmds.length - 1][0] !== OP.Z) throw new Error('路径没有以 Z 结尾');
  return cmds;
}

const quant = (v) => Math.max(0, Math.min(255, Math.round(v / SCALE)));

function encodeChar(strokes, medians) {
  const parts = [];
  const u8 = (v) => parts.push(v & 0xff);
  const u16 = (v) => { parts.push(v & 0xff, (v >> 8) & 0xff); };
  u8(VERSION);
  u8(strokes.length);
  for (const d of strokes) {
    const cmds = parsePath(d);
    const bytes = [];
    for (const c of cmds) {
      bytes.push(c[0]);
      for (let k = 1; k < c.length; k++) bytes.push(quant(c[k]));
    }
    u16(bytes.length);
    for (const b of bytes) parts.push(b);
  }
  u8(medians.length);
  for (const m of medians) {
    if (!m.length || m.length > 255) throw new Error('中线点数异常');
    u8(m.length);
    for (const p of m) { parts.push(quant(p[0]), quant(p[1])); }
  }
  return Buffer.from(parts).toString('base64');
}

// 教材组词表里缺失的叹词，补上常见搭配，保证每个字都有例词
const WORD_PATCH = {
  唉: [
    { w: '唉声叹气', p: 'āi shēng tàn qì' },
    { w: '唉呀', p: 'āi ya' },
  ],
  哦: [
    { w: '吟哦', p: 'yín é' },
    { w: '哦哟', p: 'ó yō' },
  ],
};

// ---------- 组词挑选 ----------
function pickWords(char, entry, wordDict) {
  if (WORD_PATCH[char]) return WORD_PATCH[char];
  const seen = new Set();
  const list = (entry.words || [])
    .filter((w) => typeof w === 'string' && w.includes(char) && w.length <= 4 && !seen.has(w) && seen.add(w))
    .sort((a, b) => a.length - b.length);
  return list.slice(0, 4).map((w) => {
    const p = wordDict[w];
    return p ? { w, p } : { w };
  });
}

// ---------- 主流程 ----------
function main() {
  const volumes = readJSON(path.join(SRC, 'volumes.json')).filter((b) => BOOK_IDS.includes(b.id));
  const rawChars = readJSON(path.join(SRC, 'chars.json'));
  const wordDict = readJSON(path.join(SRC, 'words.json'));
  const radicals = readJSON(path.join(SRC, 'radicals.json'));

  if (volumes.length !== 4) throw new Error(`册数异常: ${volumes.length}`);

  const catalog = {
    version: 1,
    edition: '统编版（部编版）小学语文 2019 版',
    generatedAt: new Date().toISOString(),
    books: [],
    lessons: {},
  };

  const charBook = new Map();   // 首次出现的册
  const allChars = new Map();   // char -> meta
  const bookCharSet = {};       // 册 -> Set
  const stats = {};

  for (const vol of volumes) {
    const bookChars = new Set();
    const units = [];
    let writeCount = 0;

    for (const unit of vol.units) {
      const lessonIds = [];
      for (const lid of unit.lessons) {
        const l = vol.lessons[lid];
        if (!l || !l.shizi.length) continue;
        if (l.shizi.some((c) => !rawChars[c])) throw new Error(`${lid} 存在字典外汉字`);
        lessonIds.push(lid);
        catalog.lessons[lid] = {
          id: lid,
          book: vol.id,
          unit: unit.no,
          no: l.num,
          title: l.title,
          kind: l.kind,
          page: l.page,
          chars: l.shizi.slice(),
          write: l.xiezi.slice(),
          words: (l.words || []).slice(0, 12),
        };
        for (const c of l.shizi) bookChars.add(c);
        for (const c of l.xiezi) writeCount++;
      }
      if (lessonIds.length) {
        units.push({ no: unit.no, title: unit.title, theme: unit.theme, lessons: lessonIds });
      }
    }

    if (bookChars.size !== EXPECT[vol.id]) {
      throw new Error(`${vol.id} 识字数 ${bookChars.size} != ${EXPECT[vol.id]}`);
    }
    bookCharSet[vol.id] = bookChars;

    catalog.books.push({
      id: vol.id,
      name: vol.name,
      short: vol.short,
      grade: vol.grade,
      term: vol.term,
      units,
      lessons: units.flatMap((u) => u.lessons),
      stat: { chars: bookChars.size, write: writeCount, lessons: units.reduce((n, u) => n + u.lessons.length, 0), units: units.length },
    });
    stats[vol.id] = { chars: bookChars.size, write: writeCount, units: units.length, lessons: catalog.books.at(-1).stat.lessons };
  }

  // 按首次出现顺序生成字库
  const strokesByBook = {};
  for (const book of catalog.books) {
    strokesByBook[book.id] = {};
    for (const lid of book.lessons) {
      for (const c of catalog.lessons[lid].chars) {
        if (allChars.has(c)) continue;
        const entry = rawChars[c];
        const file = path.join(SRC, 'strokes', `${c.codePointAt(0).toString(16)}.json`);
        if (!fs.existsSync(file)) throw new Error(`缺少笔顺数据: ${c}`);
        const stroke = readJSON(file);
        if (!stroke.strokes?.length || !stroke.medians?.length) throw new Error(`${c} 笔顺数据为空`);
        if (stroke.strokes.length !== stroke.medians.length) throw new Error(`${c} 笔画数不一致`);
        if (!radicals[c]) throw new Error(`${c} 缺少部首`);

        const meta = {
          py: entry.py,
          w: pickWords(c, entry, wordDict),
          r: radicals[c],
          s: stroke.strokes.length,
          b: entry.book,
          l: entry.first,
          x: entry.write || '',
        };
        const extraReadings = (entry.readings || []).filter((r) => r.py && r.lesson);
        if (extraReadings.length > 1) meta.rd = extraReadings.map((r) => ({ p: r.py, l: r.lesson }));
        allChars.set(c, meta);
        charBook.set(c, entry.book);
      }
    }
  }

  for (const [c, meta] of allChars) {
    const book = charBook.get(c);
    const file = path.join(SRC, 'strokes', `${c.codePointAt(0).toString(16)}.json`);
    const stroke = readJSON(file);
    strokesByBook[book][c] = encodeChar(stroke.strokes, stroke.medians);
  }

  if (allChars.size !== 1600) throw new Error(`字库总数 ${allChars.size} != 1600`);

  fs.mkdirSync(OUT, { recursive: true });
  const write = (name, obj, dir) => {
    const code = `/* 由 scripts/build-data.mjs 生成，请勿手工修改 */\nmodule.exports = ${JSON.stringify(obj)};\n`;
    fs.writeFileSync(path.join(dir || OUT, name), code);
    return Buffer.byteLength(code);
  };
  fs.mkdirSync(OUT_STROKES, { recursive: true });

  const sizes = {};
  sizes['catalog.js'] = write('catalog.js', catalog);
  sizes['meta.js'] = write('meta.js', Object.fromEntries(allChars));
  for (const book of BOOK_IDS) sizes[`strokes-${book}.js`] = write(`strokes-${book}.js`, strokesByBook[book], OUT_STROKES);

  const total = Object.values(sizes).reduce((a, b) => a + b, 0);
  fs.mkdirSync(path.join(ROOT, 'content/build'), { recursive: true });
  fs.writeFileSync(path.join(ROOT, 'content/build/stats.json'), JSON.stringify({ stats, sizes, total, chars: allChars.size }, null, 2));

  const kb = (n) => `${(n / 1024).toFixed(1)} KB`;
  console.log('✓ 数据构建完成');
  console.log('  册次:', BOOK_IDS.map((b) => `${b} ${stats[b].chars}字/${stats[b].lessons}课`).join('  '));
  console.log('  字库:', allChars.size, '字；', Object.entries(sizes).map(([k, v]) => `${k} ${kb(v)}`).join('  '));
  console.log('  合计:', kb(total));
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main();
