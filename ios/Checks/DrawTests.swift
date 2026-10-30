import XCTest
import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
@testable import HanziCore

/// 绘制层可测的部分：坐标映射、路径构造、动画时间轴。
///
/// 像素级的观感验证靠 `SnapshotExport` 导出 PNG 后比对，
/// 这里只锁住能被纯函数表达的几何与时间逻辑。
@MainActor
final class DrawTests: XCTestCase {

    // MARK: - 坐标映射

    func testPxMapsZeroAndFullToPaddedEdges() {
        let box: CGFloat = 400
        let pad = HanziCanvas.pad(of: box)
        XCTAssertEqual(HanziCanvas.px(0, box: box), pad, accuracy: 0.001)
        XCTAssertEqual(HanziCanvas.px(1024, box: box), box - pad, accuracy: 0.001)
    }

    func testPxIsLinear() {
        let box: CGFloat = 300
        let mid = HanziCanvas.px(512, box: box)
        let quarter = HanziCanvas.px(256, box: box)
        let threeQuarter = HanziCanvas.px(768, box: box)
        // 线性映射：等距输入应等距输出
        XCTAssertEqual(mid - quarter, threeQuarter - mid, accuracy: 0.001)
    }

    // MARK: - 路径构造

    /// 笔画路径应落在画布内。这条能抓住「忘了乘 SCALE」那类缩放错误——
    /// 之前那个 bug 就是坐标缩到 1/6，字小到看不见。
    func testStrokePathsStayInsideCanvas() {
        let repo = TestRepo.make()
        let box: CGFloat = 400
        let origin = CGPoint.zero
        for ch in ["天", "地", "人", "永", "国", "一", "口"] {
            guard let data = repo.strokes(ch) else {
                return XCTFail("\(ch) 缺少笔顺数据")
            }
            for (i, stroke) in data.strokes.enumerated() {
                let path = HanziCanvas.path(for: stroke, box: box, origin: origin)
                let b = path.boundingBoxOfPath
                XCTAssertGreaterThanOrEqual(b.minX, -1, "\(ch) 第\(i + 1)笔超出左边界")
                XCTAssertLessThanOrEqual(b.maxX, box + 1, "\(ch) 第\(i + 1)笔超出右边界")
                XCTAssertGreaterThanOrEqual(b.minY, -1, "\(ch) 第\(i + 1)笔超出上边界")
                XCTAssertLessThanOrEqual(b.maxY, box + 1, "\(ch) 第\(i + 1)笔超出下边界")
                XCTAssertGreaterThan(b.width * b.height, 0, "\(ch) 第\(i + 1)笔退化成一个点")
            }
        }
    }

    /// 墨迹包围盒（相对画布边长归一）
    private func inkExtent(_ ch: String, box: CGFloat = 400) -> CGRect {
        let repo = TestRepo.make()
        guard let data = repo.strokes(ch) else { return .null }
        var union = CGRect.null
        for stroke in data.strokes {
            union = union.union(
                HanziCanvas.path(for: stroke, box: box, origin: .zero).boundingBoxOfPath)
        }
        return CGRect(x: union.minX / box, y: union.minY / box,
                      width: union.width / box, height: union.height / box)
    }

    /// 「一」是一条横线：宽度应接近满格、高度很薄。
    ///
    /// 这是缩放错误最灵敏的探针——之前那个「忘了乘 6」的 bug 会让它变成
    /// 宽 0.13 的一条小短线，肉眼几乎看不见，但这条断言当场就红。
    func testSingleHorizontalStrokeSpansMostOfWidth() {
        let e = inkExtent("一")
        XCTAssertGreaterThan(e.width, 0.70, "「一」太窄，缩放出错")
        XCTAssertLessThan(e.height, 0.25, "「一」应该是薄薄一条")
    }

    /// 满格字应两个方向都占大半个格子
    func testFullCharFillsBox() {
        for ch in ["永", "国", "天"] {
            let e = inkExtent(ch)
            XCTAssertGreaterThan(e.width, 0.60, "「\(ch)」太窄")
            XCTAssertGreaterThan(e.height, 0.60, "「\(ch)」太矮")
        }
    }

    /// 字要大致居中。偏移说明映射的原点算错了。
    func testInkIsRoughlyCentered() {
        for ch in ["永", "国", "天", "地", "人"] {
            let e = inkExtent(ch)
            let cx = e.midX, cy = e.midY
            // 楷体的重心本来就不在几何中心，给 8% 的宽容度
            XCTAssertEqual(cx, 0.5, accuracy: 0.08, "「\(ch)」横向不居中")
            XCTAssertEqual(cy, 0.5, accuracy: 0.08, "「\(ch)」纵向不居中")
        }
    }

    /// 所有教材生字都要落在格子里，不能有越界或退化的
    func testAllCharactersFitInsideBox() {
        let repo = TestRepo.make()
        let box: CGFloat = 200
        var checked = 0
        for ch in Array(repo.allChars.prefix(400)) {
            guard let data = repo.strokes(ch) else { continue }
            var union = CGRect.null
            for stroke in data.strokes {
                union = union.union(
                    HanziCanvas.path(for: stroke, box: box, origin: .zero).boundingBoxOfPath)
            }
            XCTAssertTrue(union.minX >= -1 && union.minY >= -1
                          && union.maxX <= box + 1 && union.maxY <= box + 1,
                          "「\(ch)」越界：\(union)")
            XCTAssertGreaterThan(union.width, 0, "「\(ch)」墨迹为空")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 350, "应检查了足够多的字")
    }

    func testMedianPointsMatchCoordinateMapping() {
        let box: CGFloat = 200
        let origin = CGPoint(x: 10, y: 20)
        let median: [Float] = [0, 0, 1024, 1024]
        let pts = HanziDraw.medianPoints(median, box: box, origin: origin)
        XCTAssertEqual(pts.count, 4)
        let pad = HanziCanvas.pad(of: box)
        XCTAssertEqual(pts[0], origin.x + pad, accuracy: 0.001)
        XCTAssertEqual(pts[1], origin.y + pad, accuracy: 0.001)
        XCTAssertEqual(pts[2], origin.x + box - pad, accuracy: 0.001)
        XCTAssertEqual(pts[3], origin.y + box - pad, accuracy: 0.001)
    }

    func testPolylineLength() {
        let pts: [CGFloat] = [0, 0, 100, 0, 100, 100]
        XCTAssertEqual(HanziDraw.polylineLength(pts), 200, accuracy: 0.001)
    }

    // MARK: - 动画时间轴

    private var slot: Double { (HanziCanvas.perStrokeMs + HanziCanvas.strokeGapMs) / 1000 }

    func testAnimationStartsAtFirstStroke() {
        let s = HanziPlayerView.state(at: 0, count: 4, stopAfter: nil, loop: false)
        XCTAssertEqual(s.completed, 0)
        XCTAssertEqual(s.partial, 0)
        XCTAssertFalse(s.finished)
    }

    func testAnimationMidFirstStroke() {
        // 第一笔正中间
        let t = HanziCanvas.perStrokeMs / 1000 / 2
        let s = HanziPlayerView.state(at: t, count: 4, stopAfter: nil, loop: false)
        XCTAssertEqual(s.completed, 0)
        XCTAssertGreaterThan(s.partial, 0.3)
        XCTAssertLessThan(s.partial, 1.0)
    }

    func testAnimationAdvancesStrokeByStroke() {
        for i in 0..<4 {
            // 每一笔刚开始一点点
            let t = Double(i) * slot + 0.01
            let s = HanziPlayerView.state(at: t, count: 4, stopAfter: nil, loop: false)
            XCTAssertEqual(s.completed, i, "第 \(i + 1) 笔的起点应正好完成 \(i) 笔")
        }
    }

    func testAnimationStopsAfterLastStroke() {
        let total = 4 * slot
        let s = HanziPlayerView.state(at: total + 1, count: 4, stopAfter: nil, loop: false)
        XCTAssertEqual(s.completed, 4)
        XCTAssertEqual(s.partial, 0)
        XCTAssertTrue(s.finished)
    }

    func testStopAfterLimitsPlayback() {
        // 只播前两笔，时间给到全部播完
        let s = HanziPlayerView.state(at: 10 * slot, count: 4, stopAfter: 2, loop: false)
        XCTAssertEqual(s.completed, 2, "应只画到第 2 笔")
        XCTAssertTrue(s.finished)
    }

    func testStopAfterBeyondCountIsClamped() {
        let s = HanziPlayerView.state(at: 10 * slot, count: 4, stopAfter: 99, loop: false)
        XCTAssertEqual(s.completed, 4)
    }

    func testZeroStrokesIsImmediatelyFinished() {
        let s = HanziPlayerView.state(at: 0, count: 0, stopAfter: nil, loop: false)
        XCTAssertEqual(s.completed, 0)
        XCTAssertTrue(s.finished)
    }

    func testLoopWrapsAround() {
        let total = 4 * slot
        // 刚好一整轮之后应回到起点附近
        let s = HanziPlayerView.state(at: total + 0.01, count: 4, stopAfter: nil, loop: true)
        XCTAssertEqual(s.completed, 0)
        XCTAssertFalse(s.finished, "循环播放永远不算结束")
    }

    /// 进度必须单调不减——否则动画会「倒退」
    func testProgressIsMonotonic() {
        var lastCompleted = -1
        var lastPartial: CGFloat = 0
        // 5 笔共需 5*0.76=3.8 秒，多留一点余量
        var t = 0.0
        while t < 4.2 {
            let s = HanziPlayerView.state(at: t, count: 5, stopAfter: nil, loop: false)
            XCTAssertGreaterThanOrEqual(s.completed, lastCompleted, "t=\(t) 完成笔数倒退")
            if s.completed == lastCompleted {
                XCTAssertGreaterThanOrEqual(s.partial, lastPartial - 0.001,
                                            "t=\(t) 同一笔的进度倒退")
            }
            lastCompleted = s.completed
            lastPartial = s.partial
            t += 0.01
        }
        XCTAssertEqual(lastCompleted, 5)
    }

    /// 缓动后进度仍在 0...1 内
    func testPartialStaysNormalized() {
        var t = 0.0
        while t < 4.0 {
            let s = HanziPlayerView.state(at: t, count: 4, stopAfter: nil, loop: false)
            XCTAssertGreaterThanOrEqual(s.partial, 0)
            XCTAssertLessThanOrEqual(s.partial, 1)
            t += 0.01
        }
    }

    // MARK: - 配色

    /// 底字必须比墨迹浅，否则描红时看不清哪一笔是自己写的
    func testGhostIsLighterThanInk() {
        func lum(_ c: Color) -> CGFloat {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            #if canImport(UIKit)
            UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
            #else
            NSColor(c).usingColorSpace(.sRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
            #endif
            return 0.299 * r + 0.587 * g + 0.114 * b
        }
        XCTAssertGreaterThan(lum(HanziDraw.ghost), lum(HanziDraw.ink) + 0.3)
        XCTAssertGreaterThan(lum(HanziDraw.hint), lum(HanziDraw.ink) + 0.2)
    }

    /// 常量必须与 Android / 小程序一致，否则同一个字各端节奏不同
    func testTimingConstantsMatchOtherPlatforms() {
        XCTAssertEqual(HanziCanvas.perStrokeMs, 620)
        XCTAssertEqual(HanziCanvas.strokeGapMs, 140)
        XCTAssertEqual(HanziCanvas.size, 1024)
        XCTAssertEqual(HanziCanvas.padRatio, 0.035, accuracy: 1e-9)
    }
}
