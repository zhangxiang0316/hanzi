/**
 * 识字量测试。
 *
 * 家长最想知道的一个数字是「我家孩子认识多少字」。原来的 app 只能回答
 * 「学过多少字」——那是**点过多少个字**，不是认识多少。孩子点开一百个字
 * 一个没记住，界面上照样显示 100。
 *
 * ## 为什么用分层抽测，不是全测
 *
 * 2596 个字全问一遍要半小时，一二年级孩子坐不住。所以每册抽 5 个，
 * 按册次从低到高问；某一册正确率低于 40% 就停——再往后的册次问下去
 * 也只是让孩子反复受挫。
 *
 * 抽的时候按**等距取样**（`stride`），不是取前 5 个。取前 5 个等于只考
 * 「日月水火」这种最基础的字，估出来的数会虚高一大截。等距取样才能覆盖
 * 整册，包括靠后的难字。
 *
 * ## 估算方法
 *
 * 每册的得分率 × 该册字数，累加。停下的那一册（正确率 < 40%）之后的
 * 册次一律记 0——那是还没学到的部分，不该按更低的比例折算。
 *
 * 抽 5 个字的比例误差不小，所以结果只报「约」到百位，并且明说是估算。
 * 报一个精确到个位的数字是在骗家长。
 */
const catalog = require('./catalog');
const quiz = require('./quiz');

/** 每册抽几个字。5 × 8 册 = 最多 40 题，中间还会提前停。 */
const PER_BOOK = 5;

/** 低于这个正确率就停在这一册 */
const STOP_RATE = 0.4;

/**
 * 一册里等距抽 n 个字。
 *
 * 起点用 seed 随机，步长固定为 `len / n`——既覆盖全册，不同次测试又不会
 * 永远考同一批字。只取有拼音的字（没拼音的问不出读音题）。
 */
function sampleBook(bookId, n, rand) {
  const pool = catalog.bookChars(bookId).filter((ch) => {
    const m = catalog.getMeta(ch);
    return m && m.py && m.py.length > 1;
  });
  if (!pool.length) return [];
  const count = Math.min(n, pool.length);
  const stride = pool.length / count;
  const start = Math.floor(rand() * stride);
  const out = [];
  const used = {};
  for (let i = 0; i < count; i++) {
    let idx = Math.floor(start + i * stride) % pool.length;
    // 步长取整后可能撞到同一个下标，顺延到下一个没用过的字
    let guard = 0;
    while (used[pool[idx]] && guard < pool.length) {
      idx = (idx + 1) % pool.length;
      guard++;
    }
    used[pool[idx]] = true;
    out.push(pool[idx]);
  }
  return out;
}

/** 这个词的读音干扰项：同一册里别的字的拼音 */
function pinyinOptions(ch, bookId, rand) {
  const reading = catalog.readingFor(ch, '');
  const m = catalog.getMeta(ch);
  if (!reading || !m) return null;
  const banned = {};
  catalog.readingsOf(ch).forEach((p) => { banned[p] = true; });
  const seen = { [reading]: true };
  const opts = [quiz.option(reading, reading)];
  // 干扰项从本册取：同册的字孩子都可能见过，才谈得上「分不清」
  const pool = quiz.shuffle(catalog.bookChars(bookId).filter((c) => c !== ch), rand);
  for (let i = 0; i < pool.length && opts.length < 4; i++) {
    const p = catalog.getMeta(pool[i]).py;
    if (p && !seen[p] && !banned[p]) {
      seen[p] = true;
      opts.push(quiz.option(p, p));
    }
  }
  if (opts.length < 4) return null;
  return quiz.shuffle(opts, rand);
}

/**
 * 生成整套题。
 *
 * 一次全部生成，页面按册边界决定要不要提前停——这样「什么时候停」的
 * 判断逻辑是纯函数，能在 node 里测，不用跑小程序。
 *
 * @returns {{groups: Array, total: number}}
 *   groups[i] = { book, name, bookTotal, start, questions }
 */
function buildTest(opts) {
  const o = opts || {};
  const seed = (o.seed == null ? Date.now() : o.seed) >>> 0;
  const rand = quiz.mulberry32(seed);
  const groups = [];
  let cursor = 0;
  catalog.getBooks().forEach((b) => {
    const picked = sampleBook(b.id, o.perBook || PER_BOOK, rand);
    const questions = [];
    picked.forEach((ch) => {
      const options = pinyinOptions(ch, b.id, rand);
      if (!options) return;
      questions.push({
        type: 'vocab',
        ch,
        book: b.id,
        title: '这个字读什么？',
        prompt: ch,
        promptKind: 'char',
        sub: '会读就选对，不会就随便选',
        options,
        answer: catalog.readingFor(ch, ''),
        explain: '「' + ch + '」读 ' + catalog.readingFor(ch, '') + '。',
      });
    });
    if (!questions.length) return;
    questions.forEach((q, i) => {
      q.index = cursor + i;
      q.groupBook = b.id;
    });
    groups.push({
      book: b.id,
      name: b.name,
      bookTotal: catalog.bookChars(b.id).length,
      start: cursor,
      questions,
    });
    cursor += questions.length;
  });
  groups.forEach((g) => {
    g.questions.forEach((q) => { q.total = cursor; });
  });
  return { groups, total: cursor };
}

/**
 * 根据已答的题算识字量。
 *
 * @param {object} test `buildTest` 的返回
 * @param {object[]} answers 按答题顺序，`{ correct: boolean }`
 * @returns {{size, groups, level, done, stopBook}}
 *   groups[i] = { book, name, asked, correct, rate, counted, contribution }
 */
function estimate(test, answers) {
  const list = answers || [];
  const groups = [];
  let size = 0;
  let stopped = false;
  let stopBook = '';
  let level = '';
  for (let i = 0; i < test.groups.length; i++) {
    const g = test.groups[i];
    // 已经停过就不再「问」后面的册次。哪怕调用方把全部答案都传进来，
    // 那些题在真实流程里也没被问过，算进去会让 answered 虚高。
    const asked = stopped ? 0
      : Math.max(0, Math.min(g.questions.length, list.length - g.start));
    let correct = 0;
    for (let k = 0; k < asked; k++) if (list[g.start + k] && list[g.start + k].correct) correct++;
    const rate = asked ? correct / asked : 0;
    // 一旦停过，后面的册次一律不计——那是还没学到的部分，
    // 按更低的比例折算只会把估算压低成一个没有意义的数
    const counted = asked > 0;
    const contribution = counted ? Math.round(g.bookTotal * rate) : 0;
    if (counted) {
      size += contribution;
      if (rate >= STOP_RATE) level = g.book;
    }
    groups.push({
      book: g.book,
      name: g.name,
      asked,
      correct,
      rate,
      counted,
      contribution,
    });
    // 问满一册且没过线就停
    if (!stopped && asked >= g.questions.length && rate < STOP_RATE) {
      stopped = true;
      stopBook = g.book;
    }
  }
  // 上界是全库去重后的字数：各册字数相加是 2600，但有些字跨册重复出现，
  // 去重后只有 2596。不封顶的话全对会算出 2600，比字库还大。
  const libraryTotal = catalog.getAllChars().length;
  if (size > libraryTotal) size = libraryTotal;
  // 「问过几题」= 各册实际问到的题数之和。
  // 不能用 list.length：提前停下时调用方可能已经生成了全部答案，
  // 那样会报出「问了 40 题」，实际孩子只答了 5 题。
  const answered = groups.reduce((n, g) => n + g.asked, 0);
  return {
    size,
    groups,
    level,
    stopBook,
    answered,
    done: answered >= test.total || stopped,
  };
}

/**
 * 「约 700 字」这种表述比「712 字」诚实：抽 5 个字的误差就在这个量级。
 * 不足 100 的字数直接报整数，因为那时「约 0 字」很奇怪。
 */
function sizeLabel(size) {
  const n = Math.max(0, Math.round(size || 0));
  if (n < 100) return String(n);
  return '约 ' + (Math.round(n / 100) * 100);
}

/**
 * 一句评价。分档按《义务教育语文课程标准》的量级：
 * 一二年级认识 1600 字左右，三四年级 2500 字左右。
 */
function verdict(size) {
  const n = Math.max(0, Math.round(size || 0));
  if (n < 100) return '刚开始认字，慢慢来。';
  if (n < 400) return '一年级上下的水平，继续积累。';
  if (n < 900) return '一年级末到二年级的水平，很不错。';
  if (n < 1600) return '接近二年级末的水平，认字量已经不小了。';
  if (n < 2500) return '到了三四年级的量级，可以多读整本书了。';
  return '认字量很大，可以试着读章节书了。';
}

module.exports = {
  PER_BOOK,
  STOP_RATE,
  buildTest,
  estimate,
  sizeLabel,
  verdict,
  sampleBook,
};
