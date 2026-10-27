/**
 * Leitner 间隔复习（纯函数，方便单测）
 * 箱子 0-7 对应复习间隔 0/1/2/4/7/15/30/60 天。
 */
const INTERVALS = [0, 1, 2, 4, 7, 15, 30, 60];
const MAX_BOX = INTERVALS.length - 1;
const MASTERED_BOX = 5;

function empty() {
  return { box: 0, seen: 0, ok: 0, miss: 0, due: 0, last: 0 };
}

function isDue(entry, today) {
  return !!entry && typeof entry.due === 'number' && entry.due <= today;
}

function isMastered(entry) {
  return !!entry && entry.box >= MASTERED_BOX;
}

function isLearning(entry) {
  return !!entry && entry.box >= 1;
}

/** 第一次学习：进入箱子 1，明天复习。重复调用不会降级。 */
function learn(entry, today) {
  if (entry && entry.box >= 1) return entry;
  const e = Object.assign(empty(), entry || {});
  e.box = 1;
  e.due = today + INTERVALS[1];
  e.last = today;
  return e;
}

/** 答题评分：答对升一箱，答错回退（已较熟的字退到 1，生字退到 0）。 */
function grade(entry, correct, today) {
  const e = Object.assign(empty(), entry || {});
  e.seen = (e.seen || 0) + 1;
  if (correct) {
    e.ok = (e.ok || 0) + 1;
    e.box = Math.min(MAX_BOX, (e.box || 0) + 1);
  } else {
    e.miss = (e.miss || 0) + 1;
    e.box = (e.box || 0) >= 3 ? 1 : 0;
  }
  e.due = today + INTERVALS[e.box];
  e.last = today;
  return e;
}

/** 直接标记“已认识”（用于快速跳过已掌握的字）。 */
function markKnown(entry, today) {
  const e = Object.assign(empty(), entry || {});
  e.box = Math.max(e.box || 0, 4);
  e.due = today + INTERVALS[e.box];
  e.last = today;
  e.known = true;
  return e;
}

function stageOf(entry) {
  if (!entry) return 'new';
  if (entry.box >= MASTERED_BOX) return 'mastered';
  if (entry.box >= 1) return 'learning';
  return 'weak';
}

const STAGE_LABEL = {
  new: '未学',
  weak: '待巩固',
  learning: '学习中',
  mastered: '已掌握',
};

module.exports = {
  INTERVALS,
  MAX_BOX,
  MASTERED_BOX,
  empty,
  isDue,
  isMastered,
  isLearning,
  learn,
  grade,
  markKnown,
  stageOf,
  STAGE_LABEL,
};
