// verify:render — hide-on-scroll + one bike per screen: Motorky / Domů on a
// bike with the bars folded, the detail scrolled (8 languages × sizes).
import 'dart:io';

import '../support/fakes_home.dart' show mockPathProvider;
import '../support/fakes_routes_http.dart';
import 'cases_bars.dart';
import 'render_harness.dart';

void main() => renderMatrix(barsRenderCases(), setUpAllExtra: () async {
      mockPathProvider();
      HttpOverrides.global = RtFakeHttpOverrides();
    });
