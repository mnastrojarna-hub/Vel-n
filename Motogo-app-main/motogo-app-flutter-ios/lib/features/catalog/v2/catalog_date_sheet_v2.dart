import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../catalog_provider.dart';

/// Same write as the old `_onRangeSelected`.
void catSetDates(WidgetRef ref, DateTime start, DateTime end) {
  final filter = ref.read(catalogFilterProvider);
  ref.read(catalogFilterProvider.notifier).state = filter.copyWith(
    startDate: () => start,
    endDate: () => end,
  );
}

/// Same write as the old calendar `onReset`.
void catClearDates(WidgetRef ref) {
  final filter = ref.read(catalogFilterProvider);
  ref.read(catalogFilterProvider.notifier).state = filter.copyWith(
    startDate: () => null,
    endDate: () => null,
  );
}
