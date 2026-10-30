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

## 测试

数据层与逻辑层零 UIKit 依赖，用 SPM 在 macOS 上原生跑，不需要模拟器：

```bash
cd ios && swift test --disable-sandbox
```

（`--disable-sandbox` 只在受限环境需要，正常开发机去掉即可。）

界面层的截图测试需要模拟器，留到后续阶段单独处理。

### M1 数据层结论（2026-10-30）

28 个测试全绿，逐条对照 Android 侧已验证的数字：

| 项 | 期望 | 实际 |
| --- | --- | --- |
| 册次 | 8 | 8 |
| 总课数 | 276 | 276 |
| 唯一字数 | 2596 | 2596 |
| 笔顺覆盖 | 生字全部有 | 无缺失 |
| 笔画数一致性 | meta.s == 笔顺笔数 | 抽查 300 字全对 |

特别值得记的两条：

1. **`stat.chars` 与实际去重后数量一致**：构建脚本统计的数字和运行时算出来的
   对齐，说明「册 → 单元 → 课 → 生字」的去重逻辑没有偏差。

2. **多音字按课文取音**：「地」在 `1a-s1` 读 `dì`、在 `1a-k4` 读 `de`，
   和 Android 的 `readingFor` 行为一致。这条容易写错成「总是返回主读音」。

`Repo` 标记了 `@MainActor`：它是 App 级只读数据，只有几处解码缓存是可变状态，
而所有访问都来自 SwiftUI 视图。用 actor 隔离比手写锁更难出错——这是 Swift 6
严格并发检查给出的提示，顺手采纳了。

### M2 逻辑层结论（2026-10-30）

SRS / 描红评分 / 出题 / 计划 / 进度，全部照搬 Android 的实现，41 个测试对照
Android `LogicTest.kt` 的断言逐条验证。三处值得记的：

1. **mulberry32 必须逐位一致**。用 JS 原版算出黄金值写进测试（seed 12345 →
   0.97972826776094735），三端同 seed 才能出同一套题。实现时注意 JS 是
   `(t + imul(...)) ^ t`、Kotlin 是 `t xor (...)`，异或可交换所以等价，
   但漏看这一点很容易写成不一样的运算顺序。

2. **刚学的字答错一次会退回第 0 箱**，此时不再算「已学」。这是 `Srs.grade`
   的既定行为（`box >= 3` 才回到 1，否则掉到 0），我最初把测试期望写成了
   「仍然已学」，失败后确认是测试错、代码对，并补了一条专门的测试锁住它，
   免得以后被当成 bug 改掉。

3. **逻辑层原本硬编码 `Repo.shared`，导致测试跑不起来**。测试进程的
   `Bundle.main` 里没有那三个 JSON，`Repo` 的断言直接把测试进程打挂
   （signal 5）。改成 `Repo.overrideShared(_:)` 注入后正常——这也说明逻辑层
   不该直接依赖全局单例，依赖注入不只是为了测试好看。

### M3 绘制层结论（2026-10-30）

`HanziCanvas`（坐标映射）+ `HanziDraw`（渲染）+ `HanziView`（视图与动画）。

**与 Android 的一处有意偏离：底字用笔画轮廓画，不画字体。**

Android 的 `drawGhostChar` 走的是 `drawText`，即用楷体渲染一个淡灰的「天」垫在
下面。问题是这样一来，孩子照着描的底字和判分用的中线是两套几何：实测「天」的
笔画轮廓与 PingFang 字形只重叠 70%，因为前者是楷体骨架、后者是黑体，笔形和字重
都不同。照着描却判错，是最伤体验的那类 bug。

iOS 这边底字直接用同一批笔画轮廓填充，验证结果：

| 指标 | 值 |
| --- | --- |
| 底字 bbox | 95,95,576,530 |
| 墨迹 bbox | 95,95,576,530（完全一致） |
| 质心偏移 | 0.07 px |
| 面积比 | 1.004 |

底字和墨迹就是同一批路径，所以必然重合——不再是「看起来差不多」。

**几何正确性用离线渲染器对照。**

`Tools/render-probe.swift` 渲染同样的笔画数据到 PNG，与设备导出的图算 IoU：

| 字 | IoU | 质心偏移 |
| --- | --- | --- |
| 天 | 0.958 | 0.73px |
| 地 | 0.964 | 1.53px |
| 人 | 0.957 | 1.92px |
| 永 | 0.954 | 0.34px |
| 国 | 0.959 | 1.59px |
| 一 | 0.949 | 0.48px |
| 口 | 0.991 | 0.47px |
| 拿 | 0.943 | 1.53px |

0.94–0.99 的差异全部来自抗锯齿边缘（阈值为 R<110），不是几何偏差。

**截图验证改用 `ImageRenderer` 导出，而不是截屏。**

`xcrun simctl io screenshot` 拿到的是整屏，要定位每个格子得靠猜坐标，改一次布局
就得重猜一次。`SnapshotExport` 用 `ImageRenderer` 直接按指定尺寸渲染各状态并存成
PNG，再用 `simctl get_app_container` 拉出来——每张图就是一个待验证的状态。

踩到的坑：`ImageRenderer` 默认输出**透明背景**，PNG 里透明像素的 RGB 是 0，
「R<110 即墨迹」的判据于是一整张图都算成墨迹。加了白底才对。

**逐笔动画**用 `TimelineView(.animation)` 而不是给每笔挂 `withAnimation`。
笔画数量不定、每笔时长要精确可控，时间轴驱动才方便做「播到一半暂停」和
「跳回某一笔」——描红页两个都要。真机验证：连拍 4 帧墨迹 14145 → 38572 →
61420 → 61426（播完），确实在推进。

缓动用 `1-(1-t)^1.6`（起笔快、收笔慢）。只影响观感，不参与任何判分——
判分用的是用户自己的笔迹。
