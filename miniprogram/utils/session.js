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
