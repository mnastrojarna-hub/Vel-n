import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import '../../core/theme.dart';
import '../../core/widgets/moto_fx.dart';
import '../../core/i18n/i18n_provider.dart';
import '../auth/widgets/toast_helper.dart';
import 'payment_provider.dart';

/// Payment methods management — mirrors profile → Platební metody
/// from profile-ui-2.js + api-payment-methods.js.
///
/// Přidání karty jde NATIVNĚ přes Stripe SDK (CardField →
/// Stripe.instance.createPaymentMethod → edge fn `manage-payment-methods`
/// action=attach, která PM připojí ke Stripe zákazníkovi a synchronizuje do
/// tabulky payment_methods). Číslo karty ani CVV se NIKDY nedotknou naší DB.
/// Dřívější ruční formulář ukládal jen „atrapu" (řádek bez
/// stripe_payment_method_id), se kterou nešlo platit, a sbíral citlivá data
/// mimo Stripe (PCI problém) — proto byl nahrazen.
class PaymentMethodsScreen extends ConsumerWidget {
  const PaymentMethodsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardsAsync = ref.watch(paymentMethodsProvider);

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      appBar: AppBar(
        leading: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Center(
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(10)),
              child: const Center(child: Text('←', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black))),
            ),
          ),
        ),
        title: Text(t(context).tr('paymentMethodsTitle')),
        backgroundColor: MotoGoColors.dark,
      ),
      body: cardsAsync.when(
        data: (cards) => _buildCardsList(context, ref, cards),
        loading: () => const Center(
          child: CircularProgressIndicator(color: MotoGoColors.green),
        ),
        error: (_, __) => Center(
          child: Text(t(context).tr('cardsLoadError'),
              style: const TextStyle(color: MotoGoColors.red)),
        ),
      ),
    );
  }

  Widget _buildCardsList(
      BuildContext context, WidgetRef ref, List<SavedCard> cards) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (cards.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Column(
              children: [
                const Text('💳', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 12),
                Text(
                  t(context).tr('noSavedCards'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: MotoGoColors.black,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  t(context).tr('addCardForFaster'),
                  style: const TextStyle(fontSize: 12, color: MotoGoColors.g400),
                ),
              ],
            ),
          ),

        // Card list
        ...cards.map((card) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _CardTile(
                card: card,
                onDelete: () => _deleteCard(context, ref, card),
                onSetDefault: () => _setDefault(context, ref, card),
              ),
            )),

        const SizedBox(height: 12),

        // Add new card button
        OutlinedButton.icon(
          onPressed: () => _addNewCard(context, ref),
          icon: const Text('+ ', style: TextStyle(fontSize: 16)),
          label: Text(t(context).tr('addNewCard')),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            side: const BorderSide(color: MotoGoColors.green, width: 2),
            foregroundColor: MotoGoColors.greenDarker,
          ),
        ),

        const SizedBox(height: 12),
        Text(
          t(context).tr('cardsSecuredByStripe'),
          style: TextStyle(fontSize: 10, color: MotoGoColors.g400, height: 1.5),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Future<void> _deleteCard(
      BuildContext context, WidgetRef ref, SavedCard card) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t(context).tr('removeCard')),
        content: Text('•••• ${card.last4} ${card.displayBrand}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false), child: Text(t(context).cancel)),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child:
                  Text(t(context).tr('removeBtn'), style: const TextStyle(color: MotoGoColors.red))),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    // Historický řádek bez Stripe pm id (dřívější ruční formulář) — edge
    // `delete` by ho neuměl smazat (vyžaduje pm id), maže se přímo v tabulce.
    final ok = card.stripeId.isEmpty
        ? await deleteLocalPaymentMethod(card.id)
        : await deletePaymentMethod(card.stripeId);
    if (!context.mounted) return;

    if (ok) {
      showMotoGoToast(context, icon: '✓', title: t(context).tr('cardRemoved'), message: '');
      ref.invalidate(paymentMethodsProvider);
    } else {
      showMotoGoToast(context,
          icon: '✗', title: t(context).error, message: t(context).tr('cardRemoveFailed'));
    }
  }

  Future<void> _setDefault(
      BuildContext context, WidgetRef ref, SavedCard card) async {
    // Historický řádek bez Stripe pm id nejde strhnout → nesmí být prioritní.
    if (card.stripeId.isEmpty) return;
    final ok = await setDefaultPaymentMethod(card.stripeId);
    if (!context.mounted) return;

    if (ok) {
      showMotoGoToast(context,
          icon: '✓', title: t(context).tr('priorityCardSet'), message: '');
      ref.invalidate(paymentMethodsProvider);
    } else {
      showMotoGoToast(context,
          icon: '✗', title: t(context).error, message: t(context).tr('setFailed'));
    }
  }

  Future<void> _addNewCard(BuildContext context, WidgetRef ref) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: const _AddCardSheetBody(),
      ),
    );
    if (saved == null || !context.mounted) return;

    if (saved) {
      showMotoGoToast(context,
          icon: '✓', title: t(context).tr('cardSaved'), message: '');
      ref.invalidate(paymentMethodsProvider);
    } else {
      showMotoGoToast(context,
          icon: '✗',
          title: t(context).error,
          message: t(context).tr('cardSaveFailed'));
    }
  }
}

/// Sheet pro nativní přidání karty přes Stripe SDK — stejné pole (CardField)
/// jako platební sheet, ale místo platby se karta jen uloží (createPaymentMethod
/// + attach na Stripe zákazníka).
class _AddCardSheetBody extends StatefulWidget {
  const _AddCardSheetBody();

  @override
  State<_AddCardSheetBody> createState() => _AddCardSheetBodyState();
}

class _AddCardSheetBodyState extends State<_AddCardSheetBody> {
  bool _cardComplete = false;
  bool _processing = false;

  // Plugin drží zadané údaje v nativním view, které přežívá zavření sheetu —
  // při otevření čistíme, aby tu nestrašila karta z předchozího zadávání
  // (např. z platebního sheetu).
  final CardEditController _cardController = CardEditController();

  @override
  void initState() {
    super.initState();
    // clear() potřebuje připojený nativní CardField → až po prvním framu.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _cardController.clear();
      } catch (_) {
        // Pole se ještě nepřipojilo — pak je prázdné a není co čistit.
      }
    });
  }

  @override
  void dispose() {
    _cardController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_processing || !_cardComplete) return;
    setState(() => _processing = true);
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      // Karta jde POUZE do Stripe (SDK → payment method), k nám jen pm id.
      final pm = await Stripe.instance.createPaymentMethod(
        params: const PaymentMethodParams.card(
          paymentMethodData: PaymentMethodData(),
        ),
      );
      final ok = await attachPaymentMethod(pm.id);
      if (!mounted) return;
      Navigator.of(context).pop(ok);
    } on StripeException {
      // Nevalidní karta / zrušeno — zůstaň v sheetu, ať může opravit.
      if (!mounted) return;
      setState(() => _processing = false);
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context).pop(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = t(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: MotoGoColors.g300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            Text(
              tt.tr('addPaymentCard'),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: MotoGoColors.black,
              ),
            ),
            const SizedBox(height: 16),

            // Nativní pole karty — celý rámeček klikací, vkládání ze schránky OK
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF1FAF7),
                borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
                border: Border.all(color: const Color(0xFFD4E8E0)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                height: 56,
                child: CardField(
                  controller: _cardController,
                  autofocus: true,
                  // Sheet má bílé pozadí — text karty MUSÍ být tmavý (jinak
                  // bílá na bílé = neviditelné). Placeholder zešedlý, kurzor zelený.
                  style: const TextStyle(
                    color: Color(0xFF0F1A14),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  cursorColor: MotoGoColors.greenDark,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintStyle: TextStyle(color: Color(0xFF8AAB99)),
                  ),
                  onCardChanged: (card) {
                    setState(() => _cardComplete = card?.complete ?? false);
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),

            PressableScale(child: ElevatedButton(
              onPressed: (_processing || !_cardComplete) ? null : _save,
              style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
              child: _processing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(tt.tr('saveCard')),
            )),
            const SizedBox(height: 10),
            Text(
              '🔒 ${tt.tr('encryptedPayment')} · Stripe PCI DSS Level 1',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, color: MotoGoColors.g400),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardTile extends StatelessWidget {
  final SavedCard card;
  final VoidCallback onDelete;
  final VoidCallback onSetDefault;
  const _CardTile(
      {required this.card, required this.onDelete, required this.onSetDefault});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
        border: Border.all(
          color: card.isDefault ? MotoGoColors.green : MotoGoColors.g200,
          width: card.isDefault ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          const Text('💳', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '•••• ${card.last4}  ${card.displayBrand}',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: MotoGoColors.black),
                ),
                Text(
                  '${t(context).tr('validUntil')} ${card.displayExpiry}${card.holderName != null ? ' · ${card.holderName}' : ''}',
                  style:
                      const TextStyle(fontSize: 11, color: MotoGoColors.g400),
                ),
                if (card.isDefault)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: MotoGoColors.greenPale,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('PRIORITNÍ',
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: MotoGoColors.greenDarker)),
                  ),
              ],
            ),
          ),
          Column(
            children: [
              // Hvězdička (nastavit jako prioritní) jen u karet se Stripe pm
              // id — historický ručně zapsaný řádek nejde strhnout.
              if (!card.isDefault && card.stripeId.isNotEmpty)
                GestureDetector(
                  onTap: onSetDefault,
                  child: const Text('⭐',
                      style: TextStyle(fontSize: 16)),
                ),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: onDelete,
                child: const Text('🗑️', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
