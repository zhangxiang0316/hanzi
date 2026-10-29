import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const hc = require('../miniprogram/utils/hanzi-canvas.js');
const trace = require('../miniprogram/utils/trace.js');
const strokeStore = require('../miniprogram/utils/stroke-store.js');
const routes = require('../miniprogram/utils/routes.js');

// 笔顺数据在小程序里由分包页面按需注册；Node 环境下手动注册一遍
for (const book of Object.keys(routes.PACK_OF_BOOK)) {
  const pack = routes.packOf(book);
  strokeStore.register(book, () => require('../miniprogram/' + pack + '/data/strokes-' + book + '.js'));
}

const BOX = 300;
const CH = '天';

function median(ch, i) {
  const d = hc.get(ch);
  return hc.medianPoints(d.medians[i], BOX, 0, 0);
}

/** 沿中线采样，加一点抖动，模拟手写 */
function userStroke(pts, jitter = 0, offset = 0, reverse = false) {
  const out = [];
  const list = reverse ? pts.slice().reverse() : pts;
  for (let i = 0; i < list.length; i++) {
    const p = list[i];
    const prev = list[Math.max(0, i - 1)];
    const next = list[Math.min(list.length - 1, i + 1)];
    let nx = -(next[1] - prev[1]);
    let ny = next[0] - prev[0];
    const len = Math.hypot(nx, ny) || 1;
    nx /= len;
    ny /= len;
    const r = jitter ? (Math.random() * 2 - 1) * jitter : 0;
    out.push([p[0] + nx * (offset + r), p[1] + ny * (offset + r)]);
  }
  return out;
}

test('沿着中线写，得分高', () => {
  for (let i = 0; i < 3; i++) {
    const target = median(CH, i);
    const res = trace.scoreStroke(userStroke(target, 2), target, { tolerance: BOX * 0.075 });
    assert.ok(res.score >= 80, `第 ${i + 1} 笔得分偏低: ${res.score}`);
  }
});

test('偏离中线太远，得分低', () => {
  const target = median(CH, 0);
  const res = trace.scoreStroke(userStroke(target, 1, BOX * 0.22), target, { tolerance: BOX * 0.075 });
  assert.ok(res.score < 55, '偏移后得分仍然很高: ' + res.score);
});

test('反向书写会被识别为起笔错误', () => {
  const target = median(CH, 1);
  const res = trace.scoreStroke(userStroke(target, 1, 0, true), target, { tolerance: BOX * 0.075 });
  assert.ok(res.score < 70, '反向书写得分过高: ' + res.score);
  assert.ok(['start', 'short', 'off'].includes(res.reason));
});

test('只画一小段，得分低', () => {
  const target = median(CH, 0);
  const part = userStroke(target).slice(0, Math.max(2, Math.floor(target.length * 0.18)));
  const res = trace.scoreStroke(part, target, { tolerance: BOX * 0.075 });
  assert.ok(res.score < 70, '半截笔画得分过高: ' + res.score);
});

test('空白输入不得分', () => {
  const target = median(CH, 0);
  assert.equal(trace.scoreStroke([], target).score, 0);
  assert.equal(trace.scoreStroke([[1, 1]], target).score, 0);
});

test('整字评分：三笔全对得三星', () => {
  const strokes = [
    { score: 95 },
    { score: 90 },
    { score: 88 },
  ];
  const res = trace.scoreChar(strokes);
  assert.equal(res.stars, 3);
  assert.ok(res.score >= 85);
});

test('整字评分：有一笔很差会拉低总分', () => {
  const good = trace.scoreChar([{ score: 95 }, { score: 95 }, { score: 95 }]);
  const bad = trace.scoreChar([{ score: 95 }, { score: 95 }, { score: 20 }]);
  assert.ok(bad.score < good.score - 10);
  assert.ok(bad.stars < 3);
});

test('评分在 0-100 之间', () => {
  for (const ch of ['一', '人', '口', '日']) {
    const d = hc.get(ch);
    for (let i = 0; i < d.n; i++) {
      const target = hc.medianPoints(d.medians[i], BOX, 0, 0);
      for (const mode of [0, 1]) {
        const pts = mode ? userStroke(target, 6, 12) : userStroke(target, 0, 0);
        const s = trace.scoreStroke(pts, target, { tolerance: BOX * 0.075 }).score;
        assert.ok(s >= 0 && s <= 100, `${ch} 第 ${i + 1} 笔分数越界 ${s}`);
      }
    }
  }
});
