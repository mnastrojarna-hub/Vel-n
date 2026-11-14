import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Mode of the v2 Motorky tab (PLAN §2.2.1 / §2.2.4): browse the fleet or
/// the price calculator. In-memory only (per app session, like the web's
/// `.km` switch); nothing is written anywhere.
///
/// Every fresh mount of the Motorky tab starts in [find] (all the existing
/// "find a bike" entries — Pobočka "REZERVOVAT ZDE", Pobočky, empty
/// Rezervace, "motorka už není v nabídce" — expect the bike list with their
/// filter). Only an explicit request opens the calculator: Home's funnel
/// sets [catalogCalcRequestProvider] (+ `calcStateProvider.prefill`) right
/// before `context.go('/search')`; `MotorkyScreenV2` consumes it once.
enum CatalogMode { find, calc }

/// Mode of the mounted Motorky tab (switch taps, "show free" in the
/// calculator). Reset to the mount's mode by `MotorkyScreenV2`.
final catalogModeProvider = StateProvider<CatalogMode>((_) => CatalogMode.find);

/// One-shot "open the Motorky tab in the calculator" (Home funnel).
final catalogCalcRequestProvider = StateProvider<bool>((_) => false);
