import 'package:flutter/material.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/theme.dart';
import '../booking_models.dart';
import '../booking_provider.dart';

/// Promo code / voucher input — mirrors discount section from templates-booking-form2.js.
class PromoCodeInput extends StatefulWidget {
  final List<AppliedDiscount> appliedCodes;
  final ValueChanged<AppliedDiscount> onCodeApplied;
  final ValueChanged<String> onCodeRemoved;

  const PromoCodeInput({
    super.key,
    required this.appliedCodes,
    required this.onCodeApplied,
    required this.onCodeRemoved,
  });

  @override
  State<PromoCodeInput> createState() => _PromoCodeInputState();
}

class _PromoCodeInputState extends State<PromoCodeInput> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _success;

  Future<void> _apply() async {
    final code = _ctrl.text.trim();
    if (code.isEmpty) return;

    // Check if already applied
    if (widget.appliedCodes.any((d) => d.code == code.toUpperCase())) {
      setState(() => _error = t(context).tr('promoAlreadyUsed').replaceAll('{code}', code));
      return;
    }

    setState(() { _loading = true; _error = null; _success = null; });

    final result = await validateAndApplyCode(code);

    if (!mounted) return;
    setState(() => _loading = false);

    if (result.success && result.discount != null) {
      // K2: can't combine two percentage codes
      final newDiscount = result.discount!;
      if (newDiscount.type == DiscountType.percent &&
          widget.appliedCodes.any((d) => d.type == DiscountType.percent)) {
        setState(() {
          _error = t(context).tr('promoNoCombinePercent');
          _success = null;
        });
        return;
      }
      setState(() {
        _success = result.message(t(context).tr);
        _error = null;
      });
      _ctrl.clear();
      widget.onCodeApplied(newDiscount);
    } else {
      setState(() {
        _error = result.message(t(context).tr);
        _success = null;
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${t(context).tr('discountCode')} / ${t(context).tr('giftVoucher')}',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.black),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                decoration: InputDecoration(
                  hintText: t(context).tr('enterCodeHint'),
                  hintStyle: const TextStyle(fontSize: 13, color: MotoGoColors.g400),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
                    borderSide: BorderSide(
                      color: _error != null ? MotoGoColors.red : MotoGoColors.g200,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
                    borderSide: BorderSide(
                      color: _error != null ? MotoGoColors.red : MotoGoColors.g200,
                    ),
                  ),
                ),
                textCapitalization: TextCapitalization.characters,
                onSubmitted: (_) => _apply(),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _loading ? null : _apply,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              child: _loading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.local_offer, size: 16),
                      const SizedBox(width: 6),
                      Text(t(context).tr('apply')),
                    ]),
            ),
          ],
        ),
        // Messages
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_error!, style: const TextStyle(fontSize: 11, color: MotoGoColors.red)),
          ),
        if (_success != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('✓ $_success', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: MotoGoColors.greenDarker)),
          ),
        // Applied codes
        if (widget.appliedCodes.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...widget.appliedCodes.map((d) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: MotoGoColors.greenPale,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: MotoGoColors.green.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Text(
                    d.type == DiscountType.percent
                        ? '🏷️ ${d.code} (−${d.value.toStringAsFixed(0)}%)'
                        : '🎁 ${d.code} (−${d.value.toStringAsFixed(0)} Kč)',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: MotoGoColors.greenDarker),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => widget.onCodeRemoved(d.code),
                    child: const Text('✕', style: TextStyle(fontSize: 14, color: MotoGoColors.g400)),
                  ),
                ],
              ),
            ),
          )),
        ],
      ],
    );
  }
}
