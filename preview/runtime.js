/**
 * 浏览器预览运行时（仅开发用，不进入小程序包）
 *
 * 目的：在 Chrome 里真实执行 miniprogram 页面 JS，把 WXML 渲染成 DOM，
 * 让自动化测试能用 DOM/像素断言检查布局与交互，而不是靠肉眼截图。
 *
 * 实现了小程序里用到的最小 API 子集：
 *   Page / getApp / wx.* / WXML 指令（wx:if / wx:for / {{}}）/ canvas 2d 节点
 */
(function () {
  const BASE = '/miniprogram/';
  const pageFiles = new Map(); // '/pages/index/index' -> {js, wxml, wxss}
  const wxmlCache = new Map();
  const modules = new Map();
  const eventLog = [];

  // ---------- 模块加载（CommonJS） ----------
  function resolvePath(from, spec) {
    if (spec.startsWith('/')) return spec.replace(/\.js$/, '');
    const base = from.replace(/\/[^/]*$/, '');
    const parts = (base + '/' + spec).split('/');
    const out = [];
    for (const p of parts) {
      if (p === '..') out.pop();
      else if (p && p !== '.') out.push(p);
    }
    return '/' + out.join('/').replace(/\.js$/, '');
  }

  async function fetchPage(pagePath) {
    if (pageFiles.has(pagePath)) return pageFiles.get(pagePath);
    const files = {};
    for (const ext of ['js', 'wxml', 'wxss', 'json']) {
      try {
        const res = await fetch(BASE + pagePath.slice(1) + '.' + ext);
        files[ext] = res.ok ? await res.text() : '';
      } catch (e) {
        files[ext] = '';
      }
    }
    pageFiles.set(pagePath, files);
    return files;
  }

  function moduleOf(path) {
    if (modules.has(path)) return modules.get(path).exports;
    const entry = { exports: {} };
    modules.set(path, entry);
    const src = srcByPath.get(path);
    if (src == null) throw new Error('模块未预加载: ' + path);
    const fn = new Function('module', 'exports', 'require', src + '\n//# sourceURL=' + path + '.js');
    fn(entry, entry.exports, function (spec) {
      return moduleOf(resolvePath(path, spec));
    });
    return entry.exports;
  }

  const srcByPath = new Map();

  async function preloadModules() {
    const res = await fetch('/preview/module-list.json');
    const list = await res.json();
    await Promise.all(
      list.map(async (rel) => {
        const path = '/' + rel.replace(/^miniprogram\//, '').replace(/\.js$/, '');
        const text = await (await fetch('/' + rel)).text();
        srcByPath.set(path, text);
      })
    );
  }

  // ---------- wx 兼容层 ----------
  const storage = {
    get(k) {
      try {
        return JSON.parse(localStorage.getItem('wx:' + k) || 'null');
      } catch (e) {
        return null;
      }
    },
    set(k, v) {
      localStorage.setItem('wx:' + k, JSON.stringify(v));
    },
    remove(k) {
      localStorage.removeItem('wx:' + k);
    },
    info() {
      return { keys: Object.keys(localStorage).filter((k) => k.startsWith('wx:')) };
    },
  };

  const toasts = [];
  const screen = { width: 390, height: 844 };

  const wx = {
    getStorageSync: (k) => {
      const v = storage.get(k);
      return v == null ? '' : v;
    },
    setStorageSync: (k, v) => storage.set(k, v),
    removeStorageSync: (k) => storage.remove(k),
    getStorageInfoSync: () => storage.info(),
    getWindowInfo: () => ({
      windowWidth: screen.width,
      windowHeight: screen.height,
      statusBarHeight: 44,
      pixelRatio: Math.min(3, window.devicePixelRatio || 2),
      safeArea: { top: 44, bottom: screen.height - 34 },
    }),
    getSystemInfoSync: () => ({
      windowWidth: screen.width,
      windowHeight: screen.height,
      statusBarHeight: 44,
      pixelRatio: Math.min(3, window.devicePixelRatio || 2),
    }),
    createSelectorQuery: () => ({
      in: (page) => ({
        select: (selector) => ({
          fields: (opts) => ({
            exec: (cb) => {
              const el = page.__root.querySelector(selector);
              if (!el) {
                cb([null]);
                return;
              }
              const rect = el.getBoundingClientRect();
              const out = { width: rect.width, height: rect.height, id: el.id };
              if (opts.node) {
                // 直接使用真实 canvas 元素作为 node，保留原生 getContext / requestAnimationFrame
                out.node = el;
              }
              cb([out]);
            },
          }),
        }),
      }),
    }),
    navigateTo: ({ url }) => {
      eventLog.push({ type: 'navigateTo', url });
      runtime.navigate(url);
    },
    redirectTo: ({ url }) => {
      eventLog.push({ type: 'redirectTo', url });
      runtime.navigate(url);
    },
    switchTab: ({ url }) => {
      eventLog.push({ type: 'switchTab', url });
      runtime.navigate(url);
    },
    navigateBack: () => {
      eventLog.push({ type: 'navigateBack' });
      runtime.back();
    },
    showToast: (o) => {
      toasts.push(o.title);
      renderToast(o.title);
    },
    showModal: (o) => {
      // 预览里默认点“确定”
      if (o.success) o.success({ confirm: true, cancel: false });
    },
    setNavigationBarTitle: ({ title }) => {
      runtime.setTitle(title);
    },
    vibrateShort: () => {},
    base64ToArrayBuffer: (b64) => {
      const bin = atob(b64);
      const buf = new ArrayBuffer(bin.length);
      const view = new Uint8Array(buf);
      for (let i = 0; i < bin.length; i++) view[i] = bin.charCodeAt(i);
      return buf;
    },
  };

  window.wx = wx;

  // ---------- WXML 解析 ----------
  // WXML 是良构标记（lint 已校验标签闭合），因此只认显式 `/>` 自闭合，
  // 不能把 canvas/image 当 HTML 空元素，否则 `</canvas>` 会错误闭合父节点。
  const VOID = new Set();

  function parseWxml(src) {
    const clean = src.replace(/<!--[\s\S]*?-->/g, '');
    const root = { tag: 'root', attrs: {}, children: [] };
    const stack = [root];
    const re = /<\/?([a-zA-Z][\w-]*)((?:"[^"]*"|'[^']*'|[^>"'])*?)(\/?)>|([^<]+)/g;
    let m;
    while ((m = re.exec(clean))) {
      if (m[4] != null) {
        const text = m[4];
        if (text.trim()) stack[stack.length - 1].children.push({ tag: '#text', text });
        continue;
      }
      const tag = m[1];
      const closing = m[0].startsWith('</');
      const selfClose = m[3] === '/';
      if (closing) {
        if (stack.length > 1) stack.pop();
        continue;
      }
      const node = { tag, attrs: parseAttrs(m[2] || ''), children: [] };
      stack[stack.length - 1].children.push(node);
      if (!selfClose && !VOID.has(tag)) stack.push(node);
    }
    return root;
  }

  function parseAttrs(str) {
    const attrs = {};
    const re = /([\w:-]+)(?:\s*=\s*("([^"]*)"|'([^']*)'))?/g;
    let m;
    while ((m = re.exec(str))) {
      if (!m[1]) continue;
      attrs[m[1]] = m[3] != null ? m[3] : m[4] != null ? m[4] : '';
    }
    return attrs;
  }

  function evalExpr(expr, data) {
    try {
      // eslint-disable-next-line no-new-func
      return new Function('$d', 'with ($d) { return (' + expr + '); }')(data);
    } catch (e) {
      if (window.__PREVIEW_DEBUG) console.warn('表达式求值失败', expr, e.message);
      return '';
    }
  }

  function interpolate(str, data) {
    if (typeof str !== 'string' || str.indexOf('{{') < 0) return str;
    const single = str.match(/^\{\{([\s\S]+?)\}\}$/);
    if (single) return evalExpr(single[1], data);
    return str.replace(/\{\{([\s\S]+?)\}\}/g, (_, e) => {
      const v = evalExpr(e, data);
      return v == null ? '' : String(v);
    });
  }

  const TAG_MAP = {
    view: 'div',
    text: 'span',
    block: null,
    'scroll-view': 'div',
    canvas: 'canvas',
    button: 'button',
    image: 'img',
    switch: 'div',
    'swiper': 'div',
    'swiper-item': 'div',
    navigator: 'a',
  };

  function renderNodes(children, data, page, out) {
    // wx:if / wx:elif / wx:else 是「兄弟节点链」上的状态，必须按顺序累计
    let chainTaken = null;
    for (const node of children) {
      if (node.tag === '#text') {
        const t = interpolate(node.text, data);
        if (t !== '') out.appendChild(document.createTextNode(String(t)));
        continue;
      }
      const a = node.attrs;
      if ('wx:if' in a) {
        chainTaken = !!evalExpr(stripBraces(a['wx:if']), data);
        if (!chainTaken) continue;
      } else if ('wx:elif' in a) {
        if (chainTaken !== false) continue; // 前面已命中或没有 if，跳过
        chainTaken = !!evalExpr(stripBraces(a['wx:elif']), data);
        if (!chainTaken) continue;
      } else if ('wx:else' in a) {
        if (chainTaken !== false) continue;
        chainTaken = true;
      } else {
        chainTaken = null; // 兄弟链被普通节点打断
      }

      // wx:for
      if ('wx:for' in a) {
        const listRaw = evalExpr(stripBraces(a['wx:for']), data);
        const list = Array.isArray(listRaw) ? listRaw : listRaw && typeof listRaw === 'object' ? Object.values(listRaw) : [];
        const itemName = a['wx:for-item'] || 'item';
        const indexName = a['wx:for-index'] || 'index';
        list.forEach((item, i) => {
          const scope = Object.create(data);
          scope[itemName] = item;
          scope[indexName] = i;
          renderNode(node, scope, page, out);
        });
        continue;
      }
      renderNode(node, data, page, out);
    }
  }

  function stripBraces(v) {
    if (typeof v !== 'string') return 'false';
    const m = v.match(/^\{\{([\s\S]+)\}\}$/);
    return m ? m[1] : JSON.stringify(v);
  }

  function renderNode(node, data, page, out) {
    let tag = TAG_MAP[node.tag];
    const a = node.attrs;
    if (tag === undefined) tag = 'div';
    let el;
    if (tag === null) {
      // block：只渲染子节点
      const frag = document.createDocumentFragment();
      renderNodes(node.children, data, page, frag);
      out.appendChild(frag);
      return;
    }
    if (node.tag === 'canvas') {
      // 复用同一个 canvas 元素：页面 JS 里保存的 node/ctx 在反复 setData 后依然有效
      const pool = page.__canvasPool;
      const i = page.__canvasUsed++;
      if (!pool[i]) {
        const c = document.createElement('canvas');
        c.setAttribute('type', '2d');
        c.width = 300;
        c.height = 150;
        pool[i] = c;
      } else {
        // 复用：清掉上一轮的属性与类名，但保留位图与 ctx 变换
        const reuse = pool[i];
        while (reuse.attributes.length) reuse.removeAttribute(reuse.attributes[0].name);
        reuse.className = '';
        reuse.style.cssText = '';
      }
      el = pool[i];
    } else {
      el = document.createElement(tag);
    }
    for (const [key, raw] of Object.entries(a)) {
      if (key.startsWith('wx:') || key.startsWith('data-') || key === 'id') continue;
      if (key === 'class') {
        const cls = interpolate(raw, data);
        if (cls) el.className = String(cls).replace(/\s+/g, ' ').trim();
      } else if (key === 'style') {
        el.style.cssText = interpolate(raw, data);
      } else if (key === 'type' && node.tag === 'canvas') {
        continue;
      } else if (key.startsWith('bind') || key.startsWith('catch') || key.startsWith('capture')) {
        const parts = key.replace(/^(capture-)?/, '').replace(/^(bind|catch):?/, '').split(':');
        const evt = parts[parts.length - 1];
        const handler = interpolate(raw, data);
        if (handler) {
          const domEvt = evt === 'tap' ? 'click' : evt;
          el.addEventListener(domEvt, (e) => {
            const custom = {
              type: evt,
              currentTarget: { dataset: datasetOf(node, data), id: a.id || '' },
              target: { dataset: datasetOf(node, data) },
              detail: { value: e.target.value },
              touches: e.touches ? Array.from(e.touches) : [],
            };
            if (evt === 'input') custom.detail = { value: e.target.value };
            if (evt === 'change') custom.detail = { value: e.target.checked };
            if (evt === 'touchstart' || evt === 'touchmove') {
              const rect = el.getBoundingClientRect();
              const t = (e.touches && e.touches[0]) || e;
              custom.touches = [{ x: t.clientX - rect.left, y: t.clientY - rect.top, clientX: t.clientX, clientY: t.clientY }];
            }
            const fn = page.__handlers[handler];
            if (typeof fn === 'function') fn.call(page.__instance, custom);
            else console.warn('未找到事件处理函数', handler);
          });
        }
        continue;
      } else if (key === 'checked' || key === 'disabled' || key === 'scroll-x' || key === 'enable-flex') {
        const v = evalExpr(stripBraces(raw), data);
        if (key === 'checked') el.checked = !!v;
        if (key === 'disabled') el.disabled = !!v;
        continue;
      } else if (key === 'src') {
        el.src = interpolate(raw, data);
      } else {
        el.setAttribute(key, interpolate(raw, data));
      }
    }
    if (a.id) el.id = a.id;
    for (const [k, v] of Object.entries(datasetOf(node, data))) {
      el.dataset[k] = typeof v === 'string' ? v : JSON.stringify(v);
    }
    renderNodes(node.children, data, page, el);
    out.appendChild(el);
  }

  function datasetOf(node, data) {
    const out = {};
    for (const [k, v] of Object.entries(node.attrs)) {
      if (!k.startsWith('data-')) continue;
      const name = k.slice(5).replace(/-([a-z])/g, (_, c) => c.toUpperCase());
      out[name] = interpolate(v, data);
    }
    return out;
  }

  // ---------- 页面运行时 ----------
  const runtime = {
    current: null,
    options: {},
    title: '',
    stack: [],
    app: null,

    setTitle(t) {
      this.title = t;
      const bar = document.getElementById('nav-title');
      if (bar) bar.textContent = t;
    },

    navigate(url) {
      const [path, query] = url.split('?');
      const options = {};
      (query || '').split('&').forEach((pair) => {
        if (!pair) return;
        const [k, v] = pair.split('=');
        options[k] = decodeURIComponent(v || '');
      });
      this.stack.push({ path: this.currentPath, options: this.options });
      loadPage(path, options);
    },

    back() {
      const prev = this.stack.pop();
      if (prev && prev.path) loadPage(prev.path, prev.options || {});
    },
  };

  function parseQuery() {
    const hash = location.hash.slice(1);
    const [rawPath, rawQuery] = hash.split('?');
    const path = rawPath || '/pages/index/index';
    const options = {};
    (rawQuery || '').split('&').forEach((pair) => {
      if (!pair) return;
      const [k, v] = pair.split('=');
      options[k] = decodeURIComponent(v || '');
    });
    return { path: decodeURIComponent(path), options };
  }

  function applyWxss(text) {
    // rpx → px：预览窗口宽 390，750rpx = 390px
    const px = (text || '').replace(/(-?[\d.]+)rpx/g, (_, n) => `${(parseFloat(n) * 390) / 750}px`);
    const style = document.createElement('style');
    style.textContent = px;
    document.head.appendChild(style);
  }

  const wxssLoaded = new Set();

  function loadWxss(path) {
    for (const p of [path, '/app']) {
      if (wxssLoaded.has(p)) continue;
      wxssLoaded.add(p);
      const file = p === '/app' ? '/miniprogram/app.wxss' : `/miniprogram${path}.wxss`;
      fetch(file)
        .then((r) => (r.ok ? r.text() : ''))
        .then((t) => applyWxss(t));
    }
  }

  async function loadPage(path, options) {
    const files = await fetchPage(path);
    runtime.currentPath = path;
    runtime.options = options;
    loadWxss(path);

    if (files.json) {
      try {
        const cfg = JSON.parse(files.json);
        if (cfg.navigationBarTitleText) runtime.setTitle(cfg.navigationBarTitleText);
      } catch (e) {
        /* ignore */
      }
    }

    if (!wxmlCache.has(path)) wxmlCache.set(path, parseWxml(files.wxml || ''));
    const ast = wxmlCache.get(path);
    window.__ast = ast;

    const root = document.getElementById('page-root');
    root.innerHTML = '';
    const pageRoot = document.createElement('div');
    pageRoot.className = 'page-host';
    root.appendChild(pageRoot);

    const page = { __root: pageRoot, __handlers: {}, __instance: null, __canvasPool: [], __canvasUsed: 0 };
    runtime.current = page;
    window.__page = page;

    const config = { data: {}, setData(patch, cb) {
      Object.assign(this.data, patch);
      rerender(true);
      if (cb) cb();
    } };
    page.__instance = config;
    config.__root = pageRoot;

    // 捕获 Page({...})
    window.Page = (cfg) => {
      Object.assign(config, cfg);
      page.__handlers = cfg;
      config.data = JSON.parse(JSON.stringify(cfg.data || {}));
    };
    window.getApp = () => runtime.app;

    // 执行页面 JS（若已加载过模块，Page 定义会重复执行，需清理缓存）
    const modulePath = path;
    modules.delete(modulePath);
    srcByPath.set(modulePath, files.js || '');
    moduleOf(modulePath);

    function rerender(keepScroll) {
      const scroller = document.getElementById('page-scroll');
      const top = keepScroll && scroller ? scroller.scrollTop : 0;
      pageRoot.innerHTML = '';
      page.__canvasUsed = 0;
      renderNodes(ast.children, config.data, page, pageRoot);
      if (scroller) scroller.scrollTop = top;
      if (!keepScroll) window.dispatchEvent(new CustomEvent('preview:rerender'));
    }

    rerender();

    if (typeof config.onLoad === 'function') config.onLoad(options || {});
    rerender();
    if (typeof config.onReady === 'function') {
      // 等 DOM 与样式稳定
      setTimeout(() => config.onReady(), 30);
    }
    if (typeof config.onShow === 'function') config.onShow();
    rerender();
    window.__ready = true;
  }

  function renderToast(text) {
    const el = document.createElement('div');
    el.className = 'preview-toast';
    el.textContent = text;
    document.body.appendChild(el);
    setTimeout(() => el.remove(), 1600);
  }

  // ---------- 启动 ----------
  async function boot() {
    screen.width = window.innerWidth;
    screen.height = window.innerHeight;
    await preloadModules();
    runtime.app = { globalData: {}, onLaunch() {} };
    const { path, options } = parseQuery();
    await loadPage(path, options);
    window.__runtime = runtime;
    window.__modules = (p) => moduleOf(p);
  }

  window.addEventListener('hashchange', () => {
    const { path, options } = parseQuery();
    loadPage(path, options);
  });

  window.__preview = {
    navigate: (url) => runtime.navigate(url),
    load: (path, options) => loadPage(path, options),
    path: () => runtime.currentPath,
    options: () => runtime.options,
    events: eventLog,
    toasts,
    storage,
    seed: (fn) => fn(),
  };

  boot().catch((e) => {
    document.body.innerHTML = '<pre class="boot-error">' + (e && e.stack ? e.stack : e) + '</pre>';
    console.error(e);
  });
})();
