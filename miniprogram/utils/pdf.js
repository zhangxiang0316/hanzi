/**
 * 极简 PDF 生成器。
 *
 * 小程序没有生成 PDF 的 API（`wx.openDocument` 只能**打开**已有文件），
 * 所以字帖要导出成 PDF，只能自己拼字节。好在这件事没有想象中难：
 * PDF 就是一种「对象 + 交叉引用表」的文本格式，我们从零写起，不需要
 * 任何第三方库（这个项目一直坚持零依赖）。
 *
 * ## 为什么不用中文字体
 *
 * 正经做法是嵌一个中文 TTF，但那要 3-10MB，远超小程序 2MB 主包限制，
 * 而且 TTC/TTF 子集化本身是个大工程。
 *
 * 所以这里**一个中文字都不画成文字**：汉字全部用笔顺轮廓画成矢量路径
 * （我们本来就有笔画数据，界面上描红的范字也是这么画的）。
 * 只有日期、页码这类数字用 PDF 内置的 Helvetica —— 它是 Base-14 标准字体，
 * 阅读器自带，不需要嵌入任何数据。
 *
 * 顺带的好处：输出是纯矢量，放大到 A3 也不糊，打印比位图清楚得多。
 *
 * ## 坐标
 *
 * PDF 原点在页面**左下角**，y 轴向上；我们的笔画数据是 y 向下（0-1024）。
 * 翻转在 `glyphPath` 里做，调用方只用「格子左上角 + 边长」这种直观坐标。
 */

/** PDF 里的颜色是 0-1 的浮点三元组 */
function rgb(hex) {
  const h = hex.replace('#', '');
  return [
    parseInt(h.slice(0, 2), 16) / 255,
    parseInt(h.slice(2, 4), 16) / 255,
    parseInt(h.slice(4, 6), 16) / 255,
  ];
}

/** 固定两位小数。PDF 不接受科学计数法，1e-7 这种会让阅读器整页不显示。 */
function n(v) {
  const x = Math.abs(v) < 1e-6 ? 0 : v;
  return x.toFixed(2).replace(/\.?0+$/, '') || '0';
}

const OP_M = 0;
const OP_L = 1;
const OP_Q = 2;
const OP_C = 3;
const OP_Z = 4;

class Pdf {
  constructor(opts) {
    const o = opts || {};
    this.width = o.width || 595.28;   // A4
    this.height = o.height || 841.89;
    this.pages = [];
    this.ops = [];
  }

  /** 站点：设置描边颜色（0-1） */
  strokeColor(c) {
    this.ops.push(`${n(c[0])} ${n(c[1])} ${n(c[2])} RG`);
  }

  fillColor(c) {
    this.ops.push(`${n(c[0])} ${n(c[1])} ${n(c[2])} rg`);
  }

  lineWidth(w) {
    this.ops.push(`${n(w)} w`);
  }

  /** 虚线。[实线长, 间隔]，传 null 恢复实线 */
  dash(pattern) {
    this.ops.push(pattern ? `[${pattern.map(n).join(' ')}] 0 d` : '[] 0 d');
  }

  // moveTo / lineTo 必须自己维护 current：quadTo 要拿它做升阶，
  // 只靠 glyphPath 里的 _setCurrent 会让直接调用的人踩空指针
  moveTo(x, y) {
    this.ops.push(`${n(x)} ${n(y)} m`);
    this.current = [x, y];
  }

  lineTo(x, y) {
    this.ops.push(`${n(x)} ${n(y)} l`);
    this.current = [x, y];
  }

  rect(x, y, w, h) {
    this.ops.push(`${n(x)} ${n(y)} ${n(w)} ${n(h)} re`);
  }

  stroke() { this.ops.push('S'); }
  fill() { this.ops.push('f'); }
  /** 填充 + 描边，用于既要有色又要轮廓的地方 */
  fillStroke() { this.ops.push('B'); }

  /**
   * 二次贝塞尔。
   *
   * PDF 的路径指令里**没有二次曲线**，只有三次（`c`）。所以要先把
   * 二次升阶成三次：控制点取 P0 + 2/3(Q-P0) 和 P1 + 2/3(Q-P1)。
   * 这是精确等价的变换，不是近似。
   */
  quadTo(cx, cy, x, y) {
    const [x0, y0] = this.current;
    const c1x = x0 + (2 / 3) * (cx - x0);
    const c1y = y0 + (2 / 3) * (cy - y0);
    const c2x = x + (2 / 3) * (cx - x);
    const c2y = y + (2 / 3) * (cy - y);
    this.ops.push(`${n(c1x)} ${n(c1y)} ${n(c2x)} ${n(c2y)} ${n(x)} ${n(y)} c`);
    this.current = [x, y];
  }

  cubicTo(c1x, c1y, c2x, c2y, x, y) {
    this.ops.push(`${n(c1x)} ${n(c1y)} ${n(c2x)} ${n(c2y)} ${n(x)} ${n(y)} c`);
    this.current = [x, y];
  }

  close() { this.ops.push('h'); }

  /**
   * 把汉字轮廓画成路径。
   *
   * @param {Array} strokes 解码后的笔画数组
   * @param {object} box { x, y, size } —— 格子左上角与边长（PDF 坐标）
   * @param {number} pad 格子内边距比例，和画布引擎保持一致
   */
  glyphPath(strokes, box, padRatio) {
    const pad = box.size * (padRatio === undefined ? 0.035 : padRatio);
    const inner = box.size - 2 * pad;
    const toX = (v) => box.x + pad + (v / 1024) * inner;
    // y 要翻转：数据是 y 向下，PDF 是 y 向上
    const toY = (v) => box.y + box.size - pad - (v / 1024) * inner;
    for (const cmds of strokes) {
      for (const c of cmds) {
        if (c[0] === OP_M) {
          this.moveTo(toX(c[1]), toY(c[2]));
        } else if (c[0] === OP_L) {
          this.lineTo(toX(c[1]), toY(c[2]));
        } else if (c[0] === OP_Q) {
          this.quadTo(toX(c[1]), toY(c[2]), toX(c[3]), toY(c[4]));
        } else if (c[0] === OP_C) {
          this.cubicTo(toX(c[1]), toY(c[2]), toX(c[3]), toY(c[4]), toX(c[5]), toY(c[6]));
        } else if (c[0] === OP_Z) {
          this.close();
        }
      }
      // 每一笔单独填充：笔画之间有重叠，合成一条路径用 nonzero 也能对，
      // 但分开填充更稳（有些轮廓的方向不一致，evenodd 会挖洞）
      this.fill();
    }
  }

  /**
   * 画一段文字。只用于数字和 ASCII —— 中文字体不嵌入，见文件头说明。
   */
  text(str, x, y, size, font) {
    // 只保留可打印 ASCII，防止误传中文变成乱码方块
    const safe = String(str).replace(/[^\x20-\x7e]/g, '?');
    const esc = safe.replace(/\\/g, '\\\\').replace(/\(/g, '\\(').replace(/\)/g, '\\)');
    this.ops.push(`BT /${font || 'F1'} ${n(size)} Tf ${n(x)} ${n(y)} Td (${esc}) Tj ET`);
  }

  /** 结束当前页 */
  endPage() {
    this.pages.push(this.ops.join('\n'));
    this.ops = [];
  }

  /**
   * 输出为 PDF 字节。
   *
   * 对象编号：1 = Catalog，2 = Pages，3 = Font，
   * 之后每页两个对象（Page + Contents）。
   */
  build() {
    if (this.ops.length) this.endPage();
    const objects = [];
    const pageCount = this.pages.length;
    const firstPageObj = 4;

    objects[1] = '<< /Type /Catalog /Pages 2 0 R >>';
    const kids = [];
    for (let i = 0; i < pageCount; i++) kids.push(`${firstPageObj + i * 2} 0 R`);
    objects[2] = `<< /Type /Pages /Kids [${kids.join(' ')}] /Count ${pageCount} >>`;
    objects[3] = '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>';

    for (let i = 0; i < pageCount; i++) {
      const pageObj = firstPageObj + i * 2;
      const contentObj = pageObj + 1;
      const body = this.pages[i];
      objects[pageObj] =
        `<< /Type /Page /Parent 2 0 R ` +
        `/MediaBox [0 0 ${n(this.width)} ${n(this.height)}] ` +
        `/Resources << /Font << /F1 3 0 R >> >> ` +
        `/Contents ${contentObj} 0 R >>`;
      objects[contentObj] = `<< /Length ${body.length} >>\nstream\n${body}\nendstream`;
    }

    // 拼字节并记录每个对象的偏移量（xref 表要用）
    let out = '%PDF-1.4\n%\xE2\xE3\xCF\xD3\n';
    const offsets = [];
    for (let i = 1; i < objects.length; i++) {
      if (!objects[i]) continue;
      offsets[i] = out.length;
      out += `${i} 0 obj\n${objects[i]}\nendobj\n`;
    }
    const xrefPos = out.length;
    const maxObj = objects.length;
    out += `xref\n0 ${maxObj}\n0000000000 65535 f \n`;
    for (let i = 1; i < maxObj; i++) {
      const off = offsets[i] || 0;
      out += `${String(off).padStart(10, '0')} 00000 n \n`;
    }
    out +=
      `trailer\n<< /Size ${maxObj} /Root 1 0 R >>\n` +
      `startxref\n${xrefPos}\n%%EOF\n`;

    // Latin-1 逐字节写出：内容全是 ASCII，长度和字符数一致
    const bytes = new Uint8Array(out.length);
    for (let i = 0; i < out.length; i++) bytes[i] = out.charCodeAt(i) & 0xff;
    return bytes;
  }
}

module.exports = { Pdf, rgb, OP_M, OP_L, OP_Q, OP_C, OP_Z };
