/**
 * 部首归类浏览。
 *
 * 部首此前只作为「这个字的部首是什么」这道题的答案存在——孩子答对答错，
 * 但从没机会"按部首看一遍字"。归类的价值在横向对比：认识「氵」之后，
 * 看到江、河、湖、海都带三点水，才明白部首是什么意思。
 *
 * ## 数据
 *
 * 字库里 237 个部首，分布极不均：口 144 字、扌 138、氵 132，
 * 但有 54 个部首只带 1 个字。所以默认**按字数从多到少**排，
 * 冷门部首排在后面，不至于一进来就被一堆只有 1 个字的部首淹没。
 *
 * `inLib` 表示部首字本身在不在字库里（「口」在，能点进详情；
 * 「氵」是个偏旁形态，字库里没有这个字，不能点）。
 */
const catalog = require('../../utils/catalog');
const progress = require('../../utils/progress');
const routes = require('../../utils/routes');

Page({
  data: {
    scope: 'book', // book | all
    bookId: '',
    bookName: '',
    radicals: [],
    sel: '',
    chars: [],
    selCount: 0,
    // 选中的部首在不在字库里（决定能不能点进某个字的详情）
    learnedCount: 0,
    totalCount: 0,
  },

  onLoad() {
    // 设置里这个字段叫 book（不是 bookId），取不到就落到默认册
    const bookId = progress.getSettings().book || catalog.defaultBook();
    this.setData({ bookId, bookName: catalog.getBook(bookId).name });
    this.load('book');
  },

  /** 切换「本册 / 全部」 */
  onScope(e) {
    const scope = e.currentTarget.dataset.scope;
    if (scope === this.data.scope) return;
    this.load(scope);
  },

  load(scope) {
    const list = scope === 'all'
      ? catalog.allRadicals()
      : catalog.bookRadicals(this.data.bookId);

    // 进来先选字数最多的那个部首，省得页面一片空白等着点
    const first = list.length ? list[0].radical : '';
    this.setData({ scope, radicals: list, sel: first }, () => {
      this.pick(first);
    });
  },

  onPick(e) {
    this.pick(e.currentTarget.dataset.r);
  },

  pick(radical) {
    if (!radical) {
      this.setData({ chars: [], sel: '', selCount: 0, learnedCount: 0, totalCount: 0 });
      return;
    }
    const chars = this.data.scope === 'all'
      ? catalog.allCharsWithRadical(radical)
      : catalog.charsWithRadical(this.data.bookId, radical);
    const learned = chars.filter((ch) => progress.hasLearned(ch)).length;
    this.setData({
      sel: radical,
      chars: chars.map((ch) => ({
        ch,
        py: (catalog.getMeta(ch) || {}).py || '',
        learned: progress.hasLearned(ch),
        inLib: catalog.hasChar(ch),
      })),
      selCount: chars.length,
      learnedCount: learned,
      totalCount: chars.length,
    });
  },

  /** 点一个字进详情。字库外的字（理论上不会有）不响应 */
  onChar(e) {
    const ch = e.currentTarget.dataset.ch;
    if (!catalog.hasChar(ch)) return;
    // 详情页按册次分布在不同分包里，必须用 routes 算落点，
    // 写死 packageStrokes 会让三、四年级的字跳到空页面
    wx.navigateTo({ url: routes.detailUrl(ch) });
  },
});
