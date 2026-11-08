import 'package:flutter/widgets.dart';

import '../../../core/i18n/i18n_provider.dart';

/// Popisek pod volbou dokladu ve v2 skeneru: počet fotek + co přesně se
/// vyfotí, podle skutečných kroků [keys] (id_* / passport_* / dl_*), tedy i
/// v režimu „doplnit chybějící“ jen to, co chybí. Logiku skeneru nemění.
String scanChoiceSub(BuildContext context, List<String> keys) {
  final tr = t(context);
  String? part(String doc, String both, String front, String back) {
    final f = keys.contains('${doc}_front'), b = keys.contains('${doc}_back');
    if (f && b) return tr.tr(both);
    if (f) return tr.tr(front);
    if (b) return tr.tr(back);
    return null;
  }

  final parts = [
    part('id', 'v2UxAsmScanIdBoth', 'v2UxAsmScanIdFront', 'v2UxAsmScanIdBack'),
    part('passport', 'v2UxAsmScanPassBoth', 'v2UxAsmScanPassFront', 'v2UxAsmScanPassBack'),
    part('dl', 'v2UxAsmScanDlBoth', 'v2UxAsmScanDlFront', 'v2UxAsmScanDlBack'),
  ].whereType<String>().toList();
  final n = keys.length;
  final photos = n == 1 ? tr.tr('v2UxAsmScanPhotos1') : tr.trArgs('v2UxAsmScanPhotosN', {'n': n});
  return parts.isEmpty ? photos : '$photos: ${parts.join(', ')}';
}
