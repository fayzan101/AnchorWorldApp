# ProGuard / R8 rules for Anchor (Flutter app)
#
# In most Flutter apps, the default Android shrinker configuration is enough
# because most code runs in the Dart VM and native plugins ship their own
# consumer ProGuard rules. This file mainly ensures Flutter embedding and
# plugin entry points are not removed or obfuscated in a way that breaks
# reflection or Android manifest references.

# Keep Flutter embedding / engine APIs that can be referenced from Android
# manifest entries or via reflection.
-keep class io.flutter.embedding.android.** { *; }
-keep class io.flutter.embedding.engine.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep generated Firebase messaging / notification receivers and services.
# Most Firebase AARs already ship consumer rules, but these are safe guards.
-keep class com.google.firebase.messaging.** { *; }
-keep class com.google.firebase.iid.** { *; }

# Agora RTC — referenced via JNI / reflection; keep and ignore desugar stub.
-keep class io.agora.** { *; }
-dontwarn io.agora.**
-dontwarn com.google.devtools.build.android.desugar.runtime.ThrowableExtension

# If you add custom Java/Kotlin code that uses reflection or is referenced
# only from the AndroidManifest, add explicit keep rules for those classes
# here to avoid them being removed or renamed in release builds.

# Suppress warnings about Play Core split install classes that are referenced
# by Flutter's deferred components support but are not used in this app.
# These rules come from build/app/outputs/mapping/release/missing_rules.txt.
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task
