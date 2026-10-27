/** 按需加载某册的笔顺数据并解码，带缓存 */
const meta = require('../../data/meta.js');
const { decode } = require('./stroke-codec');

const bookData = {};
const charCache = {};

function loadBook(book) {
  if (bookData[book]) return bookData[book];
  let data = null;
  // 静态 require 路径，便于小程序打包分析；只有真正用到时才加载
  if (book === '1a') data = require('../data/strokes-1a.js');
  else if (book === '1b') data = require('../data/strokes-1b.js');
  else if (book === '2a') data = require('../data/strokes-2a.js');
  else if (book === '2b') data = require('../data/strokes-2b.js');
  bookData[book] = data || {};
  return bookData[book];
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

module.exports = { get, clear };
