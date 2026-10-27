const catalog = require('../../../utils/catalog');
const progress = require('../../../utils/progress');
const hc = require('../../utils/hanzi-canvas');
const { Player } = require('../../utils/animation');
const { initCanvas, rpx } = require('../../../utils/canvas-init');

Page({
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
    if (this.player) this.player.stop();
  },

  onHide() {
    if (this.player) this.player.pause();
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
      const box = Math.min(res.width, res.height);
      this.box = box;
      this.ox = (res.width - box) / 2;
      this.oy = (res.height - box) / 2;
      this.ready = true;
      return res;
    });
  },

  renderStatic() {
    if (!this.ctx) return;
    const data = hc.get(this.data.ch);
    if (!data) return;
    const ctx = this.ctx;
    ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
    hc.drawGrid(ctx, this.box, this.ox, this.oy);
    hc.drawStrokes(ctx, data, this.box, this.ox, this.oy, {
      completed: data.n,
      ink: hc.INK,
    });
    if (this.data.showNumbers) {
      hc.drawStrokeNumbers(ctx, data, this.box, this.ox, this.oy);
    }
  },

  play() {
    const data = hc.get(this.data.ch);
    if (!data || !this.ctx) return;
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
    if (this.player) this.player.playStroke(i, () => {
      // 播放完单笔后保留整字，避免画面闪回
      setTimeout(() => this.renderStatic(), 260);
    });
  },

  onWrite() {
    wx.navigateTo({
      url: '/packageStrokes/pages/write/write?ch=' + encodeURIComponent(this.data.ch),
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
});
