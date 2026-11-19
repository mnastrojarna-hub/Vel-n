import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/mg_nav_controls.dart';
import '../gear_order_state.dart';
import '../gear_order_ui.dart';
import 'gear_order_branch.dart';
import 'gear_order_contact.dart';
import 'gear_order_dates.dart';
import 'gear_order_items.dart';
import 'gear_order_summary.dart';

/// Starý vzhled objednávky výbavy: tmavá hlavička jako rezervační
/// formulář, číslované karty 1–4 (jako web), souhrn a zelené tlačítko.
class GearOrderView extends StatelessWidget {
  final GearOrderState state;
  final GearOrderController ctrl;
  final GearOrderFields fields;
  final GearOrderActions actions;
  final bool loading;
  final String? message;

  const GearOrderView({
    super.key,
    required this.state,
    required this.ctrl,
    required this.fields,
    required this.actions,
    required this.loading,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final Widget body;
    if (message != null) {
      body = Padding(
        key: const ValueKey('gear-order-message'),
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          const Icon(Icons.info_outline, size: 40, color: MotoGoColors.g400),
          const SizedBox(height: 12),
          Text(message!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: MotoGoColors.g600)),
          const SizedBox(height: 12),
          TextButton(onPressed: actions.retry, child: Text(tr.tr('groRetry'))),
        ]),
      );
    } else if (loading || state.data == null) {
      body = const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator(color: MotoGoColors.green)),
      );
    } else {
      body = Column(key: const ValueKey('gear-order-old'), children: [
        GearOrderBranch(state: state, ctrl: ctrl),
        GearOrderDates(state: state, ctrl: ctrl),
        GearOrderItems(state: state, ctrl: ctrl, onToggleItem: actions.toggleItem, onToggleSet: actions.toggleSet),
        GearOrderContact(state: state, ctrl: ctrl, fields: fields),
        GearOrderSummary(state: state, onSubmit: actions.submit),
        const SizedBox(height: 100),
      ]);
    }
    return Material(
      color: MotoGoColors.bg,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(children: [_header(context, tr), body]),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, AppTranslations tr) {
    final topPad = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(16, topPad + 12, 16, 14),
      decoration: const BoxDecoration(
        color: MotoGoColors.dark,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        MgBackTap(
          onTap: actions.back,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.arrow_back, size: 20, color: Colors.black),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr.tr('groTitle'),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white)),
            const SizedBox(height: 2),
            Text(tr.tr('groLead'), style: const TextStyle(fontSize: 11, color: MotoGoColors.g400)),
          ]),
        ),
      ]),
    );
  }
}
