/**
 * 学习进度：SRS 条目、每日统计、连续天数、错题本、描红成绩、设置。
 * 所有数据存在本地，无网络依赖。
 */
const store = require('./store');
const srs = require('./srs');
const day = require('./day');

const DEFAULT_SETTINGS = {
  dailyNew: 5,
  book: '1a',
  showPinyin: true,
};

let progress = {};
let settings = Object.assign({}, DEFAULT_SETTINGS);
let stats = { days: {}, streak: 0, lastDay: 0, quizzes: 0, perfect: 0 };
let wrong = {};
let writes = {};
/**
 * 笔画薄弱点：`{ 字: { 笔画序号: { f: 失败次数, t: 尝试次数, o: 连胜, d: 最近一天 } } }`
 *
 * 描红判分本来每笔都会算出「为什么不过」（起笔错 / 偏离 / 写短了），
 * 但之前只拿它拼一句即时提示就丢掉了。留下来才看得出「这个字的第 2 笔
 * 你反复写不好」——这比整字分数具体，也更能指导下一步练什么。
 */
let weak = {};
let last = null;

/**
 * 从当前命名空间重读全部状态。
 *
 * 切换孩子档案时必须调用：存储的键换了前缀，但这份内存状态还是上一个
 * 孩子的。不重读的话界面会显示「名字换了、数据没变」——比不换还糟。
 */
function load() {
  progress = store.read('progress', {}) || {};
  settings = Object.assign({}, DEFAULT_SETTINGS, store.read('settings', {}) || {});
  stats = store.read('stats', { days: {}, streak: 0, lastDay: 0, quizzes: 0, perfect: 0 });
  wrong = store.read('wrong', {}) || {};
  writes = store.read('write', {}) || {};
  weak = store.read('weak', {}) || {};
  last = store.read('last', null);
  if (!stats.days) stats.days = {};
  if (!stats.streak) stats.streak = 0;
  if (!stats.lastDay) stats.lastDay = 0;
}

load();

function persistProgress() {
  store.write('progress', progress);
}
function persistStats() {
  store.write('stats', stats);
}
function persistWrong() {
  store.write('wrong', wrong);
}
function persistWeak() {
  store.write('weak', weak);
}
function persistSettings() {
  store.write('settings', settings);
}

function today() {
  return day.dayNumber();
}

function todayKey() {
  return day.todayKey();
}

function ensureDay() {
  const n = today();
  const key = todayKey();
  if (!stats.days[key]) {
    stats.days[key] = { learned: 0, answers: 0, correct: 0 };
  }
  if (stats.lastDay !== n) {
    if (stats.lastDay === n - 1) stats.streak = (stats.streak || 0) + 1;
    else if (stats.lastDay !== 0) stats.streak = 1;
    else stats.streak = 1;
    stats.lastDay = n;
  }
  return stats.days[key];
}

function getStreak() {
  const n = today();
  if (stats.lastDay === n || stats.lastDay === n - 1) return stats.streak || 0;
  return 0;
}

function getTodayStats() {
  const d = stats.days[todayKey()];
  return d ? Object.assign({}, d) : { learned: 0, answers: 0, correct: 0 };
}

function getAccuracyToday() {
  const d = getTodayStats();
  return d.answers ? Math.round((d.correct / d.answers) * 100) : 0;
}

function getEntry(ch) {
  return progress[ch] || null;
}

function hasLearned(ch) {
  return srs.isLearning(progress[ch]);
}

function isMastered(ch) {
  return srs.isMastered(progress[ch]);
}

function learn(ch) {
  const e = progress[ch];
  if (e && e.box >= 1) return e;
  const daily = ensureDay();
  progress[ch] = srs.learn(e, today());
  daily.learned += 1;
  persistProgress();
  persistStats();
  return progress[ch];
}

function markKnown(ch) {
  const daily = ensureDay();
  if (!progress[ch] || progress[ch].box < 1) daily.learned += 1;
  progress[ch] = srs.markKnown(progress[ch], today());
  persistProgress();
  persistStats();
  return progress[ch];
}

function grade(ch, correct, ctx) {
  const daily = ensureDay();
  const before = progress[ch];
  progress[ch] = srs.grade(before, correct, today());
  daily.answers += 1;
  if (correct) daily.correct += 1;

  if (correct) {
    if (wrong[ch]) {
      wrong[ch].n = (wrong[ch].n || 1) - 1;
      if (wrong[ch].n <= 0) delete wrong[ch];
    }
  } else {
    const info = wrong[ch] || { n: 0, first: today() };
    info.n = (info.n || 0) + 1;
    info.last = today();
    if (ctx) {
      info.book = ctx.book || info.book;
      info.lesson = ctx.lesson || info.lesson;
    }
    wrong[ch] = info;
  }
  persistProgress();
  persistStats();
  persistWrong();
  return progress[ch];
}

function recordQuiz(total, correct) {
  stats.quizzes = (stats.quizzes || 0) + 1;
  if (total > 0 && correct === total) stats.perfect = (stats.perfect || 0) + 1;
  if (!stats.best) stats.best = 0;
  const rate = total ? correct / total : 0;
  if (rate > stats.best) stats.best = rate;
  persistStats();
}

function dueChars(chars) {
  const t = today();
  const list = chars || Object.keys(progress);
  const out = [];
  for (let i = 0; i < list.length; i++) {
    if (srs.isDue(progress[list[i]], t)) out.push(list[i]);
  }
  return out;
}

function allDue() {
  return dueChars(Object.keys(progress));
}

function counts(chars) {
  const t = today();
  const res = { total: chars.length, learned: 0, mastered: 0, due: 0, weak: 0 };
  for (let i = 0; i < chars.length; i++) {
    const e = progress[chars[i]];
    if (!e || e.box < 1) continue;
    res.learned += 1;
    if (e.box >= srs.MASTERED_BOX) res.mastered += 1;
    if (e.box < 3) res.weak += 1;
    if (srs.isDue(e, t)) res.due += 1;
  }
  return res;
}

function allCounts() {
  return counts(Object.keys(progress).filter((ch) => progress[ch] && progress[ch].box >= 1));
}

function totalLearned() {
  let n = 0;
  Object.keys(progress).forEach((ch) => {
    if (progress[ch] && progress[ch].box >= 1) n += 1;
  });
  return n;
}

function totalMastered() {
  let n = 0;
  Object.keys(progress).forEach((ch) => {
    if (srs.isMastered(progress[ch])) n += 1;
  });
  return n;
}

function getWrong() {
  return Object.keys(wrong)
    .map((ch) => Object.assign({ ch }, wrong[ch]))
    .sort((a, b) => (b.n || 0) - (a.n || 0) || (b.last || 0) - (a.last || 0));
}

function wrongCount() {
  return Object.keys(wrong).length;
}

function clearWrong(ch) {
  if (ch) delete wrong[ch];
  else wrong = {};
  persistWrong();
}

function getWrite(ch) {
  return writes[ch] || null;
}

function saveWrite(ch, score) {
  const old = writes[ch] || { best: 0, tries: 0 };
  const stars = score >= 85 ? 3 : score >= 65 ? 2 : score >= 40 ? 1 : 0;
  const record = {
    best: Math.max(old.best || 0, score),
    stars: Math.max(old.stars || 0, stars),
    tries: (old.tries || 0) + 1,
    last: today(),
  };
  writes[ch] = record;
  store.write('write', writes);
  return record;
}

/**
 * 记录一笔的结果。
 *
 * `passed` 是这一笔有没有过判分线。失败次数才是「薄弱」的依据：
 * 一次成功不能抵消两次失败——真正写不好的笔画会一直被记着。
 *
 * 练好的判定是**连续写对 2 次**（`o` 记连胜）。
 * 为什么不「写对一次就清掉」：那样 `t` 永远等于 `f`，
 * 下面 40% 那条门槛就成了摆设，而且手抖蒙对一次就前功尽弃。
 * 为什么不是 3 次：低年级一个字的同一笔连写 3 遍正确，样本已经够了。
 */
function recordStroke(ch, index, passed) {
  if (!ch) return;
  if (!weak[ch]) weak[ch] = {};
  const key = String(index);
  const rec = weak[ch][key] || { f: 0, t: 0, o: 0, d: 0 };
  rec.t += 1;
  rec.d = today();
  if (passed) {
    rec.o = (rec.o || 0) + 1;
    // 连续两次写对：这一笔练稳了，不用再提示
    if (rec.o >= 2) {
      delete weak[ch][key];
      if (!Object.keys(weak[ch]).length) delete weak[ch];
      persistWeak();
      return;
    }
  } else {
    rec.f += 1;
    rec.o = 0;
  }
  weak[ch][key] = rec;
  persistWeak();
}

/**
 * 这个字哪些笔画是薄弱点：失败 ≥ 2 次。
 *
 * 只错一次是很正常的（手抖、第一次不熟），不算薄弱点。
 *
 * 门槛就这一条，不再叠「失败率 ≥40%」——加上「连对两次即移除」之后，
 * 任何还在册的记录都满足 `t ≤ 2f+1`（中间不可能夹两次连续成功），
 * 于是失败率恒 ≥ 50%，那条判断永远为真，是死代码。
 * 测试里锁了这个不变量。
 */
function weakStrokesOf(ch) {
  const rec = weak[ch];
  if (!rec) return [];
  const out = [];
  Object.keys(rec).forEach((k) => {
    const r = rec[k];
    if (r.f >= 2) {
      out.push({ index: Number(k), fails: r.f, tries: r.t });
    }
  });
  // 笔画序号升序：读起来跟笔顺一致
  out.sort((a, b) => a.index - b.index);
  return out;
}

/** 有没有需要专门练的笔画 */
function hasWeakStrokes(ch) {
  return weakStrokesOf(ch).length > 0;
}

/**
 * 全部薄弱点，按「最需要练」排序：失败次数多的在前。
 *
 * 同一字的多个笔画算作一条记录各占一行——「日的第2笔」和「日的第4笔」
 * 是两个不同的动作，合成一条就没法分别练。
 */
function allWeakStrokes() {
  const out = [];
  Object.keys(weak).forEach((ch) => {
    weakStrokesOf(ch).forEach((w) => {
      out.push({ ch, index: w.index, fails: w.fails, tries: w.tries });
    });
  });
  out.sort((a, b) => {
    if (b.fails !== a.fails) return b.fails - a.fails;
    // 兜底：码点 + 笔画序号，保证三端顺序一致
    if (a.ch !== b.ch) return a.ch.codePointAt(0) - b.ch.codePointAt(0);
    return a.index - b.index;
  });
  return out;
}

/**
 * 有薄弱笔画的字，按「最弱的那一笔」排序（每个字只出现一次）。
 *
 * 练习入口用这个：一个字的第 2 笔和第 4 笔都在练同一份描红，
 * 按笔画列出会重复练同一个字。
 */
function weakChars() {
  const seen = {};
  const out = [];
  allWeakStrokes().forEach((w) => {
    if (seen[w.ch]) {
      seen[w.ch].count += 1;
      return;
    }
    const rec = { ch: w.ch, count: 1, worst: w.index, fails: w.fails };
    seen[w.ch] = rec;
    out.push(rec);
  });
  return out;
}

/** 某一笔练好了：把它从薄弱点里去掉（不删整个字的记录） */
function clearWeakStroke(ch, index) {
  if (!weak[ch]) return;
  delete weak[ch][String(index)];
  if (!Object.keys(weak[ch]).length) delete weak[ch];
  persistWeak();
}

/** 整个字从薄弱点里清掉（重练通过时用） */
function clearWeak(ch) {
  if (!weak[ch]) return;
  delete weak[ch];
  persistWeak();
}

function writeStarsTotal() {
  return Object.keys(writes).reduce((n, ch) => n + (writes[ch].stars || 0), 0);
}

/** 写过多少个字 */
function writeCount() {
  return Object.keys(writes).length;
}

/**
 * 所有写过字的记录，按「最近写的在前，同一天按最高分降序」排。
 *
 * 排序刻意不按字的音序：孩子翻开字帖想看的是「我最近写的」，
 * 而不是「按拼音排的一堆字」——后者更像词典，不像自己的成果。
 * 与 iOS `allWriteRecords()`、Android `allWriteRecords()` 三端一致。
 */
function allWriteRecords() {
  return Object.keys(writes)
    .map((ch) => ({ ch, record: writes[ch] }))
    .sort((a, b) => {
      if (a.record.last !== b.record.last) return b.record.last - a.record.last;
      if (a.record.best !== b.record.best) return b.record.best - a.record.best;
      // 兜底：保证顺序稳定，测试可复现
      return a.ch < b.ch ? -1 : a.ch > b.ch ? 1 : 0;
    });
}

/** 按星级分档的数量（3 星 / 2 星 / 1 星 / 0 星），四个键一定存在 */
function writeStarsHistogram() {
  const out = { 0: 0, 1: 0, 2: 0, 3: 0 };
  Object.keys(writes).forEach((ch) => {
    const s = writes[ch].stars || 0;
    out[s] = (out[s] || 0) + 1;
  });
  return out;
}

/**
 * 上次识字量测试的结果。存在 settings 里而不是单独一个键：
 * 它就是一个「上次测出来多少」的缓存，跟册次、每天新学一样属于设置区。
 */
function getVocabSize() {
  return settings.vocabSize || 0;
}

/** 记下这次测出的识字量（0 表示没测过，不覆盖已有结果） */
function setVocabSize(size) {
  const n = Math.max(0, Math.round(size || 0));
  if (!n) return;
  updateSettings({ vocabSize: n, vocabDate: day.dayNumber() });
}

function getSettings() {
  return Object.assign({}, settings);
}

function updateSettings(patch) {
  settings = Object.assign({}, settings, patch);
  persistSettings();
  return Object.assign({}, settings);
}

function getLast() {
  return last ? Object.assign({}, last) : null;
}

function setLast(info) {
  last = Object.assign({ at: today() }, info);
  store.write('last', last);
}

function recentDays(n) {
  const out = [];
  for (let i = n - 1; i >= 0; i--) {
    const key = day.dayKeyOf(-i);
    const d = stats.days[key] || { learned: 0, answers: 0, correct: 0 };
    const date = new Date();
    date.setDate(date.getDate() - i);
    out.push({
      key,
      label: day.weekdayCN(date).replace('周', ''),
      learned: d.learned || 0,
      answers: d.answers || 0,
      correct: d.correct || 0,
      rate: d.answers ? Math.round((d.correct / d.answers) * 100) : 0,
    });
  }
  return out;
}

/**
 * 逐日统计的原始副本（`stats.days`）。
 *
 * 周报要按自己的口径重算（滚动 7 天、活跃判定、正确率），所以给它原始
 * 数据而不是 `recentDays` 的结果——那个函数是练习页的 7 天图专用的，
 * 口径和周报不完全一样。
 *
 * 返回的是浅拷贝，外面改了不会污染内存里的状态。
 */
function getDaysStats() {
  const out = {};
  Object.keys(stats.days || {}).forEach((k) => {
    const d = stats.days[k];
    if (!d) return;
    out[k] = { learned: d.learned || 0, answers: d.answers || 0, correct: d.correct || 0 };
  });
  return out;
}

function activeDays() {
  let n = 0;
  Object.keys(stats.days).forEach((k) => {
    const d = stats.days[k];
    if (d && ((d.learned || 0) > 0 || (d.answers || 0) > 0)) n += 1;
  });
  return n;
}

function getBadges() {
  const learned = totalLearned();
  const streak = getStreak();
  const perfect = stats.perfect || 0;
  const writes3 = writeStarsTotal();
  return [
    { id: 'sprout', emoji: '🌱', name: '破土而出', desc: '认识 1 个汉字', got: learned >= 1 },
    { id: 'ten', emoji: '📖', name: '小书童', desc: '认识 10 个汉字', got: learned >= 10 },
    { id: 'fifty', emoji: '⭐', name: '识字小达人', desc: '认识 50 个汉字', got: learned >= 50 },
    { id: 'hundred', emoji: '🏅', name: '百字斩', desc: '认识 100 个汉字', got: learned >= 100 },
    { id: 'five', emoji: '👑', name: '汉字收藏家', desc: '认识 500 个汉字', got: learned >= 500 },
    { id: 'streak', emoji: '🔥', name: '坚持之星', desc: '连续学习 3 天', got: streak >= 3 },
    { id: 'perfect', emoji: '🎯', name: '满分小状元', desc: '闯关全部答对', got: perfect >= 1 },
    { id: 'write', emoji: '✍️', name: '小小书法家', desc: '描红获得 10 颗星', got: writes3 >= 10 },
  ];
}

function resetAll() {
  progress = {};
  settings = Object.assign({}, DEFAULT_SETTINGS);
  stats = { days: {}, streak: 0, lastDay: 0, quizzes: 0, perfect: 0 };
  wrong = {};
  writes = {};
  weak = {};
  last = null;
  store.remove('progress');
  store.remove('settings');
  store.remove('stats');
  store.remove('wrong');
  store.remove('write');
  store.remove('weak');
  store.remove('last');
}

module.exports = {
  DEFAULT_SETTINGS,
  getEntry,
  hasLearned,
  isMastered,
  learn,
  markKnown,
  grade,
  recordQuiz,
  dueChars,
  allDue,
  counts,
  allCounts,
  totalLearned,
  totalMastered,
  getWrong,
  wrongCount,
  clearWrong,
  getWrite,
  reload: load,
  saveWrite,
  recordStroke,
  weakStrokesOf,
  hasWeakStrokes,
  allWeakStrokes,
  weakChars,
  clearWeakStroke,
  clearWeak,
  writeStarsTotal,
  writeCount,
  allWriteRecords,
  writeStarsHistogram,
  getVocabSize,
  setVocabSize,
  getSettings,
  updateSettings,
  getLast,
  setLast,
  recentDays,
  getDaysStats,
  activeDays,
  getBadges,
  getStreak,
  getTodayStats,
  getAccuracyToday,
  resetAll,
  // 测试用
  _today: today,
};
