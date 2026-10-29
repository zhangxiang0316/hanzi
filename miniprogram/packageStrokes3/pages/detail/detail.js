/**
 * 「认识这个字」页面（薄壳）
 *
 * 页面逻辑只有一份，在主包 utils/detail-page.js；本文件只负责把
 * 本分包携带的笔顺数据注册进去。数据放分包是因为小程序限制主包 2MB，
 * 而笔顺数据每册约 0.2~0.45MB。
 */
const createDetailPage = require('../../../utils/detail-page');

Page(createDetailPage({
  books: {
    '3a': () => require('../../data/strokes-3a.js'),
    '3b': () => require('../../data/strokes-3b.js'),
  },
}));
