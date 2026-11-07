import 'package:flutter/material.dart';

import '../../../core/date_days.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/states/mg_state_banner.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_format.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../reservation_models.dart';
import '../reservation_provider.dart';
import 'res_detail_bits_v2.dart';

/// Shared bits of the v2 "Historie rezervace" (`ResHistoryV2`): the SAME
/// rows, conditions and texts as `ResModificationHistory`, drawn with v2
/// surfaces — well tiles, line icons in tone discs instead of emoji, D4
/// dates ("pá 23. 10.", the year only when it is not this year).

/// "pá 30. 10." of an ISO date ("–" when it cannot be read — as today).
String resHistDay(String iso, String lang) {
  final d = DateTime.tryParse(iso);
  return d == null ? '–' : mgDayShort(d, lang);
}

/// "út 27. 10. 14:36" — DB times are UTC → device time (as today).
String resHistAt(DateTime utcOrLocal, String lang) {
  final dt = utcOrLocal.toLocal();
  return '${mgDayShort(dt, lang)} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
}

/// Section head inside a history card: line icon in a tinted disc +
/// caps label (wraps, never overflows).
class ResHistHeadV2 extends StatelessWidget {
  final String icon;
  final String text;
  final Color color;
  const ResHistHeadV2({super.key, required this.icon, required this.text, this.color = MgColors.meta});

  @override
  Widget build(BuildContext context) => Row(children: [
        ResHistDiscV2(icon: icon, color: color, size: 28),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: MgType.eyebrow.copyWith(color: MgColors.meta))),
      ]);
}

/// Tinted disc with a line icon (meaning colour 12 %, icon in the colour).
class ResHistDiscV2 extends StatelessWidget {
  final String icon;
  final Color color;
  final double size;
  const ResHistDiscV2({super.key, required this.icon, required this.color, this.size = 24});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
        alignment: Alignment.center,
        child: MgIcon(icon, size: size * 0.58, color: color),
      );
}

/// "Historie úprav (n×)": one well tile per entry — number disc, time ·
/// source, the kind chip and the old → new rows (same rules as today).
class ResHistoryListV2 extends StatelessWidget {
  final List<ModificationEntry> entries;
  const ResHistoryListV2({super.key, required this.entries});

  @override
  Widget build(BuildContext context) => ResDetailCardV2(children: [
        ResHistHeadV2(icon: MgIcons.edit, text: '${t(context).tr('modificationHistory')} (${entries.length}×)'),
        const SizedBox(height: 10),
        for (var i = 0; i < entries.length; i++) _EntryV2(idx: i, mod: entries[i]),
      ]);
}

class _Change {
  final String label, from, to;
  final String? badge;
  final Color badgeColor;
  const _Change(this.label, this.from, this.to, [this.badge, this.badgeColor = MgColors.meta]);
}

class _EntryV2 extends StatelessWidget {
  final int idx;
  final ModificationEntry mod;
  const _EntryV2({required this.idx, required this.mod});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final lang = tr.lang;
    final hm = ModDescription.describe(mod.fromStart, mod.fromEnd, mod.toStart, mod.toEnd);
    final source = mod.source == 'admin' || mod.source == 'velin'
        ? 'admin'
        : mod.source == 'system'
            ? tr.tr('systemLabel')
            : tr.tr('customerLabel');
    String hmT(String? v) => (v == null || v.isEmpty) ? '—' : (v.length >= 5 ? v.substring(0, 5) : v);
    String method(String? m) => m == 'delivery' ? tr.tr('deliveryLabel') : tr.tr('branchPickupLabel');
    // Kind chip — same choice as today; meaning colours of v2 (history
    // accent = petrol, never a rank colour).
    var typeLabel = hm.typeText(tr.tr);
    var accent = switch (hm.kind) {
      ModKind.extended => MgColors.link,
      ModKind.shortened => MgColors.err,
      ModKind.shifted => MgColors.warn,
      ModKind.unchanged => MgColors.meta,
    };
    if (!mod.hasDateChange) {
      if (mod.hasMotoChange) {
        typeLabel = tr.tr('histMotoChange');
        accent = MgColors.petrol;
      } else if (mod.hasPickupTimeChange || mod.hasReturnTimeChange) {
        typeLabel = tr.tr('histTimeChange');
        accent = MgColors.warn;
      } else if (mod.hasGearChange || mod.extrasChanged) {
        typeLabel = tr.tr('histGearChange');
        accent = MgColors.petrol;
      } else if (mod.hasPickupMethodChange ||
          mod.hasReturnMethodChange ||
          mod.hasPickupAddressChange ||
          mod.hasReturnAddressChange) {
        typeLabel = tr.tr('histPlaceChange');
        accent = MgColors.petrol;
      }
    }
    final changes = <_Change>[];
    if (mod.hasDateChange) {
      void shift(String label, String from, String to) {
        final f = DateTime.tryParse(from), x = DateTime.tryParse(to);
        if (f == null || x == null) return;
        final diff = calendarDaysInclusive(f, x) - 1;
        if (diff == 0) return;
        changes.add(_Change(label, resHistDay(from, lang), resHistDay(to, lang),
            '${diff > 0 ? '+' : ''}$diff ${tr.tr('dayAbbr')}', diff > 0 ? MgColors.link : MgColors.err));
      }

      shift(tr.tr('startLabel'), mod.fromStart, mod.toStart);
      shift(tr.tr('endLabel'), mod.fromEnd, mod.toEnd);
    }
    if (mod.hasMotoChange) changes.add(_Change(tr.tr('motorcycle'), mod.fromMoto!, mod.toMoto!));
    if (mod.hasPickupMethodChange) {
      changes.add(_Change(tr.tr('pickupLabel'), method(mod.fromPickupMethod), method(mod.toPickupMethod)));
    }
    if (mod.hasReturnMethodChange) {
      changes.add(_Change(tr.tr('returnPlaceLabel'), method(mod.fromReturnMethod), method(mod.toReturnMethod)));
    }
    if (mod.hasPickupAddressChange) {
      changes.add(_Change(tr.tr('pickupPlace'), mod.fromPickupAddress!, mod.toPickupAddress!));
    }
    if (mod.hasReturnAddressChange) {
      changes.add(_Change(tr.tr('returnPlace'), mod.fromReturnAddress!, mod.toReturnAddress!));
    }
    if (mod.hasPickupTimeChange) {
      changes.add(_Change(tr.tr('pickupTimeEdit'), hmT(mod.fromPickupTime), hmT(mod.toPickupTime)));
    }
    if (mod.hasReturnTimeChange) {
      changes.add(_Change(tr.tr('returnTimeEdit'), hmT(mod.fromReturnTime), hmT(mod.toReturnTime)));
    }
    if (mod.hasGearChange) {
      mod.gearChanges.forEach((key, v) {
        // „Mám vlastní výbavu“ — Ano/Ne místo velikosti (jako dnes).
        if (key == 'own_gear') {
          String yn(String? b) => b == 'true' ? tr.tr('yes') : b == 'false' ? tr.tr('no') : '—';
          changes.add(_Change(tr.tr('ownGear'), yn(v['from']), yn(v['to'])));
          return;
        }
        final isPassenger = key.startsWith('passenger_');
        final base = isPassenger ? key.substring('passenger_'.length) : key;
        changes.add(_Change(
          tr.tr(base) + (isPassenger ? ' (${tr.tr('histPassenger')})' : ''),
          (v['from'] == null || v['from']!.isEmpty) ? '—' : v['from']!,
          (v['to'] == null || v['to']!.isEmpty) ? tr.tr('histRemoved') : v['to']!,
        ));
      });
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MgColors.well,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MgColors.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text('${idx + 1}',
                style: MgType.tab(MgType.micro.copyWith(fontWeight: FontWeight.w800, height: 1, color: MgColors.onDark))),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${resHistAt(mod.at, lang)} · $source', style: MgType.tab(MgType.micro.copyWith(color: MgColors.meta))),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
              child: Text(typeLabel, style: MgType.micro.copyWith(fontWeight: FontWeight.w800, color: accent)),
            ),
          ),
        ]),
        if (changes.isNotEmpty) const SizedBox(height: 8),
        for (final c in changes) _ChangeRowV2(c),
        // Řádky doplňků drží booking_extras — tady jen signál (jako dnes).
        if (mod.extrasChanged)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(tr.tr('histExtrasChanged'), style: MgType.micro.copyWith(fontWeight: FontWeight.w800, color: MgColors.petrol)),
          ),
      ]),
    );
  }
}

/// "Začátek  pá 30. 10. → ne 1. 11.  +2 d": label column (meta), the old
/// value struck through, the new one ink, the day shift in its meaning.
class _ChangeRowV2 extends StatelessWidget {
  final _Change c;
  const _ChangeRowV2(this.c);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 84, child: Text(c.label, style: MgType.micro.copyWith(color: MgColors.meta))),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(TextSpan(children: [
              TextSpan(
                text: c.from,
                style: MgType.small.copyWith(color: MgColors.meta, decoration: TextDecoration.lineThrough),
              ),
              const WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: MgIcon(MgIcons.arrowRight, size: 12, color: MgColors.meta),
                ),
              ),
              TextSpan(text: c.to, style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink)),
              if (c.badge != null)
                TextSpan(
                  text: '  ${c.badge}',
                  style: MgType.tab(MgType.micro.copyWith(fontWeight: FontWeight.w800, color: c.badgeColor)),
                ),
            ])),
          ),
        ]),
      );
}

/// "SOS události": replacement / ended-by-SOS banners and the incident
/// tiles (id, type, status, reported → resolved, title) — as today.
class ResHistorySosV2 extends StatelessWidget {
  final Reservation res;
  final List<SosIncident> incidents;
  const ResHistorySosV2({super.key, required this.res, required this.incidents});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final lang = tr.lang;
    final id = res.sosIncidentId;
    return ResDetailCardV2(children: [
      ResHistHeadV2(icon: MgIcons.sos, text: tr.tr('sosEvents'), color: MgColors.err),
      const SizedBox(height: 10),
      if (res.sosReplacement)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: MgStateBanner(tone: MgTone.ok, icon: MgIcons.swap, title: tr.tr('replacementForSos')),
        ),
      if (res.endedBySos)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: MgStateBanner(
            tone: MgTone.err,
            icon: MgIcons.alert,
            title: '${tr.tr('endedBySos')}${id != null ? ' (${id.substring(id.length - 8).toUpperCase()})' : ''}',
          ),
        ),
      for (final inc in incidents)
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: MgColors.well,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: MgColors.line),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(inc.shortId, style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.err))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: MgColors.errBg, borderRadius: BorderRadius.circular(999)),
                    child: Text(tr.tr(inc.typeKey), style: MgType.micro.copyWith(fontWeight: FontWeight.w800, color: MgColors.err)),
                  ),
                ]),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(tr.tr(inc.statusKey),
                    textAlign: TextAlign.end,
                    style: MgType.micro.copyWith(
                        fontWeight: FontWeight.w800,
                        color: inc.status == 'resolved' || inc.status == 'closed' ? MgColors.link : MgColors.err)),
              ),
            ]),
            const SizedBox(height: 4),
            Text.rich(
              TextSpan(children: [
                TextSpan(text: resHistAt(inc.createdAt, lang)),
                if (inc.resolvedAt != null) ...[
                  const WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: MgIcon(MgIcons.arrowRight, size: 12, color: MgColors.meta),
                    ),
                  ),
                  TextSpan(text: '${tr.tr('resolvedAt')} ${resHistAt(inc.resolvedAt!, lang)}'),
                ],
              ]),
              style: MgType.tab(MgType.micro.copyWith(color: MgColors.meta)),
            ),
            if (inc.title != null && inc.title!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(inc.title!, style: MgType.small.copyWith(color: MgColors.ink)),
              ),
          ]),
        ),
    ]);
  }
}
