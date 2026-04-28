import java.util.Properties
import java.io.FileInputStream

// --- TRIDETA KEYSTORE LOGIC START ---
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
// --- TRIDETA KEYSTORE LOGIC END ---

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.trideta_v2"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // 🚨 ENABLE DESUGARING: Allows modern Java features used by notifications
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.trideta_v2"
        // 🚨 REQUIRED: Desugaring requires minSdk 21 or higher
        minSdk = flutter.minSdkVersion 
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
        // 🚨 MULTIDEX: Handles the large method count from Firebase + Local Notifications
        multiDexEnabled = true
    }

    // --- TRIDETA SIGNING CONFIG START ---
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            val keystoreFilePath = keystoreProperties.getProperty("storeFile")
            if (keystoreFilePath != null) {
                storeFile = file(keystoreFilePath)
            }
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }
    // --- TRIDETA SIGNING CONFIG END ---

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            // Add shrinkResources and minifyEnable here later if you want a smaller APK
        }
    }
}

dependencies {
    // 🚨 DESUGARING LIBRARY: The bridge that makes notifications work on older Androids
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}