import SwiftUI

/// 单元列表：一册的所有单元 + 每单元下的课文。
///
/// Android 是「单元页 → 课文页」两级；iPad 内容栏高得多，直接摊平成一页，
/// 少一次跳转，也更容易看清整册结构。
struct UnitPageView: View {
    let book: String
    @Environment(AppState.self) private var app

    private var bookModel: Book? { app.repo.book(book) }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if let bookModel {
                        ForEach(bookModel.units, id: \.no) { unit in
                            unitCard(unit)
                        }
                    }
                }
                .padding(.horizontal, Dimens.pagePad(geo.size.width))
                .padding(.vertical, 22)
                .frame(maxWidth: Dimens.contentMax(geo.size.width))
                .frame(maxWidth: .infinity)
            }
            .background(Palette.paper)
        }
        .navigationTitle(bookModel.map { "\(BookNaming.gradeName($0.grade))\(BookNaming.termName($0.term))" } ?? "课本")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        let bp = Plan.bookProgress(app.progress, book)
        let color = Palette.bookColor(book)
        return HanziCard {
            HStack(spacing: 18) {
                ProgressRing(value: Double(bp.learned) / Double(max(bp.total, 1)),
                             color: color, size: 72)
                    .overlay(
                        Text("\(bp.pct)%")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(color)
                    )
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(bp.learned) / \(bp.total) 字")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.ink1)
                    Text("已掌握 \(bp.mastered) 字" + (bp.due > 0 ? " · 待复习 \(bp.due) 字" : ""))
                        .font(Fonts.bodySmall)
                        .foregroundStyle(Palette.ink3)
                    if let next = Plan.findContinue(app.progress, book) {
                        Text("接着学：\(next.title)")
                            .font(Fonts.caption)
                            .foregroundStyle(color)
                    }
                }
                Spacer()
            }
        }
    }

    private func unitCard(_ unit: Unit) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("第 \(unit.no) 单元")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Palette.ink2)
                if !unit.theme.isEmpty {
                    Text(unit.theme)
                        .font(Fonts.caption)
                        .foregroundStyle(Palette.ink3)
                }
                Spacer()
            }

            VStack(spacing: 0) {
                ForEach(Array(unit.lessons.enumerated()), id: \.element) { i, lessonId in
                    if i > 0 { HairLine() }
                    lessonRow(lessonId)
                }
            }
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

    private func lessonRow(_ lessonId: String) -> some View {
        let c = Plan.countLesson(app.progress, lessonId)
        let lesson = app.repo.lesson(lessonId)
        let done = c.total > 0 && c.rest == 0

        return Button {
            app.push(AppState.LessonRoute(id: lessonId))
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(done ? Palette.jadeSoft : Palette.track)
                        .frame(width: 32, height: 32)
                    if done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Palette.jade)
                    } else {
                        Text("\(lesson?.no ?? 0)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.ink2)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(lesson?.title ?? lessonId)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Palette.ink1)
                    Text("\(c.total) 字 · 已学 \(c.learned)")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.ink3)
                }

                Spacer()

                if c.learned > 0 && c.rest > 0 {
                    TinyPill(text: "\(c.learned)/\(c.total)", color: Palette.amber)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.ink3)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}
