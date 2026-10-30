import SwiftUI

/// 我的：学习概览 + 徽章 + 设置。
///
/// 勋章这块按用户反馈做过一次调整（Android v1.0.1「我的徽章太大了」）：
/// 用自适应网格 + 紧凑卡片，iPad 上会铺成 4-6 列，不会每屏只看到四五个。
struct ProfilePageView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    statsGrid
                    studyLinks
                    badgeSection
                    settingsSection
                    aboutRow
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
                Text("🌱").font(.system(size: 30))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("小小识字家")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Palette.ink1)
                Text("已连续学习 \(app.progress.streak) 天")
                    .font(Fonts.bodySmall)
                    .foregroundStyle(Palette.ink3)
            }
            Spacer()
        }
    }

    private var statsGrid: some View {
        let learned = app.progress.totalLearned
        let mastered = app.progress.totalMastered
        let stars = app.progress.writeStarsTotal
        let days = app.progress.activeDays

        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)],
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
                .font(.system(size: 11))
                .foregroundStyle(Palette.ink3)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(color)
                Text(unit)
                    .font(.system(size: 11))
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

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)],
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
                .font(.system(size: 24))
                .grayscale(b.got ? 0 : 1)
                .opacity(b.got ? 1 : 0.35)
            Text(b.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(b.got ? Palette.ink1 : Palette.ink3)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(b.desc)
                .font(.system(size: 9))
                .foregroundStyle(Palette.ink3)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 24)
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

    /// 学习入口：错题本。
    ///
    /// iPad 上错题本在侧边栏里单独一栏，手机上没有侧边栏，
    /// 所以收进「我的」——和 Android `ProfilePage.kt:272` 的 LinkRow 一致。
    /// 不带红色角标会让孩子忽略它，所以把待复习字数直接写在右侧。
    private var studyLinks: some View {
        let n = app.progress.wrongCount
        return VStack(alignment: .leading, spacing: 12) {
            SectionHead("学习")

            Button {
                app.push(AppState.WrongRoute())
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.bubble")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(n > 0 ? Palette.clay : Palette.ink3)
                        .frame(width: 22)
                    Text("错题本")
                        .font(Fonts.body)
                        .foregroundStyle(Palette.ink1)
                    Spacer()
                    Text(n > 0 ? "\(n) 个字" : "还没有错字")
                        .font(Fonts.caption)
                        .foregroundStyle(n > 0 ? Palette.clay : Palette.ink3)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
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
            }
            .buttonStyle(PressableStyle())
        }
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
                    .frame(width: 220)
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

            Button("重置全部学习记录", role: .destructive) {
                app.progress.resetAll()
            }
            .font(Fonts.bodySmall)
            .padding(.top, 4)
        }
    }

    private var aboutRow: some View {
        Button {
            app.push(AppState.AboutRoute())
        } label: {
            HStack {
                Text("关于小小识字家")
                    .font(Fonts.body)
                    .foregroundStyle(Palette.ink1)
                Spacer()
                Text(AppInfo.version)
                    .font(Fonts.caption)
                    .foregroundStyle(Palette.ink3)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
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
        }
        .buttonStyle(PressableStyle())
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
