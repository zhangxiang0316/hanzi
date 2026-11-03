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
    /// `-writeSkip N`：进入描红页后自动跳过 N 笔（不写，直接跳）
    ///
    /// 和 `-writeAuto` 成对：那个验证「写了之后界面刷新没有」，
    /// 这个验证「跳过之后界面/按钮有没有变形」。
    static var writeSkip: Int? {
        guard let i = args.firstIndex(of: "-writeSkip"), i + 1 < args.count else { return nil }
        return Int(args[i + 1])
    }
    #else
    static var writeAuto: Int? { nil }
    static var writeSkip: Int? { nil }
    #endif
}
