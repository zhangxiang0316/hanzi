import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const store = require('../miniprogram/utils/store.js');
const profile = require('../miniprogram/utils/profile.js');
const progress = require('../miniprogram/utils/progress.js');

/**
 * 多孩子档案。
 *
 * 一间屋里两个孩子共用一个平板学字是常态。之前所有数据挤在一套键里，
 * 弟弟写几个字就把哥哥的进度、错题本、描红星级全搅在一起。
 *
 * 最要紧的一条：**老用户升级上来不能丢进度**。默认档案的 id 是空串，
 * 键名和加档案功能之前完全一样。
 */

function fresh() {
  store.clearAll();
  profile._reset();
  progress.reload();
}

test.beforeEach(fresh);

test('默认档案的键名和老版本完全一样', () => {
  // 这是兼容性的核心：老数据存在 hanzi:v1:progress，
  // 如果默认档案换个 id，键就变成 hanzi:v1:main:progress，进度全丢
  assert.equal(profile.activeId(), '');
  assert.equal(store.keyOf('progress'), 'hanzi:v1:progress');
  assert.equal(store.keyOf('write'), 'hanzi:v1:write');
});

test('一开始有一个「我」', () => {
  assert.equal(profile.count(), 1);
  assert.equal(profile.active().name, '我');
  assert.equal(profile.list().length, 1);
});

test('老数据在升级后能被读到', () => {
  // 模拟老版本留下的数据：没有 profiles 这个键，只有 progress
  store.write('progress', { 日: { box: 3, seen: 5, ok: 4, miss: 1, due: 0, last: 1, known: true } });
  profile._reset(); // 重建档案表，模拟第一次跑新版本
  progress.reload();
  assert.equal(progress.hasLearned('日'), true, '老进度必须还能读到');
});

test('两个档案的数据互不干扰', () => {
  progress.learn('日');
  assert.equal(progress.totalLearned(), 1);

  profile.add('弟弟');
  profile.setActive('p2');
  progress.reload();
  assert.equal(progress.totalLearned(), 0, '弟弟不该看到哥哥的进度');

  progress.learn('月');
  progress.saveWrite('月', 90);
  assert.equal(progress.totalLearned(), 1);

  profile.setActive('');
  progress.reload();
  assert.equal(progress.totalLearned(), 1, '哥哥的进度还在');
  assert.equal(progress.hasLearned('月'), false, '弟弟学的字不该串到哥哥这边');
  assert.equal(progress.getWrite('月'), null);
});

test('错题本、描红、薄弱点都各自独立', () => {
  progress.grade('日', false, null);            // 哥哥答错
  progress.recordStroke('日', 1, false);
  progress.recordStroke('日', 1, false);

  profile.add('弟弟');
  profile.setActive('p2');
  progress.reload();
  assert.equal(progress.wrongCount(), 0, '弟弟的错题本应该是空的');
  assert.deepEqual(progress.allWeakStrokes(), [], '弟弟没有薄弱点');

  profile.setActive('');
  progress.reload();
  assert.equal(progress.wrongCount(), 1);
  assert.equal(progress.allWeakStrokes().length, 1);
});

test('设置也各自独立（各自选自己的册次）', () => {
  profile.add('妹妹');
  profile.setActive('p3'.replace('3', '2')); // 第二个档案的 id 是 p2
  progress.reload();
  progress.updateSettings({ book: '2a' });
  assert.equal(progress.getSettings().book, '2a');

  profile.setActive('');
  progress.reload();
  assert.equal(progress.getSettings().book, '1a', '哥哥的册次不该被改');
});

test('切换不存在的档案返回 false', () => {
  assert.equal(profile.setActive('nope'), false);
  assert.equal(profile.activeId(), '');
});

test('切到当前档案返回 false（避免无意义 reload）', () => {
  assert.equal(profile.setActive(''), false);
});

test('最多 4 个档案', () => {
  assert.equal(profile.MAX, 4);
  profile.add('老二');
  profile.add('老三');
  profile.add('老四');
  assert.equal(profile.count(), 4);
  assert.equal(profile.canAdd(), false);
  assert.equal(profile.add('老五'), null, '超上限应该拒绝');
  assert.equal(profile.count(), 4);
});

test('名字去空格、截断到 8 字', () => {
  const p = profile.add('  小明  ');
  assert.equal(p.name, '小明');
  const q = profile.add('一二三四五六七八九十');
  assert.equal(q.name.length, 8);
});

test('空名字给一个默认名', () => {
  const p = profile.add('   ');
  assert.equal(p.name, '孩子2');
});

test('改名', () => {
  const p = profile.add('老二');
  assert.equal(profile.rename(p.id, ' 弟弟 '), true);
  assert.equal(profile.list().find((x) => x.id === p.id).name, '弟弟');
  // 空名字拒绝
  assert.equal(profile.rename(p.id, ''), false);
  assert.equal(profile.list().find((x) => x.id === p.id).name, '弟弟');
});

test('可以改默认档案的名字（「我」只是占位）', () => {
  assert.equal(profile.rename('', '哥哥'), true);
  assert.equal(profile.active().name, '哥哥');
});

test('删除档案会一起删掉它的数据', () => {
  const p = profile.add('弟弟');
  profile.setActive(p.id);
  progress.reload();
  progress.learn('月');
  progress.saveWrite('月', 88);

  profile.setActive('');
  progress.reload();
  const before = progress.totalLearned();

  profile.remove(p.id);
  progress.reload();
  assert.equal(progress.totalLearned(), before, '删弟弟不该影响哥哥');

  // 弟弟的键应该真的被清掉了
  store.setProfile(p.id);
  assert.equal(store.read('progress', null), null, '弟弟的数据应该被清空');
  store.setProfile('');
});

test('删掉当前档案会自动切到剩下的第一个', () => {
  const p = profile.add('弟弟');
  profile.setActive(p.id);
  progress.reload();
  assert.equal(profile.activeId(), p.id);

  const next = profile.remove(p.id);
  assert.equal(next, '', '应该切回默认档案');
  assert.equal(profile.activeId(), '');
});

test('删掉的不是当前档案时返回 null（不必 reload）', () => {
  const p = profile.add('弟弟');
  assert.equal(profile.remove(p.id), null);
});

test('不允许删掉最后一个档案', () => {
  assert.equal(profile.count(), 1);
  assert.equal(profile.remove(''), null);
  assert.equal(profile.count(), 1);
});

test('「清空学习记录」只清当前档案', () => {
  // 一键把弟弟的进度也清掉是不可接受的
  profile.add('弟弟');
  profile.setActive('p2');
  progress.reload();
  progress.learn('月');

  profile.setActive('');
  progress.reload();
  progress.learn('日');
  progress.resetAll();

  assert.equal(progress.totalLearned(), 0, '当前档案应该清空');

  profile.setActive('p2');
  progress.reload();
  assert.equal(progress.totalLearned(), 1, '弟弟的进度不该被清掉');
});

test('档案表本身能跨重启保留', () => {
  const p = profile.add('弟弟');
  profile.rename(p.id, '小明');
  profile.setActive(p.id);
  // 重新 require 拿不到新实例（模块缓存），但档案表在 store 里，
  // 用 _reset 之外的方式验证：直接读存储
  const saved = store.read('profiles', null);
  assert.ok(saved, '档案表应该落盘了');
  assert.equal(saved.active, p.id);
  assert.ok(saved.list.some((x) => x.id === p.id && x.name === '小明'));
});

test('active 指向已删除的档案时会自动修正', () => {
  const p = profile.add('弟弟');
  profile.setActive(p.id);
  // 手工把档案表改坏，模拟异常退出留下的脏数据
  const saved = store.read('profiles', null);
  saved.list = saved.list.filter((x) => x.id !== p.id);
  store.write('profiles', saved);

  profile._reset();
  assert.equal(profile.activeId(), '', '应该回落到第一个档案');
});

test('档案表丢了也能恢复出一个默认档案', () => {
  store.remove('profiles');
  profile._reset();
  assert.equal(profile.count(), 1);
  assert.equal(profile.activeId(), '');
});
