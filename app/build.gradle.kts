import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

val localProps = Properties().apply {
    val f = rootProject.file("local.properties")
    if (f.exists()) load(f.inputStream())
}

fun secret(key: String): String =
    localProps.getProperty(key)
        ?: project.findProperty(key)?.toString()
        ?: ""

android {
    namespace = "com.nyantv"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.nyantv"
        minSdk = 26
        targetSdk = 35
        versionCode = 3
        versionName = "1.0.2"

        buildConfigField("String", "ANILIST_CLIENT_ID",     "\"${secret("ANILIST_CLIENT_ID")}\"")
        buildConfigField("String", "ANILIST_CLIENT_SECRET", "\"${secret("ANILIST_CLIENT_SECRET")}\"")
        buildConfigField("String", "MAL_CLIENT_ID",         "\"${secret("MAL_CLIENT_ID")}\"")
        buildConfigField("String", "MAL_CLIENT_SECRET",     "\"${secret("MAL_CLIENT_SECRET")}\"")
        buildConfigField("String", "SIMKL_CLIENT_ID",       "\"${secret("SIMKL_CLIENT_ID")}\"")
        buildConfigField("String", "SIMKL_CLIENT_SECRET",   "\"${secret("SIMKL_CLIENT_SECRET")}\"")
        buildConfigField("String", "TMDB_API_KEY",          "\"${secret("TMDB_API_KEY")}\"")
        buildConfigField("String", "REDIRECT_URI",          "\"nyantv://callback\"")

        val abiFilter = secret("ABI_FILTER").ifBlank { null }
        if (abiFilter != null) {
            ndk { abiFilters += abiFilter }
        }
    }

    signingConfigs {
        create("release") {
            storeFile     = file(secret("KEYSTORE_PATH").ifBlank { "nyantv.jks" })
            storePassword = secret("KEYSTORE_PASSWORD")
            keyAlias      = secret("KEY_ALIAS")
            keyPassword   = secret("KEYSTORE_PASSWORD")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            applicationIdSuffix = ".debug"
            isDebuggable = true
        }
        create("benchmark") {
            initWith(getByName("release"))
            applicationIdSuffix = ".debug"
            isMinifyEnabled = true
            isDebuggable = false
            isProfileable = true
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    buildFeatures {
        compose = true
        buildConfig = true
        aidl = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        compilerOptions {
            jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
            freeCompilerArgs.add("-Xcontext-parameters")
        }
    }
}

dependencies {
    implementation("androidx.compose.runtime:runtime-saveable:1.11.0")
    implementation("androidx.compose.foundation:foundation:1.11.0")
    implementation("androidx.compose.foundation:foundation-layout:1.11.0")
    implementation("androidx.compose.foundation:foundation:1.11.1")
    val composeBom = platform("androidx.compose:compose-bom:2024.09.03")
    implementation(composeBom)

    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3:1.5.0-alpha18")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.10.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.10.0")

    // Navigation
    implementation("androidx.navigation:navigation-compose:2.9.8")

    // Networking
    implementation("com.squareup.okhttp3:okhttp:5.3.2")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.11.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")

    // Images
    implementation("io.coil-kt:coil-compose:2.7.0")

    // OAuth browser
    implementation("androidx.browser:browser:1.10.0")

    // Media player
    val media3 = "1.10.1"
    implementation("androidx.media3:media3-exoplayer:${media3}")
    implementation("androidx.media3:media3-exoplayer-hls:${media3}")
    implementation("androidx.media3:media3-exoplayer-dash:${media3}")
    implementation("androidx.media3:media3-exoplayer-smoothstreaming:${media3}")
    implementation("androidx.media3:media3-datasource-okhttp:${media3}")
    implementation("androidx.media3:media3-extractor:${media3}")
    // Libmpv fallback for hls
    implementation("dev.jdtech.mpv:libmpv:1.0.0") {
        exclude(group = "dev.jdtech.mpv", module = "libmpv-x86")
        exclude(group = "dev.jdtech.mpv", module = "libmpv-x86_64")
    }

    // Aniyomi
    implementation("org.jsoup:jsoup:1.18.3")
    implementation("io.reactivex:rxjava:1.3.8")
    implementation("com.squareup.okhttp3:logging-interceptor:5.3.2")
    implementation("androidx.datastore:datastore-preferences:1.1.7")
    implementation("com.squareup.okhttp3:okhttp-brotli:5.3.2")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json-okio:1.11.0")
    implementation("androidx.preference:preference-ktx:1.2.1")
    implementation("uy.kohesive.injekt:injekt-core:1.16.1")

    // Watch next
    implementation("androidx.tvprovider:tvprovider:1.1.0")

    debugImplementation("androidx.compose.ui:ui-tooling")
}
