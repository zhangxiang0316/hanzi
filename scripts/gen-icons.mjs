#!/usr/bin/env node
/**
 * 生成 tabBar 图标（81×81 PNG，含 @3x 视觉清晰度）
 * 纯 Node 实现：3 倍超采样光栅化 + 手写 PNG 编码，无第三方依赖。
 */
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const OUT = path.join(ROOT, 'miniprogram/images');
const SIZE = 81;
const SS = 3; // 超采样倍数
const W = SIZE * SS;

const IDLE = [162, 156, 143];
const ACTIVE = [62, 142, 126];

// ---------- 画布 ----------
function canvas() {
  return { w: W, h: W, data: new Uint8Array(W * W * 4) };
}

function blend(c, x, y, color, alpha) {
  if (x < 0 || y < 0 || x >= c.w || y >= c.h) return;
  const i = (y * c.w + x) * 4;
  const a = Math.max(0, Math.min(1, alpha));
  const d = c.data;
  const sa = a;
  const da = d[i + 3] / 255;
  const oa = sa + da * (1 - sa);
  if (oa <= 0) return;
  for (let k = 0; k < 3; k++) {
    d[i + k] = Math.round((color[k] * sa + d[i + k] * da * (1 - sa)) / oa);
  }
  d[i + 3] = Math.round(oa * 255);
}

function fillRect(c, x, y, w, h, color) {
  const x0 = Math.max(0, Math.floor(x));
  const y0 = Math.max(0, Math.floor(y));
  const x1 = Math.min(c.w, Math.ceil(x + w));
  const y1 = Math.min(c.h, Math.ceil(y + h));
  for (let yy = y0; yy < y1; yy++) {
    for (let xx = x0; xx < x1; xx++) blend(c, xx, yy, color, 1);
  }
}

/** 圆角矩形（实心或环形），用像素中心到圆角矩形的距离判断 */
function roundRect(c, x, y, w, h, r, color, thickness) {
  const t = thickness || 0;
  const cx = x + w / 2;
  const cy = y + h / 2;
  const hw = w / 2;
  const hh = h / 2;
  for (let yy = Math.floor(y - 2); yy < Math.ceil(y + h + 2); yy++) {
    for (let xx = Math.floor(x - 2); xx < Math.ceil(x + w + 2); xx++) {
      const px = xx + 0.5;
      const py = yy + 0.5;
      // 到圆角矩形边界的有符号距离
      const qx = Math.abs(px - cx) - (hw - r);
      const qy = Math.abs(py - cy) - (hh - r);
      const ax = Math.max(qx, 0);
      const ay = Math.max(qy, 0);
      const outside = Math.sqrt(ax * ax + ay * ay) + Math.min(Math.max(qx, qy), 0) - r;
      if (t > 0) {
        if (outside <= 0 && outside >= -t) blend(c, xx, yy, color, 1);
      } else if (outside <= 0) blend(c, xx, yy, color, 1);
    }
  }
}

function circle(c, cx, cy, r, color, thickness) {
  const t = thickness || 0;
  for (let yy = Math.floor(cy - r - 2); yy < Math.ceil(cy + r + 2); yy++) {
    for (let xx = Math.floor(cx - r - 2); xx < Math.ceil(cx + r + 2); xx++) {
      const d = Math.hypot(xx + 0.5 - cx, yy + 0.5 - cy);
      if (t > 0) {
        if (d <= r && d >= r - t) blend(c, xx, yy, color, 1);
      } else if (d <= r) blend(c, xx, yy, color, 1);
    }
  }
}

/** 粗线段（圆头） */
function line(c, x1, y1, x2, y2, width, color) {
  const r = width / 2;
  const minX = Math.floor(Math.min(x1, x2) - r - 2);
  const maxX = Math.ceil(Math.max(x1, x2) + r + 2);
  const minY = Math.floor(Math.min(y1, y2) - r - 2);
  const maxY = Math.ceil(Math.max(y1, y2) + r + 2);
  const dx = x2 - x1;
  const dy = y2 - y1;
  const len2 = dx * dx + dy * dy;
  for (let yy = minY; yy < maxY; yy++) {
    for (let xx = minX; xx < maxX; xx++) {
      const px = xx + 0.5;
      const py = yy + 0.5;
      let t = len2 ? ((px - x1) * dx + (py - y1) * dy) / len2 : 0;
      t = Math.max(0, Math.min(1, t));
      const d = Math.hypot(px - (x1 + dx * t), py - (y1 + dy * t));
      if (d <= r) blend(c, xx, yy, color, 1);
    }
  }
}

function poly(c, pts, color) {
  const xs = pts.map((p) => p[0]);
  const ys = pts.map((p) => p[1]);
  const minX = Math.floor(Math.min(...xs));
  const maxX = Math.ceil(Math.max(...xs));
  const minY = Math.floor(Math.min(...ys));
  const maxY = Math.ceil(Math.max(...ys));
  for (let yy = minY; yy < maxY; yy++) {
    for (let xx = minX; xx < maxX; xx++) {
      let inside = false;
      const px = xx + 0.5;
      const py = yy + 0.5;
      for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) {
        const xi = pts[i][0];
        const yi = pts[i][1];
        const xj = pts[j][0];
        const yj = pts[j][1];
        if (yi > py !== yj > py && px < ((xj - xi) * (py - yi)) / (yj - yi) + xi) inside = !inside;
      }
      if (inside) blend(c, xx, yy, color, 1);
    }
  }
}

// ---------- 图标绘制（坐标基于 81 逻辑像素，内部乘 SS） ----------
const s = (v) => v * SS;

function iconLearn(c, color) {
  // 田字格 + 上方一点，代表“学字”
  roundRect(c, s(13), s(16), s(55), s(55), s(10), color, s(4.5));
  line(c, s(40.5), s(24), s(40.5), s(63), s(3.4), color);
  line(c, s(21), s(43.5), s(60), s(43.5), s(3.4), color);
  circle(c, s(40.5), s(9.5), s(3.6), color);
}

function iconPractice(c, color) {
  // 铅笔：斜向笔身 + 笔尖
  const angle = -45 * (Math.PI / 180);
  const cx = 40.5;
  const cy = 43;
  const L = 46;
  const halfW = 9;
  const ux = Math.cos(angle);
  const uy = Math.sin(angle);
  const px = -uy;
  const py = ux;
  const a = [cx + ux * L * 0.45, cy + uy * L * 0.45];
  const b = [cx + ux * L * 0.45 + px * halfW, cy + uy * L * 0.45 + py * halfW];
  const d = [a[0] - ux * L, a[1] - uy * L];
  const e = [b[0] - ux * L, b[1] - uy * L];
  const c2 = [d[0] + px * halfW, d[1] + py * halfW];
  const f = [e[0] + px * halfW, e[1] + py * halfW];
  poly(c, [a, b, f, c2], color);
  // 笔尖
  const tip = [c2[0] - ux * 10, c2[1] - uy * 10];
  poly(c, [c2, f, tip], color);
  // 笔帽
  line(c, a[0] - ux * 4, a[1] - uy * 4, b[0] - ux * 4, b[1] - uy * 4, s(3), color);
}

function iconProfile(c, color) {
  circle(c, s(40.5), s(28), s(13), color);
  roundRect(c, s(16), s(46), s(49), s(34), s(17), color);
  // 挖空底部，形成肩部
  fillRect(c, s(0), s(72), s(81), s(9), [0, 0, 0], 0);
}

// ---------- PNG 编码 ----------
const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();

function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length, 0);
  const typeBuf = Buffer.from(type, 'ascii');
  const crcBuf = Buffer.alloc(4);
  crcBuf.writeUInt32BE(crc32(Buffer.concat([typeBuf, data])), 0);
  return Buffer.concat([len, typeBuf, data, crcBuf]);
}

function encodePNG(rgba, w, h) {
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (w * 4 + 1)] = 0;
    rgba.copy(raw, y * (w * 4 + 1) + 1, y * w * 4, (y + 1) * w * 4);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // RGBA
  ihdr[10] = 0;
  ihdr[11] = 0;
  ihdr[12] = 0;
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

function downsample(c) {
  const out = Buffer.alloc(SIZE * SIZE * 4);
  for (let y = 0; y < SIZE; y++) {
    for (let x = 0; x < SIZE; x++) {
      let r = 0;
      let g = 0;
      let b = 0;
      let a = 0;
      for (let sy = 0; sy < SS; sy++) {
        for (let sx = 0; sx < SS; sx++) {
          const i = ((y * SS + sy) * W + (x * SS + sx)) * 4;
          const sa = c.data[i + 3] / 255;
          r += c.data[i] * sa;
          g += c.data[i + 1] * sa;
          b += c.data[i + 2] * sa;
          a += sa;
        }
      }
      const n = SS * SS;
      const o = (y * SIZE + x) * 4;
      if (a > 0) {
        out[o] = Math.round(r / a);
        out[o + 1] = Math.round(g / a);
        out[o + 2] = Math.round(b / a);
      }
      out[o + 3] = Math.round((a / n) * 255);
    }
  }
  return out;
}

function render(draw, color) {
  const c = canvas();
  draw(c, color);
  return downsample(c);
}

function main() {
  fs.mkdirSync(OUT, { recursive: true });
  const icons = [
    ['tab-learn', iconLearn],
    ['tab-practice', iconPractice],
    ['tab-profile', iconProfile],
  ];
  for (const [name, draw] of icons) {
    const idle = encodePNG(render(draw, IDLE), SIZE, SIZE);
    const active = encodePNG(render(draw, ACTIVE), SIZE, SIZE);
    fs.writeFileSync(path.join(OUT, name + '.png'), idle);
    fs.writeFileSync(path.join(OUT, name + '-on.png'), active);
    console.log('✓', name + '.png', idle.length, 'B', name + '-on.png', active.length, 'B');
  }
}

main();
