#!/usr/bin/env node
/**
 * 渲染自检：用 Node 版 Canvas 跑真实的笔顺渲染代码，做像素级断言。
 * 同时把几张字卡导出到 preview/renders/，方便肉眼检查。
 *
 * 依赖：@napi-rs/canvas（仅开发用，不进入小程序包）
 * 用法：node scripts/render-check.mjs
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { createCanvas } = require('@napi-rs/canvas');

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const OUT = path.join(ROOT, 'preview/renders');
const hc = require('../miniprogram/utils/hanzi-canvas.js');
const catalog = require('../miniprogram/utils/catalog.js');
const { Player } = require('../miniprogram/utils/animation.js');
const strokeStore = require('../miniprogram/utils/stroke-store.js');
const routes = require('../miniprogram/utils/routes.js');

// 小程序里笔顺数据由分包页面按需注册；脚本环境手动注册全部册次
for (const book of Object.keys(routes.PACK_OF_BOOK)) {
  const pack = routes.packOf(book);
  strokeStore.register(book, () => require('../miniprogram/' + pack + '/data/strokes-' + book + '.js'));
}

const SIZE = 320;
const failures = [];
const check = (ok, msg) => {
  if (!ok) failures.push(msg);
};

function newCtx(background) {
  const canvas = createCanvas(SIZE, SIZE);
  const ctx = canvas.getContext('2d');
  if (background) {
    ctx.fillStyle = background;
    ctx.fillRect(0, 0, SIZE, SIZE);
  }
  return { canvas, ctx };
}

function stats(ctx) {
  const { data } = ctx.getImageData(0, 0, SIZE, SIZE);
  let ink = 0;
  let r = 0;
  let g = 0;
  let b = 0;
  let minX = SIZE;
  let maxX = -1;
  let minY = SIZE;
  let maxY = -1;
  for (let y = 0; y < SIZE; y++) {
    for (let x = 0; x < SIZE; x++) {
      const i = (y * SIZE + x) * 4;
      const a = data[i + 3] / 255;
      // 认为明显深于纸张的像素是墨迹
      const lum = (data[i] * 0.299 + data[i + 1] * 0.587 + data[i + 2] * 0.114) / 255;
      if (a > 0.5 && lum < 0.55) {
        ink++;
        r += x;
        g += y;
        b += 1;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  return {
    ink,
    ratio: ink / (SIZE * SIZE),
    cx: ink ? r / ink / SIZE : 0,
    cy: ink ? g / ink / SIZE : 0,
    box: { minX, maxX, minY, maxY },
  };
}

function savePNG(name, canvas) {
  fs.mkdirSync(OUT, { recursive: true });
  fs.writeFileSync(path.join(OUT, name), canvas.toBuffer('image/png'));
}

// ---------- 1. 整字渲染：墨迹占比与位置 ----------
const samples = ['天', '地', '人', '口', '日', '月', '水', '火', '山', '田', '我', '你', '春', '花', '雪', '书'];
for (const ch of samples) {
  const data = hc.get(ch);
  check(!!data, ch + ' 无法加载笔顺数据');
  if (!data) continue;
  const { canvas, ctx } = newCtx('#ffffff');
  hc.drawGrid(ctx, SIZE, 0, 0);
  hc.drawStrokes(ctx, data, SIZE, 0, 0, { completed: data.n });
  const s = stats(ctx);
  check(s.ratio > 0.03 && s.ratio < 0.5, `${ch} 墨迹占比异常 ${(s.ratio * 100).toFixed(1)}%`);
  check(s.cx > 0.3 && s.cx < 0.7, `${ch} 水平方向偏离中心 ${s.cx.toFixed(2)}`);
  check(s.cy > 0.28 && s.cy < 0.72, `${ch} 垂直方向偏离中心 ${s.cy.toFixed(2)}`);
  const w = (s.box.maxX - s.box.minX) / SIZE;
  const h = (s.box.maxY - s.box.minY) / SIZE;
  check(w > 0.35 && w < 0.95, `${ch} 字形宽度异常 ${(w * 100).toFixed(0)}%`);
  check(h > 0.4 && h < 0.95, `${ch} 字形高度异常 ${(h * 100).toFixed(0)}%`);
  check(s.box.minX >= 0 && s.box.maxX <= SIZE - 1, `${ch} 墨迹越出画布`);
  savePNG(`${ch}.png`, canvas);
}

// ---------- 1.5 字形上下方向：不能镜像 ----------
// 源数据曾是字体坐标系（y 向上），直接当屏幕坐标用会把整字上下颠倒。
// 用重心位置做双重校验：字对（与系统字体比）+ 字间（与彼此比）。
{
  const centroidOf = (ch, useFont) => {
    const { ctx } = newCtx('#ffffff');
    if (useFont) {
      ctx.fillStyle = '#000';
      ctx.font = `${Math.round(SIZE * 0.8)}px "PingFang SC", "Hiragino Sans GB", sans-serif`;
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(ch, SIZE / 2, SIZE / 2);
    } else {
      const d = hc.get(ch);
      if (!d) return null;
      hc.drawStrokes(ctx, d, SIZE, 0, 0, { completed: d.n, showGhost: false });
    }
    const { data } = ctx.getImageData(0, 0, SIZE, SIZE);
    let n = 0;
    let sy = 0;
    for (let y = 0; y < SIZE; y++) {
      for (let x = 0; x < SIZE; x++) {
        const i = (y * SIZE + x) * 4;
        const lum = (data[i] * 0.299 + data[i + 1] * 0.587 + data[i + 2] * 0.114) / 255;
        const alpha = useFont ? data[i] < 140 : data[i + 3] > 40 && lum < 0.55;
        if (alpha) {
          n++;
          sy += y;
        }
      }
    }
    return n ? sy / n / SIZE : null;
  };

  // (a) 字间：上的底部长横让它重心必定低于下
  const up = centroidOf('上', false);
  const down = centroidOf('下', false);
  check(up != null && down != null, '上/下 渲染失败');
  check(up > down + 0.08, `字形上下颠倒：“上”的重心(${up.toFixed(2)})应明显低于“下”(${down.toFixed(2)})`);

  // (b) 字对：与系统字体渲染的重心比对，容忍字体差异
  const compared = [];
  for (const ch of ['上', '下', '天', '由', '甲', '春', '月']) {
    const mine = centroidOf(ch, false);
    const ref = centroidOf(ch, true);
    if (mine == null || ref == null) continue;
    compared.push({ ch, diff: Math.abs(mine - ref) });
    check(
      Math.abs(mine - ref) < 0.09,
      `${ch} 垂直重心与系统字体相差 ${Math.abs(mine - ref).toFixed(2)}，疑似上下镜像`
    );
  }
  check(compared.length >= 4, '可对比的字太少，方向检查无效');
  console.log(
    '  方向: ' +
      compared.map((c) => `${c.ch}Δ${c.diff.toFixed(2)}`).join(' ')
  );
}

// ---------- 2. 笔顺推进：墨迹必须递增 ----------
for (const ch of ['天', '我', '春']) {
  const data = hc.get(ch);
  let prev = -1;
  const series = [];
  for (let k = 0; k <= data.n; k++) {
    const { ctx } = newCtx('#ffffff');
    hc.drawStrokes(ctx, data, SIZE, 0, 0, { completed: k, showGhost: false });
    const s = stats(ctx);
    check(s.ink > prev, `${ch} 第 ${k} 笔后墨迹没有增加 (${prev} -> ${s.ink})`);
    prev = s.ink;
    series.push(s.ink);
  }
  check(series[0] === 0, `${ch} 未写字时不应该有墨迹`);
  check(series[series.length - 1] === prev, `${ch} 最后一笔墨迹异常`);
  console.log(`  ${ch}: 笔迹像素 ${series.join(' → ')}`);
}

// ---------- 3. 单笔进度：0 → 1 墨迹单调增加 ----------
{
  const data = hc.get('天');
  let prev = -1;
  for (const p of [0, 0.25, 0.5, 0.75, 1]) {
    const { ctx } = newCtx('#ffffff');
    hc.drawStrokes(ctx, data, SIZE, 0, 0, { completed: 0, partial: p, showGhost: false });
    const s = stats(ctx);
    check(s.ink >= prev, `单笔进度 ${p} 墨迹倒退 (${prev} -> ${s.ink})`);
    prev = s.ink;
  }
  check(prev > 100, '单笔写完后墨迹过少: ' + prev);
}

// ---------- 4. 田字格与起笔序号 ----------
{
  const { ctx } = newCtx('#ffffff');
  hc.drawGrid(ctx, SIZE, 0, 0);
  const gridData = ctx.getImageData(0, 0, SIZE, SIZE).data;
  let nonWhite = 0;
  for (let i = 0; i < gridData.length; i += 4) {
    if (gridData[i] < 250 || gridData[i + 1] < 250 || gridData[i + 2] < 250) nonWhite++;
  }
  check(nonWhite > 300, '田字格线条没有画出来 (' + nonWhite + ' 像素)');
  const { ctx: ctx2 } = newCtx('#ffffff');
  const data = hc.get('人');
  hc.drawStrokes(ctx2, data, SIZE, 0, 0, { completed: data.n });
  const noNums = stats(ctx2).ink;
  const { ctx: ctx3 } = newCtx('#ffffff');
  hc.drawStrokes(ctx3, data, SIZE, 0, 0, { completed: data.n });
  hc.drawStrokeNumbers(ctx3, data, SIZE, 0, 0);
  const withNums = stats(ctx3).ink;
  check(withNums !== noNums, '笔顺序号没有产生视觉差异');
}

// ---------- 5. 动画播放器：能跑完且结果等于终态 ----------
{
  const data = hc.get('口');
  const { canvas, ctx } = newCtx('#ffffff');
  let frames = 0;
  let done = false;
  const player = new Player({
    ctx,
    canvas: null,
    data,
    box: SIZE,
    speed: 6,
    onProgress() {
      frames++;
    },
    onDone() {
      done = true;
    },
  });
  player.play();
  const start = Date.now();
  while (!done && Date.now() - start < 8000) {
    // 让出事件循环，让 setTimeout 驱动的帧继续
    await new Promise((r) => setTimeout(r, 20));
  }
  check(done, '动画没有在 8 秒内播完');
  check(frames > 5, '动画帧数过少: ' + frames);
  const animated = stats(ctx).ink;
  const { ctx: refCtx } = newCtx('#ffffff');
  hc.drawStrokes(refCtx, data, SIZE, 0, 0, { completed: data.n });
  const reference = stats(refCtx).ink;
  check(Math.abs(animated - reference) / reference < 0.15, `动画终态墨迹 ${animated} 与静态 ${reference} 差异过大`);
  savePNG('animation-final.png', canvas);
}

// ---------- 6. 字卡合集（给人工检查）----------
{
  const cols = 4;
  const rows = Math.ceil(samples.length / cols);
  const cell = 160;
  const sheet = createCanvas(cols * cell, rows * cell);
  const sctx = sheet.getContext('2d');
  sctx.fillStyle = '#FBF7EE';
  sctx.fillRect(0, 0, sheet.width, sheet.height);
  samples.forEach((ch, i) => {
    const data = hc.get(ch);
    const x = (i % cols) * cell;
    const y = Math.floor(i / cols) * cell;
    sctx.save();
    sctx.translate(x + 8, y + 8);
    hc.drawGrid(sctx, cell - 16, 0, 0);
    hc.drawStrokes(sctx, data, cell - 16, 0, 0, { completed: data.n });
    sctx.restore();
  });
  savePNG('sheet.png', sheet);
}

if (failures.length) {
  console.error(`✗ 渲染自检失败 ${failures.length} 项`);
  failures.forEach((f) => console.error('  · ' + f));
  process.exit(1);
}
console.log(`✓ 渲染自检通过：${samples.length} 个字、笔顺递增、动画终态一致，图片已输出到 preview/renders/`);
