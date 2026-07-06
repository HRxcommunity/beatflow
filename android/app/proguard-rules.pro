# ─── Flutter ───────────────────────────────────────────────────────────────
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.**

# ─── Firebase ──────────────────────────────────────────────────────────────
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# ─── Agora RTC ─────────────────────────────────────────────────────────────
-keep class io.agora.** { *; }
-dontwarn io.agora.**

# ─── Hive ──────────────────────────────────────────────────────────────────
-keep class com.beatflow.** { *; }
-keepclassmembers class * {
    @hive.annotations.HiveType *;
    @hive.annotations.HiveField *;
}

# ─── just_audio / audio_service ────────────────────────────────────────────
-keep class com.ryanheise.** { *; }
-dontwarn com.ryanheise.**

# ─── on_audio_query ────────────────────────────────────────────────────────
-keep class com.lucasjosino.** { *; }

# ─── OkHttp ────────────────────────────────────────────────────────────────
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }

# ─── Kotlin ────────────────────────────────────────────────────────────────
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}

# ─── Enum classes ──────────────────────────────────────────────────────────
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# ─── Serialization ─────────────────────────────────────────────────────────
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes InnerClasses,EnclosingMethod

# ─── androidx.window (OEM foldable APIs — optional, loaded from firmware) ──
-dontwarn androidx.window.extensions.**
-dontwarn androidx.window.sidecar.**
-dontwarn androidx.window.**

# ─── WebView / webview_flutter ─────────────────────────────────────────────
# Without these rules, R8 strips the @JavascriptInterface annotations and the
# JS-to-Java bridge that backs addJavaScriptChannel() → JS postMessage calls
# silently fail in release builds (works in debug because minification is off).
#
# Also protects the Flutter platform-view MethodChannel glue used by
# webview_flutter_android to route setMediaPlaybackRequiresUserGesture() etc.
-keepattributes JavascriptInterface
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
-keep class androidx.webkit.** { *; }
-keep class android.webkit.** { *; }
# webview_flutter_android plugin classes
-keep class io.flutter.plugins.webviewflutter.** { *; }
-dontwarn io.flutter.plugins.webviewflutter.**

# ─── OTA FileProvider ───────────────────────────────────────────────────────
-keep class androidx.core.content.FileProvider { *; }

# ─── Common transitive warnings ────────────────────────────────────────────
-dontwarn javax.annotation.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**
