# Google Play doporučení „Optimalizací R8 můžete zlepšit paměť a výkon":
# dřívější plošná pravidla `-keep class io.flutter.** { *; }` a
# `-keep class com.google.firebase.** { *; }` držela v DEXu prakticky celý
# engine + Firebase neoptimalizované a R8 tím de facto vypínala.
# Flutter embedding i Firebase si svá keep pravidla dodávají samy
# (consumer rules v AAR + @Keep anotace) — plošné keepy nejsou potřeba.

# Stripe SDK — platby jsou kritické, Payment Sheet používá reflexi/Parcelable
# napříč SDK, proto tady plošný keep záměrně NECHÁVÁME.
-dontwarn com.stripe.android.**
-keep class com.stripe.android.** { *; }

# Supabase / OkHttp / Retrofit (used internally)
-dontwarn okhttp3.**
-dontwarn okio.**

# Flutter deferred components reference Play Core split classes that the app
# does not use — suppress R8 "Missing class" errors during minify.
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }
