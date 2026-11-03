import Foundation

/// 多孩子档案。
///
/// 一间屋里两个孩子共用一个 iPad 学字是常态。之前所有数据挤在一套文件里，
/// 弟弟写几个字就把哥哥的进度、错题本、描红星级全搅在一起，
/// 连「今天新学几个字」都算不对。
///
/// ## 默认档案的 id 是空串
///
/// 这一点很关键。老用户的数据存在 `progress.json`，如果给默认档案编个
/// `main` 之类的 id，文件就变成 `p/main/progress.json`，升级上来进度全丢。
/// 空串让默认档案的文件**和以前完全一样**，后建的档案才进子目录。
///
/// ## 上限 4 个
///
/// 再多就不是家庭共用而是班级共用了——那时该做的是账号体系，不是本地档案。
///
/// 与小程序 `utils/profile.js`、Android `ProfileManager.kt` 行为一致。
@MainActor
final class ProfileManager {

    struct Profile: Equatable, Identifiable {
        let id: String
        var name: String
    }

    static let max = 4
    static let defaultName = "我"
    private static let key = "profiles"

    private let store: Store
    private(set) var list: [Profile] = []
    private(set) var activeId: String = ""
    private var seq: Int = 2

    init(store: Store) {
        self.store = store
        load()
        // 启动时把命名空间对上，之后 Progress 读的就是当前档案的数据
        store.setProfile(activeId)
    }

    var count: Int { list.count }
    var canAdd: Bool { list.count < Self.max }

    var active: Profile {
        list.first { $0.id == activeId } ?? list[0]
    }

    /// 切换档案。返回 true 表示真的切了。
    ///
    /// 调用方必须紧接着重建/重载 Progress —— 存储的命名空间变了，
    /// 但内存里那份还是上一个孩子的。
    @discardableResult
    func setActive(_ id: String) -> Bool {
        if id == activeId { return false }
        guard list.contains(where: { $0.id == id }) else { return false }
        activeId = id
        persist()
        return true
    }

    /// 新建档案。名字去首尾空格、截断到 8 字，空名字给默认名。
    @discardableResult
    func add(_ name: String?) -> Profile? {
        guard canAdd else { return nil }
        let trimmed = String((name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(8))
        let id = "p\(seq)"
        seq += 1
        let p = Profile(id: id, name: trimmed.isEmpty ? "孩子\(list.count + 1)" : trimmed)
        list.append(p)
        persist()
        return p
    }

    /// 改名。默认档案也能改——「我」只是占位。
    @discardableResult
    func rename(_ id: String, _ name: String?) -> Bool {
        guard let i = list.firstIndex(where: { $0.id == id }) else { return false }
        let trimmed = String((name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(8))
        guard !trimmed.isEmpty else { return false }
        list[i].name = trimmed
        persist()
        return true
    }

    /// 删除档案（连同它的全部数据）。
    ///
    /// 不允许删掉最后一个。删的如果是当前档案，自动切到剩下的第一个，
    /// 并返回新的 active id（调用方据此决定要不要重载）；返回 nil 表示没删成、
    /// 或者删的不是当前档案、无需重载。
    @discardableResult
    func remove(_ id: String) -> String? {
        guard list.count > 1, let i = list.firstIndex(where: { $0.id == id }) else { return nil }
        let wasActive = activeId == id
        list.remove(at: i)
        store.clearProfile(id)
        if wasActive { activeId = list[0].id }
        persist()
        return wasActive ? activeId : nil
    }

    // MARK: - 序列化

    private func load() {
        let obj = store.readObjectUnscoped(Self.key)
        var l: [Profile] = []
        if let arr = obj?["list"] as? [[String: Any]] {
            for o in arr {
                let id = o["id"] as? String ?? ""
                guard let name = o["name"] as? String, !name.isEmpty else { continue }
                l.append(Profile(id: id, name: name))
            }
        }
        if let a = obj?["active"] as? String { activeId = a }
        if let s = obj?["seq"] as? Int, s >= 2 { seq = s }
        // 至少留一个档案，否则界面无处可去
        if l.isEmpty { l = [Profile(id: "", name: Self.defaultName)] }
        // 默认档案（id 空串）永远存在，否则老用户的数据成了孤儿
        if !l.contains(where: { $0.id.isEmpty }) {
            l.insert(Profile(id: "", name: Self.defaultName), at: 0)
        }
        list = l
        if !list.contains(where: { $0.id == activeId }) { activeId = list[0].id }
    }

    private func persist() {
        let arr: [[String: Any]] = list.map { ["id": $0.id, "name": $0.name] }
        store.writeObjectUnscoped(Self.key, ["list": arr, "active": activeId, "seq": seq])
        // 档案表一变就同步命名空间，避免「切了档案但还在写旧文件」
        store.setProfile(activeId)
    }
}
