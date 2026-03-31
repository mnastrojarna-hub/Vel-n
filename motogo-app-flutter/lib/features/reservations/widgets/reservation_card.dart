import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../reservation_models.dart';

/// Reservation card — mirrors _renderResCard() from reservations-ui.js.
class ReservationCard extends StatelessWidget {
  final Reservation reservation;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onCancel;

  const ReservationCard({
    super.key,
    required this.reservation,
    required this.onTap,
    this.onEdit,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final st = reservation.displayStatus;
    final grayscale = st == ResStatus.dokoncene || st == ResStatus.cancelled;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
          boxShadow: [BoxShadow(color: MotoGoColors.black.withValues(alpha: 0.08), blurRadius: 16)],
        ),
        child: Column(
          children: [
            // Image header
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(MotoGoTheme.radiusLg)),
              child: Stack(
                children: [
                  SizedBox(
                    height: 120,
                    width: double.infinity,
                    child: ColorFiltered(
                      colorFilter: grayscale
                          ? const ColorFilter.mode(Colors.grey, BlendMode.saturation)
                          : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
                      child: CachedNetworkImage(
                        imageUrl: reservation.motoImage ?? '',
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          color: MotoGoColors.g200,
                          child: const Center(child: Text('🏍️', style: TextStyle(fontSize: 32))),
                        ),
                      ),
                    ),
                  ),
                  // Gradient
                  Positioned(
                    bottom: 0, left: 0, right: 0, height: 50,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter, end: Alignment.bottomCenter,
                          colors: [Colors.transparent, MotoGoColors.black.withValues(alpha: 0.8)],
                        ),
                      ),
                    ),
                  ),
                  // Name + ID
                  Positioned(
                    bottom: 8, left: 12,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(reservation.motoName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
                        Text(reservation.shortId, style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.6))),
                      ],
                    ),
                  ),
                  // Status badge
                  Positioned(
                    top: 8, right: 8,
                    child: _StatusBadge(status: st),
                  ),
                  // SOS badge
                  if (reservation.sosReplacement)
                    Positioned(
                      bottom: 8, right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(50)),
                        child: const Text('🏍️ SOS', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFF1A8A18))),
                      ),
                    ),
                  if (reservation.endedBySos)
                    Positioned(
                      bottom: 8, right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(50)),
                        child: const Text('🆘 SOS', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFFB91C1C))),
                      ),
                    ),
                ],
              ),
            ),

            // Info row
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Row(
                children: [
                  _InfoCol(label: 'Datum', value: reservation.dateRange),
                  _InfoCol(label: 'Délka', value: '${reservation.dayCount} ${_dayWord(reservation.dayCount)}'),
                  _InfoCol(label: 'Celkem', value: '${reservation.totalPrice.toStringAsFixed(0)} Kč'),
                ],
              ),
            ),

            // Action buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Row(
                children: _buildActions(st),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildActions(ResStatus st) {
    switch (st) {
      case ResStatus.aktivni:
        return [
          _ActionBtn(label: '📋 Detail', onTap: onTap),
          if (onEdit != null) _ActionBtn(label: '⏱ Prodloužit', onTap: onEdit!, primary: true),
        ];
      case ResStatus.nadchazejici:
        return [
          _ActionBtn(label: '📋 Detail', onTap: onTap),
          if (onEdit != null) _ActionBtn(label: '✏️ Upravit', onTap: onEdit!, primary: true),
        ];
      case ResStatus.dokoncene:
        return [
          _ActionBtn(label: '📋 Detail', onTap: onTap),
          _ActionBtn(label: '⭐ Hodnotit', onTap: onTap),
        ];
      case ResStatus.cancelled:
        return [
          _ActionBtn(label: '📋 Detail', onTap: onTap),
        ];
    }
  }

  String _dayWord(int n) {
    if (n == 1) return 'den';
    if (n < 5) return 'dny';
    return 'dní';
  }
}

class _StatusBadge extends StatelessWidget {
  final ResStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (status) {
      ResStatus.aktivni => ('Aktivní', MotoGoColors.greenPale, MotoGoColors.greenDark),
      ResStatus.nadchazejici => ('Nadcházející', const Color(0xFFFEF3C7), const Color(0xFFD97706)),
      ResStatus.dokoncene => ('Dokončené', MotoGoColors.g100, MotoGoColors.g400),
      ResStatus.cancelled => ('Zrušené', MotoGoColors.g100, MotoGoColors.g400),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(50)),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: fg)),
    );
  }
}

class _InfoCol extends StatelessWidget {
  final String label;
  final String value;
  const _InfoCol({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: MotoGoColors.g400, letterSpacing: 0.3)),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: MotoGoColors.black)),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool primary;
  const _ActionBtn({required this.label, required this.onTap, this.primary = false});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: primary ? MotoGoColors.green : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: primary ? MotoGoColors.green : MotoGoColors.g200),
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700,
                  color: primary ? Colors.white : MotoGoColors.black,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
