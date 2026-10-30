import SwiftUI

/// 根视图：侧边栏 + 内容列。
///
/// 结构选择说明：
/// Android 用底部三个 tab（首页/练习/我的），是因为手机屏幕窄、列不出更多入口。
/// iPad 上底部导航离手太远、且横屏有大量横向空间，`NavigationSplitView` 的侧边栏
/// 是更自然的形态——左侧常驻导航，右侧内容可以一路 push 下去。
///
/// 侧边栏同时承担「课本选择」：8 册课本直接列在侧边栏里，
/// 比藏在首页的宫格里少一次跳转。
struct RootView: View {
    @State private var app: AppState
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    init() {
        let state = AppState()
        _app = State(initialValue: state)
        AppStateHolder.shared = state
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 245, max: 300)
        } detail: {
            NavigationStack(path: Bindable(app).path) {
                rootContent
                    .appRoutes()
            }
            .id(app.section)   // 切 section 时重置该列的滚动位置与栈
        }
        .navigationSplitViewStyle(.balanced)
        .tint(Palette.jade)
        .environment(app)
    }

    @ViewBuilder
    private var rootContent: some View {
        switch app.section {
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
