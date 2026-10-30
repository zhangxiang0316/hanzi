import Foundation

/// 数据仓库，与 Android `data/Repo.kt` 的 API 一一对应。
///
/// 数据是只读的静态 JSON，全部打进 bundle：无网络、无后端。
/// 三个文件加起来 2.9 MB，直接从 bundle 同步加载——比异步加载简单，
/// 也不会出现「界面先渲染出空列表再补数据」的闪动。
/// 标记 `@MainActor` 而不是用锁保护：这份数据是只读的，唯一的可变状态是
/// 几处解码缓存，而所有访问都来自 SwiftUI 视图（本来就在主线程）。
/// 用 actor 隔离能从构造上杜绝数据竞争，比手写 NSLock 更难出错。
@MainActor
final class Repo {
    static let shared = Repo()

    /// 数据来源。生产用 bundle，测试用目录路径。
    ///
    /// 抽这一层是为了能在命令行工具和单测里加载同一份数据——
    /// `Bundle.main` 在非 App 进程里拿不到 resource，直接依赖它就没法离线验证。
    enum Source {
        case bundle
        case directory(URL)
    }

    private(set) var books: [Book] = []
    private(set) var edition: String = ""

    private var bookMap: [String: Book] = [:]
    private var lessonMap: [String: Lesson] = [:]
    private var metaMap: [String: CharMeta] = [:]
    /// 保持 meta.json 的原始顺序（按教材出现顺序），用于「全部字」列表
    private(set) var charOrder: [String] = []
    private var rawStrokes: [String: String] = [:]

    private var bookCharsCache: [String: [String]] = [:]
    private var strokeCache: [String: StrokeCodec.CharStrokes] = [:]

    init(source: Source = .bundle) {
        load(source: source)
    }

    // MARK: - 加载

    private func url(_ name: String, from source: Source) -> URL? {
        switch source {
        case .bundle:
            return Bundle.main.url(forResource: name, withExtension: "json")
        case .directory(let dir):
            return dir.appendingPathComponent(name + ".json")
        }
    }

    private func load(source: Source) {
        guard let catalogURL = url("catalog", from: source),
              let metaURL = url("meta", from: source),
              let strokesURL = url("strokes", from: source)
        else {
            assertionFailure("数据文件缺失：catalog/meta/strokes 必须存在")
            return
        }

        let decoder = JSONDecoder()

        if let data = try? Data(contentsOf: catalogURL),
           let cat = try? decoder.decode(Catalog.self, from: data) {
            books = cat.books
            edition = cat.edition
            for b in cat.books { bookMap[b.id] = b }
            lessonMap = cat.lessons
        }

        if let data = try? Data(contentsOf: metaURL),
           let map = try? decoder.decode([String: CharMeta].self, from: data) {
            metaMap = map
            // Dictionary 无序，但 meta.json 里字的顺序是有意义的（教材顺序）。
            // 重新按 raw JSON 的键序读一遍：JSONSerialization 的字典同样无序，
            // 所以这里用 .sorted() 兜底，真正的教材顺序由 bookChars 提供。
            charOrder = map.keys.sorted()
        }

        if let data = try? Data(contentsOf: strokesURL),
           let map = try? decoder.decode([String: String].self, from: data) {
            rawStrokes = map
        }
    }

    // MARK: - 基础查询

    func book(_ id: String) -> Book? { bookMap[id] }
    func defaultBook() -> String { books.first?.id ?? "1a" }
    func lesson(_ id: String?) -> Lesson? {
        guard let id else { return nil }
        return lessonMap[id]
    }
    func meta(_ ch: String) -> CharMeta? { metaMap[ch] }
    func hasChar(_ ch: String) -> Bool { metaMap[ch] != nil }
    var charCount: Int { metaMap.count }

    func lessonTitle(_ id: String?) -> String {
        guard let id else { return "" }
        return lessonMap[id]?.title ?? ""
    }

    func lessonLabel(_ id: String?) -> String {
        guard let id, let l = lessonMap[id] else { return "" }
        let prefix = bookMap[l.book].map { $0.short + " · " } ?? ""
        return prefix + "第" + String(l.no) + "课 " + l.title
    }

    // MARK: - 教材顺序

    /// 按「册 → 单元 → 课 → 生字」的教材顺序返回某册全部生字（去重）
    func bookChars(_ bookId: String) -> [String] {
        if let c = bookCharsCache[bookId] { return c }
        guard let book = bookMap[bookId] else { return [] }
        var seen = Set<String>()
        var out: [String] = []
        for lid in book.lessons {
            guard let l = lessonMap[lid] else { continue }
            for ch in l.chars where seen.insert(ch).inserted {
                out.append(ch)
            }
        }
        bookCharsCache[bookId] = out
        return out
    }

    func lessonChars(_ lessonId: String?) -> [String] {
        guard let lessonId else { return [] }
        return lessonMap[lessonId]?.chars ?? []
    }

    // MARK: - 读音

    /// 取本课语境下的读音；多音字按教材标注
    func readingFor(_ ch: String, lessonId: String?) -> String {
        guard let m = metaMap[ch] else { return "" }
        if let rd = m.rd, let lessonId {
            for r in rd where r.l == lessonId { return r.p }
        }
        return m.py
    }

    /// 一个字所有可能读音（用于排除同音干扰项）
    func readingsOf(_ ch: String) -> [String] {
        guard let m = metaMap[ch] else { return [] }
        guard let rd = m.rd else { return [m.py] }
        var seen = Set<String>()
        var out: [String] = []
        for r in rd where seen.insert(r.p).inserted { out.append(r.p) }
        return out
    }

    func readingDetails(_ ch: String) -> [Reading] {
        guard let m = metaMap[ch] else { return [] }
        return m.rd ?? [Reading(p: m.py, l: "")]
    }

    func isWriteChar(_ ch: String) -> Bool {
        guard let m = metaMap[ch] else { return false }
        return !m.x.isEmpty
    }

    // MARK: - 前后导航

    func nextInLesson(_ lessonId: String?, _ ch: String) -> String {
        let list = lessonChars(lessonId)
        guard let i = list.firstIndex(of: ch), i < list.count - 1 else { return "" }
        return list[i + 1]
    }

    func prevInLesson(_ lessonId: String?, _ ch: String) -> String {
        let list = lessonChars(lessonId)
        guard let i = list.firstIndex(of: ch), i > 0 else { return "" }
        return list[i - 1]
    }

    func nextInBook(_ bookId: String, _ ch: String) -> String {
        let list = bookChars(bookId)
        guard let i = list.firstIndex(of: ch), i < list.count - 1 else { return "" }
        return list[i + 1]
    }

    func prevInBook(_ bookId: String, _ ch: String) -> String {
        let list = bookChars(bookId)
        guard let i = list.firstIndex(of: ch), i > 0 else { return "" }
        return list[i - 1]
    }

    /// 找到某字在教材中的首次出现课文
    func lessonOfChar(_ ch: String) -> String { metaMap[ch]?.l ?? "" }

    func bookStat(_ bookId: String) -> BookStat {
        bookMap[bookId]?.stat ?? BookStat(chars: 0, write: 0, lessons: 0, units: 0)
    }

    // MARK: - 笔顺

    /// 取某字的笔顺（解码并缓存）；数据缺失返回 nil
    func strokes(_ ch: String) -> StrokeCodec.CharStrokes? {
        if let c = strokeCache[ch] { return c }
        guard let raw = rawStrokes[ch] else { return nil }
        guard let decoded = try? StrokeCodec.decode(base64: raw) else { return nil }
        strokeCache[ch] = decoded
        return decoded
    }

    func strokeCount(_ ch: String) -> Int { strokes(ch)?.count ?? 0 }

    var strokeCharCount: Int { rawStrokes.count }

    // MARK: - 全部字（搜索用，M5 的搜索页会用到）

    /// 按册次分组返回所有字，顺序遵循教材
    func allCharsInOrder() -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        for b in books {
            for ch in bookChars(b.id) where seen.insert(ch).inserted {
                out.append(ch)
            }
        }
        return out
    }
}
