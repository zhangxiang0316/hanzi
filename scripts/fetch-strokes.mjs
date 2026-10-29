#!/usr/bin/env node
/**
 * 补齐笔顺数据
 *
 * Make Me a Hanzi 的 graphics.txt 收录约 9000 个汉字的笔画轮廓（strokes）
 * 与笔画中线（medians）。本项目按字懒加载，只有 content/source/strokes/
 * 下存在对应文件时才会被 build-data.mjs 收录。
 *
 * 本脚本：
 *   1. 下载（并缓存）graphics.txt
 *   2. 找出 chars.json 里有、但 strokes/ 下没有的字
 *   3. 把这些字的 strokes/medians 写成单个 JSON，供构建脚本使用
 *
 * 同时补齐 radicals.json：原数据只覆盖一到二年级，三至六年级的部首
 * 从同一个项目的 dictionary.txt（radical 字段）取得。
 *
 * 用法：
 *   node scripts/fetch-strokes.mjs            # 补齐所有缺失的字
 *   node scripts/fetch-strokes.mjs 3a 3b      # 只补指定册次
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const SRC = path.join(ROOT, 'content/source');
const CACHE = path.join(ROOT, 'content/cache');
const STROKES = path.join(SRC, 'strokes');
const GRAPHICS_URL = 'https://raw.githubusercontent.com/skishore/makemeahanzi/master/graphics.txt';
const GRAPHICS = path.join(CACHE, 'graphics.txt');
const DICT_URL = 'https://raw.githubusercontent.com/skishore/makemeahanzi/master/dictionary.txt';
const DICT = path.join(CACHE, 'dictionary.txt');
const RADICALS = path.join(SRC, 'radicals.json');

const hexOf = (ch) => ch.codePointAt(0).toString(16);

async function download() {
  if (fs.existsSync(GRAPHICS) && fs.statSync(GRAPHICS).size > 1e7) {
    console.log('  使用缓存 content/cache/graphics.txt');
    return;
  }
  fs.mkdirSync(CACHE, { recursive: true });
  console.log('  下载 graphics.txt（约 40MB，只需一次）…');
  const res = await fetch(GRAPHICS_URL);
  if (!res.ok) throw new Error('下载失败 HTTP ' + res.status);
  const text = await res.text();
  fs.writeFileSync(GRAPHICS, text);
  console.log(`  已保存 ${(text.length / 1048576).toFixed(1)} MB`);
}

/** graphics.txt 是每行一个 JSON 对象（NDJSON） */
function loadGraphics() {
  const map = new Map();
  const lines = fs.readFileSync(GRAPHICS, 'utf8').split('\n');
  for (const line of lines) {
    if (!line.trim()) continue;
    let rec;
    try {
      rec = JSON.parse(line);
    } catch (e) {
      continue; // 个别行可能被截断，跳过
    }
    if (!rec.character) continue;
    map.set(rec.character, rec);
  }
  return map;
}

async function downloadDict() {
  if (fs.existsSync(DICT) && fs.statSync(DICT).size > 1e6) return;
  fs.mkdirSync(CACHE, { recursive: true });
  console.log('  下载 dictionary.txt（约 2.5MB）…');
  const res = await fetch(DICT_URL);
  if (!res.ok) throw new Error('下载 dictionary.txt 失败 HTTP ' + res.status);
  fs.writeFileSync(DICT, await res.text());
}

/** 用 dictionary.txt 的 radical 字段补全 radicals.json 缺失的部首 */
function fillRadicals() {
  if (!fs.existsSync(DICT)) return { added: 0, missing: 0 };
  const map = new Map();
  const lines = fs.readFileSync(DICT, 'utf8').split('\n');
  for (const line of lines) {
    if (!line.trim()) continue;
    let rec;
    try {
      rec = JSON.parse(line);
    } catch (e) {
      continue;
    }
    if (rec.character && rec.radical) map.set(rec.character, rec.radical);
  }
  const radicals = JSON.parse(fs.readFileSync(RADICALS, 'utf8'));
  const chars = JSON.parse(fs.readFileSync(path.join(SRC, 'chars.json'), 'utf8'));
  let added = 0;
  const missing = [];
  for (const ch of Object.keys(chars)) {
    if (radicals[ch]) continue;
    if (map.has(ch)) {
      radicals[ch] = map.get(ch);
      added++;
    } else {
      missing.push(ch);
    }
  }
  if (added) {
    fs.writeFileSync(RADICALS, JSON.stringify(radicals, null, 0));
  }
  return { added, missing };
}

function main() {
  const only = process.argv.slice(2).filter((a) => /^\d[ab]$/.test(a));
  const chars = JSON.parse(fs.readFileSync(path.join(SRC, 'chars.json'), 'utf8'));
  const wanted = Object.keys(chars).filter((ch) => {
    const book = chars[ch].b || chars[ch].book;
    if (only.length && only.indexOf(book) < 0) return false;
    return !fs.existsSync(path.join(STROKES, hexOf(ch) + '.json'));
  });

  console.log(`  待补笔顺 ${wanted.length} 个字`);

  return Promise.all([wanted.length ? download() : Promise.resolve(), downloadDict()])
    .then(() => {
      const rad = fillRadicals();
      if (rad.added) console.log(`✓ 补充部首 ${rad.added} 个字`);
      if (rad.missing.length) {
        console.warn(`⚠ ${rad.missing.length} 个字没有部首数据：${rad.missing.slice(0, 20).join(' ')}`);
      }
      if (!wanted.length) {
        console.log('✓ 没有缺失的笔顺数据');
        return;
      }
      const g = loadGraphics();
      console.log(`  graphics.txt 收录 ${g.size} 字`);
      let ok = 0;
      const missing = [];
      for (const ch of wanted) {
        const rec = g.get(ch);
        if (!rec || !rec.strokes || !rec.strokes.length || !rec.medians || !rec.medians.length) {
          missing.push(ch);
          continue;
        }
        if (rec.strokes.length !== rec.medians.length) {
          missing.push(ch + '(笔画/中线数不一致)');
          continue;
        }
        fs.writeFileSync(
          path.join(STROKES, hexOf(ch) + '.json'),
          JSON.stringify({ strokes: rec.strokes, medians: rec.medians })
        );
        ok++;
      }
      console.log(`✓ 写入 ${ok} 个字的笔顺`);
      if (missing.length) {
        console.warn(`⚠ ${missing.length} 个字的笔顺在源数据里没有：${missing.slice(0, 20).join(' ')}`);
        fs.writeFileSync(
          path.join(CACHE, 'missing-strokes.json'),
          JSON.stringify({ chars: missing }, null, 2)
        );
        console.warn('  已记录到 content/cache/missing-strokes.json');
      }
    })
    .catch((e) => {
      console.error('✗ ' + e.message);
      process.exitCode = 1;
    });
}

main();
