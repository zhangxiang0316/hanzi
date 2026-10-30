import Foundation

/// 启动参数（仅 DEBUG）。
///
/// 收在这里是因为不止 `AppState` 要用：描红页的自检钩子也需要。
enum DebugArgs {
    #if DEBUG
    private static var args: [String] { ProcessInfo.processInfo.arguments }

    /// `-writeAuto N`：进入描红页后自动用完美笔迹写 N 笔
    static var writeAuto: Int? {
        guard let i = args.firstIndex(of: "-writeAuto"), i + 1 < args.count else { return nil }
        return Int(args[i + 1])
    }
    #else
    static var writeAuto: Int? { nil }
    #endif
}
