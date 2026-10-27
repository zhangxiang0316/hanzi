#!/usr/bin/env node
/**
 * 把截图转成灰度 ASCII 图，方便在终端里检查排版。
 * （纯文本环境下用眼睛“看”布局：留白、对齐、块之间是否有重叠）
 *
 * 用法：node scripts/ascii-shot.mjs preview/screenshots/01-index.png [宽=64]
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { createCanvas, loadImage } = require('@napi-rs/canvas');

const RAMP = '@%#*+=-:. ';
const file = process.argv[2];
const W = Number(process.argv[3] || 64);

if (!file) {
  console.error('用法: node scripts/ascii-shot.mjs <png> [宽度]');
  process.exit(1);
}

const img = await loadImage(path.resolve(file));
const H = Math.max(1, Math.round((W * img.height) / img.width / 2.1)); // 字符高宽比约 2:1
const canvas = createCanvas(W, H);
const ctx = canvas.getContext('2d');
ctx.fillStyle = '#fff';
ctx.fillRect(0, 0, W, H);
ctx.drawImage(img, 0, 0, W, H);
const { data } = ctx.getImageData(0, 0, W, H);

// 自动判断深浅：纸张是浅色，文字是深色
let sum = 0;
for (let i = 0; i < data.length; i += 4) sum += (data[i] * 0.299 + data[i + 1] * 0.587 + data[i + 2] * 0.114) / 255;
const mean = sum / (W * H);

const lines = [];
for (let y = 0; y < H; y++) {
  let line = '';
  for (let x = 0; x < W; x++) {
    const i = (y * W + x) * 4;
    const lum = (data[i] * 0.299 + data[i + 1] * 0.587 + data[i + 2] * 0.114) / 255;
    const idx = Math.min(RAMP.length - 1, Math.max(0, Math.round(lum * (RAMP.length - 1))));
    line += RAMP[idx];
  }
  lines.push(line);
}
console.log(`${path.basename(file)}  ${img.width}x${img.height}  平均亮度 ${mean.toFixed(2)}`);
console.log('+' + '-'.repeat(W) + '+');
lines.forEach((l) => console.log('|' + l + '|'));
console.log('+' + '-'.repeat(W) + '+');
