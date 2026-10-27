/** 今日学习计划：找出“继续学”的课文、统计进度（纯函数，便于测试） */
const catalog = require('./catalog');

function countLesson(prog, lessonId) {
  const chars = catalog.lessonChars(lessonId);
  let learned = 0;
  for (let i = 0; i < chars.length; i++) {
    if (prog.hasLearned(chars[i])) learned += 1;
  }
  return { total: chars.length, learned, rest: chars.length - learned };
}

function firstUnlearned(chars, prog) {
  for (let i = 0; i < chars.length; i++) {
    if (!prog.hasLearned(chars[i])) return chars[i];
  }
  return '';
}

function bookProgress(prog, bookId) {
  const chars = catalog.bookChars(bookId);
  const c = prog.counts(chars);
  return {
    total: chars.length,
    learned: c.learned,
    mastered: c.mastered,
    due: c.due,
    pct: chars.length ? Math.round((c.learned / chars.length) * 100) : 0,
  };
}

/**
 * 找到应该继续学的那一课：
 * 1) 上次学到的那一课还没学完 → 继续它
 * 2) 否则按目录顺序找下一课还有没学的字
 * 3) 全书学完 → 返回 null
 */
function findContinue(prog, bookId) {
  const book = catalog.getBook(bookId);
  if (!book) return null;
  const last = prog.getLast();
  let startIndex = 0;

  if (last && last.lesson) {
    const idx = book.lessons.indexOf(last.lesson);
    if (idx >= 0) {
      const c = countLesson(prog, last.lesson);
      if (c.rest > 0) {
        return {
          book: bookId,
          lesson: last.lesson,
          title: catalog.lessonTitle(last.lesson),
          bookName: book.short,
          start: firstUnlearned(catalog.lessonChars(last.lesson), prog),
          learned: c.learned,
          total: c.total,
        };
      }
      startIndex = idx + 1;
    }
  }

  for (let i = 0; i < book.lessons.length; i++) {
    const id = book.lessons[(startIndex + i) % book.lessons.length];
    const c = countLesson(prog, id);
    if (c.rest > 0) {
      return {
        book: bookId,
        lesson: id,
        title: catalog.lessonTitle(id),
        bookName: book.short,
        start: firstUnlearned(catalog.lessonChars(id), prog),
        learned: c.learned,
        total: c.total,
      };
    }
  }
  return null;
}

/** 生成首页“今日任务” */
function buildTodayTask(prog, bookId) {
  const due = prog.allDue();
  const settings = prog.getSettings();
  const today = prog.getTodayStats();
  const dailyNew = settings.dailyNew || 5;
  if (due.length > 0) {
    return {
      type: 'review',
      title: '先复习 ' + due.length + ' 个字',
      desc: '温故而知新，几分钟就好',
      action: '开始复习',
      count: due.length,
    };
  }
  if (today.learned >= dailyNew) {
    return {
      type: 'done',
      title: '今天的任务完成啦',
      desc: '新学了 ' + today.learned + ' 个字，明天见！',
      action: '再练一组',
      count: 0,
    };
  }
  const next = findContinue(prog, bookId);
  if (next) {
    return {
      type: 'learn',
      title: '继续学第 ' + catalog.getLesson(next.lesson).no + ' 课',
      desc: next.title + ' · 已学 ' + next.learned + '/' + next.total,
      action: '去学新字',
      count: dailyNew - today.learned,
    };
  }
  return {
    type: 'done',
    title: '这本已经学完啦',
    desc: '换一册，或者去复习巩固',
    action: '去复习',
    count: 0,
  };
}

/** 今日推荐一个字（按日期轮换，保证每天不同） */
function pickDailyChar(bookId, dateKey) {
  const chars = catalog.bookChars(bookId);
  if (!chars.length) return '';
  let h = 0;
  for (let i = 0; i < dateKey.length; i++) h = (h * 31 + dateKey.charCodeAt(i)) >>> 0;
  return chars[h % chars.length];
}

module.exports = {
  countLesson,
  firstUnlearned,
  bookProgress,
  findContinue,
  buildTodayTask,
  pickDailyChar,
};
