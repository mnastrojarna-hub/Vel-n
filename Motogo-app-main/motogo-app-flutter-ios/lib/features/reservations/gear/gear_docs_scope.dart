import '../../documents/docs_gate_provider.dart';
import '../reservation_models.dart';

/// Doklady pro výpůjčku JEN výbavy: stačí doklad totožnosti (OP obě strany
/// nebo pas) + datum narození 18+, ŘP ne (GEAR_RENTAL_APP.md §1, server
/// `_gear_docs_checklist`). Platí, když VŠECHNY zaplacené aktivní /
/// nadcházející rezervace zákazníka jsou výbava — s motorkou dál ŘP.

/// Zaplacené aktivní / nadcházející rezervace existují a všechny jsou výbava.
bool gearOnlyDocsScope(Iterable<Reservation>? list) {
  final paid = (list ?? const <Reservation>[]).where((r) {
    final s = r.displayStatus;
    return (s == ResStatus.aktivni || s == ResStatus.nadchazejici) && r.paymentStatus == 'paid';
  }).toList();
  return paid.isNotEmpty && paid.every((r) => r.isGearOnly);
}

/// Kompletnost dokladů pro plovoucí panel / tečku Rezervace: u zákazníka
/// jen s výpůjčkou výbavy stačí OP / pas. Bez stavu (null) = OK, jako dosud.
bool docsCompleteScoped(DocsScreenStatus? s, Iterable<Reservation>? list) {
  if (s == null) return true;
  return gearOnlyDocsScope(list) ? s.hasIdOrPassport : s.isComplete;
}

/// Stav Moje doklady zúžený na doklad totožnosti (ŘP se nepočítá ani
/// nehlásí jako chybějící; datum narození a 18+ ano).
class GearDocsScreenStatus extends DocsScreenStatus {
  GearDocsScreenStatus(DocsScreenStatus s) : super(s.profile, s.gate == null ? null : gearIdOnlyGate(s.gate!));

  @override
  bool get hasLicense => true;
}

/// Brána dokladů jen pro výbavu: ŘP (strany, platnost, skupina) splněn.
DocsGateChecklist gearIdOnlyGate(DocsGateChecklist g) => DocsGateChecklist(
      ok: g.identityOk && g.hasDob && g.ageOk,
      idFront: g.idFront,
      idBack: g.idBack,
      passport: g.passport,
      dlFront: true,
      dlBack: true,
      identityOk: g.identityOk,
      licenseOk: true,
      hasDob: g.hasDob,
      ageOk: g.ageOk,
      expiryOk: true,
      groupsOk: true,
      licenseExpiry: g.licenseExpiry ?? '-',
    );
