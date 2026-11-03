/**
 * 多孩子档案。
 *
 * 一间屋里两个孩子共用一个平板学字是常态。之前所有数据挤在一套键里，
 * 弟弟写几个字就把哥哥的进度、错题本、描红星级全搅在一起，
 * 连「今天新学几个字」都算不对。
 *
 * ## 默认档案的 id 是空串
 *
 * 这一点很关键。老用户的数据存在 `hanzi:v1:progress`，如果给默认档案
 * 编个 `main` 之类的 id，键就变成 `hanzi:v1:main:progress`，
 * 升级上来进度全丢。空串让默认档案的键**和以前完全一样**，
 * 后建的档案才加前缀（`p2`、`p3`）。
 *
 * ## 上限 4 个
 *
 * 再多就不是家庭共用而是班级共用了——那时该做的是账号体系，
 * 不是本地档案。上限也让「孩子」那块 UI 保持在两行以内。
 */
const store = require('./store');

const KEY = 'profiles'; // 档案表本身是全局的，不带命名空间
const MAX = 4;
const DEFAULT_NAME = '我';

function normalize(raw) {
  const st = raw && typeof raw === 'object' ? raw : {};
  let list = Array.isArray(st.list) ? st.list : [];
  list = list
    .filter((p) => p && typeof p.id === 'string' && typeof p.name === 'string')
    .map((p) => ({ id: p.id, name: p.name }));
  // 至少留一个档案，否则界面无处可去
  if (!list.length) list = [{ id: '', name: DEFAULT_NAME }];
  // 默认档案（id 空串）永远存在，否则老用户的数据成了孤儿
  if (!list.some((p) => p.id === '')) list.unshift({ id: '', name: DEFAULT_NAME });
  let seq = typeof st.seq === 'number' && st.seq >= 2 ? st.seq : 2;
  let active = typeof st.active === 'string' ? st.active : '';
  if (!list.some((p) => p.id === active)) active = list[0].id;
  return { list, active, seq };
}

let state = normalize(store.read(KEY, null));

function persist() {
  store.write(KEY, state);
  // 档案表一变就同步命名空间，避免「切了档案但还在写旧键」
  store.setProfile(state.active);
}

// 启动时把命名空间对上，之后 progress 读的就是当前档案的数据
store.setProfile(state.active);

/** 全部档案（按创建顺序，默认档案永远第一个） */
function list() {
  return state.list.map((p) => ({ id: p.id, name: p.name }));
}

function activeId() {
  return state.active;
}

/** 当前档案对象 */
function active() {
  return state.list.find((p) => p.id === state.active) || state.list[0];
}

function count() {
  return state.list.length;
}

function canAdd() {
  return state.list.length < MAX;
}

/**
 * 切换档案。
 *
 * 返回 true 表示真的切了。调用方必须紧接着调 `progress.reload()`——
 * 存储的命名空间变了，但 progress 里那份内存状态还是上一个孩子的，
 * 不重读的话界面上会显示「换了名字但数据没变」。
 */
function setActive(id) {
  if (id === state.active) return false;
  if (!state.list.some((p) => p.id === id)) return false;
  state.active = id;
  persist();
  return true;
}

/** 新建档案。名字去首尾空格、截断到 8 字，空名字用默认名。 */
function add(name) {
  if (!canAdd()) return null;
  const trimmed = String(name == null ? '' : name).trim().slice(0, 8);
  const id = 'p' + state.seq;
  state.seq += 1;
  const p = { id, name: trimmed || '孩子' + (state.list.length + 1) };
  state.list.push(p);
  persist();
  return p;
}

/** 改名。默认档案也能改——「我」只是占位。 */
function rename(id, name) {
  const p = state.list.find((x) => x.id === id);
  if (!p) return false;
  const trimmed = String(name == null ? '' : name).trim().slice(0, 8);
  if (!trimmed) return false;
  p.name = trimmed;
  persist();
  return true;
}

/**
 * 删除档案，连同它的全部数据。
 *
 * 不允许删掉最后一个：那样界面会没有任何档案可显示。
 * 删的如果是当前档案，自动切到剩下的第一个，并返回新的 active id
 * （调用方据此决定要不要 reload）；返回 null 表示没删成。
 */
function remove(id) {
  if (state.list.length <= 1) return null;
  const i = state.list.findIndex((x) => x.id === id);
  if (i < 0) return null;
  const wasActive = state.active === id;
  state.list.splice(i, 1);
  store.clearProfile(id);
  if (wasActive) state.active = state.list[0].id;
  persist();
  return wasActive ? state.active : null;
}

/** 测试用：回到初始状态 */
function _reset() {
  state = normalize(null);
  persist();
}

module.exports = {
  MAX,
  DEFAULT_NAME,
  list,
  activeId,
  active,
  count,
  canAdd,
  setActive,
  add,
  rename,
  remove,
  _reset,
};
