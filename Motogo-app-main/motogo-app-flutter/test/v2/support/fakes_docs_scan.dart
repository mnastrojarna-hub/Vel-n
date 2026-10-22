// Stav dokladů pro testy plánu skenu / Mých dokladů (strany z brány).
import 'package:motogo_app/features/documents/docs_gate_provider.dart';
import 'package:motogo_app/features/documents/document_provider.dart';

DocsGateChecklist gate({bool idF = false, bool idB = false, bool pp = false, bool dlF = false, bool dlB = false}) =>
    DocsGateChecklist(
      ok: false, idFront: idF, idBack: idB, passport: pp, dlFront: dlF, dlBack: dlB,
      identityOk: pp || (idF && idB), licenseOk: dlF && dlB,
      hasDob: true, ageOk: true, expiryOk: true, groupsOk: true,
    );

DocsScreenStatus st(DocsGateChecklist? g, {bool id = false, bool dl = false}) => DocsScreenStatus(
    DocsVerification(idVerifiedAt: id ? DateTime(2026) : null, licenseVerifiedAt: dl ? DateTime(2026) : null), g);
