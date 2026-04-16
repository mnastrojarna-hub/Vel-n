import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/supabase_client.dart';
import '../../auth/widgets/toast_helper.dart';
import 'branch_detail_card.dart';

/// Shows a draggable bottom sheet listing all active branches.
/// Each branch is an expandable card with detailed info + motorcycles.
Future<void> showBranchesSheet(BuildContext context) async {
  try {
    // Fetch branches and motorcycles in parallel
    final results = await Future.wait([
      MotoGoSupabase.client
          .from('branches')
          .select('*')
          .eq('active', true)
          .order('name'),
      MotoGoSupabase.client
          .from('motorcycles')
          .select(
              'id, model, brand, category, license_required, image_url, images,'
              ' status, branch_id, power_kw, engine_cc')
          .eq('status', 'active')
          .order('model'),
    ]);
    if (!context.mounted) return;

    final branches = results[0] as List;
    final allMotos = results[1] as List;

    // Group motorcycles by branch_id
    final motosByBranch = <String, List<Map<String, dynamic>>>{};
    for (final m in allMotos) {
      final bid = m['branch_id'] as String?;
      if (bid != null) {
        motosByBranch.putIfAbsent(bid, () => []).add(m);
      }
    }

    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: MotoGoColors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollCtrl) => SafeArea(
          child: Column(children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: MotoGoColors.g300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Title
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(
                'Pobočky MotoGo24',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: MotoGoColors.black,
                ),
              ),
            ),
            // Branch list
            Expanded(
              child: ListView.builder(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                itemCount: branches.length,
                itemBuilder: (_, i) {
                  final b = branches[i];
                  final motos = motosByBranch[b['id']] ?? [];
                  return BranchDetailCard(branch: b, motorcycles: motos);
                },
              ),
            ),
          ]),
        ),
      ),
    );
  } catch (_) {
    if (context.mounted) {
      showMotoGoToast(
        context,
        icon: '✗',
        title: 'Chyba',
        message: 'Nepodařilo se načíst pobočky',
      );
    }
  }
}
