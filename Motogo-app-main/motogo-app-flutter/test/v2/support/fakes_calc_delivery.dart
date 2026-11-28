// Calculator with delivery (owner 2026-11-27): shared fixtures — a faked
// Mapy.cz (geocode + route + suggest) so the address sheet prices a known
// distance, a profile with an address in Jihlava, and the handover the
// tests enter.
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:motogo_app/core/booking_address_carry.dart';
import 'package:motogo_app/features/booking/booking_models.dart';
import 'package:motogo_app/features/booking/price_calculator.dart';

/// Road distance the faked router answers (Mezná → Jihlava).
const kRouteKm = 32.4;

/// The form's own fee for [kRouteKm]: 1 000 + 40 × km.
final kRouteFee = PriceCalculator.calcDeliveryFee(kRouteKm);

/// Profile whose address is the sheet's one-tap quick option.
const kProfileJihlava = <String, dynamic>{
  'full_name': 'Jan Novák',
  'license_group': ['A', 'B'],
  'street': 'Masarykovo náměstí 1',
  'city': 'Jihlava',
  'zip': '58601',
  'license_number': 'EK123456',
  'license_expiry': '2034-05-01',
  'gear_sizes': {
    'rider': {'helmet': 'L', 'gloves': 'M', 'jacket': 'L', 'pants': 'M'},
  },
};

/// Runs [body] with Mapy.cz answering at once: geocode → Jihlava, route →
/// [km] (metres, as the API), suggest → nothing. Everything else is 404, so
/// no real network is touched.
Future<T> deliveryNet<T>(Future<T> Function() body, {double km = kRouteKm}) => http.runWithClient(
    body,
    () => MockClient((req) async {
          final p = req.url.path;
          if (req.url.host == 'api.mapy.cz' && p.endsWith('/geocode')) {
            return http.Response(
                jsonEncode({
                  'items': [
                    {
                      'position': {'lat': 49.3961, 'lon': 15.5912}
                    }
                  ]
                }),
                200);
          }
          if (req.url.host == 'api.mapy.cz' && p.endsWith('/routing/route')) {
            return http.Response(jsonEncode({'length': (km * 1000).round()}), 200);
          }
          return http.Response('{}', 404);
        }));

/// A handover as the calculator's step ④ holds it after the customer
/// entered the Jihlava address on the given sides.
HandoverChoice jihlavaHandover({bool pickup = true, bool ret = false}) => HandoverChoice(
      draft: BookingDraft(
        pickupMethod: pickup ? 'delivery' : 'store',
        returnMethod: ret ? 'delivery' : 'store',
        pickupCity: pickup ? 'Jihlava' : null,
        pickupAddress: pickup ? 'Masarykovo náměstí 1' : null,
        returnCity: ret ? 'Jihlava' : null,
        returnAddress: ret ? 'Masarykovo náměstí 1' : null,
      ),
      pickupFee: pickup ? kRouteFee : 0,
      pickupKm: pickup ? kRouteKm : 0,
      returnFee: ret ? kRouteFee : 0,
      returnKm: ret ? kRouteKm : 0,
    );
