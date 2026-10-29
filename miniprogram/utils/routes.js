/**
 * 路由常量。
 *
 * 笔顺数据按年级拆成多个分包（单个分包上限 2MB，笔顺数据每册 0.2~0.45MB）：
 *   packageStrokes   一年级上/下、二年级上/下
 *   packageStrokes3  三年级上/下
 *   packageStrokes4  四年级上/下
 *
 * 页面落点由「这个字属于哪一册」决定，调用方只给汉字即可：
 *   routes.detailUrl('鹦')  // => /packageStrokes3/pages/detail/detail?ch=...
 *
 * 新增年级时只要加一条 PACK_OF_BOOK 映射 + 一个分包目录。
 *
 * 预加载走 wx.loadSubpackage 按需触发，而不是 app.json 的 preloadRule：
 * preloadRule 是静态配置，写死"首页预载哪些包"，加四年级后三个分包
 * 合计 2483KB，超过微信「单个页面预加载分包总量 ≤ 2MB」的限制，
 * 真机上传直接报 80058。放到代码里就能只预载用户当前那册所属的包。
 */
const catalog = require('./catalog');

const PACK_OF_BOOK = {
  '1a': 'packageStrokes',
  '1b': 'packageStrokes',
  '2a': 'packageStrokes',
  '2b': 'packageStrokes',
  '3a': 'packageStrokes3',
  '3b': 'packageStrokes3',
  '4a': 'packageStrokes4',
  '4b': 'packageStrokes4',
};

const DEFAULT_PACK = 'packageStrokes';

/** 分包目录 → app.json 里的分包 name（wx.loadSubpackage 用它定位） */
const PACK_NAME = {
  packageStrokes: 'strokes',
  packageStrokes3: 'strokes3',
  packageStrokes4: 'strokes4',
};

/** 已经发起过预载的包，避免每次进页面重复调用 */
const preloaded = {};

/** 取某册对应的分包根目录；未知册次回落到默认分包 */
function packOf(book) {
  return PACK_OF_BOOK[book] || DEFAULT_PACK;
}

/** 由汉字反查分包（取不到元数据时用默认分包，保证不崩） */
function packOfChar(ch) {
  const meta = ch ? catalog.getMeta(ch) : null;
  return packOf(meta && meta.b);
}

/**
 * 预载某册所属的分包。加载失败不影响任何功能 —— 真的跳到详情页时
 * 微信会自动下载分包，只是少了一次提前量。
 *
 * @param {string} book 册次，如 '4a'
 * @returns {string} 发起预载的分包名；没发起（已预载/无 wx）时返回空串
 */
function preload(book) {
  if (typeof wx === 'undefined' || !wx || typeof wx.loadSubpackage !== 'function') return '';
  const name = PACK_NAME[packOf(book)];
  if (!name || preloaded[name]) return '';
  preloaded[name] = true;
  try {
    wx.loadSubpackage({
      name: name,
      // 下载失败就把标记清掉，下次进页面还能再试一次。
      // 不弹提示：预载只是提前量，失败了用户点进详情页时微信仍会自动下载。
      fail() {
        preloaded[name] = false;
      },
    });
  } catch (e) {
    preloaded[name] = false; // 低版本基础库没有这个 API，忽略
  }
  return name;
}

/** 某册对应的分包 name（app.json 里的 name 字段） */
function packNameOf(book) {
  return PACK_NAME[packOf(book)] || '';
}

function detailPath(ch) {
  return '/' + packOfChar(ch) + '/pages/detail/detail';
}

function writePath(ch) {
  return '/' + packOfChar(ch) + '/pages/write/write';
}

function detailUrl(ch, lessonId, extra) {
  let url = detailPath(ch) + '?ch=' + encodeURIComponent(ch || '');
  if (lessonId) url += '&lesson=' + lessonId;
  if (extra) url += '&' + extra;
  return url;
}

function writeUrl(ch) {
  return writePath(ch) + '?ch=' + encodeURIComponent(ch || '');
}

module.exports = {
  PACK_OF_BOOK,
  PACK_NAME,
  packOf,
  packOfChar,
  packNameOf,
  preload,
  detailPath,
  writePath,
  detailUrl,
  writeUrl,
};
