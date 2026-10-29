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
  bookData[book] = loader ? loader() || {} : {};
  return bookData[book];
}

/** 是否已注册某册（用于给用户更明确的错误提示） */
function hasBook(book) {
  return !!loaders[book];
}

function get(ch) {
  if (charCache[ch]) return charCache[ch];
  const m = meta[ch];
  if (!m) return null;
  const raw = loadBook(m.b)[ch];
  if (!raw) return null;
  const data = decode(raw);
  charCache[ch] = data;
  return data;
}

function clear() {
  Object.keys(charCache).forEach((k) => delete charCache[k]);
}

module.exports = { register, registerAll, hasBook, get, clear };
