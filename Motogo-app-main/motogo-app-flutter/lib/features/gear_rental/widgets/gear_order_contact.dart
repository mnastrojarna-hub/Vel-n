import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/theme.dart';
import '../../booking/booking_ui_helpers.dart' show bookingCard, bookingCheckbox;
import '../gear_order_state.dart';
import '../gear_order_ui.dart';
import 'gear_order_branch.dart' show GearOldNote;

InputDecoration _deco(String label) => InputDecoration(
      labelText: label,
      isDense: true,
      filled: true,
      fillColor: MotoGoColors.g100,
      labelStyle: const TextStyle(fontSize: 12, color: MotoGoColors.g500),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: MotoGoColors.g200)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: MotoGoColors.g200)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: MotoGoColors.greenDark, width: 2)),
    );

/// Krok 4 (starý vzhled): kontakt, firma, poznámka, dárkový poukaz a
/// souhlasy — stejná pole jako web.
class GearOrderContact extends StatelessWidget {
  final GearOrderState state;
  final GearOrderController ctrl;
  final GearOrderFields fields;
  const GearOrderContact({super.key, required this.state, required this.ctrl, required this.fields});

  Widget _f(String key, TextEditingController c, String label, void Function(String) on,
          {TextInputType? type, int max = 200, int lines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          key: ValueKey(key),
          controller: c,
          keyboardType: type,
          maxLines: lines,
          minLines: 1,
          inputFormatters: [LengthLimitingTextInputFormatter(max)],
          style: const TextStyle(fontSize: 13, color: MotoGoColors.black),
          decoration: _deco(label),
          onChanged: on,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final email = state.contact.email;
    final vs = state.vstate;
    final sum = state.summary;
    void apply() => ctrl.applyVoucher(fields.voucher.text);
    return bookingCard(
      4,
      tr.tr('groStepContact'),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (email.isNotEmpty) GearOldNote(tr.trArgs('groLoggedAs', {'email': email}), key: const ValueKey('gear-logged-as')),
        const SizedBox(height: 4),
        _f('gear-name', fields.name, tr.tr('groName'), (v) => ctrl.setContact((c) => c.name = v)),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InputDecorator(
            key: const ValueKey('gear-email'),
            isEmpty: email.isEmpty,
            decoration: _deco(tr.tr('groEmail')),
            child: Text(email, style: const TextStyle(fontSize: 13, color: MotoGoColors.g600)),
          ),
        ),
        _f('gear-phone', fields.phone, tr.tr('groPhone'), (v) => ctrl.setContact((c) => c.phone = v),
            type: TextInputType.phone, max: 30),
        _f('gear-street', fields.street, tr.tr('groStreet'), (v) => ctrl.setContact((c) => c.street = v)),
        Row(children: [
          SizedBox(width: 100, child: _f('gear-zip', fields.zip, tr.tr('groZip'), (v) => ctrl.setContact((c) => c.zip = v), max: 12)),
          const SizedBox(width: 8),
          Expanded(child: _f('gear-city', fields.city, tr.tr('groCity'), (v) => ctrl.setContact((c) => c.city = v), max: 100)),
        ]),
        KeyedSubtree(key: const ValueKey('gear-company-on'), child: bookingCheckbox(tr.tr('groCompanyToggle'), state.companyOn, ctrl.setCompanyOn)),
        const SizedBox(height: 8),
        if (state.companyOn) ...[
          _f('gear-company', fields.company, tr.tr('groCompany'), (v) => ctrl.setContact((c) => c.company = v)),
          Row(children: [
            Expanded(child: _f('gear-ico', fields.ico, tr.tr('groIco'), (v) => ctrl.setContact((c) => c.ico = v), max: 20)),
            const SizedBox(width: 8),
            Expanded(child: _f('gear-dic', fields.dic, tr.tr('groDic'), (v) => ctrl.setContact((c) => c.dic = v), max: 20)),
          ]),
        ],
        _f('gear-note', fields.note, tr.tr('groNote'), ctrl.setNote, max: 500, lines: 3),
        KeyedSubtree(
          key: const ValueKey('gear-voucher-on'),
          child: bookingCheckbox(tr.tr('groVoucherToggle'), state.voucherOn, (v) {
            if (!v) fields.voucher.clear();
            ctrl.setVoucherOn(v);
          }),
        ),
        if (state.voucherOn) ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                key: const ValueKey('gear-voucher'),
                controller: fields.voucher,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                inputFormatters: [LengthLimitingTextInputFormatter(40)],
                style: const TextStyle(fontSize: 13, color: MotoGoColors.black),
                decoration: _deco(tr.tr('groVoucherPh')),
                onSubmitted: (_) => apply(),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              key: const ValueKey('gear-voucher-apply'),
              onPressed: apply,
              style: ElevatedButton.styleFrom(
                backgroundColor: MotoGoColors.dark,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(tr.tr('groVoucherApply')),
            ),
          ]),
          if (vs == 'ok')
            Row(key: const ValueKey('gear-voucher-msg'), children: [
              Expanded(
                child: GearOldNote('${tr.trArgs('groVoucherLine', {'code': sum.voucherCode})}: −${gearMoney(sum.voucher)}'),
              ),
              TextButton(
                key: const ValueKey('gear-voucher-remove'),
                onPressed: () {
                  fields.voucher.clear();
                  ctrl.removeVoucher();
                },
                child: Text(tr.tr('groVoucherRemove')),
              ),
            ])
          else if (vs.isNotEmpty)
            GearOldNote(
              tr.tr(switch (vs) { 'bad' => 'groVoucherBad', 'wait' => 'groVoucherWait', _ => 'groVoucherNeed' }),
              key: const ValueKey('gear-voucher-msg'),
              warn: vs == 'bad',
            ),
        ],
        const SizedBox(height: 10),
        KeyedSubtree(key: const ValueKey('gear-vop'), child: bookingCheckbox(tr.tr('groAgreeVop'), state.vop, ctrl.setVop)),
        const SizedBox(height: 8),
        KeyedSubtree(key: const ValueKey('gear-gdpr'), child: bookingCheckbox(tr.tr('groAgreeGdpr'), state.gdpr, ctrl.setGdpr)),
      ]),
    );
  }
}
