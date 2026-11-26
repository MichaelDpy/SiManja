import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ─── Signing rilis ───────────────────────────────────────────────────────────
// Kunci rilis TIDAK ada di repository. Pemilik rilis membuat
// android/key.properties (diabaikan Git) yang menunjuk ke keystore di luar Git.
// Tanpa file itu, build debug/profile tetap jalan, tetapi build rilis
// (APK/AAB) berhenti dengan pesan jelas — tidak pernah jatuh ke kunci debug.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
    val requiredKeys = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
    val missing = requiredKeys.filter { keystoreProperties.getProperty(it).isNullOrBlank() }
    if (missing.isNotEmpty()) {
        throw GradleException(
            "android/key.properties belum lengkap: ${missing.joinToString()}. " +
                "Lihat README bagian Signing rilis Android.",
        )
    }
}

android {
    namespace = "com.simanja.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Identitas permanen aplikasi (keputusan tim 26 Nov 2026, B02).
        // Dipakai registrasi Firebase Android app, OAuth/Google login, dan Play.
        applicationId = "com.simanja.app"
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
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Hanya kunci rilis; tidak ada fallback ke signingConfigs "debug".
            signingConfig =
                if (hasReleaseKeystore) signingConfigs.getByName("release") else null
        }
    }
}

// Gagal sebelum pekerjaan build dimulai bila artefak rilis diminta tanpa kunci.
gradle.taskGraph.whenReady {
    if (!hasReleaseKeystore) {
        val releaseTask = allTasks.firstOrNull { task ->
            task.project == project &&
                Regex("^(assemble|bundle|package|sign)Release(Bundle)?$").matches(task.name)
        }
        if (releaseTask != null) {
            throw GradleException(
                "Build rilis (${releaseTask.name}) memerlukan kunci rilis. " +
                    "Buat android/key.properties sesuai README bagian Signing rilis Android. " +
                    "Kunci debug tidak dipakai untuk rilis.",
            )
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
