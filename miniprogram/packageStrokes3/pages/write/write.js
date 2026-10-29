/**
 * 「描红」页面（薄壳）
 * 逻辑见主包 utils/write-page.js。
 */
const createWritePage = require('../../../utils/write-page');

Page(createWritePage({
  books: {
    '3a': () => require('../../data/strokes-3a.js'),
    '3b': () => require('../../data/strokes-3b.js'),
  },
}));
