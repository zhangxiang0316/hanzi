/**
 * 选字做字帖。
 *
 * 「我的字帖」只能导**写过的字**。但家长真实的用法是：
 * 「把这课的生字打一张」「把错题打一张」「把三颗星以下的打一张」——
 * 这些都不是"我写过的"，而是"我需要练的"。
 *
 * ## 一个绕不过去的限制
 *
 * 小程序的笔画数据在分包里，主包取不到，`strokeStore` 只认得本次会话
 * 加载过或之前缓存过的字。所以选中一个没描过的字，画出来会是空田字格。
 * 这里的处理是**先标出来**：能导的正常显示，不能导的置灰并说明
 * 「要先描一遍」，而不是导出一张缺字的纸。
 */
const progress = require('../../utils/progress');
const catalog = require('../../utils/catalog');
const strokeStore = require('../../utils/stroke-store');
const copybookPdf = require('../../utils/copybook-pdf');
const pick = require('../../utils/copybook-pick');
const routes = require('../../utils/routes');

Page({
  data: {
    bookId: '',
    bookName: '',
    // 来源勾选
    srcWeak: false,
    srcWrong: true,
    srcLesson: true,
    srcStars: false,
    starLevel: 2,
    // 结果
    items: [],
    readyCount: 0,
    missingCount: 0,
    selectedCount: 0,
    nothingReady: false,
  },

  onLoad() {
    // 设置里这个字段叫 book（不是 bookId），取不到就落到默认册
    const bookId = progress.getSettings().book || catalog.defaultBook();
    this.setData({ bookId, bookName: catalog.getBook(bookId).name });
    // 默认选本册第一课：家长最常打的就是"这课的生字"
    const first = catalog.bookChars(bookId)[0] || '';
    this.lessonId = (first && catalog.lessonOfChar(first)) || '';
    this.selected = null; // null = 全选
    this.refresh();
  },

  /** 勾选某个来源 */
  onToggle(e) {
    const key = e.currentTarget.dataset.key;
    const field = 'src' + key.charAt(0).toUpperCase() + key.slice(1);
    this.setData({ [field]: !this.data[field] }, () => this.refresh());
  },

  onStar(e) {
    this.setData({ starLevel: Number(e.currentTarget.dataset.n) }, () => this.refresh());
  },

  /** 换一课 */
  onPickLesson(e) {
    this.lessonId = e.currentTarget.dataset.id;
    this.selected = null;
    this.refresh();
  },

  /** 点一个字的开关 */
  onTapChar(e) {
    const ch = e.currentTarget.dataset.ch;
    const ready = this.data.items.filter((x) => x.ready).map((x) => x.ch);

    // 没有笔顺数据的字点了不能只是"没反应"。直接送去描一遍——
    // 描完回来它就进缓存了，这条路才算走通，而不是一堵墙。
    if (ready.indexOf(ch) < 0) {
      wx.navigateTo({ url: routes.writeUrl(ch) });
      return;
    }

    if (this.selected == null) {
      // 从「全选」切到「显式选择」：先全选，再去掉这个
      this.selected = ready.filter((c) => c !== ch);
    } else if (this.selected.indexOf(ch) >= 0) {
      this.selected = this.selected.filter((c) => c !== ch);
    } else {
      this.selected = this.selected.concat([ch]);
    }
    this.refresh();
  },

  onSelectAll() {
    this.selected = null;
    this.refresh();
  },

  onSelectNone() {
    this.selected = [];
    this.refresh();
  },

  refresh() {
    // 候选字来自四条路径，按优先级合并去重
    const lessonChars = this.data.srcLesson && this.lessonId
      ? catalog.lessonChars(this.lessonId)
      : [];
    const wrongChars = this.data.srcWrong ? progress.getWrong().map((w) => w.ch) : [];
    const weakChars = this.data.srcWeak ? progress.weakChars() : [];
    const records = progress.allWriteRecords();

    const out = pick.build({
      lessonChars,
      wrongChars,
      weakChars,
      records,
      stars: this.data.srcStars ? this.data.starLevel : null,
      available: (ch) => strokeStore.isCached(ch),
    });

    // 选中集合按可用性过滤：不可用的字本来也画不出来
    const sel = this.selected == null
      ? out.ready.map((x) => x.ch)
      : this.selected.filter((c) => out.ready.some((x) => x.ch === c));

    const items = out.items.map((it) => ({
      ch: it.ch,
      fromText: it.fromText,
      ready: out.ready.some((x) => x.ch === it.ch),
      on: sel.indexOf(it.ch) >= 0,
    }));

    this.setData({
      items,
      readyCount: out.readyCount,
      missingCount: out.missingCount,
      selectedCount: sel.length,
      nothingReady: out.nothingReady,
    });
  },

  /** 导出选中（或全部可用）的字 */
  onExport() {
    const chosen = this.data.items.filter((x) => x.on).map((x) => x.ch);
    if (!chosen.length) {
      wx.showToast({ title: '先选几个字', icon: 'none' });
      return;
    }
    wx.showLoading({ title: '正在排版', mask: true });

    const strokeFor = (ch) => {
      try { return strokeStore.get(ch); } catch (e) { return null; }
    };

    let out;
    try {
      out = copybookPdf.buildPdf(chosen, strokeFor, {
        dateLabel: copybookPdf.dateLabel(),
      });
    } catch (e) {
      wx.hideLoading();
      wx.showModal({ title: '导出失败', content: e.message, showCancel: false });
      return;
    }

    if (!out.drawn.length) {
      wx.hideLoading();
      wx.showModal({
        title: '还画不出来',
        content: '这些字还没有笔顺数据。先去描红页写一遍，回来就能导出了。',
        showCancel: false,
      });
      return;
    }

    const path = `${wx.env.USER_DATA_PATH}/${copybookPdf.fileName('字帖')}`;
    wx.getFileSystemManager().writeFile({
      filePath: path,
      data: out.bytes.buffer,
      encoding: 'binary',
      success: () => {
        wx.hideLoading();
        wx.openDocument({ filePath: path, fileType: 'pdf', showMenu: true });
      },
      fail: (err) => {
        wx.hideLoading();
        wx.showModal({ title: '保存失败', content: err.errMsg || '写文件失败', showCancel: false });
      },
    });
  },
});
