const catalog = require('../../utils/catalog');
const progress = require('../../utils/progress');
const plan = require('../../utils/plan');
const routes = require('../../utils/routes');

const UNIT_COLORS = ['#e9a93c', '#4f9e8d', '#df8a4a', '#5a8fbf', '#8d7cc4', '#cf6f8d', '#6fa96a', '#c98a3f'];

Page({
  data: {
    book: null,
    stat: { learned: 0, total: 0, pct: 0 },
    units: [],
  },

  onLoad(options) {
    this.bookId = options.book || catalog.defaultBook();
    const book = catalog.getBook(this.bookId);
    wx.setNavigationBarTitle({ title: book ? book.name : '选一册' });
    // 用户已经选定册次，这时预载对应分包最准，不会下多余的数据
    routes.preload(this.bookId);
  },

  onShow() {
    this.refresh();
  },

  refresh() {
    const book = catalog.getBook(this.bookId);
    if (!book) return;
    const stat = plan.bookProgress(progress, book.id);
    const units = book.units.map((u, idx) => {
      const lessons = u.lessons.map((lid) => {
        const l = catalog.getLesson(lid);
        const c = plan.countLesson(progress, lid);
        return {
          id: lid,
          no: l.no,
          title: l.title,
          kind: l.kind,
          charCount: c.total,
          learned: c.learned,
          pct: c.total ? Math.round((c.learned / c.total) * 100) : 0,
        };
      });
      let learned = 0;
      let total = 0;
      lessons.forEach((l) => {
        learned += l.learned;
        total += l.charCount;
      });
      return {
        no: u.no,
        title: u.title,
        theme: u.theme,
        lessons,
        charCount: total,
        pct: total ? Math.round((learned / total) * 100) : 0,
        color: UNIT_COLORS[idx % UNIT_COLORS.length],
      };
    });
    this.setData({ book, stat, units });
  },

  onLessonTap(e) {
    const id = e.currentTarget.dataset.id;
    wx.navigateTo({ url: '/pages/lesson/lesson?lesson=' + id });
  },

  onContinue() {
    const next = plan.findContinue(progress, this.bookId);
    if (!next) {
      wx.showToast({ title: '这本已经学完啦', icon: 'none' });
      return;
    }
    wx.navigateTo({ url: '/pages/lesson/lesson?lesson=' + next.lesson + '&start=' + encodeURIComponent(next.start) });
  },

  onPractice() {
    const app = getApp();
    app.globalData.session = {
      mode: 'book',
      title: catalog.getBook(this.bookId).name + ' · 随机练习',
      book: this.bookId,
      count: 10,
    };
    wx.navigateTo({ url: '/pages/quiz/quiz?from=unit' });
  },
});
