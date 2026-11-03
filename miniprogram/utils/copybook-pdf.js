/**
 * 字帖导出 PDF。
 *
 * 屏幕上「我的字帖」是一堆小方块，只能看；打印出来才是真的字帖——
 * 孩子拿铅笔在上面描，比对着屏幕用手指划有用得多。
 *
 * ## 版式
 *
 * 每个字一行，四格：
 *
 *   [范字（浓墨）] [浅灰] [浅灰] [浅灰]
 *
 * 第一格是照着写的范字，后三格是描红格。为什么不是四格全浅：
 * 孩子在第三格就写走形了，第五格会更差，留一个对比基准很有用。
 *
 * ## 一页六个字
 *
 * A4 高 842pt，去掉页边距和页眉页脚剩 706pt，每行 110pt（格子 96 + 行距 14），
 * 正好 6 行。格子再小握笔的幼儿就写不开了；再大就一页五行，纸太浪费。
 *
 * ## 汉字不是"文字"
 *
 * 见 `pdf.js` 的说明：不嵌中文字体，所有汉字都用笔顺轮廓画成矢量路径。
 * 所以这个模块必须拿到笔画数据（`strokeFor` 回调），拿不到的字会被跳过
 * 并在结果里报出来——静默少几个字比报错更让人困惑。
 */
const { Pdf, rgb } = require('./pdf');

const LAYOUT = {
  pageW: 595.28,          // A4
  pageH: 841.89,
  margin: 42,
  headerH: 30,
  footerH: 22,
  cell: 96,
  colGap: 10,
  rowGap: 14,
  cols: 4,                // 1 个范字 + 3 个描红格
  rowsPerPage: 6,
};

const COLOR = {
  guide: '#c9bda6',       // 田字格外框
  grid: '#ded3bd',        // 田字格虚线
  ink: '#25332d',         // 范字
  /**
   * 描红格里的字。
   *
   * 必须比格线明显深一点。第一版用的 #cfc7b6 和格线 #c9bda6 只差 5 个色阶，
   * 打印出来孩子分不清哪条是格线、哪条是该描的字。
   * 现在压到约 30% 浓度：够看清，又不至于描完看不出来自己写过。
   */
  ghost: '#b3aa96',
  footer: '#8a8073',
};

/** 一行四个格子的总宽 */
function rowWidth(l) {
  const cfg = l || LAYOUT;
  return cfg.cols * cfg.cell + (cfg.cols - 1) * cfg.colGap;
}

/**
 * 排页。纯函数，不碰 PDF —— 版式对不对可以直接断言。
 *
 * @param {string[]} chars 要排的字（已去重、已按需要的顺序）
 * @param {object} opts { layout, title }
 * @returns {{pages: object[], perPage: number}}
 */
function layout(chars, opts) {
  const o = opts || {};
  const l = Object.assign({}, LAYOUT, o.layout || {});
  const list = chars || [];
  const perPage = l.rowsPerPage;

  // 横向居中：格子总宽通常小于可用宽度，靠左会显得偏
  const usableW = l.pageW - 2 * l.margin;
  const x0 = l.margin + Math.max(0, (usableW - rowWidth(l)) / 2);

  const pages = [];
  for (let i = 0; i < list.length; i += perPage) {
    const chunk = list.slice(i, i + perPage);
    const rows = chunk.map((ch, r) => {
      // 从页面顶部往下排，转成 PDF 的 y 向上坐标
      const top = l.pageH - l.margin - l.headerH - r * (l.cell + l.rowGap);
      const cells = [];
      for (let c = 0; c < l.cols; c++) {
        cells.push({
          x: x0 + c * (l.cell + l.colGap),
          y: top - l.cell,
          size: l.cell,
          // 第一格是范字，其余是描红格
          solid: c === 0,
        });
      }
      return { ch, cells };
    });
    pages.push({ rows, index: pages.length });
  }
  return { pages, perPage, layout: l };
}

/** 画一个田字格：外框实线 + 十字虚线 */
function drawGrid(pdf, cell) {
  const { x, y, size } = cell;
  pdf.strokeColor(rgb(COLOR.guide));
  pdf.lineWidth(0.6);
  pdf.dash(null);
  pdf.rect(x, y, size, size);
  pdf.stroke();

  // 十字虚线。留 2pt 的内缩，别和外框粘在一起
  pdf.strokeColor(rgb(COLOR.grid));
  pdf.lineWidth(0.45);
  pdf.dash([3, 2.5]);
  const midX = x + size / 2;
  const midY = y + size / 2;
  pdf.moveTo(midX, y + 2);
  pdf.lineTo(midX, y + size - 2);
  pdf.moveTo(x + 2, midY);
  pdf.lineTo(x + size - 2, midY);
  pdf.stroke();
  pdf.dash(null);
}

/**
 * 页眉。
 *
 * 只有日期和页码，没有中文标题——中文标题得靠嵌字体或者笔画轮廓，
 * 而标题里的字（比如「帖」）不一定在本册的笔画数据里。
 * 与其为了排版去凑字形，不如留白：字帖本身已经满是汉字了。
 */
function drawHeader(pdf, l, pageNo, pageTotal, when) {
  const y = l.pageH - l.margin - 14;
  pdf.fillColor(rgb(COLOR.footer));
  pdf.text(when, l.pageW - l.margin - 96, y, 8.5);
  pdf.text(`${pageNo} / ${pageTotal}`, l.pageW - l.margin - 26, y, 8.5);
}

/**
 * 生成 PDF 字节。
 *
 * @param {string[]} chars
 * @param {(ch: string) => object|null} strokeFor 返回解码后的 { strokes }
 * @param {object} opts { dateLabel, titleChars }
 * @returns {{bytes: Uint8Array, pages: number, drawn: string[], skipped: string[]}}
 */
function buildPdf(chars, strokeFor, opts) {
  const o = opts || {};
  const { pages, layout: l } = layout(chars, o);
  const pdf = new Pdf({ width: l.pageW, height: l.pageH });

  const drawn = [];
  const skipped = [];

  pages.forEach((page, idx) => {
    drawHeader(pdf, l, idx + 1, pages.length, o.dateLabel || '');
    for (const row of page.rows) {
      const data = strokeFor(row.ch);
      for (const cell of row.cells) {
        drawGrid(pdf, cell);
        if (!data) continue;
        // 田字格画完再填字，否则虚线会压在字上面
        pdf.fillColor(rgb(cell.solid ? COLOR.ink : COLOR.ghost));
        pdf.glyphPath(data.strokes, cell, 0.05);
      }
      if (data) drawn.push(row.ch);
      else if (skipped.indexOf(row.ch) < 0) skipped.push(row.ch);
    }
    // 页脚：一行极细的分隔线，视觉上收住版面
    pdf.strokeColor(rgb(COLOR.grid));
    pdf.lineWidth(0.4);
    pdf.moveTo(l.margin, l.margin + l.footerH - 8);
    pdf.lineTo(l.pageW - l.margin, l.margin + l.footerH - 8);
    pdf.stroke();
    pdf.endPage();
  });

  return { bytes: pdf.build(), pages: pages.length, drawn, skipped };
}

/** 建议的文件名。小程序写临时文件时用。 */
function fileName(copybookName) {
  const d = new Date();
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  const dd = String(d.getDate()).padStart(2, '0');
  return `${copybookName || '字帖'}-${d.getFullYear()}${mm}${dd}.pdf`;
}

/** 页眉上的日期，用 ASCII 数字（Helvetica 能画） */
function dateLabel(d) {
  const x = d || new Date();
  const mm = String(x.getMonth() + 1).padStart(2, '0');
  const dd = String(x.getDate()).padStart(2, '0');
  return `${x.getFullYear()}-${mm}-${dd}`;
}

module.exports = {
  LAYOUT,
  COLOR,
  layout,
  buildPdf,
  rowWidth,
  fileName,
  dateLabel,
};
