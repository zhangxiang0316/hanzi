/** 初始化 canvas 2d 节点（适配 dpr），返回 Promise */
function initCanvas(page, selector) {
  return new Promise(function (resolve, reject) {
    const query = wx.createSelectorQuery().in(page);
    query
      .select(selector)
      .fields({ node: true, size: true })
      .exec(function (res) {
        const info = res && res[0];
        if (!info || !info.node) {
          reject(new Error('找不到画布 ' + selector));
          return;
        }
        let dpr = 2;
        try {
          const win = wx.getWindowInfo ? wx.getWindowInfo() : wx.getSystemInfoSync();
          dpr = win.pixelRatio || 2;
        } catch (e) {
          dpr = 2;
        }
        const canvas = info.node;
        const ctx = canvas.getContext('2d');
        canvas.width = Math.round(info.width * dpr);
        canvas.height = Math.round(info.height * dpr);
        ctx.scale(dpr, dpr);
        resolve({ canvas, ctx, width: info.width, height: info.height, dpr });
      });
  });
}

/** rpx → px */
function rpx(n) {
  try {
    const win = wx.getWindowInfo ? wx.getWindowInfo() : wx.getSystemInfoSync();
    return (n * win.windowWidth) / 750;
  } catch (e) {
    return (n * 375) / 750;
  }
}

module.exports = { initCanvas, rpx };
