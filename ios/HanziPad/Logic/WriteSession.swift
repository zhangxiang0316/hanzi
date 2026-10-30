import Foundation
import CoreGraphics

/// 描红会话状态机，与 Android `WritePage.kt` 的 `pointerInput` 块对应。
///
/// 把「一笔写完怎么判定」从视图里抽出来，是因为这段逻辑最容易出错、
/// 又最难靠看界面发现问题：判定松了孩子乱画也过关，紧了会产生
/// 「明明照着写」的挫败感。抽成纯函数后可以用测试逐条盯住。
///
/// 坐标一律用画布像素。容差按画布边长取比例，所以在任何尺寸的 iPad 上
/// 手感一致——这一点比"写死 26px"重要得多，iPad 从 mini 到 13 寸
/// 画布边长能差一倍以上。
@MainActor
final class WriteSession: ObservableObject {

    enum Outcome: Equatable {
        /// 这一笔通过，进入下一笔
        case passed(index: Int, score: Int)
        /// 这一笔不通过，要求重写
        case rejected(reason: String)
        /// 整字写完
        case finished(score: Int, stars: Int)
        /// 太短，不算数（不消耗笔画，也不算失败）
        case tooShort
    }

    let ch: String
    let strokes: StrokeCodec.CharStrokes?
    /// 画布边长（像素）
    private(set) var box: CGFloat

    @Published private(set) var index: Int = 0
    @Published private(set) var scores: [Int] = []
    @Published private(set) var finished = false
    @Published private(set) var finalScore = 0
    @Published private(set) var finalStars = 0
    /// 最近一次的失败提示，空串表示没有
    @Published private(set) var message = ""

    var count: Int { strokes?.count ?? 0 }
    var isDone: Bool { finished }

    /// 容差：画布边长的 7.5%（与 Android 一致）
    var tolerance: CGFloat { box * 0.075 }
    /// 短于这个长度就不算一笔（画布比例的兜底值）
    var minLength: CGFloat { box * 0.04 }

    /// 这一笔「算一笔」所需的最短长度。
    ///
    /// 不能只用画布比例。点画（点）本身就很短——「玉」「太」的末笔中线只有
    /// 52-55px（画布 400 时），而 `box * 0.04 = 16px` 要求至少画出它的三成。
    /// 孩子把点写成一个更小的点时，长度卡在门槛下，就会被判「太短」，
    /// 而**被判太短不消耗笔画**——于是永远停在这一笔上。
    ///
    /// 所以取「画布比例」与「目标笔画长度的 35%」里更小的一个：
    /// 长笔画仍按画布比例兜底，短笔画按自身长度放宽。
    /// 这不改变长笔画的严格度，只让本来就短的笔画有活路。
    func minLength(forStroke i: Int) -> CGFloat {
        let base = minLength
        guard let t = targetPoints(for: i) else { return base }
        let targetLen = CGFloat(Trace.polylineLength(t))
        guard targetLen > 0 else { return base }
        return min(base, targetLen * 0.35)
    }

    init(ch: String, strokes: StrokeCodec.CharStrokes?, box: CGFloat) {
        self.ch = ch
        self.strokes = strokes
        self.box = box
    }

    func updateBox(_ box: CGFloat) {
        // 布局变化（旋屏、分栏拖动）时更新，但只有值真的变了才写，
        // 免得每帧都触发重绘
        if abs(self.box - box) > 0.5 { self.box = box }
    }

    /// 目标笔画的中线（画布像素坐标，扁平）
    func targetPoints(for i: Int) -> [Float]? {
        guard let strokes, i >= 0 && i < strokes.count else { return nil }
        let median = strokes.medians[i]
        guard median.count >= 4 else { return nil }
        var out: [Float] = []
        out.reserveCapacity(median.count)
        var k = 0
        while k + 1 < median.count {
            out.append(Float(HanziCanvas.px(median[k], box: box)))
            out.append(Float(HanziCanvas.px(median[k + 1], box: box)))
            k += 2
        }
        return out
    }

    /// 提交一笔（用户抬手时调用）
    /// - Parameter points: 用户笔迹，画布像素坐标，扁平存放
    func submit(_ points: [Float]) -> Outcome {
        guard !finished else { return .rejected(reason: "已经写完了") }
        guard count > 0, let target = targetPoints(for: index) else {
            return .rejected(reason: "这一笔没有参照数据")
        }

        // 只点一下或者划得太短：不算数，也不消耗笔画。
        //
        // 早先 Android 这里什么都不做，孩子会以为「写了没反应」——
        // 而点（点画）恰恰经常是最后一笔，于是就成了「最后一笔写不上」。
        if points.count < 4 || CGFloat(Trace.polylineLength(points)) < minLength(forStroke: index) {
            // 提示要能指导下一步：只说「太短」孩子不知道该怎么办。
            // 点一下（只有一个采样点）是常见情况，单独说明。
            message = points.count < 4
                ? "这一笔没采到线——按住别松手，沿着虚线划一小段"
                : "这一笔太短了，沿着虚线完整写一遍"
            return .tooShort
        }

        let r = Trace.scoreStroke(
            userPts: points, targetPts: target,
            tolerance: Float(tolerance)
        )

        if r.score >= Trace.accept {
            scores.append(r.score)
            message = ""
            if index + 1 >= count {
                let result = Trace.scoreChar(scores)
                finalScore = result.score
                finalStars = result.stars
                finished = true
                return .finished(score: result.score, stars: result.stars)
            }
            let passed = index
            index += 1
            return .passed(index: passed, score: r.score)
        } else {
            // 不达标：清空这一笔让用户重写，并说清楚原因
            message = Self.reasonText(r.reason)
            return .rejected(reason: message)
        }
    }

    /// 跳过当前这一笔（用于「这个字我不写了」）
    func skip() {
        guard !finished, index < count else { return }
        // 跳过记为 0 分：整字评分会把最差的一笔算进来，
        // 所以跳过去不是「白跳」，最终星级会如实下降
        scores.append(0)
        message = ""
        if index + 1 >= count {
            let result = Trace.scoreChar(scores)
            finalScore = result.score
            finalStars = result.stars
            finished = true
        } else {
            index += 1
        }
    }

    func restart() {
        index = 0
        scores = []
        finished = false
        finalScore = 0
        finalStars = 0
        message = ""
    }

    /// 当前进度 0...1
    ///
    /// 写完最后一笔时 `index` 不再自增（否则会越界到 strokes[count]），
    /// 所以必须显式处理 finished，否则进度条会停在 3/4——看起来像没写完。
    var progress: Double {
        if count == 0 || finished { return 1 }
        return Double(index) / Double(count)
    }

    static func reasonText(_ reason: String) -> String {
        switch reason {
        case "start": return "起笔的位置不太对，从红点开始写"
        case "off":   return "有些偏离虚线了，沿着虚线再写一遍"
        case "short": return "没写完整，一直写到虚线结束的地方"
        case "empty": return "没检测到笔画，再试一次"
        default:      return "再写一遍试试，沿着虚线慢慢写"
        }
    }
}

/// 用户笔迹的平滑与简化。
///
/// 直接用原始触点有两个问题：手指抖动会让笔迹毛糙（观感），
/// 采样点过密会让评分里的距离计算变慢（性能）。
/// 这里先做移动平均去抖，再做等距重采样。
enum StrokeSmoothing {

    /// 采样点已经足够稀疏时不做平滑。
    ///
    /// 移动平均的前提是「相邻点足够近，差异主要是抖动」。如果相邻点本身就隔着
    /// 十几像素，平均的结果是把折线的拐角切掉——笔画形状被改变，而抖动本来就是
    /// 相对间距而言的小量，平滑也压不掉什么。
    ///
    /// 这个阈值不是凭空定的：汉字笔顺数据的中线只有 6-20 个点（「天」第一笔 6 点），
    /// 真实手指在 iPad 上每次滑动能采到上百点。不设这道闸的话，
    /// 稀疏输入会被平滑成一条被切角的曲线，白白丢 2-5 分。
    private static let maxSpacingForSmoothing: Float = 8

    /// 相邻点的平均间距
    static func averageSpacing(_ pts: [Float]) -> Float {
        let n = pts.count / 2
        guard n >= 2 else { return 0 }
        var total: Float = 0
        var i = 1
        while i < n {
            let dx = pts[i * 2] - pts[(i - 1) * 2]
            let dy = pts[i * 2 + 1] - pts[(i - 1) * 2 + 1]
            total += (dx * dx + dy * dy).squareRoot()
            i += 1
        }
        return total / Float(n - 1)
    }

    /// 移动平均去抖。窗口越大越平滑，但笔画的转折也会被磨圆。
    ///
    /// 3 是折中：手指抖动的幅度通常在 1-2px，3 点平均能压掉大半，
    /// 而汉字里最小的转折（比如「乙」的钩）半径也有几十像素，不会被磨掉。
    ///
    /// 点本身很稀疏时直接返回原样，理由见 `maxSpacingForSmoothing`。
    static func smooth(_ pts: [Float], window: Int = 3) -> [Float] {
        let n = pts.count / 2
        guard n >= 3, window >= 2 else { return pts }
        if averageSpacing(pts) > maxSpacingForSmoothing { return pts }
        var out = pts
        let half = window / 2
        for i in 0..<n {
            // 首尾点保持不动：起笔和收笔的位置是判分依据，不能偏移
            if i == 0 || i == n - 1 { continue }
            var sx: Float = 0
            var sy: Float = 0
            var cnt: Float = 0
            for k in max(0, i - half)...min(n - 1, i + half) {
                sx += pts[k * 2]
                sy += pts[k * 2 + 1]
                cnt += 1
            }
            out[i * 2] = sx / cnt
            out[i * 2 + 1] = sy / cnt
        }
        return out
    }

    /// 丢掉距离过近的连续点
    static func dedupe(_ pts: [Float], minDist: Float = 1.5) -> [Float] {
        let n = pts.count / 2
        guard n >= 2 else { return pts }
        var out: [Float] = [pts[0], pts[1]]
        var lastX = pts[0], lastY = pts[1]
        for i in 1..<n {
            let x = pts[i * 2], y = pts[i * 2 + 1]
            let dx = x - lastX, dy = y - lastY
            if (dx * dx + dy * dy).squareRoot() >= minDist {
                out.append(x)
                out.append(y)
                lastX = x
                lastY = y
            }
        }
        // 末点一定要保留：收笔位置参与评分
        if out.count >= 2, (out[out.count - 2] != pts[(n - 1) * 2]
                            || out[out.count - 1] != pts[(n - 1) * 2 + 1]) {
            out.append(pts[(n - 1) * 2])
            out.append(pts[(n - 1) * 2 + 1])
        }
        return out
    }
}
