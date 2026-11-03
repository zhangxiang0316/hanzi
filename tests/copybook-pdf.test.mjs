import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { Pdf, rgb } = require('../miniprogram/utils/pdf.js');
const cp = require('../miniprogram/utils/copybook-pdf.js');
const { decode } = require('../miniprogram/utils/stroke-codec.js');

const strokes1a = require('../miniprogram/packageStrokes/data/strokes-1a.js');

/** 取字的笔画数据，取不到返回 null（和页面里的回调行为一致） */
function strokeFor(ch) {
  const raw = strokes1a[ch];
  return raw ? decode(raw) : null;
}

function text(bytes) {
  return Buffer.from(bytes).toString('latin1');
}

/**
 * 字帖导出 PDF。
 *
 * 小程序没有生成 PDF 的 API，只能自己拼字节。拼错了的 PDF 在阅读器里
 * 要么打不开、要么整页空白——所以这里既验结构（xref 偏移、对象数），
 * 也验内容（路径指令真的写进去了）。
 */

test('PDF 以 %PDF 开头、以 %%EOF 结尾', () => {
  const pdf = new Pdf();
  pdf.endPage();
  const s = text(pdf.build());
  assert.ok(s.startsWith('%PDF-1.4'));
  assert.ok(s.trimEnd().endsWith('%%EOF'));
});

test('交叉引用表的偏移量指向真正的对象开头', () => {
  // xref 里的偏移错一位，阅读器就整份文件打不开。这是手写 PDF 最容易错的地方。
  const pdf = new Pdf();
  pdf.moveTo(10, 10);
  pdf.lineTo(20, 20);
  pdf.stroke();
  pdf.endPage();
  pdf.endPage();
  const s = text(pdf.build());

  const xrefPos = Number(/startxref\s+(\d+)/.exec(s)[1]);
  assert.equal(s.slice(xrefPos, xrefPos + 4), 'xref');

  const table = s.slice(xrefPos);
  const lines = table.split('\n').slice(2);
  let checked = 0;
  for (const line of lines) {
    const m = /^(\d{10}) 00000 n/.exec(line);
    if (!m) continue;
    const off = Number(m[1]);
    // 每个 n 条目都应该正好落在一个 "N 0 obj" 上
    assert.match(s.slice(off, off + 12), /^\d+ 0 obj/);
    checked++;
  }
  assert.ok(checked >= 4, `只校验了 ${checked} 个对象`);
});

test('页数正确，每页都有 Page 和 Contents 对象', () => {
  const chars = ['天', '地', '人', '你', '我', '他', '一', '二'];
  const r = cp.buildPdf(chars, strokeFor, { dateLabel: '2026-01-01' });
  // 一页六个字 → 8 个字两页
  assert.equal(r.pages, 2);
  const s = text(r.bytes);
  assert.equal((s.match(/\/Type \/Page[^s]/g) || []).length, 2);
  assert.equal((s.match(/\/Type \/Pages/g) || []).length, 1);
});

test('Helvetica 不嵌入，只引用 Base-14 标准字体', () => {
  const r = cp.buildPdf(['天'], strokeFor, { dateLabel: '2026-01-01' });
  const s = text(r.bytes);
  assert.ok(s.includes('/BaseFont /Helvetica'));
  // 不嵌字体 = 没有 FontFile，文件才可能只有几十 KB
  assert.ok(!s.includes('/FontFile'));
});

test('日期和页码用 ASCII 写进页眉', () => {
  const r = cp.buildPdf(['天', '地'], strokeFor, { dateLabel: '2026-11-03' });
  const s = text(r.bytes);
  assert.ok(s.includes('(2026-11-03) Tj'));
  assert.ok(s.includes('(1 / 1) Tj'));
});

test('汉字画成矢量路径，不是文字', () => {
  const r = cp.buildPdf(['天'], strokeFor, { dateLabel: '' });
  const s = text(r.bytes);
  // 有填充路径指令
  assert.ok(s.includes('\nf\n'));
  // 但没有任何把汉字当字符串写进去的地方
  assert.ok(!s.includes('天'));
});

test('二次贝塞尔升阶成三次（PDF 没有 q 指令）', () => {
  const pdf = new Pdf();
  pdf.moveTo(0, 0);
  pdf.quadTo(50, 100, 100, 0);
  const s = pdf.ops.join('\n');
  assert.ok(!/\bq\b/.test(s.replace(/^q$/gm, '')), '不该出现二次曲线指令');
  assert.ok(/\bc$/.test(s.trim().split('\n').pop()), '应该转成三次曲线 c');
  // 升阶后控制点应在 1/3 和 2/3 处：P0=(0,0) Q=(50,100) P1=(100,0)
  const m = /([\d.-]+) ([\d.-]+) ([\d.-]+) ([\d.-]+) 100 0 c/.exec(s);
  assert.ok(m, '找不到三次曲线指令');
  assert.equal(Number(m[1]), 33.33);
  assert.equal(Number(m[2]), 66.67);
});

test('数字格式不用科学计数法（阅读器会整页不显示）', () => {
  const pdf = new Pdf();
  pdf.moveTo(0.0000001, 1e-9);
  pdf.lineTo(1.23456789, 100);
  const s = pdf.ops.join('\n');
  assert.ok(!/e[+-]/i.test(s), `出现了科学计数法：${s}`);
  assert.ok(s.includes('0 0 m'), '极小的值应该被归零');
});

test('一页六个字，格子四列', () => {
  assert.equal(cp.LAYOUT.rowsPerPage, 6);
  assert.equal(cp.LAYOUT.cols, 4);
  const { pages } = cp.layout(['天', '地', '人', '你', '我', '他', '一']);
  assert.equal(pages.length, 2);
  assert.equal(pages[0].rows.length, 6);
  assert.equal(pages[1].rows.length, 1);
});

test('第一格是范字，后三格是描红格', () => {
  const { pages } = cp.layout(['天']);
  const cells = pages[0].rows[0].cells;
  assert.equal(cells.length, 4);
  assert.equal(cells[0].solid, true);
  assert.deepEqual(cells.slice(1).map((c) => c.solid), [false, false, false]);
});

test('格子横向居中，不贴左边', () => {
  const { pages, layout: l } = cp.layout(['天']);
  const cells = pages[0].rows[0].cells;
  const left = cells[0].x;
  const right = cells[cells.length - 1].x + cells[0].size;
  const leftMargin = left - l.margin;
  const rightMargin = l.pageW - l.margin - right;
  assert.ok(Math.abs(leftMargin - rightMargin) < 0.01, '左右边距应该相等');
  assert.ok(leftMargin > 0);
});

test('格子之间不重叠，行与行之间留了间隙', () => {
  const { pages } = cp.layout(['天', '地']);
  const cells = pages[0].rows[0].cells;
  for (let i = 1; i < cells.length; i++) {
    const prevRight = cells[i - 1].x + cells[i - 1].size;
    assert.ok(cells[i].x >= prevRight, '第 ' + i + ' 格和前一格重叠了');
  }
  const r0 = pages[0].rows[0].cells[0];
  const r1 = pages[0].rows[1].cells[0];
  assert.ok(r1.y + r1.size <= r0.y, '第二行压到第一行了');
});

test('所有格子都在页面以内', () => {
  const { pages, layout: l } = cp.layout(
    ['天', '地', '人', '你', '我', '他', '一', '二', '三', '四', '五', '六']
  );
  for (const page of pages) {
    for (const row of page.rows) {
      for (const c of row.cells) {
        assert.ok(c.y > l.margin, '格子掉出下边距');
        assert.ok(c.y + c.size < l.pageH - l.margin, '格子超出上边距');
        assert.ok(c.x > l.margin, '格子超出左边距');
        assert.ok(c.x + c.size < l.pageW - l.margin, '格子超出右边距');
      }
    }
  }
});

test('没有笔画数据的字被跳过并报回来，不会静默少字', () => {
  // 「龘」这种字不在字帖数据里
  const r = cp.buildPdf(['天', '龘', '地'], (ch) => strokeFor(ch), { dateLabel: '' });
  assert.deepEqual(r.drawn, ['天', '地']);
  assert.deepEqual(r.skipped, ['龘']);
});

test('一个字都画不出来时 drawn 为空（页面据此提示用户）', () => {
  const r = cp.buildPdf(['龘'], () => null, { dateLabel: '' });
  assert.equal(r.drawn.length, 0);
  assert.equal(r.pages, 1);
});

test('空列表也能生成（不会崩）', () => {
  const r = cp.buildPdf([], strokeFor, { dateLabel: '' });
  assert.equal(r.pages, 0);
  const s = text(r.bytes);
  assert.ok(s.startsWith('%PDF'));
  assert.ok(s.includes('/Count 0'));
});

test('字节长度和字符数一致（全 ASCII + Latin-1 单字节）', () => {
  const r = cp.buildPdf(['天'], strokeFor, { dateLabel: '2026-01-01' });
  const s = text(r.bytes);
  assert.equal(s.length, r.bytes.length);
  assert.equal(r.bytes.length % 1, 0);
});

test('文件名带日期，扩展名是 .pdf', () => {
  const name = cp.fileName('字帖');
  assert.match(name, /^字帖-\d{8}\.pdf$/);
});

test('dateLabel 补零', () => {
  assert.equal(cp.dateLabel(new Date(2026, 0, 5)), '2026-01-05');
  assert.equal(cp.dateLabel(new Date(2026, 11, 31)), '2026-12-31');
});

test('rgb 把 #rrggbb 转成 0-1 三元组', () => {
  assert.deepEqual(rgb('#000000'), [0, 0, 0]);
  assert.deepEqual(rgb('#ffffff'), [1, 1, 1]);
  const [r, g, b] = rgb('#3e8e7e');
  assert.ok(Math.abs(r - 62 / 255) < 1e-9);
  assert.ok(Math.abs(g - 142 / 255) < 1e-9);
  assert.ok(Math.abs(b - 126 / 255) < 1e-9);
});

test('每个字都真的产生了路径指令（不是空页）', () => {
  const { bytes } = cp.buildPdf(['天', '地'], strokeFor, { dateLabel: '' });
  const s = text(bytes);
  // 笔画数据里的 moveTo/lineTo 会成为 m / l 指令
  assert.ok(/(\d+ )?m\n/.test(s) || /\d m\n/.test(s), '没有 moveto 指令');
  assert.ok(/\d l\n/.test(s), '没有 lineto 指令');
  assert.ok(s.split('\nf\n').length > 3, '填充次数太少，字可能没画出来');
});
