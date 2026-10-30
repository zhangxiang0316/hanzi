import Foundation

/// Leitner 间隔复习。
///
/// 与 Android `logic/Srs.kt`、小程序 `utils/srs.js` 逐行对应：
/// 箱子 0-7 对应复习间隔 0/1/2/4/7/15/30/60 天。
/// 保持纯函数，方便直接用单测对比三端行为。
enum Srs {
    static let intervals = [0, 1, 2, 4, 7, 15, 30, 60]
    static var maxBox: Int { intervals.count - 1 }
    static let masteredBox = 5

    /// 一个字的学习状态
    struct Entry: Equatable {
        var box: Int = 0
        var seen: Int = 0
        var ok: Int = 0
        var miss: Int = 0
        var due: Int = 0
        var last: Int = 0
        var known: Bool = false
    }

    static func isDue(_ entry: Entry?, today: Int) -> Bool {
        guard let e = entry else { return false }
        return e.due <= today
    }

    static func isMastered(_ entry: Entry?) -> Bool {
        guard let e = entry else { return false }
        return e.box >= masteredBox
    }

    static func isLearning(_ entry: Entry?) -> Bool {
        guard let e = entry else { return false }
        return e.box >= 1
    }

    /// 第一次学习：进入箱子 1，明天复习。重复调用不会降级
    static func learn(_ entry: Entry?, today: Int) -> Entry {
        if let e = entry, e.box >= 1 { return e }
        var e = entry ?? Entry()
        e.box = 1
        e.due = today + intervals[1]
        e.last = today
        return e
    }

    /// 答题评分：答对升一箱，答错回退（已较熟的字退到 1，生字退到 0）
    static func grade(_ entry: Entry?, correct: Bool, today: Int) -> Entry {
        var e = entry ?? Entry()
        let box: Int
        if correct {
            box = min(maxBox, e.box + 1)
        } else {
            box = e.box >= 3 ? 1 : 0
        }
        e.seen += 1
        if correct { e.ok += 1 } else { e.miss += 1 }
        e.box = box
        e.due = today + intervals[box]
        e.last = today
        return e
    }

    /// 直接标记「已认识」（用于快速跳过已掌握的字）
    static func markKnown(_ entry: Entry?, today: Int) -> Entry {
        var e = entry ?? Entry()
        let box = max(e.box, 4)
        e.box = box
        e.due = today + intervals[box]
        e.last = today
        e.known = true
        return e
    }

    static func stageOf(_ entry: Entry?) -> String {
        guard let e = entry else { return "new" }
        if e.box >= masteredBox { return "mastered" }
        if e.box >= 1 { return "learning" }
        return "weak"
    }

    static let stageLabel: [String: String] = [
        "new": "未学",
        "weak": "待巩固",
        "learning": "学习中",
        "mastered": "已掌握",
    ]
}
