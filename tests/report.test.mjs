import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const report = require('../miniprogram/utils/report.js');

/**
 * 学习周报。
 *
 * 周报的数字是给家长看的，算错了比不显示更糟——家长会据此判断孩子
 * 学得好不好。所以每个口径都要钉死，尤其是「没学」和「学了但没答对」
 * 这两种情况必须区分开。
 */

/** 造一份 stats.days，offset 为负表示几天前 */
function days(list) {
  const now = new Date(2026, 10, 3); // 2026-11-03 周二
  const out = {};
  list.forEach(([offset, learned, answers, correct]) => {
    const d = new Date(now.getTime());
    d.setDate(d.getDate() + offset);
    const key = d.getFullYear() + '-'
      + String(d.getMonth() + 1).padStart(2, '0') + '-'
      + String(d.getDate()).padStart(2, '0');
    out[key] = { learned, answers, correct };
  });
  return out;
}

const NOW = new Date(2026, 10, 3);

test('取最近 7 天，最后一项是今天', () => {
  const week = report.recentDays(days([[0, 3, 10, 8]]), { now: NOW });
  assert.equal(week.length, 7);
  assert.equal(week[6].daysAgo, 0);
  assert.equal(week[6].learned, 3);
  assert.equal(week[0].daysAgo, 6);
});

test('缺数据的那天算「没学」，不是 0 分', () => {
  // 这条最容易搞错：把缺失当 0 会让家长看到「正确率 0%」
  const week = report.recentDays(days([[0, 3, 10, 8]]), { now: NOW });
  const empty = week[0];
  assert.equal(empty.active, false);
  assert.equal(empty.accuracy, null, '没答题时正确率必须是 null，不能是 0');
  assert.equal(empty.learned, 0);
  assert.equal(empty.answers, 0);
});

test('学了但一题没答，正确率也是 null', () => {
  // 只描红不答题：有学习量，但算不出正确率
  const week = report.recentDays(days([[0, 2, 0, 0]]), { now: NOW });
  const today = week[6];
  assert.equal(today.active, true, '学了字就算活跃');
  assert.equal(today.accuracy, null, '没答题不能报 0%');
});

test('正确率四舍五入到整数', () => {
  const week = report.recentDays(days([[0, 1, 3, 2]]), { now: NOW });
  assert.equal(week[6].accuracy, 67); // 66.67 → 67
});

test('星期按周一打头', () => {
  // 2026-11-03 是周二
  const week = report.recentDays(null, { now: NOW });
  assert.equal(week[6].weekday, '二');
  assert.equal(week[5].weekday, '一');
});

test('汇总：学习量、答题量、正确率、活跃天数', () => {
  const week = report.recentDays(days([
    [0, 3, 10, 8],
    [-1, 5, 12, 6],
    [-3, 2, 0, 0],
  ]), { now: NOW });
  const sum = report.summarize(week);
  assert.equal(sum.learned, 10);
  assert.equal(sum.answers, 22);
  assert.equal(sum.correct, 14);
  assert.equal(sum.accuracy, 64); // 14/22 = 63.6 → 64
  assert.equal(sum.activeDays, 3);
  assert.equal(sum.empty, false);
});

test('整周没学是 empty', () => {
  const sum = report.summarize(report.recentDays(null, { now: NOW }));
  assert.equal(sum.empty, true);
  assert.equal(sum.activeDays, 0);
  assert.equal(sum.accuracy, null);
  assert.equal(sum.best, null);
});

test('「最好的一天」按学习量取，打破平手看答题量', () => {
  const week = report.recentDays(days([
    [0, 3, 4, 4],
    [-2, 8, 2, 2],
  ]), { now: NOW });
  const sum = report.summarize(week);
  assert.equal(sum.learned, 11);
  assert.equal(sum.best.learned, 8, '学习量最多的那天');
});

test('headline 对空周不说「正确率」这种空话', () => {
  const sum = report.summarize(report.recentDays(null, { now: NOW }));
  assert.match(report.headline(sum), /还没开始/);
});

test('headline 满勤和不满勤措辞不同', () => {
  const full = report.summarize(report.recentDays(
    days([0, -1, -2, -3, -4, -5, -6].map((o) => [o, 1, 0, 0])), { now: NOW }));
  assert.equal(full.activeDays, 7);
  assert.match(report.headline(full), /七天/);
});

test('advice 会指出有几天没学', () => {
  const week = report.recentDays(days([[0, 3, 10, 9], [-1, 2, 5, 4]]), { now: NOW });
  const tips = report.advice(report.summarize(week), week);
  const text = tips.map((t) => t.text).join('|');
  assert.match(text, /5 天没有学习记录/);
});

test('advice 正确率高时说扎实', () => {
  const week = report.recentDays(days([[0, 3, 10, 9]]), { now: NOW });
  const tips = report.advice(report.summarize(week), week);
  assert.ok(tips.some((t) => t.tone === 'good' && /扎实/.test(t.text)));
});

test('advice 正确率低时建议放慢', () => {
  const week = report.recentDays(days([[0, 6, 20, 8]]), { now: NOW });
  const tips = report.advice(report.summarize(week), week);
  assert.ok(tips.some((t) => t.tone === 'tip' && /放慢/.test(t.text)));
});

test('advice 在空周只给一句话，不刷屏', () => {
  const week = report.recentDays(null, { now: NOW });
  const tips = report.advice(report.summarize(week), week);
  assert.equal(tips.length, 1);
});

test('柱状图比例归一到 0~1，且只看学习量不埋没复习日', () => {
  // 只复习不学新字的那天，柱子不能是空的
  const week = report.withRatios(report.recentDays(days([
    [0, 0, 40, 36],
    [-1, 10, 0, 0],
  ]), { now: NOW }));
  const today = week[6];
  assert.ok(today.active, '复习日算活跃');
  assert.ok(today.ratio > 0, '只复习的日子柱子不能是 0');
});

test('有活动但量很小时给最小高度，否则柱子看不见', () => {
  const week = report.withRatios(report.recentDays(days([
    [0, 100, 0, 0],
    [-1, 1, 0, 0],
  ]), { now: NOW }));
  assert.ok(week[5].ratio >= 0.08, '1 个字相对 100 个字，也得看得见');
});

test('全空时比例是 0，不会除零', () => {
  const week = report.withRatios(report.recentDays(null, { now: NOW }));
  week.forEach((d) => assert.equal(d.ratio, 0));
});

test('build 一次给齐页面要的东西', () => {
  const r = report.build(days([[0, 3, 10, 8]]), { now: NOW });
  assert.equal(r.week.length, 7);
  assert.ok(r.sum);
  assert.equal(typeof r.headline, 'string');
  assert.ok(Array.isArray(r.advice));
});

/**
 * 三端黄金值。
 *
 * 这一组数字是拿同一份输入在三个平台的实现里各跑一遍、逐字比对后钉下来的
 * （小程序 / Android / iOS 输出完全一致）。改任何一端的周报口径，这里会红。
 *
 * 输入故意留了一天（前天）没有数据，把「缺数据 ≠ 0 分」这条也钉进去。
 */
const GOLDEN_DAYS = (() => {
  const now = new Date(2026, 10, 3);
  const pad = (n) => String(n).padStart(2, '0');
  const key = (off) => {
    const d = new Date(now.getTime());
    d.setDate(d.getDate() - off);
    return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate());
  };
  const out = {};
  [[0, 5, 12, 10], [1, 4, 10, 9], [3, 6, 14, 12],
   [4, 3, 6, 6], [5, 2, 4, 3], [6, 4, 8, 7]].forEach(([o, l, a, c]) => {
    out[key(o)] = { learned: l, answers: a, correct: c };
  });
  return out;
})();

test('三端黄金值：headline', () => {
  assert.equal(report.build(GOLDEN_DAYS, { now: NOW }).headline, '这周来了 6 天，很稳');
});

test('三端黄金值：汇总数字', () => {
  const { sum } = report.build(GOLDEN_DAYS, { now: NOW });
  assert.equal(sum.learned, 24);
  assert.equal(sum.answers, 54);
  assert.equal(sum.correct, 47);
  assert.equal(sum.accuracy, 87);
  assert.equal(sum.activeDays, 6);
  assert.equal(sum.empty, false);
});

test('三端黄金值：逐日学习量与柱高', () => {
  const { week } = report.build(GOLDEN_DAYS, { now: NOW });
  assert.deepEqual(week.map((d) => d.learned), [4, 2, 3, 6, 0, 4, 5]);
  // 前天（索引 4）缺数据 → 没有柱子。这一条就是「缺数据 ≠ 0 分」的可见形式
  assert.deepEqual(week.map((d) => d.ratio), [0.67, 0.33, 0.5, 1, 0, 0.67, 0.83]);
});

test('三端黄金值：三条建议逐字一致', () => {
  const { advice } = report.build(GOLDEN_DAYS, { now: NOW });
  assert.deepEqual(advice.map((a) => a.tone + ':' + a.text), [
    'good:这周认识了 24 个字，平均每天 4 个。',
    'good:答题正确率 87%，很扎实。',
    'plain:有 1 天没有学习记录。每天固定一个时间学，比一次学很久有用。',
  ]);
});

test('三端黄金值：结论文案', () => {
  // 小程序放在页面里、Android/iOS 收进纯逻辑层，但输出必须逐字一致
  const { sum } = report.build(GOLDEN_DAYS, { now: NOW });
  const parts = [];
  if (sum.learned > 0) parts.push(`认识 ${sum.learned} 个字`);
  if (sum.answers > 0) parts.push(`答题 ${sum.answers} 道`);
  if (sum.activeDays > 0) parts.push(`来了 ${sum.activeDays} 天`);
  assert.equal('这周' + parts.join('，'), '这周认识 24 个字，答题 54 道，来了 6 天');
});
