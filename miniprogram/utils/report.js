/**
 * 学习周报：把 `stats.days` 里逐日攒下的数据变成家长看得懂的报告。
 *
 * ## 为什么值得单独做一页
 *
 * `stats.days` 从第一个版本起就在逐日记录 `{learned, answers, correct}`，
 * 但它只被「活跃天数」一个徽章间接用过一次——数据一直在攒，从来没被读过。
 * 对家长来说，「今天学了几个字」在首页能看到，「这一周怎么样」看不到，
 * 而那才是他们真正关心的粒度。
 *
 * ## 为什么是「最近 7 天」而不是「本周一到周日」
 *
 * 日历周有个很难受的副作用：周一早上打开，整周几乎全是空的，看起来像
 * 「什么都没做」。滚动 7 天永远是「最近这一周」，任何时候打开都有意义。
 *
 * 代价是同一个字可能被算进两周，但周报是给家长看趋势的，不是做账。
 *
 * ## 数据可能缺失
 *
 * 用户可能中间几天没用，`stats.days` 里就没有那天的键——**不能当成 0 分**，
 * 要区分「那天没学」和「那天学了但没答对」。所以缺的天填 `active: false`，
 * 而不是 `accuracy: 0`。
 */

const day = require('./day');

/** 一周按周一→周日排，和家长的习惯一致（而不是周日打头） */
const WEEKDAYS = ['一', '二', '三', '四', '五', '六', '日'];

/**
 * 取最近 N 天的逐日数据。
 *
 * @param {object} daysStats `stats.days`，形如 { '2026-11-03': {learned, answers, correct} }
 * @param {object} opts { span, now }
 * @returns {Array} 从最早到最近，每项 { key, daysAgo, weekday, date, learned, answers, correct, accuracy, active }
 *   `daysAgo` 是「几天前」，0 = 今天。不用负偏移是为了避开 `-0`
 *   （JS 里 `-0 !== 0`，直接拿去比较会莫名其妙地失败）。
 */
function recentDays(daysStats, opts) {
  const o = opts || {};
  const span = o.span > 0 ? o.span : 7;
  const now = o.now || new Date();
  const out = [];
  // 从 span-1 天前走到今天，保证最后一项是今天
  for (let i = span - 1; i >= 0; i--) {
    const d = new Date(now.getTime());
    d.setDate(d.getDate() - i);
    const key = day.todayKey(d);
    const rec = (daysStats && daysStats[key]) || null;
    const learned = rec ? rec.learned || 0 : 0;
    const answers = rec ? rec.answers || 0 : 0;
    const correct = rec ? rec.correct || 0 : 0;
    out.push({
      key,
      daysAgo: i,
      // 周一=0 … 周日=6。JS 的 getDay() 是周日=0，要转
      weekday: WEEKDAYS[(d.getDay() + 6) % 7],
      date: day.dateLabel(d),
      learned,
      answers,
      correct,
      // 一题没答时不算准确率——记成 0% 会让家长以为全错
      accuracy: answers > 0 ? Math.round((correct / answers) * 100) : null,
      active: learned > 0 || answers > 0,
    });
  }
  return out;
}

/**
 * 汇总一周。
 *
 * @returns {object} { learned, answers, correct, accuracy, activeDays, span, best, rest }
 */
function summarize(week) {
  const list = week || [];
  let learned = 0;
  let answers = 0;
  let correct = 0;
  let activeDays = 0;
  let best = null;

  list.forEach((d) => {
    learned += d.learned;
    answers += d.answers;
    correct += d.correct;
    if (d.active) activeDays += 1;
    // 「最好的一天」按学习量算，答题量作为平手时的次序
    if (d.active && (!best || d.learned > best.learned
      || (d.learned === best.learned && d.answers > best.answers))) {
      best = d;
    }
  });

  return {
    learned,
    answers,
    correct,
    // 整周没答题就没有准确率，不是 0%
    accuracy: answers > 0 ? Math.round((correct / answers) * 100) : null,
    activeDays,
    span: list.length,
    best,
    // 完全没动过的一周要能被识别出来，好给一句鼓励而不是一张空表
    empty: learned === 0 && answers === 0,
  };
}

/**
 * 给孩子看的一句话。
 *
 * 有意写得短、可读完：周报的读者是家长，但这句是念给孩子听的。
 * 不用「正确率 87%」这种数字，孩子对它没有感觉。
 */
function headline(sum) {
  if (sum.empty) return '这周还没开始，今天写一个字就开张啦';
  if (sum.activeDays >= 7) return '整整七天没断过，太厉害了';
  if (sum.activeDays >= 5) return '这周来了 ' + sum.activeDays + ' 天，很稳';
  if (sum.activeDays >= 3) return '这周来了 ' + sum.activeDays + ' 天，继续保持';
  return '这周来了 ' + sum.activeDays + ' 天，明天再来一次就更好';
}

/**
 * 给家长的分析。比 headline 具体，可以提数字。
 *
 * @returns {Array<{tone: string, text: string}>} tone: good | tip | plain
 */
function advice(sum, week) {
  const out = [];
  const list = week || [];

  if (sum.empty) {
    out.push({ tone: 'plain', text: '这一周还没有学习记录。每天 5 分钟，先从「每日任务」开始。' });
    return out;
  }

  if (sum.learned > 0) {
    out.push({
      tone: 'good',
      text: '这周认识了 ' + sum.learned + ' 个字' + (sum.activeDays > 0
        ? '，平均每天 ' + Math.round((sum.learned / sum.activeDays) * 10) / 10 + ' 个'
        : '') + '。',
    });
  }

  if (sum.accuracy != null) {
    if (sum.accuracy >= 85) {
      out.push({ tone: 'good', text: '答题正确率 ' + sum.accuracy + '%，很扎实。' });
    } else if (sum.accuracy >= 65) {
      out.push({ tone: 'plain', text: '答题正确率 ' + sum.accuracy + '%，还有几个字没记牢。' });
    } else {
      out.push({ tone: 'tip', text: '答题正确率 ' + sum.accuracy + '%，建议放慢速度，多复习几次再往下学。' });
    }
  }

  // 中断过就说中断——这是家长最需要知道的，不然一周下来会以为孩子天天在学
  const missing = list.filter((d) => !d.active);
  if (missing.length > 0 && missing.length < list.length) {
    out.push({
      tone: 'plain',
      text: '有 ' + missing.length + ' 天没有学习记录。每天固定一个时间学，比一次学很久有用。',
    });
  }

  // 学习量和正确率都在高位时，提醒往下走
  if (sum.learned >= 35 && sum.accuracy != null && sum.accuracy >= 85) {
    out.push({ tone: 'good', text: '进度和正确率都不错，可以试试「识字量测试」看看现在到了多少。' });
  }

  return out;
}

/**
 * 把一周的数值缩到 0~1，给柱状图用。
 *
 * WXML 里没有 Math，百分比必须在 JS 里算好。
 *
 * @returns {Array} 每项多一个 `ratio`（0~1）
 */
function withRatios(week) {
  const list = week || [];
  // 按学习量和答题量的较大者归一：只看学习量的话，
  // 「今天复习了 30 道题」会画成一根空柱子
  let max = 0;
  list.forEach((d) => {
    max = Math.max(max, d.learned, Math.ceil(d.answers / 4));
  });
  return list.map((d) => {
    const v = Math.max(d.learned, Math.ceil(d.answers / 4));
    // 有活动但数值很小的时候给个最小高度，否则柱子是 0 像素看不见
    const ratio = max === 0 ? 0 : Math.max(v / max, d.active ? 0.08 : 0);
    return Object.assign({}, d, { ratio: Math.round(ratio * 100) / 100 });
  });
}

/**
 * 一次算好整份周报，页面直接 setData 就够。
 */
function build(daysStats, opts) {
  const week = withRatios(recentDays(daysStats, opts));
  const sum = summarize(week);
  return {
    week,
    sum,
    headline: headline(sum),
    advice: advice(sum, week),
  };
}

module.exports = {
  WEEKDAYS,
  recentDays,
  summarize,
  headline,
  advice,
  withRatios,
  build,
};
