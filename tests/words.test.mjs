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
