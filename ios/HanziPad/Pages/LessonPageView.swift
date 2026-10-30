import SwiftUI

/// 课文详情：本课生字一览 + 每字的拼音/笔画/描红入口。
struct LessonPageView: View {
    let lessonId: String
    @Environment(AppState.self) private var app

    private var lesson: Lesson? { app.repo.lesson(lessonId) }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let lesson {
                        header(lesson)
                        charGrid(lesson)
                        actionRow(lesson)
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
        .navigationTitle(lesson?.title ?? "课文")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func header(_ lesson: Lesson) -> some View {
        let c = Plan.countLesson(app.progress, lessonId)
        return HanziCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(lesson.title)
                        .font(.system(size: 22, weight: .bold))
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
                columns: [GridItem(.adaptive(minimum: 108), spacing: 12)],
                spacing: 12
            ) {
                ForEach(lesson.chars, id: \.self) { ch in
                    CharTileView(ch: ch, lessonId: lessonId)
                }
            }
        }
    }

    private func actionRow(_ lesson: Lesson) -> some View {
        HStack(spacing: 12) {
            HanziButton(title: "本课练习", fullWidth: true) {
                app.push(AppState.QuizPayload(mode: "lesson", book: lesson.book,
                                              lesson: lessonId))
            }
            HanziButton(title: "整课描红", kind: .secondary, fullWidth: true) {
                // 描红从第一个「会写」的字开始，没有会写字就从第一个生字开始
                let first = lesson.write.first ?? lesson.chars.first
                if let first { app.push(AppState.WriteRoute(ch: first)) }
            }
            .disabled(lesson.chars.isEmpty)
        }
    }
}

/// 单个生字卡片：笔画预览 + 状态
struct CharTileView: View {
    let ch: String
    var lessonId: String?
    @Environment(AppState.self) private var app

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
                    .frame(width: 64, height: 64)
                    .overlay(alignment: .topTrailing) {
                        if mastered {
                            Text("★")
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.amber)
                        } else if learned {
                            Circle()
                                .fill(Palette.jade)
                                .frame(width: 6, height: 6)
                                .padding(4)
                        }
                    }

                Text(meta?.py ?? " ")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.ink2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if let record, record.stars > 0 {
                    StarsView(count: record.stars, size: 9, animated: false)
                } else {
                    Text(" ")
                        .font(.system(size: 9))
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
