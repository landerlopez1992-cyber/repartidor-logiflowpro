import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.logiflowpro.repartidor"
    compileSdk = flutter.compileSdkVersion
    // NDK r28+ obligatorio para alineación ELF 16 kB (Google Play / Android 15)
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.logiflowpro.repartidor"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a", "x86", "x86_64")
        }
    }

    packaging {
        jniLibs {
            // Android 15 / Play: .so sin comprimir, alineación 16 kB (AGP 8.5.1+)
            useLegacyPackaging = false
        }
    }

    val keystorePropertiesFile = rootProject.file("key.properties")
    val tieneKeystoreRelease = keystorePropertiesFile.exists()

    if (tieneKeystoreRelease) {
        signingConfigs {
            create("release") {
                val keystoreProperties = Properties()
                keystoreProperties.load(keystorePropertiesFile.inputStream())
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
                storeFile = file(keystoreProperties["storeFile"] as String?)
                storePassword = keystoreProperties["storePassword"] as String?
            }
        }
    }

    buildTypes {
        release {
            // CI/GitHub: sin key.properties → firma debug automática de Flutter
            if (tieneKeystoreRelease) {
                signingConfig = signingConfigs.getByName("release")
            }
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
