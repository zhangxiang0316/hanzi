#!/usr/bin/env node
/**
 * 形近字表构建脚本
 *
 * 输入：content/source/strokes/*.json（Make Me a Hanzi 笔顺）+ miniprogram/data/meta.js
 * 输出：miniprogram/data/similar.js（CommonJS 模块）
 *
 * ## 为什么要算而不是抄
 *
 * 形近字是低年级最大的混淆来源之一（未/末、天/夫、日/目、人/入）。
 * 现成的表要么收费、要么来源不明。而笔顺数据我们本来就有——字形就在里面。
 *
 * ## 为什么不用像素比对
 *
 * 先试过把每个字栅格化成位图比 IoU / 模糊后比相关系数，结论是**信号不够**：
 * 在 48x48 上，已知形近对（天/夫 0.74、人/入 0.74）和随机同笔画对的前 5%
 * （0.80）完全重叠。也就是说像素办法分不出「天和夫」与「随便两个字」。
 *
 * 改用**笔画几何匹配**：形近字的学习意义本来就是「笔画数相近、笔画位置几乎重合，
 * 只差一两笔」。把每个字的笔画中线重采样成 8 个点，贪心匹配到最近的笔画，
 * 取平均距离。实测这个指标把两类彻底分开了：
 *
 *   已知形近对：己/已 27、未/末 30、土/士 62、天/夫 69、干/千 91
 *   随机同笔画对：最小 92、5% 分位 149、中位 211
 *
 * ## 还需要第二条指标兜底
 *
 * 只用笔画距离会放进「笔画位置碰巧接近但字形完全不像」的字（实测「人」会
 * 匹配到「久/九/儿」）。所以再加一条像素相关系数（64x64 模糊后比余弦）当闸门：
 * 两条都过才算形近。实测已知形近对全部通过，随机同笔画对只有 1.5% 通过。
 *
 * ## 允许笔画数差 1
 *
 * 最典型的形近字恰恰是「差一笔」的那些：日/目、木/术、大/太、木/本、鸟/乌。
 * 所以笔画数相同或相差 1 都要比，差 1 时匹配少的那一边的笔画，剩下那一笔
 * 就是差异所在。
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createCanvas, Path2D } from '@napi-rs/canvas';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const SRC = path.join(ROOT, 'content/source/strokes');
const OUT = path.join(ROOT, 'miniprogram/data/similar.js');

/** 中线重采样点数。8 个点足以区分横/竖/撇/捺，再多只是更慢。 */
const N = 8;
/** 每字最多保留几个形近字 */
const KEEP = 5;
/**
 * 平均笔画距离门槛（单位是 1024 字体坐标）。
 *
 * 120 是在真实字表上定的：已知形近对最大是 干/千 的 91，随机同笔画对
 * 最小是 92、中位 211。取 120 留一点余量，又不至于把「同部首但不像」的
 * 字大量吸进来——它们的笔画位置差得远。
 */
const MAX_DIST = 140;
/**
 * 像素相关系数门槛（64x64、模糊两遍后比余弦相似度）。
 *
 * 0.60 是放宽定下来的：已知形近对里最低的是「人/入」和「天/夫」的 0.66，
 * 再高就会把它们排除；而随机同笔画对里只有 1.5% 能同时满足两个门槛。
 */
const MIN_CORR = 0.60;
/** 像素栅格边长 */
const PIX = 64;
/** 字体坐标 y 轴向上、基线 900，翻转一次（与 build-data.mjs 一致） */
const FLIP_BASE = 900;

const readJSON = (p) => JSON.parse(fs.readFileSync(p, 'utf8'));
const hexOf = (ch) => ch.codePointAt(0).toString(16).padStart(4, '0');

/** 折线等距重采样成 n 个点 */
function resample(pts, n) {
  if (!pts || !pts.length) return null;
  if (pts.length === 1) return new Array(n).fill(pts[0]);
  const lens = [];
  let total = 0;
  for (let i = 1; i < pts.length; i++) {
    const d = Math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]);
    lens.push(d);
    total += d;
  }
  if (total < 1e-6) return new Array(n).fill(pts[0]);
  const out = [];
  const step = total / (n - 1);
  let si = 0;
  let acc = 0;
  for (let k = 0; k < n; k++) {
    const target = k * step;
    while (si < lens.length - 1 && acc + lens[si] < target) {
      acc += lens[si];
      si++;
    }
    const t = lens[si] > 1e-9 ? (target - acc) / lens[si] : 0;
    const a = pts[si];
    const b = pts[si + 1] || pts[si];
    out.push([a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t]);
  }
  return out;
}

function loadStrokes(ch) {
  const f = path.join(SRC, `${hexOf(ch)}.json`);
  if (!fs.existsSync(f)) return null;
  const g = readJSON(f);
  if (!g.medians || !g.medians.length) return null;
  const strokes = g.medians
    .map((ms) => resample(ms.map(([x, y]) => [x, FLIP_BASE - y]), N))
    .filter(Boolean);
  if (!strokes.length) return null;
  // 重心用于快速预筛：两个重心离得远的字不可能形近
  let sx = 0;
  let sy = 0;
  let cnt = 0;
  for (const s of strokes) {
    for (const [x, y] of s) {
      sx += x;
      sy += y;
      cnt++;
    }
  }
  return { strokes, cx: sx / cnt, cy: sy / cnt, pix: rasterize(g) };
}

const pixCanvas = createCanvas(PIX, PIX);
const pixCtx = pixCanvas.getContext('2d');

function path2d(d, scale) {
  const tokens = d.match(/[A-Za-z]|-?(?:\d+\.?\d*|\.\d+)/g) || [];
  const p = new Path2D();
  let i = 0;
  let cx = 0;
  let cy = 0;
  const num = () => Number(tokens[i++]);
  while (i < tokens.length) {
    const op = tokens[i++];
    if (op === 'M') {
      cx = num();
      cy = num();
      p.moveTo(cx * scale, (FLIP_BASE - cy) * scale);
    } else if (op === 'L') {
      cx = num();
      cy = num();
      p.lineTo(cx * scale, (FLIP_BASE - cy) * scale);
    } else if (op === 'Q') {
      const x1 = num();
      const y1 = num();
      cx = num();
      cy = num();
      p.quadraticCurveTo(x1 * scale, (FLIP_BASE - y1) * scale, cx * scale, (FLIP_BASE - cy) * scale);
    } else if (op === 'C') {
      const x1 = num();
      const y1 = num();
      const x2 = num();
      const y2 = num();
      cx = num();
      cy = num();
      p.bezierCurveTo(
        x1 * scale, (FLIP_BASE - y1) * scale,
        x2 * scale, (FLIP_BASE - y2) * scale,
        cx * scale, (FLIP_BASE - cy) * scale
      );
    } else if (op === 'Z' || op === 'z') {
      p.closePath();
    }
  }
  return p;
}

/** 栅格化 + 两遍 3x3 模糊。模糊是为了容忍细笔画的亚像素位移。 */
function rasterize(g) {
  const scale = PIX / 1024;
  pixCtx.clearRect(0, 0, PIX, PIX);
  pixCtx.fillStyle = '#000';
  pixCtx.strokeStyle = '#000';
  pixCtx.lineWidth = 1;
  for (const d of g.strokes) {
    const p = path2d(d, scale);
    pixCtx.fill(p);
    pixCtx.stroke(p);
  }
  const img = pixCtx.getImageData(0, 0, PIX, PIX).data;
  let a = new Float32Array(PIX * PIX);
  for (let i = 0; i < a.length; i++) a[i] = img[i * 4 + 3] / 255;
  for (let pass = 0; pass < 2; pass++) {
    const b = new Float32Array(PIX * PIX);
    for (let y = 0; y < PIX; y++) {
      for (let x = 0; x < PIX; x++) {
        let sum = 0;
        let cnt = 0;
        for (let dy = -1; dy <= 1; dy++) {
          for (let dx = -1; dx <= 1; dx++) {
            const yy = y + dy;
            const xx = x + dx;
            if (yy < 0 || yy >= PIX || xx < 0 || xx >= PIX) continue;
            sum += a[yy * PIX + xx];
            cnt++;
          }
        }
        b[y * PIX + x] = sum / cnt;
      }
    }
    a = b;
  }
  return a;
}

/** 余弦相似度 */
function cosine(a, b) {
  let sa = 0;
  let sb = 0;
  let sab = 0;
  for (let i = 0; i < a.length; i++) {
    sa += a[i] * a[i];
    sb += b[i] * b[i];
    sab += a[i] * b[i];
  }
  return sab / Math.sqrt(sa * sb || 1);
}

function strokeDist(a, b) {
  let s = 0;
  for (let i = 0; i < N; i++) s += Math.hypot(a[i][0] - b[i][0], a[i][1] - b[i][1]);
  return s / N;
}

/** 贪心匹配：A 的每一笔找 B 里最近的未匹配笔画，返回平均距离 */
function glyphDist(A, B) {
  if (A.length > B.length) return glyphDist(B, A);
  const used = new Array(B.length).fill(false);
  let sum = 0;
  for (const sa of A) {
    let best = Infinity;
    let bi = -1;
    for (let j = 0; j < B.length; j++) {
      if (used[j]) continue;
      const d = strokeDist(sa, B[j]);
      if (d < best) {
        best = d;
        bi = j;
      }
    }
    used[bi] = true;
    sum += best;
  }
  return sum / A.length;
}

async function main() {
  const metaMod = await import(`file://${path.join(ROOT, 'miniprogram/data/meta.js')}`);
  const meta = metaMod.default || metaMod.meta || metaMod;
  const chars = Object.keys(meta);

  /** @type {Map<string, {strokes:number[][][], cx:number, cy:number}>} */
  const glyphs = new Map();
  let missing = 0;
  for (const ch of chars) {
    const g = loadStrokes(ch);
    if (!g) {
      missing++;
      continue;
    }
    glyphs.set(ch, g);
  }

  // 按笔画数分组；只和「同为 n」或「n±1」的组比较
  const byCount = new Map();
  for (const [ch, g] of glyphs) {
    const s = g.strokes.length;
    if (!byCount.has(s)) byCount.set(s, []);
    byCount.get(s).push(ch);
  }

  /** ch -> [{ch, dist}] */
  const found = new Map();
  const push = (a, b, d) => {
    if (!found.has(a)) found.set(a, []);
    if (!found.has(b)) found.set(b, []);
    found.get(a).push({ ch: b, dist: d });
    found.get(b).push({ ch: a, dist: d });
  };

  let compared = 0;
  let prefiltered = 0;

  const counts = [...byCount.keys()].sort((a, b) => a - b);
  for (const count of counts) {
    const list = byCount.get(count);
    const sameSet = new Set(list);
    const nextSet = new Set(byCount.get(count + 1) || []);

    for (let i = 0; i < list.length; i++) {
      const ca = list[i];
      const ga = glyphs.get(ca);
      for (let j = i + 1; j < list.length; j++) {
        // 同笔画数：i+1 起，天然不重复
        check(ca, list[j]);
      }
      for (const cb of nextSet) {
        check(ca, cb);
      }
    }

    function check(ca, cb) {
      const ga = glyphs.get(ca);
      const gb = glyphs.get(cb);
      if (!ga || !gb) return;
      // 快速预筛：重心离得远，笔画不可能重合
      if (Math.hypot(ga.cx - gb.cx, ga.cy - gb.cy) > MAX_DIST * 2) {
        prefiltered++;
        return;
      }
      compared++;
      const d = glyphDist(ga.strokes, gb.strokes);
      if (d > MAX_DIST) return;
      // 第二条闸门：笔画位置接近还不够，字形本身也得像
      if (cosine(ga.pix, gb.pix) < MIN_CORR) return;
      push(ca, cb, d);
    }

    void sameSet;
  }

  // 每个字按距离升序取前 KEEP 个，再按字码排序保证三端一致
  const out = {};
  for (const ch of chars) {
    const list = found.get(ch);
    if (!list || list.length < 1) continue;
    list.sort((x, y) => x.dist - y.dist || x.ch.codePointAt(0) - y.ch.codePointAt(0));
    const kept = list.slice(0, KEEP);
    kept.sort((x, y) => x.ch.codePointAt(0) - y.ch.codePointAt(0));
    // 只存字，不存距离：距离已经在门槛内，三端不需要再判一次，
    // 存浮点反而会引入「两端排序不同」的风险
    out[ch] = kept.map((x) => x.ch);
  }

  const groups = Object.keys(out).length;
  const pairs = Object.values(out).reduce((n, l) => n + l.length, 0) / 2;
  const code =
    '/**\n' +
    ' * 形近字表（自动生成，勿手改）\n' +
    ' *\n' +
    ' * 生成脚本：scripts/build-similar.mjs\n' +
    ' * 方法：把每笔的中线重采样成 ' + N + ' 个点，贪心匹配到最近的笔画，\n' +
    ' *      取平均距离；只在笔画数相同或相差 1 的字之间比，保留距离 <= ' + MAX_DIST + ' 的。\n' +
    ' *\n' +
    ' * 为什么用笔画几何而不是像素比对：像素办法分不开「天/夫」和随机字对，\n' +
    ' * 详见生成脚本顶部注释里的实测数字。\n' +
    ' *\n' +
    ' * 覆盖：' + groups + ' / ' + chars.length + ' 个字有形近字，共 ' + pairs + ' 对。\n' +
    ' */\n' +
    'module.exports = ' + JSON.stringify(out) + ';\n';

  fs.writeFileSync(OUT, code);

  console.log('✓ 形近字表已生成');
  console.log(`  字库 ${chars.length} 字，缺笔顺 ${missing} 字`);
  console.log(`  比较 ${compared} 对（预筛掉 ${prefiltered}），${groups} 个字有形近字，${pairs} 对`);
  console.log(`  输出 ${(code.length / 1024).toFixed(1)} KB`);
  const sample = Object.entries(out).slice(0, 8);
  for (const [ch, list] of sample) console.log(`  ${ch} → ${list.join(' ')}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
