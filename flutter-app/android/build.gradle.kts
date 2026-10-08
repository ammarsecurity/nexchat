allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://jitpack.io") }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    // tiktok_events_sdk skips kotlin-android on AGP 9+ (expects built-in Kotlin).
    // This app keeps android.builtInKotlin=false because flutter_webrtc / livekit_client
    // still apply KGP — so force KGP onto tiktok or its .kt classes never compile.
    val projectName = name
    pluginManager.withPlugin("com.android.library") {
        if (projectName == "tiktok_events_sdk" &&
            !pluginManager.hasPlugin("org.jetbrains.kotlin.android") &&
            !pluginManager.hasPlugin("kotlin-android")) {
            pluginManager.apply("org.jetbrains.kotlin.android")
        }
    }
    afterEvaluate {
        extensions.findByName("android")?.let { ext ->
            val methods = ext.javaClass.methods
            methods.firstOrNull { it.name == "setNdkVersion" && it.parameterCount == 1 }
                ?.invoke(ext, "29.0.14206865")
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
