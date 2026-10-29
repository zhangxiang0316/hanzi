/**
 * 「认识这个字」页面逻辑（工厂）
 *
 * 页面要放在笔顺数据所在的分包里（分包可以 require 主包，反之不行），
 * 而笔顺数据按年级拆成了多个分包。为了让逻辑只有一份，这里导出工厂，
 * 由各分包的页面薄壳调用：
 *
 *   const createDetailPage = require('../../utils/detail-page');
 *   const strokeStore = require('../../utils/stroke-store');
 *   strokeStore.registerAll({ '1a': () => require('../data/strokes-1a.js') });
 *   Page(createDetailPage());
 */
const catalog = require('./catalog');
const routes = require('./routes');
const progress = require('./progress');
const hc = require('./hanzi-canvas');
const strokeStore = require('./stroke-store');
const { Player } = require('./animation');
const { initCanvas, rpx } = require('./canvas-init');

module.exports = function createDetailPage(options) {
  const opts = options || {};
  if (opts.books) strokeStore.registerAll(opts.books);
  return {
    data: {
      ch: '',
      meta: null,
      py: '',
      lessonTitle: '',
      lessonId: '',
      index: 0,
      total: 1,
      strokeList: [],
      readings: [],
      readingsText: '',
      isPoly: false,
      learned: false,
      showNumbers: false,
      showPinyin: true,
      strokeActive: -1,
      hasPrev: false,
      hasNext: false,
      mode: '',
    },

    onLoad(options) {
      this.lessonId = options.lesson || '';
      this.mode = options.mode || '';
      const ch = decodeURIComponent(options.ch || '');
      this.setData({ mode: this.mode });
      this.loadChar(ch);
    },

    onReady() {
      this.setupCanvas().then(() => {
        this.renderStatic();
        this.play();
      });
    },

    onUnload() {
      if (this.freezeTimer) clearTimeout(this.freezeTimer);
      if (this.player) this.player.stop();
    },

    onHide() {
      if (this.player) this.player.pause();
    },

    onShow() {
      // 从后台回来时位图可能被系统丢弃，重新画一遍静态画面
      if (this.ready && this.data.ch) this.renderStatic();
    },

    loadChar(ch) {
      const meta = catalog.getMeta(ch);
      if (!meta) {
        wx.showToast({ title: '暂时没有这个字', icon: 'none' });
        return;
      }
      const lessonId = this.lessonId || meta.l;
      this.lessonId = lessonId;
      const lesson = catalog.getLesson(lessonId);
      const chars = lesson ? lesson.chars : [ch];
      const idx = chars.indexOf(ch);
      const readings = catalog.readingDetails(ch);
      const entry = progress.getEntry(ch);
      const settings = progress.getSettings();

      this.setData({
        ch,
        meta,
        py: catalog.readingFor(ch, lessonId),
        lessonTitle: lesson ? lesson.title : '识字',
        lessonId,
        index: idx < 0 ? 0 : idx,
        total: chars.length,
        strokeList: Array.apply(null, { length: meta.s }).map((_, i) => ({ i })),
        readings,
        readingsText: readings.map((r) => r.p).join(' / '),
        isPoly: readings.length > 1,
        learned: !!(entry && entry.box >= 1),
        showPinyin: settings.showPinyin !== false,
        strokeActive: -1,
        hasPrev: idx > 0,
        hasNext: idx >= 0 && idx < chars.length - 1,
      });
      this.marked = false;
      this.frozenStroke = -1;

      if (this.player && this.ready) {
        const data = hc.get(ch);
        if (data) {
          this.player.setData(data);
          this.play();
        }
      }
    },

    setupCanvas() {
      if (this.ready) return Promise.resolve();
      const size = rpx(600);
      return initCanvas(this, '#hz').then((res) => {
        this.canvas = res.canvas;
        this.ctx = res.ctx;
        this.ensureCanvas = res.ensure;
        this.clearCanvas = res.clear;
        this.width = res.width;
        this.height = res.height;
        const box = Math.min(res.width, res.height);
        this.box = box;
        this.ox = (res.width - box) / 2;
        this.oy = (res.height - box) / 2;
        this.ready = true;
        return res;
      });
    },

    /**
     * 静态重绘。
     *
     * frozenStroke = -1 时画整个字；>= 0 时定格在第 frozenStroke 笔：
     * 之前的笔画用墨色，这一笔用主题色标出，其余保持浅色提示。
     */
    renderStatic() {
      if (!this.ctx) return;
      const data = hc.get(this.data.ch);
      if (!data) return;
      const ctx = this.ctx;
      // 位图若被系统重置（部分安卓机会），这里修好再画，否则画面会被拉伸裁切
      if (this.ensureCanvas && this.ensureCanvas()) {
        // 尺寸变了，坐标系已重建，直接继续整屏重绘即可
      }
      ctx.clearRect(0, 0, this.width, this.height);
      hc.drawGrid(ctx, this.box, this.ox, this.oy);

      const frozen = this.frozenStroke;
      const freezing = frozen >= 0 && frozen < data.n;
      hc.drawStrokes(ctx, data, this.box, this.ox, this.oy, {
        // 定格时"这一笔"已经写完，所以 completed 是 frozen + 1
        completed: freezing ? frozen + 1 : data.n,
        ink: hc.INK,
      });
      if (freezing) {
        hc.drawStrokeHighlight(ctx, data, frozen, this.box, this.ox, this.oy, hc.ACCENT);
      }
      if (this.data.showNumbers) {
        hc.drawStrokeNumbers(ctx, data, this.box, this.ox, this.oy);
      }
    },

    play() {
      const data = hc.get(this.data.ch);
      if (!data || !this.ctx) return;
      if (this.ensureCanvas) this.ensureCanvas();
      this.frozenStroke = -1;
      const self = this;
      if (!this.player) {
        this.player = new Player({
          ctx: this.ctx,
          canvas: this.canvas,
          data,
          box: this.box,
          ox: this.ox,
          oy: this.oy,
          showGhost: true,
          onDone() {
            self.setData({ strokeActive: -1 });
            if (self.mode === 'learn' && !self.marked) {
              self.marked = true;
              progress.learn(self.data.ch);
              self.setData({ learned: true });
            }
          },
        });
      } else {
        this.player.data = data;
      }
      this.player.ox = this.ox;
      this.player.oy = this.oy;
      this.player.box = this.box;
      this.player.play();
    },

    onReplay() {
      if (!this.player) return;
      // 重播整字 = 解除定格
      this.frozenStroke = -1;
      this.player.start(0);
      this.setData({ strokeActive: -1 });
    },

    onCanvasTap() {
      this.onReplay();
    },

    onToggleNumbers() {
      const showNumbers = !this.data.showNumbers;
      this.setData({ showNumbers });
      if (this.player) this.player.pause();
      this.renderStatic();
    },

    onStrokeChip(e) {
      const i = Number(e.currentTarget.dataset.i);
      this.setData({ strokeActive: i });
      // 定格在这一笔：播完之后必须停在这里，不能把整个字铺出来，
      // 否则用户想看第 3 笔，动画一结束就变成整字，等于什么都没看到。
      this.frozenStroke = i;
      if (this.player) {
        this.player.playStroke(i, () => {
          // 用小延时避开最后一次 raf 的重绘竞争；此时 renderStatic
          // 画出的画面与动画末帧完全一致（completed = i + 1），不会闪
          this.freezeTimer = setTimeout(() => this.renderStatic(), 80);
        });
      }
    },

    onWrite() {
      wx.navigateTo({
        url: routes.writeUrl(this.data.ch),
      });
    },

    onQuizOne() {
      const app = getApp();
      app.globalData.session = {
        mode: 'lesson',
        title: '练「' + this.data.ch + '」',
        chars: [this.data.ch],
        lesson: this.lessonId,
        book: catalog.getMeta(this.data.ch).b,
        count: 4,
      };
      wx.navigateTo({ url: '/pages/quiz/quiz?from=detail' });
    },

    onMarkKnown() {
      progress.learn(this.data.ch);
      this.setData({ learned: true });
      wx.showToast({ title: '已加入今天的学习', icon: 'none' });
    },

    onBackLesson() {
      if (this.lessonId) {
        wx.redirectTo({ url: '/pages/lesson/lesson?lesson=' + this.lessonId });
      } else {
        wx.navigateBack();
      }
    },

    go(delta) {
      const lesson = catalog.getLesson(this.lessonId);
      const chars = lesson ? lesson.chars : [];
      const idx = chars.indexOf(this.data.ch);
      const next = chars[idx + delta];
      if (!next) return;
      this.lessonId = this.lessonId;
      this.loadChar(next);
      if (this.ready) {
        const data = hc.get(next);
        if (data) {
          this.player.setData(data);
          this.play();
        }
      }
    },

    onPrev() {
      if (!this.data.hasPrev) return;
      this.go(-1);
    },

    onNext() {
      if (!this.data.hasNext) {
        wx.showToast({ title: '这一课学完啦', icon: 'none' });
        return;
      }
      this.go(1);
    },
  };
};
