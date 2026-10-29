import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const navMetrics = require(path.join(ROOT, 'miniprogram/utils/nav-metrics.js'));

/** iPhone 14 一类的刘海屏：状态栏 47，胶囊上沿 51、高 32 */
const IPHONE = { top: 51, height: 32, left: 291, right: 378, width: 87 };
/** 安卓/旧机型：状态栏 20，胶囊上沿 24 */
const ANDROID = { top: 24, height: 32, left: 271, right: 358, width: 87 };

test('导航带高度按胶囊位置反推：上下留白相等', () => {
  const h = navMetrics.headerMetrics(47, IPHONE, 390);
  assert.equal(h.statusBarHeight, 47);
  // (51 - 47) * 2 + 32 = 40
  assert.equal(h.navHeight, 40);
  assert.equal(h.statusBarHeight + h.navHeight, 87);
});

test('导航带必须完整盖住胶囊', () => {
  for (const [sb, capsule, w] of [
    [47, IPHONE, 390],
    [20, ANDROID, 375],
    [44, { top: 48, height: 32, left: 296, width: 87 }, 390],
  ]) {
    const h = navMetrics.headerMetrics(sb, capsule, w);
    const bandBottom = h.statusBarHeight + h.navHeight;
    assert.ok(
      bandBottom >= capsule.top + capsule.height,
      `导航带底 ${bandBottom} 没盖住胶囊底 ${capsule.top + capsule.height}`
    );
  }
});

test('右侧让位宽度覆盖胶囊（含呼吸空间）', () => {
  const h = navMetrics.headerMetrics(47, IPHONE, 390);
  // 胶囊左沿 291 → 右侧要空出 390 - 291 = 99，再加 8px 呼吸
  assert.equal(h.capsuleReserve, 107);
  assert.ok(390 - h.capsuleReserve < IPHONE.left, '让位后仍会压到胶囊');
});

test('拿不到胶囊信息时退化成默认导航栏高度', () => {
  for (const capsule of [null, undefined, {}, { top: 0, height: 0 }]) {
    const h = navMetrics.headerMetrics(44, capsule, 390);
    assert.equal(h.navHeight, navMetrics.DEFAULT_NAV_HEIGHT);
    assert.equal(h.capsuleReserve, 0);
  }
});

test('异常输入不会算出离谱的高度', () => {
  // 状态栏缺失
  assert.equal(navMetrics.headerMetrics(0, IPHONE, 390).statusBarHeight, 20);
  assert.equal(navMetrics.headerMetrics(undefined, IPHONE, 390).statusBarHeight, 20);
  // 屏幕宽度缺失
  assert.equal(navMetrics.headerMetrics(47, IPHONE, 0).statusBarHeight, 47);
  // 胶囊贴顶（top < statusBar）→ 高度落在合理区间
  const tiny = navMetrics.headerMetrics(47, { top: 40, height: 32, left: 291, width: 87 }, 390);
  assert.ok(tiny.navHeight >= 32 && tiny.navHeight <= 64, `异常高度 ${tiny.navHeight}`);
  // 胶囊跑出屏幕
  const huge = navMetrics.headerMetrics(20, { top: 400, height: 32, left: 10, width: 87 }, 375);
  assert.ok(huge.navHeight <= 64, `高度没夹住 ${huge.navHeight}`);
});

test('measureHeader 读取真实 wx API，并在 API 抛错时兜底', () => {
  const ok = navMetrics.measureHeader({
    getWindowInfo: () => ({ statusBarHeight: 47, windowWidth: 390 }),
    getMenuButtonBoundingClientRect: () => IPHONE,
  });
  assert.equal(ok.statusBarHeight, 47);
  assert.equal(ok.navHeight, 40);

  const broken = navMetrics.measureHeader({
    getWindowInfo: () => {
      throw new Error('boom');
    },
    getMenuButtonBoundingClientRect: () => {
      throw new Error('boom');
    },
    getSystemInfoSync: () => {
      throw new Error('boom');
    },
  });
  assert.ok(broken.navHeight > 0, '兜底也必须有导航带');
  assert.equal(broken.capsuleReserve, 0);

  // 完全没有 wx（单元测试环境）也不能崩
  const none = navMetrics.measureHeader(null);
  assert.equal(none.navHeight, navMetrics.DEFAULT_NAV_HEIGHT);
});

test('首页使用自定义导航，必须真的按胶囊让位', () => {
  const fs = require('node:fs');
  const json = JSON.parse(fs.readFileSync(path.join(ROOT, 'miniprogram/pages/index/index.json'), 'utf8'));
  assert.equal(json.navigationStyle, 'custom', '首页应当是自定义导航');

  const js = fs.readFileSync(path.join(ROOT, 'miniprogram/pages/index/index.js'), 'utf8');
  assert.match(js, /navMetrics\.measureHeader/, '首页必须按胶囊位置计算导航高度');

  const wxml = fs.readFileSync(path.join(ROOT, 'miniprogram/pages/index/index.wxml'), 'utf8');
  assert.match(wxml, /navHeight/, '首页模板必须预留导航带高度');
  assert.match(wxml, /capsuleReserve/, '品牌文字右侧必须给胶囊让位');
});
