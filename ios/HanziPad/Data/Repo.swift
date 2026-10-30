import Foundation

/// 数据仓库（M0 阶段只加载笔顺，M1 补齐字表与目录）。
enum Repo {
    /// strokes.json 里是 { "天": "base64...", ... }
    private static var strokeTable: [String: String]?

    private static func loadStrokeTable() -> [String: String] {
        if let t = strokeTable { return t }
        guard let url = Bundle.main.url(forResource: "strokes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else {
            strokeTable = [:]
            return [:]
        }
        strokeTable = obj
        return obj
    }

    /// 已解码的笔顺缓存：解码一次约几百微秒，但滚动列表里会反复用
    private static var cache: [String: StrokeCodec.CharStrokes] = [:]

    static func strokes(_ ch: String) -> StrokeCodec.CharStrokes? {
        if let c = cache[ch] { return c }
        guard let b64 = loadStrokeTable()[ch],
              let decoded = try? StrokeCodec.decode(base64: b64)
        else { return nil }
        cache[ch] = decoded
        return decoded
    }

    static var strokeCharCount: Int { loadStrokeTable().count }
}
