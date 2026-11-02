/**
 * 「听写」页面。
 *
 * 逻辑复用主包 `utils/write-page.js`（判分、画布、手势、笔顺动画全部一致），
 * 只在外面套一层多字流程：念一个词 → 写 → 下一个。
 *
 * 与描红的唯一差别是「不显示底字」（normal/hard 档），
 * 这一点通过 `createWritePage({ hideGhost })` 传下去。
 */
const createWritePage = require('../../../utils/write-page');
const dictation = require('../../../utils/dictation');

const base = createWritePage({
  books: {
    '3a': () => require('../../data/strokes-3a.js'),
    '3b': () => require('../../data/strokes-3b.js'),
  },
});

Page(
  Object.assign({}, base, {
    data: Object.assign({}, base.data, {
      level: 'normal',
      levelTitle: '',
      items: [],
      index: 0,
      word: '',
      answered: false,   // 这个字写完了没（写完才露字）
      roundDone: false,  // 一轮听写结束
      scores: [],
      avgScore: 0,
      roundStars: 0,
      // 题面是否可见。hard 档显示 3 秒后自动隐藏，逼孩子凭记忆写。
      peekVisible: true,
      peekHint: '看完记住，马上要藏起来',
      hasAudio: dictation.SUPPORTS_AUDIO,
    }),

    onLoad(options) {
      const level = (options && options.level) || 'normal';
      const book = (options && options.book) || '';
      const lv = dictation.levelOf(level);
      const items = dictation.pick(book, level, 8);

      this.hideGhost = !lv.showsGhost;
      this.items = items;
      this.setData({
        level: lv.key,
        levelTitle: lv.title,
        items,
        index: 0,
        scores: [],
        answered: false,
        roundDone: false,
      });

      if (!items.length) {
        wx.showToast({ title: '这一册没有可以听写的字', icon: 'none' });
        return;
      }
      this.loadCurrent();
      wx.setNavigationBarTitle({ title: '默写 · ' + lv.title });
    },

    /** 载入第 index 个字，按难度决定要不要限时藏题面 */
    loadCurrent() {
      const item = this.items[this.data.index];
      if (!item) return;
      this.loadChar(item.ch);
      const lv = dictation.levelOf(this.data.level);
      this.setData({
        word: item.word || '',
        answered: false,
        peekVisible: true,
      });
      if (this.hideTimer) clearTimeout(this.hideTimer);
      if (lv.peekMs > 0) {
        this.hideTimer = setTimeout(() => {
          this.setData({ peekVisible: false });
        }, lv.peekMs);
      }
    },

    /**
     * 再显示一次题面。
     *
     * 小程序端没有 TTS，这是「再念一遍」的等价物：忘了要写什么就点一下再看。
     */
    onReplay() {
      const lv = dictation.levelOf(this.data.level);
      this.setData({ peekVisible: true });
      if (this.hideTimer) clearTimeout(this.hideTimer);
      if (lv.peekMs > 0) {
        this.hideTimer = setTimeout(() => {
          this.setData({ peekVisible: false });
        }, lv.peekMs);
      }
    },

    /** write-page 的完成钩子：写完露出答案，让孩子自己对一眼 */
    onCharFinished(ch, score) {
      const scores = this.data.scores.concat([{ ch, score }]);
      if (this.hideTimer) clearTimeout(this.hideTimer);
      this.setData({
        answered: true,
        scores,
        avgScore: this.average(scores),
        peekVisible: true,
      });
    },

    average(scores) {
      if (!scores.length) return 0;
      let sum = 0;
      for (let i = 0; i < scores.length; i++) sum += scores[i].score;
      return Math.round(sum / scores.length);
    },

    onSkip() {
      this.nextChar();
    },

    onNextChar() {
      this.nextChar();
    },

    nextChar() {
      const next = this.data.index + 1;
      if (next >= this.items.length) {
        const scores = this.data.scores;
        const avg = this.average(scores);
        // 星级门槛与描红一致：85/65/40
        const stars = avg >= 85 ? 3 : avg >= 65 ? 2 : avg >= 40 ? 1 : 0;
        this.setData({ roundDone: true, avgScore: avg, roundStars: stars });
        return;
      }
      this.setData({ index: next });
      this.loadCurrent();
    },

    onFinishRound() {
      wx.navigateBack();
    },

    onUnload() {
      if (this.hideTimer) clearTimeout(this.hideTimer);
    },

    /** 听写页不需要描红那个「结果卡片」，写完后直接进下一个 */
    onAgain() {},
  })
);
