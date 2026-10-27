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

let progress = store.read('progress', {});
let settings = Object.assign({}, DEFAULT_SETTINGS, store.read('settings', {}));
let stats = store.read('stats', { days: {}, streak: 0, lastDay: 0, quizzes: 0, perfect: 0 });
let wrong = store.read('wrong', {});
let writes = store.read('write', {});
let last = store.read('last', null);

if (!stats.days) stats.days = {};
if (!stats.streak) stats.streak = 0;
if (!stats.lastDay) stats.lastDay = 0;

function persistProgress() {
  store.write('progress', progress);
}
function persistStats() {
  store.write('stats', stats);
}
function persistWrong() {
  store.write('wrong', wrong);
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

function writeStarsTotal() {
  return Object.keys(writes).reduce((n, ch) => n + (writes[ch].stars || 0), 0);
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
  last = null;
  store.remove('progress');
  store.remove('settings');
  store.remove('stats');
  store.remove('wrong');
  store.remove('write');
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
  saveWrite,
  writeStarsTotal,
  getSettings,
  updateSettings,
  getLast,
  setLast,
  recentDays,
  activeDays,
  getBadges,
  getStreak,
  getTodayStats,
  getAccuracyToday,
  resetAll,
  // 测试用
  _today: today,
};
