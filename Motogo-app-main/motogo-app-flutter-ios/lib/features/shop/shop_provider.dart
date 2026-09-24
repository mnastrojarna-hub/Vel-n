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

/// Výsledek založení objednávky. Cenu počítá SERVER (create_shop_order v2,
/// 2026-09-24) — platí se `total` ze serveru, ne součet z košíku.
class ShopOrderResult {
  final String? orderId;
  final double? total;
  final bool autoConfirmed; // objednávka za 0 Kč — server ji rovnou potvrdil
  final String? error; // kód chyby ze serveru (voucher_not_allowed, out_of_stock…)
  final String? code; // kód slevy, ke kterému se chyba vztahuje
  const ShopOrderResult(
      {this.orderId, this.total, this.autoConfirmed = false, this.error, this.code});
}

/// Create shop order via RPC.
Future<ShopOrderResult> createShopOrder({
  required List<CartItem> items,
  required ShipMode shipping,
  Map<String, String>? address,
  String? promoCode,
  String language = 'cs',
}) async {
  try {
    final res = await MotoGoSupabase.client.rpc('create_shop_order', params: {
      // Vedle legacy 'id' posíláme i product_id (UUID) + size vytažené z
      // kompozitního cart id "<uuid>-<velikost>". Stávající RPC tato pole
      // ignoruje (žádný break); jakmile RPC umí per-size sklad, naplní z nich
      // shop_order_items.product_id / size.
      'p_items': items.map((i) {
        final m = RegExp(
                r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')
            .firstMatch(i.id);
        final productId = m?.group(0);
        final size = (productId != null &&
                i.id.length > 37 &&
                i.id[36] == '-')
            ? i.id.substring(37)
            : null;
        return {
          'id': i.id,
          'name': i.name,
          'price': i.price,
          'qty': i.qty,
          if (productId != null) 'product_id': productId,
          if (size != null && size.isNotEmpty) 'size': size,
        };
      }).toList(),
      'p_shipping_method': shipping.name,
      'p_shipping_address': address,
      'p_payment_method': 'card',
      'p_promo_code': promoCode,
    });
    if (res is Map && res['order_id'] != null) {
      final orderId = res['order_id'] as String;
      // i18n: ulož jazyk zákazníka do shop_orders.language (pro maily/SMS/push)
      try {
        await MotoGoSupabase.client.rpc('set_shop_order_language', params: {
          'p_order_id': orderId,
          'p_language': language,
        });
      } catch (_) { /* ignore — log only, neni kritické */ }
      return ShopOrderResult(
        orderId: orderId,
        total: (res['total'] as num?)?.toDouble(),
        autoConfirmed: res['auto_confirmed'] == true,
      );
    }
    if (res is Map) {
      return ShopOrderResult(
          error: res['error']?.toString(), code: res['code']?.toString());
    }
    return const ShopOrderResult();
  } catch (e) {
    return const ShopOrderResult();
  }
}

/// E-shop: platí JEN promo kódy (rozhodnutí provozovatele 2026-09-24) —
/// dárkový poukaz ani poukaz ze Slevomatu v e-shopu neplatí, server
/// (create_shop_order) je odmítne. Záměrně NEvolá slevomat-voucher (ta při
/// kontrole rovnou zakládá voucher v DB).
Future<AppliedDiscount?> validateShopPromoCode(String code) async {
  try {
    final r = await MotoGoSupabase.client
        .rpc('validate_promo_code', params: {'p_code': code});
    if (r is Map && r['valid'] == true) {
      return AppliedDiscount(
        code: code,
        promoId: r['id'] as String?,
        type: r['type'] == 'percent' ? DiscountType.percent : DiscountType.fixed,
        value: (r['value'] as num?)?.toDouble() ?? 0,
      );
    }
  } catch (_) {}
  return null;
}

// Pozn.: klientské potvrzení platby (confirmShopPayment → rpc
// confirm_shop_payment) a označení poukazů jako uplatněných
// (markVouchersRedeemed — RLS ho stejně blokovalo) odstraněny 2026-09-24:
// zaplacenou objednávku označuje VÝHRADNĚ server (webhook / create_shop_order
// u objednávky za 0 Kč), poukazy v e-shopu neplatí.

/// Check if cart is digital-only (vouchers).
bool isCartDigitalOnly(List<CartItem> items) {
  return items.every((i) => i.id.startsWith('voucher'));
}
