import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_inputs.dart';
import '../../booking/v2/booking_v2_parts.dart' show BkCard;
import '../gear_order_state.dart';
import '../gear_order_ui.dart';

/// Krok 4 „Kontakt“: přihlášený e-mail, jméno, telefon, adresa pro doklad,
/// firma (IČO, DIČ), poznámka, dárkový poukaz a souhlasy — pole webu.
class GearContactV2 extends StatelessWidget {
  final GearOrderState state;
  final GearOrderController ctrl;
  final GearOrderFields fields;
  const GearContactV2({super.key, required this.state, required this.ctrl, required this.fields});

  Widget _field(
    BuildContext context,
    String key,
    TextEditingController c,
    String label,
    void Function(String v) on, {
    TextInputType? type,
    int max = 200,
    List<String>? hints,
    int lines = 1,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          key: ValueKey(key),
          controller: c,
          keyboardType: type,
          autofillHints: hints,
          maxLines: lines,
          minLines: 1,
          inputFormatters: [LengthLimitingTextInputFormatter(max)],
          style: MgType.body.copyWith(color: MgColors.ink),
          decoration: mgInputDecoration(context, label: label),
          onChanged: on,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final email = state.contact.email;
    return BkCard(
      key: const ValueKey('gear-step-contact'),
      icon: MgIcons.person,
      title: tr.tr('groStepContact'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (email.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(tr.trArgs('groLoggedAs', {'email': email}),
                key: const ValueKey('gear-logged-as'), style: MgType.small.copyWith(color: MgColors.lead)),
          ),
        _field(context, 'gear-name', fields.name, tr.tr('groName'), (v) => ctrl.setContact((c) => c.name = v),
            hints: const [AutofillHints.name]),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: InputDecorator(
            key: const ValueKey('gear-email'),
            isEmpty: email.isEmpty,
            decoration: mgInputDecoration(context, label: tr.tr('groEmail'), filledWell: true),
            child: Text(email, style: MgType.body.copyWith(color: MgColors.lead)),
          ),
        ),
        _field(context, 'gear-phone', fields.phone, tr.tr('groPhone'), (v) => ctrl.setContact((c) => c.phone = v),
            type: TextInputType.phone, max: 30, hints: const [AutofillHints.telephoneNumber]),
        _field(context, 'gear-street', fields.street, tr.tr('groStreet'), (v) => ctrl.setContact((c) => c.street = v),
            hints: const [AutofillHints.streetAddressLine1]),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 110,
            child: _field(context, 'gear-zip', fields.zip, tr.tr('groZip'), (v) => ctrl.setContact((c) => c.zip = v),
                max: 12, hints: const [AutofillHints.postalCode]),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _field(context, 'gear-city', fields.city, tr.tr('groCity'), (v) => ctrl.setContact((c) => c.city = v),
                max: 100, hints: const [AutofillHints.addressCity]),
          ),
        ]),
        MgCheckRow(
          key: const ValueKey('gear-company-on'),
          value: state.companyOn,
          onChanged: ctrl.setCompanyOn,
          label: tr.tr('groCompanyToggle'),
        ),
        if (state.companyOn) ...[
          const SizedBox(height: 4),
          _field(context, 'gear-company', fields.company, tr.tr('groCompany'), (v) => ctrl.setContact((c) => c.company = v)),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: _field(context, 'gear-ico', fields.ico, tr.tr('groIco'), (v) => ctrl.setContact((c) => c.ico = v), max: 20)),
            const SizedBox(width: 8),
            Expanded(child: _field(context, 'gear-dic', fields.dic, tr.tr('groDic'), (v) => ctrl.setContact((c) => c.dic = v), max: 20)),
          ]),
        ],
        const SizedBox(height: 4),
        _field(context, 'gear-note', fields.note, tr.tr('groNote'), ctrl.setNote, max: 500, lines: 3),
        GearVoucherV2(state: state, ctrl: ctrl, fields: fields),
        const Divider(height: 16, color: MgColors.line),
        MgCheckRow(key: const ValueKey('gear-vop'), value: state.vop, onChanged: ctrl.setVop, label: tr.tr('groAgreeVop')),
        MgCheckRow(key: const ValueKey('gear-gdpr'), value: state.gdpr, onChanged: ctrl.setGdpr, label: tr.tr('groAgreeGdpr')),
      ]),
    );
  }
}

/// „Mám dárkový poukaz“ → kód (velkými písmeny) + „Použít“; stav ověření
/// (čekám / platí −X + „Odebrat poukaz“ / neplatí / až po výběru).
class GearVoucherV2 extends StatelessWidget {
  final GearOrderState state;
  final GearOrderController ctrl;
  final GearOrderFields fields;
  const GearVoucherV2({super.key, required this.state, required this.ctrl, required this.fields});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final vs = state.vstate;
    final sum = state.summary;
    void apply() => ctrl.applyVoucher(fields.voucher.text);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      MgCheckRow(
        key: const ValueKey('gear-voucher-on'),
        value: state.voucherOn,
        onChanged: (v) {
          if (!v) fields.voucher.clear();
          ctrl.setVoucherOn(v);
        },
        label: tr.tr('groVoucherToggle'),
      ),
      if (state.voucherOn) ...[
        const SizedBox(height: 4),
        Row(children: [
          Expanded(
            child: TextField(
              key: const ValueKey('gear-voucher'),
              controller: fields.voucher,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              enableSuggestions: false,
              inputFormatters: [LengthLimitingTextInputFormatter(40)],
              style: MgType.body.copyWith(color: MgColors.ink),
              decoration: mgInputDecoration(context, label: tr.tr('groVoucherPh')),
              onSubmitted: (_) => apply(),
            ),
          ),
          const SizedBox(width: 8),
          MgBtnInk(key: const ValueKey('gear-voucher-apply'), label: tr.tr('groVoucherApply'), onTap: apply, expand: false),
        ]),
        if (vs.isNotEmpty)
          Padding(
            key: const ValueKey('gear-voucher-msg'),
            padding: const EdgeInsets.only(top: 8),
            child: vs == 'ok'
                ? Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
                    Text(
                      '${tr.trArgs('groVoucherLine', {'code': sum.voucherCode})}: −${gearMoney(sum.voucher)}',
                      style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.link),
                    ),
                    TextButton(
                      key: const ValueKey('gear-voucher-remove'),
                      onPressed: () {
                        fields.voucher.clear();
                        ctrl.removeVoucher();
                      },
                      child: Text(tr.tr('groVoucherRemove'),
                          style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.link)),
                    ),
                  ])
                : Text(
                    tr.tr(switch (vs) { 'bad' => 'groVoucherBad', 'wait' => 'groVoucherWait', _ => 'groVoucherNeed' }),
                    style: MgType.small.copyWith(
                        fontWeight: FontWeight.w700, color: vs == 'bad' ? MgColors.err : MgColors.lead),
                  ),
          ),
      ],
    ]);
  }
}
