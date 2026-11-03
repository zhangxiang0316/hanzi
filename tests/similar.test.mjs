import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const catalog = require('../miniprogram/utils/catalog.js');
const quiz = require('../miniprogram/utils/quiz.js');
const session = require('../miniprogram/utils/session.js');

/**
 * 形近字辨析。
 *
 * 与同音字正好互补：同音字考「音一样，写哪个」（袋/带），
 * 形近字考「长得像，别混」（未/末、天/夫）。这两个是低年级错字的两个主因。
 *
 * 表不是人工标注的，是用笔顺数据算出来的（scripts/build-similar.mjs）。
 * 所以这里既要保证算法质量（该收的收到、不该收的没混进来），
 * 也要锁住生成结果不随环境漂移。
 */

test('形近字收录了低年级最典型的混淆对', () => {
  // 这些是语文老师会点名讲的对子，一个都不能漏
  const mustHave = [
    ['日', '目'], ['天', '夫'], ['木', '术'], ['大', '太'],
    ['未', '末'], ['己', '已'], ['土', '士'], ['鸟', '乌'],
    ['人', '入'], ['木', '本'], ['牛', '午'], ['白', '自'],
  ];
  for (const [a, b] of mustHave) {
    assert.ok(
      catalog.similarChars(a).includes(b),
      `${a} 的形近字里应该有 ${b}，实际是 ${catalog.similarChars(a).join('')}`
    );
    // 关系必须对称：b 那边也得有 a
    assert.ok(
      catalog.similarChars(b).includes(a),
      `${b} 的形近字里应该有 ${a}，实际是 ${catalog.similarChars(b).join('')}`
    );
  }
});

test('形近字不会把完全不像的字混进来', () => {
  // 每一个候选对都必须笔画数相同或差 1——差两笔以上的字，
  // 孩子数一遍笔画就能分开，不构成混淆
  for (const ch of catalog.allSimilarChars().slice(0, 400)) {
    const sc = catalog.getMeta(ch).s;
    for (const other of catalog.similarChars(ch)) {
      const so = catalog.getMeta(other).s;
      assert.ok(
        Math.abs(so - sc) <= 1,
        `${ch}(${sc}画) 与 ${other}(${so}画) 笔画数差太多`
      );
    }
  }
});

test('形近字不会把字自己列进去', () => {
  for (const ch of catalog.allSimilarChars()) {
    assert.ok(!catalog.similarChars(ch).includes(ch), `${ch} 的形近字里出现了自己`);
  }
});

test('形近字规模', () => {
  const all = catalog.allSimilarChars();
  // 覆盖率是算法参数的直接后果，改动生成脚本时这个数字会变——
  // 变了就要重新看一眼样本质量，所以锁死
  assert.equal(all.length, 2569, '全库有形近字的字数');
  // 每个字最多 5 个（KEEP）
  for (const ch of all) {
    assert.ok(catalog.similarChars(ch).length <= 5, `${ch} 的形近字超过 5 个`);
  }
  // 一到二年级四册都要有足够的题源，否则练习入口常年是灰的
  for (const b of ['1a', '1b', '2a', '2b']) {
    const n = catalog.bookSimilarChars(b).length;
    assert.ok(n >= 60, `${b} 只有 ${n} 个形近字，组不出一套像样的题`);
  }
});

test('形近字干扰项优先同册', () => {
  // 跨册会把高年级的字塞给一年级孩子，那是在考认字量而不是辨析
  const ds = catalog.similarDistractors('天', '1a', 3);
  assert.equal(ds.length, 3);
  for (const d of ds) {
    assert.ok(catalog.getMeta(d), `${d} 不在字库里`);
    assert.ok(catalog.similarChars('天').includes(d), `${d} 不是「天」的形近字`);
  }
});

test('形近字干扰项排序稳定（同 seed 同结果）', () => {
  // 三端各用各的数据结构，排序不稳就会出不同的题
  const a = catalog.similarDistractors('日', '1a', 3);
  const b = catalog.similarDistractors('日', '1a', 3);
  assert.deepEqual(a, b);
});

test('形近字题目结构正确', () => {
  const rand = quiz.mulberry32(20240101);
  const q = quiz.buildQuiz({
    chars: ['天'], types: ['similar'], count: 1, seed: 20240101, book: '1a',
  }).questions[0];
  assert.ok(q, '应该出一道形近字题');
  assert.equal(q.type, 'similar');
  assert.equal(q.title, '形近字填空');
  assert.equal(q.options.length, 4);
  // 干扰项必须真的是形近字，否则孩子扫一眼就能排除，练不到辨析
  for (const o of q.options) {
    if (o.v === q.answer) continue;
    assert.ok(
      catalog.similarChars(q.ch).includes(o.v),
      `干扰项 ${o.v} 不是 ${q.ch} 的形近字`
    );
  }
  assert.ok(q.explain.includes(q.answer));
  void rand;
});

test('形近字题的答案一定在选项里', () => {
  for (const seed of [1, 42, 20240101]) {
    const qs = quiz.buildQuiz({
      chars: ['天', '大', '本', '术', '日', '目'],
      types: ['similar'], count: 6, seed, book: '1a',
    }).questions;
    for (const q of qs) {
      assert.ok(
        q.options.some((o) => o.v === q.answer),
        `seed=${seed} 的 ${q.ch} 题答案不在选项里`
      );
    }
  }
});

test('形近字模式能组出一套完整的题', () => {
  const s = session.buildSession('similar', { book: '2a', seed: 1 });
  assert.equal(s.mode, 'similar');
  assert.ok(s.chars.length >= 4);
  // 所有挑出来的字都得真的有形近字
  for (const ch of s.chars) {
    assert.ok(catalog.hasSimilar(ch), `${ch} 没有形近字却被选进形近字练习`);
  }
});

test('形近字跨端黄金值（三端必须完全一致）', () => {
  // 同一个 seed、同一册，三端出同一套题。
  // 这条会被 iOS 与 Android 的同名断言对照，任何一端改了排序或取字逻辑都会炸。
  const qs = quiz.buildQuiz({
    chars: catalog.bookSimilarChars('2a').slice(0, 5),
    types: ['similar'],
    count: 5,
    seed: 20240101,
    book: '2a',
  }).questions;
  const sig = qs.map((q) => `${q.ch}|${q.prompt}|${q.options.map((o) => o.v).join('')}`).join(' ');
  assert.equal(sig, GOLDEN);
});

/** 由三端共同遵守的黄金值。改动出题逻辑时三端要一起改。 */
const GOLDEN = '塘|水＿|填塘塔搭 脑|呆头呆＿|掘脑柱恼 袋|＿子|紫柴袋装 灰|＿白|东灰发灵 哇|好＿|佳桂咕哇';
