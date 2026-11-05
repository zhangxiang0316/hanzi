import SwiftUI

/// 部首归类浏览，对应小程序 `pages/radical`、Android `RadicalPage`。
///
/// 部首此前只作为「这个字的部首是什么」这道题的答案存在——孩子答对答错，
/// 但从没机会「按部首看一遍字」。归类的价值在横向对比：认识「氵」之后，
/// 看到江、河、湖、海都带三点水，才明白部首是什么意思。
///
/// 字库里 237 个部首分布极不均：口 144 字、扌 138、氵 132，但有 54 个部首
/// 只带 1 个字。所以默认**按字数从多到少**排（逻辑层已排好），冷门部首
/// 排在后面，不至于一进来就被一堆只有 1 个字的部首淹没。
struct RadicalPageView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dynamicTypeSize) private var dt

    private enum Scope { case book, all }

    @State private var scope: Scope = .book
    @State private var sel = ""

    private struct RadicalRow: Identifiable {
        let radical: String
        let count: Int
        let inLib: Bool
        var id: String { radical }
    }

    private var radicals: [RadicalRow] {
        let list = scope == .all
            ? app.repo.allRadicals()
            : app.repo.bookRadicals(app.currentBook)
        return list.map { RadicalRow(radical: $0.radical, count: $0.count, inLib: $0.inLib) }
    }

    private var chars: [String] {
        guard !sel.isEmpty else { return [] }
        return scope == .all
            ? app.repo.allCharsWithRadical(sel)
            : app.repo.charsWithRadical(app.currentBook, sel)
    }

    private var learnedCount: Int {
        chars.filter { app.progress.hasLearned($0) }.count
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    scopeBar
                    radicalGrid
                    result
                }
                .padding(.horizontal, Dimens.pagePad(geo.size.width))
                .padding(.vertical, 18)
                .frame(maxWidth: Dimens.contentMax(geo.size.width))
                .frame(maxWidth: .infinity)
            }
            .background(Palette.paper)
        }
        .navigationTitle("部首归类")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // 进来先选字数最多的那个部首，省得页面一片空白等着点
            if sel.isEmpty { sel = radicals.first?.radical ?? "" }
        }
    }

    // MARK: - 顶部

    private var header: some View {
        // 这里不再渲染 26pt 的「部首归类」大标题。
        // 导航栏已经有同名标题，正文再来一个就是同一句话说两遍，
        // 而且白占掉首屏一整块。Android 和小程序这一页也只有
        // 顶栏标题 + 一行说明。
        HStack(alignment: .firstTextBaseline) {
            Spacer()
            Text("\(radicals.count) 个部首")
                .font(Fonts.caption)
                .foregroundStyle(Palette.ink3)
        }
    }

    /// 本册是「这学期要学哪些部首」，全部是「字库里一共有哪些」
    private var scopeBar: some View {
        HStack(spacing: 8) {
            scopeChip(scope == .book ? "本册（\(app.repo.book(app.currentBook)?.short ?? "")）" : "本册",
                      on: scope == .book) {
                setScope(.book)
            }
            scopeChip("全部字库", on: scope == .all) {
                setScope(.all)
            }
        }
    }

    private func scopeChip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Fonts.s(13, on ? .semibold : .regular, .footnote))
                .foregroundStyle(on ? Color.white : Palette.ink2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Capsule().fill(on ? Palette.jade : Palette.card))
                .overlay(Capsule().strokeBorder(on ? Palette.jade : Palette.line, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .minTapTarget()
    }

    private func setScope(_ s: Scope) {
        guard s != scope else { return }
        scope = s
        // 换范围后原来选中的部首可能不存在了，直接落到新列表第一个
        sel = radicals.first?.radical ?? ""
    }

    // MARK: - 部首格子

    private var radicalGrid: some View {
        // 固定高度 + 内部滚动：237 个部首全铺开会把下面的字推得很远，
        // 家长得滑很久才能看到「选了部首之后有哪些字」。
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: LayoutRules.scaled(54, by: dt.layoutScale)), spacing: 8)],
                spacing: 8
            ) {
                ForEach(radicals) { r in
                    radicalCell(r)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
        .frame(height: LayoutRules.scaled(176, by: dt.layoutScale))
    }

    private func radicalCell(_ r: RadicalRow) -> some View {
        let on = r.radical == sel
        return Button {
            sel = r.radical
        } label: {
            VStack(spacing: 1) {
                Text(r.radical)
                    .font(Fonts.s(17, on ? .semibold : .regular, .body))
                    .foregroundStyle(on ? Palette.jadeDeep : Palette.ink1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("\(r.count)")
                    .font(Fonts.s(9, .regular, .caption2).monospacedDigit())
                    .foregroundStyle(Palette.ink3)
            }
            .frame(maxWidth: .infinity)
            .frame(height: LayoutRules.scaled(50, by: dt.layoutScale))
            .background(
                RoundedRectangle(cornerRadius: Dimens.radiusInner, style: .continuous)
                    .fill(on ? Palette.jadeSoft : Palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Dimens.radiusInner, style: .continuous)
                    .strokeBorder(on ? Palette.jade : Palette.line, lineWidth: on ? 2 : 1)
            )
        }
        .buttonStyle(PressableStyle())
        .measureTapTarget("部首-部首格")
        .accessibilityLabel("\(r.radical) 部，\(r.count) 个字")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: - 结果

    private var result: some View {
        Group {
            if sel.isEmpty {
                EmptyState(emoji: "🧩", title: "本册还没有部首",
                           desc: "换一册，或者切到「全部字库」看看")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(sel) 部")
                            .font(Fonts.s(22, .bold, .title2))
                            .foregroundStyle(Palette.ink1)
                        Text("\(chars.count) 个字" + (learnedCount > 0 ? "，认识 \(learnedCount) 个" : ""))
                            .font(Fonts.caption)
                            .foregroundStyle(Palette.ink3)
                        Spacer()
                    }

                    if chars.isEmpty {
                        EmptyState(emoji: "🪶", title: "这个部首下暂时没有字")
                    } else {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: LayoutRules.scaled(58, by: dt.layoutScale)), spacing: 8)],
                            spacing: 8
                        ) {
                            ForEach(chars, id: \.self) { ch in
                                charTile(ch)
                            }
                        }
                        Text("带绿点的字已经学过；点一个字看笔顺和组词")
                            .font(Fonts.s(10, .regular, .caption2))
                            .foregroundStyle(Palette.ink3)
                            .padding(.top, 2)
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
        }
    }

    private func charTile(_ ch: String) -> some View {
        let learned = app.progress.hasLearned(ch)
        let py = app.repo.meta(ch)?.py ?? ""
        return Button {
            guard app.repo.hasChar(ch) else { return }
            app.push(AppState.CharRoute(ch: ch, lesson: app.repo.meta(ch)?.lesson))
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 1) {
                    Text(ch)
                        .font(Fonts.s(24, .regular, .title3))
                        .foregroundStyle(Palette.ink1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(py)
                        .font(Fonts.s(9, .regular, .caption2))
                        .foregroundStyle(Palette.ink3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity)
                .frame(height: LayoutRules.scaled(60, by: dt.layoutScale))
                .background(
                    RoundedRectangle(cornerRadius: Dimens.radiusInner, style: .continuous)
                        .fill(learned ? Palette.jadeSoft : Palette.cardWarm)
                )

                if learned {
                    Circle()
                        .fill(Palette.jade)
                        .frame(width: 6, height: 6)
                        .padding(7)
                }
            }
        }
        .buttonStyle(PressableStyle())
        .minTapTarget()
        .accessibilityLabel("\(ch)，\(py)\(learned ? "，已学过" : "")")
    }
}
