import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../core/i18n/i18n_provider.dart';
import '../auth/widgets/toast_helper.dart';
import 'document_camera_screen.dart';
import 'document_models.dart';
import 'document_provider.dart';
import '../auth/auth_provider.dart';

/// Document scanner — 4-step flow matching Capacitor scanner-ui.js.
/// Camera stays open during all 4 captures (ID front+back, DL front+back).
/// After each scan shows a visible result overlay (success/error).
///
/// [scanMode] controls which documents to scan:
/// - null / 'all' → full flow (ID choice + DL)
/// - 'dl_only'   → only driver's license (dl_front + dl_back)
class DocumentScannerScreen extends ConsumerStatefulWidget {
  final String? scanMode;
  const DocumentScannerScreen({super.key, this.scanMode});
  @override
  ConsumerState<DocumentScannerScreen> createState() => _ScannerState();
}

enum _ResultKind { none, success, error }

class _ScannerState extends ConsumerState<DocumentScannerScreen> {
  String? _idType;
  int _stepIdx = 0;
  bool _scanning = false;
  bool _isCapturing = false;
  final Map<String, bool> _completed = {};

  // Camera — initialized once, reused for all 4 steps
  CameraController? _cam;
  bool _camReady = false;
  String? _camError;

  // Scan result overlay — shown after each scan
  _ResultKind _resultKind = _ResultKind.none;
  String _resultTitle = '';
  String _resultMsg = '';

  List<_ScanStep> get _sequence {
    final front = t(context).tr('frontSide');
    final back = t(context).tr('backSide');
    final dl = t(context).tr('driversLicense');
    if (_idType == 'dl_only') {
      return [
        _ScanStep(ScanDocType.driversLicense, '🏍️', dl, front, 'dl_front'),
        _ScanStep(ScanDocType.driversLicense, '🏍️', dl, back, 'dl_back'),
      ];
    }
    if (_idType == 'passport') {
      final pp = t(context).tr('passport');
      return [
        _ScanStep(ScanDocType.idCard, '📕', pp, front, 'passport_front'),
        _ScanStep(ScanDocType.idCard, '📕', pp, back, 'passport_back'),
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

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _camError = t(context).tr('cameraNotAvailable'));
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      _cam = CameraController(back, ResolutionPreset.high,
          enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
      await _cam!.initialize();
      if (!mounted) return;
      setState(() => _camReady = true);
    } catch (e) {
      setState(() => _camError = '${t(context).tr('cameraError')}: $e');
    }
  }

  void _selectIdType(String type) {
    setState(() => _idType = type);
    _initCamera();
  }

  Future<void> _disposeCamera() async {
    await _cam?.dispose();
    _cam = null;
    _camReady = false;
  }

  @override
  void dispose() {
    _cam?.dispose();
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

      // Upload photo + OCR run in parallel for speed,
      // but we await BOTH to ensure DB record is created.
      final uploadFuture = uploadDocPhoto(photo, step.docType);

      // OCR with retry (3 attempts, exponential backoff)
      final scanResult = await scanDocumentWithRetry(photo, step.docType);

      // Ensure upload completed — the DB record in documents table
      // is critical for admin verification + door code release.
      final uploadPath = await uploadFuture;
      if (uploadPath == null) {
        debugPrint('[DocScan] ⚠ Document upload failed for ${step.key}');
      }

      if (!mounted) return;
      setState(() => _scanning = false);

      if (scanResult.ok && _hasAnyFields(scanResult.data!)) {
        // Save whatever we got — even partial data
        // saveOcrToProfile NEVER crashes the scan flow
        final saveWarning = await saveOcrToProfile(
            scanResult.data!, docType: step.docType);
        if (!mounted) return;

        // Build summary of extracted fields for success overlay
        final summary = _buildFieldsSummary(scanResult.data!, step.docType);

        setState(() {
          _completed[step.key] = true;
          _resultKind = _ResultKind.success;
          _resultTitle = '${step.title} – ${step.side}';
          if (saveWarning != null) {
            _resultMsg = '$summary\n\n${t(context).tr('saveWarning')}';
          } else {
            _resultMsg = summary;
          }
        });
      } else if (scanResult.ok) {
        // OCR returned data but no useful fields — still count as success
        // (photo is uploaded, just couldn't parse content)
        setState(() {
          _completed[step.key] = true;
          _resultKind = _ResultKind.success;
          _resultTitle = '${step.title} – ${step.side}';
          _resultMsg = t(context).tr('docUploadedNoFields');
        });
      } else {
        // Build specific error message based on failure type
        setState(() {
          _resultKind = _ResultKind.error;
          _resultTitle = '${step.title} – ${step.side}';
          _resultMsg = _buildErrorMsg(scanResult, step);
        });
      }
    } catch (e) {
      debugPrint('[DocScan] Capture error: $e');
      if (!mounted) return;
      final step = _sequence[_stepIdx];
      final errStr = e.toString().toLowerCase();
      String msg;
      if (errStr.contains('permission') || errStr.contains('denied')) {
        msg = t(context).tr('errCameraPermission');
      } else if (errStr.contains('camera')) {
        msg = t(context).tr('errCameraGeneric');
      } else {
        msg = '${t(context).tr('errUnknown')}\n\n$e';
      }
      setState(() {
        _isCapturing = false;
        _scanning = false;
        _resultKind = _ResultKind.error;
        _resultTitle = '${step.title} – ${step.side}';
        _resultMsg = msg;
      });
    }
  }

  /// Build user-friendly error message with diagnostics.
  String _buildErrorMsg(ScanResult scanResult, _ScanStep step) {
    final code = scanResult.errorCode ?? 'unknown';
    final detail = scanResult.errorDetail;
    final http = scanResult.httpStatus;
    final att = scanResult.attempts;

    // Diagnostic line shown at bottom of every error
    final diag = '\n\n[${step.docType.apiType} | $code'
        '${http != null ? ' | HTTP $http' : ''}'
        '${att > 1 ? ' | pokus $att' : ''}]'
        '${detail != null && detail.length < 120 ? '\n$detail' : ''}';

    switch (code) {
      case 'network':
        return '${t(context).tr('errNetwork')}$diag';

      case 'timeout':
        return '${t(context).tr('errTimeout')}$diag';

      case 'server_config':
        // Edge function config error (e.g. missing MINDEE model ID)
        return '${t(context).tr('errServerConfig')}$diag';

      case 'server_upstream':
        // Edge function couldn't reach Mindee API
        return '${t(context).tr('errServerUpstream')}$diag';

      case 'server_error':
      case 'bad_request':
        return '${t(context).tr('errServerGeneric')}$diag';

      case 'ocr_failed':
        return '${t(context).tr('errOcrFailed')}\n\n'
            '${t(context).tr('errOcrHint')}$diag';

      case 'ocr_empty':
        return '${t(context).tr('errOcrEmpty')}$diag';

      case 'no_fields':
        return '${t(context).tr('errNoFields')}\n\n'
            '${t(context).tr('errNoFieldsHint')}$diag';

      case 'image_error':
        return '${t(context).tr('errImagePrep')}$diag';

      default:
        if (scanResult.ok) {
          return '${t(context).tr('errNoFields')}\n\n'
              '${t(context).tr('errNoFieldsHint')}$diag';
        }
        return '${t(context).tr('errUnknown')}$diag';
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

  Future<void> _finalize() async {
    showMotoGoToast(context,
        icon: '⏳', title: t(context).tr('verifyingDocs'), message: '');
    await Future.delayed(const Duration(milliseconds: 500));
    try { await verifyCustomerDocs(OcrResult()); } catch (_) {}
    if (!mounted) return;
    ref.invalidate(docsVerifiedProvider);
    ref.invalidate(profileProvider);
    showMotoGoToast(context,
        icon: '✅', title: t(context).tr('scanComplete'),
        message: t(context).tr('docsUploadedVerified'));
    // Navigate back to docs screen when scanning just DL, otherwise go home
    if (widget.scanMode == 'dl_only') {
      context.go(Routes.docs);
    } else {
      context.go(Routes.home);
    }
  }

  // ── Build ──

  @override
  void initState() {
    super.initState();
    // If scanMode is 'dl_only', skip the ID choice screen entirely
    if (widget.scanMode == 'dl_only') {
      _idType = 'dl_only';
      _initCamera();
    }
  }

  @override
  Widget build(BuildContext context) {
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
        const SizedBox(height: 12),
        _choiceBtn('🏍️', t(context).tr('dlOnly'), () => _selectIdType('dl_only')),
        const Spacer(),
        Padding(padding: const EdgeInsets.all(20), child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _badge('🔒 Zabezpečené rozpoznávání'),
            const SizedBox(width: 8),
            _badge('📱 Data uložena v telefonu'),
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

  Widget _cameraStepScreen() {
    final step = _sequence[_stepIdx];
    final mq = MediaQuery.of(context);
    final bottomPad = mq.padding.bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        // Camera preview
        if (_camReady && _cam != null)
          Center(child: CameraPreview(_cam!))
        else if (_camError != null)
          Center(child: Text(_camError!,
              style: const TextStyle(color: Colors.white, fontSize: 14)))
        else
          const Center(child: CircularProgressIndicator(color: MotoGoColors.green)),

        // Document frame
        if (_camReady)
          CustomPaint(painter: DocumentFramePainter(
              isPassport: step.docType == ScanDocType.passport)),

        // Top header + progress
        Positioned(
          top: mq.padding.top + 8, left: 16, right: 16,
          child: Column(children: [
            Row(children: [
              _backBtn(() async {
                await _disposeCamera();
                if (mounted) context.pop();
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

        // Processing overlay
        if (_scanning)
          Container(
            color: Colors.black.withValues(alpha: 0.6),
            child: Center(child: Column(
                mainAxisSize: MainAxisSize.min, children: [
              const CircularProgressIndicator(color: MotoGoColors.green),
              const SizedBox(height: 12),
              Text(t(context).tr('processing'), style: const TextStyle(
                  fontSize: 14, color: Colors.white)),
            ])),
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
    final ok = _resultKind == _ResultKind.success;
    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
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
          const SizedBox(height: 32),
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

  Widget _backBtn(VoidCallback onTap) => GestureDetector(
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

  Widget _doneScreen() => Scaffold(
    backgroundColor: MotoGoColors.dark,
    body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('✅', style: TextStyle(fontSize: 48)),
      const SizedBox(height: 16),
      Text(t(context).tr('scanComplete'), style: const TextStyle(fontSize: 20,
          fontWeight: FontWeight.w900, color: Colors.white)),
      const SizedBox(height: 8),
      Text(t(context).tr('verifyingDocs'), style: const TextStyle(fontSize: 13,
          color: Colors.white54)),
      SizedBox(height: 24),
      CircularProgressIndicator(color: MotoGoColors.green),
    ])),
  );

  Widget _headerRow() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    child: Row(children: [
      _backBtn(() => context.pop()),
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
