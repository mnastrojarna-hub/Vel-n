import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/friendly_error.dart';
import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/chrome/mg_chrome_metrics.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/states/mg_state_parts.dart';
import '../../../../core/v2/states/mg_state_sheet.dart';
import '../../../../core/v2/states/mg_tone.dart';
import '../../../../core/v2/widgets/mg_emoji_map.dart';
import '../../../../core/v2/widgets/mg_toast.dart';
import '../../../../core/widgets/error_feedback.dart' show openFixSettings;
import '../../ride_recorder.dart' show RideStartResult;

/// Ride start / stop results in the v2 look (DESIGN_V22 §4.4, Stavy group
/// 16): every failure that needs an action is a T2 sheet (what · why ·
/// working action), never a toast; "saved" is the success sheet (✓ draws,
/// pops, one ripple — `MgToneDisc(ok)`). Started / armed stay a toast. The
/// SAME result enum and the SAME actions as the old messages: login (the
/// Moje login push), `openFixSettings` (location off → location settings,
/// else app settings), retry = the caller's own start / resume.
Future<void> showRideStartResultV2(BuildContext context, RideStartResult r,
    {bool armed = false, VoidCallback? onRetry}) async {
  final tr = t(context);
  // The sheet sits on the root navigator: close it, then run the action.
  final nav = Navigator.of(context, rootNavigator: true);
  VoidCallback? then(VoidCallback? f) => f == null
      ? null
      : () {
          nav.pop();
          f();
        };
  MgStateAction settings(FriendlyKind k) =>
      MgStateAction(tr.tr('eoOpenSettings'), then(() => openFixSettings(FriendlyError(k))));
  final back = MgStateAction(tr.tr('back'), null);
  switch (r) {
    case RideStartResult.ok:
      final lift = MgChromeScope.chromeOf(context)?.dockHeight ?? 0;
      showMgToast(context, mgStripEmoji(tr.tr(armed ? 'rpToastArmed' : 'rideManualStarted')),
          icon: MgIcons.recordDot, lift: lift);
    case RideStartResult.notSignedIn:
      final router = GoRouter.maybeOf(context);
      await showMgStateSheet<void>(context,
          tone: MgTone.info,
          icon: MgIcons.user,
          title: tr.tr('v2UxRrLoginT'),
          why: tr.tr('v2UxRrLoginW'),
          support: false,
          primary: MgStateAction(tr.tr('loginBtn'), router == null ? null : then(() => router.push('/login'))),
          secondary: back);
    case RideStartResult.locationOff:
      await showMgStateSheet<void>(context,
          tone: MgTone.warn,
          icon: MgIcons.gps,
          title: tr.tr('v2UxRrLocOffT'),
          why: tr.tr('v2UxRrLocOffW'),
          support: false,
          primary: settings(FriendlyKind.locationOff),
          secondary: back);
    case RideStartResult.noPermission:
      await showMgStateSheet<void>(context,
          tone: MgTone.warn,
          icon: MgIcons.gps,
          title: tr.tr('v2UxRrPermT'),
          why: tr.tr('v2UxRrPermW'),
          support: false,
          primary: settings(FriendlyKind.permission),
          secondary: back);
    case RideStartResult.imprecise:
      await showMgStateSheet<void>(context,
          tone: MgTone.warn,
          icon: MgIcons.target,
          title: tr.tr('v2UxRrPreciseT'),
          why: tr.tr('v2UxRrPreciseW'),
          support: false,
          primary: settings(FriendlyKind.permission),
          secondary: back);
    case RideStartResult.failed:
      await showMgStateSheet<void>(context,
          tone: MgTone.err,
          icon: MgIcons.wifiOff,
          title: tr.tr('v2UxRrFailT'),
          // G-1040/G-1041: the real cause (no internet / unsaved previous
          // ride) as in the old look, not "restart the app".
          why: tr.tr('eoRideStartFailed'),
          primary: MgStateAction(tr.tr('retry'), then(onRetry)),
          secondary: back);
  }
}

/// After a stop: [kept] true = saved (success sheet), false = shorter than
/// 1 km (not saved), null = offline — the recorder retries every 2 min.
Future<void> showRideStopResultV2(BuildContext context, bool? kept) {
  final tr = t(context);
  final done = MgStateAction(tr.tr('submitSuccessOk'), null);
  if (kept == true) {
    return showMgStateSheet<void>(context,
        tone: MgTone.ok,
        title: tr.tr('v2UxRrSavedT'),
        why: tr.trArgs('v2UxRrSavedW', {'where': '${tr.tr('myExpTitle')} › ${tr.tr('v2RideSubRides')}'}),
        support: false,
        primary: done);
  }
  if (kept == false) {
    return showMgStateSheet<void>(context,
        tone: MgTone.info,
        icon: MgIcons.ruler,
        title: tr.tr('v2UxRrShortT'),
        why: tr.tr('v2UxRrShortW'),
        support: false,
        primary: MgStateAction(tr.tr('v2UxRrGotIt'), null));
  }
  return showMgStateSheet<void>(context,
      tone: MgTone.pending,
      icon: MgIcons.wifiOff,
      title: tr.tr('v2UxRrOfflineT'),
      why: tr.tr('v2UxRrOfflineW'),
      support: false,
      primary: MgStateAction(tr.tr('v2UxRrGotIt'), null));
}
