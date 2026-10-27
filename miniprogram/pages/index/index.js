const catalog = require('../../utils/catalog');
const progress = require('../../utils/progress');
const plan = require('../../utils/plan');
const day = require('../../utils/day');
const routes = require('../../utils/routes');

const BOOK_COLORS = {
  '1a': '#e9a93c',
  '1b': '#df8a4a',
  '2a': '#4f9e8d',
  '2b': '#5a8fbf',
};

const TIPS = [
  '写字前先看清结构，左右、上下、还是独体字？',
  '笔顺有规律：先横后竖，先撇后捺，从上到下，从左到右。',
  '读完拼音再读一遍汉字，让耳朵也记住它。',
  '遇到不认识的字，先看部首猜一猜意思。',
  '每天认 5 个字，一年就是 1800 个。',
  '把新学的字读给爸爸妈妈听，记得更牢。',
];

Page({
  data: {
    greeting: '',
    dateLabel: '',
    weekday: '',
    streak: 0,
    task: { type: 'learn', title: '', desc: '', action: '', count: 0 },
    todayPct: 0,
    dailyNew: 5,
    books: [],
    currentBook: '1a',
    dailyChar: '',
    dailyMeta: null,
    tip: '',
    statusBarHeight: 20,
  },

  onLoad() {
    const settings = progress.getSettings();
    let statusBarHeight = 20;
    try {
      const info = wx.getWindowInfo ? wx.getWindowInfo() : wx.getSystemInfoSync();
      statusBarHeight = info.statusBarHeight || 20;
    } catch (e) {
      statusBarHeight = 20;
    }
    this.setData({ currentBook: settings.book || '1a', statusBarHeight });
    this.refresh();
  },

  onShow() {
    this.refresh();
  },

  refresh() {
    const settings = progress.getSettings();
    const bookId = settings.book || catalog.defaultBook();
    const books = catalog.getBooks().map((b) => {
      const p = plan.bookProgress(progress, b.id);
      return {
        id: b.id,
        name: b.name,
        gradeText: b.grade === 1 ? '一年级' : '二年级',
        chars: p.total,
        learned: p.learned,
        pct: p.pct,
        lessonCount: b.stat.lessons,
        color: BOOK_COLORS[b.id] || '#4f9e8d',
      };
    });
    const task = plan.buildTodayTask(progress, bookId);
    const today = progress.getTodayStats();
    const dailyNew = settings.dailyNew || 5;
    const key = day.todayKey();
    const dailyChar = plan.pickDailyChar(bookId, key);
    const meta = dailyChar ? catalog.getMeta(dailyChar) : null;
    const lessonId = meta ? meta.l : '';
    const lesson = lessonId ? catalog.getLesson(lessonId) : null;

    this.setData({
      greeting: day.greeting(),
      dateLabel: day.dateLabel(),
      weekday: day.weekdayCN(),
      streak: progress.getStreak(),
      task,
      todayPct: Math.min(100, Math.round((today.learned / dailyNew) * 100)),
      dailyNew,
      today,
      books,
      currentBook: bookId,
      dailyChar,
      dailyMeta: meta
        ? {
            py: catalog.readingFor(dailyChar, lessonId),
            desc:
              '部首「' + meta.r + '」· ' + meta.s + ' 笔' + (lesson ? ' · ' + lesson.title : ''),
            words: (meta.w || []).slice(0, 3),
            lesson: lessonId,
          }
        : null,
      tip: TIPS[Math.floor(Math.random() * TIPS.length)],
    });
  },

  onTaskTap() {
    const t = this.data.task;
    if (t.type === 'review') {
      this.startReview();
    } else if (t.type === 'learn') {
      this.startLearn();
    } else {
      wx.switchTab({ url: '/pages/practice/practice' });
    }
  },

  startReview() {
    const app = getApp();
    const due = progress.allDue();
    if (!due.length) {
      wx.showToast({ title: '暂时没有要复习的字', icon: 'none' });
      return;
    }
    app.globalData.session = {
      mode: 'review',
      title: '今日复习',
      chars: due.slice(0, 15),
      book: this.data.currentBook,
      count: Math.min(15, due.length * 2),
    };
    wx.navigateTo({ url: '/pages/quiz/quiz?from=index-review' });
  },

  startLearn() {
    const next = plan.findContinue(progress, this.data.currentBook);
    if (!next) {
      this.openBook(this.data.currentBook);
      return;
    }
    wx.navigateTo({
      url: routes.detailUrl(next.start, next.lesson, 'mode=learn'),
    });
  },

  onBookTap(e) {
    const id = e.currentTarget.dataset.id;
    progress.updateSettings({ book: id });
    this.openBook(id);
  },

  openBook(id) {
    this.setData({ currentBook: id });
    wx.navigateTo({ url: '/pages/unit/unit?book=' + id });
  },

  onOpenDaily() {
    const ch = this.data.dailyChar;
    if (!ch) return;
    wx.navigateTo({
      url: routes.detailUrl(ch, this.data.dailyMeta.lesson),
    });
  },

  onShareAppMessage() {
    return {
      title: '小小识字家 —— 一二年级识字练习',
      path: '/pages/index/index',
    };
  },
});
