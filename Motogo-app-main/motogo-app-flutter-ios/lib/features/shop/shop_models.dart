/// Product from Supabase products table.
class Product {
  final String id;
  final String name;
  final double price;
  final String? description;
  final String? color;
  final String? material;
  final String? category;
  final String? sku;
  final List<String> images;
  final List<String> sizes;
  final int stockQuantity;
  final bool isActive;

  const Product({
    required this.id,
    required this.name,
    required this.price,
    this.description,
    this.color,
    this.material,
    this.category,
    this.sku,
    this.images = const [],
    this.sizes = const [],
    this.stockQuantity = 0,
    this.isActive = true,
  });

  factory Product.fromJson(Map<String, dynamic> json) => Product(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    price: (json['price'] as num?)?.toDouble() ?? 0,
    description: json['description'] as String?,
    color: json['color'] as String?,
    material: json['material'] as String?,
    category: json['category'] as String?,
    sku: json['sku'] as String?,
    images: (json['images'] as List?)?.map((e) => e.toString()).toList() ?? [],
    sizes: (json['sizes'] as List?)?.map((e) => e.toString()).toList() ?? [],
    stockQuantity: json['stock_quantity'] as int? ?? 0,
    isActive: json['is_active'] as bool? ?? true,
  );

  String get displayImage => images.isNotEmpty ? images.first : '';
  bool get inStock => stockQuantity > 0;
  bool get needsSize => sizes.isNotEmpty;
}

/// Cart item.
class CartItem {
  final String id;
  final String name;
  final double price;
  int qty;

  CartItem({required this.id, required this.name, required this.price, this.qty = 1});

  double get total => price * qty;
}

/// Shipping method — mirrors shipMode from cart-engine.js.
enum ShipMode {
  post,    // 99 Kč, 2-4 days
  pickup,  // Free, at Mezná 9
  digital, // No shipping (vouchers only)
}

const shippingCost = 99.0; // post shipping fee
const printedVoucherShipping = 180.0; // printed voucher + postage

/// Shop order from Supabase shop_orders table.
class ShopOrder {
  final String id;
  final String orderNumber;
  final String status;
  final String paymentStatus;
  final double totalAmount;
  final DateTime createdAt;

  const ShopOrder({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.paymentStatus,
    required this.totalAmount,
    required this.createdAt,
  });

  factory ShopOrder.fromJson(Map<String, dynamic> json) => ShopOrder(
    id: json['id'] as String,
    orderNumber: json['order_number'] as String? ?? '',
    status: json['status'] as String? ?? 'new',
    paymentStatus: json['payment_status'] as String? ?? 'unpaid',
    totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0,
    createdAt: DateTime.parse(json['created_at'] as String),
  );
}
