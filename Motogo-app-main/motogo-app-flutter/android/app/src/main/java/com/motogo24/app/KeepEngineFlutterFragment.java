package com.motogo24.app;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import java.util.List;

import io.flutter.embedding.android.FlutterFragment;
import io.flutter.embedding.android.RenderMode;
import io.flutter.embedding.android.TransparencyMode;

/**
 * FlutterFragment, který při zavření okna engine NEZNIČÍ — o tom rozhoduje
 * {@link MainActivity#onDestroy()} přes {@link RideEngineKeeper} (běžně ho
 * zničí stejně jako dřív, jen během záznamu jízdy ho nechá běžet).
 *
 * <p>Výchozí builder nového enginu nastavuje „zničit s fragmentem" natvrdo,
 * proto vlastní třída. V Javě kvůli null hodnotám, které FlutterFragmentActivity
 * předává (initialRoute = null → Flutter vezme deep link z intentu).
 */
public class KeepEngineFlutterFragment extends FlutterFragment {

  @Override
  public boolean shouldDestroyEngineWithHost() {
    return false;
  }

  /** Stejné nastavení jako FlutterFragmentActivity.createFlutterFragment() (nový engine). */
  @NonNull
  static FlutterFragment create(
      @NonNull String dartEntrypoint,
      @Nullable String dartLibraryUri,
      @Nullable List<String> dartEntrypointArgs,
      @Nullable String initialRoute,
      @Nullable String appBundlePath,
      boolean handleDeeplinking,
      @NonNull RenderMode renderMode,
      boolean opaque,
      boolean attachToActivity) {
    return new FlutterFragment.NewEngineFragmentBuilder(KeepEngineFlutterFragment.class)
        .dartEntrypoint(dartEntrypoint)
        .dartLibraryUri(dartLibraryUri)
        .dartEntrypointArgs(dartEntrypointArgs)
        .initialRoute(initialRoute)
        .appBundlePath(appBundlePath)
        .handleDeeplinking(handleDeeplinking)
        .renderMode(renderMode)
        .transparencyMode(opaque ? TransparencyMode.opaque : TransparencyMode.transparent)
        .shouldAttachEngineToActivity(attachToActivity)
        .shouldDelayFirstAndroidViewDraw(renderMode == RenderMode.surface)
        .shouldAutomaticallyHandleOnBackPressed(true)
        .build();
  }
}
