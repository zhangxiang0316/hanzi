/**
 * 描红评分（纯函数）
 * 思路：把用户笔迹点与目标笔画中线比对
 *  - 起点距离、终点距离（是否按正确方向起笔收笔）
 *  - 用户点到中线的平均距离（覆盖得好不好）
 *  - 用户笔迹长度与中线长度比（是否拖泥带水）
 * 返回 0-100 分。
 */
function dist(a, b) {
  const dx = a[0] - b[0];
  const dy = a[1] - b[1];
  return Math.sqrt(dx * dx + dy * dy);
}

function polylineLength(pts) {
  let len = 0;
  for (let i = 1; i < pts.length; i++) len += dist(pts[i], pts[i - 1]);
  return len;
}

/** 点到折线的最短距离 */
function pointToPolyline(p, poly) {
  let best = Infinity;
  for (let i = 1; i < poly.length; i++) {
    const a = poly[i - 1];
    const b = poly[i];
    const vx = b[0] - a[0];
    const vy = b[1] - a[1];
    const wx = p[0] - a[0];
    const wy = p[1] - a[1];
    const len2 = vx * vx + vy * vy;
    let t = len2 ? (wx * vx + wy * vy) / len2 : 0;
    t = Math.max(0, Math.min(1, t));
    const d = dist(p, [a[0] + vx * t, a[1] + vy * t]);
    if (d < best) best = d;
  }
  return best;
}

/** 重采样为等距点，减少采样频率差异带来的误差 */
function resample(pts, step) {
  if (pts.length < 2) return pts.slice();
  const out = [pts[0]];
  let carry = 0;
  for (let i = 1; i < pts.length; i++) {
    let a = pts[i - 1];
    const b = pts[i];
    let seg = dist(a, b);
    if (seg === 0) continue;
    while (carry + seg >= step) {
      const t = (step - carry) / seg;
      const p = [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t];
      out.push(p);
      a = p;
      seg = dist(a, b);
      carry = 0;
    }
    carry += seg;
  }
  const last = pts[pts.length - 1];
  if (dist(out[out.length - 1], last) > step * 0.4) out.push(last);
  return out;
}

function clamp01(v) {
  return Math.max(0, Math.min(1, v));
}

/**
 * @param {Array<[number,number]>} userPts 用户笔画（画布像素坐标）
 * @param {Array<[number,number]>} targetPts 目标中线（同坐标系）
 * @param {object} [opts] { tolerance: 允许偏差像素 }
 */
function scoreStroke(userPts, targetPts, opts) {
  const o = opts || {};
  const tol = o.tolerance || 26;
  if (!userPts || userPts.length < 2) return { score: 0, reason: 'empty' };
  if (!targetPts || targetPts.length < 2) return { score: 0, reason: 'no-target' };

  const user = resample(userPts, Math.max(3, tol * 0.35));
  const target = resample(targetPts, Math.max(3, tol * 0.35));

  const startD = dist(user[0], target[0]);
  const endD = dist(user[user.length - 1], target[target.length - 1]);
  const startScore = clamp01(1 - startD / (tol * 2.2));
  const endScore = clamp01(1 - endD / (tol * 2.2));

  // 覆盖度：用户每个点到中线的平均距离
  let sum = 0;
  for (let i = 0; i < user.length; i++) sum += pointToPolyline(user[i], target);
  const avg = sum / user.length;
  const coverScore = clamp01(1 - avg / tol);

  // 反向检查：中线上每个点到用户笔迹的距离，避免只点一下就得高分
  let sum2 = 0;
  for (let i = 0; i < target.length; i++) sum2 += pointToPolyline(target[i], user);
  const reachScore = clamp01(1 - sum2 / target.length / tol);

  const lu = polylineLength(user);
  const lt = polylineLength(target);
  const ratio = lu / lt;
  const lengthScore = ratio >= 0.75 && ratio <= 1.45 ? 1 : clamp01(1 - Math.abs(1 - ratio) / 0.85);

  const raw =
    startScore * 0.18 +
    endScore * 0.12 +
    coverScore * 0.32 +
    reachScore * 0.26 +
    lengthScore * 0.12;

  const score = Math.round(clamp01(raw) * 100);
  let reason = 'ok';
  if (startScore < 0.45) reason = 'start';
  else if (coverScore < 0.45) reason = 'off';
  else if (reachScore < 0.45) reason = 'short';
  return { score, reason };
}

/** 整字评分：各笔平均，全部笔画完成后调用 */
function scoreChar(strokes) {
  if (!strokes || !strokes.length) return { score: 0, stars: 0 };
  let total = 0;
  let min = 100;
  for (let i = 0; i < strokes.length; i++) {
    total += strokes[i].score;
    if (strokes[i].score < min) min = strokes[i].score;
  }
  const avg = total / strokes.length;
  // 有一笔特别差就扣分，避免“乱画也高分”
  const score = Math.round(avg * 0.85 + min * 0.15);
  const stars = score >= 85 ? 3 : score >= 65 ? 2 : score >= 40 ? 1 : 0;
  return { score, stars };
}

module.exports = { scoreStroke, scoreChar, pointToPolyline, resample, polylineLength };
