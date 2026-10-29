import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.xiaoxiao.hanzi"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.xiaoxiao.hanzi"
        minSdk = 24
        targetSdk = 36
        versionCode = 4
        versionName = "1.0.3"
    }

    // debug 签名默认落在 ~/.android/debug.keystore，放在工程内便于沙箱环境和 CI 复用
    signingConfigs {
        getByName("debug") {
            storeFile = file("../keystore/debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
        release {
            // 发布用的 keystore 不进仓库。没有配置时回落到 debug 签名，
            // 保证 `assembleRelease` 在没有密钥的环境下也能出包（仅用于本地验证体积）。
            val props = Properties()
            val f = rootProject.file("keystore/release.properties")
            if (f.exists()) f.inputStream().use { props.load(it) }
            signingConfig = if (f.exists()) {
                signingConfigs.create("release") {
                    storeFile = rootProject.file(props.getProperty("storeFile"))
                    storePassword = props.getProperty("storePassword")
                    keyAlias = props.getProperty("keyAlias")
                    keyPassword = props.getProperty("keyPassword")
                }
            } else {
                signingConfigs.getByName("debug")
            }

            // 混淆 + 资源压缩：数据是 assets 里的 JSON，不受影响；
            // 代码里没有反射，默认规则即可。
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }

    buildFeatures {
        compose = true
    }

    // 笔顺数据是构建产物，由 scripts/build-data.mjs 生成到 assets，
    // 这里不再压缩，避免 APK 里压两次（数据本身已是二进制转 base64）
    androidResources {
        noCompress += listOf("json")
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }

    testOptions {
        unitTests {
            all {
                // Robolectric 默认把下载锁文件和 android-all 依赖放在 ~/.robolectric-*，
                // 沙箱只允许写工作区。这里把 user.home 和依赖目录都指到 .tools/ 下，
                // 顺便让 CI 上也能复现同一套环境。
                val roboDir = rootProject.file(".tools/robolectric-home")
                roboDir.mkdirs()
                it.systemProperty("user.home", roboDir.absolutePath)
                it.systemProperty("robolectric.logging", "stdout")
                // Robolectric 自带的系统字体没有中文字形，截图里全是方框。
                // 把站内的中文字体目录交给它，截图才能看出真实排版。
                val fontDir = rootProject.file(".tools/robolectric-fonts")
                if (fontDir.exists()) {
                    it.systemProperty("robolectric.fonts", fontDir.absolutePath)
                }
                it.maxHeapSize = "2g"
            }
            // Repo 依赖 android.content.Context 读 assets，单测里用 loadFromStrings 绕开
            isReturnDefaultValues = true
            // Robolectric 需要读 assets，必须打出资源包
            isIncludeAndroidResources = true
        }
    }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2025.09.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.activity:activity-compose:1.10.1")
    implementation("androidx.core:core-ktx:1.15.0")
    debugImplementation("androidx.compose.ui:ui-tooling")

    // JVM 单测：org.json 在 Android 上是桩实现，单测里换成真正的实现，
    // 否则 Repo 一解析 JSON 就抛 "not mocked"
    testImplementation("org.json:json:20240303")
    testImplementation("junit:junit:4.13.2")

    // Robolectric：在 JVM 上跑真实的 Compose 渲染与布局，
    // 因为本机模拟器在沙箱里起不来（快照锁文件在沙箱外）
    testImplementation("org.robolectric:robolectric:4.17")
    testImplementation("androidx.compose.ui:ui-test-junit4")
    testImplementation("androidx.test:core:1.6.1")
    testImplementation("androidx.test.ext:junit:1.2.1")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
}
