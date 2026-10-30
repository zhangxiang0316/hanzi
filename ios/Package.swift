// swift-tools-version: 6.0
import PackageDescription

/// 数据层与逻辑层的测试包。
///
/// 这两层刻意不依赖 UIKit/SwiftUI，所以可以脱离模拟器、在 macOS 上原生跑测试——
/// 快得多，也不需要启动模拟器。界面层仍然走 Xcode 工程里的 XCTest 目标。
///
/// 用法：cd ios && swift test
let package = Package(
    name: "HanziCore",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "HanziCore",
            // 数据层与逻辑层都是纯 Swift + Foundation/CoreGraphics，无 UIKit 依赖
            path: ".",
            sources: [
                "HanziPad/Data/StrokeCodec.swift",
                "HanziPad/Data/Models.swift",
                "HanziPad/Data/Repo.swift",
                "HanziPad/UI/HanziCanvas.swift",
                "HanziPad/UI/HanziDraw.swift",
                "HanziPad/UI/HanziView.swift",
                "HanziPad/Logic/Srs.swift",
                "HanziPad/Logic/DayUtil.swift",
                "HanziPad/Logic/Store.swift",
                "HanziPad/Logic/Trace.swift",
                "HanziPad/Logic/Quiz.swift",
                "HanziPad/Logic/Progress.swift",
                "HanziPad/Logic/Plan.swift",
                "HanziPad/Logic/WriteSession.swift",
            ]
        ),
        .testTarget(
            name: "HanziCoreTests",
            dependencies: ["HanziCore"],
            path: "Checks"
        ),
    ]
)
