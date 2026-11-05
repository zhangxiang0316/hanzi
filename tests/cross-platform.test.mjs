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

/** 列目录里的条目名（不递归）。目录不存在时返回空数组，调用方不用自己判。 */
function readDir(rel) {
  const p = path.join(ROOT, rel);
  if (!fs.existsSync(p)) return [];
  return fs.readdirSync(p);
}

function exists(rel) {
  return fs.existsSync(path.join(ROOT, rel));
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

// ---------------------------------------------------------------------------
// 底部导航只在三个 tab 根页面出现
//
// 三端的导航范式不同（小程序原生 tabBar / Android 自绘 BottomBar /
// iOS TabView），但「什么时候该有底部导航」必须一致：只有「换大区」的
// 三个根页面有，往下走的每一步都没有。
//
// 这条曾在 iOS 上漏掉：TabView 推入详情页后底部标签栏还挂在下面，
// 而 Android 和小程序本来就是隐藏的。孩子在三端看到的是两种布局。
// ---------------------------------------------------------------------------

/** iOS 的 AppRoutes 里有几个 navigationDestination */
function iosDestinationCount(src) {
  return (src.match(/\.navigationDestination\(for:/g) || []).length;
}

test('iOS 每个 navigationDestination 都隐藏了 tab 栏', () => {
  const src = read('ios/HanziPad/App/AppState.swift');
  const routes = iosDestinationCount(src);
  const marked = (src.match(/\.pushedScreen\(\)/g) || []).length;

  assert.ok(routes >= 10, `只找到 ${routes} 个 destination，样本不对`);
  // 少一个就意味着那个页面推入后底部还挂着 tab 栏
  assert.equal(marked, routes,
    `${routes} 个 destination 里只有 ${marked} 个调了 pushedScreen()`);
});

test('iOS 的 pushedScreen 真的隐藏 tab 栏', () => {
  const src = read('ios/HanziPad/App/AppState.swift');
  const m = /func pushedScreen\(\)[^{]*\{([\s\S]*?)\n    \}/.exec(src);
  assert.ok(m, '找不到 pushedScreen 的定义');
  assert.match(m[1], /toolbar\(\.hidden, for: \.tabBar\)/,
    'pushedScreen 必须调 toolbar(.hidden, for: .tabBar)');
});

test('Android 底部导航只画在三个 tab 根页面', () => {
  const nav = read('android/app/src/main/java/com/xiaoxiao/hanzi/ui/Nav.kt');
  const roots = /TAB_ROOTS = setOf\(([^)]*)\)/.exec(nav);
  assert.ok(roots, '找不到 TAB_ROOTS');
  const names = roots[1].split(',').map((s) => s.trim()).filter(Boolean);
  assert.deepEqual(names, ['Screen.Index', 'Screen.Practice', 'Screen.Profile'],
    'tab 根应该正好是首页/练习/我的三个');

  // 根页面之外一律不画
  const root = read('android/app/src/main/java/com/xiaoxiao/hanzi/ui/Root.kt');
  assert.match(root, /if \(isTabRoot\(screen\)\)\s*\{\s*BottomBar\(/,
    'BottomBar 必须以 isTabRoot(screen) 为条件');
});

test('小程序 tabBar 只列三个根页面', () => {
  const app = JSON.parse(read('miniprogram/app.json'));
  const pages = (app.tabBar.list || []).map((x) => x.pagePath);
  assert.deepEqual(pages, [
    'pages/index/index',
    'pages/practice/practice',
    'pages/profile/profile',
  ], 'tabBar 只该有首页/练习/我的');
});

test('三端的 tab 根集合一致', () => {
  // 小程序三页 → Android 三个 Screen → iOS 三个 Section
  const root = read('android/app/src/main/java/com/xiaoxiao/hanzi/ui/Nav.kt');
  const androidNames = /TAB_ROOTS = setOf\(([^)]*)\)/.exec(root)[1]
    .split(',').map((s) => s.replace(/.*\./, '').trim());

  const phone = read('ios/HanziPad/App/PhoneRootView.swift');
  const iosNames = [...phone.matchAll(/tab\(\.(\w+),/g)].map((m) => m[1]);

  assert.equal(androidNames.length, iosNames.length,
    `Android ${androidNames.join('/')}，iOS ${iosNames.join('/')}`);
  // Index≈home, Practice≈practice, Profile≈profile
  const pairs = [['Index', 'home'], ['Practice', 'practice'], ['Profile', 'profile']];
  for (const [a, i] of pairs) {
    assert.ok(androidNames.includes(a), `Android 缺 ${a}`);
    assert.ok(iosNames.includes(i), `iOS 缺 ${i}`);
  }
});

// ---------------------------------------------------------------------------
// 主操作按钮的位置
//
// 用户报的是「按钮位置不统一」。查下来根因不是某一页放错了，而是两端对
// 「什么时候该把主操作钉在底部」没有共同约定，于是同一个页面各写各的：
//   - 识字量测试 / 选字做字帖：iOS 钉底，Android 跟着内容滚
//   - 课文页：iOS 跟着内容滚，Android 和小程序钉底
//   - 错题本：iOS 主按钮在列表之后，Android 在列表之前
//
// 定下来的规则：**页面级的唯一主操作钉在底部，次要操作留在内容末尾。**
// 小程序（设计基准）一直是这么做的 —— lesson.wxml 的 .footer 就是 fixed。
// 下面把这条规则锁成断言。

/** 页面源码正文（去掉注释，免得注释里的字样误判） */
function stripComments(src) {
  return src.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
}

test('三端把主操作钉在底部的页面集合一致', () => {
  // iOS：.safeAreaInset(edge: .bottom) 出现在哪些 Page
  const iosFiles = readDir('ios/HanziPad/Pages').filter((f) => f.endsWith('PageView.swift'));
  const iosPinned = iosFiles.filter((f) =>
    /safeAreaInset\(edge:\s*\.bottom\)/.test(stripComments(read('ios/HanziPad/Pages/' + f))));

  // Android：页面根 Column 里有一个「滚动区 + 底部条」结构，
  // 底部条统一是 Surface(color = p.paper, shadowElevation = 8.dp)
  const androidFiles = readDir('android/app/src/main/java/com/xiaoxiao/hanzi/ui/pages')
    .filter((f) => f.endsWith('Page.kt'));
  const androidPinned = androidFiles.filter((f) => {
    const src = stripComments(read('android/app/src/main/java/com/xiaoxiao/hanzi/ui/pages/' + f));
    return /shadowElevation\s*=\s*8\.dp/.test(src);
  });

  // 小程序：WXSS 里的底部条类名不统一——lesson 叫 .footer，
  // vocab / copybook-pick 叫 .foot，两个都是 position: fixed。
  // 一并认，否则会误判成「小程序只有课文页钉底」。
  const mpFiles = readDir('miniprogram/pages').filter((d) => !d.includes('.'));
  const mpPinned = [];
  for (const d of mpFiles) {
    const wxss = 'miniprogram/pages/' + d + '/' + d + '.wxss';
    if (!exists(wxss)) continue;
    const src = stripComments(read(wxss));
    if (/\.(?:footer|foot)\s*\{[^}]*position:\s*fixed/.test(src)) mpPinned.push(d);
  }

  // 钉底的页面：课文、识字量测试、选字做字帖
  // 三端页面文件名不同，所以比数量 + 各自点名（见下一条用例）
  assert.equal(iosPinned.length, androidPinned.length,
    `iOS 钉底 ${iosPinned.length} 页 [${iosPinned}]，` +
    `Android 钉底 ${androidPinned.length} 页 [${androidPinned}]`);
  assert.equal(mpPinned.length, iosPinned.length,
    `小程序钉底 ${mpPinned.length} 页 [${mpPinned}]，` +
    `iOS 钉底 ${iosPinned.length} 页 [${iosPinned}]`);
  assert.ok(iosPinned.length >= 3,
    `只剩 ${iosPinned.length} 页钉底了，主操作位置规则可能被改回去了`);
});

test('小程序三页底部条都是 fixed', () => {
  const cases = [
    ['miniprogram/pages/vocab/vocab.wxss', 'vocab'],
    ['miniprogram/pages/copybook-pick/copybook-pick.wxss', 'copybook-pick'],
    ['miniprogram/pages/lesson/lesson.wxss', 'lesson'],
  ];
  for (const [file, name] of cases) {
    assert.match(stripComments(read(file)),
      /\.(?:footer|foot)\s*\{[^}]*position:\s*fixed/,
      `小程序 ${name} 的底部条应 fixed`);
  }
  // 而且底部条里真的有按钮，不是个空壳
  for (const [file, name] of [
    ['miniprogram/pages/vocab/vocab.wxml', 'vocab'],
    ['miniprogram/pages/copybook-pick/copybook-pick.wxml', 'copybook-pick'],
    ['miniprogram/pages/lesson/lesson.wxml', 'lesson'],
  ]) {
    assert.match(read(file), /<button[^>]*class="btn btn-primary/,
      `小程序 ${name} 的底部条里应有主按钮`);
  }
});

test('识字量测试与选字做字帖两端都钉底', () => {
  const cases = [
    ['ios/HanziPad/Pages/VocabPageView.swift', 'iOS 识字量测试'],
    ['ios/HanziPad/Pages/CopybookPickPageView.swift', 'iOS 选字做字帖'],
    ['android/app/src/main/java/com/xiaoxiao/hanzi/ui/pages/VocabPage.kt', 'Android 识字量测试'],
    ['android/app/src/main/java/com/xiaoxiao/hanzi/ui/pages/CopybookPickPage.kt', 'Android 选字做字帖'],
  ];
  for (const [file, name] of cases) {
    const src = stripComments(read(file));
    const pinned = /safeAreaInset\(edge:\s*\.bottom\)/.test(src) ||
      /shadowElevation\s*=\s*8\.dp/.test(src);
    assert.ok(pinned, `${name} 的主操作没有钉底`);
  }
});

test('课文页三端都把主操作钉在底部', () => {
  // iOS
  assert.match(stripComments(read('ios/HanziPad/Pages/LessonPageView.swift')),
    /safeAreaInset\(edge:\s*\.bottom\)/, 'iOS 课文页主操作应钉底');
  // Android
  assert.match(stripComments(read('android/app/src/main/java/com/xiaoxiao/hanzi/ui/pages/LessonPage.kt')),
    /shadowElevation\s*=\s*8\.dp/, 'Android 课文页主操作应钉底');
  // 小程序（设计基准）
  assert.match(stripComments(read('miniprogram/pages/lesson/lesson.wxss')),
    /\.footer\s*\{[^}]*position:\s*fixed/, '小程序课文页 footer 应 fixed');
});

test('错题本主按钮在列表之后（两端一致）', () => {
  const ios = stripComments(read('ios/HanziPad/Pages/WrongPageView.swift'));
  // iOS: list 在前，HanziButton 在后
  const iosList = ios.indexOf('list');
  const iosBtn = ios.indexOf('练一遍错题');
  assert.ok(iosList >= 0 && iosBtn > iosList,
    'iOS 错题本主按钮应排在列表之后');

  const android = stripComments(
    read('android/app/src/main/java/com/xiaoxiao/hanzi/ui/pages/WrongPage.kt'));
  const aBtn = android.indexOf('重练这些字');
  const aLoop = android.indexOf('items.forEach');
  assert.ok(aLoop >= 0 && aBtn > aLoop,
    'Android 错题本主按钮应排在列表之后（之前跑到了列表上方）');
});
