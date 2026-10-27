const catalog = require('../../utils/catalog');
const progress = require('../../utils/progress');
const plan = require('../../utils/plan');
const sessionUtil = require('../../utils/session');
const day = require('../../utils/day');
const routes = require('../../utils/routes');

Page({
  data: {
    dueCount: 0,
    today: { answers: 0, rate: 0 },
    wrongCount: 0,
    heroChar: '字',
    books: [],
    bookName: '一年级上册',
    recentChars: [],
    writeChar: '',
    days: [],
  },

  onShow() {
    this.refresh();
  },

  refresh() {
    const settings = progress.getSettings();
    const bookId = settings.book || catalog.defaultBook();
    const book = catalog.getBook(bookId);
    const due = progress.allDue();
    const today = progress.getTodayStats();
    const books = catalog.getBooks().map((b) => {
      const p = plan.bookProgress(progress, b.id);
      return { id: b.id, name: b.short, learned: p.learned, chars: p.total };
    });

    // 最近学过的字：按课文顺序取已学字里靠后的几个
    const learnedChars = catalog.bookChars(bookId).filter((ch) => progress.hasLearned(ch));
    const recent = learnedChars.slice(-8).reverse();
    const recentChars = recent.slice(0, 6).map((ch) => {
      const w = progress.getWrite(ch);
      return { ch, stars: w ? w.stars || 0 : 0 };
    });
    const writeChar = recent.length ? recent[Math.floor(Math.random() * recent.length)] : catalog.bookChars(bookId)[0];

    const days = progress.recentDays(7).map((d) => ({
      key: d.key,
      label: d.label,
      answers: d.answers,
      h: Math.min(100, Math.round((d.answers / 12) * 100)),
    }));

    this.setData({
      dueCount: due.length,
      today: { answers: today.answers, rate: progress.getAccuracyToday() },
      wrongCount: progress.wrongCount(),
      heroChar: due.length ? due[0] : writeChar,
      books,
      bookName: book ? book.name : '',
      recentChars,
      writeChar,
      days,
    });
  },

  onReview() {
    if (!this.data.dueCount) {
      wx.switchTab({ url: '/pages/index/index' });
      return;
    }
    const app = getApp();
    app.globalData.session = sessionUtil.buildSession('review', {});
    wx.navigateTo({ url: '/pages/quiz/quiz?from=practice' });
  },

  onWrong() {
    if (!this.data.wrongCount) {
      wx.showToast({ title: '还没有错题，真棒', icon: 'none' });
      return;
    }
    wx.navigateTo({ url: '/pages/wrong/wrong' });
  },

  onFree() {
    const app = getApp();
    app.globalData.session = sessionUtil.buildSession('free', {});
    wx.navigateTo({ url: '/pages/quiz/quiz?from=practice' });
  },

  onBookPractice(e) {
    const id = e.currentTarget.dataset.id;
    const app = getApp();
    app.globalData.session = sessionUtil.buildSession('free', { book: id });
    wx.navigateTo({ url: '/pages/quiz/quiz?from=practice' });
  },

  onWriteRandom() {
    this.openWrite(this.data.writeChar);
  },

  onWriteChar(e) {
    this.openWrite(e.currentTarget.dataset.ch);
  },

  openWrite(ch) {
    if (!ch) {
      wx.showToast({ title: '先学几个字吧', icon: 'none' });
      return;
    }
    wx.navigateTo({ url: routes.writeUrl(ch) });
  },

  onWriteHint() {
    wx.showToast({ title: '描红会帮你检查笔顺哦', icon: 'none' });
  },
});
