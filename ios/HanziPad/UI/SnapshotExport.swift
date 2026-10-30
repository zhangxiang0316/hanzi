import SwiftUI

/// 把视图渲染成 PNG 存到 Documents，供命令行拉出来核对。
///
/// 为什么不用 `xcrun simctl io screenshot`：截屏拿到的是整屏，要定位每个格子
/// 得靠猜坐标，改一次布局就得重猜一次。`ImageRenderer` 直接指定尺寸和内容，
/// 每张图就是一个待验证的状态，比对时只关心像素本身。
///
/// 只在 Debug 下用，不参与产品界面。
@MainActor
enum SnapshotExport {

    static var outputDir: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// 渲染一个视图到 PNG
    /// 白底渲染。
    ///
    /// ImageRenderer 默认输出透明背景，PNG 里透明像素的 RGB 是 0，
    /// 用「R<110 即墨迹」的判据会把整张图算成墨迹（踩过这个坑）。
    /// 铺白底既让判定可靠，也和 Android 的观感一致。
    @discardableResult
    static func render<V: View>(_ view: V, name: String, size: CGSize, scale: CGFloat = 2) -> URL? {
        let content = view
            .frame(width: size.width, height: size.height)
            .background(Color.white)
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        guard let img = renderer.uiImage, let data = img.pngData() else { return nil }
        let url = outputDir.appendingPathComponent("\(name).png")
        do {
            try data.write(to: url)
            return url
        } catch {
            print("[Snapshot] 写入失败 \(name): \(error)")
            return nil
        }
    }

    /// 批量导出多个字的「只有笔画」版本，用于和离线渲染器逐个比对 IoU
    static func exportM3All() {
        let chars = ["天", "地", "人", "永", "国", "一", "口", "拿", "鬱", "龙"]
        var made: [String] = []
        for ch in chars {
            let strokes = Repo.shared.strokes(ch)
            guard strokes != nil else { continue }
            if render(HanziView(ch: ch, strokes: strokes, showGrid: false, showGhost: false),
                      name: "batch-\(ch)", size: CGSize(width: 320, height: 320)) != nil {
                made.append(ch)
            }
        }
        print("[Snapshot] 批量导出 \(made.count) 字: \(made.joined(separator: ""))")
    }

    /// M3 绘制引擎的验证图集
    static func exportM3(_ ch: String = "天") {
        let strokes = Repo.shared.strokes(ch)
        let S: CGFloat = 320
        var made: [String] = []

        func add<V: View>(_ v: V, _ name: String, _ size: CGSize = CGSize(width: S, height: S)) {
            if render(v, name: "m3-\(name)", size: size) != nil { made.append(name) }
        }

        // 1. 完整字：只有笔画，无格子无底字 —— 与离线渲染器直接可比
        add(HanziView(ch: ch, strokes: strokes, showGrid: false, showGhost: false),
            "ink-only")

        // 2. 带格子
        add(HanziView(ch: ch, strokes: strokes, showGrid: true, showGhost: false),
            "grid")

        // 3. 底字（只有淡灰填充，无墨迹）
        add(HanziView(ch: ch, strokes: strokes, showGrid: false, showGhost: true, completed: 0),
            "ghost")

        // 4. 每一笔的进度状态
        let n = strokes?.count ?? 0
        for i in 0...n {
            add(HanziView(ch: ch, strokes: strokes, showGrid: false, showGhost: true,
                          completed: i, partial: i < n ? 0.5 : 0),
                "step-\(i)")
        }

        // 5. 序号
        add(HanziView(ch: ch, strokes: strokes, showGrid: true, showGhost: true, showNumbers: true),
            "numbers")

        // 6. 尺寸一致性：同一字不同边长
        for s in [80, 160, 320] as [CGFloat] {
            add(HanziView(ch: ch, strokes: strokes, showGrid: false, showGhost: false),
                "size-\(Int(s)/2)", CGSize(width: s, height: s))
        }

        // 7. 无笔顺数据的回退（用字体轮廓）
        add(HanziView(ch: ch, strokes: nil, showGrid: true, showGhost: true), "fallback")

        print("[Snapshot] M3 导出 \(made.count) 张 → \(outputDir.path)")
        print("[Snapshot] \(made.joined(separator: ", "))")
    }
}
