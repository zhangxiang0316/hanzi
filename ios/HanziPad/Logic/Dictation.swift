import Foundation

/// 听写：念一个词（或字），孩子凭记忆写出来。
///
/// 与描红的区别只有一条——**不显示底字**。判分、笔顺、星级全部复用，
/// 因为「写对没写对」的标准和描红完全一样，没有理由另做一套。
///
/// 分级：
/// - `.easy` 念词 + 显示底字（等于描红，只是入口不同，给最没把握的孩子）
/// - `.normal` 念词，不显示底字（默认）
/// - `.hard` 只念字，不显示底字，也不念组词
///
/// 之所以保留 easy 档：听写最难的是「根本想不起来这个字长什么样」。
/// 一上来就完全不给提示，一部分孩子会直接卡死在第一题，一题都写不出，
/// 从此不愿意再点这个入口。给一个可以从描红过渡的档位，
/// 比逼他们直接跳到听写更可能坚持下去。
enum DictationLevel: String, CaseIterable, Sendable {
    case easy, normal, hard

    var title: String {
        switch self {
        case .easy: return "看着写"
        case .normal: return "听词写"
        case .hard: return "只听字"
        }
    }

    var desc: String {
        switch self {
        case .easy: return "念出词语，田字格里还有淡色的字"
        case .normal: return "念出词语，不显示淡色的字"
        case .hard: return "只念这一个字，不提示词语"
        }
    }

    /// 是否显示底字
    var showsGhost: Bool { self == .easy }

    /// 朗读什么
    func promptText(ch: String, word: String?) -> String {
        switch self {
        case .easy, .normal:
            // 有词念词，没词就念字——「天空」比单念「天」更容易想起是哪个字
            return word ?? ch
        case .hard:
            return ch
        }
    }
}

/// 听写会话：决定听写哪些字、念什么，并记录结果。
@MainActor
final class DictationPlan: ObservableObject {
    struct Item {
        let ch: String
        /// 用来朗读/提示的词语；可能为 nil（这个字没有组词）
        let word: String?
    }

    let level: DictationLevel
    private(set) var items: [Item]
    /// 当前第几个
    @Published private(set) var index = 0
    /// 每个字的得分（写完才追加）
    @Published private(set) var scores: [String: Int] = [:]

    var count: Int { items.count }
    var current: Item? { index >= 0 && index < items.count ? items[index] : nil }
    var isDone: Bool { index >= items.count }

    init(level: DictationLevel, items: [Item]) {
        self.level = level
        self.items = items
    }

    func record(ch: String, score: Int) {
        scores[ch] = score
    }

    /// 进下一个（或结束）
    func advance() {
        index += 1
    }

    /// 平均分；没写完返回 nil
    var averageScore: Int? {
        guard !scores.isEmpty else { return nil }
        let sum = scores.values.reduce(0, +)
        return Int((Double(sum) / Double(scores.count)).rounded())
    }

    var stars: Int {
        guard let avg = averageScore else { return 0 }
        return Trace.starsOf(avg)
    }
}

/// 选听写的字。
///
/// 优先级：本册「会写」的字 → 已经学过的字 → 本册全部字。
/// 「会写」这个区分（`isWriteChar`）是教材自带的，之前三端都定义了却没用；
/// 听写场景下它正好合适——只认不写的字（髓、嚼、蟹）要求孩子默写出来没有道理。
enum DictationSource {
    @MainActor
    static func pick(book: String, level: DictationLevel, limit: Int) -> [DictationPlan.Item] {
        let repo = Repo.shared
        var pool = repo.bookChars(book).filter { repo.isWriteChar($0) }
        if pool.count < 4 {
            // 本册会写的字太少，退回本册全部字
            pool = repo.bookChars(book)
        }
        if pool.isEmpty { pool = repo.allCharsWithStrokes() }

        // 固定按教材顺序取前 N 个，而不是随机。
        // 听写是「今天学完这几课，默一遍」的场景，顺序对得上课文才有意义；
        // 随机打乱会让家长没法对照课本。
        let picked = Array(pool.prefix(max(1, limit)))
        return picked.map { ch in
            let meta = repo.meta(ch)
            // easy 档用第一个组词；hard 档不念词
            let word: String? = level == .hard ? nil : meta?.words.first?.word
            return DictationPlan.Item(ch: ch, word: word)
        }
    }
}
