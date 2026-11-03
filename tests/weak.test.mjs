import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const progress = require('../miniprogram/utils/progress.js');

/**
 * 笔画薄弱点。
 *
 * 描红判分本来就每笔都会算出「为什么不过」（起笔错 / 偏离 / 写短了），
 * 但之前只用它拼一句即时提示就丢掉了。留下来才看得出
 * 「这个字的第 2 笔你反复写不好」——比整字分数具体，也更能指导练什么。
 *
 * 判分阈值（`ACCEPT = 42`）和两档门槛（失败 ≥2 次、失败率 ≥40%）
 * 都是「别让正常的不稳被当成薄弱」的折中，测试把这几个数字锁住。
 */

test.beforeEach(() => {
  progress.resetAll();
});

test('失败 2 次以上才算薄弱笔画', () => {
  // 只错一次是很正常的——手抖、第一次不熟，不能算薄弱点
  progress.recordStroke('日', 1, false);
  assert.deepEqual(progress.weakStrokesOf('日'), []);

  progress.recordStroke('日', 1, false);
  const w = progress.weakStrokesOf('日');
  assert.equal(w.length, 1);
  assert.equal(w[0].index, 1);
  assert.equal(w[0].fails, 2);
  assert.equal(w[0].tries, 2);
});

test('记录里尝试次数不超过 2×失败+1（不变量）', () => {
  // 「连对两次即移除」的直接推论：还在册的记录里不可能夹着两次连续成功，
  // 所以 t ≤ 2f+1 恒成立。这也是「失败率 ≥40%」那条门槛显得多余的原因。
  const seq = [
    false, true, false, false, true, false, true, false,
    false, true, true, false, false,
  ];
  for (const pass of seq) progress.recordStroke('天', 0, pass);
  for (const w of progress.allWeakStrokes()) {
    assert.ok(w.tries <= 2 * w.fails + 1,
              `t=${w.tries} 超过了 2f+1=${2 * w.fails + 1}`);
  }
});

test('连续写对两次才算练好', () => {
  progress.recordStroke('日', 1, false);
  progress.recordStroke('日', 1, false);
  assert.equal(progress.weakStrokesOf('日').length, 1);

  // 写对一次不清：手抖蒙对一次不该前功尽弃，
  // 而且清了之后 tries 永远等于 fails，40% 那条门槛就没数据可判
  progress.recordStroke('日', 1, true);
  assert.equal(progress.weakStrokesOf('日').length, 1);

  progress.recordStroke('日', 1, true);
  assert.deepEqual(progress.weakStrokesOf('日'), [], '连对两次应该移除');
});

test('蒙对一次又写错，连胜归零', () => {
  progress.recordStroke('天', 0, false);
  progress.recordStroke('天', 0, false);
  progress.recordStroke('天', 0, true);   // 蒙对
  progress.recordStroke('天', 0, false);  // 又错
  assert.equal(progress.weakStrokesOf('天').length, 1);
  // 连胜清零后要重新连对两次
  progress.recordStroke('天', 0, true);
  assert.equal(progress.weakStrokesOf('天').length, 1);
  progress.recordStroke('天', 0, true);
  assert.deepEqual(progress.weakStrokesOf('天'), []);
});

test('clearWeakStroke 手动清掉某一笔', () => {
  progress.recordStroke('日', 1, false);
  progress.recordStroke('日', 1, false);
  progress.clearWeakStroke('日', 1);
  assert.deepEqual(progress.weakStrokesOf('日'), []);
});

test('清掉某一笔不影响同一字的其他笔画', () => {
  progress.recordStroke('日', 1, false);
  progress.recordStroke('日', 1, false);
  progress.recordStroke('日', 3, false);
  progress.recordStroke('日', 3, false);
  assert.equal(progress.weakStrokesOf('日').length, 2);
  progress.clearWeakStroke('日', 1);
  const left = progress.weakStrokesOf('日');
  assert.equal(left.length, 1);
  assert.equal(left[0].index, 3);
});

test('薄弱笔画按笔画序号升序（读起来跟笔顺一致）', () => {
  for (const i of [5, 1, 3]) {
    progress.recordStroke('罐', i, false);
    progress.recordStroke('罐', i, false);
  }
  assert.deepEqual(progress.weakStrokesOf('罐').map((w) => w.index), [1, 3, 5]);
});

test('全部薄弱点按失败次数降序', () => {
  progress.recordStroke('日', 0, false);
  progress.recordStroke('日', 0, false);
  for (let i = 0; i < 4; i++) progress.recordStroke('天', 2, false);
  const all = progress.allWeakStrokes();
  assert.equal(all.length, 2);
  assert.equal(all[0].ch, '天', '错得多的应该排前面');
  assert.equal(all[0].fails, 4);
  assert.equal(all[1].ch, '日');
});

test('失败次数相同的按码点 + 笔画序号排（三端一致）', () => {
  // Swift 的 sort 不保证稳定，没有确定的 tiebreak 三端顺序会不一致
  progress.recordStroke('天', 1, false);
  progress.recordStroke('天', 1, false);
  progress.recordStroke('日', 2, false);
  progress.recordStroke('日', 2, false);
  const all = progress.allWeakStrokes();
  assert.deepEqual(all.map((w) => w.ch), ['天', '日']);
  // 「天」U+5929 < 「日」U+65E5
});

test('同一字多个薄弱笔画时，练习列表里只出现一次', () => {
  // 一个字的笔画都在同一份描红里练，按笔画列出会重复练同一个字
  progress.recordStroke('日', 1, false);
  progress.recordStroke('日', 1, false);
  progress.recordStroke('日', 3, false);
  progress.recordStroke('日', 3, false);
  const chars = progress.weakChars();
  assert.equal(chars.length, 1);
  assert.equal(chars[0].ch, '日');
  assert.equal(chars[0].count, 2, '应该记下这个字有几处薄弱');
  assert.equal(chars[0].worst, 1, '最弱的那一笔排在前面');
});

test('没有写过的字没有薄弱点', () => {
  assert.deepEqual(progress.weakStrokesOf('字'), []);
  assert.equal(progress.hasWeakStrokes('字'), false);
  assert.deepEqual(progress.allWeakStrokes(), []);
  assert.deepEqual(progress.weakChars(), []);
});

test('清空学习记录会一起清掉薄弱点', () => {
  progress.recordStroke('日', 1, false);
  progress.recordStroke('日', 1, false);
  assert.equal(progress.allWeakStrokes().length, 1);
  progress.resetAll();
  assert.equal(progress.allWeakStrokes().length, 0, '重置后不该残留薄弱点');
});

test('clearWeak 整个字清掉', () => {
  progress.recordStroke('日', 1, false);
  progress.recordStroke('日', 1, false);
  progress.recordStroke('日', 3, false);
  progress.recordStroke('日', 3, false);
  progress.clearWeak('日');
  assert.deepEqual(progress.weakStrokesOf('日'), []);
});
