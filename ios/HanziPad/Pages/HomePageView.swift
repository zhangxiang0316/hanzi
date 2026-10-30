import SwiftUI

/// 首页：问候 + 今日任务 + 总进度 + 今日一字 + 课本入口。
///
/// 与 Android `IndexPage.kt` 的差别：底部导航换成侧边栏，所以首页多一些留白、
/// 整体按 iPad 的宽屏重排（左栏信息、右栏课本网格）。
struct HomePageView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    greeting
                    todayTaskCard
                    statsRow
                    dailyCharCard
                    bookSection
                }
                .padding(.horizontal, Dimens.pagePad(geo.size.width))
                .padding(.vertical, 24)
                .frame(maxWidth: Dimens.contentMax(geo.size.width))
                .frame(maxWidth: .infinity)
            }
            .background(Palette.paper)
        }
    }

    // MARK: - 问候

    private var greeting: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(DayUtil.greeting())，小朋友")
                    .font(Fonts.pageTitle)
                    .foregroundStyle(Palette.ink1)
                Text("\(DayUtil.dateLabel()) \(DayUtil.weekdayCN())")
                    .font(Fonts.bodySmall)
                    .foregroundStyle(Palette.ink3)
            }
            Spacer()
            streakBadge
        }
    }

    private var streakBadge: some View {
        HStack(spacing: 5) {
            Text("🔥").font(.system(size: 14))
            Text("\(app.progress.streak) 天")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(app.progress.streak > 0 ? Palette.amber : Palette.ink3)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(app.progress.streak > 0 ? Palette.amberSoft : Palette.track)
        )
    }

    // MARK: - 今日任务

    private var todayTaskCard: some View {
        let task = app.todayTask
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(task.title)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                if task.count > 0 {
                    Text("\(task.count) 个")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.white.opacity(0.22)))
                }
            }
            Text(task.desc)
                .font(Fonts.bodySmall)
                .foregroundStyle(.white.opacity(0.85))
                .padding(.top, 6)

            Button {
                start(task)
            } label: {
                Text(task.action)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.jadeDeep)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white)
                    )
            }
            .buttonStyle(PressableStyle())
            .padding(.top, 15)
        }
        .padding(19)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Dimens.radiusCard, style: .continuous)
                .fill(
                    LinearGradient(colors: [Palette.jade, Palette.jadeDeep],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
        )
    }

    private func start(_ task: Plan.TodayTask) {
        switch task.type {
        case "review":
            app.push(AppState.QuizPayload(mode: "review", book: app.currentBook, lesson: nil))
        case "done":
            app.push(AppState.QuizPayload(mode: "free", book: app.currentBook, lesson: nil))
        default:
            if let next = Plan.findContinue(app.progress, app.currentBook) {
                app.push(AppState.LessonRoute(id: next.lesson))
            } else {
                app.push(AppState.QuizPayload(mode: "free", book: app.currentBook, lesson: nil))
            }
        }
    }

    // MARK: - 总进度

    private var statsRow: some View {
        let learned = app.progress.totalLearned
        let total = app.repo.allChars.count
        let pct = total > 0 ? Double(learned) / Double(total) : 0

        return HanziCard {
            HStack(spacing: 20) {
                ProgressRing(value: pct)
                    .overlay(
                        VStack(spacing: 1) {
                            Text("\(Int((pct * 100).rounded()))%")
                                .font(.system(size: 19, weight: .bold))
                                .foregroundStyle(Palette.jade)
                        }
                    )

                VStack(alignment: .leading, spacing: 5) {
                    Text("已认识 \(learned) 个字")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.ink1)
                    Text("全库 \(total) 字")
                        .font(Fonts.caption)
                        .foregroundStyle(Palette.ink3)
                    HStack(spacing: 7) {
                        TinyPill(text: "已掌握 \(app.progress.totalMastered)", color: Palette.jade)
                        let due = app.progress.allDue().count
                        if due > 0 {
                            TinyPill(text: "待复习 \(due)", color: Palette.clay)
                        }
                    }
                    .padding(.top, 2)
                }
                Spacer()
            }
        }
    }

    // MARK: - 今日一字

    private var dailyCharCard: some View {
        let ch = app.dailyChar
        let meta = app.repo.meta(ch)
        return HanziCard {
            HStack(alignment: .top, spacing: 18) {
                VStack(spacing: 8) {
                    HanziView(ch: ch, strokes: app.repo.strokes(ch),
                              showGrid: true, showGhost: false)
                        .frame(width: 104, height: 104)
                    Text("今日一字")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.ink3)
                }

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        Text(ch)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(Palette.ink1)
                        if let meta {
                            Text(meta.py)
                                .font(.system(size: 16))
                                .foregroundStyle(Palette.jade)
                        }
                    }
                    if let meta {
                        Text("部首「\(meta.radical)」· \(meta.strokes) 笔")
                            .font(Fonts.bodySmall)
                            .foregroundStyle(Palette.ink2)
                        if !meta.words.isEmpty {
                            Text(meta.words.prefix(3).map(\.word).joined(separator: " · "))
                                .font(Fonts.bodySmall)
                                .foregroundStyle(Palette.ink3)
                                .lineLimit(1)
                        }
                    }
                    HStack(spacing: 10) {
                        Button("看笔画") {
                            app.push(AppState.CharRoute(ch: ch, lesson: meta?.lesson))
                        }
                        .buttonStyle(.bordered)
                        .tint(Palette.jade)
                        .controlSize(.small)

                        Button("描红") {
                            app.push(AppState.WriteRoute(ch: ch))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.jade)
                        .controlSize(.small)
                    }
                    .padding(.top, 3)
                }
                Spacer()
            }
        }
    }

    // MARK: - 课本

    private var bookSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHead("跟课本学")
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 190), spacing: 12)],
                spacing: 12
            ) {
                ForEach(app.repo.books) { book in
                    BookTileView(book: book) {
                        app.currentBook = book.id
                        app.push(AppState.BookRoute(id: book.id))
                    }
                }
            }
        }
    }
}

/// 册次卡片：年级学期 + 进度 + 生字数
struct BookTileView: View {
    let book: Book
    let onTap: () -> Void
    @Environment(AppState.self) private var app

    var body: some View {
        let bp = Plan.bookProgress(app.progress, book.id)
        let color = Palette.bookColor(book.id)

        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline) {
                    Text(BookNaming.gradeName(book.grade))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Palette.ink1)
                    Text(BookNaming.termName(book.term))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(color.opacity(0.14)))
                    Spacer()
                    Text("\(bp.pct)%")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(color)
                }

                ProgressBar(value: Double(bp.learned) / Double(max(bp.total, 1)),
                            height: 5, color: color)

                Text("\(book.lessons.count) 课 · \(bp.total) 字 · 已学 \(bp.learned)")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.ink3)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Dimens.radiusInner, style: .continuous)
                    .fill(Palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Dimens.radiusInner, style: .continuous)
                    .strokeBorder(book.id == app.currentBook ? color : Palette.line,
                                  lineWidth: book.id == app.currentBook ? 2 : 1)
            )
        }
        .buttonStyle(PressableStyle())
    }
}
