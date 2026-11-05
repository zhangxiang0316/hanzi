import SwiftUI

/// 课文详情：本课生字一览 + 每字的拼音/笔画/描红入口。
struct LessonPageView: View {
    let lessonId: String
    @Environment(AppState.self) private var app
    /// 只在需要按字号收窄网格/控件的地方读它
    @Environment(\.dynamicTypeSize) private var dt

    private var lesson: Lesson? { app.repo.lesson(lessonId) }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let lesson {
                        header(lesson)
                        charGrid(lesson)
                    } else {
                        EmptyState(emoji: "📄", title: "找不到这一课",
                                   desc: "也许课本数据更新了，回上一页看看")
                    }
                }
                .padding(.horizontal, Dimens.pagePad(geo.size.width))
                .padding(.vertical, 22)
                .frame(maxWidth: Dimens.contentMax(geo.size.width))
                .frame(maxWidth: .infinity)
            }
            .background(Palette.paper)
        }
        // 主操作固定在底部，与 Android 和小程序一致。
        // 之前这两个按钮跟在生字网格后面的滚动内容里：一课上到二十几个字时，
        // 「本课练习」被推到屏幕外，得先滑到底才能点。
        .safeAreaInset(edge: .bottom) {
            if let lesson {
                actionRow(lesson)
                    .padding(.horizontal, Dimens.pagePad(0))
                    .padding(.vertical, 12)
                    .background(Palette.paper)
            }
        }
        .navigationTitle(lesson?.title ?? "课文")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func header(_ lesson: Lesson) -> some View {
        let c = Plan.countLesson(app.progress, lessonId)
        return HanziCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(lesson.title)
                        .font(Fonts.s(22, .bold, .title2))
                        .foregroundStyle(Palette.ink1)
                    TinyPill(text: lesson.kind, color: Palette.bookColor(lesson.book))
                    Spacer()
                    Text("第 \(lesson.no) 课")
                        .font(Fonts.caption)
                        .foregroundStyle(Palette.ink3)
                }

                HStack(spacing: 14) {
                    Label("\(c.total) 个生字", systemImage: "character.book.closed")
                    Label("已学 \(c.learned)", systemImage: "checkmark.circle")
                    if !lesson.write.isEmpty {
                        Label("\(lesson.write.count) 个会写", systemImage: "pencil")
                    }
                }
                .font(Fonts.bodySmall)
                .foregroundStyle(Palette.ink2)

                ProgressBar(value: Double(c.learned) / Double(max(c.total, 1)))
                    .padding(.top, 2)
            }
        }
    }

    private func charGrid(_ lesson: Lesson) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHead("本课生字")
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: LayoutRules.scaled(108, by: dt.layoutScale)), spacing: 12)],
                spacing: 12
            ) {
                ForEach(lesson.chars, id: \.self) { ch in
                    CharTileView(ch: ch, lessonId: lessonId)
                }
            }
        }
    }

    /// 主操作是「开始 / 继续学习」，次操作才是「本课练习」「整课描红」。
    ///
    /// 小程序 lesson.wxml 的底部条只有一颗「开始学习 · 字」，
    /// Android 也是。iOS 原来把「本课练习」「整课描红」并排当主操作，
    /// 于是进到这一课的第一件事不是开始学，而是去测验——
    /// 顺序反了。练习和描红仍然保留，只是降到第二排。
    private func actionRow(_ lesson: Lesson) -> some View {
        VStack(spacing: 10) {
            let next = lesson.chars.first { !app.progress.hasLearned($0) } ?? lesson.chars.first
            HanziButton(
                title: (lesson.chars.contains { app.progress.hasLearned($0) } ? "继续学习" : "开始学习")
                    + (next.map { " · \($0)" } ?? ""),
                fullWidth: true
            ) {
                if let next { app.push(AppState.CharRoute(ch: next, lesson: lessonId)) }
            }
            .disabled(lesson.chars.isEmpty)

            HStack(spacing: 12) {
                HanziButton(title: "本课练习", kind: .secondary, fullWidth: true) {
                    app.push(AppState.QuizPayload(mode: "lesson", book: lesson.book,
                                                  lesson: lessonId))
                }
                HanziButton(title: "整课描红", kind: .ghost, fullWidth: true) {
                    // 描红从第一个「会写」的字开始，没有会写字就从第一个生字开始
                    let first = lesson.write.first ?? lesson.chars.first
                    if let first { app.push(AppState.WriteRoute(ch: first)) }
                }
                .disabled(lesson.chars.isEmpty)
            }
        }
    }
}

/// 单个生字卡片：笔画预览 + 状态
struct CharTileView: View {
    let ch: String
    var lessonId: String?
    @Environment(AppState.self) private var app
    /// 汉字图标要跟着字号长，不然文字变大后它显得又小又空
    @Environment(\.dynamicTypeSize) private var dt

    var body: some View {
        let meta = app.repo.meta(ch)
        let learned = app.progress.hasLearned(ch)
        let mastered = app.progress.isMastered(ch)
        let record = app.progress.writeRecord(ch)

        Button {
            app.push(AppState.CharRoute(ch: ch, lesson: lessonId))
        } label: {
            VStack(spacing: 6) {
                HanziView(ch: ch, strokes: app.repo.strokes(ch),
                          showGrid: false, showGhost: false,
                          inkColor: learned ? Palette.ink1 : Palette.ink3)
                    .frame(width: LayoutRules.scaled(64, by: dt.layoutScale),
                           height: LayoutRules.scaled(64, by: dt.layoutScale))
                    .overlay(alignment: .topTrailing) {
                        if mastered {
                            Text("★")
                                .font(Fonts.s(10, .regular, .caption2))
                                .foregroundStyle(Palette.amber)
                        } else if learned {
                            Circle()
                                .fill(Palette.jade)
                                .frame(width: 6, height: 6)
                                .padding(4)
                        }
                    }

                Text(meta?.py ?? " ")
                    .font(Fonts.s(12, .regular, .caption))
                    .foregroundStyle(Palette.ink2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if let record, record.stars > 0 {
                    StarsView(count: record.stars, size: 9, animated: false)
                } else {
                    Text(" ")
                        .font(Fonts.s(9, .regular, .caption2))
                }
            }
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Dimens.radiusInner, style: .continuous)
                    .fill(Palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Dimens.radiusInner, style: .continuous)
                    .strokeBorder(mastered ? Palette.jade.opacity(0.5) : Palette.line,
                                  lineWidth: 1)
            )
        }
        .buttonStyle(PressableStyle())
    }
}
