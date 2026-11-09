import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 固定签名：android/key.properties（本地）或 CI 从 Secrets 解出的同一份，
// 保证云包与本地包可互相覆盖安装。缺省时回退 debug 签名。
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

// 车机伪装包：把 applicationId 换成 CarWith 白名单里、本机未安装的应用包名
// （如汽水音乐 com.luna.music），用于车机完整界面投屏测试。
// 用法：在 ~/.gradle/gradle.properties 写入 spoofPackage=com.luna.music 后
// flutter build apk --release（构建完删掉该行）；平时不设置即为正式包名。
val spoofPackage = (project.findProperty("spoofPackage") as String?)?.trim().orEmpty()
val appLabel = when (spoofPackage) {
    "" -> "QQ音乐AI歌单"
    "com.luna.music" -> "汽水音乐"
    else -> spoofPackage
}

android {
    namespace = "com.qqmusicai.qq_music_ai"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = spoofPackage.ifEmpty { "com.qqmusicai.qq_music_ai" }
        // 伪装包使用对应应用的显示名（车机/桌面按 label 展示）
        manifestPlaceholders["appLabel"] = appLabel
        // 汽水音乐伪装包额外暴露一个与其主界面同名的 activity-alias
        manifestPlaceholders["sodaAliasEnabled"] =
            (spoofPackage == "com.luna.music").toString()
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // 保持关闭 R8/资源收缩：audio_service 运行时按资源名查通知小图标
            // （ic_notification），裁剪/改名都有兼容性风险（实测 API 35 上
            // 通知无 small icon 直接闪退）。省 5MB 不值得冒险。
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}
