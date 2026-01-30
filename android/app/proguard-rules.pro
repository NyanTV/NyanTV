-keep class com.alexmercerind.mediakit.** { *; }
-keep class com.alexmercerind.media_kit_video.** { *; }
-keep class com.alexmercerind.media_kit_libs_android_video.** { *; }
-keep class com.alexmercerind.media_kit_libs_video.** { *; }

-keepclasseswithmembernames class * {
    native <methods>;
}

-dontwarn com.alexmercerind.**

-keep class io.isar.** { *; }
-keep class io.realm.transformer.** { *; }
-dontwarn io.isar.**