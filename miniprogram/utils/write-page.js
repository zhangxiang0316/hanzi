/**
 * 「描红」页面逻辑（工厂），由各年级分包里的薄壳页面调用。
 * 见 utils/detail-page.js 的说明。
 */
const catalog = require('./catalog');
const progress = require('./progress');
const hc = require('./hanzi-canvas');
const strokeStore = require('./stroke-store');
const { initCanvas, rpx } = require('./canvas-init');
const trace = require('./trace');
const { scoreStroke, scoreChar } = trace;
const { Player: PlayerCtor } = require('./animation');

const ACCEPT = 42; // 单笔通过分

module.exports = function createWritePage(options) {
  const opts = options || {};
  /**
   * 听写模式：不画底字。
   *
   * 描红是「照着写」，听写是「凭记忆写」——同一套判分，难度差一档。
   * 仍然保留田字格和起笔提示，否则孩子连从哪儿下笔都不知道，
   * 那不是听写，那是默写整字。
   */
  const hideGhostDefault = !!opts.hideGhost;
  if (opts.books) strokeStore.registerAll(opts.books);
  return {
    data: {
      ch: '',
      py: '',
      meta: null,
      strokeIndex: 0,
      steps: [],
      hint: '沿着淡色的字，一笔一笔写出来',
      liveScore: 0,
      done: false,
      stars: 0,
      score: 0,
      resultTip: '',
      // 教材只要求认识、不要求会写的字（341 个，如髓/嚼/蟹）
      canWrite: true,
    },

    onLoad(options) {
      // 听写页会传 hideGhost=1（难度不是 easy 时）
      this.hideGhost = options && options.hideGhost === '1' ? true : hideGhostDefault;
      this.loadChar(decodeURIComponent(options.ch || ''));
      if (this.ch) wx.setNavigationBarTitle({ title: '描红 · ' + this.ch });
    },

    /**
     * 载入（或换成）某个字。
     *
     * 抽出来是因为听写页要在一个页面里连续换字：判分、画布、手势全都能复用，
     * 只有「当前是哪个字」要重置。不抽的话听写页只能复制一遍整个初始化逻辑。
     */
    loadChar(ch) {
      this.ch = ch || '';
      const meta = catalog.getMeta(this.ch);
      if (!meta) {
        wx.showToast({ title: '找不到这个字', icon: 'none' });
        return;
      }
      const data = hc.get(this.ch);
      this.data2 = data;
      this.accepted = [];
      this.ink = [];       // 当前笔画轨迹
      this.drawing = false;
      this.setData({
        ch: this.ch,
        py: catalog.readingFor(this.ch, meta.l),
        meta,
        steps: Array.apply(null, { length: meta.s }).map((_, i) => i),
        strokeIndex: 0,
        done: false,
        score: 0,
        stars: 0,
        liveScore: 0,
        resultTip: '',
        hint: '沿着淡色的字，一笔一笔写出来',
        canWrite: catalog.isWriteChar(this.ch),
      });
      if (this.ctx) this.render();
    },

    onShow() {
      if (this.ctx && this.data2) this.render();
    },

    onReady() {
      const size = rpx(660);
      initCanvas(this, '#trace').then((res) => {
        this.canvas = res.canvas;
        this.ctx = res.ctx;
        this.ensureCanvas = res.ensure;
        this.width = res.width;
        this.height = res.height;
        this.box = Math.min(res.width, res.height);
        this.ox = (res.width - this.box) / 2;
        this.oy = (res.height - this.box) / 2;
        this.tolerance = this.box * 0.075;
        this.render();
      });
    },

    targetStroke(i) {
      const d = this.data2;
      if (!d || i >= d.n) return null;
      return hc.medianPoints(d.medians[i], this.box, this.ox, this.oy);
    },

    /** 重绘：格子 + 淡字 + 已完成笔画 + 当前笔的起笔点 + 用户正在画的线 */
    render(live) {
      const ctx = this.ctx;
      if (!ctx) return;
      // 位图被系统重置时先修好，避免画面被拉伸（字看起来会变大且写不全）
      if (this.ensureCanvas) this.ensureCanvas();
      const d = this.data2;
      const box = this.box;
      ctx.clearRect(0, 0, this.width, this.height);
      hc.drawGrid(ctx, box, this.ox, this.oy, { border: 2, lineColor: '#eee3d0' });

      // 整个字的淡色底。听写模式下不画——那是「凭记忆写」，看了底字就没意义了。
      if (!this.hideGhost) {
        hc.drawStrokes(ctx, d, box, this.ox, this.oy, {
          completed: 0,
          showGhost: true,
          ghostFill: 'rgba(37,51,45,0.10)',
        });
      }

      // 当前这一笔的引导线
      const idx = this.data.strokeIndex;
      const target = this.targetStroke(idx);
      if (target && idx < d.n) {
        ctx.save();
        ctx.strokeStyle = 'rgba(62,142,126,0.42)';
        ctx.lineWidth = Math.max(box * 0.09, 10);
        ctx.lineCap = 'round';
        ctx.lineJoin = 'round';
        ctx.beginPath();
        ctx.moveTo(target[0][0], target[0][1]);
        for (let k = 1; k < target.length; k++) ctx.lineTo(target[k][0], target[k][1]);
        ctx.stroke();
        ctx.restore();

        // 起笔点
        const s = target[0];
        ctx.save();
        ctx.beginPath();
        ctx.arc(s[0], s[1], Math.max(box * 0.028, 5), 0, Math.PI * 2);
        ctx.fillStyle = '#df6248';
        ctx.fill();
        ctx.beginPath();
        ctx.arc(s[0], s[1], Math.max(box * 0.05, 8), 0, Math.PI * 2);
        ctx.strokeStyle = 'rgba(223,98,72,0.35)';
        ctx.lineWidth = 2;
        ctx.stroke();
        ctx.restore();
      }

      // 已完成的笔画：高分吸附到标准笔形，低分保留手写痕迹
      for (let i = 0; i < this.accepted.length; i++) {
        const a = this.accepted[i];
        if (a.snap) {
          hc.drawStrokeHighlight(ctx, d, i, box, this.ox, this.oy, hc.INK);
        } else {
          this.drawPolyline(a.points, 'rgba(37,51,45,0.72)', Math.max(box * 0.05, 6));
        }
      }

      if (live && this.ink.length > 1) {
        this.drawPolyline(this.ink, 'rgba(62,142,126,0.55)', Math.max(box * 0.055, 7));
      }
    },

    drawPolyline(pts, color, width) {
      const ctx = this.ctx;
      if (!pts || pts.length < 2) return;
      ctx.save();
      ctx.strokeStyle = color;
      ctx.lineWidth = width;
      ctx.lineCap = 'round';
      ctx.lineJoin = 'round';
      ctx.beginPath();
      ctx.moveTo(pts[0][0], pts[0][1]);
      for (let i = 1; i < pts.length; i++) ctx.lineTo(pts[i][0], pts[i][1]);
      ctx.stroke();
      ctx.restore();
    },

    pushPoint(e) {
      const t = e.touches && e.touches[0];
      if (!t) return;
      const x = t.x == null ? t.clientX : t.x;
      const y = t.y == null ? t.clientY : t.y;
      const last = this.ink[this.ink.length - 1];
      if (last) {
        const dx = x - last[0];
        const dy = y - last[1];
        if (dx * dx + dy * dy < 4) return;
      }
      this.ink.push([x, y]);
    },

    onTouchStart(e) {
      if (this.data.done) return;
      this.drawing = true;
      this.ink = [];
      this.pushPoint(e);
      this.render(true);
    },

    onTouchMove(e) {
      if (!this.drawing || this.data.done) return;
      this.pushPoint(e);
      this.render(true);
    },

    onTouchEnd() {
      if (!this.drawing || this.data.done) return;
      this.drawing = false;
      const pts = this.ink;
      this.ink = [];
      const idx = this.data.strokeIndex;
      const target = this.targetStroke(idx);
      if (!target) {
        this.render();
        return;
      }
      const res = scoreStroke(pts, target, { tolerance: this.tolerance });
      const len = trace.polylineLength(pts);
      // 「算一笔」的最短长度：不能只用画布比例。
      //
      // 点画的最后一笔本来就很短（「每」末笔约 31px、「毒」28px，画布 400 时），
      // 如果门槛一刀切在 box*0.06，孩子把点写小一点就永远过不去，而且
      // 早先这里连提示都没有——表现就是「最后一笔怎么都写不上」。
      //
      // 所以取「画布比例」与「目标笔画长度的 35%」里更小的一个：
      // 长笔画仍按画布比例兜底，只有本来就短的笔画放宽。
      // 与 iOS `WriteSession.minLength(forStroke:)`、Android 同款逻辑保持一致。
      const targetLen = trace.polylineLength(target);
      const minLen = Math.min(this.box * 0.04, targetLen * 0.35);
      if (len < minLen) {
        // 一定要说清楚，否则孩子以为「写了没反应」。
        // 这里**不记**薄弱点：点一下、划得太短多半是误触，
        // 记进去的话两次手滑就把一个笔画标成「薄弱」，那个提示就没人信了。
        this.setData({
          hint: pts.length < 2
            ? '这一笔太短了——按住别松手，沿着虚线划一小段'
            : '这一笔太短了，沿着虚线完整写一遍',
        });
        this.render();
        return;
      }
      if (res.score >= ACCEPT) {
        this.accepted.push({
          points: pts,
          score: res.score,
          snap: res.score >= 68,
        });
        // 写对了也要记一笔：连着对两次才算练稳（见 recordStroke）。
        // 直接清掉的话「失败率」那条门槛就永远没有数据可判。
        progress.recordStroke(this.ch, idx, true);
        const next = idx + 1;
        const total = this.data2.n;
        const avg = Math.round(
          this.accepted.reduce((n, a) => n + a.score, 0) / this.accepted.length
        );
        if (next >= total) {
          this.finish();
        } else {
          this.setData({
            strokeIndex: next,
            liveScore: avg,
            hint: res.score >= 68 ? '很好，继续下一笔' : '这一笔过了，注意笔画要贴住淡色的字',
          });
          this.render();
          wx.vibrateShort && wx.vibrateShort({ type: 'light' });
        }
      } else {
        // 不过关就记一笔薄弱点。之前 res.reason 只拼一句提示就丢了，
        // 于是「这个字的第 2 笔总写不好」这件事从来没被记住过。
        progress.recordStroke(this.ch, this.strokeIndex, false);
        this.setData({ hint: this.reasonText(res.reason) });
        this.render();
        wx.vibrateShort && wx.vibrateShort({ type: 'medium' });
      }
    },

    reasonText(reason) {
      if (reason === 'start') return '起笔的位置不对，从红色小点开始写';
      if (reason === 'short') return '这一笔还没有写完整，再拉长一点';
      if (reason === 'off') return '偏离了笔画，沿着淡淡的那一笔写';
      return '再试一次，慢慢写会更准';
    },

    finish() {
      const result = scoreChar(this.accepted);
      const record = progress.saveWrite(this.ch, result.score);
      progress.learn(this.ch);
      // 趁分包还加载着，把这个字的轮廓存进本地缓存：
      // 字帖导出在冷启动时也能出 PDF（否则分包没加载过，取不到笔画）
      strokeStore.remember(this.ch);
      const tips = [
        '多写几次，手会更稳。',
        '写完读一读这个字，记得更牢。',
        '明天再来写一次，就能记住啦。',
      ];
      this.setData({
        done: true,
        stars: Math.max(result.stars, record.stars || 0),
        score: Math.max(result.score, record.best || 0),
        resultTip: tips[Math.floor(Math.random() * tips.length)],
        liveScore: result.score,
      });
      if (result.stars >= 2) {
        wx.vibrateShort && wx.vibrateShort({ type: 'heavy' });
      }
      // 听写页用它推进到下一个字；描红页不设这个钩子。
      // 放在最后调用，保证成绩已经写进 progress 再通知外部。
      if (typeof this.onCharFinished === 'function') {
        this.onCharFinished(this.ch, result.score, result.stars);
      }
    },

    onHint() {
      const idx = this.data.strokeIndex;
      if (!this.player) {
        const { Player } = PlayerCtor;
        this.player = new Player({
          ctx: this.ctx,
          canvas: this.canvas,
          data: this.data2,
          box: this.box,
          ox: this.ox,
          oy: this.oy,
          onDone: () => this.render(),
        });
      }
      this.player.playStroke(idx, () => {
        setTimeout(() => this.render(), 400);
      });
      this.setData({ hint: '第 ' + (idx + 1) + ' 笔这样写' });
    },

    onUndo() {
      if (!this.accepted.length) {
        wx.showToast({ title: '还没有写好的笔画', icon: 'none' });
        return;
      }
      this.accepted.pop();
      this.setData({
        strokeIndex: this.accepted.length,
        hint: '退回上一笔，重新写一次',
      });
      this.render();
    },

    onReset() {
      this.accepted = [];
      this.ink = [];
      this.setData({ strokeIndex: 0, done: false, liveScore: 0, hint: '沿着淡色的字，一笔一笔写出来' });
      this.render();
    },

    onAgain() {
      this.onReset();
    },

    onNext() {
      const meta = this.data.meta;
      const lesson = catalog.getLesson(meta.l);
      const chars = lesson ? lesson.chars : [];
      const idx = chars.indexOf(this.ch);
      if (idx >= 0 && idx < chars.length - 1) {
        const next = chars[idx + 1];
        this.ch = next;
        const data = hc.get(next);
        this.data2 = data;
        this.accepted = [];
        this.ink = [];
        const nextMeta = catalog.getMeta(next);
        this.setData({
          ch: next,
          py: catalog.readingFor(next, nextMeta.l),
          meta: nextMeta,
          strokeIndex: 0,
          done: false,
          liveScore: 0,
          stars: 0,
          score: 0,
          steps: Array.apply(null, { length: nextMeta.s }).map((_, i) => i),
          hint: '沿着淡色的字，一笔一笔写出来',
        });
        wx.setNavigationBarTitle({ title: '描红 · ' + next });
        this.render();
      } else {
        wx.navigateBack();
      }
    },
  };
};
