const catalog = require('../../utils/catalog');
const progress = require('../../utils/progress');
const sessionUtil = require('../../utils/session');
const routes = require('../../utils/routes');

Page({
  data: {
    list: [],
  },

  onShow() {
    this.refresh();
  },

  refresh() {
    const list = progress.getWrong().map((w) => {
      const m = catalog.getMeta(w.ch);
      return {
        ch: w.ch,
        n: w.n || 1,
        py: m ? catalog.readingFor(w.ch, m.l) : '',
        lessonTitle: m ? catalog.lessonTitle(m.l) : '',
        lesson: m ? m.l : '',
      };
    });
    this.setData({ list });
  },

  onOpen(e) {
    const ch = e.currentTarget.dataset.ch;
    const item = this.data.list.filter((x) => x.ch === ch)[0];
    wx.navigateTo({ url: routes.detailUrl(ch, item ? item.lesson : '') });
  },

  onWrite(e) {
    wx.navigateTo({ url: routes.writeUrl(e.currentTarget.dataset.ch) });
  },

  onPractice() {
    const chars = this.data.list.map((x) => x.ch);
    const app = getApp();
    app.globalData.session = sessionUtil.buildSession('wrong', { chars });
    wx.navigateTo({ url: '/pages/quiz/quiz?from=wrong' });
  },

  onClear() {
    wx.showModal({
      title: '清空错题本？',
      content: '清空后这些字仍会按复习计划出现。',
      confirmColor: '#df6248',
      success: (res) => {
        if (res.confirm) {
          progress.clearWrong();
          this.refresh();
        }
      },
    });
  },
});
