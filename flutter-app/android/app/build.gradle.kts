import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// android/key.properties (not committed): storeFile, storePassword, keyAlias, keyPassword.
// Must be the same keystore as the current Play Store build so the update installs over it.
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) {
        val text = f.readText(Charsets.UTF_8).removePrefix("\uFEFF")
        load(text.reader())
    }
}

fun keyProp(name: String): String? = keystoreProperties.getProperty(name)?.trim()?.trim('"')

android {
    namespace = "site.nexchat.nexchat"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "site.nexchat.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        val storePath = keyProp("storeFile")
        if (!storePath.isNullOrBlank()) {
            create("release") {
                storeFile = file(storePath)
                storePassword = keyProp("storePassword")
                keyAlias = keyProp("keyAlias")
                keyPassword = keyProp("keyPassword")
                val type = keyProp("storeType")
                if (!type.isNullOrBlank()) {
                    storeType = type
                }
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("com.onesignal:OneSignal:5.10.2")
    implementation("androidx.core:core-ktx:1.16.0")
}
