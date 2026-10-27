App({
  globalData: {
    lastQuiz: null,
    version: '1.0.0',
  },

  onLaunch() {
    // 数据模块按需 require，这里只做一次轻量的版本标记，
    // 方便后续做本地数据结构迁移。
    try {
      const info = wx.getStorageSync('hanzi:v1:installed');
      if (!info) {
        wx.setStorageSync('hanzi:v1:installed', Date.now());
      }
    } catch (e) {
      // 存储不可用时不影响使用
    }
  },

  onShow() {
    // 从后台切回时，页面通过 onShow 自行刷新数据
  },

  onError(err) {
    console.error('[小小识字家] 未捕获错误', err);
  },
});
