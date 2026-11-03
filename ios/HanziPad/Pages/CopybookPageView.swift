import SwiftUI

/// 我的字帖：把写过的字排成一张字帖。
///
/// 为什么值得单独做一页：现在的徽章体系几乎全是「认识 N 个字」这一个维度，
/// 而 `WriteRecord` 存了 `best / stars / tries / last` 四个字段却只在单字详情页
/// 显示三颗星。「我写了一百个字」和「我认识一百个字」对孩子来说是两回事，
/// 后者是看得懂，前者是写得出来——后者更难，也更值得被看见。
///
/// 没有做成「按拼音排序的列表」：那更像词典，不像自己的成果。
/// 按最近写的在前排，孩子翻开看到的是「我最近在练什么」。
struct CopybookPageView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dynamicTypeSize) private var dt
    @Environment(\.dismiss) private var dismiss

    /// 当前筛选：nil = 全部
    @State private var starFilter: Int?

    private var all: [(ch: String, record: Progress.WriteRecord)] {
        app.progress.allWriteRecords()
    }

    private var shown: [(ch: String, record: Progress.WriteRecord)] {
        guard let f = starFilter else { return all }
        return all.filter { $0.record.stars == f }
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if all.isEmpty {
                        emptyState
                    } else {
                        summaryCard
                        exportCard
                        filterRow
                        grid(geo: geo)
                    }
                }
                .padding(.horizontal, Dimens.pagePad(geo.size.width))
                .padding(.vertical, 22)
                .frame(maxWidth: Dimens.contentMax(geo.size.width))
                .frame(maxWidth: .infinity)
            }
            .background(Palette.paper)
        }
        .navigationTitle("我的字帖")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 导出

    @State private var shareURL: URL?
    @State private var exporting = false
    @State private var exportError: String?

    /// 导出 PDF：打印出来才是真的字帖，孩子拿铅笔在上面描比划屏幕有用
    private var exportCard: some View {
        Button {
            exportPdf()
        } label: {
            HStack(spacing: 12) {
                Text("🖨").font(Fonts.s(22, .regular, .title3, maxScale: 1.4))
                VStack(alignment: .leading, spacing: 3) {
                    Text(exporting ? "正在排版…" : "导出 PDF 字帖")
                        .font(Fonts.s(15, .bold, .body))
                        .foregroundStyle(Palette.jadeDeep)
                    Text("打印出来，A4 一页六个字，可以反复描")
                        .font(Fonts.caption)
                        .foregroundStyle(Palette.ink3)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(Fonts.s(12, .semibold, .caption))
                    .foregroundStyle(Palette.ink3)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: Dimens.radiusInner, style: .continuous)
                    .fill(Palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Dimens.radiusInner, style: .continuous)
                    .strokeBorder(Palette.jade.opacity(0.35), lineWidth: 1)
            )
            .measureTapTarget("字帖-导出")
        }
        .buttonStyle(PressableStyle())
        .disabled(exporting)
        .sheet(item: Binding(
            get: { shareURL.map(ShareItem.init) },
            set: { if $0 == nil { shareURL = nil } }
        )) { item in
            ShareSheet(url: item.url)
        }
        .alert("导出失败", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("好", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    private func exportPdf() {
        let chars = shown.map(\.ch)
        guard !chars.isEmpty else { return }
        exporting = true
        // 笔画数据在 MainActor 上，必须先在主线程取出来，
        // 再拿纯数据结构去后台画（遍历轮廓几百个字会到上百毫秒）
        let strokes: [String: StrokeCodec.CharStrokes] = Dictionary(
            uniqueKeysWithValues: chars.compactMap { ch in
                Repo.shared.strokes(ch).map { (ch, $0) }
            }
        )
        let label = CopybookPDF.dateLabel()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = CopybookPDF.build(
                chars,
                strokeFor: { strokes[$0] },
                dateLabel: label
            )
            guard !result.data.isEmpty else {
                DispatchQueue.main.async {
                    exporting = false
                    exportError = "生成字帖时出错了，再试一次。"
                }
                return
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(CopybookPDF.fileName())
            do {
                try result.data.write(to: url)
                DispatchQueue.main.async {
                    exporting = false
                    shareURL = url
                }
            } catch {
                DispatchQueue.main.async {
                    exporting = false
                    exportError = "保存文件失败：\(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: 14) {
            Text("🖌️").font(Fonts.s(44, .regular, .largeTitle, maxScale: 1.4))
            Text("还没有写过字")
                .font(Fonts.s(17, .bold, .headline))
                .foregroundStyle(Palette.ink1)
            Text("去描红或听写几个字，这里就会有一张你自己的字帖")
                .font(Fonts.caption)
                .foregroundStyle(Palette.ink3)
                .multilineTextAlignment(.center)
            HanziButton(title: "去描红", fullWidth: false) {
                if let first = app.repo.bookChars(app.currentBook).first {
                    app.push(AppState.WriteRoute(ch: first))
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - 汇总

    private var summaryCard: some View {
        let hist = app.progress.writeStarsHistogram()
        let total = app.progress.writeCount
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(total)")
                    .font(Fonts.s(34, .bold, .largeTitle, maxScale: 2.2))
                    .foregroundStyle(Palette.ink1)
                Text("个字写过")
                    .font(Fonts.s(13, .regular, .footnote))
                    .foregroundStyle(Palette.ink3)
                Spacer()
                Text("共 \(app.progress.writeStarsTotal) 颗星")
                    .font(Fonts.s(13, .semibold, .footnote))
                    .foregroundStyle(Palette.amber)
            }

            // 星级分布：一眼看出「写得好的有多少、还需要练的有多少」
            HStack(spacing: 10) {
                ForEach([3, 2, 1, 0], id: \.self) { s in
                    let n = hist[s] ?? 0
                    VStack(spacing: 3) {
                        Text("\(n)")
                            .font(Fonts.s(16, .bold, .body))
                            .foregroundStyle(n > 0 ? starColor(s) : Palette.ink3.opacity(0.4))
                        Text(s == 0 ? "待练" : "\(s) 星")
                            .font(Fonts.s(10, .regular, .caption2))
                            .foregroundStyle(Palette.ink3)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: Dimens.radiusInner, style: .continuous)
                            .fill(Palette.track)
                    )
                }
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

    private func starColor(_ s: Int) -> Color {
        if s >= 3 { return Palette.amber }
        if s == 2 { return Palette.jade }
        if s == 1 { return Palette.sky }
        return Palette.clay
    }

    // MARK: - 筛选

    private var filterRow: some View {
        let hist = app.progress.writeStarsHistogram()
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(title: "全部", count: all.count, value: nil)
                ForEach([3, 2, 1, 0], id: \.self) { s in
                    let n = hist[s] ?? 0
                    if n > 0 {
                        filterChip(title: s == 0 ? "待练" : "\(s) 星", count: n, value: s)
                    }
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private func filterChip(title: String, count: Int, value: Int?) -> some View {
        let on = starFilter == value
        return Button {
            starFilter = value
        } label: {
            HStack(spacing: 5) {
                Text(title)
                    .font(Fonts.s(13, on ? .semibold : .regular, .footnote))
                Text("\(count)")
                    .font(Fonts.s(11, .regular, .caption))
                    .opacity(0.7)
            }
            .foregroundStyle(on ? Color.white : Palette.ink2)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(on ? Palette.jade : Palette.card)
            )
            .overlay(
                Capsule().strokeBorder(on ? Color.clear : Palette.line, lineWidth: 1)
            )
        }
        .buttonStyle(PressableStyle())
        .minTapTarget()
    }

    // MARK: - 字格

    private func grid(geo: GeometryProxy) -> some View {
        // 复用首页生字卡的列宽规则，保证不同设备上密度一致
        let cols = LayoutRules.columns(
            width: min(geo.size.width, Dimens.contentMax(geo.size.width))
                - Dimens.pagePad(geo.size.width) * 2,
            minimum: LayoutRules.charTileMin,
            spacing: 12
        )
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: max(2, cols)),  // cols 已按字号收窄
            spacing: 12
        ) {
            ForEach(shown, id: \.ch) { item in
                Button {
                    app.push(AppState.WriteRoute(ch: item.ch))
                } label: {
                    tile(ch: item.ch, record: item.record)
                }
                .buttonStyle(PressableStyle())
                .measureTapTarget("字帖-字格")
            }
        }
    }

    private func tile(ch: String, record: Progress.WriteRecord) -> some View {
        VStack(spacing: 5) {
            HanziView(ch: ch, strokes: app.repo.strokes(ch), showGhost: false)
                .frame(width: LayoutRules.scaled(46, by: dt.layoutScale),
                       height: LayoutRules.scaled(46, by: dt.layoutScale))
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    Text("★")
                        .font(Fonts.s(9, .regular, .caption2))
                        .foregroundStyle(i < record.stars ? Palette.amber : Palette.track)
                }
            }
            Text("\(record.best) 分")
                .font(Fonts.s(10, .semibold, .caption2))
                .foregroundStyle(scoreColor(record.best))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Dimens.radiusInner, style: .continuous)
                .fill(Palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Dimens.radiusInner, style: .continuous)
                .strokeBorder(Palette.line, lineWidth: 1)
        )
    }

    private func scoreColor(_ s: Int) -> Color {
        if s >= 85 { return Palette.jade }
        if s >= 65 { return Palette.amber }
        return Palette.clay
    }
}

/// 分享用的包装。`sheet(item:)` 需要一个 Identifiable。
private struct ShareItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }

    init(_ url: URL) { self.url = url }
}

/// 系统分享面板。
///
/// 不直接用 `ShareLink`：它要求 iOS 16+，而我们的部署目标是 17——本来够用，
/// 但 `ShareLink` 没法在「文件刚写完」这个时机弹出，只能作为常驻按钮。
/// 用 UIActivityViewController 可以在导出完成后立刻弹，交互更顺。
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
