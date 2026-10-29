/** 初始化 canvas 2d 节点（适配 dpr），返回 Promise */

/**
 * 按 CSS 尺寸 + dpr 设置位图尺寸，并把绘图坐标系缩放到 CSS 像素。
 * 单独抽出来是因为：某些安卓机在页面隐藏/恢复、或元素被重新布局后，
 * 会把 canvas 位图重置成默认的 300×150。那时 CSS 尺寸不变，画面就会被
 * 拉伸放大并裁切（表现为“字突然变大、显示不全”）。重新赋值 width 会清空
 * 画布与变换矩阵，所以必须同时重设尺寸并恢复 scale。
 */
function sizeCanvas(canvas, width, height, dpr) {
  const w = Math.max(1, Math.round(width * dpr));
  const h = Math.max(1, Math.round(height * dpr));
  const ctx = canvas.getContext('2d');
  if (canvas.width !== w || canvas.height !== h) {
    canvas.width = w;
    canvas.height = h;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.scale(dpr, dpr);
    return true; // 位图被重置过，调用方需要整屏重绘
  }
  return false;
}

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
        canvas.width = Math.round(info.width * dpr);
        canvas.height = Math.round(info.height * dpr);
        const ctx = canvas.getContext('2d');
        ctx.scale(dpr, dpr);
        resolve({
          canvas: canvas,
          ctx: ctx,
          width: info.width,
          height: info.height,
          dpr: dpr,
          /** 每次重绘前调用：位图若被系统重置，这里会修好并返回 true */
          ensure: function () {
            return sizeCanvas(canvas, info.width, info.height, dpr);
          },
          /** 用 CSS 尺寸清空整块画布（不要用 canvas.width，那是物理像素） */
          clear: function () {
            this.ensure();
            ctx.clearRect(0, 0, info.width, info.height);
          },
        });
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

module.exports = { initCanvas, rpx, sizeCanvas };
