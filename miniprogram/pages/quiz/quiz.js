const quiz = require('../../utils/quiz');
const progress = require('../../utils/progress');
const sessionUtil = require('../../utils/session');
const catalog = require('../../utils/catalog');

Page({
  data: {
    q: null,
    index: 0,
    total: 0,
    pct: 0,
    feedbackState: '',
    isLast: false,
  },

  onLoad() {
    const app = getApp();
    let session = app.globalData.session;
    if (!session || !session.chars || !session.chars.length) {
      session = sessionUtil.buildSession('free', {});
    }
    app.globalData.session = null;
    this.session = session;
    this.answers = [];
    this.locked = false;

    // 词语模式的题源是课本词语表，和生字表无关，走单独的构建函数
    const built = session.mode === 'words'
      ? quiz.buildWordQuiz({
          book: session.book,
          lesson: session.lesson,
          count: session.count,
          seed: Date.now(),
        })
      : quiz.buildQuiz({
          chars: session.chars,
          book: session.book,
          lesson: session.lesson,
          count: session.count,
          seed: Date.now(),
          // 多音字模式只出多音字题；其余模式用默认题型轮转
          types: session.mode === 'polyphone' ? ['polyphone']
            : session.mode === 'homophone' ? ['homophone']
            : session.mode === 'radical' ? ['radical']
            : session.mode === 'similar' ? ['similar']
            : undefined,
        });
    this.questions = built.questions;
    if (!this.questions.length) {
      wx.showToast({ title: '还没有可以练习的字', icon: 'none' });
      setTimeout(() => wx.navigateBack(), 800);
      return;
    }
    wx.setNavigationBarTitle({ title: session.title || '练一练' });
    this.setData({ total: this.questions.length });
    this.show(0);
  },

  show(i) {
    const q = this.questions[i];
    // 复制一份，避免直接修改缓存的题目对象
    const view = Object.assign({}, q, {
      options: q.options.map((o) => Object.assign({}, o, { state: '' })),
    });
    this.setData({
      q: view,
      index: i,
      pct: Math.round((i / this.questions.length) * 100),
      feedbackState: '',
      isLast: i === this.questions.length - 1,
    });
    this.locked = false;
  },

  onOption(e) {
    if (this.locked) return;
    this.locked = true;
    const value = e.currentTarget.dataset.v;
    const q = this.questions[this.data.index];
    const correct = String(value) === String(q.answer);
    const options = this.data.q.options.map((o) => {
      let state = '';
      if (String(o.v) === String(q.answer)) state = 'correct';
      else if (String(o.v) === String(value)) state = 'wrong';
      return Object.assign({}, o, { state });
    });
    this.setData({
      q: Object.assign({}, this.data.q, { options }),
      feedbackState: correct ? 'ok' : 'no',
    });
    // 词语题的 ch 是整词，不能直接当字喂给 SRS——按词里每个字分别记账，
    // 这样「天空」答错会同时影响「天」和「空」的复习节奏，正是想要的。
    const gradeChars = q.ch && q.ch.length > 1 && !catalog.hasChar(q.ch)
      ? q.ch.split('').filter((c) => catalog.hasChar(c))
      : [q.ch];
    const gradeBook = catalog.hasChar(q.ch) && catalog.getMeta(q.ch)
      ? catalog.getMeta(q.ch).b
      : this.session.book;
    gradeChars.forEach((ch) => progress.grade(ch, correct, { book: gradeBook }));
    this.answers.push({ ch: q.ch, correct, type: q.type, answer: q.answer, picked: value });
    if (correct) {
      wx.vibrateShort && wx.vibrateShort({ type: 'light' });
    }
  },

  onContinue() {
    if (this.data.index + 1 >= this.questions.length) {
      this.finish();
      return;
    }
    this.show(this.data.index + 1);
  },

  finish() {
    const total = this.answers.length;
    const correct = this.answers.filter((a) => a.correct).length;
    progress.recordQuiz(total, correct);
    const wrongChars = [];
    this.answers.forEach((a) => {
      if (a.correct) return;
      // 词语题答错时 a.ch 是一整个词。错题本、错字重练都按单字组织，
      // 所以把词拆成字——这也更符合学习逻辑：词写错了，落点是其中某个字。
      const parts = a.ch && a.ch.length > 1 ? a.ch.split('') : [a.ch];
      parts.forEach((ch) => {
        if (!ch || !catalog.hasChar(ch)) return;
        if (wrongChars.indexOf(ch) < 0) wrongChars.push(ch);
      });
    });
    const app = getApp();
    app.globalData.lastResult = {
      title: this.session.title || '练习',
      mode: this.session.mode,
      total,
      correct,
      rate: total ? Math.round((correct / total) * 100) : 0,
      wrongChars,
      book: this.session.book,
      lesson: this.session.lesson,
      answers: this.answers,
    };
    wx.redirectTo({ url: '/pages/result/result' });
  },

  onExit() {
    if (this.answers.length === 0) {
      wx.navigateBack();
      return;
    }
    wx.showModal({
      title: '先不练了吗？',
      content: '已经答了 ' + this.answers.length + ' 题，离开后进度会保留。',
      confirmText: '继续练',
      cancelText: '离开',
      success: (res) => {
        if (!res.confirm) wx.navigateBack();
      },
    });
  },
});
