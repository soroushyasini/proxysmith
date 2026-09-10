# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Kotlin coroutines
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}
-keepclassmembers class kotlinx.coroutines.** {
    volatile <fields>;
}

# libv2ray
-keep class libv2ray.** { *; }

# Keep your own package
-keep class ir.proxysmith.** { *; }

# General Android
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-dontwarn javax.annotation.**

# Flutter Play Store deferred components — not used, suppress all missing class errors
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.android.FlutterPlayStoreSplitApplication
-dontwarn io.flutter.embedding.engine.deferredcomponents.**

# Tell R8 not to fail on missing classes — treat them as warnings
-ignorewarnings
