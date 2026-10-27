/**
 * 出题器（纯函数，可用固定 seed 复现）
 * 题型：看拼音选字 / 看字选拼音 / 词语填空 / 数笔画 / 找词语
 */
const catalog = require('./catalog');

function mulberry32(seed) {
  let a = seed >>> 0;
  return function () {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function shuffle(list, rand) {
  const arr = list.slice();
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(rand() * (i + 1));
    const t = arr[i];
    arr[i] = arr[j];
    arr[j] = t;
  }
  return arr;
}

function option(value, label) {
  return { v: value, label: label === undefined ? String(value) : label };
}

function uniqueOptions(opts) {
  const seen = {};
  const out = [];
  for (let i = 0; i < opts.length; i++) {
    const key = typeof opts[i].v + ':' + opts[i].v;
    if (seen[key]) continue;
    seen[key] = true;
    out.push(opts[i]);
  }
  return out;
}

function explainOf(ch, lessonId) {
  const m = catalog.getMeta(ch);
  if (!m) return '';
  const reading = catalog.readingFor(ch, lessonId);
  const word = m.w && m.w[0] ? m.w[0].w : '';
  let text = '「' + ch + '」读 ' + reading + '，部首是「' + m.r + '」，共 ' + m.s + ' 笔。';
  if (word) text += '可以组词「' + word + '」。';
  return text;
}

function distractorChars(ch, count, pool, rand, exclude) {
  const banned = exclude || {};
  const seen = {};
  const candidates = [];
  for (let i = 0; i < pool.length; i++) {
    const c = pool[i];
    if (c === ch || banned[c] || seen[c]) continue;
    seen[c] = true;
    candidates.push(c);
  }
  const picked = shuffle(candidates, rand).slice(0, count);
  if (picked.length >= count) return picked;
  // 极端情况下从全字库补齐
  const all = catalog.getAllChars();
  for (let i = 0; i < all.length && picked.length < count; i++) {
    const c = all[i];
    if (c !== ch && !banned[c] && picked.indexOf(c) < 0) picked.push(c);
  }
  return picked;
}

function pinyin2char(ch, lessonId, pool, rand) {
  const reading = catalog.readingFor(ch, lessonId);
  if (!reading) return null;
  const banned = {};
  for (let i = 0; i < pool.length; i++) {
    const rs = catalog.readingsOf(pool[i]);
    if (rs.indexOf(reading) >= 0) banned[pool[i]] = true;
  }
  const ds = distractorChars(ch, 3, pool, rand, banned);
  if (ds.length < 3) return null;
  const options = uniqueOptions(
    shuffle(
      [option(ch, ch)].concat(ds.map((c) => option(c, c))),
      rand
    )
  );
  if (options.length < 4) return null;
  return {
    type: 'pinyin2char',
    ch,
    lesson: lessonId,
    title: '看拼音，选汉字',
    prompt: reading,
    promptKind: 'pinyin',
    sub: '哪个字的读音是 ' + reading + '？',
    options,
    answer: ch,
    explain: explainOf(ch, lessonId),
  };
}

function char2pinyin(ch, lessonId, pool, rand) {
  const reading = catalog.readingFor(ch, lessonId);
  const m = catalog.getMeta(ch);
  if (!reading || !m) return null;
  const banned = {};
  catalog.readingsOf(ch).forEach((p) => {
    banned[p] = true;
  });
  const ds = distractorChars(ch, 8, pool, rand, {});
  const seen = { [reading]: true };
  const opts = [option(reading, reading)];
  for (let i = 0; i < ds.length && opts.length < 4; i++) {
    const p = catalog.getMeta(ds[i]).py;
    if (p && !seen[p] && !banned[p]) {
      seen[p] = true;
      opts.push(option(p, p));
    }
  }
  if (opts.length < 4) return null;
  return {
    type: 'char2pinyin',
    ch,
    lesson: lessonId,
    title: '这个字读什么？',
    prompt: ch,
    promptKind: 'char',
    sub: '选出正确的读音',
    options: shuffle(opts, rand),
    answer: reading,
    explain: explainOf(ch, lessonId),
  };
}

function fillWord(ch, lessonId, pool, rand) {
  const m = catalog.getMeta(ch);
  if (!m || !m.w || !m.w.length) return null;
  const word = m.w[Math.floor(rand() * m.w.length)];
  if (!word || word.w.indexOf(ch) < 0) return null;
  const masked = word.w.replace(ch, '＿');
  const ds = distractorChars(ch, 3, pool, rand, {});
  if (ds.length < 3) return null;
  const options = uniqueOptions(
    shuffle([option(ch, ch)].concat(ds.map((c) => option(c, c))), rand)
  );
  if (options.length < 4) return null;
  return {
    type: 'fillWord',
    ch,
    lesson: lessonId,
    title: '词语填空',
    prompt: masked,
    promptKind: 'word',
    sub: masked.indexOf('＿') === 0 ? '补上第一个字' : '补上缺少的字',
    options,
    answer: ch,
    explain: '「' + word.w + '」的「' + ch + '」读 ' + catalog.readingFor(ch, lessonId) + '。',
  };
}

function strokeCount(ch, lessonId, pool, rand) {
  const m = catalog.getMeta(ch);
  if (!m) return null;
  const correct = m.s;
  const nums = [correct];
  const offsets = shuffle([1, -1, 2, -2, 3], rand);
  for (let i = 0; i < offsets.length && nums.length < 4; i++) {
    const v = correct + offsets[i];
    if (v > 0 && nums.indexOf(v) < 0) nums.push(v);
  }
  if (nums.length < 4) return null;
  return {
    type: 'strokeCount',
    ch,
    lesson: lessonId,
    title: '数一数笔画',
    prompt: ch,
    promptKind: 'char',
    sub: '一共几笔？',
    options: shuffle(nums.map((v) => option(v, v + ' 笔')), rand),
    answer: correct,
    explain: '「' + ch + '」共 ' + correct + ' 笔，部首是「' + m.r + '」。',
  };
}

function char2word(ch, lessonId, pool, rand) {
  const m = catalog.getMeta(ch);
  if (!m || !m.w || !m.w.length) return null;
  const correct = m.w[Math.floor(rand() * m.w.length)];
  if (!correct) return null;
  const ds = distractorChars(ch, 12, pool, rand, {});
  const seen = { [correct.w]: true };
  const options = [option(correct.w, correct.w)];
  for (let i = 0; i < ds.length && options.length < 4; i++) {
    const words = catalog.getMeta(ds[i]).w || [];
    for (let j = 0; j < words.length; j++) {
      const w = words[j].w;
      if (w.indexOf(ch) >= 0 || seen[w]) continue;
      seen[w] = true;
      options.push(option(w, w));
      break;
    }
  }
  if (options.length < 4) return null;
  return {
    type: 'char2word',
    ch,
    lesson: lessonId,
    title: '词语找朋友',
    prompt: ch,
    promptKind: 'char',
    sub: '哪个词语里有这个字？',
    options: shuffle(options, rand),
    answer: correct.w,
    explain: '「' + correct.w + '」里有「' + ch + '」字，读作 ' + catalog.readingFor(ch, lessonId) + '。',
  };
}

const MAKERS = {
  pinyin2char,
  char2pinyin,
  fillWord,
  strokeCount,
  char2word,
};

const TYPE_ORDER = ['pinyin2char', 'char2pinyin', 'fillWord', 'strokeCount', 'char2word'];

/**
 * @param {object} opts
 * @param {string[]} opts.chars 目标字
 * @param {string} [opts.book] 干扰项来源册次
 * @param {string} [opts.lesson] 课文语境
 * @param {number} [opts.count=10]
 * @param {number} [opts.seed]
 */
function buildQuiz(opts) {
  const targets = (opts.chars || []).filter((ch) => catalog.hasChar(ch));
  if (!targets.length) return { questions: [], targets: [] };
  const count = opts.count || 10;
  const rand = mulberry32((opts.seed == null ? Date.now() : opts.seed) >>> 0);
  const book = opts.book || catalog.getMeta(targets[0]).b;
  let pool = catalog.bookChars(book);
  if (pool.length < 12) pool = catalog.getAllChars();
  const questions = [];
  let guard = 0;
  while (questions.length < count && guard < count * 6) {
    const idx = questions.length;
    const ch = targets[idx % targets.length];
    const lessonId = opts.lesson || catalog.getMeta(ch).l;
    const start = Math.floor(rand() * TYPE_ORDER.length);
    for (let k = 0; k < TYPE_ORDER.length; k++) {
      const type = TYPE_ORDER[(start + k) % TYPE_ORDER.length];
      const q = MAKERS[type](ch, lessonId, pool, rand);
      if (q) {
        q.index = questions.length;
        q.total = count;
        questions.push(q);
        break;
      }
    }
    guard++;
    // 防止死循环：如果一轮里所有题型都做不出来，说明字库异常
    if (guard > 0 && questions.length === 0 && guard >= count * 6) break;
  }
  questions.forEach((q, i) => {
    q.index = i;
    q.total = questions.length;
  });
  return { questions, targets };
}

module.exports = {
  buildQuiz,
  mulberry32,
  shuffle,
  TYPE_ORDER,
};
