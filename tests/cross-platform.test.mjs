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
  const iosBtn = ios.indexOf('重练这些字');
  assert.ok(iosList >= 0 && iosBtn > iosList,
    'iOS 错题本主按钮应排在列表之后');

  const android = stripComments(
    read('android/app/src/main/java/com/xiaoxiao/hanzi/ui/pages/WrongPage.kt'));
  const aBtn = android.indexOf('重练这些字');
  const aLoop = android.indexOf('items.forEach');
  assert.ok(aLoop >= 0 && aBtn > aLoop,
    'Android 错题本主按钮应排在列表之后（之前跑到了列表上方）');
});

test('没有页面自己定义一个卡片组件来替掉 HanziCard', () => {
  // AboutPage 曾经有一个 `private fun InfoCard(...)`，里面自己写
  // Surface + radiusCard + 描边 + 内边距，等于把 HanziCard 抄了一遍，
  // 而且抄漏了（还在用 line 描边、16 内边距，HanziCard 已经是 edge + 18）。
  // iOS 的 AboutPage 一直用的就是 HanziCard。
  //
  // 卡片样式一旦按页分叉，改一处不会全局生效——这正是「两端样式不统一」
  // 反复出现的原因。所以这里禁掉「自定义一个圆角+描边的卡片函数」这种写法。
  const dir = 'android/app/src/main/java/com/xiaoxiao/hanzi/ui/pages';
  const offenders = [];
  for (const f of readDir(dir).filter((x) => x.endsWith('.kt'))) {
    const src = stripComments(read(dir + '/' + f));
    // 找到每个 private 函数的签名 + 前 400 字符正文，看是不是手搓卡片
    const re = /private fun (\w*(?:Card|Panel|Box)\w*)\s*\([\s\S]{0,400}?\{([\s\S]{0,400})/g;
    for (const m of src.matchAll(re)) {
      const body = m[2];
      if (/RoundedCornerShape\(Dimens\.radiusCard\.dp\)/.test(body) &&
          /BorderStroke\(/.test(body)) {
        offenders.push(`${f}:${m[1]}`);
      }
    }
  }
  assert.deepEqual(offenders, [],
    `这些自定义卡片函数应当直接用 HanziCard：${offenders.join(', ')}`);
});

test('iOS Pages/ 的 Swift 文件括号配平', () => {
  // 为什么需要这一条：`ios/Package.swift` 只把 Data/Logic/UI 里少数纯 Swift
  // 文件放进 HanziCore target，**Pages/ 因为依赖 SwiftUI 不在里面**。
  // 所以 `swift test` 根本不编译 Pages/——那 368 个用例全绿，
  // 页面里写坏一个括号也照样「通过」，只有 xcodebuild 才会报错。
  //
  // 这条检查很便宜，但正好抓住用脚本批量改页面时最常见的破坏：括号不配平。
  // 真的发生过：把 CopybookPageView 的汇总卡改成 HanziCard 时多删了一个 `}`，
  // swift test 368 全绿，xcodebuild 报 4 个 "Attribute 'private' can only be
  // used in a non-local scope"。
  const dir = 'ios/HanziPad';
  const files = [];
  const walk = (d) => {
    for (const e of fs.readdirSync(path.join(ROOT, d), { withFileTypes: true })) {
      const rel = d + '/' + e.name;
      if (e.isDirectory()) walk(rel);
      else if (e.name.endsWith('.swift')) files.push(rel);
    }
  };
  walk(dir);
  assert.ok(files.length > 20, `只找到 ${files.length} 个 Swift 文件，样本不对`);

  const bad = [];
  for (const f of files) {
    let src = read(f);
    // 去掉字符串字面量与注释，避免里面的花括号干扰计数
    src = src.replace(/"""[\s\S]*?"""/g, '""');
    src = src.replace(/"(?:[^"\\\n]|\\.)*"/g, '""');
    src = src.replace(/\/\*[\s\S]*?\*\//g, '');
    src = src.replace(/^\s*\/\/.*$/gm, '');
    let depth = 0;
    for (const ch of src) {
      if (ch === '{') depth++;
      else if (ch === '}') depth--;
      if (depth < 0) break;
    }
    if (depth !== 0) bad.push(`${f} (差 ${depth})`);
  }
  assert.deepEqual(bad, [], `这些文件的括号不配平：${bad.join(', ')}`);
});

test('题库的汉字题干用笔形画，不是系统字体', () => {
  // iOS 的 promptView 对 promptKind == "char" 用 HanziView（笔顺轮廓），
  // Android 曾经一律 Text + 62sp —— 同一个字在详情页是笔形、
  // 在题干里是宋体，看着像两个 App。
  //
  // 为什么是源码扫描而不是截图断言：Quiz.build 的 seed 默认取
  // System.currentTimeMillis()，每次跑抽到的题型都不同，
  // 有时题干根本不是汉字。像素断言会时绿时红——我踩过。
  const android = stripComments(read('android/app/src/main/java/com/xiaoxiao/hanzi/ui/pages/QuizPage.kt'));
  assert.match(
    android,
    /promptKind == "char"[\s\S]{0,200}HanziGlyph\(/,
    'Android 题库页的汉字题干应当走 HanziGlyph，而不是 Text'
  );

  const ios = stripComments(read('ios/HanziPad/Pages/QuizPageView.swift'));
  assert.match(
    ios,
    /case "char":[\s\S]{0,300}HanziView\(/,
    'iOS 题库页的汉字题干应当走 HanziView'
  );
});

test('界面上显示的版本号都从构建产物读，不硬编码', () => {
  // 这个 bug 复发过：Android 的 AboutPage 和 ProfilePage 都曾写死
  // "v1.0.0"，版本走到 1.1.0 之后页面上仍然显示 1.0.0。
  // 修了 AboutPage 却漏了 ProfilePage，所以用扫描守住。
  const androidPages = readDir('android/app/src/main/java/com/xiaoxiao/hanzi/ui/pages')
    .filter((f) => f.endsWith('.kt'));
  const bad = [];
  for (const f of androidPages) {
    const src = stripComments(read(`android/app/src/main/java/com/xiaoxiao/hanzi/ui/pages/${f}`));
    // 只看界面上的 "v1.2.3" 字面量，不看注释
    if (/["'][^"']*v\d+\.\d+\.\d+[^"']*["']/.test(src)) {
      bad.push(f);
    }
  }
  assert.deepEqual(bad, [], `这些页面把版本号写死了：${bad.join(', ')}`);
});

test('结果页的星级与评语判据三端一致', () => {
  // 同一场测验在不同端亮不同数量的星，不是配色差异，
  // 是同一个分数得出不同结论。第三次核对时发现：
  //   小程序 60/85/100，Android 60/85/100，iOS 90/70/50。
  const ios = stripComments(read('ios/HanziPad/Pages/ResultPageView.swift'));
  const android = stripComments(read('android/app/src/main/java/com/xiaoxiao/hanzi/ui/pages/ResultPage.kt'));

  assert.match(ios, /rate >= 100[\s\S]{0,60}return 3/, 'iOS 三星阈值应为 100');
  assert.match(ios, /rate >= 85[\s\S]{0,60}return 2/, 'iOS 二星阈值应为 85');
  assert.match(ios, /rate >= 60[\s\S]{0,60}return 1/, 'iOS 一星阈值应为 60');

  assert.match(android, /rate >= 100 -> 3/, 'Android 三星阈值应为 100');
  assert.match(android, /rate >= 85 -> 2/, 'Android 二星阈值应为 85');
  assert.match(android, /rate >= 60 -> 1/, 'Android 一星阈值应为 60');

  const mp = stripComments(read('miniprogram/pages/result/result.wxml'));
  assert.match(mp, /rate >= 60/, '小程序一星阈值应为 60');
  assert.match(mp, /rate >= 85/, '小程序二星阈值应为 85');
  assert.match(mp, /rate >= 100/, '小程序三星阈值应为 100');
});

test('结果页的正确率圆环三端都有', () => {
  const ios = stripComments(read('ios/HanziPad/Pages/ResultPageView.swift'));
  assert.match(ios, /ProgressRing\(/, 'iOS 结果页应有正确率圆环');

  const android = stripComments(read('android/app/src/main/java/com/xiaoxiao/hanzi/ui/pages/ResultPage.kt'));
  assert.match(android, /ProgressRing\(/, 'Android 结果页应有正确率圆环');

  const mp = stripComments(read('miniprogram/pages/result/result.wxml'));
  assert.match(mp, /class="ring"/, '小程序结果页应有正确率圆环');
});

test('答题反馈的文案与配色三端一致', () => {
  // 同一屏上说两遍：选项格子上已经用 ✓/✕ 标出正确答案，
  // iOS 原来还在反馈条上重复写「答案是「X」」。
  const ios = stripComments(read('ios/HanziPad/Pages/QuizPageView.swift'));
  const android = stripComments(read('android/app/src/main/java/com/xiaoxiao/hanzi/ui/pages/QuizPage.kt'));
  const mp = stripComments(read('miniprogram/pages/quiz/quiz.wxml'));

  for (const [name, src] of [['iOS', ios], ['Android', android], ['小程序', mp]]) {
    assert.ok(src.includes('答对啦！'), `${name} 的答对文案应为「答对啦！」`);
    assert.ok(src.includes('再想一想'), `${name} 的答错文案应为「再想一想」`);
  }

  // 答错底色：clay 是两端通用的「错」语义色。
  //
  // 断言必须盯住**反馈卡那一处**，不能只搜 "claySoft"——iOS 文件里
  // 别的地方（选项格底色）也用了 claySoft，第一次写宽了就抓不到回退。
  assert.match(
    ios,
    /picked == q\.answer \? Palette\.jadeSoft : Palette\.claySoft/,
    'iOS 答错反馈底色应为 claySoft（与 Android 一致）'
  );
  assert.match(
    android,
    /picked == q\.answer\) p\.jadeSoft else p\.claySoft/,
    'Android 答错反馈底色应为 claySoft'
  );
});

test('答题反馈的继续按钮文案三端一致', () => {
  const ios = stripComments(read('ios/HanziPad/Pages/QuizPageView.swift'));
  const android = stripComments(read('android/app/src/main/java/com/xiaoxiao/hanzi/ui/pages/QuizPage.kt'));
  const mp = stripComments(read('miniprogram/pages/quiz/quiz.wxml'));

  for (const [name, src] of [['iOS', ios], ['Android', android], ['小程序', mp]]) {
    assert.ok(src.includes('看结果'), `${name} 最后一题应写「看结果」`);
    assert.ok(!src.includes('下一题'), `${name} 不该同时出现「下一题」（应为「继续」）`);
  }
});

test('错题本的按钮文案与顺序三端一致', () => {
  // 主操作「重练这些字」在列表之后，次要「清空错题本」再往下。
  // iOS 原来写「练一遍错题」，且把「清空」放进导航栏——
  // 同一个页面两端按钮的文案和位置都不同。
  const ios = stripComments(read('ios/HanziPad/Pages/WrongPageView.swift'));
  const android = stripComments(read('android/app/src/main/java/com/xiaoxiao/hanzi/ui/pages/WrongPage.kt'));
  const mp = stripComments(read('miniprogram/pages/wrong/wrong.wxml'));

  for (const [name, src] of [['iOS', ios], ['Android', android], ['小程序', mp]]) {
    assert.ok(src.includes('重练这些字'), `${name} 主操作应为「重练这些字」`);
    assert.ok(src.includes('清空错题本'), `${name} 次要操作应为「清空错题本」`);
  }
  // 清空不该出现在导航栏里（小程序和 Android 都放在内容末尾）
  assert.ok(!/ToolbarItem[\s\S]{0,120}清空/.test(ios), 'iOS 的「清空」不应放在导航栏');
});

test('错题本空状态不额外放「去练习」按钮', () => {
  // 底部标签栏本来就有「练习」，空状态再放一个是重复入口。
  const ios = stripComments(read('ios/HanziPad/Pages/WrongPageView.swift'));
  const android = stripComments(read('android/app/src/main/java/com/xiaoxiao/hanzi/ui/pages/WrongPage.kt'));
  assert.ok(!android.includes('去练习'), 'Android 空状态不该有「去练习」按钮');
  assert.ok(!ios.includes('去练习'), 'iOS 空状态不该有「去练习」按钮');
});

test('课文页的主操作是「开始/继续学习」，练习与描红降为次要', () => {
  // 小程序 lesson.wxml 的底部条只有一颗「开始学习 · 字」，Android 也是。
  // iOS 原来把「本课练习」「整课描红」并排当主操作——进到一课的第一件事
  // 不是开始学，而是去测验，顺序反了。
  const ios = stripComments(read('ios/HanziPad/Pages/LessonPageView.swift'));
  const android = stripComments(read('android/app/src/main/java/com/xiaoxiao/hanzi/ui/pages/LessonPage.kt'));
  const mp = stripComments(read('miniprogram/pages/lesson/lesson.wxml'));

  for (const [name, src] of [['iOS', ios], ['Android', android], ['小程序', mp]]) {
    assert.ok(src.includes('开始学习'), `${name} 应有「开始学习」主操作`);
    assert.ok(src.includes('继续学习'), `${name} 应有「继续学习」状态文案`);
  }
  // iOS 的「本课练习」必须出现在主按钮之后
  const main = ios.indexOf('开始学习');
  const quiz = ios.indexOf('本课练习');
  assert.ok(main >= 0 && quiz > main, 'iOS 的「本课练习」应排在「开始学习」之后');
});

test('详情页的写字按钮文案两端一致', () => {
  // 要求会写的字叫「描红跟写」，只要求认的叫「想写就试试」。
  // iOS 原来写「开始描红」——同一颗按钮两种叫法。
  const ios = stripComments(read('ios/HanziPad/Pages/DetailPageView.swift'));
  const android = stripComments(read('android/app/src/main/java/com/xiaoxiao/hanzi/ui/pages/DetailPage.kt'));

  for (const [name, src] of [['iOS', ios], ['Android', android]]) {
    assert.ok(src.includes('描红跟写'), `${name} 应写「描红跟写」`);
    assert.ok(src.includes('想写就试试'), `${name} 应写「想写就试试」`);
  }
  assert.ok(!ios.includes('开始描红'), 'iOS 不该再出现「开始描红」');
});

test('听写页的跳过按钮文案与 Android 一致', () => {
  // iOS 原来写 `justFinished ? "下一个" : "放弃这个字"`，
  // 但两个分支做的事完全一样（都是 next(plan)）——同一颗按钮
  // 会显示两个不同的词，做的事却相同。文案跟 Android 统一为「跳过这个字」。
  const ios = stripComments(read('ios/HanziPad/Pages/DictationPageView.swift'));
  const android = stripComments(read('android/app/src/main/java/com/xiaoxiao/hanzi/ui/pages/DictationPage.kt'));

  assert.ok(ios.includes('跳过这个字'), 'iOS 听写的跳过按钮应写「跳过这个字」');
  assert.ok(android.includes('跳过这个字'), 'Android 听写的跳过按钮应写「跳过这个字」');
  assert.ok(!ios.includes('放弃这个字'), 'iOS 不该再出现「放弃这个字」');
});

test('同一颗按钮不该用三元表达式换文案', () => {
  // 上面那条的具体形态：文案随状态变化，但分支行为相同。
  // 这种写法让人以为做了两件事，实际只做了一件。
  const ios = stripComments(read('ios/HanziPad/Pages/DictationPageView.swift'));
  assert.ok(
    !/HanziButton\(title:\s*[a-zA-Z]\w*\s*\?/.test(ios),
    'iOS 听写页的 HanziButton 标题不该用三元表达式'
  );
});
