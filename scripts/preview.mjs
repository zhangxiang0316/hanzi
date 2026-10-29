#!/usr/bin/env node
/**
 * 预览服务 + 截图/断言脚本
 *   node scripts/preview.mjs            # 启动 http://127.0.0.1:8788 预览
 *   node scripts/preview.mjs --shots    # 用 Chrome 截图并跑 DOM 断言
 */
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { spawn } from 'node:child_process';

const require = createRequire(import.meta.url);
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const PORT = Number(process.env.PREVIEW_PORT || 8788);

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.woff2': 'font/woff2',
  '.txt': 'text/plain; charset=utf-8',
};

function listModules() {
  const out = [];
  const walk = (dir) => {
    for (const name of fs.readdirSync(dir)) {
      const p = path.join(dir, name);
      const st = fs.statSync(p);
      if (st.isDirectory()) walk(p);
      else if (name.endsWith('.js')) out.push(path.relative(ROOT, p));
    }
  };
  walk(path.join(ROOT, 'miniprogram'));
  return out.sort();
}

function createServer() {
  return http.createServer((req, res) => {
    const url = decodeURIComponent(req.url.split('?')[0]);
    if (url === '/' || url === '/index.html') {
      res.writeHead(200, { 'Content-Type': MIME['.html'] });
      res.end(fs.readFileSync(path.join(ROOT, 'preview/index.html')));
      return;
    }
    if (url === '/favicon.ico') {
      res.writeHead(204);
      res.end();
      return;
    }
    if (url === '/preview/module-list.json') {
      res.writeHead(200, { 'Content-Type': MIME['.json'] });
      res.end(JSON.stringify(listModules()));
      return;
    }
    const file = path.join(ROOT, url);
    if (!file.startsWith(ROOT) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
      res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end('404 ' + url);
      return;
    }
    res.writeHead(200, { 'Content-Type': MIME[path.extname(file)] || 'application/octet-stream' });
    fs.createReadStream(file).pipe(res);
  });
}

async function shots() {
  const HARD_TIMEOUT = 150000;
  const guard = setTimeout(() => {
    console.error('✗ 截图流程超时（150s），可能是浏览器启动或页面加载卡住');
    process.exit(1);
  }, HARD_TIMEOUT);
  guard.unref && guard.unref();
  const step = (msg) => console.log('  · ' + msg);
  const puppeteer = require('puppeteer-core');
  const CHROME =
    process.env.CHROME_PATH ||
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
  const outDir = path.join(ROOT, 'preview/screenshots');
  fs.mkdirSync(outDir, { recursive: true });
  step('启动浏览器');
  const browser = await puppeteer.launch({
    executablePath: CHROME,
    headless: 'new',
    args: ['--no-sandbox', '--font-render-hinting=none'],
  });
  const page = await browser.newPage();
  // 页面内部导航是异步的，统一用轮询等待条件，避免 networkidle 卡死
  async function noWait(p, fn) {
    await p.waitForFunction(fn, { timeout: 15000, polling: 100 });
  }
  await page.setViewport({ width: 390, height: 844, deviceScaleFactor: 2 });
  const logs = [];
  page.on('console', (m) => logs.push(`${m.type()}: ${m.text()}`));
  page.on('pageerror', (e) => logs.push('pageerror: ' + e.message));

  const scenarios = [
    { name: '01-index', hash: '#/pages/index/index', wait: 500 },
    { name: '02-unit', hash: '#/pages/unit/unit?book=1a', wait: 500 },
    { name: '03-lesson', hash: '#/pages/lesson/lesson?lesson=1a-s4', wait: 500 },
    { name: '04-detail', hash: '#/packageStrokes/pages/detail/detail?ch=%E6%97%A5&lesson=1a-s4', wait: 2200 },
    { name: '05-write', hash: '#/packageStrokes/pages/write/write?ch=%E6%97%A5', wait: 900 },
    { name: '06-practice', hash: '#/pages/practice/practice', wait: 600 },
    { name: '07-profile', hash: '#/pages/profile/profile', wait: 500 },
    { name: '08-wrong', hash: '#/pages/wrong/wrong', wait: 500 },
    { name: '09-about', hash: '#/pages/about/about', wait: 400 },
  ];

  const failures = [];
  step('逐页加载');
  for (const s of scenarios) {
    await page.goto(`http://127.0.0.1:${PORT}/${s.hash}`, { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForFunction('window.__ready === true', { timeout: 20000 });
    await new Promise((r) => setTimeout(r, s.wait));
    // 关闭系统字体缺失导致的空渲染，断言页面有内容
    const metrics = await page.evaluate(() => {
      const host = document.querySelector('.page-host');
      const scroll = document.querySelector('.page-scroll');
      const rect = host.getBoundingClientRect();
      return {
        height: rect.height,
        text: host.innerText.trim().length,
        scrollWidth: scroll.scrollWidth,
        clientWidth: scroll.clientWidth,
        title: document.getElementById('nav-title').textContent,
        canvases: Array.from(document.querySelectorAll('canvas')).map((c) => {
          const ctx = c.getContext('2d');
          const data = ctx.getImageData(0, 0, c.width, c.height).data;
          let ink = 0;
          for (let i = 3; i < data.length; i += 4) if (data[i] > 10) ink++;
          return { w: c.width, h: c.height, ink };
        }),
      };
    });
    if (metrics.height < 300) failures.push(`${s.name}: 页面高度异常 ${metrics.height}`);
    if (metrics.text < 20) failures.push(`${s.name}: 页面几乎没有文字`);
    if (metrics.scrollWidth > metrics.clientWidth + 1) {
      failures.push(`${s.name}: 横向溢出 ${metrics.scrollWidth} > ${metrics.clientWidth}`);
    }
    if (s.name.includes('detail') || s.name.includes('write')) {
      const canvas = metrics.canvases[0];
      if (!canvas || canvas.ink < 500) failures.push(`${s.name}: 画布没有画出来 (ink=${canvas ? canvas.ink : 'none'})`);
    }
    await page.screenshot({ path: path.join(outDir, s.name + '.png') });
    console.log(`  ✓ ${s.name}  ${metrics.title}  h=${Math.round(metrics.height)} text=${metrics.text}`);
  }

  // 交互断言：答一题 -> 反馈 -> 继续
  await page.goto(`http://127.0.0.1:${PORT}/#/pages/practice/practice`, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForFunction('window.__ready === true', { timeout: 20000 });
  await page.evaluate(() => window.__preview.navigate('/pages/quiz/quiz?from=preview'));
  await noWait(page, () => document.querySelectorAll('.option').length === 4);
  const quizInfo = await page.evaluate(() => {
    const opts = document.querySelectorAll('.option');
    return { options: opts.length, prompt: (document.querySelector('.prompt-text') || {}).textContent || '' };
  });
  if (quizInfo.options !== 4) failures.push(`练习页选项数异常: ${quizInfo.options}`);
  await page.waitForSelector('.option', { timeout: 10000 });
  await page.screenshot({ path: path.join(outDir, '10-quiz.png') });
  await page.evaluate(() => document.querySelectorAll('.option')[0].click());
  await new Promise((r) => setTimeout(r, 250));
  const feedback = await page.evaluate(() => {
    const fb = document.querySelector('.feedback');
    return fb ? fb.innerText : '';
  });
  if (!feedback) failures.push('答题后没有出现反馈');
  await page.screenshot({ path: path.join(outDir, '11-quiz-feedback.png') });

  // 首页点击任务卡应触发跳转
  await page.goto(`http://127.0.0.1:${PORT}/#/pages/index/index`, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForFunction('window.__ready === true', { timeout: 20000 });
  await page.evaluate(() => document.querySelector('.task-card').click());
  await new Promise((r) => setTimeout(r, 400));
  const afterTap = await page.evaluate(() => ({
    hash: location.hash,
    events: window.__preview.events,
  }));
  if (!afterTap.events.length) failures.push('点击今日任务卡没有触发跳转');
  await page.screenshot({ path: path.join(outDir, '12-after-tap.png') });

  step('可点元素必须看得出来是按钮');
  // 两个曾经踩过的坑：
  //  1) `button.btn { background: transparent }` 特异性 (0,1,1) 高于
  //     `.btn-primary` (0,1,0)，把渐变全盖掉 → 白字 + 透明底，按钮消失。
  //  2) 原生 button 在 display:flex 下宽度退化成内容宽度，加上 margin:0
  //     → 整行按钮只有半个屏宽、贴在左边（真机上才复现）。
  // 所以这里同时校验：背景、对比度、铺满、左右对称、文字垂直居中。
  // [页面名, hash, 至少应有的按钮数]
  const btnPages = [
    ['课文页', '#/pages/lesson/lesson?lesson=1a-s1', 1],
    ['一年级详情页', '#/packageStrokes/pages/detail/detail?ch=%E6%97%A5&lesson=1a-s4', 3],
    ['三年级详情页', '#/packageStrokes3/pages/detail/detail?ch=%E9%B9%A6&lesson=3a-k15', 3],
  ];
  let btnCount = 0;
  for (const [label, hash, minCount] of btnPages) {
    await page.goto(`http://127.0.0.1:${PORT}/${hash}`, {
      waitUntil: 'domcontentloaded',
      timeout: 30000,
    });
    await page.waitForFunction('window.__ready === true', { timeout: 20000 }).catch(() => {});
    await new Promise((r) => setTimeout(r, 900));

    const probe = await page.evaluate(() => {
      const parse = (c) => {
        const m = (c || '').match(/[\d.]+/g);
        return m ? m.map(Number) : null;
      };
      const effBg = (el) => {
        const stack = [];
        let n = el;
        while (n && n !== document.documentElement) {
          stack.push(n);
          n = n.parentElement;
        }
        let rgb = [255, 255, 255];
        let gradient = false;
        for (let i = stack.length - 1; i >= 0; i--) {
          const cs = getComputedStyle(stack[i]);
          if (cs.backgroundImage && cs.backgroundImage !== 'none') gradient = true;
          const c = parse(cs.backgroundColor);
          if (!c) continue;
          const a = c.length > 3 ? c[3] : 1;
          if (!a) continue;
          rgb = [0, 1, 2].map((k) => rgb[k] * (1 - a) + c[k] * a);
        }
        return { rgb, gradient };
      };
      const relLum = (c) => {
        const f = (v) => {
          v /= 255;
          return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
        };
        return 0.2126 * f(c[0]) + 0.7152 * f(c[1]) + 0.0722 * f(c[2]);
      };

      return [...document.querySelectorAll('.btn')].map((el) => {
        const cs = getComputedStyle(el);
        const own = parse(cs.backgroundColor) || [0, 0, 0, 0];
        const ownAlpha = own.length > 3 ? own[3] : 1;
        const hasOwnBg = cs.backgroundImage !== 'none' || ownAlpha > 0.05;
        const bg = effBg(el);
        const fg = parse(cs.color) || [0, 0, 0];
        const L1 = relLum(fg);
        const L2 = relLum(bg.rgb);
        const ratio = (Math.max(L1, L2) + 0.05) / (Math.min(L1, L2) + 0.05);

        // 几何：横向是否铺满并居中，文字是否垂直居中
        const box = el.getBoundingClientRect();
        const holder = el.parentElement ? el.parentElement.getBoundingClientRect() : box;
        const range = document.createRange();
        range.selectNodeContents(el);
        const tb = range.getBoundingClientRect();
        return {
          text: (el.textContent || '').trim().slice(0, 10),
          cls: String(el.className),
          block: String(el.className).indexOf('btn-block') >= 0,
          hasOwnBg,
          gradient: bg.gradient,
          ratio: Number(ratio.toFixed(2)),
          width: Math.round(box.width),
          parentW: Math.round(holder.width),
          left: Math.round(box.left - holder.left),
          right: Math.round(holder.right - box.right),
          midGap: Math.round((box.top + box.height / 2 - (tb.top + tb.height / 2)) * 10) / 10,
          overflow: tb.height > box.height + 1,
          // 同级的按钮个数：>0 说明是并排布局（如详情页的两个操作按钮），
          // 各占一半是设计意图，不该要求铺满整行
          siblings: el.parentElement ? el.parentElement.querySelectorAll('.btn').length - 1 : 0,
        };
      });
    });

    if (probe.length < minCount) {
      failures.push(`${label} 只渲染出 ${probe.length} 个按钮，预期至少 ${minCount} 个`);
    }
    let hasBlock = false;
    for (const b of probe) {
      btnCount++;
      if (!b.hasOwnBg) {
        failures.push(`${label} 的按钮「${b.text}」没有背景（[${b.cls}]），会看不见`);
      } else if (!b.gradient && b.ratio < 3) {
        failures.push(`${label} 的按钮「${b.text}」文字/背景对比度仅 ${b.ratio}`);
      }
      if (!b.block) continue;
      hasBlock = true;
      if (b.siblings === 0) {
        // 独占一行：必须铺满并左右对称（用户反馈的“半个屏宽、贴左”就是这种）
        if (b.width < b.parentW * 0.9) {
          failures.push(`${label} 的按钮「${b.text}」只占 ${b.width}/${b.parentW}，没有铺满整行`);
        }
        if (Math.abs(b.left - b.right) > 2) {
          failures.push(
            `${label} 的按钮「${b.text}」左右不对称（左 ${b.left} / 右 ${b.right}），没有居中`
          );
        }
      } else {
        // 并排布局：只需保证不被压得过窄
        if (b.width < b.parentW * 0.4) {
          failures.push(`${label} 的按钮「${b.text}」并排时过窄 ${b.width}/${b.parentW}`);
        }
      }
      if (Math.abs(b.midGap) > 3) {
        failures.push(`${label} 的按钮「${b.text}」文字没有垂直居中（偏移 ${b.midGap}px）`);
      }
      if (b.overflow) {
        failures.push(`${label} 的按钮「${b.text}」文字超出按钮高度`);
      }
    }
    if (!hasBlock) failures.push(`${label} 没有找到整行按钮，无法校验布局`);
  }
  console.log(`  ✓ 按钮可见性与布局  ${btnCount} 个按钮：背景、对比度、铺满、居中均正常`);

  step('练习页册次芯片：文字必须居中');
  // 踩过的坑：芯片用 `empty` 表示"还没学过"，而 app.wxss 里的全局空状态
  // 工具类 `.empty` 带 text-align:center。于是文字居中纯属"借用"——
  // 某册一旦有了学习记录（移除 empty 类），文字立刻掉回左对齐。
  await page.goto(`http://127.0.0.1:${PORT}/#/pages/practice/practice`, {
    waitUntil: 'domcontentloaded',
    timeout: 30000,
  });
  await page.waitForFunction('window.__ready === true', { timeout: 20000 });
  await new Promise((r) => setTimeout(r, 900));

  const chipGaps = () =>
    page.evaluate(() => {
      const chip = document.querySelector('.book-chip');
      if (!chip) return null;
      const box = chip.getBoundingClientRect();
      const gaps = [];
      chip.querySelectorAll('.book-chip-name, .book-chip-sub').forEach((el) => {
        const range = document.createRange();
        range.selectNodeContents(el);
        const t = range.getBoundingClientRect();
        if (!t.width) return;
        gaps.push({
          text: (el.textContent || '').trim().slice(0, 8),
          left: Math.round(t.left - box.left),
          right: Math.round(box.right - t.right),
        });
      });
      return { cls: String(chip.className), gaps };
    });

  const withNew = await chipGaps();
  if (!withNew) failures.push('练习页没有册次芯片');
  // 模拟"这册已经有学习记录"：页面会移除淡化类
  await page.evaluate(() => {
    const chip = document.querySelector('.book-chip');
    chip.className = String(chip.className).replace(/\s*is-new\s*/g, ' ').trim();
  });
  const withoutNew = await chipGaps();

  for (const [label, state] of [
    ['未学过', withNew],
    ['已学过', withoutNew],
  ]) {
    if (!state) continue;
    for (const g of state.gaps) {
      if (Math.abs(g.left - g.right) > 4) {
        failures.push(
          `练习页册次芯片（${label}）「${g.text}」没有居中：左 ${g.left} / 右 ${g.right}`
        );
      }
    }
  }
  if (withNew && withoutNew) {
    console.log(
      `  ✓ 册次芯片居中  未学过 ${withNew.gaps.map((g) => g.left + '/' + g.right).join(' ')}` +
        ` · 已学过 ${withoutNew.gaps.map((g) => g.left + '/' + g.right).join(' ')}`
    );
  }

  step('我的页 当前册次：换行后要对齐，不能是压扁的胶囊');
  // 踩过的坑：八个册次一行放不下要换行，但容器还留着单行时的
  // border-radius: 999rpx。两行 60px 高的方块配 519px 圆角，第一行和
  // 最后一行的边缘格子全压在圆弧上；而且是 6+2 排布，第二行只有两个
  // 格子居中，看着像飘在外面。现在改成固定 4 列 grid，正好两行各四个。
  await page.goto(`http://127.0.0.1:${PORT}/#/pages/profile/profile`, {
    waitUntil: 'domcontentloaded',
    timeout: 30000,
  });
  await page.waitForFunction('window.__ready === true', { timeout: 20000 });
  await new Promise((r) => setTimeout(r, 900));

  const bookSeg = await page.evaluate(() => {
    const seg = document.querySelector('.seg-grid');
    if (!seg) return { missing: true };
    const sb = seg.getBoundingClientRect();
    const cs = getComputedStyle(seg);
    const radius = parseFloat(cs.borderTopLeftRadius) || 0;
    const pad = parseFloat(cs.paddingTop) || 0;
    const items = Array.from(seg.querySelectorAll('.seg-item'));
    const rows = new Map();
    const outside = [];
    for (const it of items) {
      const b = it.getBoundingClientRect();
      const key = Math.round(b.top);
      if (!rows.has(key)) rows.set(key, []);
      rows.get(key).push(Math.round(b.left));
      // 格子必须完全落在容器内
      if (b.left < sb.left - 0.5 || b.right > sb.right + 0.5) outside.push(it.textContent.trim());
      if (b.top < sb.top - 0.5 || b.bottom > sb.bottom + 0.5) outside.push(it.textContent.trim());
    }
    // 格子外角要落在圆角弧线内侧，否则角落格子会露出米色轨道
    // 条件：padding ≥ radius × (1 - 1/√2)
    const needPad = radius * (1 - Math.SQRT1_2);
    return {
      count: items.length,
      rowSizes: Array.from(rows.values()).map((v) => v.length),
      columnsAligned: (() => {
        const cols = Array.from(rows.values());
        if (cols.length < 2) return true;
        const a = cols[0].map((x) => x - cols[0][0]);
        return cols.every((row) => row.length === a.length && row.every((x, i) => Math.abs(x - row[0] - a[i]) <= 1));
      })(),
      radius,
      pad,
      needPad,
      height: sb.height,
      pillShaped: radius >= sb.height / 2,
      overflow: seg.scrollWidth > seg.clientWidth + 1,
      outside,
    };
  });

  if (bookSeg.missing) {
    failures.push('我的页找不到 .seg-grid（当前册次选择器）');
  } else {
    if (bookSeg.count !== 8) failures.push(`当前册次应有 8 个格子，实际 ${bookSeg.count}`);
    if (bookSeg.rowSizes.length !== 2) {
      failures.push(`当前册次应排成 2 行，实际 ${bookSeg.rowSizes.length} 行`);
    } else if (!bookSeg.rowSizes.every((n) => n === 4)) {
      failures.push(`当前册次应为 4+4 两行，实际 ${bookSeg.rowSizes.join('+')}`);
    }
    if (!bookSeg.columnsAligned) failures.push('当前册次换行后上下两行没有对齐');
    if (bookSeg.outside.length) {
      failures.push(`当前册次有格子超出容器: ${bookSeg.outside.join(', ')}`);
    }
    if (bookSeg.overflow) failures.push('当前册次出现横向溢出');
    if (bookSeg.pillShaped) {
      failures.push(
        `当前册次换行后仍是胶囊圆角（圆角 ${bookSeg.radius.toFixed(1)}px ≥ 高度一半 ${(bookSeg.height / 2).toFixed(1)}px），` +
          '边缘格子会压在弧线上'
      );
    }
    if (bookSeg.pad < bookSeg.needPad - 0.5) {
      failures.push(
        `当前册次内边距 ${bookSeg.pad.toFixed(1)}px 小于圆角要求的 ${bookSeg.needPad.toFixed(1)}px，` +
          '角落格子会露出轨道底色'
      );
    }
    console.log(
      `  ✓ 当前册次  4+4 两行 · 圆角 ${bookSeg.radius.toFixed(1)}px < 高度一半 ` +
        `${(bookSeg.height / 2).toFixed(1)}px · 内边距 ${bookSeg.pad.toFixed(1)}px ≥ ${bookSeg.needPad.toFixed(1)}px`
    );
  }

  step('首页：自定义导航不能让系统胶囊压住内容');
  // 首页是 navigationStyle: custom，页面从屏幕顶端开始画，而微信右上角的
  // 胶囊按钮（··· ⊙）是系统浮层、永远不躲。只留状态栏就排版的话，
  // 右上角「学了几天」药丸会被盖住 —— 真机上就是这么被遮的。
  await page.goto(`http://127.0.0.1:${PORT}/#/pages/index/index`, {
    waitUntil: 'domcontentloaded',
    timeout: 30000,
  });
  await page.waitForFunction('window.__ready === true', { timeout: 20000 });
  await new Promise((r) => setTimeout(r, 900));

  const capsuleCheck = await page.evaluate(() => {
    const capsule = document.getElementById('nav-capsule');
    if (!capsule || capsule.hidden) return { skipped: true };
    const cap = capsule.getBoundingClientRect();
    const hits = [];
    document.querySelectorAll('#page-root *').forEach((el) => {
      const b = el.getBoundingClientRect();
      if (b.width < 1 || b.height < 1) return;
      const cs = getComputedStyle(el);
      const bg = cs.backgroundColor;
      const bgOpaque = !!bg && bg !== 'transparent' && !/rgba\(0, 0, 0, 0\)/.test(bg);
      const bordered = parseFloat(cs.borderTopWidth) > 0 && cs.borderTopStyle !== 'none';
      const rounded = parseFloat(cs.borderTopLeftRadius) > 0;
      // 只关心「有内容」的元素：有直接文字，或者是有背景的圆角/描边组件。
      // 整页背景容器本来就铺在胶囊底下，不算遮挡。
      let direct = '';
      for (const n of el.childNodes) if (n.nodeType === 3) direct += n.textContent;
      const hasText = direct.trim().length > 0;
      if (!hasText && !(bgOpaque && (bordered || rounded))) return;
      const hit =
        !(b.right <= cap.left || b.left >= cap.right || b.bottom <= cap.top || b.top >= cap.bottom);
      if (!hit) return;
      hits.push({
        cls: String(el.className || el.tagName).slice(0, 40),
        text: (direct || el.textContent || '').trim().slice(0, 12),
        rect: [b.left, b.top, b.right, b.bottom].map(Math.round),
      });
    });
    return {
      skipped: false,
      capsule: [cap.left, cap.top, cap.right, cap.bottom].map(Math.round),
      hits,
    };
  });

  if (!capsuleCheck.skipped) {
    for (const h of capsuleCheck.hits) {
      failures.push(
        `首页元素被系统胶囊遮挡：${h.cls}${h.text ? '「' + h.text + '」' : ''} ` +
          `位于 ${JSON.stringify(h.rect)}，胶囊在 ${JSON.stringify(capsuleCheck.capsule)}`
      );
    }
    if (!capsuleCheck.hits.length) {
      console.log(`  ✓ 胶囊让位  胶囊 ${JSON.stringify(capsuleCheck.capsule)} 下方无内容`);
    }
  }

  step('三年级：从首页走完整路径');
  // 不只测深链接，还要测真实点击路径：选册 → 单元 → 课文 → 生字 → 详情。
  // 路由必须落到 packageStrokes3，落到旧分包会因为拿不到笔顺数据而白屏。
  await page.goto(`http://127.0.0.1:${PORT}/#/pages/index/index`, {
    waitUntil: 'domcontentloaded',
    timeout: 30000,
  });
  await page.waitForFunction('window.__ready === true', { timeout: 20000 });
  await new Promise((r) => setTimeout(r, 800));

  const bookCards = await page.evaluate(() => {
    const inst = window.__page.__instance;
    return {
      count: document.querySelectorAll('.book-card').length,
      ids: inst.data.books.map((b) => b.id),
      labels: inst.data.books.map((b) => b.gradeText),
      names: inst.data.books.map((b) => b.name),
    };
  });
  if (bookCards.count !== 8) failures.push(`首页册数应为 8，实际 ${bookCards.count}`);
  for (const b of ['3a', '3b', '4a', '4b']) {
    if (!bookCards.ids.includes(b)) failures.push(`首页缺少册次 ${b}`);
  }
  // 年级标签不能写死成「二年级」
  const wrongGrade = bookCards.names.find((n, i) => n.indexOf(bookCards.labels[i]) !== 0);
  if (wrongGrade) failures.push(`册次年级标签不匹配: ${wrongGrade}`);
  console.log(`  ✓ 首页八册  ${bookCards.names.join(' / ')}`);

  // 真机回归：app.json 的静态 preloadRule 一次预载三个分包共 2483KB，
  // 超「单页面预载 ≤ 2MB」，上传报 80058。改成 routes.preload(book) 按册预载后，
  // 进首页只应预载当前册所属的那一个包。
  const preloadLog = await page.evaluate(() => window.__subpackageLog.slice());
  if (preloadLog.length !== 1) {
    failures.push(`首页应只预载 1 个分包，实际 ${preloadLog.length} 个: ${preloadLog.join(', ')}`);
  }
  if (preloadLog[0] !== 'strokes') {
    failures.push(`默认册（一上）应预载 strokes，实际 ${preloadLog[0]}`);
  }
  console.log(`  ✓ 分包预载  ${preloadLog.join(', ') || '(无)'} 共 ${preloadLog.length} 个（上限 2MB）`);

  await page.evaluate(() => {
    const card = Array.from(document.querySelectorAll('.book-card')).find((e) =>
      e.textContent.includes('三年级上册')
    );
    card.click();
  });
  await new Promise((r) => setTimeout(r, 1200));
  const unitPath = await page.evaluate(() => window.__preview.path());
  if (unitPath.indexOf('unit=') < 0 && unitPath.indexOf('/pages/unit/') < 0) {
    failures.push(`点三年级上册没有进单元页: ${unitPath}`);
  }

  await page.evaluate(() => {
    const row = document.querySelector('[class*=unit]');
    row.click();
  });
  await new Promise((r) => setTimeout(r, 1200));
  await page.evaluate(() => {
    const l = Array.from(document.querySelectorAll('[class*=lesson]')).find(
      (e) => e.className.includes('tap') || e.getAttribute('bindtap')
    );
    l.click();
  });
  await new Promise((r) => setTimeout(r, 1200));
  const lessonInfo = await page.evaluate(() => {
    const inst = window.__page.__instance;
    return {
      path: window.__preview.path(),
      chars: (inst.data.chars || []).map((c) => (typeof c === 'string' ? c : c.ch)).join(''),
    };
  });
  if (!lessonInfo.chars) failures.push('三年级课文没有生字');

  await page.evaluate(() => document.querySelector('[class*=cell]').click());
  await new Promise((r) => setTimeout(r, 2200));
  const detail = await page.evaluate(() => {
    const inst = window.__page.__instance;
    const c = document.querySelector('#hz') || document.querySelector('canvas');
    const ctx = c.getContext('2d');
    const data = ctx.getImageData(0, 0, c.width, c.height).data;
    let ink = 0;
    for (let i = 3; i < data.length; i += 4) if (data[i] > 10) ink++;
    return { path: window.__preview.path(), ch: inst.data.ch, py: inst.data.py, n: inst.data.strokeList.length, ink };
  });
  if (detail.path.indexOf('packageStrokes3') < 0) {
    failures.push(`三年级生字应走 packageStrokes3，实际 ${detail.path}`);
  }
  if (!lessonInfo.chars.includes(detail.ch)) {
    failures.push(`详情页字 ${detail.ch} 不属于该课 ${lessonInfo.chars}`);
  }
  if (!detail.py || !detail.n) failures.push('三年级详情页缺少拼音或笔画');
  if (detail.ink < 500) failures.push(`三年级详情页画布空白 ink=${detail.ink}`);
  console.log(`  ✓ 三年级路径  ${detail.ch} ${detail.py} ${detail.n} 笔 → ${detail.path}`);

  step('三年级：独立分包可加载');
  // 三年级笔顺数据放在 packageStrokes3（主包塞不下），页面薄壳要能正确
  // 注册本分包的加载器，否则详情页会白屏或提示“找不到笔顺”。
  await page.goto(
    `http://127.0.0.1:${PORT}/#/packageStrokes3/pages/detail/detail?ch=%E9%B9%A6&lesson=3a-k15`,
    { waitUntil: 'domcontentloaded', timeout: 30000 }
  );
  await page.waitForFunction('window.__ready === true', { timeout: 20000 });
  await new Promise((r) => setTimeout(r, 2400));
  const g3 = await page.evaluate(() => {
    const inst = window.__page.__instance;
    const c = document.querySelector('#hz') || document.querySelector('canvas');
    const ctx = c.getContext('2d');
    const data = ctx.getImageData(0, 0, c.width, c.height).data;
    let ink = 0;
    for (let i = 3; i < data.length; i += 4) if (data[i] > 10) ink++;
    return { ch: inst.data.ch, py: inst.data.py, strokes: inst.data.strokeList.length, ink };
  });
  if (g3.ch !== '鹦') failures.push(`三年级详情页字不对: ${g3.ch}`);
  if (!g3.py) failures.push('三年级详情页没有拼音');
  if (!g3.strokes || g3.strokes < 5) failures.push(`三年级详情页笔画数异常: ${g3.strokes}`);
  if (g3.ink < 500) failures.push(`三年级详情页画布空白（笔顺数据没加载）ink=${g3.ink}`);
  await page.screenshot({ path: path.join(outDir, '18-detail-grade3.png') });
  console.log(`  ✓ 三年级详情  鹦 ${g3.py} ${g3.strokes} 笔 ink=${g3.ink}`);

  // 描红页同样要能加载三年级数据
  await page.goto(`http://127.0.0.1:${PORT}/#/packageStrokes3/pages/write/write?ch=%E9%B9%A6`, {
    waitUntil: 'domcontentloaded',
    timeout: 30000,
  });
  await page.waitForFunction('window.__ready === true', { timeout: 20000 });
  await new Promise((r) => setTimeout(r, 1200));
  const g3w = await page.evaluate(() => {
    const inst = window.__page.__instance;
    const c = document.querySelector('#hz') || document.querySelector('canvas');
    const ctx = c.getContext('2d');
    const d = ctx.getImageData(0, 0, c.width, c.height).data;
    let ink = 0;
    for (let i = 3; i < d.length; i += 4) if (d[i] > 10) ink++;
    return { ch: inst.data.ch, total: inst.data.steps.length, ink };
  });
  if (g3w.ch !== '鹦') failures.push(`三年级描红页字不对: ${g3w.ch}`);
  if (!g3w.total) failures.push('三年级描红页没有笔画步骤');
  if (g3w.ink < 200) failures.push(`三年级描红页画布空白 ink=${g3w.ink}`);
  console.log(`  ✓ 三年级描红  鹦 ${g3w.total} 笔`);

  step('四年级：独立分包可加载');
  // 四年级笔顺数据放在 packageStrokes4。分包页面只是薄壳，
  // 必须注册本分包的加载器，否则详情页画布空白、提示"找不到笔顺"。
  await page.goto(
    `http://127.0.0.1:${PORT}/#/packageStrokes4/pages/detail/detail?ch=%E7%9B%90&lesson=4a-k1`,
    { waitUntil: 'domcontentloaded', timeout: 30000 }
  );
  await page.waitForFunction('window.__ready === true', { timeout: 20000 });
  await new Promise((r) => setTimeout(r, 2400));
  const g4 = await page.evaluate(() => {
    const inst = window.__page.__instance;
    const c = document.querySelector('#hz') || document.querySelector('canvas');
    const ctx = c.getContext('2d');
    const data = ctx.getImageData(0, 0, c.width, c.height).data;
    let ink = 0;
    for (let i = 3; i < data.length; i += 4) if (data[i] > 10) ink++;
    return {
      ch: inst.data.ch,
      py: inst.data.py,
      strokes: inst.data.strokeList.length,
      lessonTitle: inst.data.lessonTitle,
      ink,
    };
  });
  if (g4.ch !== '盐') failures.push(`四年级详情页字不对: ${g4.ch}`);
  if (!g4.py) failures.push('四年级详情页没有拼音');
  if (g4.strokes !== 10) failures.push(`四年级详情页笔画数应为 10，实际 ${g4.strokes}`);
  if (g4.lessonTitle !== '观潮') failures.push(`四年级课文标题不对: ${g4.lessonTitle}`);
  if (g4.ink < 500) failures.push(`四年级详情页画布空白（笔顺数据没加载）ink=${g4.ink}`);
  console.log(`  ✓ 四年级详情  盐 ${g4.py} ${g4.strokes} 笔 · ${g4.lessonTitle} ink=${g4.ink}`);

  // 四年级描红页
  await page.goto(
    `http://127.0.0.1:${PORT}/#/packageStrokes4/pages/write/write?ch=%E7%9B%90`,
    { waitUntil: 'domcontentloaded', timeout: 30000 }
  );
  await page.waitForFunction('window.__ready === true', { timeout: 20000 });
  await new Promise((r) => setTimeout(r, 1200));
  const g4w = await page.evaluate(() => {
    const inst = window.__page.__instance;
    const c = document.querySelector('#hz') || document.querySelector('canvas');
    const ctx = c.getContext('2d');
    const d = ctx.getImageData(0, 0, c.width, c.height).data;
    let ink = 0;
    for (let i = 3; i < d.length; i += 4) if (d[i] > 10) ink++;
    return { ch: inst.data.ch, total: inst.data.steps.length, ink };
  });
  if (g4w.ch !== '盐') failures.push(`四年级描红页字不对: ${g4w.ch}`);
  if (!g4w.total) failures.push('四年级描红页没有笔画步骤');
  if (g4w.ink < 200) failures.push(`四年级描红页画布空白 ink=${g4w.ink}`);
  console.log(`  ✓ 四年级描红  盐 ${g4w.total} 笔`);


  step('字详情：笔顺序号开关');
  // 曾经的问题：切换笔顺时 canvas 位图被重置为默认 300×150，
  // 而 CSS 尺寸没变，于是整个字被拉伸放大并裁切。
  await page.goto(
    `http://127.0.0.1:${PORT}/#/packageStrokes/pages/detail/detail?ch=%E6%97%A5&lesson=1a-s4`,
    { waitUntil: 'domcontentloaded', timeout: 30000 }
  );
  await page.waitForFunction('window.__ready === true', { timeout: 20000 });
  await new Promise((r) => setTimeout(r, 2200));

  const readCanvas = () =>
    page.evaluate(() => {
      const c = document.querySelector('#hz') || document.querySelector('canvas');
      const rect = c.getBoundingClientRect();
      const ctx = c.getContext('2d');
      const data = ctx.getImageData(0, 0, c.width, c.height).data;
      let ink = 0;
      for (let i = 3; i < data.length; i += 4) if (data[i] > 10) ink++;
      return {
        bufW: c.width,
        bufH: c.height,
        cssW: Math.round(rect.width),
        cssH: Math.round(rect.height),
        ink,
        ratio: ink / (c.width * c.height),
        showNumbers: window.__page.__instance.data.showNumbers,
      };
    });

  const c0 = await readCanvas();
  // 位图尺寸必须等于 CSS 尺寸 × dpr，否则会被拉伸
  if (Math.abs(c0.bufW - c0.cssW * 2) > 2) {
    failures.push(`详情页画布位图宽度 ${c0.bufW} 与 CSS ${c0.cssW}×2 不符（会被拉伸）`);
  }
  if (c0.ink < 500) failures.push('详情页初始画布没有内容');

  await page.evaluate(() => {
    const tools = document.querySelectorAll('.tool');
    tools[0].click(); // 笔顺开关
  });
  await new Promise((r) => setTimeout(r, 700));
  const c1 = await readCanvas();
  if (!c1.showNumbers) failures.push('点“笔顺”后没有打开序号');
  if (c1.bufW !== c0.bufW || c1.bufH !== c0.bufH) {
    failures.push(`点“笔顺”后画布位图被重置 ${c0.bufW}×${c0.bufH} → ${c1.bufW}×${c1.bufH}（字会变大且显示不全）`);
  }
  if (Math.abs(c1.bufW - c1.cssW * 2) > 2) {
    failures.push(`点“笔顺”后位图与 CSS 尺寸不符 ${c1.bufW} vs ${c1.cssW}×2`);
  }
  // 开了序号后墨迹应增加，但整体占比仍应像“一个居中的字”，不是糊满整格
  if (c1.ink <= c0.ink) failures.push(`加序号后墨迹没有增加 ${c0.ink} → ${c1.ink}`);
  if (c1.ratio > 0.45) failures.push(`加序号后墨迹占比过高 ${(c1.ratio * 100).toFixed(0)}%（疑似画面被放大裁切）`);
  await page.screenshot({ path: path.join(outDir, '17-detail-numbers.png') });

  // 模拟“系统把位图重置成 300×150”：页面应能自愈，而不是一直显示拉伸的字
  await page.evaluate(() => {
    const c = document.querySelector('#hz') || document.querySelector('canvas');
    c.width = 300;
    c.height = 150;
  });
  await page.evaluate(() => {
    const tools = document.querySelectorAll('.tool');
    tools[0].click(); // 触发一次重绘
  });
  await new Promise((r) => setTimeout(r, 700));
  const healed = await readCanvas();
  if (healed.showNumbers) failures.push('自愈测试期间开关状态异常');
  if (healed.bufW !== c0.bufW || healed.bufH !== c0.bufH) {
    failures.push(`位图被重置后没有自愈：仍为 ${healed.bufW}×${healed.bufH}，应为 ${c0.bufW}×${c0.bufH}`);
  }
  if (healed.ink < c0.ink * 0.8) {
    failures.push(`自愈后画面不完整：墨迹 ${healed.ink}，初始 ${c0.ink}`);
  }

  // 再点一次，确认开关可逆
  await page.evaluate(() => document.querySelectorAll('.tool')[0].click());
  await new Promise((r) => setTimeout(r, 700));
  const c2 = await readCanvas();
  if (!c2.showNumbers) failures.push('再次点击没有重新打开序号');
  if (c2.bufW !== c0.bufW) failures.push('再次切换后画布位图尺寸又变了');
  console.log(`  ✓ 笔顺序号开关  位图 ${c1.bufW}×${c1.bufH} 稳定，墨迹 ${c0.ink} → ${c1.ink}`);

  step('点某一笔：必须定格在该笔，不能变成整字');
  // 曾经的问题：onStrokeChip 播完单笔后调 renderStatic()，而 renderStatic 用
  // completed: data.n 画整字 —— 用户点第 3 笔，动画放完立刻被整个字盖掉，
  // 等于什么都没看到。现在定格：这一笔及之前用墨色，这一笔用主题色标出，
  // 其余保持浅色提示。
  await page.goto(
    `http://127.0.0.1:${PORT}/#/packageStrokes/pages/detail/detail?ch=%E6%97%A5&lesson=1a-s4`,
    { waitUntil: 'domcontentloaded', timeout: 30000 }
  );
  await page.waitForFunction('window.__ready === true', { timeout: 20000 });
  // 关掉笔顺序号：序号圆点用的正是 rgba(62,142,126)，和本步要数的
  // 主题色高亮同色，会污染像素统计（上一步跑完序号是开着的）。
  await page.evaluate(() => {
    const inst = window.__page.__instance;
    if (inst.data.showNumbers) document.querySelectorAll('.tool')[0].click();
  });
  await new Promise((r) => setTimeout(r, 300));
  // 从整字重播一遍，确保拿到干净的初始状态
  await page.evaluate(() => document.querySelectorAll('.tool')[1].click());
  await new Promise((r) => setTimeout(r, 3200));

  // 按颜色分类像素：墨色 #25332d / 主题色 #3e8e7e / 浅灰提示 #cfc7b6
  const readInk = () =>
    page.evaluate(() => {
      const c = document.querySelector('#hz') || document.querySelector('canvas');
      const ctx = c.getContext('2d');
      const d = ctx.getImageData(0, 0, c.width, c.height).data;
      let dark = 0;
      let accent = 0;
      let ghost = 0;
      for (let i = 0; i < d.length; i += 4) {
        const r = d[i];
        const g = d[i + 1];
        const b = d[i + 2];
        const a = d[i + 3];
        if (a < 10) continue;
        if (Math.abs(r - 62) < 45 && Math.abs(g - 142) < 45 && Math.abs(b - 126) < 45) accent++;
        else if (r < 95 && g < 105 && b < 100) dark++;
        else if (r > 170 && g > 160 && b > 140) ghost++;
      }
      return {
        dark,
        accent,
        ghost,
        frozen: window.__page.__instance.frozenStroke,
        active: window.__page.__instance.data.strokeActive,
        total: window.__page.__instance.data.strokeList.length,
      };
    });

  const full = await readInk();
  if (full.total !== 4) failures.push(`日 应为 4 笔，实际 ${full.total}`);
  if (full.dark < 2000) failures.push('整字动画播完后画布墨迹太少');
  if (full.accent > 200) failures.push(`整字状态不应有主题色高亮（${full.accent} 像素）`);

  const clickChip = async (i) => {
    await page.evaluate((idx) => {
      document.querySelectorAll('.strip .chip')[idx].click();
    }, i);
    await new Promise((r) => setTimeout(r, 1500)); // 620ms 单笔动画 + 定格延时
    return readInk();
  };

  const s1 = await clickChip(1); // 第 2 笔
  if (s1.frozen !== 1) failures.push(`点第 2 笔后 frozenStroke 应为 1，实际 ${s1.frozen}`);
  if (s1.active !== 1) failures.push(`点第 2 笔后数字高亮应为 1，实际 ${s1.active}`);
  if (s1.accent < 200) failures.push(`点第 2 笔后画布没有主题色高亮（${s1.accent} 像素）`);
  // 核心回归：定格后墨迹必须明显少于整字，否则就是又变回整字了
  if (s1.dark + s1.accent >= full.dark * 0.95) {
    failures.push(
      `点第 2 笔后画布与整字几乎一样多（${s1.dark + s1.accent} vs ${full.dark}），没有定格在该笔`
    );
  }
  if (s1.ghost < 200) failures.push('定格后应保留后续笔画的浅色提示');

  const s2 = await clickChip(3); // 最后一笔
  if (s2.frozen !== 3) failures.push(`点第 4 笔后 frozenStroke 应为 3，实际 ${s2.frozen}`);
  if (s2.accent < 200) failures.push(`点第 4 笔后画布没有主题色高亮（${s2.accent} 像素）`);
  // 越往后定格，已经写完的笔画越多，墨色面积应递增
  if (s2.dark <= s1.dark) {
    failures.push(`定格第 4 笔的墨色面积 ${s2.dark} 不大于第 2 笔 ${s1.dark}`);
  }
  // 最后一笔：前三笔墨色 + 这一笔主题色，总量接近整字
  if (s2.dark + s2.accent < full.dark * 0.8) {
    failures.push(`点最后一笔后画布内容偏少（${s2.dark + s2.accent} vs ${full.dark}）`);
  }

  // 再写一遍 = 解除定格，回到整字动画
  await page.evaluate(() => document.querySelectorAll('.tool')[1].click());
  await new Promise((r) => setTimeout(r, 3200));
  const afterReplay = await readInk();
  if (afterReplay.frozen !== -1) {
    failures.push(`点「再写一遍」后应解除定格，frozenStroke 仍为 ${afterReplay.frozen}`);
  }
  if (afterReplay.accent > 200) failures.push('重播整字后不应残留主题色高亮');

  console.log(
    `  ✓ 单笔定格  整字 ${full.dark} 墨 · ` +
      `第2笔 ${s1.dark}+${s1.accent} 高亮 · 第4笔 ${s2.dark}+${s2.accent} 高亮 · ` +
      `重播后 ${afterReplay.dark} 墨`
  );

  step('按笔顺写：笔画多时换行，不能横向滚动');
  // 曾经的实现是 <scroll-view scroll-x>：23 画的字要横滑才能看到后面的笔画，
  // 而孩子不会主动发现"这里能滑"，滑的时候还容易误触数字。
  // 现在改成 flex-wrap，最多 3 行就能全部铺开。
  const stripState = async (ch) => {
    await page.goto(
      `http://127.0.0.1:${PORT}/#/packageStrokes/pages/detail/detail?ch=${encodeURIComponent(ch)}`,
      { waitUntil: 'domcontentloaded', timeout: 30000 }
    );
    await page.waitForFunction('window.__ready === true', { timeout: 20000 });
    await new Promise((r) => setTimeout(r, 700));
    return page.evaluate(() => {
      const strip = document.querySelector('.strip');
      if (!strip) return null;
      const chips = Array.from(strip.querySelectorAll('.chip'));
      const tops = {};
      chips.forEach((c) => {
        const b = c.getBoundingClientRect();
        const k = Math.round(b.top);
        tops[k] = (tops[k] || 0) + 1;
      });
      const sizes = chips.map((c) => {
        const b = c.getBoundingClientRect();
        return `${Math.round(b.width)}x${Math.round(b.height)}`;
      });
      return {
        count: chips.length,
        rows: Object.keys(tops).length,
        perRow: Object.values(tops),
        overflowX: strip.scrollWidth > strip.clientWidth + 1,
        // 被压扁的 chip 会变成宽高不等的椭圆或扁片
        squashed: sizes.filter((s) => {
          const [w, h] = s.split('x').map(Number);
          return Math.abs(w - h) > 2;
        }),
        chipSizes: Array.from(new Set(sizes)),
        // 整个页面也不能出现横向滚动条
        pageOverflowX: document.documentElement.scrollWidth > document.documentElement.clientWidth + 1,
      };
    });
  };

  const few = await stripState('日');
  const many = await stripState('罐'); // 23 画，全字库最多
  for (const [label, st, expectRows] of [
    ['日 4 画', few, 1],
    ['罐 23 画', many, 3],
  ]) {
    if (!st) {
      failures.push(`${label}：找不到按笔顺写的笔画条`);
      continue;
    }
    if (st.overflowX) failures.push(`${label}：笔画条内容横向溢出（scrollWidth > clientWidth）`);
    if (st.pageOverflowX) failures.push(`${label}：页面出现横向滚动`);
    if (st.rows !== expectRows) failures.push(`${label}：应为 ${expectRows} 行，实际 ${st.rows} 行`);
    if (st.squashed.length) failures.push(`${label}：${st.squashed.length} 个笔画数字被压扁（${st.squashed[0]}）`);
  }
  if (few && many) {
    console.log(
      `  ✓ 笔画条换行  日 ${few.rows} 行(${few.perRow.join('+')}) · ` +
        `罐 ${many.rows} 行(${many.perRow.join('+')}) 无横向溢出，数字 ${many.chipSizes.join(',')}`
    );
  }

  step('导航与返回按钮');
  // 外壳返回按钮必须可用：小程序里子页面靠它退回
  await page.goto(`http://127.0.0.1:${PORT}/#/pages/index/index`, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForFunction('window.__ready === true', { timeout: 20000 });
  const navInit = await page.evaluate(() => ({
    backVisible: !document.getElementById('nav-back').hidden,
  }));
  if (navInit.backVisible) failures.push('首页是 tab 页，不应显示返回按钮');

  await page.evaluate(() => document.querySelector('.task-card').click());
  await new Promise((r) => setTimeout(r, 700));
  const navDeep = await page.evaluate(() => ({
    path: window.__preview.path(),
    depth: window.__preview.depth(),
    backVisible: !document.getElementById('nav-back').hidden,
  }));
  if (navDeep.depth < 1) failures.push('点击任务卡没有入栈');
  if (!navDeep.backVisible) failures.push('子页面没有显示返回按钮');

  await page.evaluate(() => document.getElementById('nav-back').click());
  await new Promise((r) => setTimeout(r, 900));
  const navBack = await page.evaluate(() => ({
    path: window.__preview.path(),
    depth: window.__preview.depth(),
    backVisible: !document.getElementById('nav-back').hidden,
  }));
  if (navBack.path !== '/pages/index/index') failures.push('返回按钮没有回到首页: ' + navBack.path);
  if (navBack.depth !== 0) failures.push('返回后导航栈未清空: ' + navBack.depth);
  if (navBack.backVisible) failures.push('回到首页后返回按钮仍然显示');

  // 深链接直接进子页面（栈为空）时，返回应回首页而不是没反应
  await page.goto(`http://127.0.0.1:${PORT}/#/packageStrokes/pages/write/write?ch=%E6%97%A5`, {
    waitUntil: 'domcontentloaded',
    timeout: 30000,
  });
  await page.waitForFunction('window.__ready === true', { timeout: 20000 });
  const deepBack = await page.evaluate(() => !document.getElementById('nav-back').hidden);
  if (!deepBack) failures.push('深链接进入子页面时没有返回按钮');
  await page.evaluate(() => document.getElementById('nav-back').click());
  await new Promise((r) => setTimeout(r, 900));
  const deepHome = await page.evaluate(() => window.__preview.path());
  if (deepHome !== '/pages/index/index') failures.push('深链接空栈返回没有回首页: ' + deepHome);

  // tabBar 切换
  await page.evaluate(() => {
    const t = document.querySelector('.tabbar .tab[data-tab="/pages/practice/practice"]');
    t.click();
  });
  await new Promise((r) => setTimeout(r, 800));
  const tabState = await page.evaluate(() => ({
    path: window.__preview.path(),
    depth: window.__preview.depth(),
    active: (document.querySelector('.tabbar .tab.on') || {}).dataset
      ? document.querySelector('.tabbar .tab.on').dataset.tab
      : null,
  }));
  if (tabState.path !== '/pages/practice/practice') failures.push('tabBar 切换失败: ' + tabState.path);
  if (tabState.depth !== 0) failures.push('切换 tab 后导航栈未清空');
  if (tabState.active !== '/pages/practice/practice') failures.push('tabBar 高亮未更新');
  await page.screenshot({ path: path.join(outDir, '16-tab.png') });
  console.log('  ✓ 导航  返回按钮 / 深链接回首页 / tabBar 切换');

  step('完整练习流程');
  // 完整练习流程：答完所有题 → 结果页 → 错字进入错题本 → 再练一次
  await page.goto(`http://127.0.0.1:${PORT}/#/pages/practice/practice`, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForFunction('window.__ready === true', { timeout: 20000 });
  await page.evaluate(() => window.__preview.navigate('/pages/quiz/quiz'));
  await page.waitForFunction(() => document.querySelectorAll('.option').length === 4, { timeout: 15000 });
  const totalQ = await page.evaluate(() => window.__page.__instance.data.total);
  if (totalQ < 4) failures.push(`练习题数量异常: ${totalQ}`);
  // 第一题故意选错，其余选第一个选项
  for (let i = 0; i < totalQ; i++) {
    if (i > 0) await page.waitForFunction(() => document.querySelectorAll('.option').length === 4, { timeout: 15000 });
    await page.evaluate((idx) => {
      const opts = document.querySelectorAll('.option');
      opts[idx === 0 ? opts.length - 1 : 0].click();
    }, i);
    await new Promise((r) => setTimeout(r, 180));
    const hasNext = await page.evaluate(() => !!document.querySelector('.btn-block'));
    if (!hasNext) failures.push(`第 ${i + 1} 题没有出现继续按钮`);
    await page.evaluate(() => document.querySelector('.btn-block').click());
    await new Promise((r) => setTimeout(r, 400));
  }
  await new Promise((r) => setTimeout(r, 900));
  const result = await page.evaluate(() => {
    const host = document.querySelector('.page-host');
    return {
      path: window.__preview.path(),
      title: document.getElementById('nav-title').textContent,
      text: host.innerText.replace(/\s+/g, ' ').slice(0, 200),
      wrongCount: document.querySelectorAll('.wrong-item').length,
      hasAllRight: !!document.querySelector('.all-right'),
      rate: (host.querySelector('.ring-num') || {}).textContent,
    };
  });
  if (!String(result.path).includes('/pages/result/result')) failures.push('答完题没有进入结果页: ' + result.path);
  if (result.title !== '练习结果') failures.push('结果页标题异常: ' + result.title);
  if (result.rate == null) failures.push('结果页没有显示正确率');
  if (result.wrongCount === 0) failures.push('答错后结果页没有列出错字');
  if (result.hasAllRight) failures.push('有错字时仍显示“全部答对”');
  await page.screenshot({ path: path.join(outDir, '14-result.png') });

  // 错字应进入错题本
  await page.goto(`http://127.0.0.1:${PORT}/#/pages/wrong/wrong`, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForFunction('window.__ready === true', { timeout: 20000 });
  await new Promise((r) => setTimeout(r, 300));
  const wrongPage = await page.evaluate(() => ({
    items: document.querySelectorAll('.wrong-item, .item-main').length,
    text: document.querySelector('.page-host').innerText.replace(/\s+/g, ' ').slice(0, 120),
  }));
  if (wrongPage.items === 0) failures.push('错题本里没有刚答错的字');
  await page.screenshot({ path: path.join(outDir, '15-wrong.png') });
  console.log(`  ✓ 练习流程  ${totalQ} 题，结果页正确率 ${result.rate}%，错题 ${result.wrongCount} 个`);

  step('描红交互');
  // 描红：照着中线写一遍应当全部通过；乱画应当被拒绝
  await page.goto(`http://127.0.0.1:${PORT}/#/packageStrokes/pages/write/write?ch=%E6%97%A5`, {
    waitUntil: 'domcontentloaded',
    timeout: 30000,
  });
  await page.waitForFunction('window.__ready === true', { timeout: 20000 });
  await new Promise((r) => setTimeout(r, 800));

  const trace = await page.evaluate(() => {
    const inst = window.__page.__instance;
    const canvas = document.querySelector('#trace') || document.querySelector('canvas');
    const rect = canvas.getBoundingClientRect();
    const fire = (type, pts) => {
      const touches = pts.map((pt) => ({ x: pt[0], y: pt[1], clientX: rect.left + pt[0], clientY: rect.top + pt[1] }));
      const ev = new Event(type, { bubbles: true, cancelable: true });
      Object.defineProperty(ev, 'touches', { value: touches });
      canvas.dispatchEvent(ev);
    };
    const drawAlong = (pts) => {
      fire('touchstart', [pts[0]]);
      for (let k = 1; k < pts.length; k++) fire('touchmove', [pts[k]]);
      fire('touchend', []);
    };
    // 1) 先乱画一笔，应被拒绝
    const junk = [];
    for (let k = 0; k < 12; k++) junk.push([30 + k * 6, 30 + k * 4]);
    drawAlong(junk);
    const afterJunk = { idx: inst.data.strokeIndex, hint: inst.data.hint, accepted: inst.accepted.length };
    // 2) 再按中线写完整字
    for (let i = 0; i < inst.data2.n; i++) {
      const t = inst.targetStroke(i);
      if (!t) break;
      drawAlong(t);
    }
    return {
      afterJunk,
      done: inst.data.done,
      stars: inst.data.stars,
      score: inst.data.score,
      accepted: inst.accepted.length,
      total: inst.data2.n,
      canvasInk: (() => {
        const ctx = canvas.getContext('2d');
        const d = ctx.getImageData(0, 0, canvas.width, canvas.height).data;
        let ink = 0;
        for (let i = 3; i < d.length; i += 4) if (d[i] > 10) ink++;
        return ink;
      })(),
    };
  });
  if (trace.afterJunk.accepted !== 0) failures.push('乱画的笔画被误判通过');
  if (!trace.afterJunk.hint) failures.push('写错后没有给出提示');
  if (!trace.done) failures.push(`描红没有完成 (${trace.accepted}/${trace.total} 笔)`);
  if (trace.stars < 2) failures.push(`照着中线写只得 ${trace.stars} 星（${trace.score} 分）`);
  if (trace.canvasInk < 1000) failures.push('描红画布内容过少: ' + trace.canvasInk);
  await page.screenshot({ path: path.join(outDir, '13-write-done.png') });
  console.log(`  ✓ 描红交互  笔画 ${trace.accepted}/${trace.total}，${trace.stars} 星 ${trace.score} 分`);

  // 完成后才出现的结果按钮同样要看得见（曾经白字+透明底）
  const writeBtns = await page.evaluate(() =>
    [...document.querySelectorAll('.btn')].map((el) => {
      const cs = getComputedStyle(el);
      const own = (cs.backgroundColor.match(/[\d.]+/g) || []).map(Number);
      const alpha = own.length > 3 ? own[3] : 1;
      return {
        text: (el.textContent || '').trim().slice(0, 8),
        cls: String(el.className),
        hasBg: cs.backgroundImage !== 'none' || alpha > 0.05,
      };
    })
  );
  if (!writeBtns.length) failures.push('描红完成后没有结果按钮');
  for (const b of writeBtns) {
    if (!b.hasBg) failures.push(`描红结果按钮「${b.text}」没有背景（[${b.cls}]）`);
  }
  if (writeBtns.length) console.log(`  ✓ 描红结果按钮  ${writeBtns.map((b) => b.text).join(' / ')}`);

  fs.writeFileSync(path.join(outDir, 'console.log'), logs.join('\n'));
  await browser.close();
  clearTimeout(guard);

  if (failures.length) {
    console.error(`✗ 预览断言失败 ${failures.length} 项`);
    failures.forEach((f) => console.error('  · ' + f));
    process.exitCode = 1;
  } else {
    console.log(`✓ 预览断言通过，截图在 preview/screenshots/`);
  }
}

const server = createServer();
server.listen(PORT, '127.0.0.1', async () => {
  console.log(`预览已启动：http://127.0.0.1:${PORT}/`);
  if (process.argv.includes('--shots')) {
    try {
      await shots();
    } catch (e) {
      console.error('截图失败:', e);
      process.exitCode = 1;
    } finally {
      server.close();
    }
  }
});
