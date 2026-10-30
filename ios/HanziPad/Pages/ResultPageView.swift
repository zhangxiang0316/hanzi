import SwiftUI

/// 结果页：正确率 + 星级 + 错字复盘 + 下一步。
struct ResultPageView: View {
    let payload: AppState.ResultPayload
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    private var rate: Int {
        payload.total > 0 ? Int((Double(payload.correct) / Double(payload.total) * 100).rounded()) : 0
    }

    private var stars: Int {
        if rate >= 90 { return 3 }
        if rate >= 70 { return 2 }
        if rate >= 50 { return 1 }
        return 0
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 22) {
                    hero
                    if !payload.wrong.isEmpty { wrongSection }
                    actionRow
                }
                .padding(.horizontal, Dimens.pagePad(geo.size.width))
                .padding(.vertical, 26)
                .frame(maxWidth: Dimens.contentMax(geo.size.width))
                .frame(maxWidth: .infinity)
            }
            .background(Palette.paper)
        }
        .navigationTitle("练习结果")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
    }

    private var hero: some View {
        VStack(spacing: 14) {
            Text(emoji).font(.system(size: 56))
            StarsView(count: stars, size: 26)

            Text("答对 \(payload.correct) / \(payload.total) 题")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Palette.ink1)

            Text(praise)
                .font(Fonts.body)
                .foregroundStyle(Palette.ink2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .background(
            RoundedRectangle(cornerRadius: Dimens.radiusCard, style: .continuous)
                .fill(Palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Dimens.radiusCard, style: .continuous)
                .strokeBorder(Palette.line, lineWidth: 1)
        )
    }

    private var emoji: String {
        switch rate {
        case 100: return "🏆"
        case 90...: return "🎉"
        case 70...: return "👍"
        case 50...: return "💪"
        default: return "🌱"
        }
    }

    private var praise: String {
        switch rate {
        case 100: return "全对！太厉害了"
        case 90...: return "非常棒，只差一点点"
        case 70...: return "做得不错，再练一次就更熟了"
        case 50...: return "有进步空间，我们再来一遍"
        default: return "没关系，慢慢来，多练几次就会了"
        }
    }

    private var wrongSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHead("这些字再记一记",
                        trailing: AnyView(Text("\(payload.wrong.count) 个")
                            .font(Fonts.caption).foregroundStyle(Palette.ink3)))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
                ForEach(Array(Set(payload.wrong)).sorted(), id: \.self) { ch in
                    Button {
                        app.push(AppState.CharRoute(ch: ch,
                                                    lesson: app.repo.meta(ch)?.lesson))
                    } label: {
                        VStack(spacing: 6) {
                            HanziView(ch: ch, strokes: app.repo.strokes(ch),
                                      showGrid: false, showGhost: false)
                                .frame(width: 54, height: 54)
                            Text(app.repo.meta(ch)?.py ?? "")
                                .font(.system(size: 11))
                                .foregroundStyle(Palette.ink3)
                        }
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: Dimens.radiusInner,
                                             style: .continuous)
                                .fill(Palette.card)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Dimens.radiusInner,
                                             style: .continuous)
                                .strokeBorder(Palette.clay.opacity(0.35), lineWidth: 1)
                        )
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            HanziButton(title: "返回", kind: .secondary, fullWidth: true) {
                dismiss()
            }
            HanziButton(title: "再练一组", fullWidth: true) {
                // 回到答题页重建一套新题
                dismiss()
                app.push(AppState.QuizPayload(mode: payload.mode,
                                              book: payload.book, lesson: nil))
            }
        }
    }
}
