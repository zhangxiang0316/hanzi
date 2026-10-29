# 签名密钥

## debug.keystore（已入库）

公开的调试密钥，口令都是 `android`，别名 `androiddebugkey`。
进仓库是为了「克隆下来就能 `assembleDebug`」，不涉及任何安全风险
——它和 Android SDK 自动生成的那份等价。

## 发布密钥（不入库）

正式发版需要一个自己的 release 密钥。生成一次，之后一直复用
（**换 key 会导致老用户无法覆盖安装**）：

```bash
cd android/keystore

keytool -genkeypair -v \
  -keystore release.keystore \
  -alias hanzi \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass '你的口令' -keypass '你的口令' \
  -dname "CN=小小识字家, OU=Dev, O=Xiaoxiao, L=Beijing, ST=Beijing, C=CN"
```

然后在同目录建 `release.properties`：

```properties
storeFile=../keystore/release.keystore
storePassword=你的口令
keyAlias=hanzi
keyPassword=你的口令
```

`app/build.gradle.kts` 会自动读取：文件存在就走 release 签名，
不存在就回落到 debug 签名（仅用于本地验证体积，**不可上架**）。

```bash
# 确认签名者
$ANDROID_HOME/build-tools/36.1.0/apksigner verify --print-certs \
  app/build/outputs/apk/release/app-release.apk
```

两个文件都已被 `.gitignore` 忽略，记得另外备份——丢了就只能换包名重新发。
