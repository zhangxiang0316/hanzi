import SwiftUI

/// 生字详情：大字 + 逐笔播放 + 笔画表 + 组词 + 朗读。
///
/// iPad 上左右分栏：左边大图和进度，右边可滚动的信息与操作。
/// Android 是单列滚动，屏幕窄只能这么办；iPad 横屏宽度足够，分栏能少滚很多。
struct DetailPageView: View {
    let ch: String
    var lessonId: String?
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var highlight = -1
    @State private var replayToken = 0
    @State private var showNumbers = false
    @State private var stopAfter: Int?

    private var meta: CharMeta? { app.repo.meta(ch) }
    private var strokes: StrokeCodec.CharStrokes? { app.repo.strokes(ch) }
    private var reading: String { app.repo.readingFor(ch, lessonId: lessonId) }

    var body: some View {
        GeometryReader { geo in
            let wide = LayoutRules.detailIsSplit(geo.size.width)
            ScrollView {
                if wide {
                    HStack(alignment: .top, spacing: 24) {
                        leftPane.frame(width: min(geo.size.width * 0.44, 420))
                        rightPane.frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, Dimens.pagePad(geo.size.width))
                    .padding(.vertical, 22)
                    .frame(maxWidth: Dimens.contentMax(geo.size.width) + 500)
                    .frame(maxWidth: .infinity)
                } else {
                    VStack(spacing: 20) {
                        leftPane
                        rightPane
                    }
                    .padding(.horizontal, Dimens.pagePad(geo.size.width))
                    .padding(.vertical, 22)
                    .frame(maxWidth: Dimens.contentMax(geo.size.width))
                    .frame(maxWidth: .infinity)
                }
            }
            .background(Palette.paper)
        }
        .navigationTitle(meta?.py ?? ch)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    SpareParts.speak(ch, rate: app.progress.settings.speechRate)
                } label: {
                    Image(systemName: "speaker.wave.2")
                }
                .accessibilityLabel("朗读这个字")
            }
        }
        .onAppear {
            // 进详情页就算「学了这个字」——与 Android 一致
            if !app.progress.hasLearned(ch) { app.progress.learn(ch) }
            if let meta { app.progress.setLast(lesson: meta.lesson, book: meta.book) }
        }
    }

    // MARK: - 左栏

    private var leftPane: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .topTrailing) {
                HanziPlayerView(
                    ch: ch, strokes: strokes,
                    showGrid: true, showGhost: true,
                    showNumbers: showNumbers, stopAfter: stopAfter
                )
                .id("\(ch)-\(replayToken)-\(showNumbers)-\(stopAfter.map(String.init) ?? "all")")
                .frame(maxWidth: 400, maxHeight: 400)

                if app.progress.writeRecord(ch) != nil {
                    StarsView(count: app.progress.writeRecord(ch)?.stars ?? 0, size: 15)
                        .padding(10)
                }
            }

            HStack(spacing: 10) {
                HanziButton(title: "重播", kind: .secondary) {
                    replayToken += 1
                    stopAfter = nil
                }
                HanziButton(title: showNumbers ? "隐藏序号" : "显示序号", kind: .secondary) {
                    showNumbers.toggle()
                }
            }

            navRow
        }
    }

    /// 上一个字 / 下一个字。用 replace 语义：连翻不用按很多次返回
    private var navRow: some View {
        HStack(spacing: 8) {
            let prev = app.repo.prevInLesson(lessonId, ch)
            let next = app.repo.nextInLesson(lessonId, ch)

            HanziButton(title: "上一个", kind: .ghost) {
                if !prev.isEmpty { app.pushReplacing(AppState.CharRoute(ch: prev, lesson: lessonId)) }
            }
            .disabled(prev.isEmpty)
            .opacity(prev.isEmpty ? 0.3 : 1)

            Spacer()

            HanziButton(title: "描红", fullWidth: false) {
                app.push(AppState.WriteRoute(ch: ch))
            }

            Spacer()

            HanziButton(title: "下一个", kind: .ghost) {
                if !next.isEmpty { app.pushReplacing(AppState.CharRoute(ch: next, lesson: lessonId)) }
            }
            .disabled(next.isEmpty)
            .opacity(next.isEmpty ? 0.3 : 1)
        }
        .frame(maxWidth: 400)
    }

    // MARK: - 右栏

    private var rightPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            titleCard
            strokeTable
            wordsCard
            learnCard
        }
    }

    private var titleCard: some View {
        HanziCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(ch)
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(Palette.ink1)
                    Text(reading)
                        .font(.system(size: 20))
                        .foregroundStyle(Palette.jade)
                    Button {
                        SpareParts.speak(ch, rate: app.progress.settings.speechRate)
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Palette.jade)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }

                if let meta {
                    HStack(spacing: 18) {
                        infoItem("部首", meta.radical)
                        infoItem("笔画", "\(meta.strokes)")
                        infoItem("册次", meta.book.uppercased())
                        infoItem("状态", stageText)
                    }

                    let readings = meta.readings ?? []
                    if readings.count > 1 {
                        HStack(spacing: 6) {
                            Text("多音字")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Palette.amber)
                            Text(readings.map { "\($0.p)（\($0.l)）" }.joined(separator: "  "))
                                .font(Fonts.caption)
                                .foregroundStyle(Palette.ink3)
                        }
                    }
                }
            }
        }
    }

    private var stageText: String {
        let e = app.progress.entry(ch)
        return Srs.stageLabel[Srs.stageOf(e)] ?? "未学"
    }

    private func infoItem(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Palette.ink3)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.ink1)
        }
    }

    /// 笔画表：点一行就在大字上高亮那一笔
    private var strokeTable: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHead("笔顺", trailing: AnyView(
                Text("\(strokes?.count ?? 0) 笔")
                    .font(Fonts.caption).foregroundStyle(Palette.ink3)
            ))

            if let strokes, strokes.count > 0 {
                let cols = [GridItem(.adaptive(minimum: 44), spacing: 8)]
                LazyVGrid(columns: cols, spacing: 8) {
                    ForEach(0..<strokes.count, id: \.self) { i in
                        Button {
                            highlight = (highlight == i) ? -1 : i
                            if highlight == i {
                                stopAfter = i + 1
                                replayToken += 1
                            } else {
                                stopAfter = nil
                            }
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(highlight == i ? Palette.jadeSoft : Palette.cardWarm)
                                StrokeGlyphView(ch: ch, strokes: strokes, strokeIndex: i)
                            }
                            .frame(height: 44)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(highlight == i ? Palette.jade : Palette.line,
                                                  lineWidth: 1)
                            )
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            } else {
                Text("这个字没有笔顺数据")
                    .font(Fonts.bodySmall)
                    .foregroundStyle(Palette.ink3)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Dimens.radiusCard, style: .continuous)
                .fill(Palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Dimens.radiusCard, style: .continuous)
                .strokeBorder(Palette.line, lineWidth: 1)
        )
    }

    private var wordsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHead("组词")
            if let meta, !meta.words.isEmpty {
                FlowRow(spacing: 8) {
                    ForEach(meta.words, id: \.word) { w in
                        Button {
                            SpareParts.speak(w.word, rate: app.progress.settings.speechRate)
                        } label: {
                            HStack(spacing: 5) {
                                Text(w.word)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Palette.ink1)
                                if !w.p.isEmpty {
                                    Text(w.p)
                                        .font(.system(size: 10))
                                        .foregroundStyle(Palette.ink3)
                                }
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Palette.cardWarm))
                            .overlay(Capsule().strokeBorder(Palette.line, lineWidth: 1))
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            } else {
                Text("暂无组词")
                    .font(Fonts.bodySmall)
                    .foregroundStyle(Palette.ink3)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Dimens.radiusCard, style: .continuous)
                .fill(Palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Dimens.radiusCard, style: .continuous)
                .strokeBorder(Palette.line, lineWidth: 1)
        )
    }

    private var learnCard: some View {
        let record = app.progress.writeRecord(ch)
        return HanziCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("我的描红")
                        .font(Fonts.sectionTitle)
                        .foregroundStyle(Palette.ink1)
                    Spacer()
                    if let record {
                        StarsView(count: record.stars, size: 14, animated: false)
                    }
                }
                if let record {
                    Text("最好成绩 \(record.best) 分 · 练了 \(record.tries) 次")
                        .font(Fonts.bodySmall)
                        .foregroundStyle(Palette.ink3)
                } else {
                    Text("还没描过这个字")
                        .font(Fonts.bodySmall)
                        .foregroundStyle(Palette.ink3)
                }

                HanziButton(title: record == nil ? "开始描红" : "再写一遍", fullWidth: true) {
                    app.push(AppState.WriteRoute(ch: ch))
                }
            }
        }
    }
}

/// 单独一笔的小图，用于笔画表
struct StrokeGlyphView: View {
    let ch: String
    let strokes: StrokeCodec.CharStrokes
    let strokeIndex: Int

    var body: some View {
        Canvas { ctx, size in
            let box = min(size.width, size.height) - 8
            let origin = CGPoint(x: (size.width - box) / 2, y: (size.height - box) / 2)
            guard strokeIndex < strokes.strokes.count else { return }
            // 先画其他笔的浅色轮廓做参照，再叠上这一笔
            for i in 0..<strokes.count where i != strokeIndex {
                let p = Path(HanziCanvas.path(for: strokes.strokes[i], box: box, origin: origin))
                ctx.fill(p, with: .color(Palette.line.opacity(0.55)))
            }
            let p = Path(HanziCanvas.path(for: strokes.strokes[strokeIndex], box: box, origin: origin))
            ctx.fill(p, with: .color(Palette.ink1))
        }
    }
}

/// 自动换行的横向排布。SwiftUI 没有内建的 FlowLayout 等价物，
/// 组词数量不定、每个词宽度不同，用 LazyVGrid 会排成整齐的网格反而难看。
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sv.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
