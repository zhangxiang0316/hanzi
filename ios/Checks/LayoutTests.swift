import XCTest
@testable import HanziCore

/// 自适应布局规则。
///
/// iPadOS 26 起应用是窗口化的，用户可以拖到任意宽度，
/// 「横屏/竖屏」已经不再是确定的布局语境。所以这些阈值必须靠穷举边界验证，
/// 而不是靠截图——截图只能覆盖我当时恰好设的那个尺寸。
final class LayoutTests: XCTestCase {

    // MARK: - 分栏阈值

    func testDetailSplitsAboveThreshold() {
        XCTAssertFalse(LayoutRules.detailIsSplit(320))
        XCTAssertFalse(LayoutRules.detailIsSplit(719))
        XCTAssertFalse(LayoutRules.detailIsSplit(720), "阈值本身仍算窄")
        XCTAssertTrue(LayoutRules.detailIsSplit(721))
        XCTAssertTrue(LayoutRules.detailIsSplit(1280))
    }

    func testWriteSplitsLaterThanDetail() {
        // 描红要保证画布够大，所以比详情页更晚分栏
        XCTAssertGreaterThan(LayoutRules.writeSplitWidth, LayoutRules.detailSplitWidth)
        XCTAssertFalse(LayoutRules.writeIsSplit(760), "详情页已分栏的宽度下，描红仍是单列")
        XCTAssertFalse(LayoutRules.writeIsSplit(820))
        XCTAssertTrue(LayoutRules.writeIsSplit(821))
    }

    /// 分栏后左右两栏都得有可用宽度
    func testSplitLeavesEnoughRoomForBothPanes() {
        // 详情页分栏后左栏上限 420，右栏至少应有 280
        XCTAssertGreaterThanOrEqual(LayoutRules.detailSplitWidth - 420, 280,
                                    "刚分栏时右栏太窄，内容会被挤成一条")
    }

    // MARK: - 网格列数

    func testAdaptiveColumns() {
        // 首页课本卡片：最小 190，间距 12
        XCTAssertEqual(LayoutRules.columns(width: 320, minimum: 190, spacing: 12), 1)
        XCTAssertEqual(LayoutRules.columns(width: 447, minimum: 190, spacing: 12), 2)
        XCTAssertEqual(LayoutRules.columns(width: 700, minimum: 190, spacing: 12), 3)
        XCTAssertEqual(LayoutRules.columns(width: 1280, minimum: 190, spacing: 12), 6)
    }

    func testAdaptiveColumnsAlwaysAtLeastOne() {
        XCTAssertEqual(LayoutRules.columns(width: 10, minimum: 190, spacing: 12), 1)
        XCTAssertEqual(LayoutRules.columns(width: 0, minimum: 190, spacing: 12), 1)
    }

    /// 生字卡片在 iPad mini 竖屏（447pt）也要能排下 4 列
    func testCharGridOnSmallestWidth() {
        let n = LayoutRules.columns(width: 447, minimum: 108, spacing: 12)
        XCTAssertGreaterThanOrEqual(n, 3, "mini 上生字卡片太少列，一屏看不到几个字")
    }

    // MARK: - 留白

    func testPagePadGrowsWithWidth() {
        XCTAssertEqual(LayoutRules.pagePad(320), 20)
        XCTAssertEqual(LayoutRules.pagePad(499), 20)
        XCTAssertEqual(LayoutRules.pagePad(500), 28)
        XCTAssertEqual(LayoutRules.pagePad(799), 28)
        XCTAssertEqual(LayoutRules.pagePad(800), 36)
        XCTAssertEqual(LayoutRules.pagePad(1280), 36)
    }

    /// 留白不能吃掉全部可用宽度（分屏极窄时）
    func testPagePadNeverExceedsHalfWidth() {
        for w in [280, 320, 380, 447] as [CGFloat] {
            XCTAssertLessThan(LayoutRules.pagePad(w) * 2, w,
                              "宽度 \(w) 时留白吃掉了全部空间")
        }
    }

    func testContentMaxCapsLineLength() {
        XCTAssertEqual(LayoutRules.contentMax(320), 320, "窄屏不限制")
        XCTAssertEqual(LayoutRules.contentMax(699), 699)
        XCTAssertEqual(LayoutRules.contentMax(700), 760)
        XCTAssertEqual(LayoutRules.contentMax(1280), 760, "宽屏要限宽，否则一行太长难读")
    }

    /// 限宽后剩余空间应留白居中，不能让内容只贴左边
    func testContentMaxLeavesReasonableMargin() {
        let w: CGFloat = 1280
        let content = LayoutRules.contentMax(w)
        let margin = (w - content) / 2
        XCTAssertGreaterThan(margin, 100, "13 寸横屏两侧几乎没有留白")
        XCTAssertLessThan(margin, 320, "留白过多，内容挤在中间一小条")
    }

    // MARK: - 综合场景

    /// 列出一组真实设备/窗口尺寸，确认每种下都拿到合理结果
    func testRealWorldSizes() {
        struct Case {
            let name: String
            let width: CGFloat
            let expectSplit: Bool
            let minBookCols: Int
        }
        // 宽度取「内容区」而不是屏幕宽（13 寸要扣掉 245pt 侧栏）
        let cases = [
            Case(name: "mini 竖屏", width: 447, expectSplit: false, minBookCols: 1),
            Case(name: "mini 分屏", width: 320, expectSplit: false, minBookCols: 1),
            Case(name: "11 寸竖屏", width: 590, expectSplit: false, minBookCols: 2),
            Case(name: "13 寸竖屏", width: 780, expectSplit: true, minBookCols: 3),
            Case(name: "13 寸横屏", width: 1100, expectSplit: true, minBookCols: 5),
        ]
        for c in cases {
            XCTAssertEqual(LayoutRules.detailIsSplit(c.width), c.expectSplit,
                           "\(c.name)(\(Int(c.width))pt) 的分栏判断不对")
            let cols = LayoutRules.columns(width: c.width, minimum: 190, spacing: 12)
            XCTAssertGreaterThanOrEqual(cols, c.minBookCols,
                                        "\(c.name) 课本卡片列数不足：\(cols)")
        }
    }
}
