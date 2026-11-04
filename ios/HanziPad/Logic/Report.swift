import Foundation

/// 学习周报：把 `Progress.days` 里逐日攒下的数据变成家长看得懂的报告。
///
/// ## 为什么值得单独做一页
///
/// 逐日统计从第一个版本起就在记录 `{learned, answers, correct}`，但它只被
/// 「活跃天数」一个徽章间接用过一次——数据一直在攒，从来没被读过。
/// 对家长来说，「今天学了几个字」在首页能看到，「这一周怎么样」看不到，
/// 而那才是他们真正关心的粒度。
///
/// ## 为什么是「最近 7 天」而不是「本周一到周日」
///
/// 日历周有个很难受的副作用：周一早上打开，整周几乎全是空的，看起来像
/// 「什么都没做」。滚动 7 天永远是「最近这一周」，任何时候打开都有意义。
/// 代价是同一个字可能被算进两周，但周报是给家长看趋势的，不是做账。
///
/// ## 数据可能缺失
///
/// 用户可能中间几天没用，字典里就没有那天的键——**不能当成 0 分**，要区分
/// 「那天没学」和「那天学了但没答对」。所以缺的天填 `active: false`，
/// 而不是 `accuracy: 0`。
///
/// 与小程序 `utils/report.js` 逐条对应，口径必须三端一致。
enum Report {

    /// 一周按周一→周日排，和家长的习惯一致（而不是周日打头）
    static let weekdays = ["一", "二", "三", "四", "五", "六", "日"]

    /// 一天的原始统计。独立于 `Progress.DayStat`，是为了让这层纯函数
    /// 不依赖 `@MainActor` 的 Progress，测试里能直接造数据。
    struct DayStat: Equatable {
        var learned: Int = 0
        var answers: Int = 0
        var correct: Int = 0

        init(learned: Int = 0, answers: Int = 0, correct: Int = 0) {
            self.learned = learned
            self.answers = answers
            self.correct = correct
        }
    }

    /// 周报里的一天。
    ///
    /// `accuracy` 是 `Int?` 而不是 `Int`：一题没答时算不出正确率，记成 0%
    /// 会让家长以为孩子全错了。这个可空类型本身就是一条规则。
    struct Day: Equatable {
        let key: String
        let daysAgo: Int
        let weekday: String
        let date: String
        let learned: Int
        let answers: Int
        let correct: Int
        let accuracy: Int?
        let active: Bool
        /// 柱状图高度 0...1，由 `withRatios` 填
        var ratio: Double = 0
    }

    struct Summary: Equatable {
        let learned: Int
        let answers: Int
        let correct: Int
        let accuracy: Int?
        let activeDays: Int
        let span: Int
        /// 学习量最多的一天；整周没学时是 nil
        let best: Day?
        /// 完全没动过的一周要能被识别出来，好给一句鼓励而不是一张空表
        let empty: Bool
    }

    enum Tone: String {
        case good
        case plain
        case tip
    }

    struct Advice: Equatable {
        let tone: Tone
        let text: String
    }

    struct Result {
        let week: [Day]
        let sum: Summary
        let headline: String
        let advice: [Advice]
    }

    // MARK: - 取数

    /// 取最近 N 天的逐日数据，从最早到最近，最后一项是今天。
    ///
    /// `daysAgo` 用「几天前」的正数（0 = 今天），不用负偏移是为了避开 -0
    /// 这类边界（JS 里 `-0 !== 0`，Swift 里虽然没这个坑，但口径保持一致）。
    static func recentDays(_ daysStats: [String: DayStat]?,
                           span: Int = 7,
                           now: Date = Date()) -> [Day] {
        let n = span > 0 ? span : 7
        var out: [Day] = []
        for i in stride(from: n - 1, through: 0, by: -1) {
            let date = DayUtil.dateOfOffset(-i, from: now)
            let key = DayUtil.todayKey(date)
            let rec = daysStats?[key]
            let learned = rec?.learned ?? 0
            let answers = rec?.answers ?? 0
            let correct = rec?.correct ?? 0
            out.append(Day(
                key: key,
                daysAgo: i,
                // DayUtil 的 weekdayCN 是「周四」这种给界面用的写法，
                // 柱状图下面只要一个字，去掉前缀
                weekday: DayUtil.weekdayCN(date).replacingOccurrences(of: "周", with: ""),
                date: DayUtil.dateLabel(date),
                learned: learned,
                answers: answers,
                correct: correct,
                // 一题没答时不算准确率——记成 0% 会让家长以为全错
                accuracy: answers > 0 ? percent(correct, of: answers) : nil,
                active: learned > 0 || answers > 0
            ))
        }
        return out
    }

    /// 正确率：四舍五入到整数百分比
    private static func percent(_ correct: Int, of answers: Int) -> Int {
        guard answers > 0 else { return 0 }
        return Int((Double(correct) / Double(answers) * 100).rounded())
    }

    // MARK: - 汇总

    static func summarize(_ week: [Day]) -> Summary {
        var learned = 0
        var answers = 0
        var correct = 0
        var activeDays = 0
        var best: Day?

        for d in week {
            learned += d.learned
            answers += d.answers
            correct += d.correct
            if d.active { activeDays += 1 }
            // 「最好的一天」按学习量算，答题量作为平手时的次序。
            // 平手且都相等时保留更早的那天（和 JS 的 `>` 语义一致）。
            if d.active {
                if best == nil
                    || d.learned > best!.learned
                    || (d.learned == best!.learned && d.answers > best!.answers) {
                    best = d
                }
            }
        }

        return Summary(
            learned: learned,
            answers: answers,
            correct: correct,
            // 整周没答题就没有准确率，不是 0%
            accuracy: answers > 0 ? percent(correct, of: answers) : nil,
            activeDays: activeDays,
            span: week.count,
            best: best,
            empty: learned == 0 && answers == 0
        )
    }

    // MARK: - 文案

    /// 给孩子看的一句话。
    ///
    /// 有意写得短、可读完：周报的读者是家长，但这句是念给孩子听的。
    /// 不用「正确率 87%」这种数字，孩子对它没有感觉。
    static func headline(_ sum: Summary) -> String {
        if sum.empty { return "这周还没开始，今天写一个字就开张啦" }
        if sum.activeDays >= 7 { return "整整七天没断过，太厉害了" }
        if sum.activeDays >= 5 { return "这周来了 \(sum.activeDays) 天，很稳" }
        if sum.activeDays >= 3 { return "这周来了 \(sum.activeDays) 天，继续保持" }
        return "这周来了 \(sum.activeDays) 天，明天再来一次就更好"
    }

    /// 给家长的分析。比 headline 具体，可以提数字。
    static func advice(_ sum: Summary, week: [Day]) -> [Advice] {
        var out: [Advice] = []

        if sum.empty {
            // 空周只说一句：一次给四条「去学习」的建议只会让人关掉页面
            out.append(Advice(tone: .plain,
                              text: "这一周还没有学习记录。每天 5 分钟，先从「每日任务」开始。"))
            return out
        }

        if sum.learned > 0 {
            // 平均每天保留一位小数；整数时不带 .0（和小程序的 JS 输出一致）
            let avg = sum.activeDays > 0
                ? "，平均每天 \(number(Double(sum.learned) / Double(sum.activeDays))) 个"
                : ""
            out.append(Advice(tone: .good, text: "这周认识了 \(sum.learned) 个字\(avg)。"))
        }

        if let acc = sum.accuracy {
            if acc >= 85 {
                out.append(Advice(tone: .good, text: "答题正确率 \(acc)%，很扎实。"))
            } else if acc >= 65 {
                out.append(Advice(tone: .plain, text: "答题正确率 \(acc)%，还有几个字没记牢。"))
            } else {
                out.append(Advice(tone: .tip,
                                  text: "答题正确率 \(acc)%，建议放慢速度，多复习几次再往下学。"))
            }
        }

        // 中断过就说中断——这是家长最需要知道的，不然一周下来会以为孩子天天在学
        let missing = week.filter { !$0.active }
        if !missing.isEmpty && missing.count < week.count {
            out.append(Advice(tone: .plain,
                              text: "有 \(missing.count) 天没有学习记录。每天固定一个时间学，比一次学很久有用。"))
        }

        // 学习量和正确率都在高位时，提醒往下走
        if sum.learned >= 35, let acc = sum.accuracy, acc >= 85 {
            out.append(Advice(tone: .good,
                              text: "进度和正确率都不错，可以试试「识字量测试」看看现在到了多少。"))
        }

        return out
    }

    /// 和 JS `Math.round(v * 10) / 10` 等价，且整数不带小数点。
    private static func number(_ v: Double) -> String {
        let rounded = (v * 10).rounded() / 10
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(rounded)
    }

    // MARK: - 柱状图

    /// 把一周的数值缩到 0~1，给柱状图用。
    ///
    /// 按学习量和答题量的较大者归一：只看学习量的话，「今天复习了 30 道题」
    /// 会画成一根空柱子。
    static func withRatios(_ week: [Day]) -> [Day] {
        var maxValue = 0
        for d in week {
            maxValue = max(maxValue, d.learned, reviewWeight(d.answers))
        }
        return week.map { d in
            let v = max(d.learned, reviewWeight(d.answers))
            // 有活动但数值很小时给个最小高度，否则柱子是 0 像素看不见
            let ratio = maxValue == 0 ? 0 : max(Double(v) / Double(maxValue), d.active ? 0.08 : 0)
            var copy = d
            copy.ratio = (ratio * 100).rounded() / 100
            return copy
        }
    }

    /// 答题量折算成「学习量」：4 道题约等于 1 个字的分量
    private static func reviewWeight(_ answers: Int) -> Int {
        answers <= 0 ? 0 : Int((Double(answers) / 4).rounded(.up))
    }

    // MARK: - 一次算好

    static func build(_ daysStats: [String: DayStat]?,
                      span: Int = 7,
                      now: Date = Date()) -> Result {
        let week = withRatios(recentDays(daysStats, span: span, now: now))
        let sum = summarize(week)
        return Result(
            week: week,
            sum: sum,
            headline: headline(sum),
            advice: advice(sum, week: week)
        )
    }
}
