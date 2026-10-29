/**
 * 自定义导航栏的尺寸计算。
 *
 * 背景：首页 index 用了 "navigationStyle": "custom"，页面从屏幕最顶端开始绘制
 * （连状态栏那条也算页面自己的）。但微信右上角的胶囊按钮（··· ⊙）是**系统浮层**，
 * 永远画在页面之上，且不会让出位置。如果页面只预留 statusBarHeight 就直接排版，
 * 右上角的内容就会钻到胶囊底下被盖住 —— 「学了几天」那个小药丸就是这么被遮的。
 *
 * 所以需要按胶囊的实际位置，把「状态栏 + 导航带」整条让出来：
 *   navHeight = (胶囊上沿 - 状态栏高度) * 2 + 胶囊高度
 * 这是微信官方示例的算法：胶囊在导航带里上下留白相等，带子高度由此反推。
 */

/** 拿不到胶囊信息时的兜底高度（与微信默认导航栏一致） */
const DEFAULT_NAV_HEIGHT = 44;

/** 导航带高度的合理区间：太薄会压到胶囊，太厚纯属浪费首屏 */
const MIN_NAV_HEIGHT = 32;
const MAX_NAV_HEIGHT = 64;

/** 胶囊右侧留白之外，再让出的呼吸空间 */
const CAPSULE_GAP = 8;

/**
 * @param {number} statusBarHeight 状态栏高度（px）
 * @param {{top:number,height:number,left:number,right?:number,width:number}} capsule
 *        胶囊按钮矩形（wx.getMenuButtonBoundingClientRect 的返回值）
 * @param {number} windowWidth 屏幕宽度（px）
 * @returns {{statusBarHeight:number, navHeight:number, capsuleReserve:number, totalHeight:number}}
 */
function headerMetrics(statusBarHeight, capsule, windowWidth) {
  const sb =
    typeof statusBarHeight === 'number' && isFinite(statusBarHeight) && statusBarHeight > 0
      ? Math.round(statusBarHeight)
      : 20;

  const w =
    typeof windowWidth === 'number' && isFinite(windowWidth) && windowWidth > 0
      ? windowWidth
      : 375;

  const c = capsule || {};
  const cTop = Number(c.top);
  const cHeight = Number(c.height);
  const cLeft = Number(c.left);
  const capsuleValid = isFinite(cTop) && isFinite(cHeight) && isFinite(cLeft) && cTop > 0 && cHeight > 0 && cLeft > 0;

  let navHeight = DEFAULT_NAV_HEIGHT;
  if (capsuleValid) {
    // 胶囊在带子里居中：上方留白 = cTop - sb，下方留白相同
    navHeight = (cTop - sb) * 2 + cHeight;
  }
  navHeight = Math.max(MIN_NAV_HEIGHT, Math.min(MAX_NAV_HEIGHT, Math.round(navHeight)));

  // 品牌文字等靠左内容，右侧要让出的宽度（从胶囊左沿到屏幕右沿 + 呼吸空间）
  const capsuleReserve = capsuleValid ? Math.max(0, Math.round(w - cLeft + CAPSULE_GAP)) : 0;

  return {
    statusBarHeight: sb,
    navHeight,
    capsuleReserve,
    totalHeight: sb + navHeight,
  };
}

/**
 * 从 wx 拿导航尺寸。任何一步失败都退化成保守值，绝不抛错
 * （首屏样式崩掉比位置差几像素严重得多）。
 */
function measureHeader(wxApi) {
  const api = wxApi || (typeof wx !== 'undefined' ? wx : null);
  let statusBarHeight = 0;
  let windowWidth = 0;
  let capsule = null;

  try {
    const info = api && (api.getWindowInfo ? api.getWindowInfo() : api.getSystemInfoSync && api.getSystemInfoSync());
    if (info) {
      statusBarHeight = info.statusBarHeight || 0;
      windowWidth = info.windowWidth || 0;
    }
  } catch (e) {
    /* ignore */
  }

  try {
    if (api && typeof api.getMenuButtonBoundingClientRect === 'function') {
      capsule = api.getMenuButtonBoundingClientRect();
    }
  } catch (e) {
    capsule = null;
  }

  return headerMetrics(statusBarHeight, capsule, windowWidth);
}

module.exports = {
  DEFAULT_NAV_HEIGHT,
  headerMetrics,
  measureHeader,
};
