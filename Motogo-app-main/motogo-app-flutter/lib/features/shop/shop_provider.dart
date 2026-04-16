import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth_guard.dart';
import '../../core/supabase_client.dart';
import '../booking/booking_models.dart';
import 'shop_models.dart';

/// Active products from Supabase.
final productsProvider = FutureProvider<List<Product>>((ref) async {
  try {
    final res = await MotoGoSupabase.client
        .from('products')
        .select()
        .eq('is_active', true)
        .order('sort_order');
    return (res as List).map((e) => Product.fromJson(e)).toList();
  } catch (e) {
    if (await handleAuthError(e)) return [];
    rethrow;
  }
});

/// Shopping cart state.
class CartNotifier extends StateNotifier<List<CartItem>> {
  CartNotifier() : super([]);

  void addItem(String id, String name, double price) {
    final idx = state.indexWhere((i) => i.id == id);
    if (idx >= 0) {
      state = [
        for (var i = 0; i < state.length; i++)
          if (i == idx) CartItem(id: state[i].id, name: state[i].name, price: state[i].price, qty: state[i].qty + 1)
          else state[i]
      ];
    } else {
      state = [...state, CartItem(id: id, name: name, price: price)];
    }
  }

  void removeItem(String id) {
    state = state.where((i) => i.id != id).toList();
  }

  void changeQty(String id, int delta) {
    state = state.map((i) {
      if (i.id != id) return i;
      final newQty = i.qty + delta;
      return newQty <= 0 ? null : CartItem(id: i.id, name: i.name, price: i.price, qty: newQty);
    }).whereType<CartItem>().toList();
  }

  void clear() => state = [];

  double get subtotal => state.fold(0, (s, i) => s + i.total);
  int get itemCount => state.fold(0, (s, i) => s + i.qty);
}

final cartProvider = StateNotifierProvider<CartNotifier, List<CartItem>>(
  (_) => CartNotifier(),
);

/// Cart FAB dismissed state — resets when cart changes.
final cartFabDismissedProvider = StateProvider<bool>((_) => false);

/// Shipping mode.
final shipModeProvider = StateProvider<ShipMode>((_) => ShipMode.post);

/// Shop applied discount codes (promo + voucher).
final shopAppliedCodesProvider =
    StateProvider<List<AppliedDiscount>>((_) => []);

/// Shop discount total in Kč (calculated from applied codes).
final shopDiscountProvider = StateProvider<double>((_) => 0);

/// Create shop order via RPC.
Future<String?> createShopOrder({
  required List<CartItem> items,
  required ShipMode shipping,
  Map<String, String>? address,
  String? promoCode,
}) async {
  try {
    final res = await MotoGoSupabase.client.rpc('create_shop_order', params: {
      'p_items': items.map((i) => {
        'id': i.id,
        'name': i.name,
        'price': i.price,
        'qty': i.qty,
      }).toList(),
      'p_shipping_method': shipping.name,
      'p_shipping_address': address,
      'p_payment_method': 'card',
      'p_promo_code': promoCode,
    });
    if (res is Map && res['order_id'] != null) {
      return res['order_id'] as String;
    }
    return null;
  } catch (e) {
    return null;
  }
}

/// Confirm shop payment after successful Stripe transaction.
/// Mirrors confirm_shop_payment() from cart-checkout.js.
Future<bool> confirmShopPayment(String orderId, String method) async {
  try {
    await MotoGoSupabase.client.rpc('confirm_shop_payment', params: {
      'p_order_id': orderId,
      'p_method': method,
    });
    return true;
  } catch (_) {
    return false;
  }
}

/// Mark applied voucher codes as redeemed after successful payment.
/// Mirrors voucher status update from cart-checkout.js.
Future<void> markVouchersRedeemed(List<AppliedDiscount> codes) async {
  final userId = MotoGoSupabase.currentUser?.id;
  if (userId == null) return;

  for (final code in codes) {
    if (code.promoId == null) continue;
    // Only mark voucher-type (fixed amount with promoId from voucher table)
    try {
      await MotoGoSupabase.client.from('vouchers').update({
        'status': 'redeemed',
        'redeemed_at': DateTime.now().toUtc().toIso8601String(),
        'redeemed_by': userId,
      }).eq('id', code.promoId!);
    } catch (_) {}
  }
}

/// Check if cart is digital-only (vouchers).
bool isCartDigitalOnly(List<CartItem> items) {
  return items.every((i) => i.id.startsWith('voucher'));
}
