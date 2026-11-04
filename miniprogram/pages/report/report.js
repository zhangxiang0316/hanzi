/**
 * 学习周报（家长报告）。
 *
 * 首页告诉你「今天学了几个字」，这一页告诉你「这一周怎么样」——
 * 后者才是家长真正关心的粒度。
 *
 * 数据全来自 `progress` 里已经攒着的 `stats.days`，不新增任何存储。
 * 口径（哪些天算活跃、没答题时正确率怎么显示）都在 `utils/report.js`，
 * 那部分是纯函数，有测试；这里只负责排版。
 */
const report = require('../../utils/report');
const progress = require('../../utils/progress');
const day = require('../../utils/day');

Page({
  data: {
    week: [],
    sum: { learned: 0, answers: 0, accuracy: null, activeDays: 0, empty: true },
    headline: '',
    advice: [],
    verdict: '',
    verdictTone: 'plain',
    todayText: '',
  },

  onShow() {
    const r = report.build(progress.getDaysStats() || {});
    this.setData({
      week: r.week,
      sum: r.sum,
      headline: r.headline,
      advice: r.advice,
      verdict: this.verdictOf(r.sum),
      verdictTone: this.toneOf(r.sum),
      todayText: day.dateLabel() + ' · ' + day.weekdayCN(),
    });
  },

  /**
   * 一句话结论。
   *
   * 家长翻周报先扫结论；数字是佐证，不该是第一眼看到的东西。
   * 措辞只描述**做了什么**，不评价孩子——「这周学了 23 个字」比
   * 「学习不够努力」有用得多。
   */
  verdictOf(sum) {
    if (sum.empty) return '这周还没有学习记录';
    const parts = [];
    if (sum.learned > 0) parts.push(`认识 ${sum.learned} 个字`);
    if (sum.answers > 0) parts.push(`答题 ${sum.answers} 道`);
    if (sum.activeDays > 0) parts.push(`来了 ${sum.activeDays} 天`);
    return '这周' + parts.join('，');
  },

  toneOf(sum) {
    if (sum.empty) return 'plain';
    if (sum.activeDays >= 5 && (sum.accuracy == null || sum.accuracy >= 80)) return 'good';
    if (sum.activeDays <= 2) return 'tip';
    return 'plain';
  },
});
