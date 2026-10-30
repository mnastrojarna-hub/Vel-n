import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/currency.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/supabase_client.dart';

/// Vlastní dárkový poukaz zákazníka (koupený v e-shopu, kód přišel zprávou).
class MyVoucher {
  final String code;
  final double amount;
  final DateTime? validUntil;
  const MyVoucher({required this.code, required this.amount, this.validUntil});
}

/// Aktivní, platné poukazy, které si zákazník koupil (RLS `vouchers_user_select`:
/// buyer_id = uid). Nabízí se v zadání slevového kódu jedním klepnutím —
/// kód se dál ověřuje BEZE ZMĚNY přes `validateAndApplyCode` (2026-10-22,
/// „nic nevyplňovat dvakrát“). Jen nabídka: bez sítě / chyba = prázdný
/// seznam a kód jde dál napsat ručně.
final myVouchersProvider = FutureProvider.autoDispose<List<MyVoucher>>((ref) async {
  try {
    final uid = MotoGoSupabase.currentUser?.id;
    if (uid == null) return const [];
    final rows = await MotoGoSupabase.client
        .from('vouchers')
        .select('code, amount, valid_from, valid_until')
        .eq('buyer_id', uid)
        .eq('status', 'active')
        .order('valid_until', ascending: true)
        .limit(10)
        .timeout(const Duration(seconds: 10));
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final out = <MyVoucher>[];
    for (final r in rows) {
      final code = (r['code'] ?? '').toString().trim().toUpperCase();
      final from = DateTime.tryParse('${r['valid_from'] ?? ''}');
      final until = DateTime.tryParse('${r['valid_until'] ?? ''}');
      if (code.isEmpty || (from != null && from.isAfter(today)) || (until != null && until.isBefore(today))) continue;
      out.add(MyVoucher(code: code, amount: (r['amount'] as num?)?.toDouble() ?? 0, validUntil: until));
    }
    return out;
  } catch (_) {
    return const [];
  }
});

/// Poukazy, které ještě nejsou uplatněné ([applied] = kódy v rezervaci).
List<MyVoucher> unusedVouchers(List<MyVoucher>? all, Iterable<String> applied) {
  final used = applied.map((c) => c.toUpperCase()).toSet();
  return [for (final v in all ?? const <MyVoucher>[]) if (!used.contains(v.code)) v];
}

/// Poukazy v dialogu slevového kódu (oba vzhledy, oba stromy): klepnutí
/// kód vloží do pole, uplatní ho „Použít“ stejně jako napsaný kód (r2).
class MyVoucherChips extends StatelessWidget {
  final List<MyVoucher> vouchers;
  final bool busy;
  final ValueChanged<String> onUse;
  const MyVoucherChips({super.key, required this.vouchers, required this.onUse, this.busy = false});

  @override
  Widget build(BuildContext context) {
    if (vouchers.isEmpty) return const SizedBox.shrink();
    final tr = t(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr.tr('bkMyVouchers'),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1A2E22))),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final v in vouchers)
            Semantics(
              button: true,
              label: tr.trArgs('bkVoucherUseA11y', {'code': v.code, 'amount': Money.czk(v.amount)}),
              excludeSemantics: true,
              child: Material(
                color: const Color(0xFFE8FFE8),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: busy ? null : () => onUse(v.code),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.card_giftcard, size: 16, color: Color(0xFF1A8A18)),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text('${v.code} · ${Money.czk(v.amount).replaceAll(' ', '\u00A0')}',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF0F1A14))),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ]),
    );
  }
}
