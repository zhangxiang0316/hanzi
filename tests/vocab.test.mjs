import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const vocab = require('../miniprogram/utils/vocab.js');
const catalog = require('../miniprogram/utils/catalog.js');
const progress = require('../miniprogram/utils/progress.js');

/**
 * 识字量测试。
 *
 * 家长最想知道的一个数字是「我家孩子认识多少字」。原来的 app 只能回答
 * 「学过多少字」——那是点过多少个字，不是认识多少。
 *
 * 抽测的关键是**抽样要覆盖整册**，不能只考最基础的几个字，
 * 否则估出来的数会虚高。以及估算必须是可复现的纯函数。
 */

test('每册抽 5 个字，八册共 40 题', () => {
  const t = vocab.buildTest({ seed: 20240101 });
  assert.equal(vocab.PER_BOOK, 5);
  assert.equal(t.groups.length, 8);
  assert.equal(t.total, 40);
  for (const g of t.groups) {
    assert.equal(g.questions.length, 5, `${g.book} 应该抽 5 个`);
  }
});

test('抽出来的字都有拼音，且在本册内', () => {
  const t = vocab.buildTest({ seed: 42 });
  for (const g of t.groups) {
    const inBook = new Set(catalog.bookChars(g.book));
    for (const q of g.questions) {
      assert.ok(inBook.has(q.ch), `${q.ch} 不属于 ${g.book}`);
      const py = catalog.getMeta(q.ch).py;
      assert.ok(py && py.length > 1, `${q.ch} 没有拼音`);
      assert.equal(q.answer, py);
    }
  }
});

test('抽样覆盖整册，不是只取前几个字', () => {
  // 只取前 5 个等于只考「日月水火」这种最基础的字，估出来的数会虚高
  const t = vocab.buildTest({ seed: 7 });
  for (const g of t.groups) {
    const all = catalog.bookChars(g.book);
    const idx = g.questions.map((q) => all.indexOf(q.ch));
    assert.ok(Math.max(...idx) > all.length * 0.5,
              `${g.book} 的抽样都落在前一半（最大下标 ${Math.max(...idx)}/${all.length}）`);
  }
});

test('每次抽样的字不同（不会把答案背下来）', () => {
  const a = vocab.buildTest({ seed: 1 });
  const b = vocab.buildTest({ seed: 2 });
  const sa = a.groups.map((g) => g.questions.map((q) => q.ch).join('')).join('');
  const sb = b.groups.map((g) => g.questions.map((q) => q.ch).join('')).join('');
  assert.notEqual(sa, sb);
});

test('抽样结果锁定黄金值（三端必须一致）', () => {
  // 三端各自实现了一份抽样+RNG，只测「同 seed 可复现」不够——
  // 那样即使某一端的 mulberry32 写错了也能通过。这里锁死实际输出的字。
  const t = vocab.buildTest({ seed: 1 });
  const got = t.groups.map((g) => g.questions.map((q) => q.ch).join('')).join('|');
  assert.equal(got, '八南众到旁|万单食呢奇|舰锅留福折|蒙易坦件由|橘吞阁库瓦|释智痒警呕|震兰返怖签|冠践稿絮遣');
});

test('同一个 seed 出同一套题', () => {
  const a = vocab.buildTest({ seed: 99 });
  const b = vocab.buildTest({ seed: 99 });
  const sa = a.groups.map((g) => g.questions.map((q) => q.ch + q.options.map((o) => o.v).join('')).join('')).join('|');
  const sb = b.groups.map((g) => g.questions.map((q) => q.ch + q.options.map((o) => o.v).join('')).join('')).join('|');
  assert.equal(sa, sb);
});

test('每题 4 个选项，答案在其中，干扰项读音各不相同', () => {
  const t = vocab.buildTest({ seed: 20240101 });
  for (const g of t.groups) {
    for (const q of g.questions) {
      assert.equal(q.options.length, 4);
      assert.ok(q.options.some((o) => o.v === q.answer));
      const set = new Set(q.options.map((o) => o.v));
      assert.equal(set.size, 4, `${q.ch} 的选项有重复读音`);
    }
  }
});

test('多音字的其他读音不会当干扰项（会变成有两个正确答案）', () => {
  const t = vocab.buildTest({ seed: 5 });
  for (const g of t.groups) {
    for (const q of g.questions) {
      const all = catalog.readingsOf(q.ch);
      for (const o of q.options) {
        if (o.v === q.answer) continue;
        assert.ok(!all.includes(o.v), `${q.ch} 的干扰项 ${o.v} 也是它的读音`);
      }
    }
  }
});

test('全对时估算等于字库总量（不超过去重后的字数）', () => {
  const t = vocab.buildTest({ seed: 1 });
  const all = new Array(t.total).fill({ correct: true });
  const e = vocab.estimate(t, all);
  assert.equal(e.size, catalog.getAllChars().length);
  assert.equal(e.level, '4b');
  assert.equal(e.done, true);
});

test('全错时估算为 0，且第一册就停下', () => {
  const t = vocab.buildTest({ seed: 1 });
  const none = new Array(t.total).fill({ correct: false });
  const e = vocab.estimate(t, none);
  assert.equal(e.size, 0);
  assert.equal(e.stopBook, '1a');
  assert.equal(e.answered, 5, '第一册问完就该停');
});

test('只认识第一册时，停在第二册，估算约等于第一册字数', () => {
  const t = vocab.buildTest({ seed: 1 });
  const answers = [];
  t.groups.forEach((g) => {
    g.questions.forEach(() => answers.push({ correct: g.book === '1a' }));
  });
  const e = vocab.estimate(t, answers);
  assert.equal(e.stopBook, '1b');
  // 1a 满分 → 300 字左右（1a 实际有 300 个生字）
  assert.ok(e.size > 250 && e.size <= 300, `估算 ${e.size} 不合理`);
  assert.equal(e.level, '1a');
});

test('停在某册后，后面的册次一律不计', () => {
  // 停下的册次之后是还没学到的部分，按更低比例折算会把估算压成没意义的数
  const t = vocab.buildTest({ seed: 3 });
  const answers = [];
  t.groups.forEach((g) => {
    g.questions.forEach(() => answers.push({ correct: false }));
  });
  const e = vocab.estimate(t, answers);
  const after = e.groups.filter((g) => g.book !== '1a');
  for (const g of after) {
    assert.equal(g.counted, false, `${g.book} 不该被计入`);
    assert.equal(g.contribution, 0);
  }
});

test('答题进行中：没问到的册次不计', () => {
  const t = vocab.buildTest({ seed: 8 });
  // 只答了 7 题（1a 全对 + 1b 前两题）
  const answers = new Array(7).fill({ correct: true });
  const e = vocab.estimate(t, answers);
  assert.equal(e.done, false);
  assert.equal(e.answered, 7);
  const g2a = e.groups.find((g) => g.book === '2a');
  assert.equal(g2a.asked, 0);
  assert.equal(g2a.contribution, 0);
});

test('估算值随答对比例线性变化', () => {
  const t = vocab.buildTest({ seed: 4 });
  // 每册都对一半以上，保证不会提前停
  const half = [];
  t.groups.forEach((g) => {
    g.questions.forEach((_, i) => half.push({ correct: i < 3 }));
  });
  const e = vocab.estimate(t, half);
  assert.equal(e.stopBook, '', '六成不该提前停');
  // 每册 60% × 该册字数，累计后应该在总量的一半上下
  const total = catalog.getAllChars().length;
  assert.ok(e.size > total * 0.5 && e.size < total * 0.75,
            `六成正确率估出 ${e.size}/${total}，不合理`);
});

test('sizeLabel 报「约」到百位，不假装精确', () => {
  assert.equal(vocab.sizeLabel(0), '0');
  assert.equal(vocab.sizeLabel(45), '45');
  assert.equal(vocab.sizeLabel(712), '约 700');
  assert.equal(vocab.sizeLabel(760), '约 800');
  assert.equal(vocab.sizeLabel(2596), '约 2600');
});

test('verdict 分档：数字越大档位越高', () => {
  const marks = [200, 600, 1200, 2000, 2596];
  const texts = marks.map((n) => vocab.verdict(n));
  for (let i = 1; i < marks.length; i++) {
    assert.notEqual(texts[i], texts[i - 1], `${marks[i]} 和 ${marks[i - 1]} 的评价一样`);
  }
  // 不足 100 字统一算「刚开始」——0 字和 50 字对家长没有区分意义
  assert.equal(vocab.verdict(0), vocab.verdict(50));
  assert.ok(vocab.verdict(50).includes('刚'));
  assert.ok(vocab.verdict(2596).includes('章节书'));
});

test('识字量会存进设置，重启后还在', () => {
  progress.resetAll();
  assert.equal(progress.getVocabSize(), 0);
  progress.setVocabSize(712);
  assert.equal(progress.getVocabSize(), 712);
  // 0 不覆盖已有结果
  progress.setVocabSize(0);
  assert.equal(progress.getVocabSize(), 712);
  progress.resetAll();
});

test('识字量按档案隔离', () => {
  const profile = require('../miniprogram/utils/profile.js');
  const store = require('../miniprogram/utils/store.js');
  store.clearAll();
  profile._reset();
  progress.reload();
  progress.setVocabSize(800);

  const p = profile.add('弟弟');
  profile.setActive(p.id);
  progress.reload();
  assert.equal(progress.getVocabSize(), 0, '弟弟不该看到哥哥的测试结果');

  profile.setActive('');
  progress.reload();
  assert.equal(progress.getVocabSize(), 800);
  progress.resetAll();
});
