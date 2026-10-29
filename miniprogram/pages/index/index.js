const catalog = require('../../utils/catalog');
const progress = require('../../utils/progress');
const plan = require('../../utils/plan');
const day = require('../../utils/day');
const routes = require('../../utils/routes');
const navMetrics = require('../../utils/nav-metrics');

const BOOK_COLORS = {
  '1a': '#e9a93c',
  '1b': '#df8a4a',
  '2a': '#4f9e8d',
  '2b': '#5a8fbf',
  '3a': '#9b7fb8',
  '3b': '#b8763f',
  '4a': '#6f8fb8',
  '4b': '#3f7d6a',
};

const GRADE_TEXT = { 1: '一年级', 2: '二年级', 3: '三年级', 4: '四年级', 5: '五年级', 6: '六年级' };

/** 首页副标题的年级范围：按实际册次算，避免加年级后写死的文案变成假的 */
function gradeSpanText() {
  const grades = catalog.getBooks().map((b) => b.grade);
  if (!grades.length) return '';
  return `${GRADE_TEXT[Math.min(...grades)]}到${GRADE_TEXT[Math.max(...grades)]}`;
}

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
    navHeight: navMetrics.DEFAULT_NAV_HEIGHT,
    capsuleReserve: 0,
  },

  onLoad() {
    const settings = progress.getSettings();
    // 首页是自定义导航（navigationStyle: custom），页面从屏幕顶端开始画。
    // 微信右上角的胶囊按钮是系统浮层，会压住页面内容，所以必须按它的实际位置
    // 把「状态栏 + 导航带」整条让出来，否则右上角的连续打卡药丸会被盖住。
    const metrics = navMetrics.measureHeader(wx);
    this.setData({
      currentBook: settings.book || '1a',
      statusBarHeight: metrics.statusBarHeight,
      navHeight: metrics.navHeight,
      capsuleReserve: metrics.capsuleReserve,
      gradeSpan: gradeSpanText(),
    });
    // 提前把当前这册的笔顺分包下下来（替代 app.json 的 preloadRule，
    // 静态规则会把三个分包一起预载，超过 2MB 上限）
    routes.preload(settings.book || '1a');
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
        gradeText: GRADE_TEXT[b.grade] || b.grade + '年级',
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
      title: '小小识字家 —— 小学识字练习',
      path: '/pages/index/index',
    };
  },
});
