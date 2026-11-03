/**
 * 本地存储封装：小程序里用 wx.*Storage，Node 测试里退回内存实现。
 *
 * 加了多孩子档案之后多了一层**命名空间**：每个档案的数据各自一套键。
 * 默认档案的命名空间是空串，键还是 `hanzi:v1:progress` 这样——
 * 老用户升级上来数据原地不动，不会因为加了档案功能就丢进度。
 * 后建的档案用 `p2`、`p3`，键变成 `hanzi:v1:p2:progress`。
 */
const PREFIX = 'hanzi:v1:';
const memory = {};
const hasWx = typeof wx !== 'undefined' && typeof wx.getStorageSync === 'function';

/** 当前档案的命名空间，空串 = 默认档案 */
let ns = '';

function keyOf(name) {
  return PREFIX + (ns ? ns + ':' : '') + name;
}

/** 切换命名空间。只影响之后读写的键，不动已有数据。 */
function setProfile(id) {
  ns = id ? String(id) : '';
}

function currentProfile() {
  return ns;
}

function read(name, fallback) {
  let raw;
  try {
    const k = keyOf(name);
    raw = hasWx ? wx.getStorageSync(k) : memory[k];
  } catch (e) {
    raw = null;
  }
  if (raw === undefined || raw === null || raw === '') return fallback;
  return raw;
}

function write(name, value) {
  try {
    const k = keyOf(name);
    if (hasWx) wx.setStorageSync(k, value);
    else memory[k] = value;
  } catch (e) {
    // 存储满了也不能影响答题
    console.warn('存储写入失败', name, e);
  }
}

function remove(name) {
  try {
    const k = keyOf(name);
    if (hasWx) wx.removeStorageSync(k);
    else delete memory[k];
  } catch (e) {
    // ignore
  }
}

/**
 * 清空**当前档案**的数据。
 *
 * 不能连别的档案一起清——「清空学习记录」是清这个孩子的记录，
 * 一键把弟弟的进度也清掉是不可接受的。
 */
function clearAll() {
  const scope = PREFIX + (ns ? ns + ':' : '');
  Object.keys(memory).forEach((k) => { if (k.indexOf(scope) === 0) delete memory[k]; });
  if (!hasWx) return;
  try {
    const info = wx.getStorageInfoSync();
    (info.keys || []).forEach((k) => {
      if (k.indexOf(scope) === 0) wx.removeStorageSync(k);
    });
  } catch (e) {
    // ignore
  }
}

/** 删掉某个档案的全部数据（该档案被删除时调用） */
function clearProfile(id) {
  const scope = PREFIX + (id ? id + ':' : '');
  Object.keys(memory).forEach((k) => { if (k.indexOf(scope) === 0) delete memory[k]; });
  if (!hasWx) return;
  try {
    const info = wx.getStorageInfoSync();
    (info.keys || []).forEach((k) => {
      if (k.indexOf(scope) === 0) wx.removeStorageSync(k);
    });
  } catch (e) {
    // ignore
  }
}

function _dump() {
  return memory;
}

/**
 * 不走档案命名空间的读写。
 *
 * 只给「和哪个孩子无关」的缓存用——比如笔画轮廓缓存：同一个字对哥哥和
 * 弟弟是同一份数据，按档案各存一份纯属浪费空间，而小程序存储上限只有 10MB。
 */
function readRaw(name, fallback) {
  const k = PREFIX + name;
  try {
    if (hasWx) {
      const v = wx.getStorageSync(k);
      return v === '' || v === undefined || v === null ? fallback : v;
    }
    return memory[k] === undefined ? fallback : memory[k];
  } catch (e) {
    return fallback;
  }
}

function writeRaw(name, value) {
  const k = PREFIX + name;
  try {
    if (hasWx) wx.setStorageSync(k, value);
    else memory[k] = value;
  } catch (e) {
    // ignore
  }
}

module.exports = {
  read, write, remove, clearAll, clearProfile,
  setProfile, currentProfile, keyOf,
  readRaw, writeRaw,
  _dump, PREFIX,
};
