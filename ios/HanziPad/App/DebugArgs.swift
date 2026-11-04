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
    /// `-writeStep N`：进入描红页后，隔 1.5 秒按 N 次「下一个字」。
    ///
    /// 走的是导航栏那个按钮**完全同一条**代码路径（`pushReplacing`），
    /// 所以能验证「点了按钮字换没换」。这一条光看代码看不出来——
    /// 问题出在 SwiftUI 的视图身份复用上，不在按钮的 action 里。
    static var writeStep: Int? {
        guard let i = args.firstIndex(of: "-writeStep"), i + 1 < args.count else { return nil }
        return Int(args[i + 1])
    }
    /// `-popAfter N`：N 秒后把导航栈弹回根页面。
    ///
    /// 用来验证「推入页隐藏 tab 栏」之后，返回时 tab 栏能不能回来。
    /// 这一条光看推入的效果看不出来——iOS 16 上曾经有「弹出后 tab 栏
    /// 再也不出现」的 bug，必须实际推一次再弹回来才算验过。
    static var popAfter: Double? {
        guard let i = args.firstIndex(of: "-popAfter"), i + 1 < args.count else { return nil }
        return Double(args[i + 1])
    }
    /// 自动翻字只跑一次：`.id(ch)` 让每换一个字都重跑 `onAppear`，
    /// 不挡的话每换一次就又排一轮，越点越远。
    static var writeStepDone = false
    #else
    static var writeAuto: Int? { nil }
    static var writeSkip: Int? { nil }
    static var writeStep: Int? { nil }
    static var writeStepDone: Bool { false }
    static var popAfter: Double? { nil }
    #endif
}
