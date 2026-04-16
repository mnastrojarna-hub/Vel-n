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
