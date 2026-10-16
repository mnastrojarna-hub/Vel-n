import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Mode of the v2 Motorky tab (PLAN §2.2.1 / §2.2.4): browse the fleet or
/// the price calculator. In-memory only (per app session, like the web's
/// `.km` switch); nothing is written anywhere. Home's funnel sets [calc]
/// (+ `calcStateProvider.notifier.prefill`) before `context.go('/search')`.
enum CatalogMode { find, calc }

final catalogModeProvider = StateProvider<CatalogMode>((_) => CatalogMode.find);
