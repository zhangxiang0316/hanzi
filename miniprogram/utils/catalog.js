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

function isWriteChar(ch) {
  const m = meta[ch];
  return !!(m && m.x);
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
  nextInLesson,
  prevInLesson,
  nextInBook,
  prevInBook,
  lessonOfChar,
  bookStat,
};
