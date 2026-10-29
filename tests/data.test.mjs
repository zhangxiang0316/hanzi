import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const catalog = require('../miniprogram/utils/catalog.js');
const { decode } = require('../miniprogram/utils/stroke-codec.js');
const routes = require('../miniprogram/utils/routes.js');

/** 按册取笔顺数据；分包归属由 routes 统一决定，避免测试里再抄一份映射 */
const strokeStoreOf = (book) =>
  require('../miniprogram/' + routes.packOf(book) + '/data/strokes-' + book + '.js');

const BOOKS = ['1a', '1b', '2a', '2b', '3a', '3b', '4a', '4b'];

// 各册识字量（统编版）。少数汉字会在高年级作为复习字再次出现
// （「希/代/章」2a 学过、3b 又列一次；「兰/杀/兵/眠/仅/栖」同理），
// 字库按首次出现去重。
const REPEATS = ['希', '代', '章', '眠', '兰', '杀', '兵', '仅', '栖'];
const BOOK_SUM = 300 + 400 + 450 + 450 + 250 + 250 + 250 + 250;
// 只出现在写字表、不在任何识字表，但也进字库（要能认、能描红）
const WRITE_ONLY = ['匀', '剩', '训', '忧', '毒'];
const UNIQUE = BOOK_SUM - REPEATS.length + WRITE_ONLY.length;

test('八册去重后共 2596 个字（含仅写字表 5 字）', () => {
  const all = catalog.getAllChars();
  assert.equal(all.length, UNIQUE);
  // 各册识字表的并集（不含仅写字表的 2 字）
  const union = new Set();
  for (const b of BOOKS) for (const ch of catalog.bookChars(b)) union.add(ch);
  assert.equal(union.size, UNIQUE - WRITE_ONLY.length);
  // 字库是识字表并集 + 仅写字表的字
  for (const ch of WRITE_ONLY) assert.ok(!union.has(ch), ch + ' 不应算作识字表');
  // 跨册复习字、仅写字表的字都必须能取到完整数据，否则课文里点不开
  for (const ch of REPEATS.concat(WRITE_ONLY)) {
    assert.ok(catalog.getMeta(ch), '字库缺字: ' + ch);
  }
});

test('每册字数与教材一致', () => {
  assert.deepEqual(
    BOOKS.map((b) => catalog.bookStat(b).chars),
    [300, 400, 450, 450, 250, 250, 250, 250]
  );
  assert.equal(catalog.getBooks().length, 8);
  assert.equal(BOOKS.reduce((n, b) => n + catalog.bookStat(b).chars, 0), BOOK_SUM);
});

test('每个字都有拼音、部首、笔画数、组词和课文出处', () => {
  const bad = [];
  for (const ch of catalog.getAllChars()) {
    const m = catalog.getMeta(ch);
    if (!m) { bad.push(ch + ':无数据'); continue; }
    if (!m.py || !/^[a-züāáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜ]+$/.test(m.py)) bad.push(ch + ':拼音异常 ' + m.py);
    if (!m.r) bad.push(ch + ':无部首');
    if (!m.s || m.s < 1 || m.s > 40) bad.push(ch + ':笔画数异常 ' + m.s);
    if (!m.l || !catalog.getLesson(m.l)) bad.push(ch + ':出处课文无效');
    if (!m.w || !m.w.length) bad.push(ch + ':无组词');
    for (const w of m.w) {
      if (w.w.indexOf(ch) < 0) bad.push(ch + ':组词不含本字 ' + w.w);
      if (w.p && w.p.split(' ').length !== [...w.w].length) bad.push(ch + ':组词拼音数不匹配 ' + w.w + ' ' + w.p);
    }
  }
  assert.deepEqual(bad, []);
});

test('写字表中的字都有练字标记', () => {
  let count = 0;
  for (const b of BOOKS) {
    for (const lid of catalog.getBook(b).lessons) {
      for (const ch of catalog.getLesson(lid).write) {
        assert.ok(catalog.isWriteChar(ch), ch + ' 缺少写字标记');
        count++;
      }
    }
  }
  assert.ok(count >= 800, '写字表数量异常: ' + count);
});

test('全部生字笔顺数据可解码且与笔画数一致', () => {
  const bad = [];
  let totalStrokes = 0;
  for (const ch of catalog.getAllChars()) {
    const m = catalog.getMeta(ch);
    const store = strokeStoreOf(m.b);
    const raw = store[ch];
    if (!raw) { bad.push(ch + ':无笔顺'); continue; }
    const d = decode(raw);
    totalStrokes += d.n;
    if (d.n !== m.s) bad.push(ch + ':笔画数不一致 ' + d.n + ' vs ' + m.s);
    if (d.medians.length !== d.n) bad.push(ch + ':中线数量不一致');
    for (const stroke of d.strokes) {
      if (stroke[0][0] !== 0) bad.push(ch + ':笔画未以 M 开始');
      if (stroke[stroke.length - 1][0] !== 4) bad.push(ch + ':笔画未闭合');
      for (const cmd of stroke) {
        for (let i = 1; i < cmd.length; i++) {
          if (cmd[i] < 0 || cmd[i] > 1024) bad.push(ch + ':坐标越界 ' + cmd[i]);
        }
      }
    }
    for (const med of d.medians) {
      if (med.length < 2) bad.push(ch + ':中线点太少');
      for (const p of med) {
        if (p[0] < 0 || p[0] > 1024 || p[1] < 0 || p[1] > 1024) bad.push(ch + ':中线越界');
      }
    }
  }
  assert.deepEqual(bad.slice(0, 20), []);
  assert.ok(totalStrokes > 14000, '总笔画数异常: ' + totalStrokes);
});

test('多音字按课文读音', () => {
  const ch = '长';
  const details = catalog.readingDetails(ch);
  assert.ok(details.length >= 2, '长 应该是多音字');
  const readings = details.map((d) => d.p);
  assert.ok(readings.includes('cháng'));
  assert.ok(readings.includes('zhǎng'));
});

test('课文顺序与单元结构完整', () => {
  for (const b of catalog.getBooks()) {
    const seen = new Set();
    for (const u of b.units) {
      assert.ok(u.lessons.length > 0, b.id + ' 单元 ' + u.no + ' 没有课文');
      for (const lid of u.lessons) {
        assert.ok(catalog.getLesson(lid), '缺少课文 ' + lid);
        assert.ok(!seen.has(lid), '课文重复 ' + lid);
        seen.add(lid);
      }
    }
    assert.equal(seen.size, b.lessons.length);
  }
});

test('笔顺坐标已翻转为屏幕坐标（y 向下），否则整字上下镜像', () => {
  // 源数据是字体坐标系（y 向上、基线 900）。构建时必须翻转。
  // 用部首位置固定的两个字做“地标”：
  //   上 —— 第三笔是底部长横，必须落在下半格
  //   下 —— 第一笔是顶部横画，必须落在上半格
  const store = strokeStoreOf;
  const yOf = (ch, strokeIndex) => {
    const m = catalog.getMeta(ch);
    const data = decode(store(m.b)[ch]);
    const ys = data.medians[strokeIndex].map((p) => p[1]);
    return (Math.min.apply(null, ys) + Math.max.apply(null, ys)) / 2;
  };

  const shangBottom = yOf('上', 2); // 0-based：第 3 笔
  const xiaTop = yOf('下', 0); // 第 1 笔
  assert.ok(
    shangBottom > 1024 * 0.7,
    '“上”的底横应落在下半格，实际 y=' + shangBottom.toFixed(0) + '（说明坐标未翻转）'
  );
  assert.ok(
    xiaTop < 1024 * 0.35,
    '“下”的顶横应落在上半格，实际 y=' + xiaTop.toFixed(0) + '（说明坐标未翻转）'
  );

  // 全部字的墨迹必须落在 0-1024 内且大致居中（翻转基准写错会整体偏移）
  const off = [];
  for (const ch of ['天', '地', '人', '日', '月', '水', '火', '山', '春', '花']) {
    const m = catalog.getMeta(ch);
    const data = decode(store(m.b)[ch]);
    let min = Infinity;
    let max = -Infinity;
    for (const med of data.medians) {
      for (const p of med) {
        if (p[1] < min) min = p[1];
        if (p[1] > max) max = p[1];
      }
    }
    if (min < 0 || max > 1024) off.push(ch + ':越界 ' + min + '-' + max);
    const mid = (min + max) / 2;
    if (mid < 420 || mid > 620) off.push(ch + ':垂直偏离 ' + Math.round(mid));
  }
  assert.deepEqual(off, []);
});
