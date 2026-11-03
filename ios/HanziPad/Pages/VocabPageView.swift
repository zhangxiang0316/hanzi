import SwiftUI

/// 识字量测试，对应小程序 `pages/vocab`、Android `VocabPage`。
///
/// 三步同页切换（`stage`）：开始页 → 逐题作答 → 结果页。
/// 不用三个路由：这是个一次性流程，来回跳只会让孩子误触返回键卡在中间态。
struct VocabPageView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dynamicTypeSize) private var dt
    @Environment(\.dismiss) private var dismiss

    private enum Stage { case intro, test, result }

    @State private var stage: Stage = .intro
    @State private var test: Vocab.Test?
    @State private var answers: [Bool] = []
    @State private var qIndex = 0
    @State private var picked: String?
    @State private var result: Vocab.Estimate?

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch stage {
                    case .intro:
                        intro
                    case .test:
                        if let t = test {
                            testStage(t)
                        } else {
                            intro
                        }
                    case .result:
                        if let e = result {
                            resultStage(e)
                        } else {
                            intro
                        }
                    }
                }
                .padding(.horizontal, Dimens.pagePad(geo.size.width))
                .padding(.vertical, 24)
                .frame(maxWidth: Dimens.contentMax(geo.size.width))
                .frame(maxWidth: .infinity)
            }
            .background(Palette.paper)
        }
        // 主操作固定在底部：一个「开始测」按钮跟着内容浮在屏幕中间，
        // 看着像忘了排版，手指也不容易够到
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                switch stage {
                case .intro:
                    HanziButton(title: "开始测", fullWidth: true) { start() }
                        .measureTapTarget("识字量-开始")
                case .result:
                    HanziButton(title: "再测一次", fullWidth: true) { start() }
                        .measureTapTarget("识字量-再测")
                    HanziButton(title: "回到我的", kind: .secondary, fullWidth: true) { dismiss() }
                case .test:
                    EmptyView()
                }
            }
            .padding(.horizontal, Dimens.pagePad(0))
            .padding(.vertical, 12)
            .background(Palette.paper)
        }
        .navigationTitle("识字量测试")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 开始页

    private var intro: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: 10) {
                Text("📏").font(Fonts.s(48, .regular, .largeTitle, maxScale: 1.4))
                Text("测测认识多少字")
                    .font(Fonts.s(23, .bold, .title3))
                    .foregroundStyle(Palette.ink1)
                Text("从八册里各抽几个字，看看认字量大概到哪儿了")
                    .font(Fonts.bodySmall)
                    .foregroundStyle(Palette.ink3)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            HanziCard {
                VStack(alignment: .leading, spacing: 10) {
                    bullet("最多 40 个字，两三分钟")
                    bullet("答不出来很正常，不会的字直接跳过")
                    bullet("结果是估算，不是精确值")
                }
            }

        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("·").font(Fonts.bodySmall).foregroundStyle(Palette.jade)
            Text(text).font(Fonts.bodySmall).foregroundStyle(Palette.ink2)
            Spacer()
        }
    }

    // MARK: - 答题

    private func testStage(_ t: Vocab.Test) -> some View {
        let q = t.questions[qIndex]
        // Quiz.Question 没有册次字段（它给普通练习用），从分组里反查
        let group = t.groups.last { $0.start <= qIndex }
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: Double(qIndex), total: Double(t.total))
                    .tint(Palette.jade)
                Text("\(qIndex + 1) / \(t.total) · \(group?.name ?? "")")
                    .font(Fonts.caption)
                    .foregroundStyle(Palette.ink3)
            }

            HanziCard {
                Text(q.prompt)
                    .font(.system(size: LayoutRules.scaled(96, by: dt.layoutScale), weight: .regular))
                    .foregroundStyle(Palette.ink1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    // 字要够大：这是测「认不认识这个字」，看不清就等于不认识
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }

            // 一行两个，四个选项两行——和微信版一致
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 10) {
                ForEach(q.options, id: \.value) { o in
                    optionButton(o, q: q)
                }
            }

            Text("会读就选，不会就随便选一个，后面还会继续")
                .font(Fonts.caption)
                .foregroundStyle(Palette.ink3)
                .frame(maxWidth: .infinity)
        }
    }

    private func optionButton(_ o: Quiz.Option, q: Quiz.Question) -> some View {
        let state: String = {
            guard picked != nil else { return "" }
            if o.value == q.answer { return "right" }
            if o.value == picked { return "wrong" }
            return ""
        }()
        let bg: Color = state == "right" ? Palette.jadeSoft
            : state == "wrong" ? Palette.claySoft : Palette.card
        let border: Color = state == "right" ? Palette.jade
            : state == "wrong" ? Palette.clay : Palette.line
        let fg: Color = state == "right" ? Palette.jadeDeep
            : state == "wrong" ? Palette.clay : Palette.ink1
        return Button {
            answer(o.value, in: q)
        } label: {
            Text(o.label)
                .font(Fonts.s(17, state == "right" ? .bold : .regular, .body))
                .foregroundStyle(fg)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(RoundedRectangle(cornerRadius: 14).fill(bg))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(border, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .disabled(picked != nil)
        .measureTapTarget("识字量-选项-\(o.label)")
    }

    // MARK: - 结果

    private func resultStage(_ e: Vocab.Estimate) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: 6) {
                Text("估算认识").font(Fonts.caption).foregroundStyle(Palette.ink3)
                Text(Vocab.sizeLabel(e.size))
                    .font(Fonts.s(54, .bold, .largeTitle))
                    .foregroundStyle(Palette.jadeDeep)
                Text("个字").font(Fonts.caption).foregroundStyle(Palette.ink3)
                Text(Vocab.verdict(e.size))
                    .font(Fonts.bodySmall)
                    .foregroundStyle(Palette.ink2)
                    .multilineTextAlignment(.center)
                let stop = e.groups.first { $0.book == e.stopBook }
                Text(stop.map { "到\($0.name)就停下来了，后面的册次还没学到" } ?? "八册都测完了")
                    .font(Fonts.caption)
                    .foregroundStyle(Palette.ink3)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            HanziCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("各册情况")
                        .font(Fonts.s(13, .bold, .body))
                        .foregroundStyle(Palette.ink1)
                    ForEach(e.groups.filter { $0.asked > 0 }, id: \.book) { g in
                        HStack {
                            Text(g.name).font(Fonts.bodySmall).foregroundStyle(Palette.ink2)
                            Spacer()
                            Text("\(g.correct) / \(g.asked)")
                                .font(Fonts.bodySmall)
                                .foregroundStyle(Palette.ink1)
                            Text(g.contribution > 0 ? "+\(g.contribution)" : "不计")
                                .font(Fonts.caption)
                                .foregroundStyle(g.contribution > 0 ? Palette.jadeDeep : Palette.ink3)
                                .frame(width: 56, alignment: .trailing)
                        }
                    }
                }
            }

        }
    }

    // MARK: - 逻辑

    private func start() {
        // 每次开测用新 seed：反复测同一套题，孩子会把答案背下来
        test = Vocab.buildTest()
        answers = []
        qIndex = 0
        picked = nil
        result = nil
        stage = .test
    }

    private func answer(_ v: String, in q: Quiz.Question) {
        guard picked == nil, let t = test else { return }
        picked = v
        answers.append(v == q.answer)

        // 答错也立刻往下走：这是测验不是练习，孩子没有第二次机会
        let i = qIndex + 1
        // 一册问完就判一次要不要停：正确率过低的册次之后不必再问，
        // 问下去只是让孩子反复受挫
        if let g = t.groups.first(where: { $0.start + $0.questions.count == i }) {
            let est = Vocab.estimate(t, answers: answers)
            if let gs = est.groups.first(where: { $0.book == g.book }),
               gs.asked >= g.questions.count, gs.rate < Vocab.stopRate {
                finish(t, answers)
                return
            }
        }
        if i >= t.total {
            finish(t, answers)
            return
        }
        qIndex = i
        picked = nil
    }

    private func finish(_ t: Vocab.Test, _ ans: [Bool]) {
        let est = Vocab.estimate(t, answers: ans)
        result = est
        // 记一笔：家长在「我的」里也能看到上次测出来多少
        app.progress.setVocabSize(est.size)
        stage = .result
    }
}
