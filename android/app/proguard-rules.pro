# Flutter entrypoints/plugins
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# WebView + JS bridge (3D model-viewer runtime)
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
-keep class androidx.webkit.** { *; }
-dontwarn androidx.webkit.**

# Google Mobile Ads SDK
-keep class com.google.android.gms.ads.** { *; }
-keep class com.google.android.gms.common.** { *; }
-dontwarn com.google.android.gms.**

# share_plus / FileProvider
-keep class dev.fluttercommunity.plus.share.** { *; }
-keep class androidx.core.content.FileProvider { *; }
