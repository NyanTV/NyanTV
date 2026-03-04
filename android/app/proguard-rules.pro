# ============================================================
# media_kit
# ============================================================
-keep class com.alexmercerind.mediakit.** { *; }
-keep class com.alexmercerind.media_kit_video.** { *; }
-keep class com.alexmercerind.media_kit_libs_android_video.** { *; }
-keep class com.alexmercerind.media_kit_libs_video.** { *; }
-dontwarn com.alexmercerind.**

# ============================================================
# Isar (local database)
# ============================================================
-keep class io.isar.** { *; }
-keep class isar.** { *; }
-keep class io.realm.transformer.** { *; }
-dontwarn io.isar.**

# ============================================================
# Flutter
# ============================================================
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# ============================================================
# App package
# ============================================================
-keep class com.mukatos.nyantv.** { *; }
-keepclassmembers class com.mukatos.nyantv.** { *; }

# ============================================================
# Google Play Core
# Absent in sideloaded APKs — kept to avoid R8 "Missing class" errors
# ============================================================
-keep class com.google.android.play.core.** { *; }

# ============================================================
# Firebase / Google Mobile Services
# ============================================================
-keep class com.google.gson.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# ============================================================
# Kotlin
# ============================================================
-keep @kotlin.Metadata class **
-keepclassmembers class kotlin.Metadata {
    public <methods>;
}
-dontwarn kotlin.**
-keepclassmembers class **$WhenMappings {
    <fields>;
}

# Kotlin Coroutines
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}
-dontwarn kotlinx.coroutines.**

# ============================================================
# JNI / Native methods (flutter_rust_bridge + general)
# ============================================================
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}

# ============================================================
# OkHttp / Retrofit / Networking
# ============================================================
-keep class okhttp3.** { *; }
-keep class retrofit2.** { *; }
-dontwarn okhttp3.**
-dontwarn okio.**

# ============================================================
# MPV (libmpv video player)
# ============================================================
-keep class is.xyz.mpv.** { *; }
-dontwarn is.xyz.mpv.**

# ============================================================
# WebView JavaScript Interface
# ============================================================
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# ============================================================
# Reflection — annotations, generics, debug info
# ============================================================
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes SourceFile,LineNumberTable
-keepattributes Exceptions,InnerClasses

# ============================================================
# R8 / ProGuard behavior
# ============================================================
-verbose
-dontnote
-ignorewarnings

# ============================================================
# Misc suppressed warnings
# ============================================================
-dontwarn sun.misc.**
-dontwarn java.lang.invoke.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**