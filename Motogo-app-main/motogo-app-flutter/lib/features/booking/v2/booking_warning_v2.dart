import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/states/mg_state_banner.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/widgets/mg_buttons.dart';

/// The form's blockers as T3 banners (V22 §5.2), with the SAME texts the
/// old tree showed and the SAME fixes: missing gear sizes (amber, the
/// form's own list), validation error (red: licence / overlap / rental
/// length / pickup time), incomplete profile (amber + "Doplnit v profilu"
/// → /profile) and unknown availability (red + retry).
class BookingWarningsV2 extends StatelessWidget {
  final List<String> missingSizes;
  final String? err;
  final String? profileErr;
  final bool bookedFailed;
  final VoidCallback onCompleteProfile;
  final VoidCallback onRetryBooked;

  const BookingWarningsV2({
    super.key,
    required this.missingSizes,
    required this.err,
    required this.profileErr,
    required this.bookedFailed,
    required this.onCompleteProfile,
    required this.onRetryBooked,
  });

  bool get isEmpty => missingSizes.isEmpty && err == null && profileErr == null && !bookedFailed;

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    Widget gap(Widget w) => Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: MgEnter(child: w));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (missingSizes.isNotEmpty)
        gap(MgStateBanner(
          tone: MgTone.warn,
          icon: MgIcons.helmet,
          title: tr.tr('v2BkSizesTitle'),
          text: '${tr.tr('missingLabel')}: ${missingSizes.join(', ')}',
        )),
      if (err != null)
        gap(MgShake(
          trigger: err,
          child: MgStateBanner(
            tone: MgTone.err,
            title: tr.tr('v2BkErrTitle'),
            text: err,
          ),
        )),
      if (profileErr != null)
        gap(MgStateBanner(
          tone: MgTone.warn,
          icon: MgIcons.idCard,
          title: tr.tr('v2BkProfileTitle'),
          text: profileErr,
          actions: [
            MgBtnInk(label: tr.tr('completeProfileBtn'), onTap: onCompleteProfile, height: 48, expand: false),
          ],
        )),
      if (bookedFailed)
        gap(MgStateBanner(
          tone: MgTone.err,
          icon: MgIcons.calendarX,
          title: tr.tr('fxBookedDatesFail'),
          text: tr.tr('fxBookedDatesWait'),
          actions: [
            MgBtnGhostLight(label: tr.tr('eoRetry'), icon: MgIcons.refresh, onTap: onRetryBooked, height: 44, expand: false),
          ],
        )),
    ]);
  }
}
