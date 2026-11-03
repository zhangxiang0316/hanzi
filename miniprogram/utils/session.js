/** 练习会话：决定练哪些字（纯函数） */
const catalog = require('./catalog');
const progress = require('./progress');

/** 从数组里随机取 n 个（不重复） */
function sample(list, n, seed) {
  const arr = list.slice();
  let s = (seed || Date.now()) >>> 0;
  const rnd = function () {
    s = (s * 1664525 + 1013904223) >>> 0;
    return s / 4294967296;
  };
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(rnd() * (i + 1));
    const t = arr[i];
    arr[i] = arr[j];
    arr[j] = t;
  }
  return arr.slice(0, n);
}

function buildSession(mode, opts) {
  const o = opts || {};
  if (mode === 'review') {
    const due = o.chars || progress.allDue();
    return {
      mode: 'review',
      title: '今日复习',
      book: o.book || catalog.defaultBook(),
      chars: due.slice(0, 15),
      count: Math.min(15, Math.max(4, due.length * 2)),
    };
  }
  if (mode === 'lesson') {
    const chars = o.chars || catalog.lessonChars(o.lesson);
    return {
      mode: 'lesson',
      title: o.title || '本课练习',
      book: o.book || catalog.getMeta(chars[0]).b,
      lesson: o.lesson,
      chars,
      count: Math.max(chars.length, o.count || 8),
    };
  }
  if (mode === 'wrong') {
    const list = o.chars || progress.getWrong().map((w) => w.ch);
    return {
      mode: 'wrong',
      title: '错题重练',
      book: o.book || catalog.defaultBook(),
      chars: list.slice(0, 12),
      count: Math.min(15, list.length * 2),
    };
  }
  if (mode === 'polyphone') {
    // 多音字：只从本册里挑多音字。本册不足 4 个就从全部补
    // （3b 之后多音字很少，只有 3~6 个，太少了不成一局）
    const book = o.book || catalog.defaultBook();
    let pool = catalog.polyphones(book);
    if (pool.length < 4) pool = catalog.allPolyphones();
    const picked = sample(pool, Math.min(12, pool.length));
    return {
      mode: 'polyphone',
      title: o.title || catalog.getBook(book).name + ' · 多音字',
      book,
      chars: picked,
      count: Math.min(10, Math.max(4, picked.length)),
    };
  }
  if (mode === 'homophone') {
    // 同音字：只从本册里挑「有同音伙伴」的字。本册不足 4 个就从全部补
    const book = o.book || catalog.defaultBook();
    let pool = catalog.homophoneChars(book);
    if (pool.length < 4) pool = catalog.getAllChars().filter(catalog.hasHomophones);
    const picked = sample(pool, Math.min(12, pool.length));
    return {
      mode: 'homophone',
      title: o.title || catalog.getBook(book).name + ' · 同音字',
      book,
      chars: picked,
      count: Math.min(10, Math.max(4, picked.length)),
    };
  }
  if (mode === 'radical') {
    // 部首：只挑「部首不是自己」的字（独体字答案就在题干里，等于送分）
    const book = o.book || catalog.defaultBook();
    let pool = catalog.bookChars(book).filter((ch) => {
      const m = catalog.getMeta(ch);
      return m && m.r && m.r !== ch;
    });
    if (pool.length < 4) {
      pool = catalog.getAllChars().filter((ch) => {
        const m = catalog.getMeta(ch);
        return m && m.r && m.r !== ch;
      });
    }
    const picked = sample(pool, Math.min(12, pool.length));
    return {
      mode: 'radical',
      title: o.title || catalog.getBook(book).name + ' · 部首',
      book,
      chars: picked,
      count: Math.min(10, Math.max(4, picked.length)),
    };
  }
  if (mode === 'words') {
    // 看拼音选词语：题源是课本词语表，不是生字表
    const book = o.book || catalog.defaultBook();
    const words = require('./words');
    const total = words.bookWordCount(book);
    return {
      mode: 'words',
      title: o.title || catalog.getBook(book).name + ' · 看拼音选词语',
      book,
      chars: [],
      count: Math.min(10, Math.max(4, total)),
    };
  }
  // free：按册随机
  const book = o.book || catalog.defaultBook();
  const learned = catalog.bookChars(book).filter((ch) => progress.hasLearned(ch));
  const pool = learned.length >= 8 ? learned : catalog.bookChars(book);
  return {
    mode: 'free',
    title: o.title || catalog.getBook(book).name + ' · 随机练习',
    book,
    chars: sample(pool, Math.min(12, pool.length)),
    count: o.count || 10,
  };
}

module.exports = { buildSession, sample };
