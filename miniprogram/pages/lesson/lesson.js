const catalog = require('../../utils/catalog');
const progress = require('../../utils/progress');
const plan = require('../../utils/plan');
const routes = require('../../utils/routes');

Page({
  data: {
    lesson: null,
    bookName: '',
    chars: [],
    pct: 0,
    focus: '',
    nextChar: '',
    started: false,
  },

  onLoad(options) {
    this.lessonId = options.lesson;
    const lesson = catalog.getLesson(this.lessonId);
    if (!lesson) {
      wx.showToast({ title: '找不到这一课', icon: 'none' });
      return;
    }
    const book = catalog.getBook(lesson.book);
    wx.setNavigationBarTitle({ title: lesson.title });
    this.setData({ lesson, bookName: book ? book.short : '' });
    if (options.start) this.setData({ focus: decodeURIComponent(options.start) });
    this.refresh();
  },

  onShow() {
    this.refresh();
  },

  refresh() {
    const lesson = this.data.lesson;
    if (!lesson) return;
    const chars = lesson.chars.map((ch) => {
      const m = catalog.getMeta(ch);
      const entry = progress.getEntry(ch);
      return {
        ch,
        py: catalog.readingFor(ch, this.lessonId),
        word: m && m.w && m.w[0] ? m.w[0].w : '',
        learned: !!(entry && entry.box >= 1),
        mastered: !!(entry && entry.box >= 5),
        due: !!(entry && entry.due <= progress._today()),
      };
    });
    const learned = chars.filter((c) => c.learned).length;
    const nextChar = plan.firstUnlearned(lesson.chars, progress);
    this.setData({
      chars,
      pct: chars.length ? Math.round((learned / chars.length) * 100) : 0,
      nextChar: nextChar || '',
      started: learned > 0,
    });
  },

  onCharTap(e) {
    const ch = e.currentTarget.dataset.ch;
    wx.navigateTo({ url: routes.detailUrl(ch, this.lessonId) });
  },

  onStart() {
    const ch = this.data.nextChar || this.data.lesson.chars[0];
    wx.navigateTo({ url: routes.detailUrl(ch, this.lessonId, 'mode=learn') });
  },
});
