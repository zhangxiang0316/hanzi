import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

/**
 * 三端一致性。
 *
 * 同一个字在 Android 上 3 星、在 iOS 上 2 星，孩子会觉得莫名其妙。
 * 判分参数必须完全一致，但它们是三份独立代码，靠人记着同步不可靠——
 * 所以这里直接把三端的**源码**读出来，比对关键常量与公式。
 *
 * 这不是重复测试逻辑，而是防漂移：谁改了一端忘了改另外两端，这里会红。
 *
 * 已经抓到过一次：修「描红最后一笔写不上」时，iOS 把短笔画门槛从
 * 一刀切的 `box*0.04` 改成 `min(box*0.04, 目标长*0.35)`，
 * 但 Android 和小程序没跟上，小程序甚至还是更严的 `box*0.06` 且不给提示。
 */

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

function read(rel) {
  return fs.readFileSync(path.join(ROOT, rel), 'utf8');
}

/**
 * 从文本里抠出某个模式匹配到的数字（用于比较公式里的系数）。
 *
 * 注意必须用 `matchAll` + 全局正则：写成 `while (re.exec(text))` 而正则没有 `g`
 * 标志时，`exec` 每次都从头匹配、永远返回同一个结果——死循环，
 * 表现是进程被 OOM 干掉（我第一版就这么写，跑测试直接把 node 打崩了）。
 */
function numbersIn(text, re) {
  const g = re.global ? re : new RegExp(re.source, re.flags + 'g');
  return [...text.matchAll(g)].map((m) => Number(m[1]));
}

test('单笔通过分三端都是 42', () => {
  // 小程序的 ACCEPT 定义在 write-page.js（trace.js 只做纯评分，不持有阈值）
  assert.match(read('miniprogram/utils/write-page.js'), /ACCEPT\s*=\s*42/);
  assert.match(read('android/app/src/main/java/com/xiaoxiao/hanzi/logic/Trace.kt'),
    /ACCEPT\s*=\s*42/);
  assert.match(read('ios/HanziPad/Logic/Trace.swift'),
    /static let accept\s*=\s*42/);
});

test('容差比例三端都是画布边长的 0.075', () => {
  assert.match(read('miniprogram/utils/write-page.js'), /tolerance\s*=\s*this\.box\s*\*\s*0\.075/);
  assert.match(read('android/app/src/main/java/com/xiaoxiao/hanzi/ui/pages/WritePage.kt'),
    /geom\.box\s*\*\s*0\.075f/);
  assert.match(read('ios/HanziPad/Logic/WriteSession.swift'),
    /tolerance[^}]*box\s*\*\s*0\.075/);
});

test('单笔评分的五项权重三端一致', () => {
  // 起笔 0.18 / 收笔 0.12 / 覆盖 0.32 / 到达 0.26 / 长度 0.12
  const want = [0.18, 0.12, 0.32, 0.26, 0.12];

  // 小程序没有具名常量，权重直接内联在乘式里：
  //   startScore * 0.18 + endScore * 0.12 + ...
  const js = read('miniprogram/utils/trace.js');
  assert.deepEqual(numbersIn(js, /startScore\s*\*\s*([\d.]+)/), [want[0]]);
  assert.deepEqual(numbersIn(js, /endScore\s*\*\s*([\d.]+)/), [want[1]]);
  assert.deepEqual(numbersIn(js, /coverScore\s*\*\s*([\d.]+)/), [want[2]]);
  assert.deepEqual(numbersIn(js, /reachScore\s*\*\s*([\d.]+)/), [want[3]]);
  assert.deepEqual(numbersIn(js, /lengthScore\s*\*\s*([\d.]+)/), [want[4]]);

  const kt = read('android/app/src/main/java/com/xiaoxiao/hanzi/logic/Trace.kt');
  assert.deepEqual(numbersIn(kt, /W_START\s*=\s*([\d.]+)f/), [want[0]]);
  assert.deepEqual(numbersIn(kt, /W_END\s*=\s*([\d.]+)f/), [want[1]]);
  assert.deepEqual(numbersIn(kt, /W_COVER\s*=\s*([\d.]+)f/), [want[2]]);
  assert.deepEqual(numbersIn(kt, /W_REACH\s*=\s*([\d.]+)f/), [want[3]]);
  assert.deepEqual(numbersIn(kt, /W_LENGTH\s*=\s*([\d.]+)f/), [want[4]]);

  const sw = read('ios/HanziPad/Logic/Trace.swift');
  assert.deepEqual(numbersIn(sw, /wStart:[^=]*=\s*([\d.]+)/), [want[0]]);
  assert.deepEqual(numbersIn(sw, /wEnd:[^=]*=\s*([\d.]+)/), [want[1]]);
  assert.deepEqual(numbersIn(sw, /wCover:[^=]*=\s*([\d.]+)/), [want[2]]);
  assert.deepEqual(numbersIn(sw, /wReach:[^=]*=\s*([\d.]+)/), [want[3]]);
  assert.deepEqual(numbersIn(sw, /wLength:[^=]*=\s*([\d.]+)/), [want[4]]);
});

test('整字评分权重三端一致（平均 0.85 + 最低分 0.15）', () => {
  const js = read('miniprogram/utils/trace.js');
  assert.match(js, /0\.85/);
  assert.match(js, /0\.15/);

  const kt = read('android/app/src/main/java/com/xiaoxiao/hanzi/logic/Trace.kt');
  assert.match(kt, /0\.85f/);
  assert.match(kt, /0\.15f/);

  const sw = read('ios/HanziPad/Logic/Trace.swift');
  assert.match(sw, /0\.85/);
  assert.match(sw, /0\.15/);
});

test('星级门槛三端一致（85 / 65 / 40）', () => {
  const js = read('miniprogram/utils/trace.js');
  assert.match(js, /85/);
  assert.match(js, /65/);
  assert.match(js, /40/);

  const kt = read('android/app/src/main/java/com/xiaoxiao/hanzi/logic/Trace.kt');
  assert.match(kt, /85/);
  assert.match(kt, /65/);
  assert.match(kt, /40/);

  const sw = read('ios/HanziPad/Logic/Trace.swift');
  assert.match(sw, />= 85/);
  assert.match(sw, />= 65/);
  assert.match(sw, />= 40/);
});

test('短笔画门槛三端都用 min(画布比例, 目标长 * 0.35)', () => {
  // 这一条是回归防线：曾经 iOS 修了、另外两端没修
  const sw = read('ios/HanziPad/Logic/WriteSession.swift');
  assert.match(sw, /min\(base,\s*targetLen\s*\*\s*0\.35\)/,
    'iOS 的短笔画门槛不再是自适应版本');

  const js = read('miniprogram/utils/write-page.js');
  assert.match(js, /Math\.min\(this\.box\s*\*\s*0\.04,\s*targetLen\s*\*\s*0\.35\)/,
    '小程序的短笔画门槛与 iOS 不一致');

  const kt = read('android/app/src/main/java/com/xiaoxiao/hanzi/ui/pages/WritePage.kt');
  assert.match(kt, /minOf\([^)]*0\.04f[^)]*\*\s*0\.35f\)|min\([^)]*0\.04f[^)]*\*\s*0\.35f\)/,
    'Android 的短笔画门槛与 iOS 不一致');
});

test('判太短时的提示文案三端一致', () => {
  // 单点说「按住别松手」，划太短说「完整写一遍」——两端文案必须一样，
  // 否则同一个动作在 Android 和 iOS 上提示不同，家长会以为哪端坏了
  const short = '这一笔太短了——按住别松手，沿着虚线划一小段';
  const normal = '这一笔太短了，沿着虚线完整写一遍';

  assert.ok(read('android/app/src/main/java/com/xiaoxiao/hanzi/ui/pages/WritePage.kt').includes(short),
    'Android 缺少单点提示或文案不一致');
  assert.ok(read('miniprogram/utils/write-page.js').includes(short),
    '小程序缺少单点提示或文案不一致');
  assert.ok(read('ios/HanziPad/Logic/WriteSession.swift').includes(short),
    'iOS 缺少单点提示或文案不一致');

  assert.ok(read('android/app/src/main/java/com/xiaoxiao/hanzi/ui/pages/WritePage.kt').includes(normal));
  assert.ok(read('miniprogram/utils/write-page.js').includes(normal));
  assert.ok(read('ios/HanziPad/Logic/WriteSession.swift').includes(normal));
});

test('判太短时三端都要给提示，不能静默返回', () => {
  // 小程序早先是 render() 后直接 return，什么提示都没有
  const js = read('miniprogram/utils/write-page.js');
  const tooShortBlock = js.slice(js.indexOf('if (len < minLen)'), js.indexOf('if (res.score >= ACCEPT)'));
  assert.match(tooShortBlock, /hint:/, '小程序判太短时没有设置 hint');

  const kt = read('android/app/src/main/java/com/xiaoxiao/hanzi/ui/pages/WritePage.kt');
  assert.match(kt, /这一笔太短了/, 'Android 判太短时没有提示');

  const sw = read('ios/HanziPad/Logic/WriteSession.swift');
  assert.match(sw, /这一笔太短了/, 'iOS 判太短时没有提示');
});

// 三端各带一份教材数据（小程序是 JS 模块，另两端是 JSON）。
// 同一份数据复制三处，最容易出的问题是「改了一端忘了另两端」——
// 孩子在 iPhone 和 Android 上看到的生字列表不一样。
// 这里比对解析后的内容，忽略文件格式差异。
test('三端教材数据内容一致', () => {
  const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
  const json = (rel) => JSON.parse(fs.readFileSync(path.join(root, rel), 'utf8'));

  const iosMeta = json('ios/HanziPad/Resources/meta.json');
  const androidMeta = json('android/app/src/main/assets/data/meta.json');
  const mpMeta = readJsModule(path.join(root, 'miniprogram/data/meta.js'));

  const keys = (o) => Object.keys(o).join(',');
  assert.equal(keys(androidMeta), keys(iosMeta), 'Android meta 字表与 iOS 不一致');
  assert.equal(keys(mpMeta), keys(iosMeta), '小程序 meta 字表与 iOS 不一致');

  // 抽查若干字的全部字段，避免只对上键名
  for (const ch of ['天', '髓', '嚼', '蟹', '匀', '剩', '训', '忧', '毒']) {
    assert.deepEqual(androidMeta[ch], iosMeta[ch], `${ch} 的 Android 元数据不一致`);
    assert.deepEqual(mpMeta[ch], iosMeta[ch], `${ch} 的小程序元数据不一致`);
  }
});

/** 读 `module.exports = {...}` 这种数据模块 */
function readJsModule(file) {
  const text = fs.readFileSync(file, 'utf8');
  const i = text.indexOf('module.exports');
  assert.ok(i >= 0, `${path.basename(file)} 不是数据模块`);
  let body = text.slice(i + 'module.exports'.length).trim();
  if (body.startsWith('=')) body = body.slice(1).trim();
  if (body.endsWith(';')) body = body.slice(0, -1);
  return JSON.parse(body);
}

/**
 * 描红画布「已写完的笔画数」三端语义必须一致。
 *
 * 最后一笔通过时，三端都不再把 `index` 自增（自增会越界到 strokes[count]），
 * 而是置一个 done/finished 标志。于是画布**不能**直接拿 index 当完成数，
 * 否则绘制范围是 `0..<count-1`——最后一笔判定通过了、星星弹出来了，
 * 但屏幕上永远看不见它。iOS 曾经就是这样：写完 4 笔和写完 3 笔的
 * 画布像素完全相同。
 *
 * 这条断言直接读三端源码，防止任何一端退化成「用 index 当完成数」。
 */
test('描红最后一笔必须算进已绘制笔画（三端语义一致）', () => {
  const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
  const read = (p) => fs.readFileSync(path.join(root, p), 'utf8');

  // iOS：drawnStrokes 在 finished 时返回全部
  const iosSession = read('ios/HanziPad/Logic/WriteSession.swift');
  assert.match(
    iosSession,
    /var drawnStrokes[\s\S]{0,400}?if finished \{ return count \}/,
    'iOS 的 drawnStrokes 必须在 finished 时返回 count'
  );
  const iosCanvas = read('ios/HanziPad/UI/WriteCanvas.swift');
  assert.match(iosCanvas, /0\.\.<session\.drawnStrokes/, 'iOS 画布应使用 drawnStrokes');
  assert.doesNotMatch(
    iosCanvas,
    /0\.\.<min\(session\.index/,
    'iOS 画布不能直接用 index 当完成数（会漏画最后一笔）'
  );

  // Android：completed 显式处理 done
  const android = read('android/app/src/main/java/com/xiaoxiao/hanzi/ui/pages/WritePage.kt');
  assert.match(
    android,
    /completed = if \(done\) strokes\.count else minOf\(strokeIndex/,
    'Android 的 completed 必须在 done 时取 strokes.count'
  );

  // 小程序：用 accepted 数组累积，最后一笔通过后天然在内
  const mp = read('miniprogram/utils/write-page.js');
  assert.match(mp, /for \(let i = 0; i < this\.accepted\.length; i\+\+\)/,
    '小程序应遍历 accepted 绘制已完成笔画');
  assert.match(mp, /this\.accepted\.push\(/, '小程序每通过一笔要 push 进 accepted');
});
