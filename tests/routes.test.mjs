import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const routes = require('../miniprogram/utils/routes.js');
const catalog = require('../miniprogram/utils/catalog.js');

test('每个册次都有分包映射，且有对应页面', () => {
  for (const book of catalog.getBooks()) {
    const pack = routes.packOf(book.id);
    assert.ok(pack, book.id + ' 没有分包');
    assert.ok(
      routes.PACK_OF_BOOK[book.id],
      book.id + ' 未在 PACK_OF_BOOK 中登记（新增年级时容易漏）'
    );
  }
});

test('详情/描红 URL 指向该字所属册的分包', () => {
  const cases = [
    ['日', '1a', 'packageStrokes'],
    ['天', '1a', 'packageStrokes'],
    ['鹦', '3a', 'packageStrokes3'],
    ['坝', '3a', 'packageStrokes3'],
    ['匀', '3b', 'packageStrokes3'],
    ['盐', '4a', 'packageStrokes4'],
    ['鹦', '3a', 'packageStrokes3'],
  ];
  for (const [ch, book, pack] of cases) {
    const meta = catalog.getMeta(ch);
    assert.ok(meta, ch + ' 不在字库');
    assert.equal(meta.b, book, ch + ' 所属册次变了');
    const d = routes.detailUrl(ch, 'lesson-x');
    const w = routes.writeUrl(ch);
    assert.ok(d.startsWith('/' + pack + '/pages/detail/detail?'), ch + ' 详情页分包错误: ' + d);
    assert.ok(w.startsWith('/' + pack + '/pages/write/write?'), ch + ' 描红页分包错误: ' + w);
    assert.ok(d.includes('ch=' + encodeURIComponent(ch)), ch + ' 详情 URL 丢了 ch 参数');
    assert.ok(d.includes('&lesson=lesson-x'), ch + ' 详情 URL 丢了 lesson 参数');
  }
});

test('跨册复习字路由回首次收录的分包', () => {
  // 四年级识字表里出现了低年级学过的复习字（「兰/杀/兵」2a、「眠/仅/栖」3a）。
  // 字库按首次出现去重，笔顺数据也只在首次收录的分包里，所以路由必须指回去，
  // 否则从四年级课文点开会白屏。
  const cases = [
    ['兰', '2a', 'packageStrokes'],
    ['杀', '2a', 'packageStrokes'],
    ['兵', '2a', 'packageStrokes'],
    ['眠', '3a', 'packageStrokes3'],
    ['仅', '3a', 'packageStrokes3'],
    ['栖', '3a', 'packageStrokes3'],
  ];
  for (const [ch, book, pack] of cases) {
    const meta = catalog.getMeta(ch);
    assert.ok(meta, ch + ' 不在字库');
    assert.equal(meta.b, book, ch + ' 首次收录册次应为 ' + book);
    assert.equal(routes.packOfChar(ch), pack, ch + ' 应路由到 ' + pack);
  }
});

test('四年级课文里的每个字都能路由到有数据的页面', () => {
  const book = catalog.getBook('4a');
  assert.ok(book, '缺少四年级上册');
  const packs = new Set();
  for (const unit of book.units) {
    for (const lid of unit.lessons) {
      const lesson = catalog.getLesson(lid);
      for (const ch of lesson.chars) {
        const meta = catalog.getMeta(ch);
        assert.ok(meta, `四年级课文 ${lid} 的字「${ch}」不在字库`);
        const pack = routes.packOfChar(ch);
        assert.ok(routes.PACK_OF_BOOK[meta.b], `「${ch}」的册次 ${meta.b} 没有分包映射`);
        packs.add(pack);
      }
    }
  }
  // 四年级大部分字在 packageStrokes4，复习字在低年级分包
  assert.ok(packs.has('packageStrokes4'), '四年级应有字落在 packageStrokes4');
});

test('分包名与 app.json 里的 name 对得上', () => {
  // wx.loadSubpackage({name}) 用的是 app.json 的 name 字段，不是目录名。
  // 两者写岔了不会报错，只会静默下载失败，所以在这里钉死。
  const app = require('../miniprogram/app.json');
  const byName = {};
  for (const sp of app.subpackages) byName[sp.name] = sp.root;
  for (const [root, name] of Object.entries(routes.PACK_NAME)) {
    assert.equal(byName[name], root, `${name} 在 app.json 里应指向 ${root}`);
  }
  // 每个册次都要能取到一个真实存在的分包名
  for (const book of catalog.getBooks()) {
    const name = routes.packNameOf(book.id);
    assert.ok(name, book.id + ' 没有分包名');
    assert.ok(byName[name], `${book.id} 的分包名 ${name} 在 app.json 里不存在`);
  }
});

test('preload 只预载当前册所属的包，且不重复', () => {
  // 真机回归：app.json 静态 preloadRule 一次预载三个分包共 2483KB，
  // 超过「单页面预载 ≤ 2MB」上限，上传报 80058。改为按册动态预载。
  const calls = [];
  global.wx = {
    loadSubpackage(opts) {
      calls.push(opts.name);
    },
  };
  try {
    assert.equal(routes.preload('1a'), 'strokes');
    assert.equal(routes.preload('4a'), 'strokes4');
    // 同一个包重复调用不应再次下载
    assert.equal(routes.preload('4b'), '');
    assert.equal(routes.preload('1b'), '');
    assert.deepEqual(calls, ['strokes', 'strokes4']);
  } finally {
    delete global.wx;
  }
});

test('预载失败后允许重试', () => {
  // 网络抖动导致的失败不该把这一册彻底钉死；下次进页面要能再试。
  let attempt = 0;
  global.wx = {
    loadSubpackage(opts) {
      attempt++;
      if (attempt === 1 && opts.fail) opts.fail({ errMsg: 'network' });
    },
  };
  try {
    assert.equal(routes.preload('3a'), 'strokes3');
    // 第一次失败后标记已清，第二次应当再次发起
    assert.equal(routes.preload('3a'), 'strokes3');
    assert.equal(attempt, 2);
  } finally {
    delete global.wx;
  }
});

test('preload 在非小程序环境（无 wx）下静默返回空串', () => {
  // Node 测试、构建脚本里都会 require routes，不能因为调 preload 就崩
  assert.equal(routes.preload('1a'), '');
  assert.equal(routes.preload(''), '');
});

test('未知字回落到默认分包，不抛异常', () => {
  assert.equal(routes.packOfChar(''), 'packageStrokes');
  assert.equal(routes.packOfChar('𠀀'), 'packageStrokes');
  assert.equal(routes.packOf('zz'), 'packageStrokes');
});
