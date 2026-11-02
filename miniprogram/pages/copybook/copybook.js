/**
 * 我的字帖：把写过的字排成一张字帖。
 *
 * 为什么值得单独做一页：现在的徽章体系几乎全是「认识 N 个字」这一个维度，
 * 而描红记录存了 best / stars / tries / last 四个字段却只在单字页显示三颗星。
 * 「我写了一百个字」和「我认识一百个字」对孩子来说是两回事，
 * 后者是看得懂，前者是写得出来——后者更难，也更值得被看见。
 *
 * 与 iOS `CopybookPageView`、Android `CopybookPage` 对应。
 */
const progress = require('../../utils/progress');
const catalog = require('../../utils/catalog');
const routes = require('../../utils/routes');

Page({
  data: {
    all: [],
    shown: [],
    total: 0,
    starsTotal: 0,
    hist: { 0: 0, 1: 0, 2: 0, 3: 0 },
    chips: [],
    filter: -1,   // -1 = 全部
    empty: true,
  },

  onShow() {
    this.refresh();
  },

  refresh() {
    const all = progress.allWriteRecords();
    const hist = progress.writeStarsHistogram();

    // 只显示有内容的档位，避免一排「0」占地方
    const chips = [{ key: -1, title: '全部', count: all.length }];
    [3, 2, 1, 0].forEach((s) => {
      if (hist[s] > 0) {
        chips.push({ key: s, title: s === 0 ? '待练' : s + ' 星', count: hist[s] });
      }
    });

    const filter = this.data.filter;
    const shown = filter === -1 ? all : all.filter((x) => x.record.stars === filter);

    this.setData({
      all,
      shown: shown.map((x) => ({
        ch: x.ch,
        best: x.record.best,
        stars: x.record.stars,
        // WXML 里没法做三元嵌套比较，先把样式类算好
        scoreClass: x.record.best >= 85 ? 'good' : x.record.best >= 65 ? 'mid' : 'low',
        starList: [1, 2, 3].map((i) => i <= x.record.stars),
      })),
      total: progress.writeCount(),
      starsTotal: progress.writeStarsTotal(),
      hist,
      chips,
      empty: all.length === 0,
    });
  },

  onFilter(e) {
    const key = Number(e.currentTarget.dataset.key);
    this.setData({ filter: key }, () => this.refresh());
  },

  onChar(e) {
    const ch = e.currentTarget.dataset.ch;
    routes.preload(progress.getSettings().book || catalog.defaultBook());
    wx.navigateTo({ url: routes.writeUrl(ch) });
  },

  onStart() {
    const book = progress.getSettings().book || catalog.defaultBook();
    const first = catalog.bookChars(book)[0];
    if (!first) return;
    routes.preload(book);
    wx.navigateTo({ url: routes.writeUrl(first) });
  },
});
