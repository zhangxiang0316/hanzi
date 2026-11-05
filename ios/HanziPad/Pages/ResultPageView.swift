import SwiftUI

/// 结果页：正确率 + 星级 + 错字复盘 + 下一步。
struct ResultPageView: View {
    let payload: AppState.ResultPayload
    @Environment(AppState.self) private var app
    /// 只在需要按字号收窄网格/控件的地方读它
    @Environment(\.dynamicTypeSize) private var dt
    @Environment(\.dismiss) private var dismiss

    private var rate: Int {
        payload.total > 0 ? Int((Double(payload.correct) / Double(payload.total) * 100).rounded()) : 0
    }

    /// 星级判据与小程序 `result.wxml` 完全一致：60 / 85 / 100。
    ///
    /// 之前 iOS 是 90/70/50、Android 是 60/85/100、小程序是 60/85/100——
    /// 同一场测验在 iOS 上亮 2 星、在 Android 上亮 1 星。
    /// 这不是配色差异，是**同一个分数得出不同结论**。
    private var stars: Int {
        if rate >= 100 { return 3 }
        if rate >= 85 { return 2 }
        if rate >= 60 { return 1 }
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
            Text(emoji).font(Fonts.s(56, .regular, .largeTitle, maxScale: 1.4))
            StarsView(count: stars, size: 26)

            Text("答对 \(payload.correct) / \(payload.total) 题")
                .font(Fonts.s(22, .bold, .title2))
                .foregroundStyle(Palette.ink1)

            // 正确率圆环：小程序和 Android 都有，iOS 之前只有文字。
            // 环形价值在于「一眼看出满不满」——纯数字要读，圆环瞥一下就知道。
            ProgressRing(
                value: Double(rate) / 100,
                lineWidth: 11,
                size: LayoutRules.scaled(112, by: dt.layoutScale, cap: 1.5)
            )
            .overlay {
                VStack(spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("\(rate)")
                            .font(Fonts.s(30, .bold, .title))
                            .foregroundStyle(Palette.jade)
                        Text("%")
                            .font(Fonts.s(13, .semibold, .caption))
                            .foregroundStyle(Palette.jade)
                    }
                    Text("正确率")
                        .font(Fonts.s(10, .regular, .caption2))
                        .foregroundStyle(Palette.ink3)
                }
            }
            .padding(.vertical, 2)

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

    /// 与小程序的 mood 判据一致：100 / 80 / 60
    private var emoji: String {
        switch rate {
        case 100: return "🏆"
        case 80...: return "🎉"
        case 60...: return "👍"
        default: return "🌱"
        }
    }

    /// 与小程序的 message 判据一致：100 / 80 / 60
    private var praise: String {
        switch rate {
        case 100: return "全对！今天的你特别棒。"
        case 80...: return "很稳！只差一点点就全对了。"
        case 60...: return "不错哦，把错的字再读两遍。"
        default: return "慢慢来，多练几次就记住啦。"
        }
    }

    private var wrongSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHead("这些字再记一记",
                        trailing: AnyView(Text("\(payload.wrong.count) 个")
                            .font(Fonts.caption).foregroundStyle(Palette.ink3)))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: LayoutRules.scaled(100, by: dt.layoutScale)), spacing: 12)], spacing: 12) {
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
                                .font(Fonts.s(11, .regular, .caption))
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
