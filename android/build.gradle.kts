allprojects {
    repositories {
        google()
        mavenCentral()
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
// Bazı eklentiler (ör. file_picker) hâlâ eski bir compileSdk ile derleniyor;
// bağımlılıkları ise API 36 istiyor. Eklenti modüllerini uygulamayla aynı
// sürüme çekerek "requires compile against version 36" hatasını önlüyoruz.
subprojects {
    afterEvaluate {
        extensions.findByName("android")?.let { extension ->
            val android = extension as com.android.build.gradle.BaseExtension
            val current = android.compileSdkVersion
                ?.substringAfter("android-")
                ?.toIntOrNull() ?: 0
            if (current < 36) {
                android.compileSdkVersion(36)
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
