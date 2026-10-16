import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_skeleton.dart';
import '../../../core/v2/widgets/mg_surfaces.dart';
import 'profile_personal_form_v2.dart';
import 'profile_v2_parts.dart';

/// Everything the inline personal-data form needs — the SAME controllers,
/// values and closures as today's `_buildPersonalForm` (profile_screen.dart).
class PfFormData {
  final TextEditingController name, email, phone, city, zip, street, country, idNum, licNum;
  final DateTime? dob;
  final DateTime? licExp;
  final int dobFirstYear, dobLastYear, licFirstYear, licLastYear;
  final Set<String> licCategories;
  final List<String> licOptions;
  final ValueChanged<DateTime?> onDob;
  final ValueChanged<DateTime?> onLicExp;
  final ValueChanged<String> onToggleCategory;
  final VoidCallback onSave;

  const PfFormData({
    required this.name,
    required this.email,
    required this.phone,
    required this.city,
    required this.zip,
    required this.street,
    required this.country,
    required this.idNum,
    required this.licNum,
    required this.dob,
    required this.licExp,
    required this.dobFirstYear,
    required this.dobLastYear,
    required this.licFirstYear,
    required this.licLastYear,
    required this.licCategories,
    required this.licOptions,
    required this.onDob,
    required this.onLicExp,
    required this.onToggleCategory,
    required this.onSave,
  });
}

/// "Osobní údaje" white card (V21 §1.2): summary of the saved profile with
/// amber "Doplnit" for empty values, "Upravit" = today's toggle (incl. its
/// "still loading / load failed" guard) that expands the SAME inline form.
class ProfilePersonalV2 extends StatelessWidget {
  final Map<String, dynamic>? profile;
  final bool ready;
  final bool expanded;
  final VoidCallback onToggle;
  final PfFormData form;
  const ProfilePersonalV2({
    super.key,
    required this.profile,
    required this.ready,
    required this.expanded,
    required this.onToggle,
    required this.form,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final open = expanded && ready;
    return MgCard(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(tr.tr('personalInfo'), style: MgType.section.copyWith(color: MgColors.ink)),
            ),
          ),
          const SizedBox(width: 8),
          _EditButton(
            label: open ? tr.tr('close') : tr.tr('edit'),
            icon: open ? MgIcons.close : MgIcons.edit,
            onTap: onToggle,
          ),
        ]),
        const SizedBox(height: 12),
        AnimatedSize(
          duration: MgMotion.of(context, MgMotion.sheet),
          alignment: Alignment.topCenter,
          child: open
              ? MgEnter(child: ProfilePersonalFormV2(data: form))
              : (profile == null ? const _SummarySkeleton() : _Summary(profile: profile!, form: form)),
        ),
      ]),
    );
  }
}

class _EditButton extends StatelessWidget {
  final String label;
  final String icon;
  final VoidCallback onTap;
  const _EditButton({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        child: MgPress(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: MgColors.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: MgColors.link, width: 1.5),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              MgIcon(icon, size: 18, color: MgColors.link),
              const SizedBox(width: 6),
              Text(label, style: MgType.ctaCompact.copyWith(letterSpacing: 0, color: MgColors.link)),
            ]),
          ),
        ),
      );
}

class _Summary extends StatelessWidget {
  final Map<String, dynamic> profile;
  final PfFormData form;
  const _Summary({required this.profile, required this.form});

  String? _s(String k) {
    final v = profile[k];
    if (v == null) return null;
    final s = '$v'.trim();
    return s.isEmpty ? null : s;
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final addr = [
      _s('street'),
      [_s('zip'), _s('city')].whereType<String>().join(' '),
      _s('country'),
    ].whereType<String>().where((e) => e.trim().isNotEmpty).join(', ');
    Widget f(String label, String? value, {bool wide = false, bool lock = false}) =>
        _Field(label: label, value: value, fill: tr.tr('v2PfFill'), lock: lock, wide: wide);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      f(tr.tr('fullNameLabel'), _s('full_name'), wide: true),
      f(tr.email, _s('email'), wide: true, lock: true),
      _Pair(f(tr.tr('phone'), _s('phone')), f(tr.tr('dob'), pfDate(profile['date_of_birth']))),
      f(tr.tr('v2PfAddress'), addr.isEmpty ? null : addr, wide: true),
      _Pair(f(tr.tr('idNumberFull'), _s('id_number')), f(tr.tr('licenseNumberFull'), _s('license_number'))),
      f(tr.tr('licenseExpiry'), pfDate(profile['license_expiry']), wide: true),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(tr.tr('licenseCategory'), style: MgType.meta.copyWith(color: MgColors.meta)),
      ),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final c in form.licOptions) PfLicenceChip(label: c, on: form.licCategories.contains(c)),
      ]),
    ]);
  }
}

class _Pair extends StatelessWidget {
  final Widget a, b;
  const _Pair(this.a, this.b);

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: a),
        const SizedBox(width: 16),
        Expanded(child: b),
      ]);
}

class _Field extends StatelessWidget {
  final String label;
  final String? value;
  final String fill;
  final bool lock;
  final bool wide;
  const _Field({required this.label, required this.value, required this.fill, this.lock = false, this.wide = false});

  @override
  Widget build(BuildContext context) {
    final missing = value == null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: MergeSemantics(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: MgType.meta.copyWith(color: MgColors.meta)),
          const SizedBox(height: 2),
          Row(children: [
            Flexible(
              child: Text(missing ? fill : value!,
                  style: missing
                      ? MgType.body.copyWith(
                          fontWeight: FontWeight.w800,
                          color: MgColors.warn,
                          decoration: TextDecoration.underline,
                          decorationStyle: TextDecorationStyle.dashed,
                          decorationColor: MgColors.warnBorder)
                      : MgType.body.copyWith(color: MgColors.ink)),
            ),
            if (lock) ...[const SizedBox(width: 6), const MgIcon(MgIcons.lock, size: 16, color: MgColors.meta)],
          ]),
        ]),
      ),
    );
  }
}

/// Licence category chip (summary = static; form = 44 px toggle).
class PfLicenceChip extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback? onTap;
  const PfLicenceChip({super.key, required this.label, required this.on, this.onTap});

  @override
  Widget build(BuildContext context) {
    final big = onTap != null;
    final chip = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      constraints: BoxConstraints(minWidth: big ? 52 : 44, minHeight: big ? 44 : 32),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: on ? MgColors.panel : (big ? MgColors.surface : MgColors.well),
        borderRadius: BorderRadius.circular(big ? 14 : 12),
        border: Border.all(
            color: on ? MgColors.panel : (big ? MgColors.lineInput : MgColors.line), width: big && !on ? 1.5 : 1),
        boxShadow: on ? [BoxShadow(color: MgColors.neonA(0.25), spreadRadius: 2)] : null,
      ),
      child: Center(
        widthFactor: 1,
        child: Text(label,
            style: MgType.small.copyWith(
                fontWeight: on ? FontWeight.w900 : FontWeight.w800,
                color: on ? MgColors.neon : (big ? MgColors.ink : MgColors.meta))),
      ),
    );
    if (!big) return Semantics(label: label, selected: on, child: ExcludeSemantics(child: chip));
    return Semantics(
      button: true,
      selected: on,
      label: label,
      excludeSemantics: true,
      child: MgPress(onTap: onTap, child: on ? MgPop(trigger: on, child: chip) : chip),
    );
  }
}

class _SummarySkeleton extends StatelessWidget {
  const _SummarySkeleton();

  @override
  Widget build(BuildContext context) => const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        MgSkeleton(width: 120, height: 12),
        SizedBox(height: 8),
        MgSkeleton(width: 200, height: 16),
        SizedBox(height: 16),
        MgSkeleton(width: 90, height: 12),
        SizedBox(height: 8),
        MgSkeleton(width: 220, height: 16),
        SizedBox(height: 16),
        MgSkeleton(width: 160, height: 16),
      ]);
}
