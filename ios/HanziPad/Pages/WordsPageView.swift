import SwiftUI

/// 词语表浏览，对应小程序 `pages/words`、Android `WordsPage`。
///
/// 词语此前只在「看拼音选词语」的题目里出现——答对答错，但家长想帮孩子把
/// 这一学期的词过一遍时，没有地方能从头翻。
///
/// ## 复用 `Logic/Words.swift`，不另写一套遍历
///
/// 那边已经处理了一件容易漏的事：**一年级课本没有词语表**，它用每课生字的
/// 第一组词补上（`derived == true`）。另写一份遍历必然把这个兜底漏掉，
/// 结果就是一年级点进词语表看到一片空白——而一年级正是这个 App 最大的用户群。
///
/// 所以这里直接用 `bookWordEntries` / `uniqueWords`，页面只负责分组和排版。
/// 派生词要标出来，不能让家长以为那是课本上的词。
///
/// ## 两个去重粒度
///
/// 按册浏览按**册内**去重（「旅行」在 1b 和 3a 各显示一次，是教材事实）；
/// 搜索和总数按**全局**去重（否则搜「行」会列出两条「旅行」）。
struct WordsPageView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dynamicTypeSize) private var dt

    @State private var query = ""

    /// 搜索结果上限。搜「一」这种常用字会命中几百条，全铺出来既卡又没法看。
    private let resultLimit = 120

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    private var searching: Bool { !trimmedQuery.isEmpty }

    private var found: [WordEntry] {
        app.repo.wordsWithChar(trimmedQuery)
    }

    private var results: [WordEntry] { Array(found.prefix(resultLimit)) }

    /// 按册分组，只保留有词语的册。顺序跟着 `repo.books` 走（教材顺序）。
    private var groups: [(book: Book, words: [WordEntry])] {
        app.repo.books.compactMap { b in
            let ws = app.repo.bookWordEntries(b.id)
            return ws.isEmpty ? nil : (b, ws)
        }
    }

    private var learnedTotal: Int {
        app.repo.uniqueWords().filter { wordLearned($0) }.count
    }

    private func wordLearned(_ w: WordEntry) -> Bool {
        w.isLearned { app.progress.hasLearned($0) }
    }

    private func bookNames(_ ids: [String]) -> String {
        ids.map { app.repo.book($0)?.name ?? $0 }.joined(separator: " / ")
    }

    private func lessonNo(_ w: WordEntry) -> Int {
        app.repo.lesson(w.lesson)?.no ?? 0
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
                        if groups.isEmpty {
                            EmptyState(emoji: "📖", title: "还没有任何词语")
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
        .measureTapTarget("词语表-搜索框")
    }

    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(found.count > results.count
                 ? "找到 \(found.count) 个词，先显示前 \(results.count) 个"
                 : "找到 \(found.count) 个词")
                .font(Fonts.caption)
                .foregroundStyle(Palette.ink3)
                .padding(.leading, 4)

            if results.isEmpty {
                EmptyState(emoji: "🔍", title: "没找到含「\(trimmedQuery)」的词语")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { i, w in
                        row(w, meta: bookNames(w.books))
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
        let unique = app.repo.uniqueWords().count
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(learnedTotal)")
                    .font(Fonts.s(30, .bold, .largeTitle).monospacedDigit())
                    .foregroundStyle(Palette.jade)
                Text("/ \(unique) 个词")
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
        let derivedCount = words.filter(\.derived).count
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

            // 有的课文课本没给词语表，就用生字的组词补上。一册里可能**混合**
            // （2a 就是），所以不能只看 every 就下「这一册没有词语表」的结论，
            // 要报出数量。
            if derivedCount > 0 {
                groupNote(derivedCount == words.count
                          ? "这一册课本没有词语表，下面是每课生字的组词"
                          : "其中 \(derivedCount) 个是生字组词（课本这几课没有词语表）")
            }

            VStack(spacing: 0) {
                ForEach(Array(words.enumerated()), id: \.element.id) { i, w in
                    row(w, meta: "第 \(lessonNo(w)) 课")
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

    private func groupNote(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "info.circle")
                .font(Fonts.s(11, .regular, .caption))
                .foregroundStyle(Palette.amber)
            Text(text)
                .font(Fonts.s(11, .regular, .caption))
                .foregroundStyle(Palette.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
    }

    // MARK: - 一行一个词

    private func row(_ w: WordEntry, meta: String) -> some View {
        let learned = wordLearned(w)
        return HStack(spacing: 8) {
            // 每个字单独可点（查读音、看笔顺），但视觉上要像一个词——
            // 间距压紧、字号放大，不是几个互不相干的按钮
            HStack(spacing: 0) {
                ForEach(Array(w.chars.enumerated()), id: \.offset) { _, c in
                    charButton(c, lesson: w.lesson)
                }
            }

            Spacer(minLength: 4)

            if w.derived {
                // 派生词不是课本上的词，必须标出来
                Text("生字组词")
                    .font(Fonts.s(9, .regular, .caption2))
                    .foregroundStyle(Palette.ink3)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Palette.track))
            }

            Text(meta)
                .font(Fonts.s(10, .regular, .caption2).monospacedDigit())
                .foregroundStyle(Palette.ink3)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if learned {
                Circle()
                    .fill(Palette.jade)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .frame(minHeight: 44)
        .measureTapTarget("词语表-词行")
    }

    /// 一个可点的字。
    ///
    /// 派生词里有少数用到字库外的字（「弓弩」的弩、「镜匣」的匣），
    /// 那些字没有详情页。必须置灰且**不可点**——留着 44pt 的点击区却点不出
    /// 东西，比看起来不能点更糟。
    @ViewBuilder
    private func charButton(_ c: String, lesson: String) -> some View {
        let tappable = app.repo.hasChar(c)
        if tappable {
            Button {
                app.push(AppState.CharRoute(ch: c, lesson: lesson))
            } label: {
                Text(c)
                    .font(Fonts.s(21, .regular, .title3))
                    .foregroundStyle(Palette.ink1)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            // 21pt 的字加 3pt 内边距只有 ~33x27，远不到 44。逐字点击是这个页面
            // 的主交互（点字查读音/笔顺），必须撑到触达线
            .minTapTarget()
            .measureTapTarget("词语表-单字")
            .accessibilityLabel(c)
        } else {
            Text(c)
                .font(Fonts.s(21, .regular, .title3))
                .foregroundStyle(Palette.ink3.opacity(0.45))
                .padding(.horizontal, 3)
                .padding(.vertical, 3)
                .accessibilityLabel("\(c)，未收录")
        }
    }
}
