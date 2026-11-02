import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const catalog = require('../miniprogram/utils/catalog.js');
const dictation = require('../miniprogram/utils/dictation.js');

/**
 * 听写 / 默写。
 *
 * **小程序端做不了真正的听写**：微信小程序没有系统 TTS API，本项目也是纯前端。
 * 所以这里把「听词写」换成「看词写」——听觉输入换成视觉输入，
 * 难度上仍比描红高一档（没有底字）。App 端有系统 TTS，是真正的听写。
 *
 * 这些断言与 iOS `Dictation` 测试、Android `DictationTest` 语义对应。
 */

test('这一端没有语音能力，必须如实标注', () => {
  // 不是「暂时没有」，是平台的硬限制。写死成 false 是为了让调用方
  // 不要误以为有 TTS 而拿空音频去播。
  assert.equal(dictation.SUPPORTS_AUDIO, false);
});

test('三档难度的底字与题面', () => {
  const easy = dictation.levelOf('easy');
  const normal = dictation.levelOf('normal');
  const hard = dictation.levelOf('hard');

  assert.equal(easy.showsGhost, true);
  assert.equal(normal.showsGhost, false);
  assert.equal(hard.showsGhost, false);

  // normal 一直显示题面；hard 显示一会儿就藏（逼孩子凭记忆写）
  assert.equal(easy.peekMs, 0);
  assert.equal(normal.peekMs, 0);
  assert.ok(hard.peekMs > 0, 'hard 档应该限时显示题面');

  assert.equal(dictation.promptText('easy', '天', '天空'), '天空');
  assert.equal(dictation.promptText('normal', '天', '天空'), '天空');
  // hard 只给这一个字
  assert.equal(dictation.promptText('hard', '天', '天空'), '天');
  // 没有组词时退回给字，不能给空字符串
  assert.equal(dictation.promptText('normal', '天', null), '天');
});

test('未知难度退回默认档，不崩', () => {
  assert.equal(dictation.levelOf('whatever').key, 'normal');
  assert.equal(dictation.levelOf(undefined).key, 'normal');
});

test('听写只挑会写的字', () => {
  const items = dictation.pick('1a', 'normal', 8);
  assert.equal(items.length, 8);
  for (const it of items) {
    // 只认不写的字（髓、嚼、蟹）要求孩子默写出来没有道理
    assert.ok(catalog.isWriteChar(it.ch), `${it.ch} 是只认不写的字，不该进听写`);
  }
});

test('hard 档不给词语', () => {
  const items = dictation.pick('1a', 'hard', 5);
  for (const it of items) {
    assert.equal(it.word, null, 'hard 档不该给词语，否则等于告诉孩子答案');
  }
  const normal = dictation.pick('1a', 'normal', 5);
  assert.ok(normal.some((it) => it.word), 'normal 档应该给词语');
});

test('按教材顺序取字而不是随机', () => {
  const a = dictation.pick('1a', 'normal', 5).map((i) => i.ch);
  const b = dictation.pick('1a', 'normal', 5).map((i) => i.ch);
  // 听写是「今天学完这几课，默一遍」的场景，顺序对得上课文才有意义
  assert.deepEqual(a, b);

  const writeOrder = catalog.bookChars('1a').filter((ch) => catalog.isWriteChar(ch));
  assert.deepEqual(a, writeOrder.slice(0, 5));
});
