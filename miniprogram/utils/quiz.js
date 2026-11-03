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

/**
 * 同音字填空：给一个词，挖掉其中一个字，选项**全部同音**。
 *
 * 与「词语填空」的区别就在选项：那个用的是同册随机字，一眼就能排除；
 * 这里的选项读音完全一样，只能靠「这个字该怎么写」来选。
 * 「dì dì」到底是「弟弟」还是「第第」——这正是听写里最常见的错。
 *
 * 与多音字正好互补：多音字练「一个字有几个音」，同音字练「一个音有几个字」。
 */
function homophone(ch, lessonId, pool, rand) {
  const m = catalog.getMeta(ch);
  if (!m || !m.w || !m.w.length) return null;
  // 干扰项必须真的同音，凑不够 3 个就不出这道题——
  // 混进非同音的字等于把答案送给孩子，练不到东西
  // 传**册次**不是课次：干扰项要优先同册的字，
  // 传 lessonId（如 2a-k1）会让 bookChars 返回空，退化成纯按笔画挑
  const ds = catalog.homophoneDistractors(ch, m.b, 3);
  if (ds.length < 3) return null;

  // 找一个含有本字的组词当题面
  const cands = m.w.filter((w) => w && w.w && w.w.indexOf(ch) >= 0);
  if (!cands.length) return null;
  const word = cands[Math.floor(rand() * cands.length)];
  const masked = word.w.replace(ch, '＿');

  const options = uniqueOptions(
    shuffle([option(ch, ch)].concat(ds.map((c) => option(c, c))), rand)
  );
  if (options.length < 4) return null;
  return {
    type: 'homophone',
    ch,
    lesson: lessonId,
    title: '同音字填空',
    prompt: masked,
    promptKind: 'word',
    sub: '都不是一个音，选对的那个字',
    options,
    answer: ch,
    explain: '「' + word.w + '」写「' + ch + '」；' + ds.join('、') +
      ' 和它同音（' + (m.py || '') + '），但意思不同。',
  };
}

/**
 * 部首：给一个字，选出它的部首。
 *
 * 部首查字法是二年级语文园地的正式内容。与「数笔画」是一对——
 * 查字典要同时知道部首和笔画。
 *
 * 干扰项取本册常见的部首，但排除有字形包含关系的（「木」/「林」），
 * 那种是有争议的，不该拿来考孩子。
 */
function radical(ch, lessonId, pool, rand) {
  const m = catalog.getMeta(ch);
  if (!m || !m.r) return null;
  // 独体字的部首就是它自己（龟→龟、鼓→鼓）：答案直接印在题干上，
  // 孩子只要挑那个看得见的字就行，考不到任何东西
  if (m.r === ch) return null;
  const book = m.b;
  const ds = catalog.radicalDistractors(m.r, book, 3);
  if (ds.length < 3) return null;
  const options = uniqueOptions(
    shuffle([option(m.r, m.r)].concat(ds.map((r) => option(r, r))), rand)
  );
  if (options.length < 4) return null;
  return {
    type: 'radical',
    ch,
    lesson: lessonId,
    title: '部首',
    prompt: ch,
    promptKind: 'char',
    sub: '这个字的部首是哪个？',
    options,
    answer: m.r,
    explain: '「' + ch + '」的部首是「' + m.r + '」，共 ' + m.s + ' 笔。',
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
  polyphone,
  homophone,
  radical,
};

/**
 * 多音字：给一个用例词，问这个字在这里读什么。
 *
 * 单独一个题型、单独一个模式，不混进普通闯关：
 * 多音字只占 2596 个字里的 156 个，混进去出现的概率太低，
 * 孩子每次遇到都像突然换了个游戏。而「读准」本身是个独立的技能，
 * 值得有自己的入口。
 *
 * 选项就是这个字自己的读音（2~3 个），不掺别的字的读音——
 * 掺了会变成「猜哪个不像」，而不是「判断语境」。
 */
function polyphone(ch, lessonId, pool, rand) {
  const cases = catalog.polyphoneCases(ch);
  if (cases.length <= 1) return null;

  // 优先挑「有实际用例词」的读音，这样题目里有语境可依
  const withWord = cases.filter((c) => c.words.length > 0);
  if (!withWord.length) return null;

  // 同一个字、同一个用例词问两遍不算两道题。随机挑，但跳过这一轮里已经用过的词；
  // 全都用过就退回随机（宁可重复也不能出不来题）。
  const fresh = [];
  withWord.forEach((c) => {
    c.words.forEach((w) => {
      if (!USED_PROMPTS['polyphone|' + ch + '|' + w]) fresh.push({ reading: c.reading, word: w });
    });
  });
  let picked;
  let word;
  if (fresh.length) {
    const f = fresh[Math.floor(rand() * fresh.length)] || fresh[0];
    picked = { reading: f.reading };
    word = f.word;
  } else {
    picked = withWord[Math.floor(rand() * withWord.length)] || withWord[0];
    word = picked.words[Math.floor(rand() * picked.words.length)] || picked.words[0];
  }
  USED_PROMPTS['polyphone|' + ch + '|' + word] = true;

  const seen = {};
  const opts = [];
  cases.forEach((c) => {
    if (seen[c.reading.p]) return;
    seen[c.reading.p] = true;
    opts.push(option(c.reading.p, c.reading.p));
  });
  if (opts.length < 2) return null;

  // 解释里把每个读音的用例都列出来，这样答完能顺手记住另一个读音
  const detail = cases
    .map((c) =>
      c.words.length ? c.reading.p + '（' + c.words.slice(0, 2).join('、') + '）' : c.reading.p
    )
    .join('；');

  return {
    type: 'polyphone',
    ch,
    lesson: lessonId,
    title: '多音字读什么',
    prompt: word,
    promptKind: 'word',
    sub: '「' + ch + '」在「' + word + '」里读什么？',
    options: shuffle(opts, rand),
    answer: picked.reading.p,
    explain: '「' + ch + '」是多音字：' + detail + '。',
  };
}

const TYPE_ORDER = ['pinyin2char', 'char2pinyin', 'fillWord', 'strokeCount', 'char2word'];

/** 一轮出题内已用过的「类型|字|题面」，避免同一个字同一个词问两遍。 */
let USED_PROMPTS = {};

/**
 * 「看拼音选词语」：给一个词语的拼音，选出正确的那个词。
 *
 * 直接用课本的词语表（`utils/words.js`），不是每个字自带的组词——
 * 后者是通用例子，前者才是要求掌握的那一份。
 *
 * 与字音题的区别：孩子要读的是**整个词**，而不只是其中一个字。
 * 「天空」和「填空」的字音完全不同，光看字形分不出来，必须真的会读。
 *
 * @param {object} opts
 * @param {string} [opts.lesson] 只出这一课的词
 * @param {string} [opts.book]   只出这一册的词
 * @param {number} [opts.count=10]
 * @param {number} [opts.seed]
 */
function buildWordQuiz(opts) {
  const words = require('./words');
  const src = opts.lesson ? words.lessonWords(opts.lesson) : words.bookWords(opts.book);
  // 至少要有 4 个词才凑得出选项
  if (src.length < 4) return { questions: [], targets: [] };

  const count = Math.min(opts.count || 10, src.length);
  const rand = mulberry32((opts.seed == null ? Date.now() : opts.seed) >>> 0);
  const pool = src.filter((w) => w.py && w.word.length >= 2);
  if (pool.length < 4) return { questions: [], targets: [] };

  const picked = [];
  const usedWord = {};
  let guard = 0;
  while (picked.length < count && guard < count * 8) {
    const cand = pool[Math.floor(rand() * pool.length)];
    guard++;
    if (!cand || usedWord[cand.word]) continue;
    // 题面（拼音）也不能重复：同一轮的题会一块儿显示在结果页
    if (picked.some((p) => p.q.py === cand.py)) continue;
    usedWord[cand.word] = true;
    picked.push({ q: cand });
  }

  const questions = picked.map((x, i) => {
    const correct = x.q;
    // 干扰项：同册其他词，且拼音不能和正确答案一样
    const ds = [];
    let tries = 0;
    while (ds.length < 3 && tries < 60) {
      tries++;
      const cand = pool[Math.floor(rand() * pool.length)];
      if (!cand || cand.word === correct.word) continue;
      if (cand.py === correct.py) continue;
      if (ds.some((d) => d.word === cand.word)) continue;
      ds.push(cand);
    }
    const options = uniqueOptions(
      shuffle([option(correct.word, correct.word)].concat(ds.map((d) => option(d.word, d.word))), rand)
    );
    if (options.length < 4) return null;
    return {
      type: 'wordPinyin',
      ch: correct.word,
      lesson: x.q.lesson || opts.lesson || '',
      title: '看拼音选词语',
      prompt: correct.py,
      promptKind: 'pinyin',
      sub: '这个音是哪个词？',
      options,
      answer: correct.word,
      explain: '「' + correct.word + '」读 ' + correct.py + '。',
      index: i,
      total: picked.length,
    };
  }).filter(Boolean);

  questions.forEach((q, i) => {
    q.index = i;
    q.total = questions.length;
  });
  return { questions, targets: questions.map((q) => q.ch) };
}

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
  USED_PROMPTS = {};
  const count = opts.count || 10;
  const rand = mulberry32((opts.seed == null ? Date.now() : opts.seed) >>> 0);
  // 普通闯关传 undefined，用固定的 TYPE_ORDER——这样已有的 seed 仍然出同一套题。
  // 多音字模式传 ['polyphone']，只出这一种。
  const order = opts.types || TYPE_ORDER;
  const book = opts.book || catalog.getMeta(targets[0]).b;
  let pool = catalog.bookChars(book);
  if (pool.length < 12) pool = catalog.getAllChars();
  const questions = [];
  let guard = 0;
  while (questions.length < count && guard < count * 6) {
    // 用**尝试次数**推进取字，不能用 questions.length。
    // 某个字出不了题时（比如独体字的部首题）questions.length 不增长，
    // 就会一直重试同一个字直到 guard 耗尽——整套题变成 0 道。
    const ch = targets[guard % targets.length];
    const lessonId = opts.lesson || catalog.getMeta(ch).l;
    const start = Math.floor(rand() * order.length);
    for (let k = 0; k < order.length; k++) {
      const type = order[(start + k) % order.length];
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
  buildWordQuiz,
  mulberry32,
  shuffle,
  TYPE_ORDER,
};
