import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// C5: kredensial rilis dibaca dari android/key.properties, yang di-ignore Git.
// Buat dengan:
//   keytool -genkey -v -keystore ~/upload-keystore.jks \
//     -keyalg RSA -keysize 2048 -validity 10000 -alias upload
// lalu isi android/key.properties:
//   storePassword=...  keyPassword=...  keyAlias=upload  storeFile=/path/upload-keystore.jks
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "com.smartfootballfan"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.smartfootballfan"
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
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = keystoreProperties["storeFile"]?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // C5: pakai keystore rilis bila key.properties ada. Tanpa file itu
            // build tetap jalan memakai debug key supaya `flutter run --release`
            // untuk demo lokal tidak terblokir, tapi APK hasil build itu tidak
            // boleh diunggah ke Play Store.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
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
    // Themed AppCompat dipakai styles.xml -> ThemeAppCompat.DayNight.NoActionBar.
    // Wajib untuk FlutterFragmentActivity + local_auth (biometrik).
    implementation("androidx.appcompat:appcompat:1.7.0")
}
