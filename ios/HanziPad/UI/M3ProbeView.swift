import SwiftUI

/// M3 探针：把绘制引擎的各个状态摊开在一屏里，方便截图核对。
///
/// 布局是"体检表"而不是产品界面：每个格子只验证一件事
/// （尺寸缩放、逐笔进度、格子/底字/序号开关），
/// 免得以后改绘制代码时看不出是哪一项坏了。
struct M3ProbeView: View {
    @State private var ch = "天"
    @State private var showGrid = true
    @State private var showGhost = true
    @State private var showNumbers = false
    @State private var playing = true

    private let samples = ["天", "地", "人", "永", "国", "一", "龍", "鬱"]

    private var strokes: StrokeCodec.CharStrokes? { Repo.shared.strokes(ch) }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    animationRow
                    progressRow
                    sizeRow
                }
                .padding(28)
            }
        }
        .background(Color(red: 0.984, green: 0.965, blue: 0.925))
        
    }

    // MARK: - 侧栏

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("M3 绘制").font(.title3.bold())
            Text("轮廓 · 底字 · 逐笔动画").font(.caption).foregroundStyle(.secondary)
            Divider()

            ForEach(samples, id: \.self) { c in
                Button { ch = c } label: {
                    HStack {
                        Text(c).font(.system(size: 22, weight: .medium))
                        Spacer()
                        if let s = Repo.shared.strokes(c) {
                            Text("\(s.count) 笔").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("无数据").font(.caption).foregroundStyle(.red)
                        }
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(c == ch ? HanziDraw.accent.opacity(0.16) : .white)
                    )
                }
                .buttonStyle(.plain)
            }

            Divider()
            Toggle("田字格", isOn: $showGrid)
            Toggle("淡灰底字", isOn: $showGhost)
            Toggle("笔画序号", isOn: $showNumbers)
            Toggle("播放动画", isOn: $playing)
            Button("导出验证图集") { SnapshotExport.exportM3(ch) }
                .buttonStyle(.bordered)
            Spacer()
        }
        .padding(20)
        .frame(width: 260)
        .background(.white.opacity(0.5))
    }

    // MARK: - 各行

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(ch).font(.system(size: 40, weight: .semibold))
            if let m = Repo.shared.meta(ch) {
                Text(m.py).font(.title3).foregroundStyle(HanziDraw.accent)
                Text("部首 \(m.radical) · \(m.strokes) 笔")
                    .font(.callout).foregroundStyle(.secondary)
                Text(m.words.prefix(2).map(\.word).joined(separator: " / "))
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var animationRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("逐笔动画（每笔 \(Int(HanziCanvas.perStrokeMs))ms）")
            HStack(spacing: 20) {
                if playing {
                    HanziPlayerView(
                        ch: ch, strokes: strokes,
                        showGrid: showGrid, showGhost: showGhost, showNumbers: showNumbers
                    )
                    .frame(width: 380, height: 380)
                    .id("\(ch)-\(showGrid)-\(showGhost)-\(showNumbers)")
                } else {
                    HanziView(
                        ch: ch, strokes: strokes,
                        showGrid: showGrid, showGhost: showGhost, showNumbers: showNumbers
                    )
                    .frame(width: 380, height: 380)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("检查点").font(.headline)
                    bullet("笔画轮廓是否闭合、粗细一致")
                    bullet("未写的笔画是浅色轮廓，不是实心")
                    bullet("已写的笔画实心填充")
                    bullet("底字与笔画轮廓重合（同一套几何）")
                    bullet("序号圆点在每笔起点")
                }
                .frame(maxWidth: 320, alignment: .leading)
                Spacer()
            }
        }
    }

    /// 同一字的不同完成度并排，验证「已完成 / 进行中 / 未开始」三态
    private var progressRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("逐笔进度")
            HStack(spacing: 14) {
                ForEach(0...(strokes?.count ?? 0), id: \.self) { n in
                    VStack(spacing: 6) {
                        HanziView(
                            ch: ch, strokes: strokes,
                            showGrid: false, showGhost: true,
                            completed: n, partial: n < (strokes?.count ?? 0) ? 0.5 : 0
                        )
                        .frame(width: 108, height: 108)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.white)
                        )
                        Text(n == strokes?.count ? "全部" : "\(n)+½")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var sizeRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("尺寸缩放（同一字不同边长，字重应视觉一致）")
            HStack(alignment: .bottom, spacing: 16) {
                ForEach([64, 96, 140, 200, 280], id: \.self) { s in
                    HanziView(ch: ch, strokes: strokes, showGrid: false, showGhost: false)
                        .frame(width: CGFloat(s), height: CGFloat(s))
                }
            }
        }
    }

    // MARK: - 小组件

    private func label(_ s: String) -> some View {
        Text(s).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
    }

    private func bullet(_ s: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("·").foregroundStyle(HanziDraw.accent)
            Text(s).font(.callout).foregroundStyle(.secondary)
        }
    }
}
