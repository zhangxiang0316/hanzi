/**
 * 笔顺二进制解码器（与 scripts/build-data.mjs 的编码格式一一对应）
 * 返回：{ n, strokes: [[[op, ...coords], ...], ...], medians: [[[x,y], ...], ...] }
 * 坐标已按 SCALE=6 量化，解码时乘回 6，范围 0-1530（对应 1024 方格）。
 * 注意：y 坐标在构建时已翻转（y' = 900 - y），解码后即为屏幕坐标（y 向下）。
 */
const { toBytes } = require('./base64');

const VERSION = 3;
const SCALE = 6;
const OP_M = 0;
const OP_L = 1;
const OP_Q = 2;
const OP_C = 3;
const OP_Z = 4;

function decode(b64) {
  const buf = toBytes(b64);
  let p = 0;
  const version = buf[p++];
  if (version !== VERSION) throw new Error('笔顺数据版本不支持: ' + version);
  const n = buf[p++];
  const strokes = [];
  for (let i = 0; i < n; i++) {
    const len = buf[p] | (buf[p + 1] << 8);
    p += 2;
    const end = p + len;
    const cmds = [];
    while (p < end) {
      const op = buf[p++];
      let cmd;
      if (op === OP_M) {
        cmd = [OP_M, buf[p++] * SCALE, buf[p++] * SCALE];
      } else if (op === OP_L) {
        cmd = [OP_L, buf[p++] * SCALE, buf[p++] * SCALE];
      } else if (op === OP_Q) {
        cmd = [OP_Q, buf[p++] * SCALE, buf[p++] * SCALE, buf[p++] * SCALE, buf[p++] * SCALE];
      } else if (op === OP_C) {
        cmd = [
          OP_C,
          buf[p++] * SCALE, buf[p++] * SCALE,
          buf[p++] * SCALE, buf[p++] * SCALE,
          buf[p++] * SCALE, buf[p++] * SCALE,
        ];
      } else if (op === OP_Z) {
        cmd = [OP_Z];
      } else {
        throw new Error('未知路径指令: ' + op);
      }
      cmds.push(cmd);
    }
    strokes.push(cmds);
  }
  const medianCount = buf[p++];
  const medians = [];
  for (let i = 0; i < medianCount; i++) {
    const pc = buf[p++];
    const pts = [];
    for (let j = 0; j < pc; j++) {
      pts.push([buf[p++] * SCALE, buf[p++] * SCALE]);
    }
    medians.push(pts);
  }
  return { n, strokes, medians };
}

module.exports = { decode, VERSION };
