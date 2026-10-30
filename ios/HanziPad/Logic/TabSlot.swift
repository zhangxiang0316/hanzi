import Foundation

/// 手机底部 tab 的槽位。
///
/// 分区有 6 个、tab 只有 3 个，所以每个分区要折到一个 tab 上。
/// 这段映射放在 `HanziCore` 而不是 App 目标，是为了能在 SPM 测试里跑到——
/// 折错了的表现是「打开了某页，高亮的却是另一个 tab」，光看截图很容易漏。
///
/// 注意：**不要在 App 里另写一份映射**。`AppState.Section.tabRoot` 必须调用它。
public enum TabSlot: String, CaseIterable, Sendable {
    case home
    case practice
    case profile

    /// 分区 → tab。
    ///
    /// - `courses`（课本）从首页进，归首页
    /// - `wrong`（错题本）、`about`（关于）从「我的」进，归「我的」
    ///
    /// 未知分区一律归「我的」：宁可高亮错一个 tab，也不要因为新增分区
    /// 而让 `TabView` 的 selection 变成 nil（那时整个 tab bar 会没有选中项）。
    public static func slot(forSection section: String) -> TabSlot {
        switch section {
        case "home", "courses":
            return .home
        case "practice":
            return .practice
        default:
            return .profile
        }
    }
}
