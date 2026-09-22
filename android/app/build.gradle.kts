import java.util.Properties

// İmza anahtarı bilgileri depoya girmez: `android/key.properties` yerel
// bir dosyadır ve .gitignore ile dışarıda tutulur. Dosya yoksa yayın
// derlemesi hata ayıklama anahtarına düşer, böylece depoyu klonlayan
// biri anahtar olmadan da derleyebilir (ama o çıktı dağıtılamaz).
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val hasReleaseKey = keystoreProperties.getProperty("storeFile") != null

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "io.github.strangertheunknown.chesslibrary"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.github.strangertheunknown.chesslibrary"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // just_audio ve uyarlanabilir simgeler için en az API 23.
        minSdk = flutter.minSdkVersion
        // Bilerek sabit: AndroidManifest.xml'deki
        // PROPERTY_COMPAT_ALLOW_RESTRICTED_RESIZABILITY (tablette yönelim
        // kilidi) yalnızca API 36 hedeflenirken geçerli. Flutter varsayılanı
        // 37'ye çıkınca sessizce kalkmasın; yükseltirken tabletteki yönelim
        // davranışı yeniden ele alınmalı.
        targetSdk = 36
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                // Buraya yalnızca release olmayan görevler düşer; release
                // çıktısı aşağıdaki denetimle zaten durduruluyor.
                signingConfigs.getByName("debug")
            }
        }
    }

    // Anahtar yoksa release çıktısı üretilmesin.
    //
    // Eskiden derleme sessizce hata ayıklama anahtarına düşüyordu:
    // "release" adı taşıyan ama yanlış imzalı bir APK üretmek mümkündü.
    // Hata derleme sırasında değil, yalnızca release çıktısı istendiğinde
    // veriliyor; hata ayıklama derlemeleri anahtarsız çalışmayı sürdürür.
    if (!hasReleaseKey) {
        tasks.whenTaskAdded {
            val taskName = name
            val buildsRelease = taskName.contains("Release") &&
                (taskName.startsWith("assemble") ||
                    taskName.startsWith("bundle") ||
                    taskName.startsWith("package"))
            if (buildsRelease) {
                doFirst {
                    throw GradleException(
                        "android/key.properties yok: release cikti imzasiz " +
                            "kalirdi. BUILD.md'deki imza adimlarini uygulayin."
                    )
                }
            }
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
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
