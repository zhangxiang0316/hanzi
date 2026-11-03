import SwiftUI

/// 练习页：几种练习模式的入口 + 最近学习。
struct PracticePageView: View {
    @Environment(AppState.self) private var app
    /// 只在需要按字号收窄网格/控件的地方读它
    @Environment(\.dynamicTypeSize) private var dt

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("练习")
                        .font(Fonts.pageTitle)
                        .foregroundStyle(Palette.ink1)

                    let due = app.progress.allDue().count
                    let wrong = app.progress.wrongCount

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: LayoutRules.scaled(220, by: dt.layoutScale)), spacing: 14)],
                        spacing: 14
                    ) {
                        modeCard(
                            emoji: "🔁", title: "今日复习",
                            desc: due > 0 ? "\(due) 个字到复习时间了" : "暂时没有到期的字",
                            color: Palette.jade, enabled: due > 0
                        ) {
                            app.push(AppState.QuizPayload(mode: "review",
                                                          book: app.currentBook, lesson: nil))
                        }

                        modeCard(
                            emoji: "✍️", title: "错题重练",
                            desc: wrong > 0 ? "\(wrong) 个字曾经答错" : "还没有错题，很棒",
                            color: Palette.clay, enabled: wrong > 0
                        ) {
                            app.push(AppState.QuizPayload(mode: "wrong",
                                                          book: app.currentBook, lesson: nil))
                        }

                        modeCard(
                            emoji: "🎲", title: "随机练习",
                            desc: "从已学的字里随机出题",
                            color: Palette.amber, enabled: app.progress.totalLearned > 0
                        ) {
                            app.push(AppState.QuizPayload(mode: "free",
                                                          book: app.currentBook, lesson: nil))
                        }

                        let polyCount = app.repo.polyphones(book: app.currentBook).count
                        modeCard(
                            emoji: "🎭", title: "多音字",
                            desc: polyCount > 0
                                ? "本册 \(polyCount) 个多音字，练读准"
                                : "换一册就会有多音字",
                            color: Palette.sky, enabled: polyCount > 0
                        ) {
                            app.push(AppState.QuizPayload(mode: "polyphone",
                                                          book: app.currentBook, lesson: nil))
                        }

                        // 部首：查字法是低年级语文园地的正式内容
                        let radicalCount = app.repo.bookRadicals(app.currentBook).count
                        modeCard(
                            emoji: "🧩", title: "部首",
                            desc: "本册 \(radicalCount) 个部首，练查字法",
                            color: Palette.clay, enabled: radicalCount > 0
                        ) {
                            app.push(AppState.QuizPayload(mode: "radical",
                                                          book: app.currentBook, lesson: nil))
                        }

                        // 同音字：一个音有好几个字，练「写哪个」。
                        // 和多音字互补——那个练读对音，这个练写对字。
                        let homoCount = app.repo.homophoneChars(app.currentBook).count
                        modeCard(
                            emoji: "🔤", title: "同音字",
                            desc: homoCount > 0
                                ? "本册 \(homoCount) 个字有同音伙伴，练写对"
                                : "换一册就会有多组",
                            color: Palette.sky, enabled: homoCount > 0
                        ) {
                            app.push(AppState.QuizPayload(mode: "homophone",
                                                          book: app.currentBook, lesson: nil))
                        }

                        // 看拼音选词语：题源是课本词语表，不是生字表。
                        // 孩子要读的是整个词，光认单字读不出来也白搭。
                        let wordCount = app.repo.bookWordCount(app.currentBook)
                        modeCard(
                            emoji: "📚", title: "看拼音选词语",
                            desc: "本册 \(wordCount) 个课文词语",
                            color: Palette.clay, enabled: wordCount >= 4
                        ) {
                            app.push(AppState.QuizPayload(mode: "words",
                                                          book: app.currentBook, lesson: nil))
                        }

                        modeCard(
                            emoji: "📖", title: "课本练习",
                            desc: "按课文顺序练习",
                            color: Palette.bookColor(app.currentBook), enabled: true
                        ) {
                            if let next = Plan.findContinue(app.progress, app.currentBook) {
                                app.push(AppState.QuizPayload(mode: "lesson",
                                                              book: app.currentBook,
                                                              lesson: next.lesson))
                            }
                        }
                    }

                    dictationSection

                    recentSection
                }
                .padding(.horizontal, Dimens.pagePad(geo.size.width))
                .padding(.vertical, 24)
                .frame(maxWidth: Dimens.contentMax(geo.size.width))
                .frame(maxWidth: .infinity)
            }
            .background(Palette.paper)
        }
    }

    private func modeCard(emoji: String, title: String, desc: String,
                          color: Color, enabled: Bool,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                Text(emoji).font(Fonts.s(28, .regular, .largeTitle, maxScale: 1.4))
                Text(title)
                    .font(Fonts.s(16, .bold, .body))
                    .foregroundStyle(Palette.ink1)
                Text(desc)
                    .font(Fonts.caption)
                    .foregroundStyle(Palette.ink3)
                    .lineLimit(dt.isAccessibility ? nil : 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Dimens.radiusCard, style: .continuous)
                    .fill(Palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Dimens.radiusCard, style: .continuous)
                    .strokeBorder(enabled ? color.opacity(0.35) : Palette.line, lineWidth: 1)
            )
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }

    /// 听写：三档难度摆出来让家长选，而不是藏在设置里。
    ///
    /// 适合谁由家长判断——孩子刚学完一课就用「看着写」，
    /// 学过一阵用「听词写」，很熟了用「只听字」。
    private var dictationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHead("听写", trailing: AnyView(Text("念一个词，凭记忆写出来").font(Fonts.caption).foregroundStyle(Palette.ink3)))

            HStack(spacing: 10) {
                ForEach(DictationLevel.allCases, id: \.rawValue) { level in
                    Button {
                        app.push(AppState.DictationRoute(level: level.rawValue,
                                                         book: app.currentBook))
                    } label: {
                        VStack(spacing: 6) {
                            Text(level.title)
                                .font(Fonts.s(14, .bold, .footnote))
                                .foregroundStyle(Palette.ink1)
                            Text(level.showsGhost ? "有底字" : "无底字")
                                .font(Fonts.s(10, .regular, .caption2))
                                .foregroundStyle(Palette.ink3)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: Dimens.radiusInner, style: .continuous)
                                .fill(Palette.card)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Dimens.radiusInner, style: .continuous)
                                .strokeBorder(Palette.line, lineWidth: 1)
                        )
                    }
                    .buttonStyle(PressableStyle())
                    .measureTapTarget("练习-听写\(level.title)")
                }
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHead("最近 7 天")
            HanziCard {
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(app.progress.recentDays(7), id: \.key) { day in
                        VStack(spacing: 6) {
                            // 柱高按当天学习量，最高的柱子占满可用高度
                            let maxVal = max(1, app.progress.recentDays(7).map(\.learned).max() ?? 1)
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(day.learned > 0 ? Palette.jade : Palette.track)
                                .frame(height: max(4, CGFloat(day.learned) / CGFloat(maxVal) * 70))
                            Text(day.label)
                                .font(Fonts.s(10, .regular, .caption2))
                                .foregroundStyle(Palette.ink3)
                            Text("\(day.learned)")
                                .font(Fonts.s(10, .semibold, .caption2))
                                .foregroundStyle(day.learned > 0 ? Palette.jade : Palette.ink3)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}
