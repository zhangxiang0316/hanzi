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
    func clearAll()
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

    private func url(_ name: String) -> URL {
        dir.appendingPathComponent(name + ".json")
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

    func clearAll() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return }
        for f in files { try? FileManager.default.removeItem(at: f) }
    }
}

/// 内存实现，测试用
final class MemoryStore: Store {
    private var data: [String: [String: Any]] = [:]

    func readObject(_ name: String) -> [String: Any]? { data[name] }
    func writeObject(_ name: String, _ value: [String: Any]) { data[name] = value }
    func remove(_ name: String) { data.removeValue(forKey: name) }
    func clearAll() { data.removeAll() }
}
