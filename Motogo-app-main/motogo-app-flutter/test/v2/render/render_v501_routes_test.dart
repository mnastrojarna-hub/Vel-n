// verify:render — v5.0.1 Trasy list (one route per screen, toolbar,
// active filters).
import 'render_harness.dart';
import 'cases_v501_routes.dart';

void main() => renderMatrix(v501RoutesCases(), setUpAllExtra: setUpRoutePhotos);
