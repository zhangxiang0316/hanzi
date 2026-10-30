import SwiftUI

/// 共享组件，与 Android `ui/Components.kt` 对应。

// MARK: - 卡片

struct HanziCard<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Dimens.radiusCard, style: .continuous)
                    .fill(Palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Dimens.radiusCard, style: .continuous)
                    .strokeBorder(Palette.edge, lineWidth: 1)
            )
    }
}

// MARK: - 按钮

struct HanziButton: View {
    enum Kind { case primary, secondary, ghost }

    let title: String
    var kind: Kind = .primary
    var fullWidth: Bool = false
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .padding(.horizontal, 20)
                .padding(.vertical, 11)
                .background(background)
                .foregroundStyle(foreground)
                .clipShape(RoundedRectangle(cornerRadius: Dimens.radiusInner, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Dimens.radiusInner, style: .continuous)
                        .strokeBorder(kind == .secondary ? Palette.edge : .clear, lineWidth: 1)
                )
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }

    private var background: Color {
        switch kind {
        case .primary: return Palette.jade
        case .secondary: return Palette.card
        case .ghost: return .clear
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary: return .white
        case .secondary: return Palette.ink1
        case .ghost: return Palette.jade
        }
    }
}

/// 按下时轻微缩小 —— 比默认的高亮反馈更细腻，也更符合「纸片」的质感
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - 进度

struct ProgressBar: View {
    /// 0...1
    let value: Double
    var height: CGFloat = 8
    var color: Color = Palette.jade

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.track)
                Capsule()
                    .fill(color)
                    .frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: height)
    }
}

/// 圆环进度，首页「已认识 N 字」用
struct ProgressRing: View {
    let value: Double
    var lineWidth: CGFloat = 9
    var color: Color = Palette.jade
    var size: CGFloat = 84

    var body: some View {
        ZStack {
            Circle()
                .stroke(Palette.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, value)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.5), value: value)
    }
}

// MARK: - 小标签

struct TinyPill: View {
    let text: String
    var color: Color = Palette.jade
    var filled: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(filled ? color : color.opacity(0.13))
            .foregroundStyle(filled ? .white : color)
            .clipShape(Capsule())
    }
}

struct SectionHead: View {
    let title: String
    var trailing: AnyView?

    init(_ title: String, trailing: AnyView? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Fonts.sectionTitle)
                .foregroundStyle(Palette.ink1)
            Spacer()
            if let trailing { trailing }
        }
    }
}

// MARK: - 空状态

struct EmptyState: View {
    let emoji: String
    let title: String
    var desc: String?

    var body: some View {
        VStack(spacing: 10) {
            Text(emoji).font(.system(size: 42))
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.ink1)
            if let desc {
                Text(desc)
                    .font(Fonts.bodySmall)
                    .foregroundStyle(Palette.ink3)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}

// MARK: - 星星

struct StarsView: View {
    let count: Int
    var size: CGFloat = 16
    var animated: Bool = true
    @State private var shown = 0

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Text(i < shown ? "★" : "☆")
                    .font(.system(size: size))
                    .foregroundStyle(i < shown ? Palette.amber : Palette.line)
                    .scaleEffect(animated && i < shown ? 1 : 0.9)
            }
        }
        .onAppear {
            guard animated else {
                shown = count
                return
            }
            // 逐颗亮起，比一次全亮更有"得到奖励"的感觉
            shown = 0
            for i in 1...3 where i <= count {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.12) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                        shown = i
                    }
                }
            }
        }
    }
}

struct HairLine: View {
    var body: some View {
        Rectangle().fill(Palette.line).frame(height: 1)
    }
}

// MARK: - 册次名称

enum BookNaming {
    static func gradeName(_ grade: Int) -> String {
        switch grade {
        case 1: return "一年级"
        case 2: return "二年级"
        case 3: return "三年级"
        case 4: return "四年级"
        default: return "\(grade) 年级"
        }
    }

    /// 统编版教材的一册跨度说明
    static func gradeSpan() -> String {
        "统编版 · 一到四年级"
    }

    static func termName(_ term: Int) -> String {
        term == 1 ? "上册" : "下册"
    }
}
