/// E-shop (2026-09-24): v e-shopu platí jen promo kódy — dárkový poukaz ani
/// poukaz ze Slevomatu ne, a na nákup dárkového poukazu žádný kód. Hlášky pro
/// chyby serverového výpočtu ceny (create_shop_order v2).
/// Merged into the global translations map.
const Map<String, Map<String, String>> translationsExt22Eshop = {
  'cs': {
    'shopVoucherNotAllowed': 'Dárkový poukaz ani poukaz ze Slevomatu nelze v e-shopu uplatnit — platí jen na půjčení motorky.',
    'shopCodeNotForVoucher': 'Slevový kód nelze uplatnit na nákup dárkového poukazu.',
    'shopCodeInvalid': 'Kód {code} nelze v e-shopu uplatnit. Platí jen slevové (promo) kódy — dárkové poukazy a poukazy ze Slevomatu jen na půjčení motorky.',
    'shopOutOfStock': 'Některé zboží v košíku už není skladem v požadovaném množství.',
    'shopProductUnavailable': 'Některé zboží v košíku už není v nabídce. Upravte prosím košík.',
  },
  'en': {
    'shopVoucherNotAllowed': 'Gift vouchers and Slevomat vouchers cannot be used in the e-shop — they are only valid for motorcycle rental.',
    'shopCodeNotForVoucher': 'A discount code cannot be applied to buying a gift voucher.',
    'shopCodeInvalid': 'Code {code} cannot be used in the e-shop. Only discount (promo) codes apply — gift and Slevomat vouchers are only for motorcycle rental.',
    'shopOutOfStock': 'Some items in your cart are no longer in stock in the requested quantity.',
    'shopProductUnavailable': 'Some items in your cart are no longer available. Please update your cart.',
  },
  'de': {
    'shopVoucherNotAllowed': 'Geschenkgutscheine und Slevomat-Gutscheine können im E-Shop nicht eingelöst werden – sie gelten nur für die Motorradmiete.',
    'shopCodeNotForVoucher': 'Ein Rabattcode kann nicht auf den Kauf eines Geschenkgutscheins angewendet werden.',
    'shopCodeInvalid': 'Der Code {code} kann im E-Shop nicht eingelöst werden. Es gelten nur Rabattcodes (Promo-Codes) – Geschenk- und Slevomat-Gutscheine nur für die Motorradmiete.',
    'shopOutOfStock': 'Einige Artikel im Warenkorb sind in der gewünschten Menge nicht mehr auf Lager.',
    'shopProductUnavailable': 'Einige Artikel im Warenkorb sind nicht mehr verfügbar. Bitte passen Sie den Warenkorb an.',
  },
  'es': {
    'shopVoucherNotAllowed': 'Los vales regalo y los vales de Slevomat no se pueden usar en la tienda online: solo son válidos para el alquiler de motos.',
    'shopCodeNotForVoucher': 'No se puede aplicar un código de descuento a la compra de un vale regalo.',
    'shopCodeInvalid': 'El código {code} no se puede usar en la tienda online. Solo valen los códigos de descuento (promocionales); los vales regalo y de Slevomat son solo para el alquiler de motos.',
    'shopOutOfStock': 'Algunos productos del carrito ya no están disponibles en la cantidad solicitada.',
    'shopProductUnavailable': 'Algunos productos del carrito ya no están disponibles. Actualiza el carrito, por favor.',
  },
  'fr': {
    'shopVoucherNotAllowed': 'Les bons cadeaux et les bons Slevomat ne sont pas utilisables dans la boutique – ils sont valables uniquement pour la location de moto.',
    'shopCodeNotForVoucher': 'Un code de réduction ne peut pas être appliqué à l\'achat d\'un bon cadeau.',
    'shopCodeInvalid': 'Le code {code} n\'est pas utilisable dans la boutique. Seuls les codes de réduction (codes promo) s\'appliquent – les bons cadeaux et Slevomat sont réservés à la location de moto.',
    'shopOutOfStock': 'Certains articles du panier ne sont plus en stock dans la quantité demandée.',
    'shopProductUnavailable': 'Certains articles du panier ne sont plus disponibles. Merci de mettre à jour votre panier.',
  },
  'nl': {
    'shopVoucherNotAllowed': 'Cadeaubonnen en Slevomat-bonnen kunnen niet in de webshop worden gebruikt – ze gelden alleen voor motorverhuur.',
    'shopCodeNotForVoucher': 'Een kortingscode kan niet worden toegepast op de aankoop van een cadeaubon.',
    'shopCodeInvalid': 'Code {code} kan niet in de webshop worden gebruikt. Alleen kortingscodes (promocodes) gelden – cadeaubonnen en Slevomat-bonnen alleen voor motorverhuur.',
    'shopOutOfStock': 'Sommige artikelen in je winkelwagen zijn niet meer op voorraad in de gevraagde hoeveelheid.',
    'shopProductUnavailable': 'Sommige artikelen in je winkelwagen zijn niet meer beschikbaar. Pas je winkelwagen aan.',
  },
  'pl': {
    'shopVoucherNotAllowed': 'Bonów podarunkowych ani bonów Slevomat nie można wykorzystać w sklepie – są ważne tylko na wynajem motocykla.',
    'shopCodeNotForVoucher': 'Kodu rabatowego nie można zastosować przy zakupie bonu podarunkowego.',
    'shopCodeInvalid': 'Kodu {code} nie można użyć w sklepie. Obowiązują tylko kody rabatowe (promocyjne) – bony podarunkowe i Slevomat tylko na wynajem motocykla.',
    'shopOutOfStock': 'Niektórych produktów z koszyka nie ma już w magazynie w żądanej ilości.',
    'shopProductUnavailable': 'Niektóre produkty z koszyka nie są już dostępne. Zaktualizuj koszyk.',
  },
  'uk': {
    'shopVoucherNotAllowed': 'Подарункові сертифікати та сертифікати Slevomat не можна використати в інтернет-магазині – вони дійсні лише для оренди мотоцикла.',
    'shopCodeNotForVoucher': 'Код знижки не можна застосувати до купівлі подарункового сертифіката.',
    'shopCodeInvalid': 'Код {code} не можна використати в інтернет-магазині. Діють лише коди знижок (промокоди) – подарункові сертифікати та Slevomat лише для оренди мотоцикла.',
    'shopOutOfStock': 'Деяких товарів у кошику вже немає на складі в потрібній кількості.',
    'shopProductUnavailable': 'Деякі товари в кошику вже недоступні. Будь ласка, оновіть кошик.',
  },
};
