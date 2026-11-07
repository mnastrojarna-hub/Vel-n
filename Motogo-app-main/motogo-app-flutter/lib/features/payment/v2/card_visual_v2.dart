import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../payment_provider.dart';

/// A saved card drawn as a card (Profil board "Platební metody"): the
/// priority card dark (`gDark`, neon "PRIORITNÍ" chip — OD-PS-13), others
/// white with a line; brand, chip graphic, "•••• 4242" 22/800 tabular,
/// "PLATÍ DO" + expiry and the holder. Under it the EXISTING actions:
/// "Nastavit jako prioritní" (only where the old star was) and red
/// "Odebrat".
class SavedCardV2 extends StatelessWidget {
  final SavedCard card;
  final VoidCallback onDelete;
  final VoidCallback? onSetDefault;
  const SavedCardV2({super.key, required this.card, required this.onDelete, required this.onSetDefault});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final dark = card.isDefault;
    final fg = dark ? MgColors.onDark : MgColors.ink;
    final meta = dark ? MgColors.onDarkMeta : MgColors.meta;
    final holder = card.holderName;
    final face = Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        gradient: dark ? MgGradients.dark : null,
        color: dark ? null : MgColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: dark ? MgColors.neonA(0.25) : MgColors.line),
        boxShadow: dark ? MgShadows.dark : MgShadows.card,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: MgWordFit(
              child: Text(card.displayBrand,
                  style: MgType.h3.copyWith(fontStyle: FontStyle.italic, fontWeight: FontWeight.w900, color: fg)),
            ),
          ),
          if (dark)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: MgColors.neon, borderRadius: BorderRadius.circular(999)),
              child: Text(tr.tr('priority'), style: MgType.micro.copyWith(fontWeight: FontWeight.w900, color: MgColors.onNeon)),
            ),
        ]),
        const SizedBox(height: 14),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Container(
          width: 36,
          height: 26,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            gradient: const LinearGradient(colors: [MgColors.warnDark, MgColors.star]),
          ),
        ),
        ),
        const SizedBox(height: 14),
        Text('•••• ${card.last4}', style: MgType.tab(MgType.h2.copyWith(letterSpacing: 2, color: fg))),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr.tr('validUntil').toUpperCase(), style: MgType.micro.copyWith(color: meta)),
            Text(card.displayExpiry, style: MgType.tab(MgType.body.copyWith(fontWeight: FontWeight.w800, color: fg))),
          ]),
          const Spacer(),
          if (holder != null && holder.isNotEmpty)
            Flexible(
              child: Text(holder.toUpperCase(),
                  textAlign: TextAlign.end, maxLines: 2, style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: fg)),
            ),
        ]),
      ]),
    );
    return Semantics(
      container: true,
      label: '${card.displayBrand} •••• ${card.last4}${dark ? ', ${tr.tr('priority')}' : ''}',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ExcludeSemantics(child: face),
        const SizedBox(height: 4),
        Wrap(alignment: WrapAlignment.end, spacing: 8, children: [
          if (onSetDefault != null) MgBtnText(label: tr.tr('v2UxPsSetPriority'), icon: MgIcons.star, onTap: onSetDefault),
          MgBtnText(label: tr.tr('removeBtn'), icon: MgIcons.trash, color: MgColors.err, onTap: onDelete),
        ]),
      ]),
    );
  }
}
