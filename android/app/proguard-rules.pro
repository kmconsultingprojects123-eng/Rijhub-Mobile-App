# Please add these rules to your existing keep rules in order to suppress warnings.
# This is generated automatically by the Android Gradle plugin.
-dontwarn com.google.errorprone.annotations.CanIgnoreReturnValue
-dontwarn com.google.errorprone.annotations.CheckReturnValue
-dontwarn com.google.errorprone.annotations.Immutable
-dontwarn com.google.errorprone.annotations.RestrictedApi
-dontwarn com.google.j2objc.annotations.RetainedWith
-dontwarn javax.annotation.Nullable
-dontwarn javax.annotation.concurrent.GuardedBy
-dontwarn org.bouncycastle.jce.provider.BouncyCastleProvider
-dontwarn org.bouncycastle.pqc.jcajce.provider.BouncyCastlePQCProvider
-keep class org.xmlpull.v1.** { *; }

# Keep Flutter Plugin registrant and platform views
-keep class io.flutter.app.** { *; }
-keep class io.flutter.embedding.engine.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.facade.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.embedding.engine.FlutterEngine { *; }

# Keep OkHttp & Retrofit (if used)
-dontwarn okhttp3.**
-keep class okhttp3.** { *; }
-keep class retrofit2.** { *; }

# Keep Firebase / Play Services placeholders (no-op rules to suppress warnings)
-dontwarn com.google.android.gms.**
-dontwarn com.google.firebase.**

# Add Play Core / SplitInstall keep rules for deferred components
# Keep the Play Core install API used by Flutter's deferred components
-keep class com.google.android.play.core.splitinstall.** { *; }
-keep class com.google.android.play.core.tasks.** { *; }
-dontwarn com.google.android.play.core.**

# If Play Core is provided at runtime (Play Store), suppress warnings but keep references
# Keep the Play Core interfaces used by Flutter engine
-keepclassmembers class * {
    public void onStateUpdate(...);
}

# Keep the native entry points called from JNI
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep classes referenced from reflection by Dart/Flutter
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# Suppress common warnings from generated code
-dontwarn io.flutter.embedding.**
-dontwarn io.flutter.plugin.**

# End of conservative rules
