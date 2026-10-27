const catalog = require('../../utils/catalog');
const progress = require('../../utils/progress');

Page({
  data: {
    learned: 0,
    mastered: 0,
    pct: 0,
    streak: 0,
    days: 0,
    writeStars: 0,
    badges: [],
    badgeGot: 0,
    settings: {},
    dailyNew: 5,
    dailyOptions: [3, 5, 8, 10],
    book: '1a',
    books: [],
    showPinyin: true,
    wrongCount: 0,
    version: '1.0.0',
  },

  onShow() {
    this.refresh();
  },

  refresh() {
    const settings = progress.getSettings();
    const learned = progress.totalLearned();
    const total = catalog.getAllChars().length;
    const badges = progress.getBadges();
    const days = progress.activeDays();
    this.setData({
      learned,
      mastered: progress.totalMastered(),
      pct: Math.round((learned / total) * 100),
      streak: progress.getStreak(),
      days,
      writeStars: progress.writeStarsTotal(),
      badges,
      badgeGot: badges.filter((b) => b.got).length,
      dailyNew: settings.dailyNew || 5,
      book: settings.book || '1a',
      books: catalog.getBooks().map((b) => ({ id: b.id, short: b.short, name: b.name })),
      showPinyin: settings.showPinyin !== false,
      wrongCount: progress.wrongCount(),
    });
  },

  onDaily(e) {
    const n = Number(e.currentTarget.dataset.n);
    progress.updateSettings({ dailyNew: n });
    this.refresh();
  },

  onBook(e) {
    const id = e.currentTarget.dataset.id;
    progress.updateSettings({ book: id });
    this.refresh();
  },

  onPinyin(e) {
    progress.updateSettings({ showPinyin: !!e.detail.value });
    this.refresh();
  },

  onWrong() {
    wx.navigateTo({ url: '/pages/wrong/wrong' });
  },

  onAbout() {
    wx.navigateTo({ url: '/pages/about/about' });
  },

  onReset() {
    wx.showModal({
      title: '清空学习记录？',
      content: '所有学习进度、错题和描红记录都会被删除，且无法恢复。',
      confirmText: '确定清空',
      confirmColor: '#df6248',
      success: (res) => {
        if (res.confirm) {
          progress.resetAll();
          this.refresh();
          wx.showToast({ title: '已清空', icon: 'none' });
        }
      },
    });
  },
});
