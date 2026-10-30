import SwiftUI
import UIKit

/// 设备与窗口形态的判断。
///
/// 只放「必须知道是手机还是平板」的判断。能按宽度算的都放 `LayoutRules`，
/// 因为那才是真正随窗口变化的东西——iPad 分屏后内容区可能比手机还窄。
enum AppLayout {

    /// 是不是手机。
    ///
    /// 用来决定导航范式（底部 tab 还是侧边栏），不用来决定页面布局。
    /// 理由见 `RootView` 的说明：按尺寸类判断会让手机横屏时导航模型整个换掉。
    static var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }
}

/// 手机端根视图：底部 tab + 每个 tab 各自一条导航栈。
///
/// tab 只放三个：首页 / 练习 / 我的，与 Android 版一致。
/// 课本从首页的「跟课本学」进，错题本和关于收在「我的」里——
/// 手机上塞五个 tab 每个只剩 78pt，中文标签会挤成一团。
struct PhoneRootView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        TabView(selection: selection) {
            tab(.home, "首页", "house.fill")
            tab(.practice, "练习", "square.grid.2x2.fill")
            tab(.profile, "我的", "person.fill")
        }
    }

    /// 当前选中的 tab。
    ///
    /// 分区里 `courses` / `wrong` / `about` 不是 tab——它们只能通过 push 到达，
    /// 或者在 iPad 侧边栏里直接切。手机上万一被设成这些（比如调试参数
    /// `-startSection courses`），要落到一个有 tab 的分区，否则 TabView 没有
    /// 选中项，界面会空着。
    private var selection: Binding<AppState.Section> {
        Binding(
            get: { app.section.tabRoot },
            set: { app.section = $0 }
        )
    }

    /// 一个 tab。
    ///
    /// 标题交给 `SectionRootView` 设（它内部已经按分区给了标题），
    /// 这里只管导航栈和 tab 标签，避免两处都设标题。
    private func tab(_ section: AppState.Section,
                     _ title: String, _ icon: String) -> some View {
        NavigationStack(path: app.pathBinding(section)) {
            SectionRootView(section: section)
                .appRoutes()
        }
        .tabItem { Label(title, systemImage: icon) }
        .tag(section)
    }
}

extension AppState.Section {

    /// 这个分区归属哪个 tab。非 tab 分区映射到最接近的那个。
    var tabRoot: AppState.Section {
        switch self {
        case .home, .courses: return .home
        case .practice: return .practice
        case .profile, .wrong, .about: return .profile
        }
    }
}
