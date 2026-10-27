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
