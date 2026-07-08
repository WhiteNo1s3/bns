# BNS release rules. Flutter's own keep rules are injected by the Flutter
# Gradle plugin; these cover the plugins we ship.

# Flutter embedding + plugin registrants are reflectively loaded.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }

# home_widget providers are instantiated by the system from the manifest.
-keep class es.antonborri.home_widget.** { *; }
-keep class com.whiteno1se.bns.** extends android.appwidget.AppWidgetProvider { *; }

# flutter_local_notifications uses reflection for notification details.
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# ...and Gson under the hood, which needs generic type signatures at runtime.
# Without these, R8 strips them and scheduling dies with "Missing type
# parameter" (caught live on the S23 Ultra, 2026-07-08).
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.** { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep public class * implements java.lang.reflect.Type

# Flutter engine references Play Core split-install (deferred components) —
# we don't use them; the classes are absent by design. Standard suppression.
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
