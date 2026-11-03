import XCTest
@testable import HanziCore

/// 字帖导出 PDF 的版式。
///
/// 版式算错会让格子重叠或掉出页面，打印出来才发现——那时候纸已经废了。
/// 这个文件只测 `CopybookLayout`（纯计算）；真正的 PDF 渲染在 App 层，
/// 用启动参数导出后人工核对。
///
/// 与小程序 `tests/copybook-pdf.test.mjs`、Android `CopybookPDFTest` 对应。
@MainActor
final class CopybookLayoutTests: XCTestCase {

    func testPageHoldsSixRowsFourCols() {
        XCTAssertEqual(CopybookLayout.rowsPerPage, 6)
        XCTAssertEqual(CopybookLayout.cols, 4)
        let pages = CopybookLayout.layout(["天", "地", "人", "你", "我", "他", "一"])
        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages[0].rows.count, 6)
        XCTAssertEqual(pages[1].rows.count, 1)
    }

    func testFirstCellIsModelRestAreTracing() {
        let cells = CopybookLayout.layout(["天"])[0].rows[0].cells
        XCTAssertEqual(cells.count, 4)
        XCTAssertTrue(cells[0].solid)
        XCTAssertEqual(cells.dropFirst().map(\.solid), [false, false, false])
    }

    func testRowIsHorizontallyCentered() {
        let cells = CopybookLayout.layout(["天"])[0].rows[0].cells
        let left = cells[0].x
        let right = cells[cells.count - 1].x + cells[0].size
        let leftGap = left - CopybookLayout.margin
        let rightGap = CopybookLayout.pageW - CopybookLayout.margin - right
        XCTAssertEqual(leftGap, rightGap, accuracy: 0.01, "左右边距应该相等")
        XCTAssertGreaterThan(leftGap, 0)
    }

    func testCellsDoNotOverlap() {
        let rows = CopybookLayout.layout(["天", "地"])[0].rows
        let cells = rows[0].cells
        for i in 1..<cells.count {
            let prevRight = cells[i - 1].x + cells[i - 1].size
            XCTAssertGreaterThanOrEqual(cells[i].x, prevRight, "第 \(i) 格和前一格重叠了")
        }
        let r0 = rows[0].cells[0]
        let r1 = rows[1].cells[0]
        XCTAssertLessThanOrEqual(r1.y + r1.size, r0.y, "第二行压到第一行了")
    }

    func testAllCellsStayInsidePage() {
        let chars = ["天", "地", "人", "你", "我", "他", "一", "二", "三", "四", "五", "六"]
        for page in CopybookLayout.layout(chars) {
            for row in page.rows {
                for c in row.cells {
                    XCTAssertGreaterThan(c.y, CopybookLayout.margin, "格子掉出下边距")
                    XCTAssertLessThan(c.y + c.size,
                                      CopybookLayout.pageH - CopybookLayout.margin, "格子超出上边距")
                    XCTAssertGreaterThan(c.x, CopybookLayout.margin, "格子超出左边距")
                    XCTAssertLessThan(c.x + c.size,
                                      CopybookLayout.pageW - CopybookLayout.margin, "格子超出右边距")
                }
            }
        }
    }

    func testEmptyListProducesNoPages() {
        XCTAssertTrue(CopybookLayout.layout([]).isEmpty)
    }

    func testExactlySixCharsIsOnePage() {
        XCTAssertEqual(CopybookLayout.layout(["一", "二", "三", "四", "五", "六"]).count, 1)
        XCTAssertEqual(CopybookLayout.layout(["一", "二", "三", "四", "五", "六", "七"]).count, 2)
    }

    /// 描红格的字必须比格线明显深，否则打印出来分不清哪条该描
    func testGhostIsDarkerThanGrid() {
        let ghost = CopybookLayout.colorGhost
        let grid = CopybookLayout.colorGrid
        let ghostLum = 0.299 * ghost.r + 0.587 * ghost.g + 0.114 * ghost.b
        let gridLum = 0.299 * grid.r + 0.587 * grid.g + 0.114 * grid.b
        XCTAssertLessThan(ghostLum, gridLum - 0.05,
                          "描红字和格线太接近（\(ghostLum) vs \(gridLum)），打印出来分不清")
    }

    func testInkIsDarkest() {
        let ink = CopybookLayout.colorInk
        let inkLum = 0.299 * ink.r + 0.587 * ink.g + 0.114 * ink.b
        XCTAssertLessThan(inkLum, 0.25, "范字应该是浓墨")
    }

    func testFileNameHasDateAndPdfExtension() {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 1
        comps.day = 5
        let d = Calendar(identifier: .gregorian).date(from: comps)!
        XCTAssertEqual(CopybookLayout.fileName("字帖", date: d), "字帖-20260105.pdf")
    }

    func testDateLabelPadsZeros() {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 1
        comps.day = 5
        let d = Calendar(identifier: .gregorian).date(from: comps)!
        XCTAssertEqual(CopybookLayout.dateLabel(d), "2026-01-05")
    }
}
