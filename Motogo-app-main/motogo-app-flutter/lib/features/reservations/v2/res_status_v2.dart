import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/pending_booking_fab_provider.dart';
import '../../../core/widgets/net_image.dart';
import '../../../core/v2/calendar/trip_day_state.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim_loops.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../reservation_models.dart';

/// Shared bits of the v2 reservations look (PLAN §2.4): status words and
/// pills, payment status label, date lines. Pure presentation of the
/// existing `Reservation` fields — no rule here decides anything new.

/// Status word exactly as the old list / detail (`active`, `upcoming`,
/// `completed`, `cancelled`).
String resStatusLabel(AppTranslations tr, ResStatus st) => switch (st) {
      ResStatus.aktivni => tr.active,
      ResStatus.nadchazejici => tr.upcoming,
      ResStatus.dokoncene => tr.completed,
      ResStatus.cancelled => tr.cancelled,
    };

/// Payment status label — the same mapping as the payment details tab
/// (`ResPaymentDetailsTab._statusLabel`), never the raw DB value.
String resPayStatusLabel(AppTranslations tr, Reservation r) => switch (r.paymentStatus) {
      'paid' when r.status == 'cancelled' => tr.tr('payStatusRefundPending'),
      'paid' => tr.tr('paid'),
      'refunded' => tr.tr('payStatusRefunded'),
      'partial_refund' => tr.tr('payStatusPartialRefund'),
      'refund_pending' => tr.tr('payStatusRefundPending'),
      _ => tr.tr('payStatusUnpaid'),
    };

/// "3 dny" in the app language.
String resDays(AppTranslations tr, int n) => '$n ${tr.daysWord(n)}';

/// "pá 16. 10. – ne 18. 10." (short, language-aware).
String resRangeShort(AppTranslations tr, Reservation r) =>
    '${tripShortDate(tr, r.startDate)} – ${tripShortDate(tr, r.endDate)}';

/// The unpaid / verifying state of THIS booking, from the same provider the
/// shell strip uses (`pendingBookingFabProvider`).
enum ResPayFlag { none, unpaid, verifying }

ResPayFlag resPayFlag(Reservation r, PendingBooking? p) {
  if (p == null || p.id != r.id || p.isExpired) return ResPayFlag.none;
  return p.verifying ? ResPayFlag.verifying : ResPayFlag.unpaid;
}

/// Status pill over a photo (V22 `.stp` / `.ls-pl`): active = dark pill
/// with a live neon dot, upcoming = neon, completed / cancelled = white.
class ResStatusPill extends StatelessWidget {
  final ResStatus status;
  final String? suffix;
  final bool live;
  const ResStatusPill({super.key, required this.status, this.suffix, this.live = true});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final label = resStatusLabel(tr, status).toUpperCase() + (suffix == null ? '' : ' · $suffix');
    final (Color bg, Color fg, Color? border) = switch (status) {
      ResStatus.aktivni => (MgColors.night, MgColors.neon, MgColors.neonA(0.45)),
      ResStatus.nadchazejici => (MgColors.neon, MgColors.onNeon, null),
      ResStatus.dokoncene => (MgColors.white(0.92), MgColors.ink, null),
      ResStatus.cancelled => (MgColors.white(0.92), MgColors.ink, null),
    };
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: border == null ? null : Border.all(color: border),
        boxShadow: [BoxShadow(color: MgColors.black(0.35), blurRadius: 16, offset: const Offset(0, 6), spreadRadius: -8)],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (status == ResStatus.aktivni) ...[
          MgPing(size: 8, color: MgColors.neon, active: live),
          const SizedBox(width: 6),
        ],
        if (status == ResStatus.dokoncene) ...[
          MgIcon(MgIcons.check, size: 14, color: fg, stroke: 2.6),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: MgType.micro.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.6, color: fg)),
        ),
      ]),
    );
  }
}

/// Small pill on a photo: ★ rating, SOS, unpaid / verifying.
class ResPhotoChip extends StatelessWidget {
  final String label;
  final String icon;
  final Color iconColor;
  final Color border;
  final Color? textColor;
  final String? semanticLabel;
  const ResPhotoChip({
    super.key,
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.border,
    this.textColor,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel ?? label,
      excludeSemantics: true,
      child: Container(
        height: 26,
        padding: const EdgeInsets.fromLTRB(6, 0, 9, 0),
        decoration: BoxDecoration(
          color: MgColors.nightA(0.82),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          MgIcon(icon, size: 14, color: iconColor, stroke: 2.2),
          const SizedBox(width: 4),
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MgType.micro.copyWith(fontWeight: FontWeight.w800, color: textColor ?? MgColors.onDark)),
          ),
        ]),
      ),
    );
  }
}

/// Moto photo: contained bike over a dark ground; never throws on a missing
/// or broken URL (old guard: empty URL → placeholder, no build crash).
class ResBikePhoto extends StatelessWidget {
  final String? url;
  final bool grayscale;
  final int thumbWidth;
  const ResBikePhoto({super.key, required this.url, this.grayscale = false, this.thumbWidth = 800});

  @override
  Widget build(BuildContext context) {
    const placeholder = ColoredBox(
      color: MgColors.panel,
      child: Center(child: MgIcon(MgIcons.moto, size: 44, color: MgColors.onDarkMeta)),
    );
    Widget child = (url == null || url!.isEmpty)
        ? placeholder
        : MgImage(url!, thumbWidth: thumbWidth, fit: BoxFit.contain, placeholder: placeholder, error: placeholder);
    if (grayscale) {
      // ClipRect: the filter layer must not grey anything outside the photo.
      child = ClipRect(
        child: ColorFiltered(colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.saturation), child: child),
      );
    }
    return ColoredBox(color: MgColors.panel, child: child);
  }
}
