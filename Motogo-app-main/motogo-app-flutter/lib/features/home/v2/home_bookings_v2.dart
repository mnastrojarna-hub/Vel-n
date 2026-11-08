import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/router.dart';
import '../../../core/v2/chrome/mg_fab_avoid.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_icon_tile.dart';
import '../../../core/v2/widgets/mg_photo.dart';
import '../../../core/v2/widgets/mg_section.dart';
import '../../../core/v2/widgets/mg_surfaces.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../reservations/reservation_models.dart';

/// Domů v2 = the old `HomeReservationsSection` in the v2 look (owner
/// 2026-11-07 "jen upgrade vzhledu"): "Aktivní rezervace" + "VŠE" (→
/// Rezervace), up to 2 paid active / upcoming bookings (each → its detail)
/// or the "Žádná aktivní rezervace" row (→ Rezervovat), then the SOS card
/// while a booking allows SOS (→ SOS). [error] replaces the empty row when
/// the bookings could not be loaded (R2: what happened + retry).
class HomeBookingsV2 extends StatelessWidget {
  final List<Reservation> active;
  final Widget? error;
  const HomeBookingsV2({super.key, required this.active, this.error});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final router = GoRouter.maybeOf(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
        child: MgSectionHeader(
          title: tr.tr('homeActiveReservations'),
          trailingLabel: tr.tr('homeViewAll'),
          onTrailing: () => router?.go(Routes.reservations),
          padding: EdgeInsets.zero,
        ),
      ),
      const SizedBox(height: 10),
      if (active.isNotEmpty)
        for (final r in active.take(2))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: HomeBookingCardV2(reservation: r),
          )
      else if (error != null)
        error!
      else
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _Row(
            key: const ValueKey('home-no-booking'),
            leading: const MgIconTileLight(MgIcons.moto),
            title: tr.tr('homeNoActiveReservation'),
            sub: tr.tr('homeBookMotorcycle'),
            onTap: () => router?.go(Routes.search),
          ),
        ),
      if (active.any((r) => r.sosAllowed))
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: HomeSosCardV2(onTap: () => router?.push(Routes.sos)),
        ),
    ]);
  }
}

/// One booking (old `HomeReservationCard`): photo, bike, "číslo · termín",
/// status — tap → the booking detail.
class HomeBookingCardV2 extends StatelessWidget {
  final Reservation reservation;
  const HomeBookingCardV2({super.key, required this.reservation});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final r = reservation;
    final img = r.motoImage;
    return _Row(
      key: ValueKey('home-booking-${r.id}'),
      leading: SizedBox(
        width: 50,
        height: 50,
        child: img == null
            ? Container(
                decoration: BoxDecoration(color: MgColors.well, borderRadius: BorderRadius.circular(10)),
                child: const Center(child: MgIcon(MgIcons.moto, size: 24, color: MgColors.meta)),
              )
            : MgPhoto(url: img, thumbWidth: 200, width: 50, height: 50, glyph: MgIcons.moto, borderRadius: BorderRadius.circular(10)),
      ),
      title: r.motoName,
      sub: '${r.shortId} · ${r.dateRange}',
      badge: _StatusPill(status: r.displayStatus, label: _label(tr, r.displayStatus)),
      onTap: () => GoRouter.maybeOf(context)?.push('/reservations/${r.id}'),
    );
  }

  static String _label(AppTranslations tr, ResStatus s) => switch (s) {
        ResStatus.aktivni => tr.tr('homeStatusActive'),
        ResStatus.nadchazejici => tr.tr('homeStatusUpcoming'),
        ResStatus.dokoncene => tr.tr('homeStatusCompleted'),
        ResStatus.cancelled => tr.tr('homeStatusCancelled'),
      };
}

/// Old SOS card on Domů: "NEHODA, KRÁDEŽ, PORUCHA · Okamžitá pomoc 24/7".
class HomeSosCardV2 extends StatelessWidget {
  final VoidCallback onTap;
  const HomeSosCardV2({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final title = tr.tr('homeSosTitle');
    final sub = tr.tr('homeSosSubtitle');
    return MgFabAvoid(
      kind: MgAvoidKind.tap,
      child: Semantics(
        button: true,
        label: '$title, $sub',
        excludeSemantics: true,
        child: MgPress(
          key: const ValueKey('home-sos-card'),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(color: MgColors.sos, borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: MgColors.white(0.2), borderRadius: BorderRadius.circular(10)),
                child: const Center(child: MgIcon(MgIcons.sos, size: 20, color: MgColors.onDark)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  MgWordFit(
                    minScale: 0.75,
                    child: Text(title, style: MgType.body.copyWith(fontWeight: FontWeight.w900, color: MgColors.onDark)),
                  ),
                  Text(sub, style: MgType.small.copyWith(fontWeight: FontWeight.w600, color: MgColors.white(0.8))),
                ]),
              ),
              const SizedBox(width: 8),
              const MgIcon(MgIcons.chevronRight, size: 20, color: MgColors.onDark),
            ]),
          ),
        ),
      ),
    );
  }
}

/// White tappable card row: leading, title + sub, chevron. [badge] (the
/// status pill) sits on the right, or under the texts when the row is
/// narrow (320 dp phone, long German status) — the bike name never splits.
class _Row extends StatelessWidget {
  final Widget leading;
  final String title;
  final String sub;
  final Widget? badge;
  final VoidCallback onTap;
  const _Row({super.key, required this.leading, required this.title, required this.sub, this.badge, required this.onTap});

  @override
  Widget build(BuildContext context) => MgFabAvoid(
        kind: MgAvoidKind.tap,
        child: Semantics(
          button: true,
          label: '$title, $sub',
          excludeSemantics: true,
          child: MgPress(
            scale: 0.99,
            onTap: onTap,
            child: MgCard(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: LayoutBuilder(builder: (context, c) {
                final below = badge != null && c.maxWidth < 290;
                return Row(children: [
                  leading,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      MgWordFit(
                        minScale: 0.8,
                        child: Text(title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink)),
                      ),
                      const SizedBox(height: 2),
                      Text(sub, style: MgType.tab(MgType.meta.copyWith(color: MgColors.meta))),
                      if (below) ...[const SizedBox(height: 6), badge!],
                    ]),
                  ),
                  const SizedBox(width: 8),
                  if (badge != null && !below) badge! else const MgIcon(MgIcons.chevronRight, size: 20, color: MgColors.lead),
                ]);
              }),
            ),
          ),
        ),
      );
}

/// Status pill of the booking card (active = night + neon, upcoming = neon).
class _StatusPill extends StatelessWidget {
  final ResStatus status;
  final String label;
  const _StatusPill({required this.status, required this.label});

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg) = switch (status) {
      ResStatus.aktivni => (MgColors.night, MgColors.neon),
      ResStatus.nadchazejici => (MgColors.neon, MgColors.onNeon),
      _ => (MgColors.well, MgColors.ink),
    };
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 120),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: MgWordFit(
          minScale: 0.75,
          child: Text(label, maxLines: 1, style: MgType.micro.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.4, color: fg)),
        ),
      ),
    );
  }
}
