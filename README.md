# 小小识字家

面向小学一、二年级的汉字学习微信小程序：**跟着统编版课本，一笔一笔把字写对。**

![首页](docs/images/index.png)

<p align="center">
  <img src="docs/images/lesson.png" width="24%" alt="课文生字" />
  <img src="docs/images/detail.png" width="24%" alt="笔顺动画" />
  <img src="docs/images/write.png" width="24%" alt="描红评分" />
  <img src="docs/images/quiz.png" width="24%" alt="练习" />
</p>

---

## 它能做什么

| 功能 | 说明 |
| --- | --- |
| 跟课本学 | 统编版一上 / 一下 / 二上 / 二下，4 册 32 单元 150 课 **1600 个生字** |
| 看笔顺 | Canvas 逐笔动画，可重播、单笔回放、显示笔顺序号，速度可调 |
| 描红评分 | 手指在田字格里写，**每一笔**即时判定；写错告诉你"起笔不对 / 写歪了 / 没写全" |
| 练 | 5 种题型（看拼音选字、看字选拼音、词语填空、数笔画、找词语），同册干扰项 |
| 复习 | Leitner 间隔重复（0/1/2/4/7/15/30/60 天）+ 错题本，到期自动提醒复习 |
| 看进步 | 今日任务、连续天数、识字/掌握统计、徽章、近 7 天练习图 |
| 零负担 | 无登录、无广告、无内购、无社交；数据只存本机 |

**不做**：排行榜、付费、广告、虚拟宠物、每日签到奖励。

---

## 快速开始

### 用微信开发者工具跑

```bash
git clone <repo> && cd hanzi
```

1. 打开微信开发者工具 → 导入项目 → 选择本目录；
2. `project.config.json` 里已配置 `miniprogramRoot: "miniprogram/"` 与 `appid: "touristappid"`（游客模式即可预览）；
3. 编译，首页即出。

> 换正式 AppID 时，只需改 `project.config.json` 的 `appid`。笔顺页在分包 `packageStrokes`，首屏会自动预载。

### 用浏览器看（不需要开发者工具）

```bash
npm install          # 只装开发依赖（@napi-rs/canvas、puppeteer-core）
npm run preview      # http://127.0.0.1:8788
```

预览器会真实执行小程序页面 JS、解析 WXML、实现 `wx.*` 的最小兼容层，用于开发期快速看效果与自动化断言。

---

## 命令

```bash
npm run build:data     # 源数据 → 压缩笔顺二进制 + 目录/字库模块
npm run build:icons    # 生成 tabBar 图标（纯代码画 PNG）
npm run lint           # 自研静态检查（页面完整性/分包/WXSS 兼容/包体积/路由）
npm test               # 47 个单元测试
npm run render:check   # Node Canvas 渲染自检（像素断言）
npm run preview        # 浏览器预览
npm run preview:shots  # 9 页截图 + 交互断言（需本机 Chrome）
npm run check          # 以上：构建 + 静态检查 + 单测 + 渲染自检
```

`npm run check` 当前输出：

```
✓ 数据构建完成   字库 1600 字；合计 1777.8 KB
✓ 静态检查通过：11 个页面，34 个 JS，12 个 WXSS，主包 471 KB，分包 packageStrokes 1474KB
# tests 47   # pass 47   # fail 0
✓ 渲染自检通过：16 个字、笔顺递增、动画终态一致
```

---

## 目录结构

```
hanzi/
├── miniprogram/                 → 小程序源码（miniprogramRoot）
│   ├── data/                    主包数据：catalog.js（目录）meta.js（字属性）
│   ├── utils/                   catalog / progress / srs / plan / quiz / trace / store …
│   ├── pages/                   首页、单元、课文、练习、答题、结果、我的、错题本、关于
│   ├── packageStrokes/          分包：笔顺数据（1.4MB）+ 字详情 + 描红
│   └── LICENSE-ARPHIC.txt       笔顺数据许可证（随包分发）
├── content/source/              原始数据（不打包，可复现构建）
├── scripts/                     build-data / gen-icons / lint / render-check / preview
├── tests/                       node:test 单元测试
└── docs/                        规划、技术方案、合规、测试与验收
```

---

## 文档

| 文档 | 内容 |
| --- | --- |
| [产品规划](docs/01-产品规划.md) | 用户与场景、学习闭环、信息架构、页面线框、分期与指标 |
| [技术方案](docs/02-技术方案.md) | 选型、数据管线、二进制格式、渲染引擎、评分算法、SRS、体积账本 |
| [内容版权与合规](docs/03-内容版权与合规.md) | 数据来源、Arphic 许可证义务、上架合规、免责文案 |
| [测试与验收](docs/04-测试与验收.md) | 五层验证怎么做、怎么跑、覆盖了什么、没覆盖什么 |

---

## 体积

| 包 | 大小 | 内容 |
| --- | --- | --- |
| 主包 | **471 KB** / 2 MB | 9 个页面 + 目录 + 字库 |
| 分包 `packageStrokes` | **1.44 MB** / 2 MB | 4 册笔顺二进制 + 字详情 + 描红 |

1600 个字的完整笔顺（含分笔矢量与中线）原本是 6.5MB 的 JSON，经过「坐标量化 + 二进制 + base64」压到 1.4MB。

---

## 数据来源

- **字表 / 拼音 / 部首 / 组词**：依据统编版（部编版）小学语文教材整理，经 [fsiceangel/zishi](https://github.com/fsiceangel/zishi) 汇总。
- **笔顺**：[Make Me a Hanzi](https://github.com/skishore/makemeahanzi)，字形来源于 Arphic 字体，遵循 **Arphic Public License**（[许可证全文](miniprogram/LICENSE-ARPHIC.txt)）。

本小程序与教材出版方无隶属关系，内容仅用于识字练习。详见 [内容版权与合规](docs/03-内容版权与合规.md)。

---

## 隐私

不收集任何个人信息，无登录、无网络请求。学习记录仅保存在本机 `wx.storage`，清除小程序缓存即清除记录。

---

## License

- 程序代码：可自由用于学习与教学。
- 笔顺数据：Arphic Public License（见 `miniprogram/LICENSE-ARPHIC.txt`），修改后的数据须以相同条款提供。
