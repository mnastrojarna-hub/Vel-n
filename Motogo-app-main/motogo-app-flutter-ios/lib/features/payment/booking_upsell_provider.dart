import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../shop/shop_models.dart';
import '../shop/shop_provider.dart';

/// Upsell item selected during booking payment flow.
/// Kept separate from the shop cart so the cart FAB never appears.
class BookingUpsellItem {
  final String id;
  final String name;
  final double price;
  final String? size;

  const BookingUpsellItem({
    required this.id,
    required this.name,
    required this.price,
    this.size,
  });
}

/// State notifier for booking upsell selections.
class BookingUpsellNotifier extends StateNotifier<List<BookingUpsellItem>> {
  BookingUpsellNotifier() : super([]);

  /// Toggle a product on/off.
  void toggle(String id, String name, double price, {String? size}) {
    final itemId = size != null ? '$id-$size' : id;
    final exists = state.any((i) => i.id == itemId);
    if (exists) {
      state = state.where((i) => i.id != itemId).toList();
    } else {
      final displayName = size != null ? '$name ($size)' : name;
      state = [
        ...state,
        BookingUpsellItem(
            id: itemId, name: displayName, price: price, size: size),
      ];
    }
  }

  /// Remove all variants of a product (any size).
  void removeProduct(String productId) {
    state = state.where((i) => i.id != productId && !i.id.startsWith('$productId-')).toList();
  }

  /// Check if any variant of a product is selected.
  bool isProductSelected(String productId) =>
      state.any((i) => i.id == productId || i.id.startsWith('$productId-'));

  /// Get the selected size for a product (if any).
  String? selectedSize(String productId) {
    final item = state.where((i) => i.id.startsWith('$productId-')).firstOrNull;
    return item?.size;
  }

  double get total => state.fold(0, (s, i) => s + i.price);

  void clear() => state = [];
}

final bookingUpsellProvider =
    StateNotifierProvider<BookingUpsellNotifier, List<BookingUpsellItem>>(
  (_) => BookingUpsellNotifier(),
);

/// Create a shop order for upsell items added during booking.
/// Uses digital/pickup shipping since these are add-ons to an existing booking.
Future<String?> createBookingUpsellOrder(
  List<BookingUpsellItem> items, {
  String language = 'cs',
}) async {
  if (items.isEmpty) return null;
  final cartItems = items
      .map((i) => CartItem(id: i.id, name: i.name, price: i.price))
      .toList();
  return createShopOrder(
    items: cartItems,
    shipping: ShipMode.pickup,
    language: language,
  );
}
