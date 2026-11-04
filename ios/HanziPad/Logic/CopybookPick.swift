import Foundation

/// 字帖选字：决定「导出哪些字」的纯逻辑。
///
/// ## 为什么这件事不能只靠界面
///
/// 小程序端笔画数据在分包里，主包取不到，所以「按课时选 20 个字导出」在
/// 数据上可能只成立一半——没描过的字没有笔顺，画出来是空田字格。那边要
/// 标出「哪些字能导、哪些要先去描一遍」。
///
/// **iOS 不适用这个限制**：笔画数据整包打在 app 里，任何字都能画出来。
/// 所以这里**不做 `available` 过滤**，也不返回 missing——不是偷懒，是
/// iOS 侧没有这个约束，凭空加一层置灰只会让用户以为有字导不了。
///
/// ## 优先级
///
/// 一个字的来源可能同时命中多条（既是错题、星级又低），展示时按
/// 「错题 > 笔画弱 > 课时 > 低分」排——错题最该练。首次出现的先后顺序则
/// 按候选拼进来的顺序，和小程序逐行一致。
///
/// 与小程序 `utils/copybook-pick.js` 对应。
enum CopybookPick {

    /// 候选字的来源。rawValue 直接用作排序键，顺序就是展示优先级。
    enum Source: String, CaseIterable {
        case wrong
        case weak
        case lesson
        case stars

        /// 来源的展示文案
        var text: String {
            switch self {
            case .wrong: return "错题"
            case .weak: return "笔画弱"
            case .lesson: return "课时"
            case .stars: return "低分"
            }
        }

        /// 在标签串里的先后（`allCases` 顺序即优先级）
        var rank: Int { Source.allCases.firstIndex(of: self) ?? Source.allCases.count }
    }

    /// 一条原始候选（一个字可以出现多次，来源不同）
    struct Candidate: Equatable {
        let ch: String
        let from: Source

        init(_ ch: String, _ from: Source) {
            self.ch = ch
            self.from = from
        }
    }

    /// 合并后的字：去重并收集全部来源
    struct Merged: Equatable {
        let ch: String
        let froms: [Source]
    }

    /// 给界面用的最终条目：来源已排序、转成中文
    struct Item: Equatable {
        let ch: String
        let froms: [Source]
        let fromText: String
    }

    /// 一条描红成绩。只取选字需要的星级，不把 `Progress.WriteRecord`
    /// 整个搬进来——这层要保持不依赖 `@MainActor` 的 Progress。
    struct Record: Equatable {
        let ch: String
        let stars: Int

        init(ch: String, stars: Int) {
            self.ch = ch
            self.stars = stars
        }
    }

    struct BuildResult {
        let items: [Item]

        /// iOS 上每个字都能画，所以「可导」就是全部条目。
        /// 保留这两个名字是为了和三端的口径对齐，页面上的计数直接用它。
        var readyCount: Int { items.count }
        var missingCount: Int { 0 }
    }

    // MARK: - 合并与装饰

    /// 一组候选字去重并合并来源标签，保持首次出现的顺序。
    static func merge(_ items: [Candidate]) -> [Merged] {
        var order: [String] = []
        var map: [String: [Source]] = [:]
        for it in items {
            guard !it.ch.isEmpty else { continue }
            if map[it.ch] == nil {
                map[it.ch] = []
                order.append(it.ch)
            }
            // 同一个来源重复命中只记一次
            if !(map[it.ch]?.contains(it.from) ?? false) {
                map[it.ch]?.append(it.from)
            }
        }
        return order.map { Merged(ch: $0, froms: map[$0] ?? []) }
    }

    /// 把来源标签排好序、转成中文，给界面用。
    static func decorate(_ items: [Merged]) -> [Item] {
        items.map { it in
            let froms = it.froms.sorted { $0.rank < $1.rank }
            return Item(
                ch: it.ch,
                froms: froms,
                fromText: froms.map(\.text).joined(separator: " · ")
            )
        }
    }

    // MARK: - 四条来源

    /// 按课时取字（教材顺序）。
    static func fromLesson(_ lessonChars: [String]) -> [Candidate] {
        lessonChars.map { Candidate($0, .lesson) }
    }

    /// 按星档取字：只要这一档。
    static func fromStars(_ records: [Record], stars: Int) -> [Candidate] {
        records.filter { $0.stars == stars }.map { Candidate($0.ch, .stars) }
    }

    /// 错题本里的字。
    static func fromWrong(_ wrongChars: [String]) -> [Candidate] {
        wrongChars.map { Candidate($0, .wrong) }
    }

    /// 笔画薄弱点里的字（失败过 2 次以上）。
    static func fromWeak(_ weakChars: [String]) -> [Candidate] {
        weakChars.map { Candidate($0, .weak) }
    }

    // MARK: - 一次算好

    /// 一次算好整个选字界面要的数据。
    ///
    /// - Parameters:
    ///   - stars: 要哪一档星（0~3），nil = 不按星级选
    static func build(lessonChars: [String] = [],
                      records: [Record] = [],
                      wrongChars: [String] = [],
                      weakChars: [String] = [],
                      stars: Int? = nil) -> BuildResult {
        let raw = fromWrong(wrongChars)
            + fromWeak(weakChars)
            + (stars.map { fromStars(records, stars: $0) } ?? [])
            + fromLesson(lessonChars)
        return BuildResult(items: decorate(merge(raw)))
    }
}
