import SwiftUI

/// 实测可点击控件的真实布局尺寸。
///
/// 触达区域这件事没法靠截图判断——`minTapTarget()` 只撑大点击区域、
/// 不改变视觉大小，所以画面上看不出区别。用代码里的 padding 反推也不可靠
/// （字号、行高、`max(文字高, 控件高)` 都会影响最终高度）。
///
/// 所以让 SwiftUI 自己报数：给控件挂一个 `GeometryReader`，把量到的尺寸写进文件。
/// 启动参数 `-probeTapTargets` 触发。
///
/// **只在 DEBUG 编译**。早先的做法是「Release 里给个空实现的 `record()`」，
/// 但那没用——`GeometryReader` 本身是真实视图，Release 里照样参与布局，
/// 被消掉的只是那次空函数调用。9 处探针就等于 9 次多余布局。
/// 现在改用 `measureTapTarget(_:)`，Release 下整个 modifier 编译成空。
#if DEBUG
@MainActor
final class TapTargetProbe: ObservableObject {
    static let shared = TapTargetProbe()

    private(set) var rows: [(name: String, size: CGSize)] = []
    private var flushed = false

    func record(_ name: String, _ size: CGSize) {
        // 同一个控件可能报多次（布局过程中），只留最后一次
        if let i = rows.firstIndex(where: { $0.name == name }) {
            rows[i] = (name, size)
        } else {
            rows.append((name, size))
        }
    }

    /// 布局稳定后落盘。
    ///
    /// **可以多次调用，每次覆盖写**。早先是用一个 `flushed` 闩只写一次，
    /// 由启动后固定 1.2 秒触发——页面稍慢一点没布局完，探针就只记到
    /// 首页控件，而文件照样生成，看起来像"这个页面没有需要量的控件"。
    /// 我拿词语表页实测过：等 4 秒只探到「首页-今日一字」，等 6 秒就
    /// 三个控件全在了。这种"静默漏数据"的取证工具比没有更危险，
    /// 所以改成可以重复 flush，由调用方多调几次。
    func flush() {
        guard !rows.isEmpty else { return }

        let lines = rows.map { r -> String in
            let w = Int(r.size.width.rounded())
            let h = Int(r.size.height.rounded())
            let ok = (w >= 44 && h >= 44) ? "OK" : "TOO SMALL"
            return "\(r.name)\t\(w)x\(h)\t\(ok)"
        }
        let header = "控件\t实测尺寸(pt)\t是否达标(>=44x44)"
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("tap-targets.txt")
        try? ([header] + lines).joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}

extension View {
    /// 记录这个控件的布局尺寸。Release 下编译成 `self`，零开销。
    func measureTapTarget(_ name: String) -> some View {
        background(GeometryReader { g in
            // `onAppear` 只触发一次，而且常常在宽度定下来之前就触发了，
            // 于是量到 `0x120` 这种半截尺寸——看着像「控件太窄」，
            // 其实是测量时机的问题。`onChange` 会把布局稳定后的真实尺寸补上。
            // 这个坑是加「笔画薄弱点」四个一排的小卡片时踩到的。
            Color.clear
                .onAppear { TapTargetProbe.shared.record(name, g.size) }
                .onChange(of: g.size) { _, size in
                    TapTargetProbe.shared.record(name, size)
                }
        })
    }
}
#else
extension View {
    /// Release 下什么都不做。整个方法体是 `self`，不会进视图树。
    @inlinable
    func measureTapTarget(_ name: String) -> some View { self }
}
#endif
