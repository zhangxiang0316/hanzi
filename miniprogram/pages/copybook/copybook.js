/**
 * 我的字帖：把写过的字排成一张字帖。
 *
 * 为什么值得单独做一页：现在的徽章体系几乎全是「认识 N 个字」这一个维度，
 * 而描红记录存了 best / stars / tries / last 四个字段却只在单字页显示三颗星。
 * 「我写了一百个字」和「我认识一百个字」对孩子来说是两回事，
 * 后者是看得懂，前者是写得出来——后者更难，也更值得被看见。
 *
 * 与 iOS `CopybookPageView`、Android `CopybookPage` 对应。
 */
const progress = require('../../utils/progress');
const catalog = require('../../utils/catalog');
const routes = require('../../utils/routes');
const strokeStore = require('../../utils/stroke-store');
const copybookPdf = require('../../utils/copybook-pdf');

Page({
  data: {
    all: [],
    shown: [],
    total: 0,
    starsTotal: 0,
    hist: { 0: 0, 1: 0, 2: 0, 3: 0 },
    chips: [],
    filter: -1,   // -1 = 全部
    empty: true,
  },

  onShow() {
    this.refresh();
    // 本次会话里加载过的册，顺手把字帖里的字都存进轮廓缓存。
    // 老用户升级后没有历史缓存，靠这一步逐次补齐。
    strokeStore.rememberAll(this.data.all.map((x) => x.ch));
  },

  refresh() {
    const all = progress.allWriteRecords();
    const hist = progress.writeStarsHistogram();

    // 只显示有内容的档位，避免一排「0」占地方
    const chips = [{ key: -1, title: '全部', count: all.length }];
    [3, 2, 1, 0].forEach((s) => {
      if (hist[s] > 0) {
        chips.push({ key: s, title: s === 0 ? '待练' : s + ' 星', count: hist[s] });
      }
    });

    const filter = this.data.filter;
    const shown = filter === -1 ? all : all.filter((x) => x.record.stars === filter);

    this.setData({
      all,
      shown: shown.map((x) => ({
        ch: x.ch,
        best: x.record.best,
        stars: x.record.stars,
        // WXML 里没法做三元嵌套比较，先把样式类算好
        scoreClass: x.record.best >= 85 ? 'good' : x.record.best >= 65 ? 'mid' : 'low',
        starList: [1, 2, 3].map((i) => i <= x.record.stars),
      })),
      total: progress.writeCount(),
      starsTotal: progress.writeStarsTotal(),
      hist,
      chips,
      empty: all.length === 0,
    });
  },

  onFilter(e) {
    const key = Number(e.currentTarget.dataset.key);
    this.setData({ filter: key }, () => this.refresh());
  },

  /**
   * 导出 PDF 字帖。
   *
   * 屏幕上「我的字帖」只能看；打印出来才是真的字帖，孩子拿铅笔在上面描
   * 比对着屏幕用手指划有用得多。
   *
   * 笔画数据分布在分包里，主包的 copybook 页面本来取不到。但字帖里的每个字
   * 用户都亲手描过——意味着那个字所在的分包页面一定加载过、也一定注册过
   * 自己的笔画加载器。所以这里能拿到的字，刚好就是字帖里的字。
   *
   * 拿不到的字会被 `buildPdf` 跳过并报回来，不会静默少字。
   */
  onExport() {
    const chars = this.data.shown.map((x) => x.ch);
    if (!chars.length) {
      wx.showToast({ title: '没有可以导出的字', icon: 'none' });
      return;
    }
    wx.showLoading({ title: '正在排版', mask: true });

    const strokeFor = (ch) => {
      try {
        return strokeStore.get(ch);
      } catch (e) {
        return null;
      }
    };

    // 先试一次：能取到几个字。取不到说明这些字的册本次会话没加载过、
    // 本地也没缓存（老用户从没写过的字），直接告诉用户去写一遍，
    // 而不是导出一张缺字的字帖让他打印。
    const missing = chars.filter((ch) => !strokeFor(ch));

    let out;
    try {
      out = copybookPdf.buildPdf(chars, strokeFor, {
        dateLabel: copybookPdf.dateLabel(),
      });
    } catch (e) {
      wx.hideLoading();
      wx.showModal({ title: '导出失败', content: '生成字帖时出错了：' + e.message, showCancel: false });
      return;
    }

    if (!out.drawn.length) {
      wx.hideLoading();
      wx.showModal({
        title: '还画不出来',
        content: missing.length === chars.length
          ? '这些字还没有笔顺数据。去描红页把它们再写一遍，就能导出了。'
          : '笔画数据没取到，再试一次看看。',
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
        wx.openDocument({
          filePath: path,
          fileType: 'pdf',
          showMenu: true,
          fail: () => {
            wx.showModal({
              title: '打不开预览',
              content: '文件已经存到本地，但没能打开预览。可以试试从聊天里发送到电脑再打印。',
              showCancel: false,
            });
          },
        });
        if (out.skipped.length) {
          // 不静默少字：导出的字帖会缺这几个，得让用户知道
          wx.showModal({
            title: '有字没画出来',
            content: `「${out.skipped.join('')}」没有笔顺数据，这次没排进字帖。`
              + '去描红页把它们写一遍，下次就有了。',
            showCancel: false,
          });
        }
      },
      fail: (err) => {
        wx.hideLoading();
        wx.showModal({
          title: '保存失败',
          content: (err && err.errMsg) || '写文件失败',
          showCancel: false,
        });
      },
    });
  },

  onChar(e) {
    const ch = e.currentTarget.dataset.ch;
    routes.preload(progress.getSettings().book || catalog.defaultBook());
    wx.navigateTo({ url: routes.writeUrl(ch) });
  },

  onStart() {
    const book = progress.getSettings().book || catalog.defaultBook();
    const first = catalog.bookChars(book)[0];
    if (!first) return;
    routes.preload(book);
    wx.navigateTo({ url: routes.writeUrl(first) });
  },
});
