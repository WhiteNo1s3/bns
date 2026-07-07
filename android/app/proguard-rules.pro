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
