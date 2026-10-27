/**
 * 笔顺动画播放器
 * 用法：const p = new Player({ ctx, canvas, data, box, ox, oy }); p.play();
 * 支持：整字播放、单笔播放、暂停、重播。
 */
const hc = require('./hanzi-canvas');

const PER_STROKE_MS = 620;
const STROKE_GAP_MS = 140;

function raf(canvas, cb) {
  if (canvas && typeof canvas.requestAnimationFrame === 'function') {
    return canvas.requestAnimationFrame(cb);
  }
  return setTimeout(function () {
    cb(Date.now());
  }, 16);
}

function cancelRaf(canvas, id) {
  if (canvas && typeof canvas.cancelAnimationFrame === 'function') {
    canvas.cancelAnimationFrame(id);
  } else {
    clearTimeout(id);
  }
}

function now() {
  return typeof performance !== 'undefined' && performance.now ? performance.now() : Date.now();
}

function Player(opts) {
  this.ctx = opts.ctx;
  this.canvas = opts.canvas || null;
  this.data = opts.data;
  this.box = opts.box;
  this.ox = opts.ox || 0;
  this.oy = opts.oy || 0;
  this.speed = opts.speed || 1;
  this.ink = opts.ink;
  this.showGhost = opts.showGhost !== false;
  this.onStroke = opts.onStroke || null;
  this.onDone = opts.onDone || null;
  this.onProgress = opts.onProgress || null;
  this.timer = null;
  this.playing = false;
  this.stroke = 0;
  this.partial = 0;
  this.startedAt = 0;
  this.frame = this.frame.bind(this);
}

Player.prototype.base = function () {
  const ctx = this.ctx;
  ctx.clearRect(0, 0, this.box + this.ox * 2, this.box + this.oy * 2);
  hc.drawGrid(ctx, this.box, this.ox, this.oy);
  return ctx;
};

Player.prototype.render = function () {
  const ctx = this.base();
  hc.drawStrokes(ctx, this.data, this.box, this.ox, this.oy, {
    completed: Math.floor(this.stroke),
    partial: this.stroke % 1,
    ink: this.ink,
    showGhost: this.showGhost,
  });
};

Player.prototype.start = function (fromStroke) {
  this.stop();
  this.stroke = fromStroke || 0;
  this.partial = 0;
  this.playing = true;
  this.startedAt = now();
  this.frame();
};

Player.prototype.play = function () {
  if (this.playing) return;
  if (this.stroke >= this.data.n) this.stroke = 0;
  this.playing = true;
  this.startedAt = now() - (this.stroke % 1) * PER_STROKE_MS;
  this.frame();
};

Player.prototype.pause = function () {
  this.playing = false;
  if (this.timer) cancelRaf(this.canvas, this.timer);
  this.timer = null;
};

Player.prototype.stop = function () {
  this.pause();
  this.stroke = 0;
  this.partial = 0;
  this.startedAt = 0;
};

Player.prototype.frame = function () {
  if (!this.playing) return;
  const t = now();
  const elapsed = (t - this.startedAt) * this.speed;
  const unit = PER_STROKE_MS + STROKE_GAP_MS;
  const idx = Math.floor(elapsed / unit);
  const within = elapsed - idx * unit;
  const n = this.data.n;
  if (idx >= n) {
    this.stroke = n;
    this.render();
    this.playing = false;
    if (this.onProgress) this.onProgress(n, n);
    if (this.onDone) this.onDone();
    return;
  }
  const prev = this.stroke;
  this.stroke = idx + Math.min(1, within / PER_STROKE_MS);
  this.partial = this.stroke % 1;
  if (idx !== Math.floor(prev) && this.onStroke) this.onStroke(idx);
  this.render();
  if (this.onProgress) this.onProgress(idx + 1, n);
  const self = this;
  this.timer = raf(this.canvas, function () {
    self.frame();
  });
};

Player.prototype.playStroke = function (i, done) {
  this.stop();
  this.stroke = i;
  this.playing = true;
  this.startedAt = now();
  const self = this;
  const step = function () {
    const el = (now() - self.startedAt) * self.speed;
    self.partial = Math.min(1, el / PER_STROKE_MS);
    self.stroke = i + self.partial;
    self.render();
    if (self.partial < 1 && self.playing) {
      self.timer = raf(self.canvas, step);
    } else {
      self.playing = false;
      if (done) done();
    }
  };
  step();
};

Player.prototype.setData = function (data) {
  this.stop();
  this.data = data;
  this.render();
};

module.exports = { Player, PER_STROKE_MS };
