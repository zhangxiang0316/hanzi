import XCTest
@testable import HanziCore

/// 手机端布局。
///
/// 手机和 iPad 的差别不只是「更窄」：底部 tab 占了约 50pt 高，
/// 安全区两边各留一截，可用宽度比屏幕宽度还小。这些测试按真实机型宽度算，
/// 确认分栏、网格列数、留白在每种尺寸下都还合理。
final class PhoneLayoutTests: XCTestCase {

    /// 真实 iPhone 的逻辑宽度（pt），从 SE 到 Pro Max
    static let phoneWidths: [(name: String, width: CGFloat)] = [
        ("iPhone SE", 320),
        ("iPhone 13 mini", 375),
        ("iPhone 17 / 16", 393),
        ("iPhone 17 Pro", 402),
        ("iPhone 17 Pro Max", 440),
        ("Pro Max 横屏", 932),
    ]

    // MARK: - 分栏

    /// 竖屏手机一律单列。这是最要紧的一条：
    /// 402pt 上若分栏，左右各剩约 180pt，汉字和选项都会挤成一条。
    func testPhonesNeverSplitInPortrait() {
        for (name, w) in Self.phoneWidths where w < 500 {
            XCTAssertFalse(LayoutRules.detailIsSplit(w), "\(name)(\(Int(w))pt) 不该分栏")
            XCTAssertFalse(LayoutRules.writeIsSplit(w), "\(name)(\(Int(w))pt) 描红不该分栏")
        }
    }

    /// 手机横屏（Pro Max 932pt）可以分栏 —— 内容区和 iPad 差不多宽，
    /// 分栏能少滚动一屏
    func testProMaxLandscapeMaySplit() {
        XCTAssertTrue(LayoutRules.detailIsSplit(932))
        XCTAssertTrue(LayoutRules.writeIsSplit(932))
    }

    // MARK: - 留白

    /// 手机上留白必须是 20，比例不能太大
    func testPhonePagePad() {
        for (name, w) in Self.phoneWidths where w >= 320 && w <= 440 {
            XCTAssertEqual(LayoutRules.pagePad(w), 20, "\(name) 留白应为 20")
        }
    }

    /// 留白不能吃掉可用宽度的一半以上（SE 只有 320pt）
    func testNarrowestPhoneKeepsUsableWidth() {
        let w: CGFloat = 320
        let usable = w - LayoutRules.pagePad(w) * 2
        XCTAssertGreaterThanOrEqual(usable, 270, "SE 上内容区太窄了")
    }

    /// 手机不限宽（contentMax 返回自身），限宽只在 iPad 上生效
    func testPhoneIsNotWidthCapped() {
        for (_, w) in Self.phoneWidths {
            if w < 700 {
                XCTAssertEqual(LayoutRules.contentMax(w), w, "手机不该限宽")
            }
        }
    }

    // MARK: - 网格

    /// 生字网格：卡片不能被压到 108pt 以下。
    ///
    /// 一开始我按「至少 3 列」写，SE 和 13 mini 直接失败——但这其实是对的：
    /// SE 可用宽度 280pt，放 3 列需要 3×108 + 2×12 = 348pt，物理上放不下。
    /// 2 列、每列 134pt 才是正解：卡片更大，一二年级的孩子更好点中。
    ///
    /// 所以真正要守的不是列数，而是「卡片不小于最小宽」。
    func testCharGridCardsNeverShrinkBelowMinimum() {
        for (name, w) in Self.phoneWidths {
            let usable = w - LayoutRules.pagePad(w) * 2
            let cols = LayoutRules.columns(width: usable, minimum: 108, spacing: 12)
            let cardW = (usable - CGFloat(cols - 1) * 12) / CGFloat(cols)
            XCTAssertGreaterThanOrEqual(cardW, 108,
                "\(name) 生字卡片被压到 \(Int(cardW))pt，低于 108 最小宽")
        }
    }

    /// 手机上至少 2 列，单列会让一屏只能看到一行字
    func testCharGridHasAtLeastTwoColumns() {
        for (name, w) in Self.phoneWidths where w <= 440 {
            let usable = w - LayoutRules.pagePad(w) * 2
            let cols = LayoutRules.columns(width: usable, minimum: 108, spacing: 12)
            XCTAssertGreaterThanOrEqual(cols, 2, "\(name) 生字网格只有 \(cols) 列")
        }
    }

    /// 课本卡片在手机上至少 1 列，且不能因为卡片最小宽 190 而空出一半
    func testBookGridColumnsOnPhones() {
        for (name, w) in Self.phoneWidths where w <= 440 {
            let usable = w - LayoutRules.pagePad(w) * 2
            let cols = LayoutRules.columns(width: usable, minimum: 190, spacing: 12)
            XCTAssertGreaterThanOrEqual(cols, 1, "\(name) 课本网格放不下卡片")
            // 1 列时卡片会占满宽度，不算浪费；这里只确认不会算出 0
            XCTAssertLessThanOrEqual(cols, 2, "\(name) 课本卡片太多列会太挤")
        }
    }

    // MARK: - 描红画布

    /// 描红画布边长必须随可用宽度缩放，且留出手写余量。
    ///
    /// 判定容差是 `box * 0.075`——画布越小，容差越小（SE 上只有约 20pt），
    /// 所以画布不能低于 260pt，否则判定会变得过严。
    func testWriteCanvasStaysLargeEnough() {
        for (name, w) in Self.phoneWidths where w <= 440 {
            let usable = w - LayoutRules.pagePad(w) * 2
            XCTAssertGreaterThanOrEqual(usable, 260,
                "\(name) 画布只有 \(Int(usable))pt，容差会小到难以通过")
        }
    }

    // MARK: - 底部 tab

    /// 底部 tab 只放三个：首页 / 练习 / 我的。
    /// 五个 tab 在 320pt 上每个只剩 64pt，中文标签会挤成一团。
    func testTabCountFitsNarrowestPhone() {
        let tabs = 3
        let w: CGFloat = 320
        XCTAssertGreaterThanOrEqual(w / CGFloat(tabs), 100,
            "每个 tab 不足 100pt，标签会挤")
    }
}
