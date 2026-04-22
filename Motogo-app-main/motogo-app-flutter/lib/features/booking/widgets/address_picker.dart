import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../booking_ui_helpers.dart' show showAddrBottomSheet;
import '../map_launcher.dart' show launchMapPicker;

/// Address picker with geocoding.
/// Delegates address entry to [showAddrBottomSheet] — the same modal used in
/// the new-booking flow. Inline autocomplete used to collide with the keyboard
/// in the reservation-edit ListView (field scrolled to top, rest empty).
class AddressPickerWidget extends StatefulWidget {
  final String label;
  final String method;
  final ValueChanged<String> onMethodChanged;
  final ValueChanged<AddressResult> onAddressChanged;
  final ValueChanged<double> onDeliveryFeeChanged;

  const AddressPickerWidget({
    super.key,
    required this.label,
    required this.method,
    required this.onMethodChanged,
    required this.onAddressChanged,
    required this.onDeliveryFeeChanged,
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

  @override
  void didUpdateWidget(AddressPickerWidget old) {
    super.didUpdateWidget(old);
    if (old.method == 'delivery' && widget.method != 'delivery') {
      _street = '';
      _city = '';
      _zip = '';
      _lat = null;
      _lng = null;
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

  void _openAddressSheet() {
    showAddrBottomSheet(
      context,
      widget.label == 'Vyzvednutí'
          ? 'Přistavení na vaši adresu'
          : 'Odvoz z vaší adresy',
      _city,
      _street,
      (city, addr) {
        setState(() {
          _city = city;
          _street = addr;
        });
        widget.onAddressChanged(AddressResult(
            street: _street,
            city: _city,
            zip: _zip,
            lat: _lat,
            lng: _lng));
      },
      onDistCalc: (km, fee) {
        if (!mounted) return;
        setState(() {
          _distanceKm = km;
          _deliveryFee = fee;
        });
        widget.onDeliveryFeeChanged(fee);
      },
      onMapTap: (ctx) async {
        final r = await launchMapPicker(ctx);
        if (r == null || !mounted) return;
        setState(() {
          _city = r.city;
          _street = r.address;
          _distanceKm = r.km;
          _deliveryFee = r.fee;
        });
        widget.onAddressChanged(AddressResult(
            street: _street,
            city: _city,
            zip: _zip,
            lat: _lat,
            lng: _lng));
        widget.onDeliveryFeeChanged(r.fee);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RadioOption(
          label: 'Na pobočce',
          sublabel: 'Mezná 9, Mezná',
          price: 'Zdarma',
          selected: widget.method == 'store',
          onTap: () => widget.onMethodChanged('store'),
        ),
        const SizedBox(height: 6),
        _RadioOption(
          label: widget.label == 'Vyzvednutí'
              ? 'Přistavení na vaši adresu'
              : 'Odvoz z vaší adresy',
          sublabel: '1 000 Kč + 40 Kč/km',
          price: 'od 1 000 Kč',
          selected: widget.method == 'delivery',
          onTap: () => widget.onMethodChanged('delivery'),
        ),
        if (widget.method == 'delivery') ...[
          const SizedBox(height: 10),
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
                    child: Text(
                        _city.isNotEmpty
                            ? '${_street.isNotEmpty ? '$_street, ' : ''}$_city'
                            : 'Klikněte pro zadání adresy',
                        style: TextStyle(
                            fontSize: 12,
                            color: _city.isNotEmpty
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
                              '${_deliveryFee!.toStringAsFixed(0)} Kč',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: MotoGoColors.greenDarker)),
                        ]))),
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
          child: Row(children: [
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
                  Text(label,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: MotoGoColors.black)),
                  Text(sublabel,
                      style: const TextStyle(
                          fontSize: 10, color: MotoGoColors.g400)),
                ])),
            Text(price,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? MotoGoColors.greenDarker
                        : MotoGoColors.g400)),
          ])));
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
