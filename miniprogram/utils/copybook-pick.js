/**
 * 字帖选字：决定「导出哪些字」的纯逻辑。
 *
 * ## 为什么这件事不能只靠界面
 *
 * 小程序端有一个硬约束：笔画数据在分包里，主包取不到。`strokeStore` 只
 * 认得**本次会话加载过、或者之前缓存过**的字。所以「按课时选 20 个字导出」
 * 这件事在数据上可能只成立一半——没描过的字没有笔顺，画出来是空田字格。
 *
 * 与其让用户导出一张缺字的字帖去打印，不如在选的时候就标出来：
 * 哪些字能导、哪些要先去描一遍。三条路径（课时 / 错题 / 星级）都要过滤，
 * 所以抽成纯函数放这里，三端照抄同一套口径。
 *
 * ## 优先级
 *
 * 一个字的来源可能同时命中多条（既是错题、星级又低），去重时按
 * 「错题 > 星级 > 课时」排——错题最该练。
 */

/**
 * 一组候选字去重并合并来源标签。
 *
 * @param {Array<{ch: string, from: string}>} items
 * @returns {Array<{ch: string, froms: string[]}>} 保持首次出现的顺序
 */
function merge(items) {
  const order = [];
  const map = {};
  (items || []).forEach((it) => {
    if (!it || !it.ch) return;
    if (!map[it.ch]) {
      map[it.ch] = { ch: it.ch, froms: [] };
      order.push(it.ch);
    }
    if (it.from && map[it.ch].froms.indexOf(it.from) < 0) {
      map[it.ch].froms.push(it.from);
    }
  });
  return order.map((ch) => map[ch]);
}

/** 来源的展示顺序与文案 */
const FROM_ORDER = ['wrong', 'weak', 'lesson', 'stars'];
const FROM_TEXT = {
  wrong: '错题',
  weak: '笔画弱',
  lesson: '课时',
  stars: '低分',
};

/**
 * 把来源标签排好序、转成中文，给界面用。
 */
function decorate(items) {
  return (items || []).map((it) => {
    const froms = (it.froms || []).slice().sort(
      (a, b) => FROM_ORDER.indexOf(a) - FROM_ORDER.indexOf(b)
    );
    return {
      ch: it.ch,
      froms,
      fromText: froms.map((f) => FROM_TEXT[f] || f).join(' · '),
    };
  });
}

/**
 * 按课时取字。
 *
 * @param {Array<string>} lessonChars 课时里的字（教材顺序）
 * @param {function(string): boolean} available 这个字有没有笔画数据
 */
function fromLesson(lessonChars, available) {
  return (lessonChars || []).map((ch) => ({
    ch,
    from: 'lesson',
    // 没有笔顺的字标出来，界面上置灰并说明原因
    ready: available ? !!available(ch) : true,
  }));
}

/**
 * 按星档取字。
 *
 * @param {Array<{ch, record}>} records progress.allWriteRecords() 的结果
 * @param {number} stars 要哪一档（0~3）
 */
function fromStars(records, stars) {
  return (records || [])
    .filter((r) => r.record && r.record.stars === stars)
    .map((r) => ({ ch: r.ch, from: 'stars', ready: true }));
}

/**
 * 错题本里的字。
 */
function fromWrong(wrongChars) {
  return (wrongChars || []).map((ch) => ({ ch, from: 'wrong', ready: true }));
}

/**
 * 笔画薄弱点里的字（失败过 2 次以上）。
 */
function fromWeak(weakChars) {
  return (weakChars || []).map((ch) => ({ ch, from: 'weak', ready: true }));
}

/**
 * 一次算好整个选字界面要的数据。
 *
 * @param {object} src {
 *   lessonChars, records, wrongChars, weakChars,
 *   stars,     // 要哪一档星（0~3），null = 不按星级选
 *   available, // (ch) => boolean
 * }
 * @returns {object} { items, readyCount, missing }
 */
function build(src) {
  const s = src || {};
  const raw = [];
  const wrong = fromWrong(s.wrongChars);
  const weak = fromWeak(s.weakChars);
  const lesson = fromLesson(s.lessonChars, s.available);
  const stars = s.stars == null ? [] : fromStars(s.records, s.stars);

  // 错题优先：它最该练
  raw.push(...wrong, ...weak, ...stars, ...lesson);

  const merged = decorate(merge(raw));

  // 能不能导出，以 available 为准——错题里的字也可能从没描过
  const ready = merged.filter((it) => (s.available ? s.available(it.ch) : true));
  const missing = merged.filter((it) => !(s.available ? s.available(it.ch) : true));

  return {
    items: merged,
    ready,
    missing,
    readyCount: ready.length,
    missingCount: missing.length,
    // 一个字都画不出来时界面要给明确指引，而不是让用户点了没反应
    nothingReady: merged.length > 0 && ready.length === 0,
  };
}

module.exports = {
  merge,
  decorate,
  fromLesson,
  fromStars,
  fromWrong,
  fromWeak,
  build,
  FROM_TEXT,
};
