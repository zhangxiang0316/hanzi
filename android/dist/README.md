# 安装包

> **推荐从 [Releases](https://github.com/zhangxiang0316/hanzi/releases/latest) 下载**，
> 那里有版本说明且不占 git 历史。本目录留一份是为了离线可用与可追溯。

直接下载安装，无需 Android Studio。

| 文件 | 版本 | 大小 | 最低系统 |
| --- | --- | --- | --- |
| `xiaoxiao-hanzi-1.0.2.apk` | 1.0.2 | 3.9 MB | Android 7.0（API 24） |

- SHA-256：`db7fa1dca6db05106c376254ca8a3a395c17eeb3751bece884917ce0091624a9`

## 安装

**手机上**：下载到手机后点击安装。首次安装需要在系统设置里允许
「安装未知来源应用」（不同机型叫法略有差异：华为/荣耀在「安全 → 更多安全设置」，
小米在「隐私保护 → 特殊权限」，OPPO/vivo 在「安全 → 安装外部来源应用」）。

**用 adb**：

```bash
adb install -r xiaoxiao-hanzi-1.0.2.apk
```

## 关于签名

这个包是用**公开的 debug 密钥**签的（因为仓库里没有发布密钥），
能正常安装使用，但不适合上架应用商店。要正式发布，按
[`../keystore/README.md`](../keystore/README.md) 生成 release 密钥后重新构建。

## 自己构建

```bash
node scripts/export-android.mjs
export GRADLE_USER_HOME=$PWD/.tools/gradle-home
export ANDROID_HOME=$HOME/Library/Android/sdk
.tools/gradle-8.14.3/bin/gradle -p android :app:assembleRelease
```

产物在 `android/app/build/outputs/apk/release/app-release.apk`。
构建出的包与本文件不是同一份（每次构建的字节可能不同，这是正常的）。
