import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const catalog = require('../miniprogram/utils/catalog.js');
const words = require('../miniprogram/utils/words.js');
const quiz = require('../miniprogram/utils/quiz.js');

/**
 * 课文词语表。
 *
 * `catalog.lessons[*].words` 里有 1276 条课本词语，之前三端一次都没读过
 * （已有的「词语填空」用的是每个字自带的组词 `meta.w`，那是通用例子）。
 */

test('课本词语表共 1276 条，只在 2-4 年级', () => {
  const cat = catalog.catalog;
  const ids = Object.keys(cat.lessons);
  let total = 0;
  const booksWithWords = new Set();
  ids.forEach((id) => {
    const l = cat.lessons[id];
    if (l.words && l.words.length) {
      total += l.words.length;
      booksWithWords.add(l.book);
    }
  });
  assert.equal(total, 1276);
  // 一年级课本没有单独的词语表，识字量还在积累——这是数据事实，不是缺失
  assert.deepEqual([...booksWithWords].sort(), ['2a', '2b', '3a', '3b', '4a', '4b']);
});

test('有词语表的课时直接用课本数据', () => {
  const list = words.lessonWords('2a-k1');
  assert.ok(list.length > 0);
  assert.equal(list[0].from, 'textbook');
  // 都带拼音，且拼音非空
  for (const w of list) {
    assert.ok(w.py && w.py.length > 0, `${w.word} 缺拼音`);
  }
});

test('一年级没有词语表时用生字组词兜底', () => {
  const list = words.lessonWords('1a-s1');
  assert.ok(list.length > 0, '一年级也应有词可练');
  assert.equal(list[0].from, 'derived');
  // 兜底出来的词必须包含本课某个生字
  const lesson = catalog.getLesson('1a-s1');
  for (const w of list) {
    assert.ok(
      w.word.split('').some((ch) => lesson.chars.includes(ch)),
      `${w.word} 不含本课生字`
    );
  }
});

test('整册词语去重且数量合理', () => {
  for (const b of ['1a', '2a', '3b']) {
    const list = words.bookWords(b);
    assert.ok(list.length >= 100, `${b} 词语太少`);
    const set = new Set(list.map((w) => w.word));
    assert.equal(set.size, list.length, `${b} 词语有重复`);
  }
});

test('看拼音选词语：四个选项、答案在其中、拼音不重复', () => {
  const r = quiz.buildWordQuiz({ book: '2a', count: 8, seed: 12345 });
  assert.equal(r.questions.length, 8);
  const pinyins = new Set();
  for (const q of r.questions) {
    assert.equal(q.type, 'wordPinyin');
    assert.equal(q.options.length, 4, '每题应有 4 个选项');
    assert.ok(q.options.some((o) => o.v === q.answer), '答案必须在选项里');
    assert.ok(q.prompt.length > 0, '题面（拼音）不能为空');
    // 同一轮里题面不能重复，否则结果页会看到两道一样的题
    assert.ok(!pinyins.has(q.prompt), `重复题面：${q.prompt}`);
    pinyins.add(q.prompt);
    // 干扰项不能和正确答案同音，否则这题无解
    for (const o of q.options) {
      if (o.v === q.answer) continue;
      assert.notEqual(o.v, q.answer);
    }
  }
});

test('看拼音选词语：同一 seed 出同一套题', () => {
  const a = quiz.buildWordQuiz({ book: '2a', count: 6, seed: 7 }).questions.map((q) => q.answer);
  const b = quiz.buildWordQuiz({ book: '2a', count: 6, seed: 7 }).questions.map((q) => q.answer);
  assert.deepEqual(a, b);
});

test('看拼音选词语：词太少的册也能安全返回', () => {
  // 不存在的册 → 空结果，不能崩
  const r = quiz.buildWordQuiz({ book: 'zz', count: 10, seed: 1 });
  assert.deepEqual(r.questions, []);
});

test('词语答错要能拆成单字进错题本', () => {
  // 错题本、错字重练都按单字组织，整词塞进去会让结果页 getMeta 拿到 null
  const r = quiz.buildWordQuiz({ book: '2a', count: 8, seed: 42 });
  for (const q of r.questions) {
    const parts = q.ch.length > 1 ? q.ch.split('') : [q.ch];
    const valid = parts.filter((ch) => catalog.hasChar(ch));
    assert.ok(valid.length > 0, `${q.ch} 拆不出任何可学字`);
    // 结果页会对每个错字做 getMeta，必须都取得到
    valid.forEach((ch) => assert.ok(catalog.getMeta(ch), `${ch} 缺元数据`));
  }
});

/**
 * 跨端黄金值：同一 seed 三端必须出完全相同的题（含选项顺序）。
 *
 * 这份期望值是基准——iOS `testWordQuizMatchesCrossPlatformGolden` 和
 * Android `同 seed 三端出同一套词语题` 都断言同样的字符串。
 * 任何一端改了随机数调用顺序、干扰项挑选或洗牌方式，三处会同时红。
 */
test('同 seed 的出题结果锁定为跨端黄金值', () => {
  const r = quiz.buildWordQuiz({ book: '2a', count: 5, seed: 20240101 });
  const got = r.questions.map((q) =>
    [q.ch, q.prompt, q.answer, q.options.map((o) => o.v).join('|')].join('|')
  );
  assert.deepEqual(got, [
    '卧室|wò shì|卧室|邻居|秧苗|卧室|蚯蚓',
    '那些|nà xiē|那些|那些|和好|看见|回家',
    '展开|zhǎn kāi|展开|头顶|展开|电影|井口',
    '白蛇|bái shé|白蛇|爱慕|时辰|花朵|白蛇',
    '船身|chuán shēn|船身|展开|井沿|船身|时间',
  ]);
});

// ---------------------------------------------------------------------------
// 词语表浏览
//
// 词语此前只在「看拼音选词语」的题目和课时页里露过脸，
// 没有任何地方能从头翻一遍。
// ---------------------------------------------------------------------------

test('全库词语按册拼接，8 册都有（一年级靠派生词兜底）', () => {
  const all = words.allWords();
  assert.ok(all.length > 2400, `词语太少：${all.length}`);
  const books = new Set(all.map((w) => w.book));
  ['1a', '1b', '2a', '2b', '3a', '3b', '4a', '4b'].forEach((b) => {
    assert.ok(books.has(b), `${b} 应该有词语`);
  });
});

test('一年级全是生字组词兜底，中高年级是课本词与派生词混着', () => {
  // 不是 bug，是数据事实：一年级课本没有词语表，用每课生字的第一组词补。
  // 而且**一册里可能混合**——2a 有的课文有词语表、有的没有，
  // 所以页面上不能只看 every 就下"这册没有词语表"的结论。
  const g1 = words.bookWords('1a');
  assert.ok(g1.length > 0, '一年级也要有词可看');
  assert.ok(g1.every((w) => w.from === 'derived'), '一年级应该全是派生词');

  const g2 = words.bookWords('2a');
  assert.ok(g2.some((w) => w.from === 'textbook'), '2a 应该有真课本词');
  assert.ok(g2.some((w) => w.from === 'derived'), '2a 也有派生词——混合册');
});

test('全库去重后少于按册拼接的条目数', () => {
  // 「旅行」在 3a 和 3b 各出一次是教材事实，分组浏览该各显示一次；
  // 但统计"有多少个词"必须全局去重
  const dup = words.allWords().length;
  const uniq = words.uniqueWords().length;
  assert.ok(uniq < dup, `去重后 ${uniq} 应该少于 ${dup}`);
  const seen = new Set();
  words.uniqueWords().forEach((w) => {
    assert.ok(!seen.has(w.word), `重复的词：${w.word}`);
    seen.add(w.word);
  });
});

test('跨册重复的词记下所有册次', () => {
  const travel = words.uniqueWords().find((w) => w.word === '旅行');
  assert.ok(travel, '应该有「旅行」');
  assert.ok(travel.books.length >= 2, `「旅行」应跨册，实际 ${travel.books.join('/')}`);
});

test('按字搜词能搜到跨册的词，且不重复', () => {
  const found = words.wordsWithChar('行');
  assert.ok(found.length >= 3, `含「行」的词太少：${found.length}`);
  assert.ok(found.every((w) => w.word.indexOf('行') >= 0));
  const names = found.map((w) => w.word);
  assert.equal(new Set(names).size, names.length, '搜索结果不能有重复的词');
});

test('搜不存在的字返回空数组而不是报错', () => {
  assert.deepEqual(words.wordsWithChar(''), []);
  assert.deepEqual(words.wordsWithChar('龘'), []);
});

test('每个词都有拼音', () => {
  const bad = words.uniqueWords().filter((w) => !w.py);
  assert.equal(bad.length, 0,
    `这些词缺拼音：${bad.slice(0, 5).map((w) => w.word).join(' ')}`);
});

test('派生词里有少数含字库外的字，页面要认得出（不然点了没反应）', () => {
  // 派生词取自每个字的组词，那些组词可能用到 2596 字之外的常用字
  // （「弓弩」的弩、「镜匣」的匣）。这类字点不进详情页，
  // 页面必须靠 catalog.hasChar 把它们置灰，而不是让用户点了以为卡住。
  const derived = words.uniqueWords().filter((w) => w.from === 'derived');
  const withOutsider = derived.filter((w) =>
    Array.from(w.word).some((c) => !catalog.hasChar(c)));

  assert.ok(withOutsider.length > 0, '数据里确实有这类词，断言要贴着现实');
  // 比例不该高到离谱：绝大多数派生词都该是可点的
  const ratio = withOutsider.length / derived.length;
  assert.ok(ratio < 0.05, `含字库外字的派生词占比 ${(ratio * 100).toFixed(1)}% 太高了`);

  // 每个这样的词，至少有一个字能点，不至于整条都没得点
  withOutsider.forEach((w) => {
    const tappable = Array.from(w.word).filter((c) => catalog.hasChar(c));
    assert.ok(tappable.length > 0, `「${w.word}」一个字都点不了`);
  });
});
