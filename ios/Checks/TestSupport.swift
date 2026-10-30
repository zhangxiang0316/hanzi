import Foundation
@testable import HanziCore

/// 测试共用的数据源。
///
/// 三个测试文件都要一个 Repo，而且都必须同时设成 `Repo.shared`——
/// Quiz / Plan 内部读全局实例，不设就会去 Bundle.main 找资源然后失败。
@MainActor
enum TestRepo {
    private static var cached: Repo?

    static func make() -> Repo {
        if let c = cached { return c }
        let resources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Checks
            .deletingLastPathComponent()   // ios
            .appendingPathComponent("HanziPad/Resources")
        let r = Repo(source: .directory(resources))
        cached = r
        Repo.overrideShared(r)
        return r
    }
}
