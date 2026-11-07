import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_animated_size.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_icon_tile.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../branches/v2/branch_moto_row_v2.dart';
import '../../catalog/moto_model.dart';

/// Body of the "Motorky na pobočkách" sheet in the v2 look (Profil board):
/// one white card per branch with the type (OBSLUŽNÁ / SAMOOBSLUŽNÁ) as a
/// dark eyebrow, the open chip, address, "Otevřít v mapě", and — expanded
/// (one tap, 300 ms) — the details, navigation, "Zavolat" and the branch's
/// motorcycles as `BranchMotoRowV2`. The data and every action (maps, tel:,
/// bike detail) are the SAME as `BranchDetailCard` / `BranchMotoList`.
class BranchesSheetV2 extends StatelessWidget {
  final List branches;
  final Map<String, List<Map<String, dynamic>>> motosByBranch;
  const BranchesSheetV2({super.key, required this.branches, required this.motosByBranch});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < branches.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 4 : 12),
            child: MgReveal(
              index: i,
              child: _BranchCardV2(
                branch: Map<String, dynamic>.from(branches[i] as Map),
                motos: motosByBranch[branches[i]['id']] ?? const [],
              ),
            ),
          ),
      ]);
}

class _BranchCardV2 extends StatefulWidget {
  final Map<String, dynamic> branch;
  final List<Map<String, dynamic>> motos;
  const _BranchCardV2({required this.branch, required this.motos});

  @override
  State<_BranchCardV2> createState() => _BranchCardV2State();
}

class _BranchCardV2State extends State<_BranchCardV2> {
  bool _open = false;

  Map<String, dynamic> get b => widget.branch;
  bool get _self => ((b['type'] as String?)?.toLowerCase() ?? '').contains('samo');
  double? get _lat => (b['gps_lat'] as num?)?.toDouble();
  double? get _lng => (b['gps_lng'] as num?)?.toDouble();
  String get _address => '${b['address'] ?? ''}, ${b['city'] ?? ''}';

  String _service(AppTranslations tr) {
    final type = b['type'] as String?;
    if (type != null && type.isNotEmpty) return type;
    return _self ? tr.tr('selfService') : tr.tr('servicedBranch');
  }

  /// Same targets as `BranchDetailCard` (maps directions / q / tel:).
  void _openMaps() {
    final hasGps = _lat != null && _lng != null;
    final url = hasGps
        ? 'https://www.google.com/maps/dir/?api=1&destination=$_lat,$_lng'
        : 'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(_address)}';
    launchUrl(Uri.parse(url));
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final open = b['is_open'] == true;
    final phone = b['phone'] as String? ?? '';
    final hasGps = _lat != null && _lng != null;
    final hasAddr = hasGps || _address.trim() != ',';
    final eyebrow = (_self ? tr.tr('v2UxRpSelfBranch') : tr.tr('v2UxRpStaffBranch')).toUpperCase();
    return Container(
      decoration: BoxDecoration(
        color: MgColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MgColors.line),
        boxShadow: MgShadows.card,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(
          button: true,
          expanded: _open,
          child: MgPress(
            scale: 0.99,
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      MgEyebrowDark(eyebrow, icon: _self ? MgIcons.kiosk : MgIcons.person),
                      _OpenChip(open: open, label: tr.tr(open ? 'nonstop' : 'closed')),
                    ]),
                    const SizedBox(height: 8),
                    MgWordFit(
                      minScale: 0.85,
                      child: Text('${b['name'] ?? ''}', style: MgType.section.copyWith(color: MgColors.ink)),
                    ),
                    if (_address.trim() != ',')
                      Text(_address, style: MgType.small.copyWith(color: MgColors.lead)),
                  ]),
                ),
                const SizedBox(width: 8),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: MgMotion.of(context, MgMotion.color),
                  child: const SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(child: MgIcon(MgIcons.chevronDown, size: 22, color: MgColors.link)),
                  ),
                ),
              ]),
            ),
          ),
        ),
        if (hasAddr)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: MgBtnGhostLight(label: tr.tr('openInMaps'), icon: MgIcons.map, height: 44, onTap: _openMaps),
          ),
        MgAnimatedSize(
          duration: MgMotion.sheet,
          curve: MgMotion.out,
          alignment: Alignment.topCenter,
          child: !_open
              ? const SizedBox(width: double.infinity)
              : Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: MgColors.line))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    _row(MgIcons.pin, tr.tr('addressLabel'), _address),
                    if (phone.isNotEmpty) _row(MgIcons.phone, tr.tr('phone'), phone),
                    if (b['branch_code'] != null) _row(MgIcons.tag, tr.tr('branchCodeLabel'), '${b['branch_code']}'),
                    if (hasGps) _row(MgIcons.gps, 'GPS', '${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}'),
                    if (b['type'] != null) _row(MgIcons.map, tr.tr('localityType'), _typeLabel(tr, '${b['type']}')),
                    _row(MgIcons.wrench, tr.tr('operationLabel'), _service(tr)),
                    if (_self) _row(MgIcons.parking, tr.tr('capacityLabel'), tr.tr('max8Motos')),
                    if (hasGps) ...[
                      const SizedBox(height: 8),
                      MgBtnInk(
                        label: tr.tr('navigateToBranch'),
                        icon: MgIcons.navigate,
                        neonLabel: true,
                        onTap: () => launchUrl(Uri.parse('https://maps.google.com/?q=$_lat,$_lng')),
                      ),
                    ],
                    if (phone.isNotEmpty)
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: MgBtnText(
                          label: '${tr.tr('callLabel')} $phone',
                          icon: MgIcons.phone,
                          onTap: () => launchUrl(Uri.parse('tel:$phone')),
                        ),
                      ),
                    if (widget.motos.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text('${tr.tr('branchMotosTitle')} (${widget.motos.length})',
                          style: MgType.title.copyWith(color: MgColors.ink)),
                      const SizedBox(height: 8),
                      for (final m in widget.motos) _moto(context, m),
                    ],
                  ]),
                ),
        ),
      ]),
    );
  }

  Widget _row(String icon, String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          MgIconTileLight(icon, size: 32),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: MgType.meta.copyWith(color: MgColors.meta)),
              Text(value, style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.ink)),
            ]),
          ),
        ]),
      );

  /// Same mapping as `BranchDetailCard._typeLabel`.
  static String _typeLabel(AppTranslations tr, String type) {
    const keys = {
      'turistická': 'usageTouristic',
      'městská': 'usageUrban',
      'horská': 'usageMountain',
      'rekreační voda': 'usageRecWater',
      'metropolitní centrum': 'usageMetro',
      'městská tranzitní': 'usageUrbanTransit',
    };
    final k = keys[type];
    return k != null ? tr.tr(k) : type;
  }

  /// A bike row → closes the sheet and opens the bike (as `BranchMotoList`).
  Widget _moto(BuildContext context, Map<String, dynamic> m) {
    final id = m['id']?.toString();
    if (id == null) return const SizedBox.shrink();
    Motorcycle moto;
    try {
      moto = Motorcycle.fromJson(m);
    } catch (_) {
      return const SizedBox.shrink();
    }
    return BranchMotoRowV2(
      moto: moto,
      onTap: () {
        Navigator.of(context).pop(); // close the bottom sheet
        context.push('/moto/$id');
      },
    );
  }
}

class _OpenChip extends StatelessWidget {
  final bool open;
  final String label;
  const _OpenChip({required this.open, required this.label});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: open ? MgColors.tintOk : MgColors.errBg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: open ? MgColors.tintOkBorder : MgColors.errBorder),
        ),
        child: Text(label,
            style: MgType.micro.copyWith(fontWeight: FontWeight.w800, color: open ? MgColors.onTintOk : MgColors.err)),
      );
}
