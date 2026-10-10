import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/supabase_client.dart';
import '../auth/auth_provider.dart';
import 'document_provider.dart';

/// Brána dokladů pro vydání přístupových kódů (RPC `get_docs_gate_checklist`,
/// 2026-10-10) — STEJNÉ pravidlo, podle kterého server kódy vydává: OP líc +
/// rub nebo pas, ŘP líc + rub (skutečné fotky v úložišti), datum narození
/// 18+, platný ŘP, skupina ŘP. OCR `*_verified_at` v profilu fotky už
/// NENAHRAZUJE — chybějící stranu dokladu ukáže jen tahle brána.
class DocsGateChecklist {
  final bool ok;
  final bool idFront, idBack, passport, dlFront, dlBack;
  final bool identityOk, licenseOk;
  final bool hasDob, ageOk, expiryOk, groupsOk;
  final String? licenseExpiry;
  final List<String> licenseGroups, requiredGroups;

  const DocsGateChecklist({
    required this.ok,
    required this.idFront, required this.idBack, required this.passport,
    required this.dlFront, required this.dlBack,
    required this.identityOk, required this.licenseOk,
    required this.hasDob, required this.ageOk,
    required this.expiryOk, required this.groupsOk,
    this.licenseExpiry,
    this.licenseGroups = const [], this.requiredGroups = const [],
  });

  factory DocsGateChecklist.fromJson(Map<String, dynamic> j) {
    bool b(String k) => j[k] == true;
    List<String> l(String k) =>
        j[k] is List ? (j[k] as List).map((e) => '$e').toList() : const [];
    // Dětská motorka (jen u dotazu na rezervaci): doklady se nevyžadují.
    final child = b('child');
    return DocsGateChecklist(
      ok: b('ok'),
      idFront: b('id_front'), idBack: b('id_back'), passport: b('passport'),
      dlFront: b('dl_front'), dlBack: b('dl_back'),
      identityOk: child || b('identity_ok'),
      licenseOk: child || b('license_ok'),
      hasDob: child || j['date_of_birth'] != null,
      ageOk: child || b('age_ok'),
      expiryOk: child || b('expiry_ok'),
      groupsOk: child || b('groups_ok'),
      licenseExpiry: child ? null : j['license_expiry']?.toString(),
      licenseGroups: l('license_groups'),
      requiredGroups: l('required_groups'),
    );
  }
}

/// Kontrolní seznam přihlášeného zákazníka (bez parametrů = sám sebe).
/// null = RPC nedostupné / chyba (starší backend, offline) → UI se vrátí
/// k profilovému `docsVerifiedProvider`.
Future<DocsGateChecklist?> fetchDocsGateChecklist() async {
  if (MotoGoSupabase.currentUser == null) return null;
  try {
    final res = await MotoGoSupabase.client.rpc('get_docs_gate_checklist');
    if (res is! Map || res['error'] != null || res['ok'] is! bool) return null;
    return DocsGateChecklist.fromJson(Map<String, dynamic>.from(res));
  } catch (e) {
    debugPrint('[DocsGate] get_docs_gate_checklist failed: $e');
    return null;
  }
}

final docsGateChecklistProvider =
    FutureProvider.autoDispose<DocsGateChecklist?>((ref) => fetchDocsGateChecklist());

/// Stav pro obrazovku Moje doklady — stejné gettery jako [DocsVerification],
/// ale kompletnost OP/pasu a ŘP podle brány (obě strany); bez odpovědi RPC
/// zpět na profilové `*_verified_at`.
class DocsScreenStatus {
  final DocsVerification profile;
  final DocsGateChecklist? gate;
  const DocsScreenStatus(this.profile, this.gate);

  bool get hasIdOrPassport => gate?.identityOk ?? profile.hasIdOrPassport;
  bool get hasLicense => gate?.licenseOk ?? profile.hasLicense;
  bool get isComplete => hasIdOrPassport && hasLicense;

  /// Splněno vše pro vydání kódů (i věk, platnost a skupina ŘP). Jen podle
  /// brány — bez její odpovědi zelený box „kódy k vyzvednutí“ neslibujeme.
  bool get codesReady => gate?.ok ?? false;
}

final docsScreenStatusProvider =
    FutureProvider.autoDispose<DocsScreenStatus>((ref) async {
  final profile = ref.watch(docsVerifiedProvider.future);
  final gate = ref.watch(docsGateChecklistProvider.future);
  return DocsScreenStatus(await profile, await gate);
});

/// Totéž pro proaktivní FAB „doklady nejsou ověřeny“ v AppShell — vlastní
/// cache, aby trvale sledovaný FAB nedržel naživu [docsGateChecklistProvider]
/// (Moje doklady si bránu načtou čerstvě při každém otevření). Znovu po
/// přihlášení / odhlášení a po nahrání dokladů (invalidace docsVerified).
final docsFabStatusProvider =
    FutureProvider.autoDispose<DocsScreenStatus>((ref) async {
  ref.watch(authStateProvider.select((s) => s.valueOrNull?.user.id));
  final profile = await ref.watch(docsVerifiedProvider.future);
  return DocsScreenStatus(profile, await fetchDocsGateChecklist());
});

/// Co chybí pro vydání kódů — lokalizované krátké položky za „Chybí:“
/// (ekvivalenty serverových `missing`). [docsOnly] = jen strany dokladů.
List<String> docsGateMissingLabels(BuildContext context, DocsGateChecklist g,
    {bool docsOnly = false}) {
  final tr = t(context).tr;
  final out = <String>[];
  if (!g.identityOk) {
    out.add(!g.idFront && !g.idBack
        ? tr('gmIdOrPassport')
        : (!g.idBack ? tr('gmIdBack') : tr('gmIdFront')));
  }
  if (!g.licenseOk) {
    out.add(!g.dlFront && !g.dlBack
        ? tr('gmDl')
        : (!g.dlBack ? tr('gmDlBack') : tr('gmDlFront')));
  }
  if (docsOnly) return out;
  if (!g.hasDob) {
    out.add(tr('gmDob'));
  } else if (!g.ageOk) {
    out.add(tr('gmAge18'));
  }
  if (g.licenseExpiry == null) {
    out.add(tr('gmDlExpiry'));
  } else if (!g.expiryOk) {
    out.add(tr('gmDlExpired').replaceAll('{date}', _fmtDate(g.licenseExpiry!)));
  }
  if (!g.groupsOk) {
    out.add(g.licenseGroups.isEmpty || g.requiredGroups.isEmpty
        ? tr('gmGroup')
        : tr('gmGroupLow').replaceAll('{groups}', g.requiredGroups.join('/')));
  }
  return out;
}

String _fmtDate(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  String p(int n) => n.toString().padLeft(2, '0');
  return '${p(d.day)}.${p(d.month)}.${d.year}';
}
