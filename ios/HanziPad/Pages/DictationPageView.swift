import SwiftUI

/// 听写页：念一个词，孩子凭记忆写。
///
/// 复用描红的判分（`WriteSession`）与画布（`WriteCanvas`），只是把底字藏起来。
/// 页面自己管「一道题写完之后进下一题」，因为听写是按字推进的，
/// 而描红是「一个字写完就结束」。
struct DictationPageView: View {
    let level: DictationLevel
    /// 要听写的字（从哪一册来由调用方决定）
    let book: String

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var plan: DictationPlan?
    @State private var session: WriteSession?
    @State private var showResult = false
    /// 写完一个字后短暂显示对错，再进下一个
    @State private var justFinished = false

    var body: some View {
        GeometryReader { geo in
            Group {
                if let plan, let session {
                    content(plan: plan, session: session, geo: geo)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Palette.paper)
        }
        .navigationTitle("听写 · \(level.title)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: start)
    }

    private func start() {
        guard plan == nil else { return }
        let items = DictationSource.pick(book: book, level: level, limit: 8)
        let p = DictationPlan(level: level, items: items)
        plan = p
        loadCurrent(p)
    }

    private func loadCurrent(_ p: DictationPlan) {
        guard let item = p.current else { return }
        justFinished = false
        session = WriteSession(ch: item.ch,
                               strokes: app.repo.strokes(item.ch),
                               box: 400,
                               hideGhost: !p.level.showsGhost)
        // 进页面/换字后自动念一遍——否则孩子不知道要写什么
        speak(item, level: p.level)
    }

    private func speak(_ item: DictationPlan.Item, level: DictationLevel) {
        let text = level.promptText(ch: item.ch, word: item.word)
        SpareParts.speak(text, rate: app.progress.settings.speechRate)
    }

    // MARK: - 主体

    @ViewBuilder
    private func content(plan: DictationPlan, session: WriteSession, geo: GeometryProxy) -> some View {
        let wide = LayoutRules.writeIsSplit(geo.size.width)

        ScrollView {
            VStack(spacing: 18) {
                progressHeader(plan)

                HStack(alignment: .top, spacing: 22) {
                    if let item = plan.current {
                        DictationCanvasHost(session: session) { pts in
                            handle(session.submit(pts), plan: plan, session: session)
                        }
                        .frame(maxWidth: wide ? 460 : 520, maxHeight: wide ? 460 : 520)
                        .overlay(alignment: .topTrailing) {
                            if !wide { replayButton(item, plan: plan) }
                        }
                    }

                    if wide, let item = plan.current {
                        sidePanel(plan: plan, session: session, item: item)
                            .frame(maxWidth: 320)
                    }
                }

                if !wide, let item = plan.current {
                    sidePanel(plan: plan, session: session, item: item)
                }

                footer(plan: plan, session: session)
            }
            .padding(.horizontal, Dimens.pagePad(geo.size.width))
            .padding(.vertical, 20)
            .frame(maxWidth: Dimens.contentMax(geo.size.width) + (wide ? 320 : 0))
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showResult) {
            DictationResultSheet(plan: plan) {
                showResult = false
                dismiss()
            }
        }
    }

    private func progressHeader(_ plan: DictationPlan) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text("第 \(min(plan.index + 1, plan.count)) / \(plan.count) 个")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.ink2)
                Spacer()
                if let avg = plan.averageScore {
                    Text("平均 \(avg) 分")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.jade)
                }
            }
            ProgressBar(
                value: plan.count > 0 ? Double(plan.index) / Double(plan.count) : 0,
                height: 6
            )
        }
    }

    private func replayButton(_ item: DictationPlan.Item, plan: DictationPlan) -> some View {
        Button {
            speak(item, level: plan.level)
        } label: {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.jade)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Palette.card))
                .overlay(Circle().strokeBorder(Palette.line, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .padding(10)
        .accessibilityLabel("再念一遍")
    }

    private func sidePanel(plan: DictationPlan, session: WriteSession, item: DictationPlan.Item) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(plan.level.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.sky)
                Text(plan.level == .hard ? "听清楚了吗？" : "听到的是——")
                    .font(Fonts.caption)
                    .foregroundStyle(Palette.ink3)
                // 写完之后才显示答案：写之前显示就等于把底字给了
                if justFinished {
                    Text(item.ch)
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(Palette.ink1)
                } else {
                    Text("＿")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(Palette.ink3.opacity(0.35))
                }
                if let w = item.word, plan.level != .hard {
                    Text(w)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.ink3)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Dimens.radiusInner, style: .continuous)
                    .fill(Palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Dimens.radiusInner, style: .continuous)
                    .strokeBorder(Palette.line, lineWidth: 1)
            )

            // 笔画提示：听写不比描红，看不见底字，得让孩子知道还剩几笔
            if !justFinished, session.count > 0 {
                tipRow("笔画", "第 \(min(session.index + 1, session.count)) / \(session.count) 笔")
            }
            if !session.message.isEmpty, !justFinished {
                Text(session.message)
                    .font(Fonts.caption)
                    .foregroundStyle(Palette.clay)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                speak(item, level: plan.level)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.wave.2.fill")
                    Text("再念一遍")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.jade)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: Dimens.radiusInner, style: .continuous)
                        .fill(Palette.jadeSoft)
                )
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("再念一遍")
        }
    }

    private func tipRow(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(Fonts.caption).foregroundStyle(Palette.ink3)
            Spacer()
            Text(v).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink2)
        }
    }

    private func footer(plan: DictationPlan, session: WriteSession) -> some View {
        HStack(spacing: 12) {
            HanziButton(title: justFinished ? "下一个" : "放弃这个字", kind: .ghost) {
                if justFinished { next(plan) } else { next(plan) }
            }
            Spacer()
        }
    }

    // MARK: - 交互

    private func handle(_ outcome: WriteSession.Outcome, plan: DictationPlan, session: WriteSession) {
        switch outcome {
        case .tooShort, .rejected:
            break
        case .passed:
            break
        case .finished(let score, _):
            plan.record(ch: session.ch, score: score)
            justFinished = true
            // 写完把字露出来，让孩子自己对一眼
            SpareParts.speak(session.ch, rate: app.progress.settings.speechRate)
        }
    }

    private func next(_ plan: DictationPlan) {
        plan.advance()
        if plan.isDone {
            showResult = true
        } else {
            loadCurrent(plan)
        }
    }
}

/// 画布宿主：与描红页同款，单独抽出来避免两处各写一遍手势逻辑。
private struct DictationCanvasHost: View {
    @ObservedObject var session: WriteSession
    let onSubmit: ([Float]) -> Void
    @State private var current: [Float] = []

    var body: some View {
        WriteCanvas(session: session, current: $current, onStrokeEnd: onSubmit)
            .aspectRatio(1, contentMode: .fit)
            .background(
                RoundedRectangle(cornerRadius: Dimens.radiusInner, style: .continuous)
                    .fill(Palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Dimens.radiusInner, style: .continuous)
                    .strokeBorder(Palette.line, lineWidth: 1)
            )
    }
}

/// 听写结果：这一轮写了几个字、平均多少分、得了几个星。
private struct DictationResultSheet: View {
    @ObservedObject var plan: DictationPlan
    let onDone: () -> Void

    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 20) {
            Text("听写完成")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Palette.ink1)

            StarsView(count: plan.stars, size: 30)

            HStack(spacing: 26) {
                stat("写了", "\(plan.scores.count) 个字")
                stat("平均", "\(plan.averageScore ?? 0) 分")
            }

            // 逐字列出得分，家长一眼能看出哪几个字没记住
            VStack(spacing: 0) {
                ForEach(plan.items.filter { plan.scores[$0.ch] != nil }, id: \.ch) { item in
                    HStack {
                        Text(item.ch)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Palette.ink1)
                        Spacer()
                        Text("\(plan.scores[item.ch] ?? 0) 分")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(scoreColor(plan.scores[item.ch] ?? 0))
                    }
                    .padding(.vertical, 9)
                    if item.ch != plan.items.filter({ plan.scores[$0.ch] != nil }).last?.ch {
                        Divider().overlay(Palette.line)
                    }
                }
            }
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: Dimens.radiusInner, style: .continuous)
                    .fill(Palette.card)
            )

            HanziButton(title: "完成", fullWidth: true, action: onDone)
        }
        .padding(24)
        .frame(maxWidth: 460)
        .background(Palette.paper)
        .presentationDetents([.medium, .large])
        .onAppear {
            // 听写的成绩也进描红记录：都是「写」这个能力，没理由分开统计
            for (ch, score) in plan.scores {
                app.progress.saveWrite(ch, score: score)
            }
        }
    }

    private func stat(_ k: String, _ v: String) -> some View {
        VStack(spacing: 4) {
            Text(v).font(.system(size: 19, weight: .bold)).foregroundStyle(Palette.ink1)
            Text(k).font(Fonts.caption).foregroundStyle(Palette.ink3)
        }
    }

    private func scoreColor(_ s: Int) -> Color {
        if s >= 85 { return Palette.jade }
        if s >= 65 { return Palette.amber }
        return Palette.clay
    }
}
