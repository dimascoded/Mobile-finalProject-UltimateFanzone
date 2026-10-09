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
subprojects {
    project.evaluationDependsOn(":app")
}

// Sebagian plugin (mis. sensors_plus 4.0.2) masih dipin ke compileSdk 33,
// padahal dependensi androidx transitifnya butuh >= 34/36 -> kegagalan
// checkDebugAarMetadata. Di AGP 9 compileSdk sudah difinalisasi saat evaluasi,
// jadi setelah-evaluate "too late"; pakai hook finalizeDsl (variant API) untuk
// memaksa modul library plugin memakai compileSdk yang sama dengan :app.
subprojects {
    plugins.withId("com.android.library") {
        project.extensions.configure<com.android.build.api.variant.LibraryAndroidComponentsExtension>("androidComponents") {
            finalizeDsl { extension ->
                extension.compileSdk = 36
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
