#!/bin/bash

echo "🔧 FINALE LÖSUNG - NDK + Signing Fix"

# 1. NDK 27 installieren (falls nicht vorhanden)
echo "📦 Prüfe NDK 27.0.12077973..."
if [ ! -d "$HOME/Library/Android/sdk/ndk/27.0.12077973" ]; then
    echo "⚠️ NDK 27 nicht gefunden, installiere..."
    sdkmanager "ndk;27.0.12077973"
fi

# 2. Backup
cp android/app/build.gradle android/app/build.gradle.backup

# 3. Korrektes build.gradle mit NDK 27 UND funktionierender Signing
cat > android/app/build.gradle << 'EOF'
plugins {
    id "com.android.application"
    id "kotlin-android"
    id "dev.flutter.flutter-gradle-plugin"
}

def localProperties = new Properties()
def localPropertiesFile = rootProject.file('local.properties')
if (localPropertiesFile.exists()) {
    localPropertiesFile.withReader('UTF-8') { reader ->
        localProperties.load(reader)
    }
}

def flutterVersionCode = localProperties.getProperty('flutter.versionCode')
if (flutterVersionCode == null) {
    flutterVersionCode = '1'
}

def flutterVersionName = localProperties.getProperty('flutter.versionName')
if (flutterVersionName == null) {
    flutterVersionName = '1.0'
}

android {
    namespace "com.example.nyantv"
    compileSdkVersion 34
    ndkVersion "27.0.12077973"

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_1_8
        targetCompatibility JavaVersion.VERSION_1_8
    }

    kotlinOptions {
        jvmTarget = '1.8'
    }

    sourceSets {
        main.java.srcDirs += 'src/main/kotlin'
    }

    defaultConfig {
        applicationId "com.example.nyantv"
        minSdkVersion 21
        targetSdkVersion 34
        versionCode flutterVersionCode.toInteger()
        versionName flutterVersionName
    }

    signingConfigs {
        release {
            storeFile file('keystore.jks')
            storePassword 'android'
            keyAlias 'androiddebugkey'
            keyPassword 'android'
        }
    }

    buildTypes {
        release {
            signingConfig signingConfigs.release
            minifyEnabled false
            shrinkResources false
        }
        debug {
            signingConfig signingConfigs.release
        }
    }
}

flutter {
    source '../..'
}

dependencies {}
EOF

echo "✅ build.gradle mit NDK 27 erstellt"

# 4. Gradle properties cleanup
cat > android/gradle.properties << 'EOF'
org.gradle.jvmargs=-Xmx4G
android.useAndroidX=true
android.enableJetifier=true
EOF

echo "✅ gradle.properties bereinigt"

# 5. local.properties update
cat > android/local.properties << EOF
sdk.dir=$HOME/Library/Android/sdk
flutter.sdk=$PROJECT_FLUTTER
ndk.dir=$HOME/Library/Android/sdk/ndk/27.0.12077973
EOF

echo "✅ local.properties aktualisiert"

# 6. Clean
rm -rf android/.gradle android/build build

echo ""
echo "🔥 Starte Build..."
flutter build apk --split-per-abi --release