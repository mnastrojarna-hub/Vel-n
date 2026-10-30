import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/friendly_error.dart';
import '../../core/widgets/error_feedback.dart' show openFixSettings;
import '../auth/widgets/toast_helper.dart';
import 'document_camera_screen.dart';
import 'document_models.dart';
import 'document_provider.dart';
import 'docs_gate_provider.dart';
import 'doc_scan_plan.dart';
import '../auth/auth_provider.dart';
import '../../core/widgets/mg_nav_controls.dart';

// Kontakt z CLAUDE.md — firma Bc. Petra Semorádová.
const String _kSupportPhone = '+420 774 256 271';
const String _kSupportEmail = 'info@motogo24.cz';

// Počet povolených neúspěšných pokusů na jedné straně dokladu.
const int _kMaxAttemptsPerStep = 3;

/// Document scanner — 4-step flow matching Capacitor scanner-ui.js.
/// Camera stays open during all 4 captures (ID front+back, DL front+back).
/// After each scan shows a visible result overlay (success/error).
///
/// [scanMode] controls which documents to scan:
/// - null / 'all' → full flow (ID choice + DL)
/// - 'dl_only'   → only driver's license (dl_front + dl_back)
/// - 'missing' / 'missing_id' / 'missing_dl' → only the sides the docs gate
///   still lacks (nothing already uploaded is photographed again) — see
///   [resolveDocScanPlan]
class DocumentScannerScreen extends ConsumerStatefulWidget {
  final String? scanMode;
  const DocumentScannerScreen({super.key, this.scanMode});
  @override
  ConsumerState<DocumentScannerScreen> createState() => _ScannerState();
}

enum _ResultKind { none, success, error, contactFallback }

class _ScannerState extends ConsumerState<DocumentScannerScreen>
    with WidgetsBindingObserver {
  String? _idType;
  int _stepIdx = 0;
  bool _scanning = false;
  bool _isCapturing = false;
  final Map<String, bool> _completed = {};
  // Počet nezdařených pokusů na daný krok (step.key).
  // Resetuje se při úspěchu daného kroku.
  final Map<String, int> _attempts = {};

  // Režim „doplnit chybějící“ (missing*): plán se načítá ze stavu dokladů;
  // [_only] = jen tyto kroky, [_offerDlOnly] = volba „Jen řidičák“.
  bool _planLoading = false;
  Set<String>? _only;
  bool _offerDlOnly = true;

  // Camera — initialized once, reused for all 4 steps
  CameraController? _cam;
  bool _camReady = false;
  String? _camError;
  FriendlyError? _camFe;
  String? _progressText;

  // Scan result overlay — shown after each scan
  _ResultKind _resultKind = _ResultKind.none;
  String _resultTitle = '';
  String _resultMsg = '';
  String _resultGuidance = '';
  int _resultAttempt = 0;

  List<_ScanStep> get _sequence {
    final all = _stepsFor(_idType);
    final only = _only;
    if (only == null) return all;
    final some = all.where((s) => only.contains(s.key)).toList();
    return some.isEmpty ? all : some;
  }

  List<_ScanStep> _stepsFor(String? idType) {
    final front = t(context).tr('frontSide');
    final back = t(context).tr('backSide');
    final dl = t(context).tr('driversLicense');
    if (idType == 'dl_only') {
      return [
        _ScanStep(ScanDocType.driversLicense, '🏍️', dl, front, 'dl_front'),
        _ScanStep(ScanDocType.driversLicense, '🏍️', dl, back, 'dl_back'),
      ];
    }
    if (idType == 'passport') {
      final pp = t(context).tr('passport');
      return [
        // Pas = vlastní typ (`documents.type` 'passport', Mindee model pasu);
        // pro bránu kódů stačí jedna datová strana.
        _ScanStep(ScanDocType.passport, '📕', pp, front, 'passport_front'),
        _ScanStep(ScanDocType.passport, '📕', pp, back, 'passport_back'),
        _ScanStep(ScanDocType.driversLicense, '🏍️', dl, front, 'dl_front'),
        _ScanStep(ScanDocType.driversLicense, '🏍️', dl, back, 'dl_back'),
      ];
    }
    final id = t(context).tr('idCard');
    return [
      _ScanStep(ScanDocType.idCard, '🪪', id, front, 'id_front'),
      _ScanStep(ScanDocType.idCard, '🪪', id, back, 'id_back'),
      _ScanStep(ScanDocType.driversLicense, '🏍️', dl, front, 'dl_front'),
      _ScanStep(ScanDocType.driversLicense, '🏍️', dl, back, 'dl_back'),
    ];
  }

  // ── Camera ──

  /// Bezpečný dispose kamery. CameraX hodí PlatformException
  /// „releaseFlutterSurfaceTexture() … has not yet been initialized", když
  /// dispose přijde dřív, než se stihl inicializovat preview surface (rychlé
  /// inactive/resumed během initu). Controller je stejně zahozený a resume
  /// vytvoří nový — chybu jen zalogujeme, appka nesmí spadnout.
  static Future<void> _safeDisposeCam(CameraController? cam) async {
    if (cam == null) return;
    try {
      await cam.dispose();
    } catch (e) {
      debugPrint('[DocScan] camera dispose ignored: $e');
    }
  }

  Future<void> _initCamera() async {
    CameraController? cam;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _camError = t(context).tr('cameraNotAvailable');
            _camFe = null;
          });
        }
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      cam = CameraController(back, ResolutionPreset.high,
          enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
      _cam = cam;
      await cam.initialize();
      if (!mounted || _cam != cam) {
        // Mezitím zavřeno (pauza appky / odchod ze skeneru) → uklidit.
        if (_cam != cam) await _safeDisposeCam(cam);
        return;
      }
      setState(() => _camReady = true);
    } catch (e) {
      // Dispose během initu (pauza appky) není chyba — resume kameru nahodí.
      if (!mounted || (cam != null && _cam != cam)) return;
      // Bez syrové výjimky („CameraException(CameraAccessDenied…)"): proč +
      // Otevřít nastavení / Zkusit znovu / Zpět (galerie je v Mých dokladech).
      FriendlyError.log('doc_scan_camera_init', e);
      final fe = FriendlyError.of(e, perm: DevicePerm.camera);
      setState(() {
        _camFe = fe;
        _camError = fe.kind == FriendlyKind.permission
            ? t(context).tr('errCameraPermission')
            : t(context).tr('errCameraGeneric');
      });
    }
  }

  /// Když appka jde na pozadí, OS uvolní kameru → controller se znevalidní a
  /// `CameraPreview` (interní ValueListenableBuilder) by se překreslil nad už
  /// disposnutým controllerem → pád „buildPreview() was called on a disposed
  /// CameraController". Kameru proto při pauze zavřeme (preview se schová PŘED
  /// dispose) a po návratu do popředí ji znovu nahodíme.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (_cam != null) _disposeCamera();
    } else if (state == AppLifecycleState.resumed) {
      if (_idType != null && _cam == null && _camError == null) _initCamera();
    }
  }

  void _selectIdType(String type) {
    setState(() => _idType = type);
    _initCamera();
  }

  Future<void> _disposeCamera() async {
    // Nejdřív schovat preview (setState + zahodit referenci), TEPRVE PAK
    // dispose — jinak se CameraPreview během await překreslí nad už
    // disposnutým controllerem a appka spadne.
    final cam = _cam;
    _cam = null;
    _camReady = false;
    if (mounted) setState(() {});
    await _safeDisposeCam(cam);
  }

  /// Zpět ze skeneru i bez zásobníku (deep link / context.go) — jinak by
  /// šipka nedělala nic a uživatel by ve skeneru uvízl.
  void _safePop() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.docs);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _safeDisposeCam(_cam);
    _cam = null;
    super.dispose();
  }

  // ── Capture + scan ──

  Future<void> _capture() async {
    if (_isCapturing || _scanning || _cam == null ||
        !_cam!.value.isInitialized) return;

    setState(() => _isCapturing = true);
    try {
      final photo = await _cam!.takePicture();
      if (!mounted) return;
      setState(() { _isCapturing = false; _scanning = true; });

      final step = _sequence[_stepIdx];
      debugPrint('[DocScan] Step ${_stepIdx + 1}/${_sequence.length}: '
          '${step.key} (${step.docType.apiType})');

      // Nejdřív OCR, pak nahrání fotky s odpovídajícím mindee_status.
      final scanResult = await scanDocumentWithRetry(photo, step.docType,
          onAttempt: (a, max) {
        if (mounted) {
          setState(() => _progressText = a > 1
              ? t(context).trArgs('eoScanAttempt', {'n': a, 'max': max})
              : null);
        }
      });
      if (mounted) setState(() => _progressText = t(context).tr('eoScanSaving'));
      final ocrDataOk = scanResult.ok
          && scanResult.data != null
          && _hasRequiredFieldsForStep(scanResult.data!, step);
      final uploadResult = await uploadDocPhoto(
        photo,
        step.docType,
        mindeeOk: scanResult.ok && scanResult.data != null,
        docSide: step.key.endsWith('_front')
            ? 'front'
            : step.key.endsWith('_back')
                ? 'back'
                : null,
      );

      if (!mounted) return;
      setState(() {
        _scanning = false;
        _progressText = null;
      });

      final uploadOk = uploadResult.ok;

      // Pravidlo (b3): když je fotka uložená, krok NIKDY neselže — pro kódy
      // rozhoduje fotka dané strany (+ platné údaje v profilu), ne OCR. OCR
      // data jen navíc doplní profil (číslo/platnost/jméno/…); jejich
      // absence není chyba.
      if (uploadOk) {
        String message;
        if (ocrDataOk) {
          // Uložení do profilu (může selhat částečně — nekrashujeme flow)
          final saveWarning = await saveOcrToProfile(
              scanResult.data!, docType: step.docType, stepKey: step.key);
          if (!mounted) return;
          final summary = _buildFieldsSummary(scanResult.data!, step.docType);
          // saveWarning = specifická zpráva (neshoda čísla ŘP) nebo chyba DB.
          message = saveWarning != null ? '$summary\n\n⚠️ $saveWarning' : summary;
        } else {
          // Fotka uložená, ale OCR nepřečetlo pole → pořád úspěch.
          message = t(context).tr('docPhotoSavedNoOcr');
        }
        setState(() {
          _completed[step.key] = true;
          _attempts.remove(step.key); // reset — krok dokončen
          _resultKind = _ResultKind.success;
          _resultTitle = '${step.title} – ${step.side}';
          _resultMsg = message;
          _resultGuidance = '';
          _resultAttempt = 0;
        });
      } else {
        // Selhalo i nahrání fotky (vzácné) — zvýš counter pokusu a rozhodni:
        final attempt = (_attempts[step.key] ?? 0) + 1;
        _attempts[step.key] = attempt;

        final reason = _buildFailureReason(
          scanResult: scanResult,
          uploadResult: uploadResult,
          step: step,
          ocrOk: ocrDataOk,
          uploadOk: uploadOk,
        );
        final guidance = _guidanceForStep(step);

        setState(() {
          _resultTitle = '${step.title} – ${step.side}';
          _resultAttempt = attempt;
          if (attempt >= _kMaxAttemptsPerStep) {
            _resultKind = _ResultKind.contactFallback;
            _resultMsg = reason;
            _resultGuidance = guidance;
          } else {
            _resultKind = _ResultKind.error;
            _resultMsg = reason;
            _resultGuidance = guidance;
          }
        });
      }
    } catch (e) {
      debugPrint('[DocScan] Capture error: $e');
      if (!mounted) return;
      final step = _sequence[_stepIdx];
      final errStr = e.toString().toLowerCase();
      FriendlyError.log('doc_scan_capture', e);
      String msg;
      if (errStr.contains('permission') || errStr.contains('denied')) {
        msg = t(context).tr('errCameraPermission');
      } else if (errStr.contains('camera')) {
        msg = t(context).tr('errCameraGeneric');
      } else {
        // Důvod + rada, nikdy syrová výjimka.
        msg = FriendlyError.of(e).compose(t(context), t(context).tr('eoScanStepFail'));
      }
      final attempt = (_attempts[step.key] ?? 0) + 1;
      _attempts[step.key] = attempt;
      setState(() {
        _isCapturing = false;
        _scanning = false;
        _progressText = null;
        _resultTitle = '${step.title} – ${step.side}';
        _resultMsg = msg;
        _resultGuidance = _guidanceForStep(step);
        _resultAttempt = attempt;
        _resultKind = attempt >= _kMaxAttemptsPerStep
            ? _ResultKind.contactFallback
            : _ResultKind.error;
      });
    }
  }

  /// Sestaví konkrétní text důvodu selhání — rozlišuje upload, OCR
  /// a chybějící povinná pole, aby uživatel věděl proč zopakovat.
  String _buildFailureReason({
    required ScanResult scanResult,
    required DocUploadResult uploadResult,
    required _ScanStep step,
    required bool ocrOk,
    required bool uploadOk,
  }) {
    // Diagnostika jen do logu (Velín), zákazník ji nevidí.
    FriendlyError.log('doc_scan_failed',
        '${step.docType.apiType} | ocr=${scanResult.errorCode} http=${scanResult.httpStatus} '
        '#${scanResult.attempts} | upload=${uploadResult.errorDetail} | ${scanResult.errorDetail}');
    // Síť / limit má přednost — dřív se offline hlásilo „záznam se nepodařilo
    // uložit na server" místo „nejsi připojený".
    final upFe = FriendlyError.of(uploadResult.cause);
    if (scanResult.errorCode == 'network' ||
        (uploadResult.cause != null && upFe.kind == FriendlyKind.offline)) {
      return t(context).tr('errNetwork');
    }
    if (scanResult.errorCode == 'timeout' ||
        (uploadResult.cause != null && upFe.kind == FriendlyKind.timeout)) {
      return t(context).tr('errTimeout');
    }
    // DB zápis selhal — příčina je technická, ne fotografická.
    if (!uploadOk) {
      return t(context).tr('scanSaveFailed');
    }

    // OCR selhal technicky (server/timeout/network)
    if (!scanResult.ok) {
      return _buildErrorMsg(scanResult, step);
    }

    // OCR prošel ale pole nejsou — to je typicky kvalita fotky.
    return _missingFieldsReason(step);
  }

  /// Specifická výzva čeho dosáhnout pro úspěšný scan dané strany.
  String _guidanceForStep(_ScanStep step) {
    final key = switch (step.key) {
      'id_front' => 'scanGuideIdFront',
      'id_back' => 'scanGuideIdBack',
      'passport_front' => 'scanGuidePassportFront',
      'passport_back' => 'scanGuidePassportBack',
      'dl_front' => 'scanGuideDlFront',
      'dl_back' => 'scanGuideDlBack',
      _ => 'scanGuideDefault',
    };
    return t(context).tr(key);
  }

  /// Lidsky srozumitelný důvod proč OCR nenašel potřebná pole.
  String _missingFieldsReason(_ScanStep step) {
    final isBack = step.key.endsWith('_back');
    if (step.docType == ScanDocType.driversLicense) {
      return t(context).tr(isBack ? 'scanMissingDlBack' : 'scanMissingDlFront');
    }
    return t(context).tr(isBack ? 'scanMissingBack' : 'scanMissingFront');
  }

  /// Build user-friendly error message with diagnostics.
  String _buildErrorMsg(ScanResult scanResult, _ScanStep step) {
    final code = scanResult.errorCode ?? 'unknown';
    final detail = scanResult.errorDetail;
    final http = scanResult.httpStatus;
    final att = scanResult.attempts;

    // Diagnostika jen do logu (Velín) — zákazníkovi ji neukazujeme.
    debugPrint('[DocScan] diag: ${step.docType.apiType} | $code'
        '${http != null ? ' | HTTP $http' : ''}${att > 1 ? ' | #$att' : ''} | $detail');

    switch (code) {
      case 'network':
        return t(context).tr('errNetwork');

      case 'timeout':
        return t(context).tr('errTimeout');

      case 'server_config':
        // Edge function config error (e.g. missing MINDEE model ID)
        return t(context).tr('errServerConfig');

      case 'server_upstream':
        // Edge function couldn't reach Mindee API
        return t(context).tr('errServerUpstream');

      case 'server_error':
      case 'bad_request':
        return t(context).tr('errServerGeneric');

      case 'ocr_failed':
        return '${t(context).tr('errOcrFailed')}\n\n'
            '${t(context).tr('errOcrHint')}';

      case 'ocr_empty':
        return t(context).tr('errOcrEmpty');

      case 'no_fields':
        return '${t(context).tr('errNoFields')}\n\n'
            '${t(context).tr('errNoFieldsHint')}';

      case 'image_error':
        return t(context).tr('errImagePrep');

      default:
        if (scanResult.ok) {
          return '${t(context).tr('errNoFields')}\n\n'
              '${t(context).tr('errNoFieldsHint')}';
        }
        return t(context).tr('errUnknown');
    }
  }

  /// Build human-readable summary of fields extracted from scan.
  String _buildFieldsSummary(OcrResult r, ScanDocType docType) {
    final lines = <String>[];

    if (docType == ScanDocType.driversLicense) {
      // ŘP fields
      if (_notEmpty(r.licenseNumber)) {
        lines.add('${t(context).tr('fieldLicenseNum')}: ${r.licenseNumber}');
      } else if (_notEmpty(r.idNumber)) {
        lines.add('${t(context).tr('fieldLicenseNum')}: ${r.idNumber}');
      }
      if (_notEmpty(r.licenseCategory)) {
        lines.add('${t(context).tr('fieldCategory')}: ${r.licenseCategory}');
      }
      if (_notEmpty(r.expiryDate)) {
        lines.add('${t(context).tr('fieldExpiry')}: ${r.expiryDate}');
      }
      if (_notEmpty(r.firstName) || _notEmpty(r.lastName)) {
        lines.add('${t(context).tr('fieldName')}: ${r.fullName}');
      }
      if (_notEmpty(r.dob)) {
        lines.add('${t(context).tr('fieldDob')}: ${r.dob}');
      }
    } else {
      // OP / passport fields
      if (_notEmpty(r.firstName) || _notEmpty(r.lastName)) {
        lines.add('${t(context).tr('fieldName')}: ${r.fullName}');
      }
      if (_notEmpty(r.idNumber)) {
        lines.add('${t(context).tr('fieldIdNum')}: ${r.idNumber}');
      }
      if (_notEmpty(r.dob)) {
        lines.add('${t(context).tr('fieldDob')}: ${r.dob}');
      }
      if (_notEmpty(r.expiryDate)) {
        lines.add('${t(context).tr('fieldExpiry')}: ${r.expiryDate}');
      }
    }

    if (lines.isEmpty) {
      return t(context).tr('docScannedPartial');
    }
    return '${t(context).tr('docScannedOk')}\n\n${lines.join('\n')}';
  }

  /// Check if result has ANY useful fields (for partial save).
  bool _hasAnyFields(OcrResult result) {
    return _notEmpty(result.firstName) ||
        _notEmpty(result.lastName) ||
        _notEmpty(result.idNumber) ||
        _notEmpty(result.licenseNumber) ||
        _notEmpty(result.licenseCategory) ||
        _notEmpty(result.dob) ||
        _notEmpty(result.expiryDate);
  }

  /// Check if result has the expected fields for this document type.
  bool _hasRequiredFields(OcrResult result, ScanDocType docType) {
    if (docType == ScanDocType.driversLicense) {
      return _notEmpty(result.licenseNumber) ||
          _notEmpty(result.idNumber) ||
          _notEmpty(result.licenseCategory) ||
          _notEmpty(result.expiryDate);
    }
    return _notEmpty(result.idNumber) ||
        _notEmpty(result.firstName) ||
        _notEmpty(result.lastName);
  }

  /// Per-step validace — co je potřeba, aby scan té strany měl smysl.
  ///
  /// ŘP přední: číslo NEBO platnost NEBO skupiny (alespoň jedno, bez
  ///            toho nelze ověřit).
  /// ŘP zadní:  stačí skupiny NEBO číslo (zadní strana hlavně dodává
  ///            tabulku skupin a slouží jako kontrola čísla).
  /// OP/pas přední: jméno/příjmení NEBO číslo dokladu NEBO platnost.
  /// OP/pas zadní:  adresa (ulice/město/PSČ/address string). Pokud OCR
  ///                vrátí alespoň MRZ nebo jméno, také stačí — není to
  ///                výpad, user jen naskenoval zadní stranu. Záloha v DB
  ///                pak ukládá jen ty pole, která mají hodnotu.
  bool _hasRequiredFieldsForStep(OcrResult r, _ScanStep step) {
    final isBack = step.key.endsWith('_back');
    if (step.docType == ScanDocType.driversLicense) {
      if (isBack) {
        // Zadní ŘP: hlavně skupiny; číslo je bonus pro cross-check.
        return _notEmpty(r.licenseCategory)
            || _notEmpty(r.licenseNumber)
            || _notEmpty(r.idNumber);
      }
      return _notEmpty(r.licenseNumber)
          || _notEmpty(r.expiryDate)
          || _notEmpty(r.licenseCategory);
    }
    if (isBack) {
      // Zadní OP/pas: hlavně adresa. Povolíme i MRZ nebo jméno jako
      // důkaz, že Mindee zadní stranu přečetl — jinak by user nemohl
      // pokračovat v případě, kdy model adresu nerozpozná.
      return _notEmpty(r.street)
          || _notEmpty(r.city)
          || _notEmpty(r.zip)
          || _notEmpty(r.address)
          || _notEmpty(r.firstName)
          || _notEmpty(r.lastName);
    }
    return _notEmpty(r.firstName)
        || _notEmpty(r.lastName)
        || _notEmpty(r.idNumber)
        || _notEmpty(r.expiryDate);
  }

  static bool _notEmpty(String? s) => s != null && s.isNotEmpty;

  // ── Result overlay actions ──

  void _onContinue() {
    setState(() => _resultKind = _ResultKind.none);
    if (_stepIdx < _sequence.length - 1) {
      setState(() => _stepIdx++);
    } else {
      _disposeCamera();
      _finalize();
    }
  }

  void _onRetry() {
    // Reset overlay — camera is still running, same step
    setState(() => _resultKind = _ResultKind.none);
  }

  Future<void> _skip() async {
    setState(() => _resultKind = _ResultKind.none);
    if (_stepIdx < _sequence.length - 1) {
      setState(() => _stepIdx++);
    } else {
      await _disposeCamera();
      await _finalize();
    }
  }

  /// Přeskočená povinná strana (záloha, když brána dokladů neodpoví):
  /// OP líc + rub, u pasu stačí jedna strana, ŘP líc + rub.
  bool get _skippedRequired {
    bool done(String k) => _completed[k] == true;
    final keys = _sequence.map((s) => s.key).toList();
    if (_idType == 'passport') {
      keys.removeWhere((k) => k.startsWith('passport_'));
      if (!done('passport_front') && !done('passport_back')) return true;
    }
    return keys.any((k) => !done(k));
  }

  Future<void> _finalize() async {
    showMotoGoToast(context,
        icon: '⏳', title: t(context).tr('verifyingDocs'), message: '');
    await Future.delayed(const Duration(milliseconds: 500));
    try { await verifyCustomerDocs(OcrResult()); } catch (_) {}
    // Kompletnost stran podle serverové brány (počítá i dřív nahrané fotky);
    // bez odpovědi RPC podle kroků tohoto skenu.
    final gate = await fetchDocsGateChecklist();
    if (!mounted) return;
    ref.invalidate(docsVerifiedProvider);
    ref.invalidate(docsGateChecklistProvider);
    ref.invalidate(profileProvider);
    final missing = gate != null
        ? docsGateMissingLabels(context, gate, docsOnly: true)
        : const <String>[];
    if (gate != null ? missing.isNotEmpty : _skippedRequired) {
      // Poctivě: kódy nepřijdou, dokud strana chybí (dřív „nahrány a ověřeny“).
      showMotoGoToast(context,
          icon: '⚠️', title: t(context).tr('docsScanIncompleteTitle'),
          message: missing.isEmpty
              ? t(context).tr('docsScanIncomplete')
              : '${t(context).tr('docsScanIncomplete')}\n'
                  '${t(context).tr('missing')}: ${missing.join(', ')}',
          duration: const Duration(seconds: 6));
    } else if (gate == null) {
      // Bránu dokladů se nepodařilo zeptat (výpadek / časový limit) — fotky
      // máme, ale „ověřeno" by nebyla pravda. Výsledek je v Mých dokladech.
      showMotoGoToast(context,
          icon: '⏳', title: t(context).tr('scanComplete'),
          message: t(context).tr('navDocsVerifyPending'),
          duration: const Duration(seconds: 7));
      context.go(Routes.docs);
      return;
    } else if (!gate.ok) {
      // Strany jsou, ale brána dál drží kódy (datum narození / 18+ /
      // platnost či skupina ŘP) — žádné „nahrány a ověřeny“.
      final rest = docsGateMissingLabels(context, gate);
      showMotoGoToast(context,
          icon: '⚠️', title: t(context).tr('scanComplete'),
          message: rest.isEmpty
              ? t(context).tr('codesStillWithheld')
              : '${t(context).tr('codesStillWithheld')}\n'
                  '${t(context).tr('missing')}: ${rest.join(', ')}',
          duration: const Duration(seconds: 6));
    } else {
      showMotoGoToast(context,
          icon: '✅', title: t(context).tr('scanComplete'),
          message: t(context).tr('docsUploadedVerified'));
    }
    // Navigate back to docs screen when scanning just DL or only the missing
    // sides (started from Moje doklady), otherwise go home
    if (widget.scanMode == 'dl_only' || isDocScanMissingMode(widget.scanMode)) {
      context.go(Routes.docs);
    } else {
      context.go(Routes.home);
    }
  }

  // ── Build ──

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // If scanMode is 'dl_only', skip the ID choice screen entirely
    if (widget.scanMode == 'dl_only') {
      _idType = 'dl_only';
      _initCamera();
    } else if (isDocScanMissingMode(widget.scanMode)) {
      _planLoading = true;
      _loadPlan();
    }
  }

  /// Režim „doplnit chybějící“: plán podle stavu dokladů ([loadDocScanPlan]).
  Future<void> _loadPlan() async {
    final plan = await loadDocScanPlan(ref, widget.scanMode);
    if (!mounted) return;
    setState(() {
      _planLoading = false;
      _only = plan.only;
      _offerDlOnly = plan.offerDlOnly;
    });
    if (plan.idType != null) _selectIdType(plan.idType!);
  }

  @override
  Widget build(BuildContext context) {
    if (_planLoading) return _loadingScreen();
    if (_idType == null) return _idChoiceScreen();
    if (_stepIdx >= _sequence.length) return _doneScreen();
    return _cameraStepScreen();
  }

  // ═══════════════════════════════════════════
  // ID TYPE CHOICE
  // ═══════════════════════════════════════════

  Widget _idChoiceScreen() {
    return Scaffold(
      backgroundColor: MotoGoColors.dark,
      body: SafeArea(child: Column(children: [
        _headerRow(),
        const Spacer(),
        Text(t(context).tr('selectIdDocument'),
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900,
                color: Colors.white)),
        const SizedBox(height: 24),
        _choiceBtn('🪪', t(context).tr('idCard'), () => _selectIdType('op')),
        const SizedBox(height: 12),
        _choiceBtn('📕', t(context).tr('passport'), () => _selectIdType('passport')),
        if (_offerDlOnly) ...[
          const SizedBox(height: 12),
          _choiceBtn('🏍️', t(context).tr('dlOnly'), () => _selectIdType('dl_only')),
        ],
        const Spacer(),
        Padding(padding: const EdgeInsets.all(20), child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _badge('🔒 ${t(context).tr('secureRecognition')}'),
            const SizedBox(width: 8),
            _badge('📱 ${t(context).tr('dataStoredLocally')}'),
          ],
        )),
        _badge('🇪🇺 EU GDPR compliant'),
        const SizedBox(height: 20),
      ])),
    );
  }

  Widget _badge(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8)),
    child: Text(text,
        style: TextStyle(fontSize: 9, color: Colors.white.withValues(alpha: 0.5))),
  );

  Widget _choiceBtn(String icon, String label, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 40),
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity, padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Text(icon, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontSize: 15,
              fontWeight: FontWeight.w700, color: MotoGoColors.black)),
        ]),
      ),
    ),
  );

  // ═══════════════════════════════════════════
  // CAMERA STEP SCREEN
  // ═══════════════════════════════════════════

  /// Kamera nejde: proč + Otevřít nastavení / Zkusit znovu / Zpět (doklad jde
  /// nahrát i z galerie v Mých dokladech).
  Widget _cameraErrorView() {
    final tr = t(context);
    final fe = _camFe;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('📷', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 12),
          Text(_camError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4)),
          const SizedBox(height: 8),
          Text(tr.tr('eoScanUseGallery'),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12)),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
            if (fe != null && fe.needsSettings)
              ElevatedButton(
                onPressed: () => openFixSettings(fe),
                child: Text(tr.tr('eoOpenSettings')),
              ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
              onPressed: () {
                setState(() {
                  _camError = null;
                  _camFe = null;
                });
                _initCamera();
              },
              child: Text(tr.tr('eoRetry')),
            ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
              onPressed: () async {
                await _disposeCamera();
                if (mounted) _safePop();
              },
              child: Text(tr.tr('eoBack')),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _cameraStepScreen() {
    final step = _sequence[_stepIdx];
    final mq = MediaQuery.of(context);
    final bottomPad = mq.padding.bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        // Camera preview
        if (_camReady && _cam != null && _cam!.value.isInitialized)
          Center(child: CameraPreview(_cam!))
        else if (_camError != null)
          _cameraErrorView()
        else
          const Center(child: CircularProgressIndicator(color: MotoGoColors.green)),

        // Document frame
        if (_camReady)
          CustomPaint(painter: DocumentFramePainter(
              isPassport: step.docType == ScanDocType.passport)),

        // Processing overlay
        if (_scanning)
          Container(
            color: Colors.black.withValues(alpha: 0.6),
            child: Center(child: Column(
                mainAxisSize: MainAxisSize.min, children: [
              const CircularProgressIndicator(color: MotoGoColors.green),
              const SizedBox(height: 12),
              Text(_progressText ?? t(context).tr('processing'), style: const TextStyle(
                  fontSize: 14, color: Colors.white)),
            ])),
          ),

        // Top header + progress — NAD překryvem zpracování, ať je šipka zpět
        // vidět a funguje i během nahrávání (systémové zpět funguje vždy).
        Positioned(
          top: mq.padding.top + 8, left: 16, right: 16,
          child: Column(children: [
            Row(children: [
              _backBtn(() async {
                await _disposeCamera();
                if (mounted) _safePop();
              }),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${step.icon} ${step.title}',
                    style: const TextStyle(fontSize: 14,
                        fontWeight: FontWeight.w900, color: Colors.white)),
                Text('${step.side}  ${_stepIdx + 1}/${_sequence.length}',
                    style: TextStyle(fontSize: 10,
                        color: Colors.white.withValues(alpha: 0.5))),
              ]),
            ]),
            const SizedBox(height: 12),
            _progressDots(),
          ]),
        ),

        // Guide text
        if (!_scanning && _resultKind == _ResultKind.none)
          Positioned(
            bottom: bottomPad + 130, left: 40, right: 40,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12)),
              child: Text(_guideText(step), textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13,
                      fontWeight: FontWeight.w600, color: Colors.white,
                      height: 1.4)),
            ),
          ),

        // Capture button + skip
        if (!_scanning && _resultKind == _ResultKind.none)
          Positioned(
            bottom: bottomPad + 24, left: 0, right: 0,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              GestureDetector(
                onTap: _isCapturing ? null : _capture,
                child: Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle, color: Colors.white,
                    border: Border.all(color: MotoGoColors.green, width: 4)),
                  child: _isCapturing
                      ? const Padding(padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(
                              color: MotoGoColors.green, strokeWidth: 3))
                      : const Icon(Icons.camera_alt,
                          size: 32, color: MotoGoColors.dark),
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _skip,
                icon: const Icon(Icons.skip_next,
                    size: 16, color: Colors.white54),
                label: Text(t(context).tr('skipArrow'),
                    style: const TextStyle(color: Colors.white54, fontSize: 13)),
              ),
            ]),
          ),

        // ── RESULT OVERLAY ──
        if (_resultKind != _ResultKind.none)
          _resultOverlay(),
      ]),
    );
  }

  // ═══════════════════════════════════════════
  // RESULT OVERLAY (success / error)
  // ═══════════════════════════════════════════

  Widget _resultOverlay() {
    if (_resultKind == _ResultKind.contactFallback) {
      return _contactFallbackOverlay();
    }
    final ok = _resultKind == _ResultKind.success;
    final remaining = _kMaxAttemptsPerStep - _resultAttempt;
    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(ok ? '✅' : '⚠️', style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          Text(ok ? t(context).tr('scanned') : t(context).tr('scanFailed'),
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900,
                  color: ok ? MotoGoColors.green : const Color(0xFFFBBF24))),
          const SizedBox(height: 8),
          Text(_resultTitle, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14,
                  fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 12),
          Text(_resultMsg, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13,
                  color: Colors.white70, height: 1.5)),
          if (!ok && _resultGuidance.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
              ),
              child: Text(_resultGuidance, textAlign: TextAlign.left,
                style: const TextStyle(fontSize: 12,
                  color: Colors.white, height: 1.5, fontWeight: FontWeight.w600)),
            ),
          ],
          if (!ok && remaining > 0) ...[
            const SizedBox(height: 10),
            Text(t(context).trArgs('scanAttemptsLeft', {'n': remaining}),
              style: const TextStyle(fontSize: 12,
                color: Color(0xFFFBBF24), fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 24),
          GestureDetector(
            onTap: ok ? _onContinue : _onRetry,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                  color: ok ? MotoGoColors.green : Colors.white,
                  borderRadius: BorderRadius.circular(50)),
              child: Text(ok ? t(context).tr('continueArrow') : t(context).tr('retry'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
                      color: ok ? Colors.black : MotoGoColors.dark)),
            ),
          ),
          if (!ok) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: _skip,
              child: Text(t(context).tr('skipArrow'),
                  style: const TextStyle(color: Colors.white54, fontSize: 13)),
            ),
          ],
        ]),
      )),
    );
  }

  // Zobrazí se po _kMaxAttemptsPerStep nezdařených pokusech na jednom kroku.
  // Nabídne volání a email s předvyplněným subjektem.
  Widget _contactFallbackOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.92),
      child: Center(child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('📞', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          Text(t(context).tr('scanHelpTitle'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900,
              color: Colors.white)),
          const SizedBox(height: 8),
          Text(_resultTitle, textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13,
              fontWeight: FontWeight.w700, color: Colors.white70)),
          const SizedBox(height: 14),
          Text(
            t(context).trArgs('scanHelpText', {'n': _kMaxAttemptsPerStep}),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13,
              color: Colors.white70, height: 1.5),
          ),
          if (_resultGuidance.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
              ),
              child: Text(_resultGuidance,
                style: const TextStyle(fontSize: 12,
                  color: Colors.white, height: 1.5, fontWeight: FontWeight.w600)),
            ),
          ],
          const SizedBox(height: 22),
          _contactBtn(
            icon: '📞',
            label: '${t(context).tr('callLabel')} $_kSupportPhone',
            onTap: () => _launchExternal(
              'tel:${_kSupportPhone.replaceAll(' ', '')}'),
            primary: true,
          ),
          const SizedBox(height: 10),
          _contactBtn(
            icon: '✉️',
            label: '${t(context).tr('scanWriteBtn')} $_kSupportEmail',
            // Předmět pro obsluhu (Velín) zůstává česky.
            onTap: () => _launchExternal(
              'mailto:$_kSupportEmail?subject='
              '${Uri.encodeComponent('Ověření dokladů — $_resultTitle')}'),
            primary: false,
          ),
          const SizedBox(height: 18),
          // Možnost znovu — třeba zákazník chce po konzultaci zkusit znovu
          TextButton(
            onPressed: () => setState(() {
              _attempts[_sequence[_stepIdx].key] = 0;
              _resultAttempt = 0;
              _resultKind = _ResultKind.none;
            }),
            child: Text(t(context).tr('scanTryAgainAnyway'),
              style: const TextStyle(color: Colors.white54, fontSize: 13)),
          ),
          TextButton(
            onPressed: () async {
              await _disposeCamera();
              if (mounted) _safePop();
            },
            child: Text(t(context).tr('scanCloseScanner'),
              style: const TextStyle(color: Colors.white38, fontSize: 13)),
          ),
        ]),
      )),
    );
  }

  Widget _contactBtn({required String icon, required String label,
    required VoidCallback onTap, required bool primary}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
        decoration: BoxDecoration(
          color: primary ? MotoGoColors.green : Colors.white,
          borderRadius: BorderRadius.circular(50),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Flexible(
            child: Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14,
                fontWeight: FontWeight.w800, color: Colors.black)),
          ),
        ]),
      ),
    );
  }

  Future<void> _launchExternal(String url) async {
    try {
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[DocScan] launchUrl failed: $e');
    }
  }

  // ═══════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════

  Widget _progressDots() => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: List.generate(_sequence.length, (i) => Container(
      width: i == _stepIdx ? 24 : 10, height: 6,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: i < _stepIdx ? MotoGoColors.green
            : (i == _stepIdx ? MotoGoColors.greenDark : Colors.white24),
        borderRadius: BorderRadius.circular(3)),
    )),
  );

  Widget _backBtn(VoidCallback onTap) => MgBackTap(
    onTap: onTap,
    child: Container(width: 36, height: 36,
        decoration: BoxDecoration(
            color: MotoGoColors.green,
            borderRadius: BorderRadius.circular(10)),
        child: const Center(child: Text('←',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900,
                color: Colors.black)))),
  );

  String _guideText(_ScanStep step) {
    if (step.docType == ScanDocType.passport) return t(context).tr('placePassportInFrame');
    if (step.docType == ScanDocType.driversLicense) return t(context).tr('placeLicenseInFrame');
    return t(context).tr('placeIdInFrame');
  }

  Widget _loadingScreen() => Scaffold(
    backgroundColor: MotoGoColors.dark,
    body: SafeArea(child: Column(children: [
      _headerRow(),
      const Expanded(child: Center(
          child: CircularProgressIndicator(color: MotoGoColors.green))),
    ])),
  );

  // Šipka zpět i během ověřování (ověření doběhne na serveru i tak).
  Widget _doneScreen() => Scaffold(
    backgroundColor: MotoGoColors.dark,
    body: SafeArea(child: Column(children: [
      _headerRow(),
      Expanded(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('✅', style: TextStyle(fontSize: 48)),
        const SizedBox(height: 16),
        Text(t(context).tr('scanComplete'), style: const TextStyle(fontSize: 20,
            fontWeight: FontWeight.w900, color: Colors.white)),
        const SizedBox(height: 8),
        Text(t(context).tr('verifyingDocs'), style: const TextStyle(fontSize: 13,
            color: Colors.white54)),
        SizedBox(height: 24),
        CircularProgressIndicator(color: MotoGoColors.green),
      ]))),
    ])),
  );

  Widget _headerRow() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    child: Row(children: [
      _backBtn(() => _safePop()),
      const SizedBox(width: 12),
      Text(t(context).tr('scanDocuments'), style: const TextStyle(fontSize: 14,
          fontWeight: FontWeight.w900, color: Colors.white)),
    ]),
  );
}

class _ScanStep {
  final ScanDocType docType;
  final String icon, title, side, key;
  const _ScanStep(this.docType, this.icon, this.title, this.side, this.key);
}
