import Foundation

/// 描红评分，与 Android `Trace.kt`、小程序 `utils/trace.js` 逐行对应。
///
/// 思路：把用户笔迹点与目标笔画中线比对
///   - 起点距离、终点距离（是否按正确方向起笔收笔）
///   - 用户点到中线的平均距离（覆盖得好不好）
///   - 中线上每个点到用户笔迹的距离（防止只点一下就得高分）
///   - 用户笔迹长度与中线长度比（是否拖泥带水）
///
/// 三端的参数必须完全一致，否则同一个字在 Android 上 3 星、在 iPad 上 2 星。
enum Trace {
    /// 单笔通过分，低于这个分要求重写这一笔
    static let accept = 42

    private static let wStart: Float = 0.18
    private static let wEnd: Float = 0.12
    private static let wCover: Float = 0.32
    private static let wReach: Float = 0.26
    private static let wLength: Float = 0.12

    struct Result {
        let score: Int
        let reason: String
    }

    struct CharResult {
        let score: Int
        let stars: Int
    }

    static func dist(_ ax: Float, _ ay: Float, _ bx: Float, _ by: Float) -> Float {
        let dx = ax - bx
        let dy = ay - by
        return (dx * dx + dy * dy).squareRoot()
    }

    static func polylineLength(_ pts: [Float]) -> Float {
        var len: Float = 0
        var i = 2
        while i < pts.count {
            len += dist(pts[i - 2], pts[i - 1], pts[i], pts[i + 1])
            i += 2
        }
        return len
    }

    /// 点到折线的最短距离
    static func pointToPolyline(_ px: Float, _ py: Float, _ poly: [Float]) -> Float {
        var best = Float.greatestFiniteMagnitude
        var i = 2
        while i < poly.count {
            let ax = poly[i - 2], ay = poly[i - 1]
            let bx = poly[i], by = poly[i + 1]
            let vx = bx - ax, vy = by - ay
            let wx = px - ax, wy = py - ay
            let len2 = vx * vx + vy * vy
            var t: Float = len2 != 0 ? (wx * vx + wy * vy) / len2 : 0
            t = max(0, min(1, t))
            let d = dist(px, py, ax + vx * t, ay + vy * t)
            if d < best { best = d }
            i += 2
        }
        return best
    }

    /// 重采样为等距点，减少采样频率差异带来的误差
    static func resample(_ pts: [Float], step: Float) -> [Float] {
        let n = pts.count / 2
        if n < 2 { return pts }
        var out: [Float] = [pts[0], pts[1]]
        var carry: Float = 0
        var ax = pts[0], ay = pts[1]
        var idx = 1
        while idx < n {
            let bx = pts[idx * 2], by = pts[idx * 2 + 1]
            var seg = dist(ax, ay, bx, by)
            if seg == 0 { idx += 1; continue }
            while carry + seg >= step {
                let t = (step - carry) / seg
                let nx = ax + (bx - ax) * t
                let ny = ay + (by - ay) * t
                out.append(nx)
                out.append(ny)
                ax = nx
                ay = ny
                seg = dist(ax, ay, bx, by)
                carry = 0
            }
            carry += seg
            ax = bx
            ay = by
            idx += 1
        }
        let lastX = pts[(n - 1) * 2], lastY = pts[(n - 1) * 2 + 1]
        let outN = out.count / 2
        if dist(out[(outN - 1) * 2], out[(outN - 1) * 2 + 1], lastX, lastY) > step * 0.4 {
            out.append(lastX)
            out.append(lastY)
        }
        return out
    }

    private static func clamp01(_ v: Float) -> Float { max(0, min(1, v)) }

    /// - Parameters:
    ///   - userPts: 用户笔画，扁平化 [x0,y0,x1,y1,...]，画布像素坐标
    ///   - targetPts: 目标中线，同坐标系
    ///   - tolerance: 允许偏差像素，默认 26（与另外两端一致）
    static func scoreStroke(userPts: [Float]?, targetPts: [Float]?, tolerance: Float = 26) -> Result {
        guard let userPts, userPts.count >= 4 else { return Result(score: 0, reason: "empty") }
        guard let targetPts, targetPts.count >= 4 else { return Result(score: 0, reason: "no-target") }

        let step = max(3, tolerance * 0.35)
        let user = resample(userPts, step: step)
        let target = resample(targetPts, step: step)

        let startD = dist(user[0], user[1], target[0], target[1])
        let endD = dist(user[user.count - 2], user[user.count - 1],
                        target[target.count - 2], target[target.count - 1])
        let startScore = clamp01(1 - startD / (tolerance * 2.2))
        let endScore = clamp01(1 - endD / (tolerance * 2.2))

        var sum: Float = 0
        var i = 0
        while i < user.count {
            sum += pointToPolyline(user[i], user[i + 1], target)
            i += 2
        }
        let avg = sum / Float(user.count / 2)
        let coverScore = clamp01(1 - avg / tolerance)

        var sum2: Float = 0
        i = 0
        while i < target.count {
            sum2 += pointToPolyline(target[i], target[i + 1], user)
            i += 2
        }
        let reachScore = clamp01(1 - sum2 / Float(target.count / 2) / tolerance)

        let lu = polylineLength(user)
        let lt = polylineLength(target)
        let ratio = lt > 0 ? lu / lt : 0
        let lengthScore: Float
        if ratio >= 0.75 && ratio <= 1.45 {
            lengthScore = 1
        } else {
            lengthScore = clamp01(1 - abs(1 - ratio) / 0.85)
        }

        let raw = startScore * wStart + endScore * wEnd + coverScore * wCover
            + reachScore * wReach + lengthScore * wLength
        let score = Int((clamp01(raw) * 100).rounded())

        let reason: String
        if startScore < 0.45 {
            reason = "start"
        } else if coverScore < 0.45 {
            reason = "off"
        } else if reachScore < 0.45 {
            reason = "short"
        } else {
            reason = "ok"
        }
        return Result(score: score, reason: reason)
    }

    /// 整字评分：各笔平均，但有一笔特别差会扣分，避免「乱画也高分」
    static func scoreChar(_ scores: [Int]) -> CharResult {
        if scores.isEmpty { return CharResult(score: 0, stars: 0) }
        let total = scores.reduce(0, +)
        let minScore = scores.min() ?? 0
        let avg = Float(total) / Float(scores.count)
        let score = Int((avg * 0.85 + Float(minScore) * 0.15).rounded())
        return CharResult(score: score, stars: starsOf(score))
    }

    static func starsOf(_ score: Int) -> Int {
        if score >= 85 { return 3 }
        if score >= 65 { return 2 }
        if score >= 40 { return 1 }
        return 0
    }
}
