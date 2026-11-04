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

// 只认不写的字：教材自带 isWriteChar 区分，341 个字只要求认识。
// 描红页据此显示「不要求会写」的说明，避免孩子以为自己没学会。
test('只认不写的字有 798 个，且都有笔顺数据', () => {
  const all = catalog.getAllChars();
  const readOnly = all.filter((ch) => !catalog.isWriteChar(ch));
  // 1798 个要求会写，798 个只要求认识
  assert.equal(readOnly.length, 798);
  assert.equal(all.length - readOnly.length, 1798);

  // 这些字仍能描红（有笔顺数据），只是课标不要求会写
  for (const ch of readOnly.slice(0, 30)) {
    assert.ok(catalog.getMeta(ch), `${ch} 应有元数据`);
  }
});

// 曾经 isWriteChar 只看 meta.x 非空，把 457 个「写字课在五六年级」的字
// （棋→6a-k6、鸦→6b-k3、氏→5a-k16）误判成本项目要求会写——
// 于是听写会要求二年级孩子默写「鸦」。修正后必须与课时的 write 数组
// 并集严格一致，这个交叉验证是两边独立算的，能抓到任何一边的偏差。
test('会写字集合与课时写字表并集严格一致', () => {
  const cat = catalog.catalog;
  const inWriteLists = new Set();
  Object.keys(cat.lessons).forEach((id) => {
    (cat.lessons[id].write || []).forEach((ch) => inWriteLists.add(ch));
  });
  const byMeta = catalog.getAllChars().filter((ch) => catalog.isWriteChar(ch));

  assert.equal(byMeta.length, inWriteLists.size, '两种算法数量不一致');
  for (const ch of byMeta) {
    assert.ok(inWriteLists.has(ch), `${ch} 被判为会写，却不在任何课时写字表里`);
  }
});

test('写字课超出本项目册次的字算只认不写', () => {
  // 这几个字的 meta.x 分别指向 6a/6b/5a/5b，本项目只做一到四年级
  for (const ch of ['棋', '鸦', '氏', '孙', '纯']) {
    assert.equal(catalog.isWriteChar(ch), false, `${ch} 的写字课在五六年级，本项目不要求会写`);
  }
  // 一到四年级的字不受影响
  assert.equal(catalog.isWriteChar('天'), true);
  assert.equal(catalog.isWriteChar('匀'), true); // 3b-k7，在本项目范围内
});

test('典型只认字：髓、嚼、蟹', () => {
  for (const ch of ['髓', '嚼', '蟹']) {
    assert.equal(catalog.isWriteChar(ch), false, `${ch} 不该要求会写`);
  }
  // 会写的字不受影响
  assert.equal(catalog.isWriteChar('天'), true);
});

// 全字表必须是 2596 个字 / 2255 个会写 / 341 个只认。
// 曾经 iOS 和 Android 从「课时 chars 并集」构建字表，得到 2591 个，
// 少了 5 个只出现在课时写字表、没进识字表的字（匀剩训忧毒）；
// 小程序端用 meta 键序，是 2596 个。三端各说各话会导致
// 听写候选池、错题干扰项、字帖统计都对不上。
test('全字表规模：2596 / 1798 / 798', () => {
  const all = catalog.getAllChars();
  assert.equal(all.length, 2596);
  assert.equal(all.filter((ch) => catalog.isWriteChar(ch)).length, 1798);
  assert.equal(all.filter((ch) => !catalog.isWriteChar(ch)).length, 798);
});

test('漏收字：匀剩训忧毒 必须在全字表里', () => {
  const all = catalog.getAllChars();
  for (const ch of ['匀', '剩', '训', '忧', '毒']) {
    assert.ok(all.includes(ch), `${ch} 应在全字表里`);
  }
});

/**
 * 多音字的跨端黄金值：同一 seed、同一批字，三端必须出同一套题。
 * iOS `testPolyphoneMatchesCrossPlatformGolden` 和 Android
 * `同 seed 三端出同一套多音字题` 断言同样的字符串。
 */
test('多音字同 seed 出题锁定为跨端黄金值', () => {
  const quiz = require('../miniprogram/utils/quiz.js');
  const chars = catalog.polyphones('2a').slice(0, 4);
  const r = quiz.buildQuiz({
    chars, book: '2a', count: 4, seed: 20240101, types: ['polyphone'],
  });
  const got = r.questions.map((q) =>
    [q.ch, q.prompt, q.answer, q.options.map((o) => o.v).join('|')].join('|')
  );
  assert.deepEqual(got, [
    '哇|好哇|wa|wā|wa',
    '奔|奔跑|bēn|bēn|bèn',
    '冲|冲锋|chōng|chòng|chōng',
    '炸|炸死|zhà|zhà|zhá',
  ]);
});

// ---------------------------------------------------------------------------
// 词语表浏览
//
// 1276 条词语此前只在「看拼音选词语」的题目和课时页里露过脸，
// 没有任何地方能从头翻一遍。
// ---------------------------------------------------------------------------

test('词语表按教材顺序，且跨课去重', () => {
  const all = catalog.allWords();
  assert.ok(all.length > 1200, `词语太少：${all.length}`);
  assert.ok(all.length <= 1276, '去重后不该多于原始条数');

  const words = all.map((w) => w.word);
  assert.equal(new Set(words).size, words.length, '不能有重复的词');

  // 保留的是**最早**出现的那一课
  const first = all[0];
  assert.ok(first.lesson, '每条都要带课时');
  assert.ok(first.book, '每条都要带册次');
});

test('词语只出现在 2~4 年级（一年级课本没有词语表）', () => {
  // 这不是 bug，是数据事实。页面要据此给出提示，不能显示一片空白
  const books = new Set(catalog.allWords().map((w) => w.book));
  ['2a', '2b', '3a', '3b', '4a', '4b'].forEach((b) => {
    assert.ok(books.has(b), `${b} 应该有词语`);
  });
  assert.equal(catalog.bookWords('1a').length, 0, '一年级没有词语表');
});

test('每条词语的每个字都在字库里', () => {
  // 有字库外的字，孩子点进去查不到读音
  const bad = catalog.allWords().filter((w) => w.missing > 0);
  assert.equal(bad.length, 0,
    `这些词含字库外的字：${bad.slice(0, 5).map((w) => w.word).join(' ')}`);
});

test('按字搜词能搜到跨册的词', () => {
  const found = catalog.wordsWithChar('行');
  assert.ok(found.length >= 3, `含「行」的词太少：${found.length}`);
  // 「银行」和「行走」的「行」读音不同，搜字应该都列出来
  const words = found.map((w) => w.word);
  assert.ok(words.every((w) => w.includes('行')));
});

test('搜不存在的字返回空数组而不是报错', () => {
  assert.deepEqual(catalog.wordsWithChar(''), []);
  assert.deepEqual(catalog.wordsWithChar('龘'), []);
});

test('某一课的词语与教材一致', () => {
  const words = catalog.lessonWords('2a-k1');
  assert.ok(words.length > 0, '2a-k1 应该有词语');
  words.forEach((w) => assert.equal(typeof w, 'string'));
});
