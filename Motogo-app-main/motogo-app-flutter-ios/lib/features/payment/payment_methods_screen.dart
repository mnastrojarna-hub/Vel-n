import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/supabase_client.dart';
import '../auth/widgets/toast_helper.dart';
import 'payment_provider.dart';

/// Payment methods management — mirrors profile → Platební metody
/// from profile-ui-2.js + api-payment-methods.js.
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
                  t(context).tr('cardsSavedAtCheckout'),
                  style: const TextStyle(fontSize: 12, color: MotoGoColors.g400),
                  textAlign: TextAlign.center,
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

        // Cards are added automatically during a real payment via Stripe
        // (Payment Sheet saves the card to the Stripe Customer). We deliberately
        // do NOT offer a manual card-entry form here — collecting a raw card
        // number / CVV in a custom field is an App Store 5.1.1 / PCI problem.
        if (cards.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            t(context).tr('cardsSavedAtCheckout'),
            style: TextStyle(fontSize: 12, color: MotoGoColors.g400),
            textAlign: TextAlign.center,
          ),
        ],

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

    final ok = await deletePaymentMethod(card.stripeId);
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
              if (!card.isDefault)
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

