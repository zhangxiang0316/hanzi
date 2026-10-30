import SwiftUI

/// 根视图。手机端是底部 tab，iPad 上是侧边栏 + 内容列。
///
/// **为什么按设备而不是按尺寸类分支。**
///
/// SwiftUI 常规建议是按 `horizontalSizeClass` 自适应，但导航范式不适合这么做：
/// iPhone Pro Max 横屏时宽度 932pt，尺寸类会变成 `.regular`，
/// 于是「转一下手机，整个导航从底部 tab 变成侧边栏」——同一台设备上导航模型突变，
/// 用户还得重新学一遍怎么切页面。
///
/// 所以这里分开处理：
/// - **导航范式**按设备定：手机永远底部 tab，iPad 永远侧边栏。
/// - **页面内部布局**（详情页分不分栏、网格几列）按宽度定，走 `LayoutRules`。
///
/// 这样手机横过来只是内容变宽（详情页可以分栏），不会换掉整个导航。
struct RootView: View {
    @State private var app: AppState
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    init() {
        let state = AppState()
        _app = State(initialValue: state)
        AppStateHolder.shared = state
    }

    var body: some View {
        Group {
            if AppLayout.isPhone {
                PhoneRootView()
            } else {
                padRoot
            }
        }
        .tint(Palette.jade)
        .environment(app)
    }

    private var padRoot: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 245, max: 300)
        } detail: {
            NavigationStack(path: app.pathBinding(app.section)) {
                rootContent
                    .appRoutes()
            }
            .id(app.section)   // 切 section 时重置该列的滚动位置与栈
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var rootContent: some View {
        SectionRootView(section: app.section)
    }
}

/// 某个分区对应的根页面。
///
/// 抽出来是因为手机和 iPad 都要用它：iPad 跟着 `app.section` 走，
/// 手机则是每个 tab 固定一个分区。写在 RootView 里的私有属性手机端用不到。
struct SectionRootView: View {
    let section: AppState.Section

    var body: some View {
        switch section {
        case .home:
            HomePageView()
                .navigationTitle("小小识字家")
                .navigationBarTitleDisplayMode(.inline)
        case .courses:
            CoursesPageView()
                .navigationTitle("课本")
                .navigationBarTitleDisplayMode(.inline)
        case .practice:
            PracticePageView()
                .navigationTitle("练习")
                .navigationBarTitleDisplayMode(.inline)
        case .wrong:
            WrongPageView()
                .navigationTitle("错题本")
                .navigationBarTitleDisplayMode(.inline)
        case .profile:
            ProfilePageView()
                .navigationTitle("我的")
                .navigationBarTitleDisplayMode(.inline)
        case .about:
            AboutPageView()
                .navigationTitle("关于")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// 侧边栏：主导航 + 课本列表 + 今日进度
struct SidebarView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        List {
            Section {
                navRow(.home, "首页", "house")
                navRow(.practice, "练习", "square.grid.2x2")
                navRow(.wrong, "错题本", "exclamationmark.bubble")
                navRow(.profile, "我的", "person")
            }

            Section("课本") {
                ForEach(app.repo.books) { book in
                    bookRow(book)
                }
            }

            Section {
                navRow(.about, "关于", "info.circle")
            }

            Section {
                todayFooter
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("小小识字家")
    }

    private func navRow(_ section: AppState.Section,
                        _ title: String, _ icon: String) -> some View {
        Button {
            app.go(section)
        } label: {
            Label {
                HStack {
                    Text(title)
                    if section == .wrong {
                        let n = app.progress.wrongCount
                        if n > 0 {
                            Spacer()
                            TinyPill(text: "\(n)", color: Palette.clay)
                        }
                    }
                }
            } icon: {
                Image(systemName: icon)
            }
        }
        .buttonStyle(.plain)
        .listRowBackground(
            app.section == section
                ? Palette.jadeSoft
                : Color.clear
        )
        .foregroundStyle(app.section == section ? Palette.jadeDeep : Palette.ink1)
    }

    private func bookRow(_ book: Book) -> some View {
        let bp = Plan.bookProgress(app.progress, book.id)
        let color = Palette.bookColor(book.id)
        let active = app.currentBook == book.id

        return Button {
            app.currentBook = book.id
            app.section = .courses
            app.popToRoot()
        } label: {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: 4, height: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(BookNaming.gradeName(book.grade))\(BookNaming.termName(book.term))")
                        .font(.system(size: 13, weight: active ? .semibold : .regular))
                        .foregroundStyle(Palette.ink1)
                    Text("\(bp.learned)/\(bp.total) · \(bp.pct)%")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.ink3)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .listRowBackground(active ? Palette.jadeSoft : Color.clear)
    }

    private var todayFooter: some View {
        let t = app.progress.todayStats
        return VStack(alignment: .leading, spacing: 5) {
            Text("今天")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.ink3)
            Text("学了 \(t.learned) 字 · 答了 \(t.answers) 题")
                .font(.system(size: 11))
                .foregroundStyle(Palette.ink2)
            if t.answers > 0 {
                Text("正确率 \(app.progress.accuracyToday)%")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.jade)
            }
        }
        .padding(.vertical, 4)
    }
}

/// 课本总览：从侧边栏点「课本」或某个册次进来
struct CoursesPageView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let next = Plan.findContinue(app.progress, app.currentBook) {
                        continueCard(next)
                    }
                    SectionHead("全部课本")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)],
                              spacing: 12) {
                        ForEach(app.repo.books) { book in
                            BookTileView(book: book) {
                                app.currentBook = book.id
                                app.push(AppState.BookRoute(id: book.id))
                            }
                        }
                    }
                }
                .padding(.horizontal, Dimens.pagePad(geo.size.width))
                .padding(.vertical, 22)
                .frame(maxWidth: Dimens.contentMax(geo.size.width))
                .frame(maxWidth: .infinity)
            }
            .background(Palette.paper)
        }
    }

    private func continueCard(_ next: Plan.ContinueInfo) -> some View {
        HanziCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("接着学")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.ink3)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(next.title)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(Palette.ink1)
                    TinyPill(text: "\(next.learned)/\(next.total) 字", color: Palette.jade)
                    Spacer()
                }
                ProgressBar(value: Double(next.learned) / Double(max(next.total, 1)))
                HStack(spacing: 10) {
                    HanziButton(title: "继续学习") {
                        app.push(AppState.LessonRoute(id: next.lesson))
                    }
                    if !next.start.isEmpty {
                        HanziButton(title: "跳到「\(next.start)」", kind: .secondary) {
                            app.push(AppState.CharRoute(ch: next.start, lesson: next.lesson))
                        }
                    }
                    Spacer()
                }
            }
        }
    }
}
