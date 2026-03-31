import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../auth/widgets/toast_helper.dart';
import 'payment_provider.dart';
import 'stripe_service.dart';

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
        title: const Text('Platební metody'),
        backgroundColor: MotoGoColors.dark,
      ),
      body: cardsAsync.when(
        data: (cards) => _buildCardsList(context, ref, cards),
        loading: () => const Center(
          child: CircularProgressIndicator(color: MotoGoColors.green),
        ),
        error: (_, __) => const Center(
          child: Text('Chyba při načítání karet',
              style: TextStyle(color: MotoGoColors.red)),
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
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Column(
              children: [
                Text('💳', style: TextStyle(fontSize: 48)),
                SizedBox(height: 12),
                Text(
                  'Žádné uložené karty',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: MotoGoColors.black,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Přidejte kartu pro rychlejší platby',
                  style: TextStyle(fontSize: 12, color: MotoGoColors.g400),
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
          label: const Text('Přidat novou kartu'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            side: const BorderSide(color: MotoGoColors.green, width: 2),
            foregroundColor: MotoGoColors.greenDarker,
          ),
        ),

        const SizedBox(height: 12),
        const Text(
          'Údaje karet jsou zabezpečeny přes Stripe.\nMotoGo24 nikdy neukládá číslo karty.',
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
        title: const Text('Odebrat kartu?'),
        content: Text('•••• ${card.last4} ${card.displayBrand}'),
        actions: [
          TextButton(
              onPressed: () => ctx.pop(false), child: const Text('Zrušit')),
          TextButton(
              onPressed: () => ctx.pop(true),
              child:
                  const Text('Odebrat', style: TextStyle(color: MotoGoColors.red))),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final ok = await deletePaymentMethod(card.stripeId);
    if (!context.mounted) return;

    if (ok) {
      showMotoGoToast(context, icon: '✓', title: 'Karta odebrána', message: '');
      ref.invalidate(paymentMethodsProvider);
    } else {
      showMotoGoToast(context,
          icon: '✗', title: 'Chyba', message: 'Nepodařilo se odebrat kartu');
    }
  }

  Future<void> _setDefault(
      BuildContext context, WidgetRef ref, SavedCard card) async {
    final ok = await setDefaultPaymentMethod(card.stripeId);
    if (!context.mounted) return;

    if (ok) {
      showMotoGoToast(context,
          icon: '✓', title: 'Prioritní karta nastavena', message: '');
      ref.invalidate(paymentMethodsProvider);
    } else {
      showMotoGoToast(context,
          icon: '✗', title: 'Chyba', message: 'Nepodařilo se nastavit');
    }
  }

  Future<void> _addNewCard(BuildContext context, WidgetRef ref) async {
    final url = await setupNewCard();
    if (url != null) {
      await StripeService.openCheckout(url);
      // After return from Stripe setup, refresh cards
      if (context.mounted) {
        await Future.delayed(const Duration(seconds: 3));
        ref.invalidate(paymentMethodsProvider);
      }
    } else if (context.mounted) {
      showMotoGoToast(context,
          icon: '✗', title: 'Chyba', message: 'Nepodařilo se otevřít Stripe');
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
                  'Platí do ${card.displayExpiry}${card.holderName != null ? ' · ${card.holderName}' : ''}',
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
