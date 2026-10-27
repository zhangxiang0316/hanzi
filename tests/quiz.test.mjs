import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const catalog = require('../miniprogram/utils/catalog.js');
const quiz = require('../miniprogram/utils/quiz.js');

const SAMPLE = ['天', '地', '人', '你', '我', '他', '日', '月', '水', '火', '山', '石', '田', '禾', '虫', '云'];
const TYPES = new Set(['pinyin2char', 'char2pinyin', 'fillWord', 'strokeCount', 'char2word']);

test('题目结构完整：4 个不重复选项，答案在选项中且唯一正确', () => {
  for (let seed = 1; seed <= 20; seed++) {
    const { questions } = quiz.buildQuiz({ chars: SAMPLE, book: '1a', count: 12, seed });
    assert.equal(questions.length, 12);
    for (const q of questions) {
      assert.ok(TYPES.has(q.type), '未知题型 ' + q.type);
      assert.equal(q.options.length, 4, q.type + ' 选项数不对');
      const values = q.options.map((o) => String(o.v));
      assert.equal(new Set(values).size, 4, q.type + ' 选项重复');
      assert.ok(values.includes(String(q.answer)), q.type + ' 答案不在选项中');
      assert.ok(q.explain && q.explain.length > 4, q.type + ' 缺少解析');
      assert.ok(q.prompt && String(q.prompt).length > 0, q.type + ' 缺少题干');
      assert.ok(catalog.hasChar(q.ch), q.type + ' 目标字无效');
    }
  }
});

test('看拼音选字：选项中只有目标字读这个音', () => {
  const { questions } = quiz.buildQuiz({ chars: ['天'], book: '1a', count: 1, seed: 7 });
  const q = questions[0];
  if (q.type === 'pinyin2char') {
    const same = q.options.filter((o) => catalog.readingsOf(o.v).includes(q.prompt));
    assert.equal(same.length, 1);
    assert.equal(same[0].v, q.answer);
  }
});

test('看字选拼音：选项读音互不相同且包含正确读音', () => {
  for (let seed = 1; seed <= 30; seed++) {
    const { questions } = quiz.buildQuiz({ chars: SAMPLE, book: '1a', count: 6, seed });
    for (const q of questions) {
      if (q.type !== 'char2pinyin') continue;
      const ps = q.options.map((o) => o.v);
      assert.equal(new Set(ps).size, ps.length, '读音重复');
      assert.ok(ps.includes(catalog.readingFor(q.ch, q.lesson)));
    }
  }
});

test('词语填空：答案能把词补全', () => {
  const { questions } = quiz.buildQuiz({ chars: SAMPLE, book: '1a', count: 10, seed: 3 });
  for (const q of questions) {
    if (q.type !== 'fillWord') continue;
    assert.ok(q.prompt.includes('＿'), '没有挖空');
    const filled = q.prompt.replace('＿', q.answer);
    assert.ok([...filled].length >= 2, '词语太短');
    assert.ok(filled.includes(q.ch));
  }
});

test('数笔画：答案等于真实笔画数', () => {
  const { questions } = quiz.buildQuiz({ chars: SAMPLE, book: '1a', count: 10, seed: 11 });
  for (const q of questions) {
    if (q.type !== 'strokeCount') continue;
    assert.equal(q.answer, catalog.getMeta(q.ch).s);
    assert.ok(q.options.every((o) => typeof o.v === 'number' && o.v > 0 && o.v < 40));
  }
});

test('相同 seed 结果可复现', () => {
  const a = quiz.buildQuiz({ chars: SAMPLE, book: '1a', count: 8, seed: 42 });
  const b = quiz.buildQuiz({ chars: SAMPLE, book: '1a', count: 8, seed: 42 });
  assert.deepEqual(
    a.questions.map((q) => [q.type, q.ch, q.answer, q.options.map((o) => o.v)]),
    b.questions.map((q) => [q.type, q.ch, q.answer, q.options.map((o) => o.v)])
  );
});

test('目标字会全部覆盖到', () => {
  const chars = SAMPLE.slice(0, 8);
  const { questions } = quiz.buildQuiz({ chars, book: '1a', count: 8, seed: 5 });
  const used = new Set(questions.map((q) => q.ch));
  for (const ch of chars) assert.ok(used.has(ch), ch + ' 没有被考到');
});

test('干扰项来自同一册，难度可控', () => {
  const pool = new Set(catalog.bookChars('1a'));
  let checked = 0;
  for (let seed = 1; seed <= 10; seed++) {
    const { questions } = quiz.buildQuiz({ chars: SAMPLE, book: '1a', count: 8, seed });
    for (const q of questions) {
      if (q.type !== 'pinyin2char' && q.type !== 'fillWord') continue;
      for (const o of q.options) {
        if (o.v === q.answer) continue;
        assert.ok(pool.has(o.v), o.v + ' 不在本册字表中');
        checked++;
      }
    }
  }
  assert.ok(checked > 20);
});

test('空输入不会崩溃', () => {
  const { questions } = quiz.buildQuiz({ chars: [], count: 5, seed: 1 });
  assert.equal(questions.length, 0);
});
