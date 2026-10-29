/**
 * 「描红」页面（薄壳）
 * 逻辑见主包 utils/write-page.js。
 */
const createWritePage = require('../../../utils/write-page');

Page(createWritePage({
  books: {
    '4a': () => require('../../data/strokes-4a.js'),
    '4b': () => require('../../data/strokes-4b.js'),
  },
}));
