import SwiftUI

/// 练习页：几种练习模式的入口 + 最近学习。
struct PracticePageView: View {
    @Environment(AppState.self) private var app

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
                        columns: [GridItem(.adaptive(minimum: 220), spacing: 14)],
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
                Text(emoji).font(.system(size: 28))
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Palette.ink1)
                Text(desc)
                    .font(Fonts.caption)
                    .foregroundStyle(Palette.ink3)
                    .lineLimit(2)
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
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.ink3)
                            Text("\(day.learned)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(day.learned > 0 ? Palette.jade : Palette.ink3)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}
