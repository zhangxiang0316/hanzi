/**
 * 课文词语表。
 *
 * `catalog.lessons[*].words` 是教材每课末尾的词语表（统编版叫「词语表」），
 * 2a 起共 1276 条。这份数据从第一天就躺在 catalog 里，但三端**一次都没有读过**——
 * 之前的「词语填空」用的是每个字自己带的组词（`meta.w`），那是通用例子，
 * 不是课本上要求学生掌握的那一份。
 *
 * 两个用途：
 * 1. 课文词语表（复习时照着念）
 * 2. 「看拼音选词语」练习（`quiz.buildWordQuiz`）
 *
 * 一年级（1a/1b）的课时没有 words 字段。不是数据缺失——一年级课本
 * 本来就没有单独的词语表，识字量还在积累。对这一档用本课生字的组词
 * 兜底，保证功能在所有八册上都可用。
 */
const catalog = require('./catalog');

/** 缓存：课时 → 词语数组（含拼音） */
const lessonCache = {};

function pinyinOf(ch, m) {
  return m && m.py ? m.py : '';
}

/**
 * 一个词的拼音。
 *
 * 优先用 meta 里该字组词自带的拼音（`w[].p`，带声调、按词连写），
 * 拿不到再逐字拼。前者更准——多音字在具体词里的读音只有它知道。
 */
function wordPinyin(word) {
  for (let i = 0; i < word.length; i++) {
    const m = catalog.getMeta(word[i]);
    if (!m || !m.w) continue;
    for (let j = 0; j < m.w.length; j++) {
      if (m.w[j].w === word && m.w[j].p) return m.w[j].p;
    }
  }
  // 退路：逐字拼，空格分开
  const parts = [];
  for (let i = 0; i < word.length; i++) parts.push(pinyinOf(word[i], catalog.getMeta(word[i])));
  return parts.join(' ');
}

/**
 * 某一课的词语。
 *
 * 有课本词语表就用它（带拼音），没有就退到本课生字的组词。
 * 结果按课本顺序，不排序——家长对照课本念的时候顺序要对得上。
 */
function lessonWords(lessonId) {
  if (lessonCache[lessonId]) return lessonCache[lessonId];
  const lesson = catalog.getLesson(lessonId);
  if (!lesson) return [];

  let out = [];
  const raw = lesson.words || [];
  if (raw.length) {
    out = raw.map((w) => ({ word: w, py: wordPinyin(w), from: 'textbook' }));
  } else {
    // 一年级兜底：用本课生字各自的第一组词
    const seen = {};
    (lesson.chars || []).forEach((ch) => {
      const m = catalog.getMeta(ch);
      if (!m || !m.w || !m.w.length) return;
      const w = m.w[0];
      if (!w || !w.w || seen[w.w]) return;
      seen[w.w] = true;
      out.push({ word: w.w, py: w.p || wordPinyin(w.w), from: 'derived' });
    });
  }
  lessonCache[lessonId] = out;
  return out;
}

/** 某一册的全部词语（按课本顺序，去重） */
function bookWords(bookId) {
  const book = catalog.getBook(bookId);
  if (!book) return [];
  const seen = {};
  const out = [];
  (book.lessons || []).forEach((lid) => {
    lessonWords(lid).forEach((w) => {
      if (seen[w.word]) return;
      seen[w.word] = true;
      out.push(Object.assign({ lesson: lid }, w));
    });
  });
  return out;
}

/** 这一册有多少个词（入口上显示用） */
function bookWordCount(bookId) {
  return bookWords(bookId).length;
}

/**
 * 全库词语，按册次顺序。
 *
 * 词语表页要"从头翻一遍"，所以需要一份把 8 册串起来的列表。
 * 复用 `bookWords` 而不是另写一遍：那里面已经处理了一年级的兜底
 * （课本没有词语表时用生字的组词补），另写一份必然会把那个兜底漏掉，
 * 结果就是一年级点进词语表看到一片空白。
 */
function allWords() {
  const out = [];
  catalog.getBooks().forEach((b) => {
    bookWords(b.id).forEach((w) => {
      out.push(Object.assign({ book: b.id, bookName: b.name }, w));
    });
  });
  return out;
}

/**
 * 全库去重后的词语（按册次顺序，保留最早出现的那一册）。
 *
 * `allWords()` 是按册拼接的，去重只做到册内——「旅行」在 3a 和 3b 各出一次
 * 是教材事实，分组浏览时应该各显示一次。但搜索和总数统计算的是"有多少个词"，
 * 那就必须全局去重，否则搜「行」会列出两条「旅行」。
 */
function uniqueWords() {
  const seen = {};
  const out = [];
  allWords().forEach((w) => {
    if (seen[w.word]) {
      // 记下还出现在哪些册，搜索结果里可以显示"3a / 3b"
      seen[w.word].books.push(w.book);
      return;
    }
    const item = Object.assign({}, w, { books: [w.book] });
    seen[w.word] = item;
    out.push(item);
  });
  return out;
}

/**
 * 按字搜词。
 *
 * 只看词里是否含这个字，不看读音——搜「行」应该把「行走」「银行」都列出来，
 * 孩子要的是"哪些词里有这个字"。
 *
 * @returns {Array<{word, py, lesson, book, books, from}>} 全局去重
 */
function wordsWithChar(ch) {
  if (!ch) return [];
  return uniqueWords().filter((w) => w.word.indexOf(ch) >= 0);
}

module.exports = {
  lessonWords,
  bookWords,
  bookWordCount,
  wordPinyin,
  allWords,
  uniqueWords,
  wordsWithChar,
};
