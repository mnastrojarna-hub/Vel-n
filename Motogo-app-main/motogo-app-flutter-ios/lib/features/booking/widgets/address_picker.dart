import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/booking_address_carry.dart' show AddrQuick;
import '../booking_ui_helpers.dart' show showAddrBottomSheet;
import '../map_launcher.dart' show launchMapPicker;
import '../price_calculator.dart' show PriceCalculator;
import '../../../core/booking_form_locked_option.dart';
import '../../../core/currency.dart';
import '../../../core/i18n/i18n_provider.dart';

/// Jednořádková adresa (`bookings.pickup_address`, `return_address`) →
/// (ulice, obec): obec = text za POSLEDNÍ čárkou, ulice = vše před ní —
/// `'$ulice, $obec'` dá zpět původní text.
(String, String) splitAddressLine(String? line) {
  final s = (line ?? '').trim();
  final i = s.lastIndexOf(',');
  if (i < 0) return ('', s);
  return (s.substring(0, i).trim(), s.substring(i + 1).trim());
}

/// Stejná adresa bez ohledu na velikost písmen, mezery a čárky.
bool sameAddressLine(String? a, String? b) {
  String n(String? s) => (s ?? '').toLowerCase().replaceAll(RegExp(r'[\s,]+'), ' ').trim();
  return n(a).isNotEmpty && n(a) == n(b);
}

/// Data řádku adresy (zodpovězená sekce): [address] = zobrazená adresa
/// (null = zatím nezadaná), [onTap] znovu otevře list adresy.
class AddressRowData {
  final String? address;
  final VoidCallback onTap;
  final double? distKm;
  final double? fee;
  const AddressRowData({required this.address, required this.onTap, this.distKm, this.fee});
}

/// Jiný vzhled řádku adresy (v2) — null = výchozí řádek.
typedef AddressRowBuilder = Widget Function(BuildContext context, AddressRowData data);

/// Address picker with geocoding.
/// Delegates address entry to [showAddrBottomSheet] — the same modal used in
/// the new-booking flow. Inline autocomplete used to collide with the keyboard
/// in the reservation-edit ListView (field scrolled to top, rest empty).
class AddressPickerWidget extends StatefulWidget {
  final String label;

  /// true = vyzvednutí (přistavení na adresu), false = vrácení (odvoz z
  /// adresy). Dřív se odvozovalo z [label] == 'Vyzvednutí' — v cizojazyčné
  /// appce tak vyzvednutí ukazovalo „odvoz z adresy".
  final bool isPickup;
  final String method;
  final ValueChanged<String> onMethodChanged;
  final ValueChanged<AddressResult> onAddressChanged;
  final ValueChanged<double> onDeliveryFeeChanged;

  /// Název + město pobočky motorky (null = starý výchozí text).
  final String? branchLabel;

  /// Samoobslužná pobočka bez přistavení / odvozu (feature flag
  /// `self_service_delivery` vypnutý, 2026-09-28): volba na adresu zůstává
  /// vidět zabalená s vysvětlením, vybrat nejde ([BookingLockedOptionTile]).
  final bool deliveryBlocked;

  /// Adresa, kterou rezervace na téhle straně UŽ MÁ (jen strana na adrese;
  /// 2026-10-22 „nic nevyplňovat dvakrát“): ukáže se jako vyplněná a
  /// předvyplní list. Potvrzení stejné adresy hlásí rodiči přesně tenhle
  /// text (= beze změny, žádný poplatek ani záznam v historii).
  final String? initialAddress;

  /// Adresa, kterou zákazník v téhle úpravě už zadal (stav rodiče) — po
  /// znovusestavení widgetu se ukáže ona, ne [initialAddress].
  final String? currentAddress;

  /// Rychlé volby listu adresy (adresa druhé strany, adresa z profilu).
  final List<AddrQuick> quick;

  /// Vzhled řádku adresy (v2); null = výchozí řádek.
  final AddressRowBuilder? rowBuilder;

  const AddressPickerWidget({
    super.key,
    required this.label,
    this.isPickup = true,
    required this.method,
    required this.onMethodChanged,
    required this.onAddressChanged,
    required this.onDeliveryFeeChanged,
    this.branchLabel,
    this.deliveryBlocked = false,
    this.initialAddress,
    this.currentAddress,
    this.quick = const [],
    this.rowBuilder,
  });

  @override
  State<AddressPickerWidget> createState() => _AddressPickerWidgetState();
}

class _AddressPickerWidgetState extends State<AddressPickerWidget> {
  String _street = '';
  String _city = '';
  String _zip = '';
  double? _lat, _lng;
  double? _distanceKm;
  double? _deliveryFee;

  // Vzdálenost / cena spočtená v listu — platí až s potvrzenou adresou
  // (list zavřený bez potvrzení nemění cenu ani adresu).
  double? _sheetKm, _sheetFee;

  @override
  void initState() {
    super.initState();
    _fill(widget.currentAddress ?? widget.initialAddress);
  }

  void _fill(String? line) {
    final (street, city) = splitAddressLine(line);
    _street = street;
    _city = city;
    _zip = '';
    _lat = null;
    _lng = null;
  }

  @override
  void didUpdateWidget(AddressPickerWidget old) {
    super.didUpdateWidget(old);
    if (old.method == 'delivery' && widget.method != 'delivery') {
      // Rodič teď drží „beze změny“ → zpět na adresu rezervace (je-li).
      _fill(widget.initialAddress);
      _distanceKm = null;
      _deliveryFee = null;
      // Defer parent setState — see note on "Restartujte aplikaci" crash fix.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {});
        widget.onDeliveryFeeChanged(0);
        widget.onAddressChanged(const AddressResult(street: '', city: '', zip: ''));
      });
    }
  }

  String _deliveryTitle(BuildContext context) =>
      t(context).tr(widget.isPickup ? 'deliveryToAddress' : 'returnFromAddress');

  void _onSaved(String city, String addr) {
    final initial = widget.initialAddress;
    // Stejná (nebo žádná) adresa jako v rezervaci = beze změny.
    final unchanged = initial != null &&
        (city.trim().isEmpty || sameAddressLine('$addr, $city', initial));
    final km = _sheetKm, fee = _sheetFee;
    setState(() {
      if (unchanged) {
        _fill(initial);
        _distanceKm = null;
        _deliveryFee = null;
      } else {
        _city = city;
        _street = addr;
        if (fee != null) {
          _distanceKm = km;
          _deliveryFee = fee;
        }
      }
    });
    if (fee != null) widget.onDeliveryFeeChanged(fee);
    widget.onAddressChanged(unchanged
        ? AddressResult(street: '', city: initial, zip: '')
        : AddressResult(street: _street, city: _city, zip: _zip, lat: _lat, lng: _lng));
  }

  void _openAddressSheet() {
    _sheetKm = null;
    _sheetFee = null;
    showAddrBottomSheet(
      context,
      _deliveryTitle(context),
      _city,
      _street,
      _onSaved,
      onDistCalc: (km, fee) {
        _sheetKm = km;
        _sheetFee = fee;
      },
      // The sheet fills itself from the map result and persists on confirm via
      // the onSave / onDistCalc callbacks above, so just hand back the result.
      onMapTap: (ctx) => launchMapPicker(ctx),
      quick: widget.quick,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final shown = _city.isNotEmpty ? '${_street.isNotEmpty ? '$_street, ' : ''}$_city' : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RadioOption(
          label: tr.tr('atBranch'),
          sublabel: widget.branchLabel ?? 'Mezná 9, Pelhřimov',
          price: tr.free,
          selected: widget.method == 'store',
          onTap: () => widget.onMethodChanged('store'),
        ),
        const SizedBox(height: 6),
        if (widget.deliveryBlocked)
          BookingLockedOptionTile(
            label: _deliveryTitle(context),
            shortReason: t(context).tr('ssNoDeliveryShort'),
            info: t(context).tr('ssNoDeliveryInfo'),
          )
        else
          _RadioOption(
            label: _deliveryTitle(context),
            sublabel: '${Money.czk(PriceCalculator.deliveryBase)} + '
                '${Money.czk(PriceCalculator.deliveryPerKm)}/km',
            price: tr.trArgs('fromPriceValue',
                {'price': Money.czk(PriceCalculator.deliveryBase)}),
            selected: widget.method == 'delivery',
            onTap: () => widget.onMethodChanged('delivery'),
          ),
        if (!widget.deliveryBlocked && widget.method == 'delivery') ...[
          const SizedBox(height: 10),
          if (widget.rowBuilder != null)
            widget.rowBuilder!(
                context,
                AddressRowData(
                    address: shown,
                    onTap: _openAddressSheet,
                    distKm: _distanceKm,
                    fee: _deliveryFee))
          else ...[
          GestureDetector(
            onTap: _openAddressSheet,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: const Color(0xFFF1FAF7),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFD4E8E0))),
              child: Row(children: [
                const Icon(Icons.location_on,
                    size: 16, color: Color(0xFF8AAB99)),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(shown ?? tr.tr('clickEnterAddress'),
                        style: TextStyle(
                            fontSize: 12,
                            color: shown != null
                                ? const Color(0xFF0F1A14)
                                : const Color(0xFF8AAB99)))),
                const Icon(Icons.edit,
                    size: 14, color: Color(0xFF8AAB99)),
              ]),
            ),
          ),
          if (_distanceKm != null && _deliveryFee != null)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: MotoGoColors.greenPale,
                        borderRadius: BorderRadius.circular(8)),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.route,
                              size: 14, color: MotoGoColors.greenDarker),
                          const SizedBox(width: 6),
                          Text(
                              '~${_distanceKm!.toStringAsFixed(0)} km · '
                              '${Money.czk(_deliveryFee!)}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: MotoGoColors.greenDarker)),
                        ]))),
          ],
        ],
      ],
    );
  }
}

class _RadioOption extends StatelessWidget {
  final String label, sublabel, price;
  final bool selected;
  final VoidCallback onTap;
  const _RadioOption(
      {required this.label,
      required this.sublabel,
      required this.price,
      required this.selected,
      required this.onTap});

  static const _labelStyle = TextStyle(
      fontSize: 12, fontWeight: FontWeight.w700, color: MotoGoColors.black);
  static const _subStyle = TextStyle(fontSize: 10, color: MotoGoColors.g400);

  /// Šířka [s] stylem [st] (s výchozím písmem a velikostí písma zařízení).
  static double _w(BuildContext context, String s, TextStyle st) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: DefaultTextStyle.of(context).style.merge(st)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    return tp.width;
  }

  /// Nejdelší slovo popisku / podtitulku — sloupec textu nesmí být užší
  /// (jinak se slovo láme uprostřed: „Récupératio|n à votre adresse“).
  double _longestWord(BuildContext context) {
    var m = 0.0;
    for (final (t, st) in [(label, _labelStyle), (sublabel, _subStyle)]) {
      for (final w in t.split(RegExp(r'\s+'))) {
        if (w.isEmpty) continue;
        final ww = _w(context, w, st);
        if (ww > m) m = ww;
      }
    }
    return m;
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: selected ? MotoGoColors.greenPale : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: selected ? MotoGoColors.green : MotoGoColors.g200,
                  width: selected ? 2 : 1)),
          child: LayoutBuilder(builder: (context, c) {
            final priceStyle = TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: selected
                    ? MotoGoColors.greenDarker
                    : MotoGoColors.g400);
            // Cena vpravo jen když text vedle ní nezlomí slovo; jinak pod text.
            final side = !c.hasBoundedWidth ||
                c.maxWidth - 28 - _w(context, price, priceStyle) >= _longestWord(context);
            return Row(children: [
            Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color:
                            selected ? MotoGoColors.green : MotoGoColors.g400,
                        width: 2)),
                child: selected
                    ? Center(
                        child: Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: MotoGoColors.green)))
                    : null),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(label, style: _labelStyle),
                  Text(sublabel, style: _subStyle),
                  if (!side) Text(price, style: priceStyle),
                ])),
            if (side) Text(price, style: priceStyle),
          ]);
          })));
}

class AddressResult {
  final String street, city, zip;
  final double? lat, lng;
  const AddressResult(
      {required this.street,
      required this.city,
      required this.zip,
      this.lat,
      this.lng});
}
