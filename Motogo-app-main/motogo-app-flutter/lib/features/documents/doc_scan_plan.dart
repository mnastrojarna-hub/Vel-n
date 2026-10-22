import 'docs_gate_provider.dart';

/// Režimy skeneru dokladů (`/docs/scan?mode=`):
/// - null / 'all' — celý tok (volba OP / pas / jen ŘP + všechny strany), beze změny
/// - 'dl_only'    — obě strany ŘP, beze změny (starý vzhled)
/// - 'missing'    — jen strany, které brána dokladů ještě nemá (OP/pas i ŘP)
/// - 'missing_id' — jen chybějící strany OP / pasu
/// - 'missing_dl' — jen chybějící strany ŘP
/// Zákazník tak nikdy znovu nefotí stranu, kterou už nahrál (2026-10-22).
const kDocScanMissingModes = {'missing', 'missing_id', 'missing_dl'};

bool isDocScanMissingMode(String? mode) => kDocScanMissingModes.contains(mode);

const _kIdKeys = {'id_front', 'id_back', 'passport_front', 'passport_back'};
const _kDlKeys = {'dl_front', 'dl_back'};

/// Co skener nafotí: [idType] přeskočí volbu dokladu ('op' / 'dl_only'),
/// [only] = povolené kroky (null = všechny kroky zvoleného typu),
/// [offerDlOnly] = na volbě dokladu nabídnout „Jen řidičák“.
class DocScanPlan {
  final String? idType;
  final Set<String>? only;
  final bool offerDlOnly;
  const DocScanPlan({this.idType, this.only, this.offerDlOnly = true});

  /// Celý tok jako dosud.
  static const full = DocScanPlan();
}

/// Plán pro režim „doplnit chybějící“ podle [status] (strany z brány
/// `get_docs_gate_checklist`; bez její odpovědi celé doklady z profilu).
/// [status] null (stav nejde zjistit) → bezpečná záloha: celý doklad.
DocScanPlan resolveDocScanPlan(String? mode, DocsScreenStatus? status) {
  if (!isDocScanMissingMode(mode)) return DocScanPlan.full;
  final g = status?.gate;

  // OP / pas: ověřený → nic; z OP chybí jen jedna strana → jen ta (bez
  // volby dokladu); jinak volba OP / pas a obě strany.
  var askId = false;
  final id = <String>{};
  if (status == null || !status.hasIdOrPassport) {
    if (g != null && g.idFront != g.idBack) {
      id.add(g.idFront ? 'id_back' : 'id_front');
    } else {
      askId = true;
      id.addAll(_kIdKeys);
    }
  }

  // ŘP: jen chybějící strana, jinak obě.
  final dl = <String>{};
  if (status == null || !status.hasLicense) {
    if (g != null && g.dlFront != g.dlBack) {
      dl.add(g.dlFront ? 'dl_back' : 'dl_front');
    } else {
      dl.addAll(_kDlKeys);
    }
  }

  DocScanPlan idPlan(Set<String> extra) => askId
      ? DocScanPlan(only: {...id, ...extra}, offerDlOnly: extra.isNotEmpty)
      : DocScanPlan(idType: 'op', only: {...id, ...extra});

  switch (mode) {
    case 'missing_id':
      // OP už je kompletní (tlačítko se pak neukazuje) → volba dokladu znovu.
      return id.isEmpty ? const DocScanPlan(only: _kIdKeys, offerDlOnly: false) : idPlan(const {});
    case 'missing_dl':
      return DocScanPlan(idType: 'dl_only', only: dl.isEmpty ? null : dl);
    default:
      if (id.isEmpty && dl.isEmpty) return DocScanPlan.full;
      if (id.isEmpty) return DocScanPlan(idType: 'dl_only', only: dl);
      return idPlan(dl);
  }
}

/// Zákazník zatím nenahrál vůbec nic (žádná strana dokladu) — hlavní
/// výzva v Mých dokladech pak zní „naskenovat doklady“, ne „doplnit“.
bool docsNothingUploaded(DocsScreenStatus v) {
  final g = v.gate;
  if (g == null) return !v.hasIdOrPassport && !v.hasLicense;
  return !g.idFront && !g.idBack && !g.passport && !g.dlFront && !g.dlBack;
}
