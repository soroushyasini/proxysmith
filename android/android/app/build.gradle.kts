import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

// Load keystore properties
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        load(keystorePropertiesFile.inputStream())
    }
}

android {
    namespace = "ir.proxysmith.proxysmith_flutter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "ir.proxysmith.proxysmith_flutter"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
            // Must match the splits.abi filter below — both say arm64-v8a only
            abiFilters += setOf("arm64-v8a")
        }
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
                ?: error("keyAlias missing in key.properties")
            keyPassword = keystoreProperties.getProperty("keyPassword")
                ?: error("keyPassword missing in key.properties")
            storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
                ?: error("storeFile missing in key.properties")
            storePassword = keystoreProperties.getProperty("storePassword")
                ?: error("storePassword missing in key.properties")
        }
    }

    lint {
        checkReleaseBuilds = false
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
    packaging {
        jniLibs {
            val excluded = (project.findProperty("excludeAbis") as? String)
                ?.split(",")
                ?.map { "**/$it/**" }
                ?: listOf("**/x86/**", "**/x86_64/**")
            excludes += excluded
        }
    }
    kotlin {
        compilerOptions {
            jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
        }
    }

    dependencies {
        implementation(files("libs/libv2ray.aar"))
        implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    }

    flutter {
        source = "../.."
    }
}