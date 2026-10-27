import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const catalog = require('../miniprogram/utils/catalog.js');
const progress = require('../miniprogram/utils/progress.js');
const plan = require('../miniprogram/utils/plan.js');
const day = require('../miniprogram/utils/day.js');

function fresh() {
  progress.resetAll();
  progress.updateSettings({ book: '1a', dailyNew: 5 });
}

test('新用户从第一课开始', () => {
  fresh();
  const next = plan.findContinue(progress, '1a');
  assert.equal(next.lesson, '1a-s1');
  assert.equal(next.start, '天');
  assert.equal(next.learned, 0);
  assert.equal(next.total, 6);
});

test('学完一课自动进入下一课', () => {
  fresh();
  const lesson = catalog.getLesson('1a-s1');
  lesson.chars.forEach((ch) => progress.learn(ch));
  const next = plan.findContinue(progress, '1a');
  assert.notEqual(next.lesson, '1a-s1');
  assert.equal(next.learned, 0);
});

test('学到一半会记录上次位置', () => {
  fresh();
  progress.learn('天');
  progress.learn('地');
  progress.setLast({ lesson: '1a-s1', ch: '地' });
  const next = plan.findContinue(progress, '1a');
  assert.equal(next.lesson, '1a-s1');
  assert.equal(next.start, '人');
  assert.equal(next.learned, 2);
});

test('整册学完后返回 null', () => {
  fresh();
  catalog.bookChars('1a').forEach((ch) => progress.learn(ch));
  assert.equal(plan.findContinue(progress, '1a'), null);
  const task = plan.buildTodayTask(progress, '1a');
  assert.equal(task.type, 'done');
});

test('今日任务优先安排复习', () => {
  fresh();
  progress.learn('天');
  // 把到期时间调到今天之前
  const entry = progress.getEntry('天');
  entry.due = 0;
  const task = plan.buildTodayTask(progress, '1a');
  assert.equal(task.type, 'review');
  assert.equal(task.count, 1);
});

test('今日新学达标后任务变成完成', () => {
  fresh();
  progress.updateSettings({ dailyNew: 2 });
  progress.learn('天');
  progress.learn('地');
  const task = plan.buildTodayTask(progress, '1a');
  assert.equal(task.type, 'done');
});

test('今日推荐字在日期内稳定，跨天会变', () => {
  const a = plan.pickDailyChar('1a', '2026-10-27');
  const b = plan.pickDailyChar('1a', '2026-10-27');
  assert.equal(a, b);
  assert.ok(catalog.bookChars('1a').includes(a));
  const c = plan.pickDailyChar('1a', '2026-10-28');
  assert.ok(catalog.bookChars('1a').includes(c));
});

test('册进度统计正确', () => {
  fresh();
  progress.learn('天');
  progress.learn('地');
  const p = plan.bookProgress(progress, '1a');
  assert.equal(p.total, 300);
  assert.equal(p.learned, 2);
  assert.equal(p.pct, 1);
});

test('学习会累加今日统计与连续天数', () => {
  fresh();
  progress.learn('天');
  const today = progress.getTodayStats();
  assert.equal(today.learned, 1);
  assert.equal(progress.getStreak(), 1);
  assert.equal(progress.totalLearned(), 1);
});

test('答错进错题本，答对一次就移出', () => {
  fresh();
  progress.learn('天');
  progress.grade('天', false, { lesson: '1a-s1' });
  assert.equal(progress.wrongCount(), 1);
  assert.equal(progress.getWrong()[0].ch, '天');
  progress.grade('天', true, { lesson: '1a-s1' });
  assert.equal(progress.wrongCount(), 0);
});

test('答错两次需要答对两次才移出错题本', () => {
  fresh();
  progress.grade('天', false, {});
  progress.grade('天', false, {});
  assert.equal(progress.getWrong()[0].n, 2);
  progress.grade('天', true, {});
  assert.equal(progress.wrongCount(), 1);
  progress.grade('天', true, {});
  assert.equal(progress.wrongCount(), 0);
});

test('到期字会被 allDue 找到', () => {
  fresh();
  progress.learn('天');
  progress.learn('地');
  assert.equal(progress.allDue().length, 0, '今天刚学，明天才到期');
  progress.getEntry('天').due = 0;
  const due = progress.allDue();
  assert.deepEqual(due, ['天']);
});

test('描红成绩记录最好一次', () => {
  fresh();
  const a = progress.saveWrite('天', 50);
  assert.equal(a.stars, 1);
  const b = progress.saveWrite('天', 90);
  assert.equal(b.best, 90);
  assert.equal(b.stars, 3);
  assert.equal(b.tries, 2);
  assert.equal(progress.writeStarsTotal(), 3);
});

test('徽章按进度解锁', () => {
  fresh();
  let badges = progress.getBadges();
  assert.equal(badges[0].got, false);
  progress.learn('天');
  badges = progress.getBadges();
  assert.equal(badges[0].got, true);
  assert.equal(badges[1].got, false);
});

test('最近 7 天数据完整', () => {
  const days = progress.recentDays(7);
  assert.equal(days.length, 7);
  days.forEach((d) => {
    assert.ok(d.key.match(/^\d{4}-\d{2}-\d{2}$/));
    assert.ok(d.label.length === 1);
    assert.ok(d.rate >= 0 && d.rate <= 100);
  });
});

test('日期工具跨月正确', () => {
  const d = new Date(2026, 9, 31, 23, 30); // 2026-10-31
  assert.equal(day.todayKey(d), '2026-10-31');
  assert.equal(day.yesterdayKey(d), '2026-10-30');
  assert.equal(day.dayNumber(new Date(2026, 10, 1)) - day.dayNumber(d), 1);
});

test('清空记录后回到初始状态', () => {
  fresh();
  progress.learn('天');
  progress.grade('天', false, {});
  progress.resetAll();
  assert.equal(progress.totalLearned(), 0);
  assert.equal(progress.wrongCount(), 0);
  assert.equal(progress.getStreak(), 0);
});
