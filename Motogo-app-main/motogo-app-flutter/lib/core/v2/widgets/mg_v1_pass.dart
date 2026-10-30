import 'package:flutter/widgets.dart';

import '../flag/v2_scope.dart';
import '../tokens/mg_colors.dart';
import 'mg_back_v2.dart';

/// Token pass for the screens that keep their v1 body inside the v2 look
/// (PLAN "T": SOS flow, registration — r2 2026-10-29, owner decides on a
/// full SOS / Přihlášení board port before 4.2.0): v2 page canvas instead
/// of the v1 mint and the v2 back disc with the SAME onTap. Old look (and
/// the iOS tree, which has no v2) unchanged.

/// v2 page canvas `#F4F7F5`, else the v1 page colour.
Color mgV1PageColor(BuildContext context, Color v1) => MgV2.on(context) ? MgColors.canvas : v1;

/// v2 back disc (44 px, hit 48) for a v1 back control; [v1] stays the
/// old look. [onTap] = the old control's action.
Widget mgV1Back(BuildContext context,
        {required VoidCallback onTap, required Widget v1, MgBackStyle style = MgBackStyle.light}) =>
    MgV2.on(context) ? MgV2Back(onTap: onTap, style: style) : v1;
