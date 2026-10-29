import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const { createCanvas, loadImage } = require('@napi-rs/canvas');

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const DIR = path.join(ROOT, 'miniprogram/images');
const SIZE = 81;
const NAMES = ['tab-learn', 'tab-practice', 'tab-profile'];

/** 读 PNG 的 alpha 通道，返回 { alpha(x,y), ink, bbox, fullRows } */
async function readIcon(file) {
  const img = await loadImage(file);
  const canvas = createCanvas(img.width, img.height);
  const ctx = canvas.getContext('2d');
  ctx.drawImage(img, 0, 0);
  const data = ctx.getImageData(0, 0, img.width, img.height).data;
  const w = img.width;
  const h = img.height;

  let ink = 0;
  let minX = Infinity;
  let maxX = -1;
  let minY = Infinity;
  let maxY = -1;
  let fullRows = 0;

  for (let y = 0; y < h; y++) {
    let rowInk = 0;
    for (let x = 0; x < w; x++) {
      const a = data[(y * w + x) * 4 + 3];
      if (a > 20) {
        ink++;
        rowInk++;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
    // 整行都是不透明像素 —— tabBar 上就是一条横贯的线
    if (rowInk === w) fullRows++;
  }

  return {
    w,
    h,
    ink,
    coverage: ink / (w * h),
    fullRows,
    bbox: { minX, maxX, minY, maxY, w: maxX - minX + 1, h: maxY - minY + 1 },
    center: { x: (minX + maxX) / 2, y: (minY + maxY) / 2 },
  };
}

test('tabBar 图标齐全且尺寸正确', () => {
  for (const name of NAMES) {
    for (const suffix of ['', '-on']) {
      const file = path.join(DIR, name + suffix + '.png');
      assert.ok(fs.existsSync(file), '缺少图标 ' + name + suffix + '.png');
      const stat = fs.statSync(file);
      assert.ok(stat.size > 100, name + suffix + '.png 内容为空');
      assert.ok(stat.size < 20 * 1024, name + suffix + '.png 过大，图标应当很小');
    }
  }
});

test('图标里不能有横贯整行的实心边（"下面多一条横线"的元凶）', async () => {
  const bad = [];
  for (const name of NAMES) {
    for (const suffix of ['', '-on']) {
      const icon = await readIcon(path.join(DIR, name + suffix + '.png'));
      if (icon.fullRows > 0) bad.push(`${name}${suffix}: ${icon.fullRows} 行整行不透明`);
    }
  }
  assert.deepEqual(bad, [], bad.join('；'));
});

test('图标内容大小适中且居中，不能缩在角落', async () => {
  const problems = [];
  for (const name of NAMES) {
    for (const suffix of ['', '-on']) {
      const icon = await readIcon(path.join(DIR, name + suffix + '.png'));
      const label = name + suffix;
      // 图形要撑得起画布（太小说明坐标没做超采样映射，会缩在角落）
      if (icon.bbox.w < SIZE * 0.4) problems.push(`${label} 太窄 ${icon.bbox.w}px`);
      if (icon.bbox.h < SIZE * 0.4) problems.push(`${label} 太矮 ${icon.bbox.h}px`);
      // 不能撑满到边缘（贴边会被 tabBar 裁掉）
      if (icon.bbox.minX < 2 || icon.bbox.minY < 2) problems.push(`${label} 贴边`);
      // 视觉重心要接近画布中心
      if (Math.abs(icon.center.x - SIZE / 2) > 8) problems.push(`${label} 横向偏移 ${icon.center.x}`);
      if (Math.abs(icon.center.y - SIZE / 2) > 8) problems.push(`${label} 纵向偏移 ${icon.center.y}`);
      // 墨迹占比太少 = 图形没画出来；太多 = 糊成一块
      if (icon.coverage < 0.05) problems.push(`${label} 墨迹过少 ${(icon.coverage * 100).toFixed(1)}%`);
      if (icon.coverage > 0.45) problems.push(`${label} 墨迹过多 ${(icon.coverage * 100).toFixed(1)}%`);
    }
  }
  assert.deepEqual(problems, [], problems.join('；'));
});

test('选中态与未选中态形状一致，只有颜色不同', async () => {
  for (const name of NAMES) {
    const idle = await readIcon(path.join(DIR, name + '.png'));
    const active = await readIcon(path.join(DIR, name + '-on.png'));
    assert.deepEqual(active.bbox, idle.bbox, name + ' 选中态形状变了');
    assert.ok(
      Math.abs(active.coverage - idle.coverage) < 0.01,
      name + ' 选中态墨迹量差异过大'
    );
  }
});

test('图标尺寸与 tabBar 配置匹配', () => {
  const app = JSON.parse(fs.readFileSync(path.join(ROOT, 'miniprogram/app.json'), 'utf8'));
  for (const item of app.tabBar.list) {
    for (const key of ['iconPath', 'selectedIconPath']) {
      const rel = item[key];
      assert.ok(rel, item.pagePath + ' 缺少 ' + key);
      assert.ok(
        fs.existsSync(path.join(ROOT, 'miniprogram', rel)),
        `tabBar 引用的图标不存在: ${rel}`
      );
    }
  }
});
