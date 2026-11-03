import Foundation

/// 本地存储。
///
/// Android 用 SharedPreferences，iOS 这边写文件而不是 UserDefaults：
/// UserDefaults 也是异步落盘，而且会把整个 plist 重写一遍。
/// 我们的数据量按学过 2596 字算约 200KB，写独立 JSON 文件更合适，
/// 也方便调试时直接 `cat` 出来看。
protocol Store {
    func readObject(_ name: String) -> [String: Any]?
    func writeObject(_ name: String, _ value: [String: Any])
    func remove(_ name: String)
    /// 清空**当前档案**的数据（不动别的孩子，也不动档案表）
    func clearAll()

    /// 切换孩子档案的命名空间。空串 = 默认档案。
    ///
    /// 默认档案用空串，文件名和加档案功能之前完全一样（`progress.json`），
    /// 老用户升级上来数据原地不动。后建的档案放进子目录（`p2/progress.json`）。
    /// 用子目录而不是文件名前缀，是为了避开「文件名里带冒号」这类坑，
    /// 也让「删掉一个孩子的全部数据」变成一次递归删除。
    func setProfile(_ id: String)
    var currentProfile: String { get }

    /// 档案表本身是**全局**的，不带命名空间——
    /// 它是「有哪些档案」的元数据，属于整个 app 而不是某个孩子。
    func readObjectUnscoped(_ name: String) -> [String: Any]?
    func writeObjectUnscoped(_ name: String, _ value: [String: Any])

    /// 删掉某个档案的全部数据（该档案被删除时调用）
    func clearProfile(_ id: String)
}

/// 写文件实现。默认放 Application Support，备份到 iCloud 是合理的
/// （换机后学习进度应该跟着走），所以不设 isExcludedFromBackup。
final class FileStore: Store {
    private let dir: URL

    init(dir: URL? = nil) {
        if let dir {
            self.dir = dir
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.dir = base.appendingPathComponent("HanziPad", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.dir, withIntermediateDirectories: true)
    }

    private var ns: String = ""

    func setProfile(_ id: String) { ns = id }
    var currentProfile: String { ns }

    /// 当前档案的数据目录。默认档案就是根目录，和后建档案天然隔离。
    private var scopeDir: URL {
        ns.isEmpty ? dir : dir.appendingPathComponent(ns, isDirectory: true)
    }

    private func url(_ name: String) -> URL {
        if ns.isEmpty { return dir.appendingPathComponent(name + ".json") }
        try? FileManager.default.createDirectory(at: scopeDir, withIntermediateDirectories: true)
        return scopeDir.appendingPathComponent(name + ".json")
    }

    func readObject(_ name: String) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    func writeObject(_ name: String, _ value: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: value) else { return }
        // 原子写：答题过程中被杀进程也不会留下半截文件
        try? data.write(to: url(name), options: .atomic)
    }

    func remove(_ name: String) {
        try? FileManager.default.removeItem(at: url(name))
    }

    /// 只清当前档案。默认档案要**跳过子目录**，否则会把别的孩子的数据一起删掉——
    /// 「清空学习记录」是清这个孩子的记录，连坐弟弟的进度是不可接受的。
    func clearAll() {
        let target = scopeDir
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: target, includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return }
        for f in entries {
            let isDir = (try? f.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if ns.isEmpty && isDir { continue }
            try? FileManager.default.removeItem(at: f)
        }
    }

    func readObjectUnscoped(_ name: String) -> [String: Any]? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(name + ".json")) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    func writeObjectUnscoped(_ name: String, _ value: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: value) else { return }
        try? data.write(to: dir.appendingPathComponent(name + ".json"), options: .atomic)
    }

    func clearProfile(_ id: String) {
        if id.isEmpty {
            // 默认档案：只删根目录下的 .json 文件，保留各档案子目录
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isDirectoryKey]
            ) else { return }
            for f in entries {
                let isDir = (try? f.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if !isDir { try? FileManager.default.removeItem(at: f) }
            }
        } else {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(id, isDirectory: true))
        }
    }
}

/// 内存实现，测试用
final class MemoryStore: Store {
    /// 键已经带命名空间前缀（`p2:progress`），默认档案是裸名（`progress`）
    private var data: [String: [String: Any]] = [:]
    private var ns: String = ""

    func setProfile(_ id: String) { ns = id }
    var currentProfile: String { ns }

    private func key(_ name: String) -> String { ns.isEmpty ? name : "\(ns):\(name)" }

    func readObject(_ name: String) -> [String: Any]? { data[key(name)] }
    func writeObject(_ name: String, _ value: [String: Any]) { data[key(name)] = value }
    func remove(_ name: String) { data.removeValue(forKey: key(name)) }

    /// 只清当前档案：默认档案清裸名键，后建档案清 `p2:` 前缀的键
    func clearAll() {
        if ns.isEmpty {
            for k in data.keys where !k.contains(":") { data.removeValue(forKey: k) }
        } else {
            let p = "\(ns):"
            for k in data.keys where k.hasPrefix(p) { data.removeValue(forKey: k) }
        }
    }

    func readObjectUnscoped(_ name: String) -> [String: Any]? { data[name] }
    func writeObjectUnscoped(_ name: String, _ value: [String: Any]) { data[name] = value }

    func clearProfile(_ id: String) {
        if id.isEmpty {
            for k in data.keys where !k.contains(":") { data.removeValue(forKey: k) }
        } else {
            let p = "\(id):"
            for k in data.keys where k.hasPrefix(p) { data.removeValue(forKey: k) }
        }
    }
}
