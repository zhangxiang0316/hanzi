import SwiftUI

/// 词语表浏览，对应小程序 `pages/words`、Android `WordsPage`。
///
/// 1276 条词语此前只在「看拼音选词语」的题目里出现——答对答错，但家长想
/// 帮孩子把这一学期的词过一遍时，没有地方能从头翻。
///
/// ## 只有 2~4 年级有词语
///
/// 一年级课本没有词语表（教材本身就没有），所以选了 1a/1b 时这一册是空的。
/// 这时候不能显示一片空白让人以为坏了，要明确说「这一册课本没有词语表」。
///
/// ## 按册分组而不是一个大长列表
///
/// 一次列 1200 多条，手机要滑很久，而且孩子找不到「我们学到哪了」。
/// 按册分组 + 每册显示进度，家长能直接定位到当前学期。
struct WordsPageView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dynamicTypeSize) private var dt

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    /// 搜索结果上限。搜「一」这种常用字会命中几百条，全铺出来既卡又没法看。
    private let resultLimit = 120

    private var all: [WordEntry] { app.repo.allWords() }

    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    private var results: [WordEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return Array(all.filter { $0.word.contains(q) }.prefix(resultLimit))
    }

    /// 按册分组，只保留有词语的册。顺序跟着 `repo.books` 走（教材顺序）。
    private var groups: [(book: Book, words: [WordEntry])] {
        var byBook: [String: [WordEntry]] = [:]
        for w in all { byBook[w.book, default: []].append(w) }
        return app.repo.books.compactMap { b in
            guard let ws = byBook[b.id], !ws.isEmpty else { return nil }
            return (b, ws)
        }
    }

    private var totalLearned: Int {
        all.filter { wordLearned($0) }.count
    }

    private func wordLearned(_ w: WordEntry) -> Bool {
        w.isLearned { app.progress.hasLearned($0) }
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    searchField
                    if searching {
                        searchResults
                    } else {
                        summary
                        ForEach(groups, id: \.book.id) { g in
                            group(g.book, g.words)
                        }
                        // 一年级没有词语表：要说明白，不能留一片空白
                        if groups.isEmpty {
                            EmptyState(emoji: "📖", title: "还没有任何词语")
                        } else if !groups.contains(where: { $0.book.id == app.currentBook }) {
                            noWordsNotice
                        }
                    }
                }
                .padding(.horizontal, Dimens.pagePad(geo.size.width))
                .padding(.vertical, 16)
                .frame(maxWidth: Dimens.contentMax(geo.size.width))
                .frame(maxWidth: .infinity)
            }
            .background(Palette.paper)
        }
        .navigationTitle("词语表")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 搜索

    /// 家长想查某个字有哪些词，直接搜比一册一册翻快得多。
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(Fonts.s(13, .regular, .footnote))
                .foregroundStyle(Palette.ink3)
            TextField("搜词语，或搜一个字（如「行」）", text: $query)
                .font(Fonts.body)
                .foregroundStyle(Palette.ink1)
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(Fonts.s(14, .regular, .body))
                        .foregroundStyle(Palette.ink3)
                }
                .buttonStyle(.plain)
                .minTapTarget()
                .accessibilityLabel("清空搜索")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Capsule().fill(Palette.card))
        .overlay(Capsule().strokeBorder(Palette.line, lineWidth: 1))
    }

    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("找到 \(results.count) 个词" + (results.count >= resultLimit ? "（只显示前 \(resultLimit) 个）" : ""))
                .font(Fonts.caption)
                .foregroundStyle(Palette.ink3)
                .padding(.leading, 4)

            if results.isEmpty {
                EmptyState(emoji: "🔍", title: "没找到含「\(query.trimmingCharacters(in: .whitespaces))」的词语")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { i, w in
                        row(w, showBook: true)
                        if i < results.count - 1 { HairLine().padding(.leading, 16) }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: Dimens.radiusCard, style: .continuous)
                        .fill(Palette.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Dimens.radiusCard, style: .continuous)
                        .strokeBorder(Palette.line, lineWidth: 1)
                )
            }
        }
    }

    // MARK: - 汇总

    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(totalLearned)")
                    .font(Fonts.s(30, .bold, .largeTitle).monospacedDigit())
                    .foregroundStyle(Palette.jade)
                Text("/ \(all.count) 个词")
                    .font(Fonts.s(13, .regular, .footnote))
                    .foregroundStyle(Palette.ink3)
                Spacer()
                Text(app.repo.book(app.currentBook)?.short ?? "")
                    .font(Fonts.s(11, .semibold, .caption))
                    .foregroundStyle(Palette.jadeDeep)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Palette.jadeSoft))
            }
            Text("一个词里的字都学过，这个词才算学会")
                .font(Fonts.s(10, .regular, .caption2))
                .foregroundStyle(Palette.ink3)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - 分组

    private func group(_ book: Book, _ words: [WordEntry]) -> some View {
        let learned = words.filter { wordLearned($0) }.count
        let current = book.id == app.currentBook
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(book.name)
                    .font(Fonts.s(15, .semibold, .headline))
                    .foregroundStyle(current ? Palette.jadeDeep : Palette.ink2)
                if current {
                    Text("当前")
                        .font(Fonts.s(9, .semibold, .caption2))
                        .foregroundStyle(Palette.jadeDeep)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Palette.jadeSoft))
                }
                Spacer()
                Text("\(learned)/\(words.count)")
                    .font(Fonts.s(11, .regular, .caption).monospacedDigit())
                    .foregroundStyle(Palette.ink3)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(words.enumerated()), id: \.element.id) { i, w in
                    row(w, showBook: false)
                    if i < words.count - 1 { HairLine().padding(.leading, 16) }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: Dimens.radiusCard, style: .continuous)
                    .fill(Palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Dimens.radiusCard, style: .continuous)
                    .strokeBorder(Palette.line, lineWidth: 1)
            )
        }
    }

    private func row(_ w: WordEntry, showBook: Bool) -> some View {
        let learned = wordLearned(w)
        return HStack(spacing: 10) {
            // 每个字单独可点（查读音、看笔顺），但视觉上要像一个词——
            // 间距压紧、字号放大，不是四个互不相干的按钮
            HStack(spacing: 0) {
                ForEach(Array(w.chars.enumerated()), id: \.offset) { _, c in
                    Button {
                        guard app.repo.hasChar(c) else { return }
                        app.push(AppState.CharRoute(ch: c, lesson: w.lesson))
                    } label: {
                        Text(c)
                            .font(Fonts.s(21, .regular, .title3))
                            .foregroundStyle(Palette.ink1)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("\(c)")
                }
            }

            Spacer(minLength: 6)

            Text(showBook
                 ? "\(app.repo.book(w.book)?.short ?? w.book) 第 \(w.lessonNo) 课"
                 : "第 \(w.lessonNo) 课")
                .font(Fonts.s(10, .regular, .caption2).monospacedDigit())
                .foregroundStyle(Palette.ink3)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if w.missing > 0 {
                // 词里有字库外的字：孩子点进去查不到读音，得说明白
                TinyPill(text: "\(w.missing) 字未收录", color: Palette.clay)
            }

            if learned {
                Circle()
                    .fill(Palette.jade)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
    }

    private var noWordsNotice: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "info.circle")
                .font(Fonts.s(13, .regular, .footnote))
                .foregroundStyle(Palette.amber)
            Text("\(app.repo.book(app.currentBook)?.name ?? "这一册")课本没有单独的词语表，从二年级上册开始才有。现在可以先看上面其它册的词语。")
                .font(Fonts.s(12, .regular, .caption))
                .foregroundStyle(Palette.ink2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Dimens.radiusInner, style: .continuous)
                .fill(Palette.amberSoft)
        )
    }
}
