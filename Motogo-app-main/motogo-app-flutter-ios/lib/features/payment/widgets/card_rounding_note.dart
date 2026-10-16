import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/theme.dart';
import '../card_minimum.dart';

/// Průhlednost minima karty PŘED platbou (D1/D2): „Minimální platba kartou je
/// 15 Kč – zaplatíš 15 Kč" + řádek dorovnání, nebo „Částky do 1 Kč
/// neúčtujeme". Pro běžné částky nic nekreslí.
class CardRoundingNote extends StatelessWidget {
  /// Serverová částka k zaplacení (Kč).
  final num due;
  /// Text pro dorovnání na 15 Kč / pro odpuštění do 1 Kč (`{amount}` = due,
  /// `{rounding}` = dorovnání).
  final String roundKey;
  final String waiveKey;
  /// Ukázat i řádek „Dorovnání na minimální platbu kartou +X".
  final bool showLine;

  const CardRoundingNote({
    super.key,
    required this.due,
    this.roundKey = 'pdRoundNote',
    this.waiveKey = 'pdWaiveNote',
    this.showLine = true,
  });

  @override
  Widget build(BuildContext context) {
    final cc = cardCharge(due);
    if (!cc.isRound && !cc.isWaive) return const SizedBox.shrink();
    final tr = t(context);
    String fill(String s) => s
        .replaceAll('{amount}', kcExact(cc.due))
        .replaceAll('{rounding}', kcExact(cc.rounding.abs()));
    final note = fill(tr.tr(cc.isRound ? roundKey : waiveKey));
    final line = tr.tr(cc.isRound ? 'pdMinCardLine' : 'pdWaiveLine');
    final value = cc.isRound ? '+${kcExact(cc.rounding)}' : kcExact(cc.rounding);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MotoGoColors.amberBg,
        borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
        border: Border.all(color: MotoGoColors.amberBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('ℹ️ $note',
            style: const TextStyle(
                fontSize: 12, height: 1.4, fontWeight: FontWeight.w700, color: Color(0xFF78350F))),
        if (showLine) ...[
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: Text(line,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF92400E))),
            ),
            Text(value,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF78350F))),
          ]),
        ],
      ]),
    );
  }
}
