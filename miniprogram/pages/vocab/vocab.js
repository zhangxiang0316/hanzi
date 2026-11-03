/**
 * 识字量测试页。
 *
 * 分三步：开始页 → 逐题作答 → 结果页。三步同页切换（`stage`），
 * 不用三个页面：这是个一次性流程，跳来跳去反而会让孩子误触返回到中间态。
 */
const vocab = require('../../utils/vocab');
const catalog = require('../../utils/catalog');
const progress = require('../../utils/progress');

Page({
  data: {
    stage: 'intro', // intro | test | result
    qIndex: 0,
    total: 0,
    q: null,
    bookName: '',
    pct: 0,
    // 结果
    size: 0,
    sizeText: '0',
    verdict: '',
    groups: [],
    stopName: '',
    answered: 0,
  },

  onLoad() {
    this.answers = [];
    this.test = null;
  },

  onStart() {
    // 每次开测用新 seed：反复测同一套题，孩子会把答案背下来
    this.test = vocab.buildTest({ seed: Date.now() });
    this.answers = [];
    this.setData({ stage: 'test', total: this.test.total }, () => this.show(0));
  },

  show(i) {
    const q = this.test.groups
      .reduce((all, g) => all.concat(g.questions), [])
      [i];
    if (!q) return this.finish();
    const book = catalog.getBook(q.book);
    // WXML 里没有 Math，进度百分比要在 JS 算好
    this.setData({
      qIndex: i,
      pct: Math.round((i / this.data.total) * 100),
      q: Object.assign({}, q, {
        options: q.options.map((o) => Object.assign({}, o, { state: '' })),
      }),
      bookName: book ? book.name : '',
    });
  },

  onPick(e) {
    const v = e.currentTarget.dataset.v;
    const q = this.data.q;
    if (!q || q.picked) return;
    const correct = v === q.answer;
    // 答错要立刻显示正确答案——这是测验，不是练习，
    // 孩子没有第二次机会，必须当场知道这个字读什么
    const options = q.options.map((o) => Object.assign({}, o, {
      state: o.v === q.answer ? 'right' : (o.v === v ? 'wrong' : ''),
    }));
    this.setData({ q: Object.assign({}, q, { options, picked: v }) });
    this.answers.push({ ch: q.ch, correct });

    wx.vibrateShort && wx.vibrateShort({ type: correct ? 'light' : 'medium' });
    setTimeout(() => this.next(), correct ? 420 : 900);
  },

  next() {
    const i = this.data.qIndex + 1;
    // 一册问完就判一次要不要停：正确率过低的册次之后不必再问，
    // 问下去只是让孩子反复受挫
    const justFinished = this.test.groups.find(
      (g) => g.start + g.questions.length === i
    );
    if (justFinished) {
      const est = vocab.estimate(this.test, this.answers);
      if (est.groups.some((g) => g.book === justFinished.book && g.asked >= justFinished.questions.length
        && g.rate < vocab.STOP_RATE)) {
        return this.finish();
      }
    }
    if (i >= this.data.total) return this.finish();
    this.show(i);
  },

  finish() {
    const est = vocab.estimate(this.test, this.answers);
    const stopGroup = est.groups.find((g) => g.book === est.stopBook);
    this.setData({
      stage: 'result',
      size: est.size,
      sizeText: vocab.sizeLabel(est.size),
      verdict: vocab.verdict(est.size),
      groups: est.groups.filter((g) => g.asked > 0),
      stopName: stopGroup ? stopGroup.name : '',
      answered: est.answered,
    });
    // 记一笔：结果页之外，家长在「我的」里也能看到上次测出来多少
    progress.setVocabSize(est.size);
  },

  onRestart() {
    this.setData({ stage: 'intro', qIndex: 0, q: null, groups: [] });
    this.answers = [];
  },

  onDone() {
    wx.navigateBack();
  },
});
