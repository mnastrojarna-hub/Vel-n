import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../feature_flags.dart' show appV2UiProvider;
import '../tokens/mg_theme_v2.dart';
import 'v2_scope.dart';

/// The kill-switch gate inserted ONCE in `MaterialApp.router(builder:)`
/// around the router's navigator (main.dart): [MgV2Scope] from
/// `appV2UiProvider` (screens ask `MgV2.on`, the router picks with
/// `V2Switch`) and, while ON, the v2 theme overlay (only snackbar / dialog /
/// bottom-sheet / progress shapes — see `MgThemeV2`). OFF = the app theme
/// untouched, every seam builds the old UI.
class MgV2Gate extends ConsumerWidget {
  final Widget child;
  const MgV2Gate({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(appV2UiProvider);
    final base = Theme.of(context);
    return MgV2Scope(
      enabled: on,
      child: Theme(data: on ? MgThemeV2.overlay(base) : base, child: child),
    );
  }
}
