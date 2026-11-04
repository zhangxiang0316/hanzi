import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const pick = require('../miniprogram/utils/copybook-pick.js');

/**
 * 字帖选字。
 *
 * 这块的价值全在「哪些字能真的画出来」上——小程序主包拿不到分包的笔画
 * 数据，导出一张缺字的字帖让孩子描空格子，比不导出更糟。
 */

test('合并去重，保持首次出现的顺序', () => {
  const m = pick.merge([
    { ch: '天', from: 'lesson' },
    { ch: '地', from: 'wrong' },
    { ch: '天', from: 'stars' },
  ]);
  assert.deepEqual(m.map((x) => x.ch), ['天', '地']);
  assert.deepEqual(m[0].froms, ['lesson', 'stars']);
});

test('来源标签按「错题 > 弱笔 > 课时 > 低分」排', () => {
  const d = pick.decorate(pick.merge([
    { ch: '天', from: 'stars' },
    { ch: '天', from: 'lesson' },
    { ch: '天', from: 'wrong' },
  ]));
  assert.deepEqual(d[0].froms, ['wrong', 'lesson', 'stars']);
  assert.equal(d[0].fromText, '错题 · 课时 · 低分');
});

test('空输入不炸', () => {
  assert.deepEqual(pick.merge(null), []);
  assert.deepEqual(pick.build({}).items, []);
});

test('按星档选出的字只含那一档', () => {
  const records = [
    { ch: '天', record: { stars: 1 } },
    { ch: '地', record: { stars: 3 } },
    { ch: '人', record: { stars: 1 } },
  ];
  const out = pick.fromStars(records, 1);
  assert.deepEqual(out.map((x) => x.ch), ['天', '人']);
});

test('没有笔顺的字被标成不可用，不混进可导列表', () => {
  const out = pick.build({
    lessonChars: ['天', '地'],
    available: (ch) => ch === '天',
  });
  assert.deepEqual(out.ready.map((x) => x.ch), ['天']);
  assert.deepEqual(out.missing.map((x) => x.ch), ['地']);
  assert.equal(out.readyCount, 1);
  assert.equal(out.missingCount, 1);
});

test('一个字都画不出来时给出 nothingReady', () => {
  // 界面要靠这个标志说明原因，否则用户点了导出毫无反应
  const out = pick.build({
    lessonChars: ['天', '地'],
    available: () => false,
  });
  assert.equal(out.nothingReady, true);
  assert.equal(out.ready.length, 0);
});

test('全部可导时 nothingReady 为 false', () => {
  const out = pick.build({ lessonChars: ['天'], available: () => true });
  assert.equal(out.nothingReady, false);
});

test('错题优先于课时，同时出现时错题标签在前', () => {
  const out = pick.build({
    lessonChars: ['天', '地', '人'],
    wrongChars: ['人'],
    available: () => true,
  });
  // 「人」是错题，排在前面
  assert.equal(out.items[0].ch, '人');
  assert.match(out.items[0].fromText, /错题/);
});

test('不给 available 时默认全部可用（Android/iOS 的字库是全量的）', () => {
  const out = pick.build({ lessonChars: ['天'] });
  assert.equal(out.readyCount, 1);
  assert.equal(out.missingCount, 0);
});

test('四条来源可以同时生效', () => {
  const out = pick.build({
    lessonChars: ['天', '地'],
    wrongChars: ['你'],
    weakChars: ['我'],
    records: [{ ch: '他', record: { stars: 0 } }],
    stars: 0,
    available: () => true,
  });
  const chars = out.items.map((x) => x.ch).sort();
  assert.deepEqual(chars, ['他', '你', '天', '地', '我'].sort());
  assert.equal(out.readyCount, 5);
});
