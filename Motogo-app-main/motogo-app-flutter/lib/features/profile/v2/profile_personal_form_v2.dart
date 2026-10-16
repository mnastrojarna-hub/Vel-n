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
class ProfilePersonalFormV2 extends StatelessWidget {
  final PfFormData data;
  const ProfilePersonalFormV2({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final d = data;
    Widget field(TextEditingController c, String label,
            {TextInputType type = TextInputType.text, bool readOnly = false, Widget? suffix}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(
            controller: c,
            keyboardType: type,
            readOnly: readOnly,
            enableInteractiveSelection: true,
            style: MgType.body.copyWith(color: readOnly ? MgColors.meta : MgColors.ink),
            decoration: mgInputDecoration(context, label: label, suffixIcon: suffix, filledWell: readOnly),
          ),
        );
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
        _Group(tr.tr('v2PfGroupAddress')),
        field(d.street, tr.tr('streetShort')),
        field(d.zip, tr.tr('zip')),
        field(d.city, tr.tr('city')),
        field(d.country, tr.tr('countryLabel')),
        _Group(tr.tr('v2PfGroupDocs')),
        field(d.idNum, tr.tr('idNumberFull')),
        field(d.licNum, tr.tr('licenseNumberFull')),
        DateDropdownField(
          label: tr.tr('licenseExpiry'),
          value: d.licExp,
          firstYear: d.licFirstYear,
          lastYear: d.licLastYear,
          onChanged: d.onLicExp,
        ),
        const SizedBox(height: 4),
        Text(tr.tr('licenseCategory'), style: MgType.meta.copyWith(color: MgColors.meta)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in d.licOptions)
            PfLicenceChip(label: c, on: d.licCategories.contains(c), onTap: () => d.onToggleCategory(c)),
        ]),
        const SizedBox(height: 16),
        MgBtnInk(label: tr.tr('saveChanges'), icon: MgIcons.check, neonLabel: true, onTap: d.onSave),
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

class _Group extends StatelessWidget {
  final String text;
  const _Group(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 10),
        child: Semantics(
          header: true,
          child: Text(text.toUpperCase(), style: MgType.eyebrow.copyWith(color: MgColors.link)),
        ),
      );
}
