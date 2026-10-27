import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const catalog = require('../miniprogram/utils/catalog.js');
const { decode } = require('../miniprogram/packageStrokes/utils/stroke-codec.js');

const BOOKS = ['1a', '1b', '2a', '2b'];

test('四册共 1600 个生字', () => {
  const all = catalog.getAllChars();
  assert.equal(all.length, 1600);
  const union = new Set();
  for (const b of BOOKS) for (const ch of catalog.bookChars(b)) union.add(ch);
  assert.equal(union.size, 1600);
});

test('每册字数与教材一致', () => {
  assert.deepEqual(BOOKS.map((b) => catalog.bookStat(b).chars), [300, 400, 450, 450]);
  assert.equal(catalog.getBooks().length, 4);
});

test('每个字都有拼音、部首、笔画数、组词和课文出处', () => {
  const bad = [];
  for (const ch of catalog.getAllChars()) {
    const m = catalog.getMeta(ch);
    if (!m) { bad.push(ch + ':无数据'); continue; }
    if (!m.py || !/^[a-züāáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜ]+$/.test(m.py)) bad.push(ch + ':拼音异常 ' + m.py);
    if (!m.r) bad.push(ch + ':无部首');
    if (!m.s || m.s < 1 || m.s > 40) bad.push(ch + ':笔画数异常 ' + m.s);
    if (!m.l || !catalog.getLesson(m.l)) bad.push(ch + ':出处课文无效');
    if (!m.w || !m.w.length) bad.push(ch + ':无组词');
    for (const w of m.w) {
      if (w.w.indexOf(ch) < 0) bad.push(ch + ':组词不含本字 ' + w.w);
      if (w.p && w.p.split(' ').length !== [...w.w].length) bad.push(ch + ':组词拼音数不匹配 ' + w.w + ' ' + w.p);
    }
  }
  assert.deepEqual(bad, []);
});

test('写字表中的字都有练字标记', () => {
  let count = 0;
  for (const b of BOOKS) {
    for (const lid of catalog.getBook(b).lessons) {
      for (const ch of catalog.getLesson(lid).write) {
        assert.ok(catalog.isWriteChar(ch), ch + ' 缺少写字标记');
        count++;
      }
    }
  }
  assert.ok(count >= 800, '写字表数量异常: ' + count);
});

test('全部 1600 字笔顺数据可解码且与笔画数一致', () => {
  const bad = [];
  let totalStrokes = 0;
  for (const ch of catalog.getAllChars()) {
    const m = catalog.getMeta(ch);
    const store = require('../miniprogram/packageStrokes/data/strokes-' + m.b + '.js');
    const raw = store[ch];
    if (!raw) { bad.push(ch + ':无笔顺'); continue; }
    const d = decode(raw);
    totalStrokes += d.n;
    if (d.n !== m.s) bad.push(ch + ':笔画数不一致 ' + d.n + ' vs ' + m.s);
    if (d.medians.length !== d.n) bad.push(ch + ':中线数量不一致');
    for (const stroke of d.strokes) {
      if (stroke[0][0] !== 0) bad.push(ch + ':笔画未以 M 开始');
      if (stroke[stroke.length - 1][0] !== 4) bad.push(ch + ':笔画未闭合');
      for (const cmd of stroke) {
        for (let i = 1; i < cmd.length; i++) {
          if (cmd[i] < 0 || cmd[i] > 1024) bad.push(ch + ':坐标越界 ' + cmd[i]);
        }
      }
    }
    for (const med of d.medians) {
      if (med.length < 2) bad.push(ch + ':中线点太少');
      for (const p of med) {
        if (p[0] < 0 || p[0] > 1024 || p[1] < 0 || p[1] > 1024) bad.push(ch + ':中线越界');
      }
    }
  }
  assert.deepEqual(bad.slice(0, 20), []);
  assert.ok(totalStrokes > 14000, '总笔画数异常: ' + totalStrokes);
});

test('多音字按课文读音', () => {
  const ch = '长';
  const details = catalog.readingDetails(ch);
  assert.ok(details.length >= 2, '长 应该是多音字');
  const readings = details.map((d) => d.p);
  assert.ok(readings.includes('cháng'));
  assert.ok(readings.includes('zhǎng'));
});

test('课文顺序与单元结构完整', () => {
  for (const b of catalog.getBooks()) {
    const seen = new Set();
    for (const u of b.units) {
      assert.ok(u.lessons.length > 0, b.id + ' 单元 ' + u.no + ' 没有课文');
      for (const lid of u.lessons) {
        assert.ok(catalog.getLesson(lid), '缺少课文 ' + lid);
        assert.ok(!seen.has(lid), '课文重复 ' + lid);
        seen.add(lid);
      }
    }
    assert.equal(seen.size, b.lessons.length);
  }
});
