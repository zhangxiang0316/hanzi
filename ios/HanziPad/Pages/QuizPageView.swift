import SwiftUI

/// 答题页：五类题型 + 即时反馈。
///
/// iPad 上题干、选项、进度条一屏放得下，不需要滚动——
/// 这是相对 Android 手机版最明显的体验提升：孩子不用一边滑动一边答题。
struct QuizPageView: View {
    let payload: AppState.QuizPayload
    @Environment(AppState.self) private var app
    /// 辅助功能字号下选项一律单列：两列时汉字的字号被挤到看不清
    @Environment(\.dynamicTypeSize) private var dt
    @Environment(\.dismiss) private var dismiss

    @State private var questions: [Quiz.Question] = []
    @State private var targets: [String] = []
    @State private var index = 0
    @State private var correct = 0
    @State private var wrongChars: [String] = []
    @State private var picked: String?
    @State private var revealed = false
    @State private var finishedPayload: AppState.ResultPayload?

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                progressHeader(geo.size.width)
                if questions.isEmpty {
                    Spacer()
                    EmptyState(emoji: "🎉", title: "没有可以练习的字",
                               desc: "先去学几个新字吧")
                    Spacer()
                } else if index < questions.count {
                    questionBody(geo)
                } else {
                    Spacer()
                    EmptyState(emoji: "✅", title: "答完了", desc: "看看结果吧")
                    Spacer()
                }
            }
            .background(Palette.paper)
        }
        .navigationTitle("练习")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("退出") { dismiss() }
            }
        }
        .onAppear(perform: build)
        .onChange(of: index) { _, _ in
            if index >= questions.count && !questions.isEmpty { finish() }
        }
        .navigationDestination(item: $finishedPayload) { p in
            ResultPageView(payload: p)
        }
    }

    // MARK: - 构建题目

    private func build() {
        guard questions.isEmpty else { return }

        // 词语模式的题源是课本词语表，和生字表无关，走单独的构建函数
        if payload.mode == "words" {
            let r = Quiz.buildWordQuiz(repo: app.repo, book: payload.book,
                                       lesson: payload.lesson,
                                       count: 10, seed: UInt32(Date().timeIntervalSince1970))
            questions = r.questions
            targets = r.targets
            dumpIfRequested()
            return
        }

        let session: Plan.Session
        switch payload.mode {
        case "lesson":
            session = Plan.buildSession(mode: "lesson", prog: app.progress,
                                        book: payload.book, lesson: payload.lesson)
        case "review":
            session = Plan.buildSession(mode: "review", prog: app.progress, book: payload.book)
        case "wrong":
            session = Plan.buildSession(mode: "wrong", prog: app.progress, book: payload.book)
        case "polyphone":
            session = Plan.buildSession(mode: "polyphone", prog: app.progress, book: payload.book)
        case "homophone":
            session = Plan.buildSession(mode: "homophone", prog: app.progress, book: payload.book)
        case "radical":
            session = Plan.buildSession(mode: "radical", prog: app.progress, book: payload.book)
        case "similar":
            session = Plan.buildSession(mode: "similar", prog: app.progress, book: payload.book)
        default:
            session = Plan.buildSession(mode: "free", prog: app.progress, book: payload.book)
        }

        // 多音字模式只出多音字题；其余模式用默认题型轮转
        let types: [String]? = session.mode == "polyphone" ? ["polyphone"]
            : session.mode == "homophone" ? ["homophone"]
            : session.mode == "radical" ? ["radical"]
            : session.mode == "similar" ? ["similar"] : nil
        let r = Quiz.build(chars: session.chars, book: payload.book,
                           lesson: payload.lesson, count: session.count, types: types)
        questions = r.questions
        targets = r.targets
        dumpIfRequested()
    }

    /// 自检：把生成的题目落盘，用于核对「三端是否出同一套题」。
    /// 沙箱里没法注入点击，光看截图判断题目内容不可靠。
    private func dumpIfRequested() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-dumpQuestions") {
            let lines = questions.map { q in
                "\(q.type)\t\(q.ch)\t\(q.prompt)\t\(q.sub)\t答:\(q.answer)\t选:\(q.options.map(\.value).joined(separator: "|"))"
            }
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("questions.txt")
            try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        }
        #endif
    }

    // MARK: - 头部

    private func progressHeader(_ width: CGFloat) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text("第 \(min(index + 1, questions.count)) / \(questions.count) 题")
                    .font(Fonts.s(13, .semibold, .footnote))
                    .foregroundStyle(Palette.ink2)
                Spacer()
                Text("答对 \(correct)")
                    .font(Fonts.s(13, .semibold, .footnote))
                    .foregroundStyle(Palette.jade)
            }
            ProgressBar(
                value: questions.isEmpty ? 0 : Double(index) / Double(questions.count),
                height: 6
            )
        }
        .padding(.horizontal, Dimens.pagePad(width))
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: - 题干与选项

    private func questionBody(_ geo: GeometryProxy) -> some View {
        let q = questions[index]
        let wide = LayoutRules.detailIsSplit(geo.size.width, scale: dt.layoutScale)

        return ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 10) {
                    Text(q.title)
                        .font(Fonts.s(15, .semibold, .body))
                        .foregroundStyle(Palette.ink2)

                    promptView(q)

                    Text(q.sub)
                        .font(Fonts.bodySmall)
                        .foregroundStyle(Palette.ink3)
                }
                .padding(.top, 10)

                LazyVGrid(
                    // 辅助功能字号下一律单列。两列时每个选项只剩一半宽度，
                    // 系统字号能到 3 倍，汉字会被压到看不出结构——这题就废了。
                    columns: wide && !dt.isAccessibility
                        ? [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
                        : [GridItem(.flexible())],
                    spacing: 12
                ) {
                    ForEach(q.options, id: \.value) { opt in
                        optionButton(q, opt)
                    }
                }
                .frame(maxWidth: 640)

                if revealed {
                    feedback(q)
                }
            }
            .padding(.horizontal, Dimens.pagePad(geo.size.width))
            .padding(.bottom, 30)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func promptView(_ q: Quiz.Question) -> some View {
        switch q.promptKind {
        case "pinyin":
            Text(q.prompt)
                .font(Fonts.s(46, .medium, .largeTitle, maxScale: 2.2))
                .foregroundStyle(Palette.jadeDeep)
                .padding(.vertical, 6)
        case "char":
            // 题干是汉字时用笔画轮廓画，字重和笔形跟其他页面一致
            HanziView(ch: q.prompt, strokes: app.repo.strokes(q.prompt),
                      showGrid: false, showGhost: false)
                // 汉字是笔画画出来的，不跟字号走，得手动跟着长
                .frame(width: LayoutRules.scaled(130, by: dt.layoutScale, cap: 1.8),
                       height: LayoutRules.scaled(130, by: dt.layoutScale, cap: 1.8))
        default:
            Text(q.prompt)
                .font(Fonts.s(40, .medium, .largeTitle, maxScale: 2.2))
                .foregroundStyle(Palette.ink1)
                .padding(.vertical, 6)
        }
    }

    private func optionButton(_ q: Quiz.Question, _ opt: Quiz.Option) -> some View {
        let isPicked = picked == opt.value
        let isAnswer = opt.value == q.answer
        var border: Color = Palette.edge
        var fill: Color = Palette.card
        if revealed {
            if isAnswer {
                border = Palette.jade
                fill = Palette.jadeSoft
            } else if isPicked {
                border = Palette.clay
                fill = Palette.claySoft
            }
        } else if isPicked {
            border = Palette.jade
            fill = Palette.jadeSoft
        }

        return Button {
            choose(q, opt)
        } label: {
            HStack {
                if q.type == "strokeCount" {
                    Text(opt.label)
                        .font(Fonts.s(17, .medium, .headline))
                        .foregroundStyle(Palette.ink1)
                } else if opt.value.count == 1, isHanzi(opt.value) {
                    HanziView(ch: opt.value, strokes: app.repo.strokes(opt.value),
                              showGrid: false, showGhost: false,
                              inkColor: Palette.ink1)
                        .frame(width: LayoutRules.scaled(42, by: dt.layoutScale),
                               height: LayoutRules.scaled(42, by: dt.layoutScale))
                    Text(opt.label)
                        .font(Fonts.s(17, .medium, .headline))
                        .foregroundStyle(Palette.ink1)
                } else {
                    Text(opt.label)
                        .font(Fonts.s(17, .medium, .headline))
                        .foregroundStyle(Palette.ink1)
                }
                Spacer()
                if revealed && isAnswer {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Palette.jade)
                } else if revealed && isPicked {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Palette.clay)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .measureTapTarget("答题-选项")
            .background(
                RoundedRectangle(cornerRadius: Dimens.radiusInner, style: .continuous)
                    .fill(fill)
                    // 阴影是第二重提示：即使边框在低对比度屏幕上糊掉，
                    // 卡片浮起来的样子也能让人看出这是可以点的
                    .shadow(color: Palette.ink1.opacity(0.06), radius: 3, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Dimens.radiusInner, style: .continuous)
                    .strokeBorder(border, lineWidth: isPicked ? 2 : 1.2)
            )
        }
        .buttonStyle(PressableStyle())
        .disabled(revealed)
    }

    private func isHanzi(_ s: String) -> Bool {
        guard let scalar = s.unicodeScalars.first, s.unicodeScalars.count == 1 else { return false }
        return (0x4E00...0x9FFF).contains(scalar.value)
    }

    private func feedback(_ q: Quiz.Question) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: picked == q.answer ? "checkmark.seal.fill" : "info.circle.fill")
                    .foregroundStyle(picked == q.answer ? Palette.jade : Palette.amber)
                Text(picked == q.answer ? "答对了！" : "答案是「\(q.answer)」")
                    .font(Fonts.s(15, .semibold, .body))
                    .foregroundStyle(Palette.ink1)
                Spacer()
            }
            Text(q.explain)
                .font(Fonts.bodySmall)
                .foregroundStyle(Palette.ink2)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                Button {
                    SpareParts.speak(q.ch, rate: app.progress.settings.speechRate)
                } label: {
                    Label("听一听", systemImage: "speaker.wave.2")
                        .font(Fonts.bodySmall)
                }
                .buttonStyle(.bordered)
                .tint(Palette.jade)
                .controlSize(.small)

                Spacer()

                HanziButton(title: index + 1 < questions.count ? "下一题" : "看结果") {
                    advance()
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Dimens.radiusInner, style: .continuous)
                .fill(picked == q.answer ? Palette.jadeSoft : Palette.amberSoft)
        )
        .frame(maxWidth: 640)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: - 交互

    private func choose(_ q: Quiz.Question, _ opt: Quiz.Option) {
        guard !revealed else { return }
        picked = opt.value
        let ok = opt.value == q.answer
        if ok {
            correct += 1
        }
        // 词语题的 ch 是整词，错题本和 SRS 都按单字组织——
        // 拆成字反而更符合学习逻辑：词写错了，落点是其中某个字。
        let gradeChars = q.ch.count > 1 && app.repo.meta(q.ch) == nil
            ? q.ch.map(String.init).filter { app.repo.meta($0) != nil }
            : [q.ch]
        if !ok {
            for ch in gradeChars where !wrongChars.contains(ch) {
                wrongChars.append(ch)
            }
        }
        // 记进 SRS 和错题本
        for ch in gradeChars {
            app.progress.grade(ch, correct: ok, lesson: q.lesson)
        }
        withAnimation(.easeOut(duration: 0.2)) { revealed = true }

        // 答对了自动进下一题，答错则停留让人看清解析。
        // 手动点"下一题"对答错的情况更友好——孩子需要时间读解析。
        if ok {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
                if revealed { advance() }
            }
        }
    }

    private func advance() {
        guard revealed else { return }
        picked = nil
        revealed = false
        index += 1
    }

    private func finish() {
        guard finishedPayload == nil, !questions.isEmpty else { return }
        app.progress.recordQuiz(total: questions.count, correct: correct)
        finishedPayload = AppState.ResultPayload(
            correct: correct, total: questions.count,
            wrong: wrongChars, mode: payload.mode, book: payload.book
        )
    }
}
