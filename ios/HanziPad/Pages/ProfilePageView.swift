import SwiftUI

/// 我的：学习概览 + 徽章 + 设置。
///
/// 勋章这块按用户反馈做过一次调整（Android v1.0.1「我的徽章太大了」）：
/// 用自适应网格 + 紧凑卡片，iPad 上会铺成 4-6 列，不会每屏只看到四五个。
struct ProfilePageView: View {
    @Environment(AppState.self) private var app
    /// 只在需要按字号收窄网格/控件的地方读它
    @Environment(\.dynamicTypeSize) private var dt

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    profileSection
                    statsGrid
                    studyLinks
                    badgeSection
                    settingsSection
                }
                .padding(.horizontal, Dimens.pagePad(geo.size.width))
                .padding(.vertical, 24)
                .frame(maxWidth: Dimens.contentMax(geo.size.width))
                .frame(maxWidth: .infinity)
            }
            .background(Palette.paper)
        }
        .navigationTitle("我的")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(colors: [Palette.jade, Palette.jadeDeep],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 66, height: 66)
                Text("🌱").font(Fonts.s(30, .regular, .largeTitle, maxScale: 1.4))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(app.profiles.active.name)
                    .font(Fonts.s(19, .bold, .title3))
                    .foregroundStyle(Palette.ink1)
                Text("已连续学习 \(app.progress.streak) 天")
                    .font(Fonts.bodySmall)
                    .foregroundStyle(Palette.ink3)
            }
            Spacer()
        }
    }

    // MARK: - 孩子

    @State private var showAddProfile = false
    @State private var showRenameProfile = false
    @State private var showRemoveProfile = false
    @State private var nameDraft = ""

    /// 多孩子档案：一间屋里两个孩子共用一个 iPad 是常态，
    /// 数据必须分开，否则弟弟写几个字就把哥哥的进度搅乱了。
    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHead("孩子", trailing: AnyView(
                Text(app.profiles.count > 1 ? "各用各的进度" : "")
                    .font(Fonts.caption).foregroundStyle(Palette.ink3)
            ))
            HanziCard {
                VStack(alignment: .leading, spacing: 12) {
                    // 最多 4 个档案 + 一个「＋」。用自适应网格而不是固定 HStack：
                    // 辅助功能字号下名字会长到放不下，硬排会截断。
                    let cols = [GridItem(.adaptive(minimum: LayoutRules.scaled(84, by: dt.layoutScale)),
                                         spacing: 8)]
                    LazyVGrid(columns: cols, // alignment 默认 .center
                              alignment: .leading, spacing: 8) {
                        ForEach(app.profiles.list) { pf in
                            let on = pf.id == app.profiles.activeId
                            Button {
                                switchTo(pf.id)
                            } label: {
                                Text(pf.name)
                                    .font(Fonts.bodySmall)
                                    .fontWeight(on ? .bold : .regular)
                                    .foregroundStyle(on ? Color.white : Palette.ink2)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .frame(maxWidth: .infinity)
                                    // 11pt 上下内边距实测只有 38pt 高，不到 44 的触达线；
                                    // 14pt 刚好 44+，与小程序 20rpx(45px) 对齐
                                    .padding(.vertical, 14)
                                    .background(
                                        Capsule().fill(on ? Palette.jade : Palette.cardWarm)
                                    )
                                    .overlay(
                                        Capsule().strokeBorder(on ? Palette.jade : Palette.line, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(PressableStyle())
                            .measureTapTarget("档案-\(pf.name)")
                        }
                        if app.profiles.canAdd {
                            Button {
                                nameDraft = ""
                                showAddProfile = true
                            } label: {
                                Text("＋")
                                    .font(Fonts.bodySmall)
                                    .foregroundStyle(Palette.ink3)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Capsule().fill(Palette.card))
                                    .overlay(Capsule().strokeBorder(Palette.line, lineWidth: 1))
                            }
                            .buttonStyle(PressableStyle())
                            .measureTapTarget("档案-添加")
                        }
                    }
                    if app.profiles.count > 1 {
                        HStack(spacing: 20) {
                            Button("改名") {
                                nameDraft = app.profiles.active.name
                                showRenameProfile = true
                            }
                            .font(Fonts.caption)
                            .foregroundStyle(Palette.ink2)
                            .measureTapTarget("档案-改名")
                            Button("删除这个孩子") {
                                showRemoveProfile = true
                            }
                            .font(Fonts.caption)
                            .foregroundStyle(Palette.clay)
                            .measureTapTarget("档案-删除")
                            Spacer()
                        }
                    }
                }
            }
        }
        .alert("添加一个孩子", isPresented: $showAddProfile) {
            TextField("名字（8 字以内）", text: $nameDraft)
            Button("取消", role: .cancel) { }
            Button("确定") {
                if let p = app.profiles.add(nameDraft) {
                    // 新建后直接切过去：家长的意图就是「给这个孩子开始用」
                    switchTo(p.id)
                }
            }
        } message: {
            Text("每个孩子各有一份学习进度。")
        }
        .alert("改名", isPresented: $showRenameProfile) {
            TextField("名字（8 字以内）", text: $nameDraft)
            Button("取消", role: .cancel) { }
            Button("确定") { app.profiles.rename(app.profiles.activeId, nameDraft) }
        }
        .alert("删除「\(app.profiles.active.name)」？", isPresented: $showRemoveProfile) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                if let next = app.profiles.remove(app.profiles.activeId) {
                    _ = next
                    app.progress.reload()
                    app.currentBook = app.repo.defaultBook()
                }
            }
        } message: {
            Text("这个孩子的学习进度、错题本、描红记录都会一起删掉，不能恢复。")
        }
    }

    /// 切换孩子。
    ///
    /// 切完必须 `progress.reload()`——存储的命名空间变了，但 Progress 里那份
    /// 内存状态还是上一个孩子的，不重读会显示「名字换了、数据没变」。
    /// 册次也要跟着重读：每个孩子可能读不同册。
    private func switchTo(_ id: String) {
        guard app.profiles.setActive(id) else { return }
        app.progress.reload()
        // 册次也要跟着重读：每个孩子可能读不同册。
        // 必须**先** reload 再读 settings，否则读到的是上一个孩子的册次。
        app.currentBook = app.progress.settings.book
    }

    private var statsGrid: some View {
        let learned = app.progress.totalLearned
        let mastered = app.progress.totalMastered
        let stars = app.progress.writeStarsTotal
        let days = app.progress.activeDays

        return LazyVGrid(columns: [GridItem(.adaptive(minimum: LayoutRules.scaled(130, by: dt.layoutScale)), spacing: 12)],
                         spacing: 12) {
            statCard("认识", "\(learned)", "个字", Palette.jade)
            statCard("掌握", "\(mastered)", "个字", Palette.amber)
            statCard("描红", "\(stars)", "颗星", Palette.clay)
            statCard("学习", "\(days)", "天", Palette.bookColor("2b"))
        }
    }

    private func statCard(_ title: String, _ value: String,
                          _ unit: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(Fonts.s(11, .regular, .caption))
                .foregroundStyle(Palette.ink3)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(Fonts.s(24, .bold, .title2))
                    .foregroundStyle(color)
                Text(unit)
                    .font(Fonts.s(11, .regular, .caption))
                    .foregroundStyle(Palette.ink3)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Dimens.radiusInner, style: .continuous)
                .fill(Palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Dimens.radiusInner, style: .continuous)
                .strokeBorder(Palette.line, lineWidth: 1)
        )
    }

    private var badgeSection: some View {
        let badges = app.progress.badges()
        let got = badges.filter(\.got).count

        return VStack(alignment: .leading, spacing: 12) {
            SectionHead("我的徽章", trailing: AnyView(
                Text("\(got) / \(badges.count)")
                    .font(Fonts.caption).foregroundStyle(Palette.ink3)
            ))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: LayoutRules.scaled(96, by: dt.layoutScale)), spacing: 10)],
                      spacing: 10) {
                ForEach(badges, id: \.id) { b in
                    badgeCell(b)
                }
            }
        }
    }

    private func badgeCell(_ b: Progress.Badge) -> some View {
        VStack(spacing: 5) {
            Text(b.emoji)
                .font(Fonts.s(24, .regular, .title2))
                .grayscale(b.got ? 0 : 1)
                .opacity(b.got ? 1 : 0.35)
            Text(b.name)
                .font(Fonts.s(11, .semibold, .caption))
                .foregroundStyle(b.got ? Palette.ink1 : Palette.ink3)
                .lineLimit(dt.isAccessibility ? 2 : 1)
                .minimumScaleFactor(0.75)
            Text(b.desc)
                .font(Fonts.s(9, .regular, .caption2))
                .foregroundStyle(Palette.ink3)
                .lineLimit(dt.isAccessibility ? 4 : 2)
                .multilineTextAlignment(.center)
                // 原来写死 24pt，字号一放大两行字就被裁掉下半截；
                // 改成 minHeight，默认字号下高度不变，放大时自己长
                .frame(minHeight: 24)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Dimens.radiusInner, style: .continuous)
                .fill(b.got ? Palette.amberSoft : Palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Dimens.radiusInner, style: .continuous)
                .strokeBorder(b.got ? Palette.amber.opacity(0.5) : Palette.line, lineWidth: 1)
        )
    }

    /// 学习入口。
    ///
    /// iPad 上错题本在侧边栏里单独一栏，手机上没有侧边栏，所以收进「我的」——
    /// 和 Android `ProfilePage.kt:272` 的 LinkRow 一致。
    ///
    /// 这几行的顺序是照「家长一天里会想做的事」排的：先看这一周怎么样，
    /// 再查认识多少字，然后是错题、字帖、按部首/按册翻字。关于和清空收在
    /// 最后——它们不是日常动作，混在前面只会让人误触。
    private var studyLinks: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHead("学习")

            // 周报：首页只看得到「今天」，家长关心的是「这一周」
            linkRow(icon: "chart.bar.doc.horizontal",
                    tint: Palette.jade,
                    title: "学习周报",
                    subtitle: nil,
                    trailing: "最近 7 天",
                    trailingColor: Palette.ink3,
                    tapName: "我的-周报入口") {
                app.push(AppState.ReportRoute())
            }

            // 识字量测试：「学过多少字」是点过多少个字，不是认识多少，
            // 家长真正想知道的是后者，所以按抽测单独给一个入口。
            linkRow(icon: "ruler",
                    tint: Palette.jade,
                    title: "识字量测试",
                    subtitle: "从八册各抽几个字，估算认字量",
                    trailing: app.progress.vocabSize > 0
                        ? "上次 \(Vocab.sizeLabel(app.progress.vocabSize)) 字"
                        : "测一测",
                    trailingColor: Palette.ink3,
                    tapName: "我的-识字量入口") {
                app.push(AppState.VocabRoute())
            }

            linkRow(icon: "exclamationmark.bubble",
                    tint: app.progress.wrongCount > 0 ? Palette.clay : Palette.ink3,
                    title: "错题本",
                    subtitle: nil,
                    trailing: app.progress.wrongCount > 0
                        ? "\(app.progress.wrongCount) 个字"
                        : "还没有错字",
                    trailingColor: app.progress.wrongCount > 0 ? Palette.clay : Palette.ink3,
                    tapName: "我的-错题本入口") {
                app.push(AppState.WrongRoute())
            }

            // 字帖：写出来的字和认得的字是两种能力，值得单独有一个入口。
            // 徽章体系几乎全是「认识 N 个字」，写字这个维度此前只有单字详情页里的三颗星。
            linkRow(icon: "square.grid.2x2",
                    tint: app.progress.writeCount > 0 ? Palette.jade : Palette.ink3,
                    title: "我的字帖",
                    subtitle: nil,
                    trailing: app.progress.writeCount > 0
                        ? "\(app.progress.writeCount) 个字"
                        : "还没写过",
                    trailingColor: app.progress.writeCount > 0 ? Palette.jade : Palette.ink3,
                    tapName: "我的-字帖入口") {
                app.push(AppState.CopybookRoute())
            }

            // 选字做字帖：「我的字帖」只能导写过的字，而家长想打的是
            // 「这课的生字」「错题」，那是两种不同的集合。
            linkRow(icon: "square.and.pencil",
                    tint: Palette.jade,
                    title: "选字做字帖",
                    subtitle: "按课时 / 错题挑字",
                    trailing: nil,
                    trailingColor: Palette.ink3,
                    tapName: "我的-选字字帖入口") {
                app.push(AppState.CopybookPickRoute())
            }

            // 部首与词语：两种「换个角度看字」的浏览方式
            linkRow(icon: "square.grid.3x3",
                    tint: Palette.clay,
                    title: "部首归类",
                    subtitle: "按部首看字",
                    trailing: nil,
                    trailingColor: Palette.ink3,
                    tapName: "我的-部首入口") {
                app.push(AppState.RadicalRoute())
            }

            linkRow(icon: "text.book.closed",
                    tint: Palette.sky,
                    title: "词语表",
                    subtitle: "按册翻词语",
                    trailing: nil,
                    trailingColor: Palette.ink3,
                    tapName: "我的-词语表入口") {
                app.push(AppState.WordsRoute())
            }

            linkRow(icon: "info.circle",
                    tint: Palette.ink3,
                    title: "关于与数据来源",
                    subtitle: nil,
                    trailing: AppInfo.version,
                    trailingColor: Palette.ink3,
                    tapName: "我的-关于入口") {
                app.push(AppState.AboutRoute())
            }

            // 清空：破坏性操作放最后，且要二次确认——孩子误触一下就把
            // 整学期的进度没了，这种代价不该靠「反正能重学」来兜
            Button {
                showReset = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "trash")
                        .font(Fonts.s(15, .medium, .body))
                        .foregroundStyle(Palette.clay)
                        .frame(width: LayoutRules.scaled(22, by: dt.layoutScale))
                    Text("清空学习记录")
                        .font(Fonts.body)
                        .foregroundStyle(Palette.clay)
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
                        .strokeBorder(Palette.line, lineWidth: 1)
                )
                .measureTapTarget("我的-清空记录")
            }
            .buttonStyle(PressableStyle())
        }
        .alert("清空学习记录？", isPresented: $showReset) {
            Button("取消", role: .cancel) { }
            Button("确定清空", role: .destructive) { app.progress.resetAll() }
        } message: {
            Text("所有学习进度、错题和描红记录都会被删除，且无法恢复。")
        }
    }

    @State private var showReset = false

    /// 一行入口。
    ///
    /// 抽成一个函数而不是复制九遍：这九行的内边距、边框、chevron 必须完全一致，
    /// 复制粘贴的下一步必然是某一行的 padding 少两格，触达高度掉到 44 以下。
    private func linkRow(icon: String, tint: Color, title: String, subtitle: String?,
                         trailing: String?, trailingColor: Color, tapName: String,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(Fonts.s(15, .medium, .body))
                    .foregroundStyle(tint)
                    .frame(width: LayoutRules.scaled(22, by: dt.layoutScale))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Fonts.body).foregroundStyle(Palette.ink1)
                    if let subtitle {
                        Text(subtitle).font(Fonts.caption).foregroundStyle(Palette.ink3)
                    }
                }
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(Fonts.caption)
                        .foregroundStyle(trailingColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Image(systemName: "chevron.right")
                    .font(Fonts.s(12, .semibold, .caption))
                    .foregroundStyle(Palette.ink3)
            }
            // 16pt 内边距让每行稳定在 44pt 以上（Apple HIG 的最小触达尺寸）
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: Dimens.radiusInner, style: .continuous)
                    .fill(Palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Dimens.radiusInner, style: .continuous)
                    .strokeBorder(Palette.line, lineWidth: 1)
            )
            .measureTapTarget(tapName)
        }
        .buttonStyle(PressableStyle())
    }

    private var settingsSection: some View {
        @Bindable var app = app
        return VStack(alignment: .leading, spacing: 12) {
            SectionHead("设置")

            VStack(spacing: 0) {
                // 每日新字数
                HStack {
                    Text("每天学几个新字")
                        .font(Fonts.body)
                        .foregroundStyle(Palette.ink1)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { app.progress.settings.dailyNew },
                        set: { v in
                            var s = app.progress.settings
                            s.dailyNew = v
                            app.progress.updateSettings(s)
                        }
                    )) {
                        ForEach([3, 5, 8, 10], id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: LayoutRules.scaled(220, by: dt.layoutScale))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)

                HairLine()

                HStack {
                    Text("显示拼音")
                        .font(Fonts.body)
                        .foregroundStyle(Palette.ink1)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { app.progress.settings.showPinyin },
                        set: { v in
                            var s = app.progress.settings
                            s.showPinyin = v
                            app.progress.updateSettings(s)
                        }
                    ))
                    .labelsHidden()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .measureTapTarget("我的-设置行(开关)")

                HairLine()

                HStack {
                    Text("朗读")
                        .font(Fonts.body)
                        .foregroundStyle(Palette.ink1)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { app.progress.settings.speakEnabled },
                        set: { v in
                            var s = app.progress.settings
                            s.speakEnabled = v
                            app.progress.updateSettings(s)
                        }
                    ))
                    .labelsHidden()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .measureTapTarget("我的-设置行(开关)")

                HairLine()

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("朗读语速")
                            .font(Fonts.body)
                            .foregroundStyle(Palette.ink1)
                        Spacer()
                        Text(String(format: "%.2f", app.progress.settings.speechRate))
                            .font(Fonts.caption.monospacedDigit())
                            .foregroundStyle(Palette.ink3)
                    }
                    Slider(value: Binding(
                        get: { Double(app.progress.settings.speechRate) },
                        set: { v in
                            var s = app.progress.settings
                            s.speechRate = Float(v)
                            app.progress.updateSettings(s)
                        }
                    ), in: 0.3...1.7)
                    .tint(Palette.jade)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)

                if !Speech.shared.hasChineseVoice {
                    HairLine()
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(Palette.amber)
                        Text("这台设备没有中文语音，朗读会没有声音。可在「设置 › 辅助功能 › 朗读内容」里下载。")
                            .font(Fonts.caption)
                            .foregroundStyle(Palette.ink2)
                    }
                    .padding(16)
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
}

/// 版本信息统一从 Bundle 读，不写死字符串。
///
/// Android 侧曾在两个页面硬编码 "v1.0.0"，和实际 versionName 1.0.5 脱节，
/// 用户看到的版本号是错的。iOS 这边从一开始就走 Bundle。
enum AppInfo {
    static var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v\(v) (\(b))"
    }
}
