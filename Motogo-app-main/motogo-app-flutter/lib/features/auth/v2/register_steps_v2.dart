import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/widgets/date_dropdown_field.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_choice_card.dart';
import '../../../core/v2/widgets/mg_inputs.dart';
import 'auth_parts_v2.dart';
import 'register_view_v2.dart';

/// The three v2 registration steps — the SAME fields, controllers and
/// validators as the old form; labels sit above the inputs.

Widget _gap() => const SizedBox(height: 14);

/// A field wrapped in its scroll-into-view key + the inline error.
Widget _f(RegisterV2Model m, String field, String label,
    {TextInputType? kb, Iterable<String>? hints, bool password = false, TextCapitalization cap = TextCapitalization.none}) {
  return KeyedSubtree(
    key: m.keyFor(field),
    child: AsmField(
      label: label,
      controller: m.ctrl[field]!,
      error: m.errors[field],
      keyboardType: kb,
      autofillHints: hints,
      obscure: password ? true : null,
      capitalization: cap,
      action: TextInputAction.next,
      onChanged: (_) => m.onEdited(field),
    ),
  );
}

/// Two fields side by side, stacked when a column would get too narrow.
Widget _pair(Widget a, Widget b, {int flexA = 1, int flexB = 1}) => LayoutBuilder(
      builder: (context, c) => c.maxWidth < 270
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [a, _gap(), b])
          : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: flexA, child: a),
              const SizedBox(width: 10),
              Expanded(flex: flexB, child: b),
            ]),
    );

/// Date field + its inline error; clears the error when a value is picked.
Widget _date(RegisterV2Model m, String field, String label, int first, int last, {bool desc = false}) {
  return KeyedSubtree(
    key: m.keyFor(field),
    child: _CtrlWatch(
      controller: m.ctrl[field]!,
      onChange: () => m.onEdited(field),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DateDropdownField(
          controller: m.ctrl[field]!,
          label: label,
          firstYear: first,
          lastYear: last,
          yearsDescending: desc,
        ),
        if (m.errors[field] != null) _ErrText(m.errors[field]!),
      ]),
    ),
  );
}

class RegisterStep1V2 extends StatelessWidget {
  final RegisterV2Model m;
  const RegisterStep1V2({super.key, required this.m});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final y = DateTime.now().year;
    return AutofillGroup(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _pair(
          _f(m, 'fname', tr.tr('firstName'), hints: const [AutofillHints.givenName], cap: TextCapitalization.words),
          _f(m, 'lname', tr.tr('lastName'), hints: const [AutofillHints.familyName], cap: TextCapitalization.words),
        ),
        _gap(),
        _f(m, 'email', tr.tr('email'), kb: TextInputType.emailAddress, hints: const [AutofillHints.email]),
        _gap(),
        _f(m, 'phone', tr.tr('phone'), kb: TextInputType.phone, hints: const [AutofillHints.telephoneNumber]),
        _gap(),
        _date(m, 'dob', tr.tr('dob'), y - 100, y - 15, desc: true),
        const SizedBox(height: 6),
        _f(m, 'pass', tr.tr('passwordMin8'), password: true, hints: const [AutofillHints.newPassword]),
        _gap(),
        _f(m, 'pass2', tr.tr('passwordConfirm'), password: true, hints: const [AutofillHints.newPassword]),
      ]),
    );
  }
}

class RegisterStep2V2 extends StatelessWidget {
  final RegisterV2Model m;
  const RegisterStep2V2({super.key, required this.m});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _pair(
        _f(m, 'city', tr.tr('city'), hints: const [AutofillHints.addressCity], cap: TextCapitalization.words),
        _f(m, 'zip', tr.tr('zip'), kb: TextInputType.number, hints: const [AutofillHints.postalCode]),
        flexA: 2,
      ),
      _gap(),
      _f(m, 'street', tr.tr('street'), hints: const [AutofillHints.streetAddressLine1]),
      _gap(),
      _f(m, 'country', tr.tr('countryLabel'), hints: const [AutofillHints.countryName], cap: TextCapitalization.words),
    ]);
  }
}

class RegisterStep3V2 extends StatelessWidget {
  final RegisterV2Model m;
  const RegisterStep3V2({super.key, required this.m});

  (String, String?) _split(String s) {
    final i = s.indexOf(' – ');
    return i < 0 ? (s, null) : (s.substring(0, i), s.substring(i + 3));
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final y = DateTime.now().year;
    final a2 = _split(tr.tr('licA2Desc'));
    final a = _split(tr.tr('licADesc'));
    final consentErr = m.errors['consent'];
    Widget card(String value, (String, String?) txt) => MgChoiceCard(
          title: txt.$1,
          sub: txt.$2,
          selected: m.licGroup == value,
          onTap: () => m.onLic(value),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _f(m, 'idNum', tr.tr('idNumberFull')),
      _gap(),
      _f(m, 'licNum', tr.tr('licenseNumber')),
      _gap(),
      _date(m, 'licExp', tr.tr('licenseExpiry'), y, y + 20),
      const SizedBox(height: 6),
      AsmLabel(tr.tr('licenseCategory')),
      Semantics(
        container: true,
        label: tr.tr('licenseCategory'),
        child: _pair(card('A2', a2), card('A', a)),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Divider(height: 1, thickness: 1, color: MgColors.line),
      ),
      KeyedSubtree(
        key: m.keyFor('consent'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr.tr('regConsentTitle'), style: MgType.title.copyWith(fontSize: 13.5, color: MgColors.ink)),
          const SizedBox(height: 4),
          MgCheckRow(
            value: m.consentVop,
            onChanged: m.onVop,
            label: tr.tr('consentTermsVop'),
            error: consentErr != null && !m.consentVop,
          ),
          MgCheckRow(
            value: m.consentGdpr,
            onChanged: m.onGdpr,
            label: tr.tr('consentPersonalData'),
            error: consentErr != null && !m.consentGdpr,
          ),
          if (consentErr != null) _ErrText(consentErr),
        ]),
      ),
    ]);
  }
}

class _ErrText extends StatelessWidget {
  final String text;
  const _ErrText(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6, left: 2),
        child: Semantics(
          liveRegion: true,
          child: Text(text, style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.err)),
        ),
      );
}

/// Calls [onChange] when a controller written by a child (date dropdowns)
/// changes — clears that field's inline error.
class _CtrlWatch extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onChange;
  final Widget child;
  const _CtrlWatch({required this.controller, required this.onChange, required this.child});

  @override
  State<_CtrlWatch> createState() => _CtrlWatchState();
}

class _CtrlWatchState extends State<_CtrlWatch> {
  late String _last = widget.controller.text;

  void _on() {
    if (widget.controller.text == _last) return;
    _last = widget.controller.text;
    widget.onChange();
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_on);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_on);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
