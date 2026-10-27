const catalog = require('../../utils/catalog');
const progress = require('../../utils/progress');
const routes = require('../../utils/routes');

Page({
  data: {
    title: '练习',
    total: 0,
    correct: 0,
    rate: 0,
    mood: '🎉',
    message: '',
    wrongChars: [],
    ringStyle: '',
  },

  onLoad() {
    const app = getApp();
    const res = app.globalData.lastResult;
    if (!res) {
      wx.redirectTo({ url: '/pages/index/index' });
      return;
    }
    app.globalData.lastResult = null;
    const rate = res.rate;
    let mood = '🌱';
    let message = '慢慢来，多练几次就记住啦。';
    if (rate >= 100) {
      mood = '🏆';
      message = '全对！今天的你特别棒。';
    } else if (rate >= 80) {
      mood = '🎉';
      message = '很稳！只差一点点就全对了。';
    } else if (rate >= 60) {
      mood = '👍';
      message = '不错哦，把错的字再读两遍。';
    }
    const wrongChars = (res.wrongChars || []).map((ch) => {
      const m = catalog.getMeta(ch);
      return {
        ch,
        py: catalog.readingFor(ch, m.l),
        word: m.w && m.w[0] ? m.w[0].w : '',
        lesson: m.l,
      };
    });
    this.result = res;
    this.setData({
      title: res.title,
      total: res.total,
      correct: res.correct,
      rate,
      mood,
      message,
      wrongChars,
      ringStyle:
        'background: conic-gradient(#3e8e7e 0deg, #3e8e7e ' +
        Math.round((rate / 100) * 360) +
        'deg, #eef0e9 ' +
        Math.round((rate / 100) * 360) +
        'deg);',
    });
  },

  onOpenChar(e) {
    const ch = e.currentTarget.dataset.ch;
    const item = this.data.wrongChars.filter((w) => w.ch === ch)[0];
    wx.navigateTo({ url: routes.detailUrl(ch, item ? item.lesson : '') });
  },

  onAgain() {
    const app = getApp();
    const res = this.result;
    if (res.wrongChars && res.wrongChars.length) {
      app.globalData.session = {
        mode: 'wrong',
        title: '错字重练',
        chars: res.wrongChars,
        book: res.book,
        lesson: res.lesson,
        count: 6,
      };
    } else {
      // 没有错题时，quiz 页面会自动回退到“随机练习”
      app.globalData.session = null;
    }
    wx.redirectTo({ url: '/pages/quiz/quiz?from=result' });
  },

  onPractice() {
    wx.switchTab({ url: '/pages/practice/practice' });
  },

  onHome() {
    wx.switchTab({ url: '/pages/index/index' });
  },
});
