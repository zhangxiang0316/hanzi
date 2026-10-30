import Foundation

/// 日期工具：以「本地自然日」为单位的编号，与 Android `DayUtil.kt` / 小程序 `utils/day.js` 一致。
///
/// dayNumber 用 UTC 时间加时区偏移后除以一天，得到的是「本地自然日」的整数编号。
/// 这个编号直接用作 SRS 的 due 值，跨时区旅行时不会跳天。
enum DayUtil {
    static let dayMs: Int = 86_400_000

    static func dayNumber(_ date: Date = Date()) -> Int {
        let offset = TimeZone.current.secondsFromGMT(for: date)
        return Int((date.timeIntervalSince1970 * 1000 + Double(offset * 1000)) / Double(dayMs))
    }

    private static func pad(_ n: Int) -> String {
        n < 10 ? "0\(n)" : "\(n)"
    }

    private static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    /// "2026-10-30"
    static func todayKey(_ date: Date = Date()) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(c.year!)-\(pad(c.month!))-\(pad(c.day!))"
    }

    static func yesterdayKey(_ date: Date = Date()) -> String {
        todayKey(date.addingTimeInterval(-Double(dayMs) / 1000))
    }

    /// "周四"
    static func weekdayCN(_ date: Date = Date()) -> String {
        let names = ["日", "一", "二", "三", "四", "五", "六"]
        // Calendar 的 weekday 是 1=周日 … 7=周六，与 JS getDay() 的 0-6 差 1
        let w = calendar.component(.weekday, from: date)
        return "周" + names[w - 1]
    }

    /// "10月30日"
    static func dateLabel(_ date: Date = Date()) -> String {
        let c = calendar.dateComponents([.month, .day], from: date)
        return "\(c.month!)月\(c.day!)日"
    }

    static func greeting(_ date: Date = Date()) -> String {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 0...5: return "夜深了"
        case 6...10: return "早上好"
        case 11...13: return "中午好"
        case 14...17: return "下午好"
        default: return "晚上好"
        }
    }

    /// 相对今天偏移若干天的日期键
    static func dayKeyOf(_ offsetDays: Int, from date: Date = Date()) -> String {
        let d = calendar.date(byAdding: .day, value: offsetDays, to: date) ?? date
        return todayKey(d)
    }

    static func dateOfOffset(_ offsetDays: Int, from date: Date = Date()) -> Date {
        calendar.date(byAdding: .day, value: offsetDays, to: date) ?? date
    }
}
