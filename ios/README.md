# 小小识字家 · iPad 版

SwiftUI 原生实现，**以 iPad 大屏为主**，不做 iPhone 专属紧凑布局。

## 构建

```bash
cd ios
xcodebuild -project HanziPad.xcodeproj -scheme HanziPad \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
  -derivedDataPath .build -configuration Debug \
  OTHER_SWIFT_FLAGS="-disable-sandbox" build
```

两个和代码无关、但必须加的参数：

- `-derivedDataPath .build`：默认的 `~/Library/Developer/Xcode/DerivedData` 在受限沙箱下不可写
- `OTHER_SWIFT_FLAGS="-disable-sandbox"`：Swift 编译器会用 `sandbox-exec` 包裹宏插件进程，
  在已经受限的环境里会报 `sandbox_apply: Operation not permitted`，导致 `@State`、`#Preview`
  等 SwiftUI 宏全部「could not be found」。在正常的开发机上这两个参数都不需要。

## 工程结构

```
HanziPad/
  App/        入口
  Data/       Arcade 模型、数据加载、笔顺解码
  Logic/      SRS、学习计划、出题、描红判分（纯逻辑，可单测）
  UI/         界面与画布
  Resources/  catalog.json / meta.json / strokes.json（与 Android 共用同一份）
Tools/
  render-probe.swift   离线渲染探针，不经过模拟器直接出图
```

## M0 结论（2026-10-30）

在写一行界面代码之前先验证了地基，结论如下。

### 1. 笔顺轮廓在 iOS 上能正确渲染

`strokes.json` 是 Base64 编码的二进制路径数据。**移植时踩到一个坑**：
`StrokeCodec.kt` 里注释写「坐标 = 原坐标 / SCALE(6)」，我照着写成了解码时**除以** 6，
结果每个字的包围盒只有 20 多像素，看起来像"数据坏了"。

实际 Android 的 `private fun c(v: Byte) = (v and 0xFF) * SCALE` 是**乘以** 6——
注释描述的是构建期的编码方向（除以 6 才能塞进一个字节），解码要乘回来。修正后正常。

这个 bug 值得记下来：它不会报错、不会崩溃，只会让字变小到几乎看不见，
如果等到 M5 做界面时才发现，排查成本会高得多。

### 2. 方向正确，没有翻转

用互为镜像的「上」「下」做交叉验证，比较笔画与系统字形的墨迹分布：

| 字 | 笔画质心 y | 字形质心 y | 笔画上半墨迹 | 字形上半墨迹 |
| --- | --- | --- | --- | --- |
| 上 | 0.567 | 0.626 | 40% | 39% |
| 下 | 0.372 | 0.354 | 77% | 75% |

两个字的方向相反且各自与字形高度吻合，确认 y 轴处理正确。

### 3. 底字要用笔画轮廓，不能用系统字体

「天」的笔画轮廓填充 6266 px，PingFang SC 字形填充 10833 px，
笔画被字形覆盖 70%——**两者形状并不一致**：`strokes.json` 是楷体骨架，
PingFang 是黑体，字重和笔形都不同。

所以描红页的「淡灰底字」必须用**笔画轮廓**绘制，而不是 `Text(ch)`：
- 底字与判分用的 median 中线天然对齐，孩子照着写出来的才是被判分的那一笔
- Android 版用的是系统字体画底字（`drawGhostChar` → `drawText`），这一点上
  iOS 版会比 Android 更准，属于有意为之的改进

### 4. 工程文件

没有 xcodegen/tuist，`project.pbxproj` 是手写的。用 Xcode 16+ 的
`PBXFileSystemSynchronizedRootGroup`（文件系统同步组），新增源文件不需要改工程文件。
