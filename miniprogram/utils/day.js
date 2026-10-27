/** 日期工具：以“本地自然日”为单位的编号，方便做间隔复习 */
const DAY_MS = 86400000;

function dayNumber(d) {
  const date = d || new Date();
  return Math.floor((date.getTime() - date.getTimezoneOffset() * 60000) / DAY_MS);
}

function pad(n) {
  return n < 10 ? '0' + n : '' + n;
}

function todayKey(d) {
  const date = d || new Date();
  return date.getFullYear() + '-' + pad(date.getMonth() + 1) + '-' + pad(date.getDate());
}

function yesterdayKey(d) {
  const date = d || new Date();
  return todayKey(new Date(date.getTime() - DAY_MS));
}

function weekdayCN(d) {
  const names = ['日', '一', '二', '三', '四', '五', '六'];
  return '周' + names[(d || new Date()).getDay()];
}

function dateLabel(d) {
  const date = d || new Date();
  return date.getMonth() + 1 + '月' + date.getDate() + '日';
}

function greeting(d) {
  const h = (d || new Date()).getHours();
  if (h < 6) return '夜深了';
  if (h < 11) return '早上好';
  if (h < 14) return '中午好';
  if (h < 18) return '下午好';
  return '晚上好';
}

function dayKeyOf(offsetDays) {
  const d = new Date();
  d.setDate(d.getDate() + offsetDays);
  return todayKey(d);
}

module.exports = {
  DAY_MS,
  dayNumber,
  todayKey,
  yesterdayKey,
  weekdayCN,
  dateLabel,
  greeting,
  dayKeyOf,
};
