/** 教材目录 + 字库元数据（由 scripts/build-data.mjs 生成） */
const catalog = require('../data/catalog.js');
const meta = require('../data/meta.js');

const books = catalog.books;
const bookMap = {};
books.forEach((b) => {
  bookMap[b.id] = b;
});

const lessonMap = catalog.lessons;

const bookCharsCache = {};
const allCharList = Object.keys(meta);

function getBooks() {
  return books;
}

function getBook(id) {
  return bookMap[id] || null;
}

function defaultBook() {
  return books[0] ? books[0].id : '1a';
}

function getLesson(id) {
  return lessonMap[id] || null;
}

function getMeta(ch) {
  return meta[ch] || null;
}

function hasChar(ch) {
  return !!meta[ch];
}

function getAllChars() {
  return allCharList.slice();
}

function lessonTitle(id) {
  const l = lessonMap[id];
  return l ? l.title : '';
}

function lessonLabel(id) {
  const l = lessonMap[id];
  if (!l) return '';
  const b = bookMap[l.book];
  return (b ? b.short + ' · ' : '') + '第' + l.no + '课 ' + l.title;
}

/** 按“册 → 单元 → 课 → 生字”的教材顺序返回某册全部生字（去重）。 */
function bookChars(bookId) {
  if (bookCharsCache[bookId]) return bookCharsCache[bookId];
  const book = bookMap[bookId];
  if (!book) return [];
  const seen = {};
  const out = [];
  for (let i = 0; i < book.lessons.length; i++) {
    const l = lessonMap[book.lessons[i]];
    if (!l) continue;
    for (let j = 0; j < l.chars.length; j++) {
      const ch = l.chars[j];
      if (!seen[ch]) {
        seen[ch] = true;
        out.push(ch);
      }
    }
  }
  bookCharsCache[bookId] = out;
  return out;
}

function lessonChars(lessonId) {
  const l = lessonMap[lessonId];
  return l ? l.chars.slice() : [];
}

function unitLessons(bookId, unitNo) {
  const book = bookMap[bookId];
  if (!book) return [];
  const unit = book.units.filter((u) => u.no === unitNo)[0];
  return unit ? unit.lessons.slice() : [];
}

/** 取本课语境下的读音；多音字按教材标注。 */
function readingFor(ch, lessonId) {
  const m = meta[ch];
  if (!m) return '';
  if (m.rd) {
    for (let i = 0; i < m.rd.length; i++) {
      if (m.rd[i].l === lessonId) return m.rd[i].p;
    }
  }
  return m.py;
}

/** 一个字所有可能读音（用于排除同音干扰项）。 */
function readingsOf(ch) {
  const m = meta[ch];
  if (!m) return [];
  if (!m.rd) return [m.py];
  const out = [];
  m.rd.forEach((r) => {
    if (out.indexOf(r.p) < 0) out.push(r.p);
  });
  return out;
}

/** 多音字展示：读音 + 出现课文。 */
function readingDetails(ch) {
  const m = meta[ch];
  if (!m) return [];
  if (!m.rd) return [{ p: m.py }];
  return m.rd.map((r) => ({
    p: r.p,
    lesson: r.l,
    title: lessonTitle(r.l),
  }));
}

/** 本项目覆盖的册次（一上～四下）。meta.x 可能指向五六年级的写字课。 */
const BOOK_IDS = {};
books.forEach((b) => { BOOK_IDS[b.id] = true; });

/**
 * 这个字在本项目范围内是否要求会写。
 *
 * 不能只看 `meta.x` 非空：有 457 个字的写字课在五、六年级（如「棋」的
 * x 是 6a-k6），而本项目只做一到四年级。这些字在本项目里是「只认不写」，
 * 之前三端都误判成会写，导致听写会要求孩子默写「鸦」「氏」「孙」这类字。
 *
 * 修正后与本项目课时的 `write` 数组并集严格一致（都是 1798 个），
 * 这个交叉验证写进了测试。
 */
function isWriteChar(ch) {
  const m = meta[ch];
  if (!m || !m.x) return false;
  return BOOK_IDS[m.x.split('-')[0]] === true;
}

// MARK: - 多音字

/** 是否多音字 */
function isPolyphone(ch) {
  const m = meta[ch];
  return !!(m && m.rd && m.rd.length > 1);
}

/** 某册里的多音字（保持教材顺序） */
function polyphones(bookId) {
  return bookChars(bookId).filter(isPolyphone);
}

/** 全部多音字 */
function allPolyphones() {
  return getAllChars().filter(isPolyphone);
}

/**
 * 某个读音的用例词。
 *
 * 组词数据里每个词都带拼音，而拼音音节与汉字一一对应。所以只要把
 * 「本字在词中的位置」与「拼音里的音节位置」对上，就能确定这个词用的是哪个读音。
 *
 * 早先试过「拼音里任意位置出现该音节就算」——那样会把「地方」的 dì
 * 误配到别的读音上（同一个词里另一个字恰好同音时）。改成按位置对齐后，
 * 156 个多音字全部都能匹配到用例，且不会串音。
 *
 * 音节数与字数不一致的词（儿化、轻声合写等）直接跳过，宁可少几个例子也不出错。
 */
function wordsUsing(ch, reading) {
  const m = meta[ch];
  if (!m || !m.w) return [];
  const out = [];
  for (let i = 0; i < m.w.length; i++) {
    const w = m.w[i];
    const chars = Array.from(w.w);
    const idx = chars.indexOf(ch);
    if (idx < 0) continue;
    const syl = w.p.split(/\s+/);
    if (syl.length !== chars.length) continue;
    if (syl[idx] === reading) out.push(w.w);
  }
  return out;
}

/** 册次在教材里的先后序号（越小越早） */
function bookRank(bookId) {
  const i = books.findIndex((b) => b.id === bookId);
  return i >= 0 ? i : books.length;
}

/**
 * 一个词「最难的字的册次」。用来给多音字例句排序：
 * 「数落」里「落」是 3 年级的字，一年级的孩子看不懂，
 * 优先选整词都在本册或更早的词。
 */
function wordRank(word) {
  let worst = 0;
  Array.from(word).forEach((c) => {
    const m = meta[c];
    const r = m ? bookRank(m.b) : books.length;
    if (r > worst) worst = r;
  });
  return worst;
}

/** 多音字的读音 + 各自用例词（按「好懂」排序） */
function polyphoneCases(ch) {
  return readingDetails(ch).map((r) => {
    const ws = wordsUsing(ch, r.p).sort((a, b) => {
      const ra = wordRank(a);
      const rb = wordRank(b);
      if (ra !== rb) return ra - rb;
      return a.length - b.length; // 同难度优先短词
    });
    return { reading: r, words: ws };
  });
}

/** 在本课内的下一个 / 上一个字（用于详情页翻页）。 */
function nextInLesson(lessonId, ch) {
  const list = lessonChars(lessonId);
  const i = list.indexOf(ch);
  return i >= 0 && i < list.length - 1 ? list[i + 1] : '';
}

function prevInLesson(lessonId, ch) {
  const list = lessonChars(lessonId);
  const i = list.indexOf(ch);
  return i > 0 ? list[i - 1] : '';
}

function nextInBook(bookId, ch) {
  const list = bookChars(bookId);
  const i = list.indexOf(ch);
  return i >= 0 && i < list.length - 1 ? list[i + 1] : '';
}

function prevInBook(bookId, ch) {
  const list = bookChars(bookId);
  const i = list.indexOf(ch);
  return i > 0 ? list[i - 1] : '';
}

/** 找到某字在教材中的首次出现课文。 */
function lessonOfChar(ch) {
  const m = meta[ch];
  return m ? m.l : '';
}

function bookStat(bookId) {
  const b = bookMap[bookId];
  return b ? b.stat : { chars: 0, write: 0, lessons: 0, units: 0 };
}

module.exports = {
  catalog,
  meta,
  books,
  getBooks,
  getBook,
  defaultBook,
  getLesson,
  getMeta,
  hasChar,
  getAllChars,
  lessonTitle,
  lessonLabel,
  bookChars,
  lessonChars,
  unitLessons,
  readingFor,
  readingsOf,
  readingDetails,
  isWriteChar,
  isPolyphone,
  polyphones,
  allPolyphones,
  wordsUsing,
  bookRank,
  wordRank,
  polyphoneCases,
  nextInLesson,
  prevInLesson,
  nextInBook,
  prevInBook,
  lessonOfChar,
  bookStat,
};
