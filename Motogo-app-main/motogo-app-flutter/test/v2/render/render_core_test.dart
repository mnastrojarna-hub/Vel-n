// verify:render — shared v2 state templates, dialogs, snackbars (large
// text + reduced motion, every language × 320/360/412).
import 'render_harness.dart';
import 'cases_core.dart';

void main() => renderMatrix(coreCases());
