/**
 * 路由常量：描红/笔顺相关的页面放在分包 packageStrokes 里，
 * 主包只负责跳转，统一从这里取路径，避免写死分包前缀。
 */
const DETAIL = '/packageStrokes/pages/detail/detail';
const WRITE = '/packageStrokes/pages/write/write';

function detailUrl(ch, lessonId, extra) {
  let url = DETAIL + '?ch=' + encodeURIComponent(ch || '');
  if (lessonId) url += '&lesson=' + lessonId;
  if (extra) url += '&' + extra;
  return url;
}

function writeUrl(ch) {
  return WRITE + '?ch=' + encodeURIComponent(ch || '');
}

module.exports = { DETAIL, WRITE, detailUrl, writeUrl };
