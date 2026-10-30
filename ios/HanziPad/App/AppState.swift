import SwiftUI

/// 应用级状态：导航 + 进度 + 设置。
///
/// Android 用 `AppState` 持有 `Progress` 和一个 `revision` 计数器来触发重组；
/// iOS 这边用 `@Observable`，属性变化自动触发依赖它的视图重绘，不需要手动计数。
@MainActor
@Observable
final class AppState {

    // MARK: - 数据与进度

    let repo: Repo
    let progress: Progress

    /// 当前册次。读写 Progress 里的设置，这样重启后记得上次学到哪一册
    var currentBook: String {
        get { progress.settings.book }
        set {
            var s = progress.settings
            s.book = newValue
            progress.updateSettings(s)
        }
    }

    // MARK: - 导航

    enum Section: Hashable {
        case home
        case courses
        case practice
        case wrong
        case profile
        case about
    }

    var section: Section = .home
    /// 每个分区各自一条导航栈。
    ///
    /// 原本只有一条 `path`，因为 iPad 上只有一个内容列。手机端改成底部 tab 后，
    /// 三个 tab 各有一个 `NavigationStack`——如果还共用一条 path，
    /// 在「首页」里推到某个单元，切到「我的」会看到同一个单元页，
    /// 再切回来栈已经乱了。
    private var paths: [Section: NavigationPath] = [:]

    /// 当前分区的导航栈。push/pop 都作用在这里。
    var path: NavigationPath {
        get { paths[section] ?? NavigationPath() }
        set { paths[section] = newValue }
    }

    /// 取某个分区的栈绑定，给各自的 NavigationStack 用。
    ///
    /// 必须是「按分区取」而不是读 `path`：TabView 会把三个 tab 的视图树都建起来，
    /// 三个 NavigationStack 同时求值时，只有这个能保证各自读到自己那条。
    func pathBinding(_ s: Section) -> Binding<NavigationPath> {
        Binding(
            get: { [weak self] in self?.paths[s] ?? NavigationPath() },
            set: { [weak self] in self?.paths[s] = $0 }
        )
    }

    func go(_ section: Section) {
        self.section = section
        path = NavigationPath()
    }

    func push<V: Hashable>(_ route: V) {
        path.append(route)
    }

    func popToRoot() {
        path = NavigationPath()
    }

    /// 用新页面替换栈顶，不增加栈深度。
    ///
    /// 详情页的「上一个/下一个」用它：连翻 20 个字不该需要按 20 次返回。
    /// `NavigationPath` 没有 replace 操作，所以先移除再追加——
    /// 这在 SwiftUI 里会做一次无动画的替换，看起来正是想要的。
    func pushReplacing<V: Hashable>(_ route: V) {
        if !path.isEmpty { path.removeLast() }
        path.append(route)
    }

    // MARK: - 生命周期

    init(repo: Repo? = nil, store: Store = FileStore()) {
        // Repo.shared 是 @MainActor 的，不能在默认参数里引用（默认参数在
        // 非隔离上下文求值）。所以做成可选，在初始化体内取。
        let r = repo ?? Repo.shared
        self.repo = r
        self.progress = Progress(store: store)
        applyDebugLaunchArgs()
    }

    /// 调试用启动参数，让命令行能给每个页面单独截图。
    ///
    /// 沙箱里没有注入点击事件的办法（simctl 没有 tap 命令），
    /// 而逐个页面核对是界面开发里最需要做的事。用启动参数直接跳到目标页，
    /// 比截一整屏再猜坐标可靠得多。
    ///
    /// 只在 Debug 且参数存在时生效，正常使用完全不受影响。
    private func applyDebugLaunchArgs() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        func value(_ key: String) -> String? {
            guard let i = args.firstIndex(of: key), i + 1 < args.count else { return nil }
            let v = args[i + 1]
            return v.hasPrefix("-") ? nil : v
        }

        if let s = value("-startSection") {
            switch s {
            case "home": section = .home
            case "courses": section = .courses
            case "practice": section = .practice
            case "wrong": section = .wrong
            case "profile": section = .profile
            case "about": section = .about
            default: break
            }
        }

        // 预置一些学习记录，否则练习/错题/徽章等页面全是空状态，看不出真实样子
        if args.contains("-seedDemo") { seedDemoData() }

        if let v = value("-setPinyin") {
            var st = progress.settings
            st.showPinyin = (v == "1")
            progress.updateSettings(st)
        }

        if args.contains("-reportBundle") {
            // 本地化配置是否真的生效，光看工程文件看不出来——
            // 要问运行时的 Bundle 才知道
            let b = Bundle.main
            let lines = [
                "CFBundleDevelopmentRegion: \(b.infoDictionary?["CFBundleDevelopmentRegion"] as? String ?? "nil")",
                "localizations: \(b.localizations.sorted())",
                "preferredLocalizations: \(Bundle.preferredLocalizations(from: b.localizations))",
                "developmentLocalization: \(b.developmentLocalization ?? "nil")",
                "CFBundleLocalizations: \(b.infoDictionary?["CFBundleLocalizations"] as? [String] ?? [])",
                "displayName: \(b.infoDictionary?["CFBundleDisplayName"] as? String ?? "nil")",
            ]
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("bundle-report.txt")
            try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        }

        if args.contains("-selfTestSpeech") {
            // 在设备上真的调一次朗读，验证音频会话能配起来、不崩
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                Speech.shared.speak("天地人", rate: 0.85)
                let report = [
                    "中文语音可用: \(Speech.shared.hasChineseVoice)",
                    "已发起朗读: 天地人",
                ].joined(separator: "\n")
                let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("speech-check.txt")
                try? report.write(to: url, atomically: true, encoding: .utf8)
            }
        }

        if let route = value("-startRoute") {
            let parts = route.split(separator: ":").map(String.init)
            switch parts.first {
            case "book":
                if parts.count > 1 { push(BookRoute(id: parts[1])) }
            case "lesson":
                if parts.count > 1 { push(LessonRoute(id: parts[1])) }
            case "char":
                if parts.count > 1 {
                    push(CharRoute(ch: parts[1], lesson: parts.count > 2 ? parts[2] : nil))
                }
            case "write":
                if parts.count > 1 { push(WriteRoute(ch: parts[1])) }
            case "wrong":
                push(WrongRoute())
            case "about":
                push(AboutRoute())
            case "result":
                // result:对/总/错字数，用于核对结果页
                let correct = Int(parts.count > 1 ? parts[1] : "8") ?? 8
                let total = Int(parts.count > 2 ? parts[2] : "10") ?? 10
                push(ResultPayload(correct: correct, total: total,
                                   wrong: correct < total ? ["地", "人"] : [],
                                   mode: "review", book: currentBook))
            case "quiz":
                push(QuizPayload(mode: parts.count > 1 ? parts[1] : "free",
                                 book: parts.count > 2 ? parts[2] : currentBook,
                                 lesson: parts.count > 3 ? parts[3] : nil))
            default: break
            }
        }
        #endif
    }

    #if DEBUG
    /// 造一批学习记录，用于界面截图核对。
    ///
    /// 开头先 resetAll：进度是落盘的，不重置的话每次启动都在上一次的数据上
    /// 继续叠加，同一个参数两次截图的画面就不一样，没法做像素对比。
    private func seedDemoData() {
        progress.resetAll()
        let book = currentBook
        let chars = repo.bookChars(book)
        let learned = Array(chars.prefix(18))
        for (i, ch) in learned.enumerated() {
            progress.learn(ch)
            // 前面几个字反复答对，推高掌握度
            if i < 8 {
                for _ in 0..<5 { progress.grade(ch, correct: true, lesson: repo.meta(ch)?.lesson) }
            }
        }
        // 造几个错题
        for ch in learned.suffix(4) {
            progress.grade(ch, correct: false, lesson: repo.meta(ch)?.lesson)
        }
        // 造描红成绩
        for (i, ch) in learned.prefix(6).enumerated() {
            progress.saveWrite(ch, score: [96, 88, 72, 65, 50, 90][i % 6])
        }
        progress.recordQuiz(total: 10, correct: 10)
    }
    #endif

    // MARK: - 便捷查询

    var todayTask: Plan.TodayTask {
        Plan.buildTodayTask(progress, currentBook)
    }

    var dailyChar: String {
        Plan.pickDailyChar(currentBook, DayUtil.todayKey())
    }

    /// 练习/答题会话结果，交给答题页和结果页传递
    struct QuizPayload: Hashable {
        let mode: String
        let book: String
        let lesson: String?
    }

    struct ResultPayload: Hashable {
        let correct: Int
        let total: Int
        let wrong: [String]
        let mode: String
        let book: String
    }

    struct LessonRoute: Hashable { let id: String }
    struct CharRoute: Hashable { let ch: String; let lesson: String? }
    struct WriteRoute: Hashable { let ch: String }
    struct BookRoute: Hashable { let id: String }
    struct AboutRoute: Hashable {}
    /// 错题本。iPad 上在侧边栏里直接切分区，手机上只能 push，所以需要一条路由。
    struct WrongRoute: Hashable {}
}

/// 详情列的路由目的地。集中在一处，新增页面时不容易漏。
struct AppRoutes: ViewModifier {
    @Environment(AppState.self) private var app

    func body(content: Content) -> some View {
        content
            .navigationDestination(for: BookRoute.self) { r in
                UnitPageView(book: r.id)
            }
            .navigationDestination(for: LessonRoute.self) { r in
                LessonPageView(lessonId: r.id)
            }
            .navigationDestination(for: CharRoute.self) { r in
                DetailPageView(ch: r.ch, lessonId: r.lesson)
            }
            .navigationDestination(for: WriteRoute.self) { r in
                WritePageView(ch: r.ch)
            }
            .navigationDestination(for: AppState.QuizPayload.self) { p in
                QuizPageView(payload: p)
            }
            .navigationDestination(for: AppState.ResultPayload.self) { p in
                ResultPageView(payload: p)
            }
            .navigationDestination(for: AboutRoute.self) { _ in
                AboutPageView()
            }
            .navigationDestination(for: WrongRoute.self) { _ in
                WrongPageView()
            }
    }
}

// 路由类型需要在文件作用域可见，这里做个别名方便页面引用
typealias BookRoute = AppState.BookRoute
typealias LessonRoute = AppState.LessonRoute
typealias CharRoute = AppState.CharRoute
typealias WriteRoute = AppState.WriteRoute
typealias AboutRoute = AppState.AboutRoute
typealias WrongRoute = AppState.WrongRoute

extension View {
    func appRoutes() -> some View { modifier(AppRoutes()) }
}
