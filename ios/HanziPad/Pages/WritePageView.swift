import SwiftUI
import UIKit

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
        // 「上一个字 / 下一个字」是导航，放导航栏；页脚留给操作。
        // 挤在页脚时五个按钮放不下，见 footer 的注释。
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                let prev = app.repo.prevInLesson(app.repo.meta(ch)?.lesson, ch)
                let next = app.repo.nextInLesson(app.repo.meta(ch)?.lesson, ch)
                if !prev.isEmpty {
                    Button {
                        app.pushReplacing(AppState.WriteRoute(ch: prev))
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("上一个字")
                }
                if !next.isEmpty {
                    Button {
                        app.pushReplacing(AppState.WriteRoute(ch: next))
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .accessibilityLabel("下一个字")
                }
            }
        }
        .onAppear {
            if session == nil {
                session = WriteSession(ch: ch, strokes: app.repo.strokes(ch), box: 400)
            }
            #if DEBUG
            // 自检：进页面后自动用完美笔迹写 N 笔。
            // 用来确认「状态推进后界面有没有跟着刷新」——这一条光看代码看不出来。
            if let n = DebugArgs.writeSkip, let s = session, n > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    for _ in 0..<n where !s.isDone { s.skip() }
                    TapTargetProbe.shared.record(
                        "描红-跳过\(n)笔后",
                        CGSize(width: CGFloat(s.index), height: CGFloat(s.scores.count))
                    )
                    TapTargetProbe.shared.flush()
                }
            }
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
    /// 分栏阈值要随字号放大，否则大字号下侧栏被挤成竖条
    @Environment(\.dynamicTypeSize) private var dt
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
        let wide = LayoutRules.writeIsSplit(geo.size.width, scale: dt.layoutScale)

        return ScrollView {
            VStack(spacing: 18) {
                header
                if !app.repo.isWriteChar(ch) { readOnlyNote }

                HStack(alignment: .top, spacing: 22) {
                    WriteCanvasHost(session: session) { pts in
                        // 先记住这一笔的序号：.passed 之后 session.index 已经 +1 了
                        let idx = session.index
                        let outcome = session.submit(pts)
                        recordStroke(outcome, index: idx)
                        handle(outcome)
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
                .font(Fonts.s(32, .semibold, .largeTitle, maxScale: 2.2))
                .foregroundStyle(Palette.ink1)
            if let m = app.repo.meta(ch) {
                Text(app.repo.readingFor(ch, lessonId: m.lesson))
                    .font(Fonts.s(17, .regular, .headline))
                    .foregroundStyle(Palette.jade)
                Button {
                    SpareParts.speak(ch, rate: app.progress.settings.speechRate)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(Fonts.s(14, .regular, .footnote))
                        .foregroundStyle(Palette.jade)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text("第 \(min(session.index + 1, max(session.count, 1))) / \(session.count) 笔")
                .font(Fonts.s(14, .semibold, .footnote).monospacedDigit())
                .foregroundStyle(Palette.ink2)
        }
    }

    /// 只认不写的字（教材里 341 个，如髓/嚼/蟹）要提前说明，
    /// 否则孩子写不好会以为自己「没学会」——课标本来就不要求会写。
    private var readOnlyNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("💡").font(Fonts.s(13, .regular, .footnote))
            Text("这个字课本只要求认识，不要求会写。写不好没关系，多写几次手会熟。")
                .font(Fonts.caption)
                .foregroundStyle(Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Dimens.radiusInner, style: .continuous)
                .fill(Palette.skySoft)
        )
    }

    private var sidePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 进度
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("进度")
                        .font(Fonts.s(12, .semibold, .caption))
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
                        .font(Fonts.s(12, .semibold, .caption))
                        .foregroundStyle(Palette.ink2)
                    FlowRow(spacing: 6) {
                        ForEach(Array(session.scores.enumerated()), id: \.offset) { i, s in
                            Text("\(i + 1):\(s)")
                                .font(Fonts.s(11, .regular, .caption).monospacedDigit())
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
                .font(Fonts.s(10, .bold, .caption2))
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

    /// 页脚只放三个**操作**：重写 / 跳过一笔 / 完成。
    ///
    /// 「上一个字 / 下一个字」挪去导航栏了——它们是**导航**，不是操作。
    /// 原来五个按钮挤在 iPhone 的 362pt 里（70+100+100+100+70+48 间距 = 488pt），
    /// 必然放不下，「跳过一笔」被压到 70pt 宽、文字折成两行、按钮高度从
    /// 40 涨到 58，整行跟着错位。这不是换行的问题，是塞不下的问题——
    /// 所以减按钮而不是缩字号。
    /// 页脚。默认字号横排，辅助功能字号竖排。
    ///
    /// 竖排不是洁癖：最大字号下三颗按钮要 496pt，而 iPhone 只有 362pt。
    /// 实测「跳过一笔」被压到 104pt 宽——4 个字各分到 16pt，
    /// 连 `minimumScaleFactor(0.8)` 都救不回来，只能截断成省略号。
    /// 一个字都看不全的按钮，等于没有。
    @ViewBuilder
    private var footer: some View {
        if LayoutRules.footerStacks(scale: dt.layoutScale) {
            VStack(spacing: 12) {
                // 顺序和横排的左→右一致，主动作落在最下面（离拇指最近）
                restartButton(fullWidth: true)
                skipButton(fullWidth: true)
                primaryAction(fullWidth: true)
            }
            .frame(maxWidth: .infinity)
        } else {
            HStack(spacing: 12) {
                restartButton(fullWidth: false)
                skipButton(fullWidth: false)
                Spacer()
                primaryAction(fullWidth: false)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func restartButton(fullWidth: Bool) -> some View {
        HanziButton(title: "重写", kind: .secondary, fullWidth: fullWidth) {
            session.restart()
            showResult = false
        }
    }

    private func skipButton(fullWidth: Bool) -> some View {
        HanziButton(title: "跳过一笔", kind: .secondary, fullWidth: fullWidth) {
            session.skip()
        }
        .disabled(session.isDone)
    }

    private func primaryAction(fullWidth: Bool) -> some View {
        HanziButton(
            title: session.isDone ? "看结果" : "完成",
            fullWidth: fullWidth
        ) {
            if session.isDone {
                showResult = true
            } else {
                dismiss()
            }
        }
        .opacity(session.isDone ? 1 : 0.5)
    }

    private func handle(_ outcome: WriteSession.Outcome) {
        if case .finished = outcome {
            showResult = true
        }
    }

    /// 记一笔笔画薄弱点。
    ///
    /// 只有判分没过（.rejected）才算失败；`.tooShort` 不计——
    /// 点一下、划得太短多半是误触，记进去的话两次手滑就把一个笔画
    /// 标成「薄弱」，那个提示就没人信了。与小程序、Android 一致。
    private func recordStroke(_ outcome: WriteSession.Outcome, index: Int) {
        switch outcome {
        case .passed, .finished:
            // 连着对两次才算练稳（见 Progress.recordStroke）
            app.progress.recordStroke(ch, index: index, passed: true)
        case .rejected:
            app.progress.recordStroke(ch, index: index, passed: false)
        case .tooShort:
            break
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
                .font(Fonts.s(54, .regular, .largeTitle, maxScale: 1.4))
            StarsView(count: session.finalStars, size: 28)
            Text("\(session.finalScore) 分")
                .font(Fonts.s(32, .bold, .largeTitle, maxScale: 2.2))
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
