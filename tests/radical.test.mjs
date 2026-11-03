import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const catalog = require('../miniprogram/utils/catalog.js');
const quiz = require('../miniprogram/utils/quiz.js');
const session = require('../miniprogram/utils/session.js');

/**
 * 部首。
 *
 * 部首查字法是二年级语文园地的正式内容，但 `meta.r` 一直只在解析文案里
 * 出现过，从没当成学习维度用过。
 *
 * 237 个部首里只有 144 个是字库里的生字（能画笔顺），另外 93 个是偏旁变形
 * （亻 艹 扌 讠 纟 宀）——所以部首只以文字形式出现，不参与描红判分。
 */

test('部首数量与分布', () => {
  const all = catalog.allRadicals();
  assert.equal(all.length, 237);
  // 按频次从高到低：口144 扌138 氵132
  assert.deepEqual(all.slice(0, 3).map((x) => x.radical), ['口', '扌', '氵']);
  assert.deepEqual(all.slice(0, 3).map((x) => x.count), [144, 138, 132]);
  // 频次单调不增
  for (let i = 1; i < all.length; i++) {
    assert.ok(all[i].count <= all[i - 1].count, '应按频次降序');
  }
});

test('每个字的部首都能取到', () => {
  let missing = 0;
  for (const ch of catalog.getAllChars()) {
    if (!catalog.radicalOf(ch)) missing++;
  }
  assert.equal(missing, 0, '所有字都应有部首');
  assert.equal(catalog.radicalOf('地'), '土');
  assert.equal(catalog.radicalOf('顶'), '页');
});

test('某册部首只用本册的字统计', () => {
  const rads = catalog.bookRadicals('2a');
  assert.ok(rads.length > 50, `2a 部首应有 50+ 个，实际 ${rads.length}`);
  // 抽查：氵 部下的字都在 2a，且部首确实是 氵
  const chars = catalog.charsWithRadical('2a', '氵');
  assert.ok(chars.length > 0);
  const bookChars = new Set(catalog.bookChars('2a'));
  for (const ch of chars) {
    assert.ok(bookChars.has(ch), `${ch} 不属于 2a`);
    assert.equal(catalog.radicalOf(ch), '氵');
  }
});

test('部首干扰项排除字形包含关系', () => {
  // 「木」的干扰项里不该有「林」「森」这类包含它的部首
  const ds = catalog.radicalDistractors('木', '2a', 3);
  assert.equal(ds.length, 3);
  for (const d of ds) {
    assert.notEqual(d, '木');
    assert.ok(d.indexOf('木') < 0 && '木'.indexOf(d) < 0, `${d} 与「木」有字形包含关系，有歧义`);
  }
});

test('部首题：答案在选项里且选项互不相同', () => {
  const chars = catalog.bookChars('2a').slice(10, 20);
  const r = quiz.buildQuiz({
    chars, book: '2a', count: 5, seed: 20240101, types: ['radical'],
  });
  assert.equal(r.questions.length, 5);

  for (const q of r.questions) {
    assert.equal(q.type, 'radical');
    assert.equal(q.options.length, 4);
    assert.ok(q.options.some((o) => o.v === q.answer));
    assert.equal(new Set(q.options.map((o) => o.v)).size, 4, '选项不能重复');
    assert.equal(q.answer, catalog.radicalOf(q.ch));
  }
});

/**
 * 回归测试：某个字出不了题时，不能卡死在它身上。
 *
 * `buildQuiz` 原来用 `questions.length` 决定取哪个字。如果某个字出不了题
 * （独体字的部首就是它自己，答案印在题干上），questions.length 不增长，
 * 就会**永远重试同一个字**，直到 guard 耗尽——整套题变成 0 道。
 *
 * 修复：改用尝试次数推进取字。
 */
test('出不了题的字不会卡死整套题', () => {
  // 龟、鼓 的部首就是它们自己，radical 题型会返回 null
  const withStall = ['龟', '顶', '鼓', '披'];
  const r = quiz.buildQuiz({
    chars: withStall, book: '2a', count: 2, seed: 1, types: ['radical'],
  });
  assert.equal(r.questions.length, 2, '应跳过独体字继续出题，而不是 0 道');
  for (const q of r.questions) {
    assert.notEqual(q.answer, q.ch, '独体字不该出部首题（答案就是题干）');
  }
});

test('独体字的部首就是它自己时不出题', () => {
  const r = quiz.buildQuiz({
    chars: ['龟', '鼓'], book: '2a', count: 2, seed: 1, types: ['radical'],
  });
  assert.equal(r.questions.length, 0, '全是独体字时出 0 道是对的');
});

test('部首会话排除独体字', () => {
  const s = session.buildSession('radical', { book: '2a' });
  assert.equal(s.mode, 'radical');
  assert.ok(s.chars.length >= 4);
  for (const ch of s.chars) {
    assert.notEqual(catalog.radicalOf(ch), ch, `${ch} 是独体字，不该进部首会话`);
  }
});

test('部首题同 seed 可复现', () => {
  const chars = catalog.bookChars('2a').slice(10, 16);
  const a = quiz.buildQuiz({ chars, book: '2a', count: 4, seed: 7, types: ['radical'] })
    .questions.map((q) => `${q.ch}:${q.answer}`);
  const b = quiz.buildQuiz({ chars, book: '2a', count: 4, seed: 7, types: ['radical'] })
    .questions.map((q) => `${q.ch}:${q.answer}`);
  assert.deepEqual(a, b);
});

/**
 * 跨端黄金值：同一 seed 三端必须出完全相同的题（含选项顺序）。
 *
 * 期望字符串由小程序实现算出；iOS `testRadicalQuizMatchesCrossPlatformGolden`
 * 和 Android `同 seed 三端出同一套部首题` 断言同样的内容。
 *
 * 麻烦都出在「顺序」上：部首频次相同时的并列、干扰项的取法，
 * 任何一处不同都会让同一 seed 出不同的题。同音字那次就是靠这条
 * 抓出了两个真实 bug。
 */
test('部首同 seed 出题锁定为跨端黄金值', () => {
  const chars = catalog.bookChars('2a').slice(10, 20);
  const r = quiz.buildQuiz({
    chars, book: '2a', count: 5, seed: 20240101, types: ['radical'],
  });
  const got = r.questions.map((q) =>
    [q.ch, q.answer, q.options.map((o) => o.v).join('|')].join('|')
  );
  assert.deepEqual(got, [
    '顶|页|扌|页|木|氵',
    '披|扌|木|扌|氵|亻',
    '晒|日|氵|日|木|扌',
    '极|木|扌|木|氵|亻',
    '傍|亻|木|扌|氵|亻',
  ]);
});
