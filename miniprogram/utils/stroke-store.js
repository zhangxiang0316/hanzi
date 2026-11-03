/**
 * 按需加载某册的笔顺数据并解码，带缓存。
 *
 * 笔顺数据体积大（每个年级约 0.5MB），必须放在分包里；而小程序规定
 * 「分包可以 require 主包，主包不能 require 分包」。所以这里不写死数据路径，
 * 而是由分包页面在启动时注册自己的加载器：
 *
 *   // miniprogram/packageStrokes/pages/detail/detail.js
 *   strokeStore.register('1a', () => require('../../data/strokes-1a.js'));
 *
 * 传的是函数而不是对象，保证只有真正用到某一册时才加载它。
 */
const meta = require('../data/meta.js');
const { decode } = require('./stroke-codec');
const store = require('./store');

/**
 * 轮廓缓存：字 → 原始 base64。
 *
 * 为什么需要它：`loaders` 是内存里的，只有分包页面执行过才会注册。用户
 * 冷启动 App 直接进「我的字帖」点导出时，一个分包都没加载过，`get()`
 * 全返回 null，导出的 PDF 会是一张白纸。
 *
 * 而字帖里的每个字用户都**写过**——写的那一刻分包一定是加载着的。所以
 * 在写的时候把原始 base64 存一份到本地，之后任何时候都能出 PDF。
 *
 * 存原始 base64 而不是解码后的指令：解码结果体积更大（对象数组），
 * 而 base64 就是数据文件里的样子，解码很快且带缓存。
 */
const CACHE_KEY = 'outline-cache';

/** 缓存上限。一个字约 0.5~1KB，600 字约 0.5MB，离 10MB 上限还很远 */
const CACHE_MAX = 600;

const loaders = {}; // 册 -> () => { 字: base64 }
const bookData = {}; // 册 -> { 字: base64 }（已加载）
const charCache = {}; // 字 -> 解码结果

/** 注册一册的数据加载器（由分包页面调用） */
function register(book, loader) {
  if (typeof loader === 'function') loaders[book] = loader;
}

/** 批量注册：{ '1a': () => require(...), ... } */
function registerAll(map) {
  Object.keys(map || {}).forEach((book) => register(book, map[book]));
}

function loadBook(book) {
  if (bookData[book]) return bookData[book];
  const loader = loaders[book];
  // 没有加载器时**不能**缓存空对象：那样等分包页面稍后注册了加载器，
  // 这里还是会拿到那份空的 { }，这个字就永远取不到了。
  // 冷启动直接进字帖页导出就会踩到——那正是本缓存要解决的场景。
  if (!loader) return {};
  bookData[book] = loader() || {};
  return bookData[book];
}

/** 读整份轮廓缓存 */
function readCache() {
  const v = store.readRaw(CACHE_KEY, null);
  return v && typeof v === 'object' ? v : {};
}

/**
 * 把某字的原始轮廓存进本地缓存。
 *
 * 该字的册还没加载时静默跳过——不是错误，只是这次没东西可存。
 *
 * @returns {boolean} 是否真的存了
 */
function remember(ch) {
  if (!ch) return false;
  const m = meta[ch];
  if (!m) return false;
  const raw = loadBook(m.b)[ch];
  if (!raw) return false;
  const cache = readCache();
  if (cache[ch] === raw) return true; // 已经有了，不必重写整份缓存
  cache[ch] = raw;
  // 超出上限就按插入顺序丢掉最早的（对象 key 保持插入顺序）
  const keys = Object.keys(cache);
  if (keys.length > CACHE_MAX) {
    keys.slice(0, keys.length - CACHE_MAX).forEach((k) => delete cache[k]);
  }
  try {
    store.writeRaw(CACHE_KEY, cache);
  } catch (e) {
    // 存储满了也不能让描红流程失败
    return false;
  }
  return true;
}

/**
 * 批量把一批字的轮廓存进缓存。
 *
 * 字帖页打开时调一次：本次会话里加载过的册，顺手把字帖里的字都存下来。
 * 老用户升级后没有历史缓存，靠这一步逐次补齐。
 *
 * @returns {number} 新存进去的字数
 */
function rememberAll(chars) {
  const cache = readCache();
  let added = 0;
  (chars || []).forEach((ch) => {
    if (cache[ch]) return;
    if (remember(ch)) added += 1;
  });
  return added;
}

/** 该字的轮廓是否已经在本地缓存里（字帖导出前用它判断要不要提示） */
function isCached(ch) {
  return !!readCache()[ch];
}

/** 是否已注册某册（用于给用户更明确的错误提示） */
function hasBook(book) {
  return !!loaders[book];
}

function get(ch) {
  if (charCache[ch]) return charCache[ch];
  const m = meta[ch];
  if (!m) return null;
  const raw = loadBook(m.b)[ch] || readCache()[ch];
  if (!raw) return null;
  const data = decode(raw);
  charCache[ch] = data;
  return data;
}

/**
 * 清掉解码缓存。
 *
 * 只清 `charCache`：`bookData` 里是数据文件原样的 base64，不可变，
 * 没有失效的理由，留着还能省一次重新加载。
 */
function clear() {
  Object.keys(charCache).forEach((k) => delete charCache[k]);
}

/**
 * 连注册和原始数据一起清空。
 *
 * 只给测试用——生产代码没有「忘掉已加载的分包」这个需求，
 * 而测试要能反复模拟「冷启动、一个分包都没加载」的处境。
 */
function _reset() {
  clear();
  Object.keys(loaders).forEach((k) => delete loaders[k]);
  Object.keys(bookData).forEach((k) => delete bookData[k]);
}

module.exports = {
  register, registerAll, hasBook, get, clear,
  remember, rememberAll, isCached, CACHE_KEY, CACHE_MAX, _reset,
};
