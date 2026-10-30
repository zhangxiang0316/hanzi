#!/usr/bin/env node
/**
 * 生成 iOS App 图标。
 *
 * 用笔画数据画字，不是贴字体——和 App 内的渲染方式一致，
 * 所以图标和界面里的「字」长得是同一个字。
 *
 * 输出 1024×1024 无透明 PNG（App Store 要求图标不能有 alpha 通道）。
 *
 *   node scripts/gen-ios-icon.mjs
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createCanvas } from '@napi-rs/canvas';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const RES = path.join(ROOT, 'ios/HanziPad/Resources');
const OUT_DIR = path.join(ROOT, 'ios/HanziPad/Assets.xcassets/AppIcon.appiconset');

const SCALE = 6;
const OPM = 0, OPL = 1, OPQ = 2, OPC = 3, OPZ = 4;

/** 解一笔的路径指令 */
function decodeStrokes(base64) {
  const buf = Buffer.from(base64, 'base64');
  let p = 0;
  const ver = buf[p++];
  if (ver !== 3) throw new Error(`不支持的版本 ${ver}`);
  const n = buf[p++];
  const strokes = [];
  for (let i = 0; i < n; i++) {
    const len = buf[p] | (buf[p + 1] << 8);
    p += 2;
    const end = p + len;
    const cmds = [];
    while (p < end) {
      const op = buf[p++];
      const c = (k) => buf[p + k] * SCALE;
      if (op === OPM || op === OPL) { cmds.push({ op, x: c(0), y: c(1) }); p += 2; }
      else if (op === OPQ) { cmds.push({ op, x: c(0), y: c(1), x1: c(2), y1: c(3) }); p += 4; }
      else if (op === OPC) { cmds.push({ op, c1x: c(0), c1y: c(1), c2x: c(2), c2y: c(3), x: c(4), y: c(5) }); p += 6; }
      else if (op === OPZ) { cmds.push({ op }); }
      else throw new Error(`未知 op ${op}`);
    }
    p = end;
    strokes.push(cmds);
  }
  return strokes;
}

/** 把 0..1024 的字形坐标映射到画布 */
function mapper(box, ox, oy) {
  const PAD = 0.035;
  const pad = box * PAD;
  const s = (box - 2 * pad) / 1024;
  return (x, y) => [ox + pad + x * s, oy + pad + y * s];
}

function tracePath(ctx, cmds, map) {
  ctx.beginPath();
  for (const c of cmds) {
    if (c.op === OPM) { const [x, y] = map(c.x, c.y); ctx.moveTo(x, y); }
    else if (c.op === OPL) { const [x, y] = map(c.x, c.y); ctx.lineTo(x, y); }
    else if (c.op === OPQ) {
      const [x1, y1] = map(c.x1, c.y1);
      const [x, y] = map(c.x, c.y);
      ctx.quadraticCurveTo(x1, y1, x, y);
    } else if (c.op === OPC) {
      const [c1x, c1y] = map(c.c1x, c.c1y);
      const [c2x, c2y] = map(c.c2x, c.c2y);
      const [x, y] = map(c.x, c.y);
      ctx.bezierCurveTo(c1x, c1y, c2x, c2y, x, y);
    } else if (c.op === OPZ) ctx.closePath();
  }
}

/**
 * 画一个图标。
 * @param {string} ch 汉字
 * @param {number} size 边长
 * @param {{bg:[string,string], ink:string, grid:boolean, inset:number}} opt
 */
function drawIcon(ch, size, opt) {
  const strokesData = JSON.parse(fs.readFileSync(path.join(RES, 'strokes.json'), 'utf8'));
  const strokes = decodeStrokes(strokesData[ch]);

  const canvas = createCanvas(size, size);
  const ctx = canvas.getContext('2d');

  // 背景：对角渐变，和 App 里今日任务卡同一套绿
  const g = ctx.createLinearGradient(0, 0, size, size);
  g.addColorStop(0, opt.bg[0]);
  g.addColorStop(1, opt.bg[1]);
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, size, size);

  // 圆角内衬（iOS 会自己切圆角，这里只做视觉层次）
  const inset = size * opt.inset;
  const box = size - inset * 2;

  if (opt.grid) {
    // 极淡的田字格，暗示「识字」这件事
    ctx.strokeStyle = 'rgba(255,255,255,0.18)';
    ctx.lineWidth = Math.max(1, size * 0.004);
    const r = size * 0.30;
    ctx.strokeRect(inset + size * 0.06, inset + size * 0.06,
                   box - size * 0.12, box - size * 0.12);
    ctx.setLineDash([size * 0.02, size * 0.02]);
    ctx.beginPath();
    ctx.moveTo(size / 2, inset + size * 0.09);
    ctx.lineTo(size / 2, size - inset - size * 0.09);
    ctx.moveTo(inset + size * 0.09, size / 2);
    ctx.lineTo(size - inset - size * 0.09, size / 2);
    ctx.stroke();
    ctx.setLineDash([]);
  }

  const map = mapper(box, inset, inset);
  ctx.fillStyle = opt.ink;
  for (const cmds of strokes) {
    tracePath(ctx, cmds, map);
    ctx.fill('nonzero');
  }

  return canvas;
}

// ---------- 主流程 ----------

const VARIANTS = [
  // 主图标：玉色渐变 + 白字「字」
  { name: 'AppIcon-1024', ch: '字', bg: ['#4FA091', '#2C6A5D'], ink: '#FFFFFF', grid: true, inset: 0.10 },
];

fs.mkdirSync(OUT_DIR, { recursive: true });

for (const v of VARIANTS) {
  const canvas = drawIcon(v.ch, 1024, v);
  // App Store 要求图标不带 alpha：用白底铺一层再输出
  const flat = createCanvas(1024, 1024);
  const fctx = flat.getContext('2d');
  fctx.fillStyle = '#FFFFFF';
  fctx.fillRect(0, 0, 1024, 1024);
  fctx.drawImage(canvas, 0, 0);
  const buf = flat.toBuffer('image/png');
  const file = path.join(OUT_DIR, `${v.name}.png`);
  fs.writeFileSync(file, buf);
  console.log(`${v.name}.png  ${buf.length} 字节  (字: ${v.ch})`);
}

// Contents.json：单尺寸 1024，iOS 17+ 只需要这一张
const contents = {
  images: [
    { filename: 'AppIcon-1024.png', idiom: 'universal', platform: 'ios', size: '1024x1024' },
  ],
  info: { author: 'xcode', version: 1 },
};
fs.writeFileSync(path.join(OUT_DIR, 'Contents.json'), JSON.stringify(contents, null, 2) + '\n');
console.log('Contents.json 已更新');
