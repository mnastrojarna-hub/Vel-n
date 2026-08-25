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
///
/// Bere v úvahu JEN karty se Stripe payment method id. Historické řádky
/// zapsané dřívějším ručním formulářem (bez stripe_payment_method_id) nejde
/// strhnout — nesmí spouštět off-session flow ani náhled „uložené karty"
/// na platbě/checkoutu (mátl by: ukázal kartu, kterou nelze použít).
final defaultCardProvider = Provider<SavedCard?>((ref) {
  final all = ref.watch(paymentMethodsProvider).valueOrNull;
  if (all == null) return null;
  final cards = all.where((c) => c.stripeId.isNotEmpty).toList();
  if (cards.isEmpty) return null;
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

/// Attach a Stripe payment method (created client-side via Stripe SDK
/// CardField → createPaymentMethod) to the customer and sync it into the
/// payment_methods table. Používá obrazovka „Platební metody" pro nativní
/// přidání karty — číslo karty/CVV jdou POUZE do Stripe, k nám jen pm id.
Future<bool> attachPaymentMethod(String pmId) async {
  try {
    final res = await MotoGoSupabase.client.functions.invoke(
      'manage-payment-methods',
      body: {'action': 'attach', 'payment_method_id': pmId},
    );
    final data = res.data as Map<String, dynamic>?;
    return data?['success'] == true;
  } catch (_) {
    return false;
  }
}

/// Delete a legacy local-only card row (missing stripe_payment_method_id —
/// vznikaly dřívějším ručním formulářem). Maže přímo v tabulce podle PK;
/// RLS dovoluje uživateli mazat vlastní řádky. Edge `delete` tu nejde použít,
/// protože vyžaduje Stripe pm id, které řádek nemá.
Future<bool> deleteLocalPaymentMethod(String rowId) async {
  try {
    await MotoGoSupabase.client
        .from('payment_methods')
        .delete()
        .eq('id', rowId);
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

/// Payment context — carries data between screens for edit/SOS/booking flows.
/// Mirrors global variables _currentBookingId, _currentPaymentAmount, etc.
/// from Capacitor payment-ui.js + payment-edit.js.
/// SOS price breakdown item for payment display.
class SosPriceItem {
  final String icon;
  final String label;
  final double amount;
  const SosPriceItem({required this.icon, required this.label, required this.amount});
}

class PaymentContext {
  final PaymentFlowType flowType;
  final String? bookingId;
  final String? orderId;
  final String? incidentId;
  final double amount;
  final String label; // displayed to user, e.g. "Doplatek za prodloužení"
  final List<SosPriceItem>? sosBreakdown; // SOS price breakdown items
  final String? sosDepositNote; // "Záloha je vratná po vyhodnocení škody"
  /// Pending edit changes — stored here and applied ONLY after Stripe confirms.
  /// Mirrors window._pendingEditChanges from Capacitor app.
  final Map<String, dynamic>? pendingEditChanges;

  const PaymentContext({
    required this.flowType,
    this.bookingId,
    this.orderId,
    this.incidentId,
    required this.amount,
    required this.label,
    this.sosBreakdown,
    this.sosDepositNote,
    this.pendingEditChanges,
  });
}

enum PaymentFlowType { booking, extension, sos, shop }

/// Global payment context — set before navigating to PaymentScreen.
final paymentContextProvider = StateProvider<PaymentContext?>((ref) => null);

/// ID poslední potvrzené rezervace — PaymentScreen ho nastaví těsně před
/// navigací na /success a `PaymentConfirmationScreen` z něj pak fetchuje
/// stav dokladů a typ motorky (dětská vs. dospělá), aby ukázala parizní
/// dialogy s webovou /potvrzeni stránkou.
final lastConfirmedBookingProvider = StateProvider<String?>((ref) => null);

/// Jeden řádek detailu na univerzální výsledkové obrazovce (ikona + text).
class PaymentOutcomeLine {
  final String icon;
  final String text;
  const PaymentOutcomeLine(this.icon, this.text);
}

/// Data pro univerzální potvrzovací obrazovku (`PaymentResultScreen`) — používají
/// ji flow, které nemají vlastní bohatou děkovací stránku jako nová rezervace
/// (prodloužení/úprava, SOS, e-shop). Zajišťuje, že zákazník po KAŽDÉ platbě
/// uvidí jednoznačné potvrzení „zaplaceno", ne jen mizící toast.
class PaymentOutcome {
  final String title;
  final String subtitle;
  final List<PaymentOutcomeLine> lines;
  /// Popis, co se stane dál (např. „Fakturu jsme poslali na e-mail").
  final String? nextStepNote;
  final String ctaLabel;
  /// Route, kam vede primární tlačítko (Routes.reservations / shop / sosDone…).
  final String ctaRoute;

  const PaymentOutcome({
    required this.title,
    required this.subtitle,
    this.lines = const [],
    this.nextStepNote,
    required this.ctaLabel,
    required this.ctaRoute,
  });
}

/// Nastaví se těsně před navigací na `Routes.paymentResult`.
final paymentOutcomeProvider = StateProvider<PaymentOutcome?>((ref) => null);
