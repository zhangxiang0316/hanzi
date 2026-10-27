/** 本地存储封装：小程序里用 wx.*Storage，Node 测试里退回内存实现。 */
const PREFIX = 'hanzi:v1:';
const memory = {};
const hasWx = typeof wx !== 'undefined' && typeof wx.getStorageSync === 'function';

function read(name, fallback) {
  let raw;
  try {
    raw = hasWx ? wx.getStorageSync(PREFIX + name) : memory[name];
  } catch (e) {
    raw = null;
  }
  if (raw === undefined || raw === null || raw === '') return fallback;
  return raw;
}

function write(name, value) {
  try {
    if (hasWx) wx.setStorageSync(PREFIX + name, value);
    else memory[name] = value;
  } catch (e) {
    // 存储满了也不能影响答题
    console.warn('存储写入失败', name, e);
  }
}

function remove(name) {
  try {
    if (hasWx) wx.removeStorageSync(PREFIX + name);
    else delete memory[name];
  } catch (e) {
    // ignore
  }
}

function clearAll() {
  Object.keys(memory).forEach((k) => delete memory[k]);
  if (!hasWx) return;
  try {
    const info = wx.getStorageInfoSync();
    (info.keys || []).forEach((k) => {
      if (k.indexOf(PREFIX) === 0) wx.removeStorageSync(k);
    });
  } catch (e) {
    // ignore
  }
}

function _dump() {
  return memory;
}

module.exports = { read, write, remove, clearAll, _dump, PREFIX };
