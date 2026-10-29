/**
 * 「描红」页面（薄壳）
 * 逻辑见主包 utils/write-page.js。
 */
const createWritePage = require('../../../utils/write-page');

Page(createWritePage({
  books: {
    '1a': () => require('../../data/strokes-1a.js'),
    '1b': () => require('../../data/strokes-1b.js'),
    '2a': () => require('../../data/strokes-2a.js'),
    '2b': () => require('../../data/strokes-2b.js'),
  },
}));
