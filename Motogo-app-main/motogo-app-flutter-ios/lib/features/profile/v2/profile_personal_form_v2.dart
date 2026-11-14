import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_inputs.dart';
import '../../../core/widgets/date_dropdown_field.dart';
import 'profile_personal_v2.dart';

/// The inline personal-data form in the v2 look: the SAME controllers, the
/// same `DateDropdownField`s (year ranges computed by the screen) and the
/// same save / licence toggles — only grouped (Kontakt · Adresa · Doklady
/// pro smlouvu) with light v2 inputs.
///
/// Opened from the booking form ([fix], profile_booking_fix_v2.dart): the
/// fields the booking requires (address; licence number + expiry when
/// [fixLicence]) say "Potřebné k rezervaci" while empty, [expiryNote] /
/// [groupNote] say what is wrong with the saved licence right at it,
/// [addressKey] / [docsKey] mark the groups the screen scrolls to and
/// [afterSave] sits under Save ("Zpět k rezervaci").
class ProfilePersonalFormV2 extends StatelessWidget {
  final PfFormData data;
  final bool fix;
  final bool fixLicence;
  final String? expiryNote;
  final String? groupNote;
  final Key? addressKey;
  final Key? docsKey;
  final Widget? afterSave;
  const ProfilePersonalFormV2({
    super.key,
    required this.data,
    this.fix = false,
    this.fixLicence = false,
    this.expiryNote,
    this.groupNote,
    this.addressKey,
    this.docsKey,
    this.afterSave,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final d = data;
    final needText = tr.tr('v2PfFixNeeded');
    Widget field(TextEditingController c, String label,
        {TextInputType type = TextInputType.text, bool readOnly = false, Widget? suffix, bool need = false}) {
      Widget input([String? error]) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TextField(
              controller: c,
              keyboardType: type,
              readOnly: readOnly,
              enableInteractiveSelection: true,
              style: MgType.body.copyWith(color: readOnly ? MgColors.meta : MgColors.ink),
              decoration: mgInputDecoration(context, label: label, suffixIcon: suffix, filledWell: readOnly, error: error),
            ),
          );
      if (!fix || !need) return input();
      // Live: the hint goes away as soon as the customer types.
      return ValueListenableBuilder<TextEditingValue>(
        valueListenable: c,
        builder: (context, v, _) => input(v.text.trim().isEmpty ? needText : null),
      );
    }

    return Theme(
      data: _inputTheme(Theme.of(context)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _Group(tr.tr('v2PfGroupContact')),
        field(d.name, tr.tr('fullNameLabel')),
        field(d.email, tr.email,
            readOnly: true,
            suffix: const Padding(
              padding: EdgeInsets.all(14),
              child: MgIcon(MgIcons.lock, size: 18, color: MgColors.meta),
            )),
        Padding(
          padding: const EdgeInsets.only(bottom: 10, left: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const MgIcon(MgIcons.info, size: 16, color: MgColors.meta),
            const SizedBox(width: 6),
            Expanded(child: Text(tr.tr('v2PfEmailNote'), style: MgType.meta.copyWith(color: MgColors.meta))),
          ]),
        ),
        field(d.phone, tr.tr('phone'), type: TextInputType.phone),
        DateDropdownField(
          label: tr.tr('dob'),
          value: d.dob,
          firstYear: d.dobFirstYear,
          lastYear: d.dobLastYear,
          yearsDescending: true,
          onChanged: d.onDob,
        ),
        _Group(tr.tr('v2PfGroupAddress'), key: addressKey),
        field(d.street, tr.tr('streetShort'), need: true),
        field(d.zip, tr.tr('zip'), need: true),
        field(d.city, tr.tr('city'), need: true),
        field(d.country, tr.tr('countryLabel')),
        _Group(tr.tr('v2PfGroupDocs'), key: docsKey),
        field(d.idNum, tr.tr('idNumberFull')),
        field(d.licNum, tr.tr('licenseNumberFull'), need: fixLicence),
        DateDropdownField(
          label: tr.tr('licenseExpiry'),
          value: d.licExp,
          firstYear: d.licFirstYear,
          lastYear: d.licLastYear,
          onChanged: d.onLicExp,
        ),
        if (fix && fixLicence && d.licExp == null)
          _Note(needText)
        else if (expiryNote != null)
          _Note(expiryNote!),
        const SizedBox(height: 4),
        Text(tr.tr('licenseCategory'), style: MgType.meta.copyWith(color: MgColors.meta)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in d.licOptions)
            PfLicenceChip(label: c, on: d.licCategories.contains(c), onTap: () => d.onToggleCategory(c)),
        ]),
        if (groupNote != null) ...[const SizedBox(height: 8), _Note(groupNote!)],
        const SizedBox(height: 16),
        MgBtnInk(label: tr.tr('saveChanges'), icon: MgIcons.check, neonLabel: true, onTap: d.onSave),
        if (afterSave != null) afterSave!,
      ]),
    );
  }

  /// Light v2 borders for the dropdowns of `DateDropdownField` (its own
  /// decoration sets only `border`, so enabled / focused come from here).
  static ThemeData _inputTheme(ThemeData base) {
    OutlineInputBorder b(Color c, double w) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c, width: w),
        );
    return base.copyWith(
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: MgColors.surface,
        enabledBorder: b(MgColors.lineInput, 1.5),
        focusedBorder: b(MgColors.focusLight, 2),
      ),
    );
  }
}

/// Booking-fix note right at a date / the licence chips (like a field error).
class _Note extends StatelessWidget {
  final String text;
  const _Note(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
        child: Text(text, style: MgType.small.copyWith(color: MgColors.err, fontWeight: FontWeight.w700)),
      );
}

class _Group extends StatelessWidget {
  final String text;
  const _Group(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 10),
        child: Semantics(
          header: true,
          child: Text(text.toUpperCase(), style: MgType.eyebrow.copyWith(color: MgColors.link)),
        ),
      );
}
