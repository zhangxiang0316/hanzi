import SwiftUI

/// 选字做字帖，对应小程序 `pages/copybook-pick`、Android `CopybookPickPage`。
///
/// 「我的字帖」只能导**写过的字**。但家长真实的用法是：
/// 「把这课的生字打一张」「把错题打一张」「把三颗星以下的打一张」——
/// 这些都不是「我写过的」，而是「我需要练的」。
///
/// 和小程序不同，iOS 的笔画数据整包在 app 里，任何字都画得出来，所以
/// 这里不做「能不能导」的置灰，选中的字全都能进 PDF。
struct CopybookPickPageView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dynamicTypeSize) private var dt

    // MARK: - 来源勾选

    @State private var srcWrong = true
    @State private var srcWeak = false
    @State private var srcLesson = true
    @State private var srcStars = false
    @State private var starLevel = 2

    /// 当前选中要导出的课时。nil 表示还没初始化（进页面时落到本册第一课）
    @State private var lessonId: String?
    /// nil = 全选（默认）；非 nil 时是一份显式选择
    @State private var selected: Set<String>?

    @State private var shareURL: URL?
    @State private var exporting = false
    @State private var exportError: String?

    private var bookName: String {
        app.repo.book(app.currentBook)?.short ?? ""
    }

    private var lessons: [Lesson] {
        (app.repo.book(app.currentBook)?.lessons ?? []).compactMap { app.repo.lesson($0) }
    }

    private var currentLessonLabel: String {
        guard let id = lessonId else { return "本册第一课" }
        return app.repo.lessonLabel(id)
    }

    /// 当前来源组合下选出来的字。所有计算都在 `Logic/CopybookPick.swift`，
    /// 这里只把进度和课时喂进去。
    private var result: CopybookPick.BuildResult {
        let stars: Int? = srcStars ? starLevel : nil
        return CopybookPick.build(
            lessonChars: srcLesson ? app.repo.lessonChars(lessonId) : [],
            records: app.progress.allWriteRecords().map {
                CopybookPick.Record(ch: $0.ch, stars: $0.record.stars)
            },
            wrongChars: srcWrong ? app.progress.wrongList.map(\.ch) : [],
            weakChars: srcWeak ? app.progress.weakChars().map(\.ch) : [],
            stars: stars
        )
    }

    /// 当前选中的字。`selected == nil` 表示全选，且永远跟着候选集走。
    private var chosen: Set<String> {
        let all = Set(result.items.map(\.ch))
        guard let s = selected else { return all }
        return s.intersection(all)
    }

    var body: some View {
        let r = result
        let on = chosen
        return GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    sourceBar
                    if srcStars { starRow }
                    if srcLesson { lessonPicker }
                    countBar(r)
                    grid(r, on: on)
                    if r.items.isEmpty {
                        EmptyState(emoji: "🗂", title: "这几个来源里没有字",
                                   desc: "换一个来源，或者先学几个字再来")
                    }
                }
                .padding(.horizontal, Dimens.pagePad(geo.size.width))
                .padding(.vertical, 16)
                .frame(maxWidth: Dimens.contentMax(geo.size.width))
                .frame(maxWidth: .infinity)
            }
            .background(Palette.paper)
        }
        .safeAreaInset(edge: .bottom) {
            // 主操作固定底部：一屏几十个字，按钮跟着内容滚走等于每次都要找
            VStack(spacing: 0) {
                HanziButton(
                    title: exporting ? "正在排版…" : "导出字帖（\(chosen.count) 个字）",
                    fullWidth: true,
                    enabled: !chosen.isEmpty && !exporting
                ) {
                    export()
                }
                .measureTapTarget("选字字帖-导出")
                .padding(.horizontal, Dimens.pagePad(0))
                .padding(.vertical, 10)
            }
            .background(Palette.paper)
        }
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
        .navigationTitle("选字做字帖")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: setupLesson)
    }

    // MARK: - 初始化

    /// 默认选本册第一课：家长最常打的就是「这课的生字」。
    ///
    /// 课时 id 从「本册第一个字的首现课时」反查，而不是取 book.lessons.first：
    /// 后者是单元里的课时顺序，教材第一课可能是识字课，未必收了这个字；
    /// 小程序用的也是这条路径。
    private func setupLesson() {
        guard lessonId == nil else { return }
        if let first = app.repo.bookChars(app.currentBook).first {
            let lid = app.repo.lessonOfChar(first)
            lessonId = lid.isEmpty ? lessons.first?.id : lid
        } else {
            lessonId = lessons.first?.id
        }
    }

    // MARK: - 来源

    private var sourceBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                sourceChip("错题本", on: srcWrong) { srcWrong.toggle() }
                sourceChip("笔画弱", on: srcWeak) { srcWeak.toggle() }
                sourceChip("本课生字", on: srcLesson) { srcLesson.toggle() }
                sourceChip("低分字", on: srcStars) { srcStars.toggle() }
            }
            .padding(.horizontal, 1)
        }
    }

    private func sourceChip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Fonts.s(14, on ? .semibold : .regular, .subheadline))
                .foregroundStyle(on ? Color.white : Palette.ink2)
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(Capsule().fill(on ? Palette.jade : Palette.card))
                .overlay(Capsule().strokeBorder(on ? Palette.jade : Palette.line, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .minTapTarget()
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var starRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("几颗星以下")
                .font(Fonts.s(10, .regular, .caption2))
                .foregroundStyle(Palette.ink3)
            HStack(spacing: 8) {
                ForEach([0, 1, 2], id: \.self) { n in
                    Button {
                        starLevel = n
                    } label: {
                        Text("\(n) 星及以下")
                            .font(Fonts.s(13, starLevel == n ? .semibold : .regular, .footnote))
                            .foregroundStyle(starLevel == n ? Palette.jadeDeep : Palette.ink2)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                Capsule().fill(starLevel == n ? Palette.jadeSoft : Palette.card)
                            )
                            .overlay(
                                Capsule().strokeBorder(starLevel == n ? Palette.jade : Palette.line,
                                                       lineWidth: 1)
                            )
                    }
                    .buttonStyle(PressableStyle())
                    .minTapTarget()
                }
            }
        }
    }

    /// 换一课。
    ///
    /// 小程序页里 `onPickLesson` 存在但没有界面上的人口，结果「本课生字」永远
    /// 只能打第一课。这里补上一个下拉，让「按课时挑字」真的可用。
    private var lessonPicker: some View {
        Menu {
            ForEach(lessons) { l in
                Button {
                    lessonId = l.id
                    // 换课等于换一批字，保留上一课的勾选只会导出不想要的字
                    selected = nil
                } label: {
                    if l.id == lessonId {
                        Label(app.repo.lessonLabel(l.id), systemImage: "checkmark")
                    } else {
                        Text(app.repo.lessonLabel(l.id))
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text("本课")
                    .font(Fonts.s(10, .regular, .caption2))
                    .foregroundStyle(Palette.ink3)
                Text(currentLessonLabel)
                    .font(Fonts.s(12, .medium, .caption))
                    .foregroundStyle(Palette.jadeDeep)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(Fonts.s(9, .semibold, .caption2))
                    .foregroundStyle(Palette.ink3)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Palette.card))
            .overlay(Capsule().strokeBorder(Palette.line, lineWidth: 1))
        }
        .measureTapTarget("选字字帖-换课")
    }

    // MARK: - 选中条

    private func countBar(_ r: CopybookPick.BuildResult) -> some View {
        HStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("已选")
                    .font(Fonts.s(13, .regular, .footnote))
                    .foregroundStyle(Palette.ink2)
                Text("\(chosen.count)")
                    .font(Fonts.s(18, .bold, .headline).monospacedDigit())
                    .foregroundStyle(Palette.jade)
                Text("个字")
                    .font(Fonts.s(13, .regular, .footnote))
                    .foregroundStyle(Palette.ink2)
            }
            Spacer()
            Button("全选") { selected = nil }
                .font(Fonts.s(13, .semibold, .footnote))
                .foregroundStyle(Palette.jadeDeep)
                .minTapTarget()
                .disabled(r.items.isEmpty)
            Button("清空") { selected = [] }
                .font(Fonts.s(13, .semibold, .footnote))
                .foregroundStyle(Palette.ink2)
                .minTapTarget()
                .disabled(chosen.isEmpty)
        }
        .padding(.vertical, 2)
    }

    // MARK: - 字格

    private func grid(_ r: CopybookPick.BuildResult, on: Set<String>) -> some View {
        // 每个字格子至少 ~74pt：字要够大看得清，同时保证 44pt 的触达线
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: LayoutRules.scaled(78, by: dt.layoutScale)), spacing: 10)],
            spacing: 10
        ) {
            ForEach(r.items, id: \.ch) { it in
                cell(it, selected: on.contains(it.ch))
            }
        }
    }

    private func cell(_ it: CopybookPick.Item, selected: Bool) -> some View {
        Button {
            var s = chosen
            if s.contains(it.ch) { s.remove(it.ch) } else { s.insert(it.ch) }
            self.selected = s
        } label: {
            VStack(spacing: 5) {
                Text(it.ch)
                    .font(Fonts.s(30, .regular, .title2))
                    .foregroundStyle(Palette.ink1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(it.fromText)
                    .font(Fonts.s(9, .regular, .caption2))
                    .foregroundStyle(Palette.ink3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .frame(height: LayoutRules.scaled(78, by: dt.layoutScale))
            .background(
                RoundedRectangle(cornerRadius: Dimens.radiusInner, style: .continuous)
                    .fill(selected ? Palette.jadeSoft : Palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Dimens.radiusInner, style: .continuous)
                    .strokeBorder(selected ? Palette.jade : Palette.line,
                                  lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(it.ch)，\(it.fromText)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - 导出

    private func export() {
        let chars = result.items.map(\.ch).filter { chosen.contains($0) }
        guard !chars.isEmpty else { return }
        exporting = true

        // 笔画数据在 MainActor 上，必须先在主线程取出来，
        // 再拿纯数据结构去后台画（遍历轮廓几百个字会到上百毫秒）
        let strokes: [String: StrokeCodec.CharStrokes] = Dictionary(
            uniqueKeysWithValues: chars.compactMap { ch in
                app.repo.strokes(ch).map { (ch, $0) }
            }
        )
        let label = CopybookPDF.dateLabel()
        let name = CopybookPDF.fileName("字帖")
        DispatchQueue.global(qos: .userInitiated).async {
            let out = CopybookPDF.build(chars, strokeFor: { strokes[$0] }, dateLabel: label)
            guard !out.data.isEmpty else {
                DispatchQueue.main.async {
                    exporting = false
                    exportError = "生成字帖时出错了，再试一次。"
                }
                return
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            do {
                try out.data.write(to: url)
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
}
