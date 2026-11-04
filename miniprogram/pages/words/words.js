/**
 * 词语表浏览。
 *
 * 1276 条词语此前只在「看拼音选词语」的题目里出现——答对答错，但家长
 * 想帮孩子把这一学期的词过一遍时，没有地方能从头翻。
 *
 * ## 只有 2~4 年级有词语
 *
 * 一年级课本没有词语表（教材本身就没有），所以选了 1a/1b 时页面是空的。
 * 这时候不能显示一片空白让人以为坏了，要明确说「这一册课本没有词语表」。
 *
 * ## 按册次分组而不是一个大长列表
 *
 * 一次列 1266 条，手机要滑很久，而且孩子找不到"我们学到哪了"。
 * 按册分组 + 每册显示进度，家长能直接定位到当前学期。
 */
const catalog = require('../../utils/catalog');
const progress = require('../../utils/progress');
const routes = require('../../utils/routes');

Page({
  data: {
    bookId: '',
    bookName: '',
    hasWords: false,
    groups: [],
    total: 0,
    learnedWords: 0,
    query: '',
    searching: false,
    results: [],
  },

  onLoad() {
    // 设置里这个字段叫 book（不是 bookId），取不到就落到默认册
    const bookId = progress.getSettings().book || catalog.defaultBook();
    this.all = catalog.allWords();
    this.setData({ bookId, bookName: catalog.getBook(bookId).name });
    this.render();
  },

  render() {
    // 按册分组，只保留有词语的册
    const byBook = {};
    this.all.forEach((w) => {
      (byBook[w.book] = byBook[w.book] || []).push(w);
    });
    const groups = catalog.getBooks()
      .filter((b) => byBook[b.id] && byBook[b.id].length)
      .map((b) => {
        const words = byBook[b.id];
        const learned = words.filter((w) => this.wordLearned(w)).length;
        return {
          bookId: b.id,
          name: b.name,
          words: words.map((w) => ({
            word: w.word,
            // 拆成单字数组：WXML 不能对字符串做 Array.from，
            // 而每个字都要能单独点进详情
            chars: w.chars.map((c) => ({ c, learned: progress.hasLearned(c) })),
            lessonNo: w.lessonNo,
            learned: this.wordLearned(w),
          })),
          count: words.length,
          learned,
          current: b.id === this.data.bookId,
        };
      });

    const total = this.all.length;
    const learnedWords = this.all.filter((w) => this.wordLearned(w)).length;
    const hasWords = (groups.find((g) => g.current) || null) != null;

    this.setData({ groups, total, learnedWords, hasWords });
  },

  /**
   * 一个词算不算"学过"。
   *
   * 只有词里**每个字都学过**才算。有一个字不认识，这个词孩子读不出来，
   * 算学过是自欺欺人。
   */
  wordLearned(w) {
    return w.chars.every((c) => progress.hasLearned(c));
  },

  onSearch(e) {
    const q = (e.detail.value || '').trim();
    if (!q) {
      this.setData({ query: '', searching: false, results: [] });
      return;
    }
    // 单字搜「含这个字的词」，多字搜「包含这串字的词」
    const results = this.all
      .filter((w) => w.word.indexOf(q) >= 0)
      .slice(0, 120)
      .map((w) => ({
        word: w.word,
        chars: w.chars.map((c) => ({ c, learned: progress.hasLearned(c) })),
        bookName: catalog.getBook(w.book).name,
        lessonNo: w.lessonNo,
        learned: this.wordLearned(w),
      }));
    this.setData({ query: q, searching: true, results });
  },

  onClear() {
    this.setData({ query: '', searching: false, results: [] });
  },

  /** 点词里的某个字 → 详情 */
  onChar(e) {
    const ch = e.currentTarget.dataset.ch;
    if (!catalog.hasChar(ch)) return;
    wx.navigateTo({ url: routes.detailUrl(ch) });
  },
});
