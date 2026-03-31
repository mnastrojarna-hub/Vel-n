import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/supabase_client.dart';

/// Payment methods from Supabase payment_methods table.
/// Mirrors apiFetchPaymentMethods() from api-payment-methods.js.
final paymentMethodsProvider =
    FutureProvider<List<SavedCard>>((ref) async {
  final user = MotoGoSupabase.currentUser;
  if (user == null) return [];

  try {
    final res = await MotoGoSupabase.client
        .from('payment_methods')
        .select(
          'id, stripe_payment_method_id, brand, last4, '
          'exp_month, exp_year, holder_name, is_default',
        )
        .eq('user_id', user.id)
        .order('is_default', ascending: false);

    return (res as List)
        .map((e) => SavedCard.fromJson(e as Map<String, dynamic>))
        .toList();
  } catch (_) {
    return [];
  }
});

/// Default saved card (first with is_default=true).
final defaultCardProvider = Provider<SavedCard?>((ref) {
  final cards = ref.watch(paymentMethodsProvider).valueOrNull;
  if (cards == null || cards.isEmpty) return null;
  return cards.firstWhere((c) => c.isDefault, orElse: () => cards.first);
});

/// Saved card model — mirrors payment_methods table columns.
class SavedCard {
  final String id;
  final String stripeId;
  final String brand;
  final String last4;
  final int expMonth;
  final int expYear;
  final String? holderName;
  final bool isDefault;

  const SavedCard({
    required this.id,
    required this.stripeId,
    required this.brand,
    required this.last4,
    required this.expMonth,
    required this.expYear,
    this.holderName,
    required this.isDefault,
  });

  factory SavedCard.fromJson(Map<String, dynamic> json) {
    return SavedCard(
      id: json['id'] as String,
      stripeId: json['stripe_payment_method_id'] as String? ?? '',
      brand: json['brand'] as String? ?? 'card',
      last4: json['last4'] as String? ?? '****',
      expMonth: json['exp_month'] as int? ?? 1,
      expYear: json['exp_year'] as int? ?? 2030,
      holderName: json['holder_name'] as String?,
      isDefault: json['is_default'] as bool? ?? false,
    );
  }

  String get displayBrand => brand.toUpperCase();
  String get displayExpiry => '$expMonth/${expYear % 100}';
}

/// Delete a payment method via manage-payment-methods edge function.
Future<bool> deletePaymentMethod(String pmId) async {
  try {
    final session = MotoGoSupabase.currentSession;
    if (session == null) return false;

    await MotoGoSupabase.client.functions.invoke(
      'manage-payment-methods',
      body: {'action': 'delete', 'payment_method_id': pmId},
    );
    return true;
  } catch (_) {
    return false;
  }
}

/// Set a card as default.
Future<bool> setDefaultPaymentMethod(String pmId) async {
  try {
    await MotoGoSupabase.client.functions.invoke(
      'manage-payment-methods',
      body: {'action': 'set_default', 'payment_method_id': pmId},
    );
    return true;
  } catch (_) {
    return false;
  }
}

/// Setup a new card (Stripe Checkout in setup mode).
Future<String?> setupNewCard() async {
  try {
    final res = await MotoGoSupabase.client.functions.invoke(
      'manage-payment-methods',
      body: {'action': 'setup'},
    );
    final data = res.data as Map<String, dynamic>?;
    return data?['url'] as String?;
  } catch (_) {
    return null;
  }
}

/// Auto-cancel timer constant (10 minutes) — matches _PAYMENT_TIMEOUT_MS.
const paymentTimeoutDuration = Duration(minutes: 10);

/// Max payment attempts before auto-cancel.
const maxPaymentAttempts = 3;
