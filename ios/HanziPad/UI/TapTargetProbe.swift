import SwiftUI

/// 实测可点击控件的真实布局尺寸。
///
/// 触达区域这件事没法靠截图判断——`minTapTarget` 只撑大点击区域、
/// 不改变视觉大小，所以画面上看不出区别。而用代码里的 padding 数字
/// 反推也不可靠（字号、行高、Spacer 都会影响最终高度）。
///
/// 所以直接让 SwiftUI 报数：每个待测控件挂一个 GeometryReader，
/// 把量到的尺寸写进文件。这样拿到的是真实布局结果。
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

    /// 布局稳定后落盘。启动参数 `-probeTapTargets` 触发。
    func flush() {
        guard !flushed, !rows.isEmpty else { return }
        flushed = true

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

/// 给任意视图测尺寸并上报
struct Measured<Content: View>: View {
    let name: String
    @ViewBuilder let content: Content

    var body: some View {
        content.background(
            GeometryReader { g in
                Color.clear.onAppear {
                    TapTargetProbe.shared.record(name, g.size)
                }
            }
        )
    }
}

#else

/// Release 构建下的空实现。
///
/// 页面里的调用点没有包 `#if DEBUG`（那样每处都要包一层，容易漏），
/// 所以这里给一个不做事的同名类型。`record` 是空函数，
/// 整个调用会被编译器优化掉，不会进 Release 包。
@MainActor
final class TapTargetProbe {
    static let shared = TapTargetProbe()
    func record(_ name: String, _ size: CGSize) {}
}

#endif
