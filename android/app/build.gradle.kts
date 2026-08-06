import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}
val keystorePropertiesFile: File = file("../key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        load(FileInputStream(keystorePropertiesFile))
    }
}
android {
    namespace = "com.anchor.heart1"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.anchor.heart1"
        // record_android requires minSdk 23+
        minSdk = maxOf(23, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        // Driven by pubspec.yaml (version: x.y.z+build)
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Do not set ndk.abiFilters here — conflicts with `flutter build apk --split-per-abi`.
        // Use --split-per-abi (or appbundle) so each device only gets one ABI.
    }
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias") ?: ""
            keyPassword = keystoreProperties.getProperty("keyPassword") ?: ""
            storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
            storePassword = keystoreProperties.getProperty("storePassword") ?: ""
        }
    }

    buildTypes {
        getByName("release") {
            isMinifyEnabled = true
            isShrinkResources = true
            signingConfig = signingConfigs.getByName("release")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    // Agora ships many optional AI / beauty / AV1 extensions we don't use for
    // basic voice/video calls — excluding them cuts tens of MB per ABI.
    packaging {
        jniLibs {
            excludes += listOf(
                "**/libagora_lip_sync_extension.so",
                "**/libagora_spatial_audio_extension.so",
                "**/libagora_segmentation_extension.so",
                "**/libagora_face_capture_extension.so",
                "**/libagora_face_detection_extension.so",
                "**/libagora_content_inspect_extension.so",
                "**/libagora_clear_vision_extension.so",
                "**/libagora_video_quality_analyzer_extension.so",
                "**/libagora_video_av1_encoder_extension.so",
                "**/libagora_video_av1_decoder_extension.so",
                "**/libagora_audio_beauty_extension.so",
                "**/libagora_screen_capture_extension.so",
                // Keep ains / aec if you want better call audio; comment these two to restore.
                "**/libagora_ai_noise_suppression_extension.so",
                "**/libagora_ai_echo_cancellation_extension.so",
            )
        }
    }
}

flutter {
    source = "../.."
}
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.3")
}
apply(plugin = "com.google.gms.google-services")
