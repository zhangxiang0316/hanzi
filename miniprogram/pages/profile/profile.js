const catalog = require('../../utils/catalog');
const progress = require('../../utils/progress');
const profile = require('../../utils/profile');

const GRADE_TEXT = { 1: '一年级', 2: '二年级', 3: '三年级', 4: '四年级', 5: '五年级', 6: '六年级' };

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
    writeCount: 0,
    version: '1.0.0',
    profiles: [],
    profileName: '',
    activeProfileId: '',
    profileCount: 1,
    canAddProfile: true,
  },

  onShow() {
    this.refresh();
  },

  refresh() {
    const settings = progress.getSettings();
    this.setData({
      profiles: profile.list(),
      profileName: profile.active().name,
      activeProfileId: profile.activeId(),
      profileCount: profile.count(),
      canAddProfile: profile.canAdd(),
    });
    const learned = progress.totalLearned();
    const total = catalog.getAllChars().length;
    // 年级范围不能写死"一到三年级"：加四年级后会变成假的。按实际册次算。
    const grades = catalog.getBooks().map((b) => b.grade);
    const gradeSpan = `${GRADE_TEXT[Math.min(...grades)]}到${GRADE_TEXT[Math.max(...grades)]}`;
    // 按每天 5 个新字估算学完所需天数
    const daysNeeded = Math.ceil(total / 5);
    const badges = progress.getBadges();
    const days = progress.activeDays();
    this.setData({
      learned,
      mastered: progress.totalMastered(),
      pct: Math.round((learned / total) * 100),
      total,
      gradeSpan,
      daysNeeded,
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
      writeCount: progress.writeCount(),
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

  onCopybook() {
    wx.navigateTo({ url: '/pages/copybook/copybook' });
  },

  onWrong() {
    wx.navigateTo({ url: '/pages/wrong/wrong' });
  },

  onAbout() {
    wx.navigateTo({ url: '/pages/about/about' });
  },

  /**
   * 切换孩子。
   *
   * 切完必须 `progress.reload()`——存储的键换了前缀，但 progress 里那份
   * 内存状态还是上一个孩子的，不重读会显示「名字换了、数据没变」。
   */
  onSwitchProfile(e) {
    const id = e.currentTarget.dataset.id;
    if (id === profile.activeId()) return;
    if (!profile.setActive(id)) return;
    progress.reload();
    this.refresh();
    wx.showToast({ title: '已切到 ' + profile.active().name, icon: 'none' });
  },

  onAddProfile() {
    if (!profile.canAdd()) {
      wx.showToast({ title: '最多 ' + profile.MAX + ' 个', icon: 'none' });
      return;
    }
    wx.showModal({
      title: '添加一个孩子',
      editable: true,
      placeholderText: '孩子的名字（8 字以内）',
      success: (res) => {
        if (!res.confirm) return;
        const p = profile.add(res.content);
        if (!p) return;
        // 新建后直接切过去：家长的意图就是「给这个孩子开始用」
        profile.setActive(p.id);
        progress.reload();
        this.refresh();
      },
    });
  },

  onRenameProfile() {
    const cur = profile.active();
    wx.showModal({
      title: '改名',
      editable: true,
      content: cur.name,
      placeholderText: '孩子的名字（8 字以内）',
      success: (res) => {
        if (!res.confirm) return;
        if (!profile.rename(cur.id, res.content)) {
          wx.showToast({ title: '名字不能为空', icon: 'none' });
          return;
        }
        this.refresh();
      },
    });
  },

  onRemoveProfile() {
    const cur = profile.active();
    if (profile.count() <= 1) return;
    wx.showModal({
      title: '删除「' + cur.name + '」？',
      content: '这个孩子的学习进度、错题本、描红记录都会一起删掉，不能恢复。',
      confirmText: '删除',
      confirmColor: '#c0503c',
      success: (res) => {
        if (!res.confirm) return;
        const next = profile.remove(cur.id);
        if (next === null) return;
        progress.reload();
        this.refresh();
      },
    });
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
