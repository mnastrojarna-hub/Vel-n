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
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Column(
              children: [
                Text('💳', style: TextStyle(fontSize: 48)),
                SizedBox(height: 12),
                Text(
                  t(context).tr('noSavedCards'),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: MotoGoColors.black,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  t(context).tr('addCardForFaster'),
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

  Future<void> _addNewCard(BuildContext context, WidgetRef ref) async {
    final cardNumberCtrl = TextEditingController();
    final expCtrl = TextEditingController();
    final holderCtrl = TextEditingController();

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(t(context).tr('addPaymentCard'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
          const SizedBox(height: 4),
          Text(t(context).tr('cardSavedInApp'),
            style: TextStyle(fontSize: 11, color: MotoGoColors.g400), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          TextField(controller: holderCtrl, decoration: InputDecoration(labelText: t(context).tr('cardHolderName'))),
          const SizedBox(height: 8),
          TextField(controller: cardNumberCtrl, decoration: InputDecoration(labelText: t(context).tr('cardNumber'), hintText: '1234 5678 9012 3456'), keyboardType: TextInputType.number, maxLength: 19),
          const SizedBox(height: 8),
          TextField(controller: expCtrl, decoration: InputDecoration(labelText: t(context).tr('cardExpiry'), hintText: '12/28'), keyboardType: TextInputType.datetime),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              final digits = cardNumberCtrl.text.replaceAll(RegExp(r'\s'), '');
              if (digits.length < 13) return;
              Navigator.pop(ctx, true);
            },
            style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.save, size: 18),
              const SizedBox(width: 8),
              Text(t(context).tr('saveCard')),
            ]),
          ),
        ]),
      ),
    );
    if (result != true || !context.mounted) return;

    // Save to Supabase payment_methods table
    final user = MotoGoSupabase.currentUser;
    if (user == null) return;
    try {
      final digits = cardNumberCtrl.text.replaceAll(RegExp(r'\s'), '');
      final last4 = digits.length >= 4 ? digits.substring(digits.length - 4) : digits;
      // Detect brand from card number prefix
      String brand = 'Card';
      if (digits.startsWith('4')) {
        brand = 'Visa';
      } else if (digits.startsWith('5') || digits.startsWith('2')) {
        brand = 'Mastercard';
      }
      final expParts = expCtrl.text.split('/');
      await MotoGoSupabase.client.from('payment_methods').insert({
        'user_id': user.id,
        'type': 'card',
        'brand': brand,
        'last4': last4,
        'exp_month': expParts.isNotEmpty ? int.tryParse(expParts[0]) : null,
        'exp_year': expParts.length > 1 ? int.tryParse('20${expParts[1]}') : null,
        'holder_name': holderCtrl.text.trim(),
        'is_default': true,
      });
      if (context.mounted) {
        showMotoGoToast(context, icon: '✓', title: t(context).tr('cardSaved'), message: '•••• $last4');
        ref.invalidate(paymentMethodsProvider);
      }
    } catch (e) {
      if (context.mounted) showMotoGoToast(context, icon: '✗', title: t(context).error, message: '$e');
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
