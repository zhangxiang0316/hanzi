import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const catalog = require('../miniprogram/utils/catalog.js');
const quiz = require('../miniprogram/utils/quiz.js');
const session = require('../miniprogram/utils/session.js');

/**
 * 同音字辨析。
 *
 * 同音字是听写最主要的错因：「地弟第递」读音一样、字形不同，
 * 记住音不等于会写。数据不用新增——`meta.py` 按读音分组就能得到。
 *
 * 与多音字互补：多音字练「一个字有几个音」，同音字练「一个音有几个字」。
 */

test('同音字按完整拼音（含声调）分组', () => {
  assert.deepEqual(catalog.homophones('地').sort(), ['弟', '第', '帝', '递'].sort());
  assert.ok(catalog.homophones('天').includes('添'));
  // 声调不同不算同音：「地」是 dì，「底」是 dǐ
  assert.ok(!catalog.homophones('地').includes('底'));
  // 没有同音字的字返回空
  assert.equal(catalog.homophones('天').includes('天'), false);
});

test('全库同音字组规模与分布', () => {
  // 按册分组后累加：同一组字若跨册出现会各算一次，
  // 所以这个数字大于「全库去重后的组数」。两个数都有意义：
  // 前者是各册练习的题源总量，后者是全库的同音关系数。
  const groups = catalog.allHomophoneGroups();
  assert.equal(groups.length, 382, '八册累加的同音字组数');

  // 全库去重（按 meta 的完整拼音分组）
  const byPy = new Map();
  for (const ch of catalog.getAllChars()) {
    const py = catalog.getMeta(ch).py;
    if (!byPy.has(py)) byPy.set(py, []);
    byPy.get(py).push(ch);
  }
  const globalGroups = [...byPy.values()].filter((l) => l.length >= 2);
  assert.equal(globalGroups.length, 588, '全库同音字组数');
  // 每组至少 2 个字，且组内读音一致
  for (const g of groups.slice(0, 200)) {
    assert.ok(g.chars.length >= 2);
    for (const ch of g.chars) {
      assert.equal(catalog.getMeta(ch).py, g.py, `${ch} 的读音与组不一致`);
    }
  }
});

test('某册的同音字组只用本册的字', () => {
  const groups = catalog.homophoneGroups('2a');
  assert.ok(groups.length > 30, `2a 同音字组应超过 30，实际 ${groups.length}`);
  const bookChars = new Set(catalog.bookChars('2a'));
  for (const g of groups) {
    for (const ch of g.chars) {
      assert.ok(bookChars.has(ch), `${ch} 不属于 2a，不该出现在本册分组里`);
    }
  }
});

test('干扰项必须同音且笔画接近', () => {
  const ds = catalog.homophoneDistractors('坐', '2a', 3);
  assert.equal(ds.length, 3);
  const py = catalog.getMeta('坐').py;
  for (const d of ds) {
    assert.equal(catalog.getMeta(d).py, py, `${d} 不和「坐」同音，当干扰项等于送分`);
    assert.notEqual(d, '坐');
  }
});

test('同音字题：选项全部同音，答案在其中', () => {
  const chars = catalog.homophoneChars('2a').slice(0, 6);
  const r = quiz.buildQuiz({
    chars, book: '2a', count: 6, seed: 20240101, types: ['homophone'],
  });
  assert.ok(r.questions.length >= 4, `应出至少 4 题，实际 ${r.questions.length}`);

  for (const q of r.questions) {
    assert.equal(q.type, 'homophone');
    assert.equal(q.options.length, 4);
    assert.ok(q.options.some((o) => o.v === q.answer), '答案必须在选项里');
    // 核心断言：每个干扰项都必须和答案同音，否则这道题就白出了
    const py = catalog.getMeta(q.answer).py;
    for (const o of q.options) {
      assert.equal(catalog.getMeta(o.v).py, py, `${o.v} 与 ${q.answer} 不同音`);
    }
    // 题面必须真的挖了空
    assert.ok(q.prompt.includes('＿'), '题面应有空格');
  }
});

test('没有同音伙伴的字不出同音字题', () => {
  // 找一个孤立的字（无同音字）
  const lonely = catalog.getAllChars().find((ch) => !catalog.hasHomophones(ch));
  assert.ok(lonely, '应存在没有同音字的字');
  const r = quiz.buildQuiz({
    chars: [lonely], book: '2a', count: 3, seed: 1, types: ['homophone'],
  });
  assert.equal(r.questions.length, 0, `${lonely} 没有同音字，不该出题`);
});

test('同音字会话能用本册组题', () => {
  const s = session.buildSession('homophone', { book: '2a' });
  assert.equal(s.mode, 'homophone');
  assert.ok(s.chars.length >= 4);
  assert.ok(s.count >= 4);
  // 会话里的字必须都有同音伙伴，否则会出空题
  for (const ch of s.chars) {
    assert.ok(catalog.hasHomophones(ch), `${ch} 没有同音字，不该进会话`);
  }
});

test('同音字题同 seed 可复现', () => {
  const chars = catalog.homophoneChars('2a').slice(0, 5);
  const a = quiz.buildQuiz({ chars, book: '2a', count: 5, seed: 7, types: ['homophone'] })
    .questions.map((q) => q.answer);
  const b = quiz.buildQuiz({ chars, book: '2a', count: 5, seed: 7, types: ['homophone'] })
    .questions.map((q) => q.answer);
  assert.deepEqual(a, b);
});

/**
 * 跨端黄金值：同一 seed 三端必须出完全相同的题（含选项顺序）。
 *
 * 期望字符串由小程序实现算出；iOS `testHomophoneQuizMatchesCrossPlatformGolden`
 * 和 Android `同 seed 三端出同一套同音字题` 断言同样的内容。
 *
 * 光有 RNG 黄金值（mulberry32）不够——它只证明随机数发生器一致，
 * 不证明**调用顺序**一致。干扰项怎么挑、洗牌几轮，任何一处不同都会
 * 让同一 seed 出不同的题。
 */
test('同音字同 seed 出题锁定为跨端黄金值', () => {
  const chars = catalog.homophoneChars('2a').slice(0, 5);
  const r = quiz.buildQuiz({
    chars, book: '2a', count: 5, seed: 20240101, types: ['homophone'],
  });
  const got = r.questions.map((q) =>
    [q.ch, q.prompt, q.answer, q.options.map((o) => o.v).join('|')].join('|')
  );
  assert.deepEqual(got, [
            "袋|口＿|袋|带|袋|戴|代",
            "龟|＿甲|龟|瑰|龟|归|规",
            "鼓|重整旗＿|鼓|骨|谷|鼓|股",
            "极|＿大|极|即|极|吉|及",
            "溪|＿水|溪|吸|希|锡|溪"
  ]);
});
