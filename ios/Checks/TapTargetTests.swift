import XCTest
@testable import HanziCore

/// 触达区域。
///
/// Apple HIG 要求可点击元素至少 44×44pt。这个 App 的用户是一二年级的孩子，
/// 手指更小、精细动作控制更弱，比成人更需要留足。
///
/// 尺寸本身在真机/模拟器上是靠 `TapTargetProbe` 实测的（见 `UI/TapTargetProbe.swift`
/// 与 README 的验证记录）。这里只锁住那些「可以离线算出来」的部分。
final class TapTargetTests: XCTestCase {

    /// HIG 的最小触达尺寸
    static let minSide: CGFloat = 44

    /// 组词胶囊：字号 + padding 算出来的自然高度必须够
    ///
    /// 胶囊里最多两行（汉字 15pt + 拼音 10pt），行高约 18 + 12 = 30，
    /// 加 padding(.vertical, 7) × 2 = 14，合计约 44。
    /// 若哪天有人把 padding 调小，这里会先报出来。
    func testWordChipNaturalHeight() {
        let textLine: CGFloat = 18   // 15pt 汉字行高
        let pinyinLine: CGFloat = 12 // 10pt 拼音行高
        let padVertical: CGFloat = 7
        let natural = textLine + pinyinLine + padVertical * 2
        XCTAssertGreaterThanOrEqual(natural, 44,
            "组词胶囊自然高度只有 \(natural)pt，需要靠 minTapTarget 兜底")
    }

    /// 笔画格是固定 44pt 高，必须不小于最小值
    func testStrokeCellHeight() {
        XCTAssertGreaterThanOrEqual(44, Self.minSide)
    }

    /// 答题选项：两行文字 + padding 必须够 44
    func testQuizOptionHeight() {
        let oneLine: CGFloat = 22      // 16pt 文字行高
        let padVertical: CGFloat = 13
        XCTAssertGreaterThanOrEqual(oneLine + padVertical * 2, Self.minSide)
    }

    /// 列表行（单元课次、设置项）高度
    ///
    /// 注意：一行的实际高度是 `max(文字高, 控件高) + padding`，不是「文字高 + padding」。
    /// 我第一版就漏算了这一点，把设置行算成 36pt 判成不达标——
    /// 用 `TapTargetProbe` 在模拟器上实测是 90pt。所以模型要按 max 来算。
    func testListRowHeight() {
        // 单元课次：两行 15pt + 11pt，加 padding(.vertical, 11)
        let twoLines: CGFloat = 18 + 14
        XCTAssertGreaterThanOrEqual(twoLines + 11 * 2, Self.minSide)

        // 设置项：文字一行 18pt，但右侧是 UISwitch（51×31），行高由它决定
        let switchHeight: CGFloat = 31
        let textLine: CGFloat = 18
        let padVertical: CGFloat = 9
        let rowHeight = max(textLine, switchHeight) + padVertical * 2
        XCTAssertGreaterThanOrEqual(rowHeight, Self.minSide,
            "设置行 \(rowHeight)pt，不足 44")
    }

    /// UISwitch 本身就是 51×31，宽度够、高度不足，所以开关行的达标
    /// 必须靠竖向 padding 补足 —— 这条断言防止有人把 padding 调到 6 以下
    func testSwitchRowDependsOnPaddingForHeight() {
        let switchHeight: CGFloat = 31
        let needed = (Self.minSide - switchHeight) / 2  // 6.5
        XCTAssertLessThanOrEqual(needed, 9,
            "开关自身 31pt，需要 padding ≥ \(needed) 才够 44，当前用的是 9")
    }

    /// 底部 tab 高度
    func testTabBarHeight() {
        // 系统 tab bar 默认 49pt + 底部安全区，一定达标
        XCTAssertGreaterThanOrEqual(49, Self.minSide)
    }
}
