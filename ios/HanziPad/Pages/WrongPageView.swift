import SwiftUI

/// 错题本：按错误次数排序，可以练一遍或清掉。
struct WrongPageView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if app.progress.wrongCount == 0 {
                        EmptyState(emoji: "🌟", title: "还没有错题",
                                   desc: "做练习时答错的字会收进这里")
                    } else {
                        list
                        HanziButton(title: "练一遍错题", fullWidth: true) {
                            app.push(AppState.QuizPayload(mode: "wrong",
                                                          book: app.currentBook, lesson: nil))
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
        .navigationTitle("错题本")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if app.progress.wrongCount > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("清空", role: .destructive) {
                        app.progress.clearWrong()
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text("错题本")
                .font(Fonts.pageTitle)
                .foregroundStyle(Palette.ink1)
            Spacer()
            TinyPill(text: "\(app.progress.wrongCount) 个字", color: Palette.clay)
        }
    }

    private var list: some View {
        VStack(spacing: 10) {
            ForEach(app.progress.wrongList, id: \.ch) { item in
                row(item)
            }
        }
    }

    private func row(_ item: Progress.WrongItem) -> some View {
        let meta = app.repo.meta(item.ch)
        return HStack(spacing: 14) {
            HanziView(ch: item.ch, strokes: app.repo.strokes(item.ch),
                      showGrid: false, showGhost: false)
                .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(item.ch)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Palette.ink1)
                    if let meta {
                        Text(meta.py)
                            .font(Fonts.bodySmall)
                            .foregroundStyle(Palette.jade)
                    }
                }
                Text("错 \(item.n) 次" + (meta.map { " · 部首「\($0.radical)」" } ?? ""))
                    .font(Fonts.caption)
                    .foregroundStyle(Palette.ink3)
            }

            Spacer()

            Button {
                app.push(AppState.CharRoute(ch: item.ch, lesson: item.lesson))
            } label: {
                Text("看看")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.jade)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Palette.jadeSoft))
            }
            .buttonStyle(PressableStyle())

            Button {
                app.progress.clearWrong(item.ch)
            } label: {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(Palette.ink3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("从错题本移除「\(item.ch)」")
        }
        .padding(14)
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
