import SwiftUI

/// 关于页：版本、数据来源、致谢、隐私说明。
struct AboutPageView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    dataCard
                    privacyCard
                    techCard
                }
                .padding(.horizontal, Dimens.pagePad(geo.size.width))
                .padding(.vertical, 24)
                .frame(maxWidth: Dimens.contentMax(geo.size.width))
                .frame(maxWidth: .infinity)
            }
            .background(Palette.paper)
        }
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hero: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(colors: [Palette.jade, Palette.jadeDeep],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 88, height: 88)
                HanziView(ch: "字", strokes: app.repo.strokes("字"),
                          showGrid: false, showGhost: false, inkColor: .white)
                    .frame(width: 62, height: 62)
            }
            Text("小小识字家")
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(Palette.ink1)
            Text(AppInfo.version)
                .font(Fonts.caption)
                .foregroundStyle(Palette.ink3)
            Text("陪一二年级的小朋友，一笔一画认汉字")
                .font(Fonts.bodySmall)
                .foregroundStyle(Palette.ink2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var dataCard: some View {
        HanziCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("内容来源")
                    .font(Fonts.sectionTitle)
                    .foregroundStyle(Palette.ink1)

                row("课本", "统编版语文教材，一到四年级共 \(app.repo.books.count) 册")
                row("生字", "\(app.repo.allChars.count) 个，按教材顺序编排")
                row("笔顺", "Make Me a Hanzi 笔画数据（MIT / Arphic 授权）")
                row("拼音", "带声调标注，多音字按所在课文取音")

                Text("笔顺数据仅用于教学演示，与课本印刷字体可能略有差异。")
                    .font(Fonts.caption)
                    .foregroundStyle(Palette.ink3)
                    .padding(.top, 2)
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(Fonts.bodySmall)
                .foregroundStyle(Palette.ink3)
                .frame(width: 44, alignment: .leading)
            Text(value)
                .font(Fonts.bodySmall)
                .foregroundStyle(Palette.ink2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var privacyCard: some View {
        HanziCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("隐私")
                    .font(Fonts.sectionTitle)
                    .foregroundStyle(Palette.ink1)
                Text("所有学习记录只保存在这台设备上，不上传、不收集个人信息，也没有广告和第三方统计。")
                    .font(Fonts.bodySmall)
                    .foregroundStyle(Palette.ink2)
            }
        }
    }

    private var techCard: some View {
        HanziCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("技术")
                    .font(Fonts.sectionTitle)
                    .foregroundStyle(Palette.ink1)
                Text("SwiftUI 原生绘制。汉字用笔画轮廓渲染，不是字体贴图——"
                     + "所以描红的底字和判分用的中线是同一套几何。")
                    .font(Fonts.bodySmall)
                    .foregroundStyle(Palette.ink2)
            }
        }
    }
}
