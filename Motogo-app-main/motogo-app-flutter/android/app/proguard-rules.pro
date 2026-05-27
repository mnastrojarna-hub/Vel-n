# Flutter-specific
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Stripe SDK
-dontwarn com.stripe.android.**
-keep class com.stripe.android.** { *; }

# Firebase
-keep class com.google.firebase.** { *; }

# Supabase / OkHttp / Retrofit (used internally)
-dontwarn okhttp3.**
-dontwarn okio.**

# Flutter deferred components reference Play Core split classes that the app
# does not use — suppress R8 "Missing class" errors during minify.
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }
