import 'package:flutter/material.dart';
import '../../core/i18n/i18n_provider.dart';
import 'booking_models.dart';
import 'booking_provider.dart';

/// Promo code bottom sheet widget for the booking form.

/// Promo code bottom sheet.
void showPromoBottomSheet(BuildContext ctx,
    List<AppliedDiscount> current,
    void Function(AppliedDiscount) onApplied,
    void Function(String) onRemoved) {
  showModalBottomSheet(
    context: ctx,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (c) => _PromoSheetBody(
      current: current,
      onApplied: (d) { onApplied(d); Navigator.pop(c); },
      onRemoved: onRemoved),
  );
}

class _PromoSheetBody extends StatefulWidget {
  final List<AppliedDiscount> current;
  final ValueChanged<AppliedDiscount> onApplied;
  final ValueChanged<String> onRemoved;
  const _PromoSheetBody({required this.current,
    required this.onApplied, required this.onRemoved});
  @override
  State<_PromoSheetBody> createState() => _PromoSheetBodyState();
}

class _PromoSheetBodyState extends State<_PromoSheetBody> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  String? _msg; bool? _ok;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _apply() async {
    final code = _ctrl.text.trim();
    if (code.isEmpty) return;
    setState(() { _loading = true; _msg = null; });
    final result = await validateAndApplyCode(code);
    if (!mounted) return;
    setState(() => _loading = false);
    if (result.success && result.discount != null) {
      _ctrl.clear();
      setState(() { _msg = result.message(t(context).tr); _ok = true; });
      widget.onApplied(result.discount!);
    } else {
      setState(() { _msg = result.message(t(context).tr); _ok = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 16, 20,
        MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4, decoration: BoxDecoration(
          color: const Color(0xFFD4E8E0),
          borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 14),
        Text(t(context).tr('discountCode'), style: const TextStyle(fontSize: 15,
          fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: TextField(controller: _ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            onSubmitted: (_) => _apply(),
            decoration: InputDecoration(
              hintText: t(context).tr('enterCodeHint'),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10))))),
          const SizedBox(width: 8),
          ElevatedButton(onPressed: _loading ? null : _apply,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A2E22),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10))),
            child: _loading
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(t(context).tr('apply').toUpperCase(), style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w800))),
        ]),
        if (_msg != null)
          Padding(padding: const EdgeInsets.only(top: 8),
            child: Text(_ok == true ? '✓ $_msg' : _msg!,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                color: _ok == true ? const Color(0xFF1A8A18) : const Color(0xFFEF4444)))),
      ]));
  }
}
