import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme.dart';
import '../../../core/i18n/i18n_provider.dart';
import 'branch_moto_list.dart';

/// Expandable card showing full branch details + motorcycle list.
class BranchDetailCard extends StatefulWidget {
  final Map<String, dynamic> branch;
  final List<Map<String, dynamic>> motorcycles;

  const BranchDetailCard({
    required this.branch,
    required this.motorcycles,
    super.key,
  });

  @override
  State<BranchDetailCard> createState() => _BranchDetailCardState();
}

class _BranchDetailCardState extends State<BranchDetailCard> {
  bool _expanded = false;

  Map<String, dynamic> get b => widget.branch;
  bool get isOpen => b['is_open'] == true;
  bool get isSelfService {
    final type = (b['type'] as String?)?.toLowerCase() ?? '';
    return type.contains('samo');
  }
  String serviceLabelFor(BuildContext context) {
    final type = b['type'] as String?;
    if (type != null && type.isNotEmpty) return type;
    return isSelfService ? t(context).tr('selfService') : 'Obslužná';
  }
  double? get lat => (b['gps_lat'] as num?)?.toDouble();
  double? get lng => (b['gps_lng'] as num?)?.toDouble();

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(MotoGoRadius.card),
        boxShadow: MotoGoShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          _buildNavButton(),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: _buildExpandedContent(),
            crossFadeState:
                _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 250),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isSelfService
                  ? MotoGoColors.green.withValues(alpha: 0.15)
                  : MotoGoColors.dark.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Icon(
                isSelfService ? Icons.smart_toy_outlined : Icons.support_agent,
                size: 22,
                color: isSelfService ? MotoGoColors.greenDark : MotoGoColors.dark,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  b['name'] ?? '',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: MotoGoColors.black,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${b['address'] ?? ''}, ${b['city'] ?? ''} · ${serviceLabelFor(context)}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: MotoGoColors.g400,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isOpen ? const Color(0xFFDCFCE7) : MotoGoColors.redBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              isOpen ? t(context).tr('nonstop') : t(context).tr('closed'),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: isOpen ? const Color(0xFF16A34A) : const Color(0xFFB91C1C),
              ),
            ),
          ),
          const SizedBox(width: 6),
          AnimatedRotation(
            turns: _expanded ? 0.5 : 0,
            duration: const Duration(milliseconds: 200),
            child: const Icon(
              Icons.keyboard_arrow_down,
              color: MotoGoColors.g400,
              size: 22,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildNavButton() {
    final hasGps = lat != null && lng != null;
    final address = '${b['address'] ?? ''}, ${b['city'] ?? ''}';
    if (!hasGps && address.trim() == ',') return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: SizedBox(
        width: double.infinity,
        height: 40,
        child: ElevatedButton.icon(
          onPressed: () {
            final url = hasGps
                ? 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng'
                : 'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(address)}';
            launchUrl(Uri.parse(url));
          },
          icon: const Icon(Icons.map_outlined, size: 16),
          label: const Text(
            'Otevřít v mapách',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: MotoGoColors.greenPale,
            foregroundColor: MotoGoColors.greenDark,
            elevation: 0,
            side: const BorderSide(color: MotoGoColors.green),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(MotoGoRadius.pill),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1, color: MotoGoColors.g200),
        _buildDetails(),
        if (widget.motorcycles.isNotEmpty) ...[
          const Divider(
            height: 1,
            indent: 14,
            endIndent: 14,
            color: MotoGoColors.g200,
          ),
          BranchMotoList(
            motorcycles: widget.motorcycles,
            isSelfService: isSelfService,
          ),
        ],
      ],
    );
  }

  Widget _buildDetails() {
    final phone = b['phone'] as String? ?? '';
    final hasPhone = phone.isNotEmpty;
    final hasGps = lat != null && lng != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row(Icons.location_on, 'Adresa',
              '${b['address'] ?? ''}, ${b['city'] ?? ''}'),
          if (hasPhone) _row(Icons.phone, 'Telefon', phone),
          if (b['branch_code'] != null)
            _row(Icons.qr_code, 'Kód pobočky', '${b['branch_code']}'),
          if (b['type'] != null)
            _row(Icons.terrain, 'Typ lokality', _typeLabel(b['type'])),
          if (hasGps)
            _row(Icons.my_location, 'GPS',
                '${lat!.toStringAsFixed(5)}, ${lng!.toStringAsFixed(5)}'),
          _row(Icons.build_outlined, 'Provoz', serviceLabelFor(context)),
          if (isSelfService)
            _row(Icons.inventory_2_outlined, 'Kapacita', 'Max 8 motorek'),
          const SizedBox(height: 12),
          if (hasGps)
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                onPressed: () =>
                    launchUrl(Uri.parse('https://maps.google.com/?q=$lat,$lng')),
                icon: const Icon(Icons.navigation_rounded, size: 18),
                label: const Text(
                  'Navigovat na pobočku',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: MotoGoColors.green,
                  foregroundColor: MotoGoColors.dark,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(MotoGoRadius.pill),
                  ),
                ),
              ),
            ),
          if (hasPhone) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 40,
              child: OutlinedButton.icon(
                onPressed: () => launchUrl(Uri.parse('tel:$phone')),
                icon: const Icon(Icons.phone, size: 16),
                label: Text(
                  'Zavolat $phone',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: MotoGoColors.greenDark,
                  side: const BorderSide(color: MotoGoColors.g200),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(MotoGoRadius.pill),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: MotoGoColors.g400),
          const SizedBox(width: 8),
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: MotoGoColors.g400,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: MotoGoColors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(
        text,
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }

  static String _typeLabel(String type) {
    const labels = {
      'turistická': 'Turistická',
      'městská': 'Městská',
      'horská': 'Horská',
      'rekreační voda': 'Rekreační voda',
      'metropolitní centrum': 'Metropolitní centrum',
      'městská tranzitní': 'Městská tranzitní',
    };
    return labels[type] ?? type;
  }
}
