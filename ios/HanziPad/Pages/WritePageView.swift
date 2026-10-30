import SwiftUI

/// 描红页：接进导航后的完整版。
///
/// 与 M4 探针的区别：这里有真实的保存逻辑、上/下字导航、
/// 以及写完后的星级反馈面板。
///
/// **结构上刻意拆成两层**，原因见 `WritePageBody`。
struct WritePageView: View {
    let ch: String
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var session: WriteSession?
    @State private var showResult = false

    var body: some View {
        GeometryReader { geo in
            Group {
                if let session {
                    WritePageBody(session: session, geo: geo, ch: ch,
                                  showResult: $showResult)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Palette.paper)
        }
        .navigationTitle("描红 · \(ch)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if session == nil {
                session = WriteSession(ch: ch, strokes: app.repo.strokes(ch), box: 400)
            }
            #if DEBUG
            // 自检：进页面后自动用完美笔迹写 N 笔。
            // 用来确认「状态推进后界面有没有跟着刷新」——这一条光看代码看不出来。
            if let n = DebugArgs.writeAuto, let s = session, n > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    for _ in 0..<n where !s.isDone {
                        if let t = s.targetPoints(for: s.index) { _ = s.submit(t) }
                    }
                    TapTargetProbe.shared.record(
                        "描红-自动写\(n)笔后",
                        CGSize(width: CGFloat(s.index), height: CGFloat(s.scores.count))
                    )
                    TapTargetProbe.shared.flush()
                }
            }
            #endif
        }
    }
}

/// 描红页主体。
///
/// **为什么必须单独拆出来**：`WritePageView` 用 `@State` 持有 `WriteSession`，
/// 而 `@State` 不订阅 `ObservableObject` 的变化——状态推进时页面根本不会刷新。
///
/// 实测（`-writeAuto 2` 自动写完两笔后截图）：画布那一块像素变了（笔画填上了），
/// 但表头「第 X / Y 笔」、进度条、每笔得分的区域**像素差为 0**，完全没动。
/// 后果是：孩子被判不合格时，那句「起笔的位置不太对」「没写完整」的提示
/// 永远不会显示，画布上也没有变化——看起来就是「这一笔写不上」。
///
/// 把读 `session` 的部分放进一个带 `@ObservedObject` 的视图，由它订阅，
/// 问题从根上消失。
private struct WritePageBody: View {
    @ObservedObject var session: WriteSession
    let geo: GeometryProxy
    let ch: String
    @Binding var showResult: Bool

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        content
            .sheet(isPresented: $showResult) {
                WriteResultSheet(
                    session: session,
                    onRestart: {
                        session.restart()
                        showResult = false
                    },
                    onDone: {
                        showResult = false
                        dismiss()
                    }
                )
            }
    }

    private var content: some View {
        let wide = LayoutRules.writeIsSplit(geo.size.width)

        return ScrollView {
            VStack(spacing: 18) {
                header

                HStack(alignment: .top, spacing: 22) {
                    WriteCanvasHost(session: session) { pts in
                        handle(session.submit(pts))
                    }
                    .frame(maxWidth: wide ? 480 : 560, maxHeight: wide ? 480 : 560)

                    if wide {
                        sidePanel.frame(maxWidth: 320)
                    }
                }

                if !wide { sidePanel }

                footer
            }
            .padding(.horizontal, Dimens.pagePad(geo.size.width))
            .padding(.vertical, 20)
            .frame(maxWidth: Dimens.contentMax(geo.size.width) + (wide ? 340 : 0))
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Text(session.ch)
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(Palette.ink1)
            if let m = app.repo.meta(ch) {
                Text(app.repo.readingFor(ch, lessonId: m.lesson))
                    .font(.system(size: 17))
                    .foregroundStyle(Palette.jade)
                Button {
                    SpareParts.speak(ch, rate: app.progress.settings.speechRate)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.jade)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text("第 \(min(session.index + 1, max(session.count, 1))) / \(session.count) 笔")
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(Palette.ink2)
        }
    }

    private var sidePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 进度
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("进度")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.ink2)
                    Spacer()
                    Text("\(session.scores.count) 笔已写")
                        .font(Fonts.caption)
                        .foregroundStyle(Palette.ink3)
                }
                ProgressBar(value: session.progress, height: 7)
            }

            // 提示：这一块是「被判不合格」时唯一的反馈，必须随状态刷新
            if !session.message.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(Palette.amber)
                    Text(session.message)
                        .font(Fonts.bodySmall)
                        .foregroundStyle(Palette.ink1)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Palette.amberSoft)
                )
            } else if !session.isDone {
                VStack(alignment: .leading, spacing: 6) {
                    tipRow("1", "从红点起笔")
                    tipRow("2", "沿着淡灰色的字描")
                    tipRow("3", "一笔写完再抬笔")
                }
            }

            // 每笔得分
            if !session.scores.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("每一笔")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.ink2)
                    FlowRow(spacing: 6) {
                        ForEach(Array(session.scores.enumerated()), id: \.offset) { i, s in
                            Text("\(i + 1):\(s)")
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(scoreColor(s))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(scoreColor(s).opacity(0.12)))
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func tipRow(_ n: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(n)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Palette.jade)
                .frame(width: 16, height: 16)
                .background(Circle().fill(Palette.jadeSoft))
            Text(text)
                .font(Fonts.caption)
                .foregroundStyle(Palette.ink2)
        }
    }

    private func scoreColor(_ s: Int) -> Color {
        if s >= 85 { return Palette.jade }
        if s >= 65 { return Palette.amber }
        return Palette.clay
    }

    private var footer: some View {
        HStack(spacing: 12) {
            let prev = app.repo.prevInLesson(app.repo.meta(ch)?.lesson, ch)
            let next = app.repo.nextInLesson(app.repo.meta(ch)?.lesson, ch)

            HanziButton(title: "重写", kind: .secondary) {
                session.restart()
                showResult = false
            }

            HanziButton(title: "跳过一笔", kind: .secondary) {
                session.skip()
            }
            .disabled(session.isDone)

            Spacer()

            if !prev.isEmpty {
                HanziButton(title: "上一个字", kind: .ghost) {
                    app.pushReplacing(AppState.WriteRoute(ch: prev))
                }
            }
            if !next.isEmpty {
                HanziButton(title: "下一个字", kind: .ghost) {
                    app.pushReplacing(AppState.WriteRoute(ch: next))
                }
            }

            HanziButton(title: session.isDone ? "看结果" : "完成", fullWidth: false) {
                if session.isDone {
                    showResult = true
                } else {
                    dismiss()
                }
            }
            .opacity(session.isDone ? 1 : 0.5)
        }
        .frame(maxWidth: .infinity)
    }

    private func handle(_ outcome: WriteSession.Outcome) {
        if case .finished = outcome {
            showResult = true
        }
    }
}

/// 写完后的星级面板。
///
/// 同样要 `@ObservedObject`：`session.restart()` 之后分数会变回 0，
/// 面板要跟着变，否则「再写一遍」后还显示上一次的成绩。
private struct WriteResultSheet: View {
    @ObservedObject var session: WriteSession
    let onRestart: () -> Void
    let onDone: () -> Void

    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text(session.finalStars == 3 ? "🏆" : session.finalStars > 0 ? "🎉" : "🌱")
                .font(.system(size: 54))
            StarsView(count: session.finalStars, size: 28)
            Text("\(session.finalScore) 分")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(Palette.ink1)
            Text(resultText)
                .font(Fonts.body)
                .foregroundStyle(Palette.ink2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)

            Spacer()

            VStack(spacing: 10) {
                HanziButton(title: "再写一遍", fullWidth: true, action: onRestart)
                HanziButton(title: "完成", kind: .secondary, fullWidth: true, action: onDone)
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 26)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            // 一次描红只记一次成绩
            app.progress.saveWrite(session.ch, score: session.finalScore)
            SpareParts.speak(session.ch, rate: app.progress.settings.speechRate)
        }
    }

    private var resultText: String {
        switch session.finalStars {
        case 3: return "一笔一画都很到位，太棒了！"
        case 2: return "写得不错，有几笔再稳一点就更好"
        case 1: return "形状大致对了，慢慢写会更准"
        default: return "再试一次吧，沿着淡灰色的字慢慢描"
        }
    }
}

/// WriteCanvas 的持有者。
///
/// 把 `current` 的 @State 收在这里，`WriteSession` 由外部传入。
/// 之前把两者放在同一个视图里，切换笔画时会因为 `.id()` 重建而丢掉半截笔迹。
private struct WriteCanvasHost: View {
    @ObservedObject var session: WriteSession
    let onStrokeEnd: ([Float]) -> Void
    @State private var current: [Float] = []

    var body: some View {
        WriteCanvas(session: session, current: $current, onStrokeEnd: onStrokeEnd)
    }
}
