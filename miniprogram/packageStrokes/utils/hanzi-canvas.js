/**
 * 汉字画布渲染引擎
 * 与平台无关：只依赖 CanvasRenderingContext2D，小程序 / 浏览器预览共用。
 *
 * 坐标：Make Me a Hanzi 使用 1024×1024 方格，y 轴向下；本引擎把 0-1020 映射到画布边长。
 */
const { get } = require('./stroke-store');

const SIZE = 1024;
// 字形在格子里留一点边距，避免笔画贴死边框（田字格书写习惯）
const PAD_RATIO = 0.035;
const OP_M = 0;
const OP_L = 1;
const OP_Q = 2;
const OP_C = 3;
const OP_Z = 4;

const INK = '#25332d';
const GHOST = '#cfc7b6';
const GUIDE = '#c9bda6';
const HINT = '#8fc4b8';

function padOf(box) {
  return box * PAD_RATIO;
}

function px(v, box) {
  const pad = padOf(box);
  return pad + (v / SIZE) * (box - 2 * pad);
}

function buildPath(ctx, cmds, box, ox, oy) {
  ctx.beginPath();
  for (let i = 0; i < cmds.length; i++) {
    const c = cmds[i];
    if (c[0] === OP_M) ctx.moveTo(ox + px(c[1], box), oy + px(c[2], box));
    else if (c[0] === OP_L) ctx.lineTo(ox + px(c[1], box), oy + px(c[2], box));
    else if (c[0] === OP_Q) ctx.quadraticCurveTo(ox + px(c[1], box), oy + px(c[2], box), ox + px(c[3], box), oy + px(c[4], box));
    else if (c[0] === OP_C) {
      ctx.bezierCurveTo(
        ox + px(c[1], box), oy + px(c[2], box),
        ox + px(c[3], box), oy + px(c[4], box),
        ox + px(c[5], box), oy + px(c[6], box)
      );
    } else if (c[0] === OP_Z) ctx.closePath();
  }
}

/** 把中线折线（已缩放）细分，得到可用于测距/虚线的点序列 */
function medianPoints(median, box, ox, oy) {
  const out = [];
  for (let i = 0; i < median.length; i++) {
    out.push([ox + px(median[i][0], box), oy + px(median[i][1], box)]);
  }
  return out;
}

function polylineLength(pts) {
  let len = 0;
  for (let i = 1; i < pts.length; i++) {
    const dx = pts[i][0] - pts[i - 1][0];
    const dy = pts[i][1] - pts[i - 1][1];
    len += Math.sqrt(dx * dx + dy * dy);
  }
  return len;
}

function tracePath(ctx, pts) {
  if (!pts.length) return;
  ctx.beginPath();
  ctx.moveTo(pts[0][0], pts[0][1]);
  for (let i = 1; i < pts.length; i++) ctx.lineTo(pts[i][0], pts[i][1]);
}

/** 田字格：外框 + 虚线十字 */
function drawGrid(ctx, box, ox, oy, opts) {
  const o = opts || {};
  ctx.save();
  ctx.lineWidth = o.border || 2;
  ctx.strokeStyle = o.borderColor || '#e0d5c0';
  ctx.strokeRect(ox + 0.5, oy + 0.5, box - 1, box - 1);
  ctx.setLineDash(o.dash || [6, 6]);
  ctx.lineWidth = o.line || 1;
  ctx.strokeStyle = o.lineColor || '#eee3d0';
  ctx.beginPath();
  ctx.moveTo(ox + box / 2, oy + box * 0.06);
  ctx.lineTo(ox + box / 2, oy + box * 0.94);
  ctx.moveTo(ox + box * 0.06, oy + box / 2);
  ctx.lineTo(ox + box * 0.94, oy + box / 2);
  ctx.stroke();
  ctx.setLineDash([]);
  ctx.restore();
}

/** 田字格里画淡灰色“字帖底字”（用系统字体画，作为描红参照） */
function drawGhostChar(ctx, ch, box, ox, oy, opts) {
  const o = opts || {};
  ctx.save();
  ctx.fillStyle = o.color || GHOST;
  ctx.font = '600 ' + Math.round(box * 0.84) + 'px "Kaiti SC", "STKaiti", "KaiTi", "Songti SC", serif';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText(ch, ox + box / 2, oy + box * 0.53);
  ctx.restore();
}

/**
 * 画静态字：已写好的笔画实心，未写的笔画用浅色轮廓。
 * progress: 0-1 之间表示“这一笔写到哪里”，或整数笔画数。
 */
function drawStrokes(ctx, data, box, ox, oy, opts) {
  const o = opts || {};
  const completed = o.completed == null ? data.n : o.completed;
  const partial = o.partial == null ? 0 : o.partial;
  const inkColor = o.ink || INK;

  ctx.save();
  ctx.lineJoin = 'round';
  ctx.lineCap = 'round';

  for (let i = 0; i < data.n; i++) {
    const cmds = data.strokes[i];
    if (i < completed) {
      buildPath(ctx, cmds, box, ox, oy);
      ctx.fillStyle = inkColor;
      ctx.fill();
    } else if (i === completed && partial > 0) {
      // 当前笔：裁剪到笔画轮廓内，用粗线沿中线推进
      ctx.save();
      buildPath(ctx, cmds, box, ox, oy);
      ctx.clip();
      const pts = medianPoints(data.medians[i], box, ox, oy);
      const len = polylineLength(pts);
      ctx.strokeStyle = inkColor;
      ctx.lineWidth = Math.max(box * 0.22, 18);
      ctx.lineJoin = 'round';
      ctx.lineCap = 'round';
      ctx.setLineDash([Math.max(len * partial, 0.1), len + 10]);
      tracePath(ctx, pts);
      ctx.stroke();
      ctx.setLineDash([]);
      ctx.restore();
    } else if (o.showGhost !== false) {
      buildPath(ctx, cmds, box, ox, oy);
      if (o.ghostFill) {
        ctx.fillStyle = o.ghostFill;
        ctx.fill();
      } else {
        ctx.strokeStyle = o.ghostLine || HINT;
        ctx.lineWidth = Math.max(box * 0.006, 1);
        ctx.globalAlpha = o.ghostAlpha || 0.55;
        ctx.stroke();
        ctx.globalAlpha = 1;
      }
    }
  }
  ctx.restore();
}

/** 高亮某一笔（详情页点击笔画时用） */
function drawStrokeHighlight(ctx, data, index, box, ox, oy, color) {
  if (index < 0 || index >= data.n) return;
  ctx.save();
  buildPath(ctx, data.strokes[index], box, ox, oy);
  ctx.fillStyle = color || '#df6248';
  ctx.globalAlpha = 0.85;
  ctx.fill();
  ctx.restore();
}

/** 画笔画序号 + 起点圆点（笔顺提示） */
function drawStrokeNumbers(ctx, data, box, ox, oy, opts) {
  const o = opts || {};
  ctx.save();
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  for (let i = 0; i < data.n; i++) {
    if (o.index != null && i !== o.index) continue;
    const m = data.medians[i];
    if (!m || !m.length) continue;
    const start = m[0];
    const x = ox + px(start[0], box);
    const y = oy + px(start[1], box);
    const r = Math.max(box * 0.045, 7);
    ctx.beginPath();
    ctx.arc(x, y, r, 0, Math.PI * 2);
    ctx.fillStyle = o.bg || 'rgba(62,142,126,0.92)';
    ctx.fill();
    ctx.fillStyle = '#ffffff';
    ctx.font = '600 ' + Math.round(r * 1.15) + 'px -apple-system, sans-serif';
    ctx.fillText(String(i + 1), x, y + 0.5);
  }
  ctx.restore();
}

/** 带裁剪的整字填充（结果页大字用） */
function drawCharInk(ctx, ch, box, ox, oy, color) {
  ctx.save();
  ctx.fillStyle = color || INK;
  ctx.font = '600 ' + Math.round(box * 0.9) + 'px "Kaiti SC", "STKaiti", "KaiTi", "Songti SC", serif';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText(ch, ox + box / 2, oy + box * 0.52);
  ctx.restore();
}

/** 取字的笔画数（数据缺失时返回 0） */
function strokeCount(ch) {
  const d = get(ch);
  return d ? d.n : 0;
}

module.exports = {
  SIZE,
  INK,
  GHOST,
  HINT,
  drawGrid,
  drawGhostChar,
  drawStrokes,
  drawStrokeHighlight,
  drawStrokeNumbers,
  drawCharInk,
  medianPoints,
  polylineLength,
  strokeCount,
  get,
};
