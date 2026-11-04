/**
 * 词语表浏览。
 *
 * 词语此前只在「看拼音选词语」的题目里出现——答对答错，但家长想帮孩子
 * 把这一学期的词过一遍时，没有地方能从头翻。
 *
 * ## 复用 `utils/words.js`，不另写一套
 *
 * 那个模块已经处理了一件容易漏的事：**一年级课本没有词语表**，它用每课
 * 生字的第一组词补上（`from: 'derived'`）。自己另写一份遍历必然把这个
 * 兜底漏掉，结果就是一年级点进词语表看到一片空白——而一年级正是这个
 * App 最大的用户群。
 *
 * 所以这里直接用 `words.bookWords()` / `words.allWords()`，页面只负责
 * 分组和排版。派生词要标出来，不能让家长以为那是课本上的词。
 *
 * ## 为什么按册分组
 *
 * 一次列一千多条，手机要滑很久，而且孩子找不到"我们学到哪了"。
 * 按册分组 + 每册显示进度，家长能直接定位到当前学期。
 */
const words = require('../../utils/words');
const catalog = require('../../utils/catalog');
const progress = require('../../utils/progress');
const routes = require('../../utils/routes');

Page({
  data: {
    bookId: '',
    bookName: '',
    groups: [],
    total: 0,
    uniqueTotal: 0,
    learnedWords: 0,
    query: '',
    searching: false,
    results: [],
    resultTotal: 0,
  },

  onLoad() {
    // 设置里这个字段叫 book（不是 bookId），取不到就落到默认册
    const bookId = progress.getSettings().book || catalog.defaultBook();
    this.setData({ bookId, bookName: catalog.getBook(bookId).name });
    this.render();
  },

  render() {
    const groups = catalog.getBooks()
      .map((b) => {
        const list = words.bookWords(b.id);
        if (!list.length) return null;
        const learned = list.filter((w) => this.wordLearned(w.word)).length;
        // 一册里可能**混合**：有的课文有词语表，有的没有（2a 就是这种）。
        // 所以不能只看 every，要数出有几个是派生词。
        const derivedCount = list.filter((w) => w.from === 'derived').length;
        return {
          bookId: b.id,
          name: b.name,
          count: list.length,
          learned,
          derivedCount,
          // 全册都是派生词（一年级）和只补了几课（2a 那种），说法的轻重不一样
          allDerived: derivedCount === list.length,
          current: b.id === this.data.bookId,
          words: list.map((w) => ({
            word: w.word,
            // 拆成单字数组：WXML 不能对字符串做 Array.from，
            // 而每个字都要能单独点进详情
            chars: this.splitChars(w.word),
            lessonNo: this.lessonNo(w.lesson),
            learned: this.wordLearned(w.word),
            derived: w.from === 'derived',
          })),
        };
      })
      .filter(Boolean);

    const all = words.uniqueWords();
    this.setData({
      groups,
      total: words.allWords().length,
      uniqueTotal: all.length,
      learnedWords: all.filter((w) => this.wordLearned(w.word)).length,
    });
  },

  /**
   * 拆成单字。
   *
   * `tap` 是"这个字能不能点进详情"。派生词里有少数用到了字库外的字
   * （比如「弓弩」的「弩」不在 2596 字里），那些字点了没反应——
   * 所以要置灰，而不是让用户点了以为卡住了。
   */
  splitChars(word) {
    return Array.from(word).map((c) => ({
      c,
      learned: progress.hasLearned(c),
      tap: catalog.hasChar(c),
    }));
  },

  lessonNo(lessonId) {
    const l = catalog.getLesson(lessonId);
    return l ? l.no : 0;
  },

  onSearch(e) {
    const q = (e.detail.value || '').trim();
    if (!q) {
      this.setData({ query: '', searching: false, results: [], resultTotal: 0 });
      return;
    }
    const found = words.wordsWithChar(q);
    // 结果可能很长（搜「一」会命中几百条），先显示前 120 条并报出总数
    const results = found.slice(0, 120).map((w) => ({
      word: w.word,
      chars: this.splitChars(w.word),
      bookNames: this.bookNames(w.books),
      learned: this.wordLearned(w.word),
    }));
    this.setData({ query: q, searching: true, results, resultTotal: found.length });
  },

  bookNames(books) {
    return (books || []).map((id) => {
      const b = catalog.getBook(id);
      return b ? b.name : id;
    }).join(' / ');
  },

  onClear() {
    this.setData({ query: '', searching: false, results: [], resultTotal: 0 });
  },

  /**
   * 一个词算不算"学过"。
   *
   * 只有词里**每个字都学过**才算。有一个字不认识，这个词孩子读不出来，
   * 算学过是自欺欺人。
   */
  wordLearned(word) {
    return Array.from(word).every((c) => progress.hasLearned(c));
  },

  /** 点词里的某个字 → 详情 */
  onChar(e) {
    const ch = e.currentTarget.dataset.ch;
    if (!catalog.hasChar(ch)) return;
    wx.navigateTo({ url: routes.detailUrl(ch) });
  },
});
