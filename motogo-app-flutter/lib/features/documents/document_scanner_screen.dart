import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../auth/widgets/toast_helper.dart';
import 'document_models.dart';
import 'document_provider.dart';

/// Document scanner — mirrors scan-flow.js + doc-scanner-*.js.
/// Flow: OP (front) → ŘP (front) → Done (merge + verify).
class DocumentScannerScreen extends ConsumerStatefulWidget {
  const DocumentScannerScreen({super.key});

  @override
  ConsumerState<DocumentScannerScreen> createState() => _ScannerState();
}

class _ScannerState extends ConsumerState<DocumentScannerScreen> {
  final _picker = ImagePicker();
  int _step = 0; // 0=OP, 1=ŘP, 2=Done
  bool _scanning = false;
  OcrResult? _idResult;
  OcrResult? _dlResult;

  static const _steps = [
    (ScanDocType.idCard, '🪪 Občanský průkaz', 'Naskenujte přední stranu OP'),
    (ScanDocType.driversLicense, '🏍️ Řidičský průkaz', 'Naskenujte přední stranu ŘP'),
  ];

  Future<void> _capture() async {
    final photo = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
      maxWidth: 1600,
    );
    if (photo == null) return;
    if (!mounted) return;

    final docType = _steps[_step].$1;
    setState(() => _scanning = true);
    showMotoGoToast(context, icon: '⏳', title: 'OCR skenování...', message: 'Zpracovávám doklad');

    // Upload photo to storage
    await uploadDocPhoto(photo, docType);

    // OCR via Mindee
    final result = await scanDocument(photo, docType);

    if (!mounted) return;
    setState(() => _scanning = false);

    if (result == null) {
      showMotoGoToast(context, icon: '⚠️', title: 'OCR', message: 'Nepodařilo se rozpoznat doklad. Zkuste znovu.');
      return;
    }

    // Store result
    if (_step == 0) {
      _idResult = result;
      showMotoGoToast(context, icon: '✅', title: 'OP naskenován', message: result.fullName.isNotEmpty ? result.fullName : 'Rozpoznáno');
    } else {
      _dlResult = result;
      showMotoGoToast(context, icon: '✅', title: 'ŘP naskenován', message: result.licenseNumber ?? 'Rozpoznáno');
    }

    setState(() => _step++);

    // If both done, merge and save
    if (_step >= _steps.length) {
      await _finalize();
    }
  }

  Future<void> _skip() async {
    setState(() => _step++);
    if (_step >= _steps.length) await _finalize();
  }

  Future<void> _finalize() async {
    // Merge results — OP for identity, ŘP for license
    final merged = OcrResult(
      firstName: _idResult?.firstName ?? _dlResult?.firstName,
      lastName: _idResult?.lastName ?? _dlResult?.lastName,
      dob: _idResult?.dob ?? _dlResult?.dob,
      idNumber: _idResult?.idNumber,
      licenseNumber: _dlResult?.licenseNumber,
      licenseCategory: _dlResult?.licenseCategory,
      issuedDate: _dlResult?.issuedDate,
      expiryDate: _dlResult?.expiryDate,
      address: _idResult?.address,
    );

    // Save to profile
    await saveOcrToProfile(merged);

    // Verify
    final verification = await verifyCustomerDocs(merged);

    if (!mounted) return;
    ref.invalidate(docsVerifiedProvider);
    ref.invalidate(profileProvider);

    final success = verification?['success'] == true;
    showMotoGoToast(context,
      icon: success ? '✅' : '⚠️',
      title: success ? 'Doklady ověřeny' : 'Ověření s výhradami',
      message: success ? 'OP + ŘP v pořádku' : 'Zkontrolujte údaje v profilu',
    );

    context.go(Routes.home);
  }

  @override
  Widget build(BuildContext context) {
    final isDone = _step >= _steps.length;

    return Scaffold(
      backgroundColor: MotoGoColors.dark,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // Header
              Row(children: [
                GestureDetector(
                  onTap: () => context.pop(),
                  child: Container(width: 36, height: 36,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
                    child: const Center(child: Text('←', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)))),
                ),
                const SizedBox(width: 12),
                const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('📷 Sken dokladů', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white)),
                  Text('Mindee OCR', style: TextStyle(fontSize: 11, color: Colors.white54)),
                ]),
              ]),
              const SizedBox(height: 24),

              // Progress dots
              Row(mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_steps.length, (i) => Container(
                  width: i <= _step ? 24 : 10, height: 10, margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: i < _step ? MotoGoColors.green : (i == _step ? MotoGoColors.greenDark : Colors.white24),
                    borderRadius: BorderRadius.circular(5),
                  ),
                )),
              ),
              const SizedBox(height: 32),

              // Current step
              Expanded(
                child: isDone
                    ? _doneView()
                    : _stepView(_steps[_step].$1, _steps[_step].$2, _steps[_step].$3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepView(ScanDocType type, String title, String subtitle) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
        const SizedBox(height: 8),
        Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.6)), textAlign: TextAlign.center),
        const SizedBox(height: 32),

        // Scan frame
        Container(
          width: 260, height: 170,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: MotoGoColors.green, width: 3),
          ),
          child: Center(
            child: _scanning
                ? const CircularProgressIndicator(color: MotoGoColors.green)
                : Text(type == ScanDocType.idCard ? '🪪' : '🏍️', style: const TextStyle(fontSize: 48)),
          ),
        ),
        const SizedBox(height: 24),
        const Text('Umístěte doklad do rámečku', style: TextStyle(fontSize: 12, color: Colors.white54)),
        const SizedBox(height: 32),

        // Capture button
        ElevatedButton.icon(
          onPressed: _scanning ? null : _capture,
          icon: const Text('📷', style: TextStyle(fontSize: 18)),
          label: Text(_scanning ? 'Zpracovávám...' : 'Vyfotit doklad'),
          style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _scanning ? null : _skip,
          child: const Text('Přeskočit →', style: TextStyle(color: Colors.white54)),
        ),
      ],
    );
  }

  Widget _doneView() {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('✅', style: TextStyle(fontSize: 48)),
        SizedBox(height: 16),
        Text('Skenování dokončeno', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
        SizedBox(height: 8),
        Text('Ukládám a ověřuji doklady...', style: TextStyle(fontSize: 13, color: Colors.white54)),
        SizedBox(height: 24),
        CircularProgressIndicator(color: MotoGoColors.green),
      ],
    );
  }
}
