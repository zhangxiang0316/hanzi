import SwiftUI

/// 学习周报（家长报告），对应小程序 `pages/report`、Android `ReportPage`。
///
/// 首页告诉你「今天学了几个字」，这一页告诉你「这一周怎么样」——后者才是
/// 家长真正关心的粒度。数据全部来自 `Progress` 里已经攒着的逐日统计，
/// 不新增任何存储；口径（哪些天算活跃、没答题时正确率怎么显示）都在
/// `Logic/Report.swift`，那部分是纯函数、有测试，这里只负责排版。
struct ReportPageView: View {
    @Environment(AppState.self) private var app

    /// 每次重算都很便宜（7 条），而且 Progress 是 @Observable，
    /// 学完一个字回来这一页会自己刷新。
    private var report: Report.Result {
        Report.build(app.progress.dayStats)
    }

    var body: some View {
        let r = report
        return GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    head(r)
                    chart(r.week)
                    stats(r.sum)
                    sectionTitle("每天")
                    dayList(r.week)
                    sectionTitle("给家长")
                    adviceList(r.advice)
                    footNote
                }
                .padding(.horizontal, Dimens.pagePad(geo.size.width))
                .padding(.vertical, 18)
                .frame(maxWidth: Dimens.contentMax(geo.size.width))
                .frame(maxWidth: .infinity)
            }
            .background(Palette.paper)
        }
        .navigationTitle("学习周报")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 顶部结论

    private func head(_ r: Report.Result) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(DayUtil.dateLabel() + " · " + DayUtil.weekdayCN())
                .font(Fonts.caption)
                .foregroundStyle(Palette.ink3)
            Text("最近 7 天")
                .font(Fonts.s(24, .bold, .title2))
                .foregroundStyle(Palette.ink1)
            // 家长翻周报先扫结论；数字是佐证，不该是第一眼看到的东西。
            // 措辞只描述「做了什么」，不评价孩子。
            Text(verdict(r.sum))
                .font(Fonts.s(16, .semibold, .body))
                .foregroundStyle(toneColor(verdictTone(r.sum)))
            Text(r.headline)
                .font(Fonts.bodySmall)
                .foregroundStyle(Palette.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6)
        .padding(.horizontal, 4)
    }

    private func verdict(_ sum: Report.Summary) -> String {
        if sum.empty { return "这周还没有学习记录" }
        var parts: [String] = []
        if sum.learned > 0 { parts.append("认识 \(sum.learned) 个字") }
        if sum.answers > 0 { parts.append("答题 \(sum.answers) 道") }
        if sum.activeDays > 0 { parts.append("来了 \(sum.activeDays) 天") }
        return "这周" + parts.joined(separator: "，")
    }

    /// 结论的语气。和 `Report.advice` 用同一套 Tone，颜色映射只写一处。
    private func verdictTone(_ sum: Report.Summary) -> Report.Tone {
        if sum.empty { return .plain }
        if sum.activeDays >= 5 && (sum.accuracy == nil || sum.accuracy! >= 80) { return .good }
        if sum.activeDays <= 2 { return .tip }
        return .plain
    }

    private func toneColor(_ tone: Report.Tone) -> Color {
        switch tone {
        case .good: return Palette.jade
        case .tip: return Palette.clay
        case .plain: return Palette.ink2
        }
    }

    // MARK: - 柱状图

    private func chart(_ week: [Report.Day]) -> some View {
        VStack(spacing: 10) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(week, id: \.key) { d in
                    VStack(spacing: 4) {
                        // 没学的那天不写 0，留白更干净
                        Text(d.learned > 0 ? "\(d.learned)" : " ")
                            .font(Fonts.s(9, .regular, .caption2).monospacedDigit())
                            .foregroundStyle(Palette.ink3)
                            .frame(height: 13)

                        GeometryReader { g in
                            VStack(spacing: 0) {
                                Spacer(minLength: 0)
                                if d.active {
                                    // 高度比例在逻辑层算好，这里只管画
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(d.daysAgo == 0 ? Palette.jade : Palette.jadeSoft)
                                        .frame(height: max(3, g.size.height * d.ratio))
                                } else {
                                    // 没学的那天保留一条底边：表示「这一天存在，但是空的」
                                    Capsule()
                                        .fill(Palette.track)
                                        .frame(height: 3)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .bottom)
                        }
                        .frame(height: 128)

                        Text(d.weekday)
                            .font(Fonts.s(11, d.daysAgo == 0 ? .semibold : .regular, .caption))
                            .foregroundStyle(d.daysAgo == 0 ? Palette.jade : Palette.ink3)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Text("柱子上面的数字是当天认识的字")
                .font(Fonts.s(10, .regular, .caption2))
                .foregroundStyle(Palette.ink3)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Dimens.radiusCard, style: .continuous)
                .fill(Palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Dimens.radiusCard, style: .continuous)
                .strokeBorder(Palette.line, lineWidth: 1)
        )
    }

    // MARK: - 四个指标

    private func stats(_ sum: Report.Summary) -> some View {
        HStack(spacing: 0) {
            statCell("\(sum.learned)", "认识的字")
            statCell("\(sum.answers)", "答题数")
            statCell(sum.accuracy.map { "\($0)" } ?? "—",
                     sum.accuracy == nil ? "没答题" : "正确率 %")
            statCell("\(sum.activeDays)", "学了几天")
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Dimens.radiusCard, style: .continuous)
                .fill(Palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Dimens.radiusCard, style: .continuous)
                .strokeBorder(Palette.line, lineWidth: 1)
        )
    }

    private func statCell(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(Fonts.s(23, .bold, .title2).monospacedDigit())
                .foregroundStyle(Palette.ink1)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(Fonts.s(10, .regular, .caption2))
                .foregroundStyle(Palette.ink3)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 逐日明细

    private func sectionTitle(_ s: String) -> some View {
        Text(s)
            .font(Fonts.s(14, .semibold, .subheadline))
            .foregroundStyle(Palette.ink2)
            .padding(.leading, 4)
            .padding(.top, 4)
    }

    private func dayList(_ week: [Report.Day]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(week.enumerated()), id: \.element.key) { i, d in
                dayRow(d)
                if i < week.count - 1 {
                    HairLine().padding(.leading, 16)
                }
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

    private func dayRow(_ d: Report.Day) -> some View {
        HStack(spacing: 12) {
            Text(d.daysAgo == 0 ? "今天" : (d.daysAgo == 1 ? "昨天" : d.weekday))
                .font(Fonts.s(13, d.daysAgo == 0 ? .semibold : .regular, .footnote))
                .foregroundStyle(d.daysAgo == 0 ? Palette.jade : Palette.ink2)
                .frame(width: 44, alignment: .leading)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(d.learned) 字")
                    .font(Fonts.s(14, .regular, .subheadline).monospacedDigit())
                    .foregroundStyle(d.learned > 0 ? Palette.ink1 : Palette.ink3)
                Text(d.answers > 0 ? "\(d.answers) 题" : "没答题")
                    .font(Fonts.s(10, .regular, .caption2))
                    .foregroundStyle(Palette.ink3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(d.accuracy.map { "\($0)%" } ?? "—")
                .font(Fonts.s(13, .regular, .footnote).monospacedDigit())
                .foregroundStyle(d.active ? Palette.ink2 : Palette.ink3)
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(minHeight: 44)
    }

    // MARK: - 建议

    private func adviceList(_ advice: [Report.Advice]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(advice.enumerated()), id: \.offset) { i, a in
                HStack(alignment: .top, spacing: 9) {
                    Circle()
                        .fill(toneColor(a.tone))
                        .frame(width: 6, height: 6)
                        .padding(.top, 7)
                    Text(a.text)
                        .font(Fonts.s(13, .regular, .footnote))
                        .foregroundStyle(Palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                if i < advice.count - 1 {
                    HairLine().padding(.leading, 31)
                }
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

    private var footNote: some View {
        Text("周报统计最近 7 个自然日（含今天），不是周一到周日——滚动 7 天任何时候打开都有内容，不会周一早上看到一片空白。")
            .font(Fonts.s(10, .regular, .caption2))
            .foregroundStyle(Palette.ink3)
            .lineSpacing(3)
            .padding(.horizontal, 4)
            .padding(.top, 6)
            .padding(.bottom, 12)
    }
}
