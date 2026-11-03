const catalog = require('../../utils/catalog');
const progress = require('../../utils/progress');
const plan = require('../../utils/plan');
const sessionUtil = require('../../utils/session');
const day = require('../../utils/day');
const dictation = require('../../utils/dictation');
const words = require('../../utils/words');
const routes = require('../../utils/routes');

Page({
  data: {
    dueCount: 0,
    today: { answers: 0, rate: 0 },
    wrongCount: 0,
    polyCount: 0,
    dictLevels: dictation.LEVELS,
    wordCount: 0,
    homoCount: 0,
    radicalCount: 0,
    similarCount: 0,
    heroChar: '字',
    books: [],
    bookName: '',
    recentChars: [],
    /** 笔画薄弱点：前几个「这个字的第 N 笔写不好」 */
    weakStrokes: [],
    weakCount: 0,
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

    // 笔画薄弱点：判分本来每笔都会算出「为什么不过」，之前只拼一句提示就丢了。
    // 取失败次数最多的前 4 个，够提示「下次该练哪一笔」而不至于变成一张报表。
    const weakAll = progress.allWeakStrokes();
    this.setData({
      weakStrokes: weakAll.slice(0, 4).map((w) => ({
        key: w.ch + ':' + w.index,
        ch: w.ch,
        index: w.index,
        fails: w.fails,
      })),
      weakCount: weakAll.length,
      dueCount: due.length,
      today: { answers: today.answers, rate: progress.getAccuracyToday() },
      wrongCount: progress.wrongCount(),
      polyCount: catalog.polyphones(book ? book.id : catalog.defaultBook()).length,
      wordCount: words.bookWordCount(book ? book.id : catalog.defaultBook()),
      homoCount: catalog.homophoneChars(book ? book.id : catalog.defaultBook()).length,
      radicalCount: catalog.bookRadicals(book ? book.id : catalog.defaultBook()).length,
      similarCount: catalog.bookSimilarChars(book ? book.id : catalog.defaultBook()).length,
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

  /** 部首：查字法是低年级语文园地的正式内容 */
  onRadical() {
    const app = getApp();
    app.globalData.session = sessionUtil.buildSession('radical', {});
    wx.navigateTo({ url: '/pages/quiz/quiz?mode=radical' });
  },

  /** 形近字：长得像的字别写混（未/末、天/夫） */
  onSimilar() {
    if (!this.data.similarCount) {
      wx.showToast({ title: '这一册没有形近字', icon: 'none' });
      return;
    }
    const app = getApp();
    app.globalData.session = sessionUtil.buildSession('similar', {});
    wx.navigateTo({ url: '/pages/quiz/quiz?mode=similar' });
  },

  /** 同音字：一个音有好几个字，练「写哪个」 */
  onHomophone() {
    if (!this.data.homoCount) {
      wx.showToast({ title: '这一册没有同音字组', icon: 'none' });
      return;
    }
    const app = getApp();
    app.globalData.session = sessionUtil.buildSession('homophone', {});
    wx.navigateTo({ url: '/pages/quiz/quiz?mode=homophone' });
  },

  /** 看拼音选词语：题源是课本词语表 */
  onWords() {
    const book = progress.getSettings().book || catalog.defaultBook();
    const app = getApp();
    app.globalData.session = sessionUtil.buildSession('words', { book });
    wx.navigateTo({ url: '/pages/quiz/quiz?mode=words' });
  },

  onDictation(e) {
    const level = e.currentTarget.dataset.level;
    const book = progress.getSettings().book || catalog.defaultBook();
    // 听写页需要笔顺数据，在分包里；先确保分包已预载再跳
    routes.preload(book);
    wx.navigateTo({ url: routes.dictationUrl(book, level) });
  },

  onPolyphone() {
    if (!this.data.polyCount) {
      wx.showToast({ title: '这一册没有多音字', icon: 'none' });
      return;
    }
    const app = getApp();
    app.globalData.session = sessionUtil.buildSession('polyphone', {});
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

  /** 薄弱笔画：直接进那个字的描红，从第一笔重新写一遍 */
  onWeakStroke(e) {
    this.openWrite(e.currentTarget.dataset.ch);
  },

  onWriteHint() {
    wx.showToast({ title: '描红会帮你检查笔顺哦', icon: 'none' });
  },
});
