import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'document_models.dart';

/// Custom camera screen with document frame overlay for OP / ŘP scanning.
/// Returns the captured [XFile] or null if cancelled.
class DocumentCameraScreen extends StatefulWidget {
  final ScanDocType docType;
  final String title;
  final String side;

  const DocumentCameraScreen({
    super.key,
    required this.docType,
    required this.title,
    required this.side,
  });

  @override
  State<DocumentCameraScreen> createState() => _DocumentCameraScreenState();
}

class _DocumentCameraScreenState extends State<DocumentCameraScreen> {
  CameraController? _controller;
  bool _isInitialized = false;
  bool _isCapturing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = 'Kamera není dostupná');
        return;
      }

      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();
      if (!mounted) return;
      setState(() => _isInitialized = true);
    } catch (e) {
      setState(() => _error = 'Chyba kamery: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    if (_isCapturing || _controller == null || !_controller!.value.isInitialized) return;

    setState(() => _isCapturing = true);
    try {
      final file = await _controller!.takePicture();
      if (!mounted) return;
      Navigator.of(context).pop(file);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isCapturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera preview
          if (_isInitialized && _controller != null)
            Center(child: CameraPreview(_controller!))
          else if (_error != null)
            Center(
              child: Text(_error!, style: const TextStyle(color: Colors.white, fontSize: 14)),
            )
          else
            const Center(
              child: CircularProgressIndicator(color: MotoGoColors.green),
            ),

          // Document frame overlay
          if (_isInitialized)
            CustomPaint(
              painter: DocumentFramePainter(
                isPassport: widget.docType == ScanDocType.passport,
              ),
            ),

          // Top bar
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(null),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: MotoGoColors.green,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Center(
                      child: Text('←',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Colors.white)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        widget.side,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Guide text
          Positioned(
            bottom: 140,
            left: 40,
            right: 40,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _getGuideText(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  height: 1.4,
                ),
              ),
            ),
          ),

          // Capture button
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _isCapturing ? null : _capture,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(color: MotoGoColors.green, width: 4),
                  ),
                  child: _isCapturing
                      ? const Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(
                            color: MotoGoColors.green,
                            strokeWidth: 3,
                          ),
                        )
                      : const Icon(Icons.camera_alt,
                          size: 32, color: MotoGoColors.dark),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getGuideText() {
    if (widget.docType == ScanDocType.passport) {
      return 'Umístěte cestovní pas do rámečku';
    }
    if (widget.docType == ScanDocType.driversLicense) {
      return 'Umístěte řidičský průkaz do rámečku';
    }
    return 'Umístěte občanský průkaz do rámečku';
  }
}

/// Paints the document frame overlay with semi-transparent background
/// and a clear rectangle where the document should be placed.
class DocumentFramePainter extends CustomPainter {
  final bool isPassport;

  DocumentFramePainter({this.isPassport = false});

  @override
  void paint(Canvas canvas, Size size) {
    // Calculate document frame rect (ID card aspect ratio ~1.586:1, passport ~1.42:1)
    final aspectRatio = isPassport ? 1.42 : 1.586;
    final frameWidth = size.width * 0.85;
    final frameHeight = frameWidth / aspectRatio;
    final frameRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2 - 30),
      width: frameWidth,
      height: frameHeight,
    );

    // Draw semi-transparent overlay outside the frame
    final overlayPaint = Paint()..color = Colors.black.withValues(alpha: 0.5);
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(frameRect, const Radius.circular(16)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, overlayPaint);

    // Draw frame border
    final borderPaint = Paint()
      ..color = const Color(0xFF4ADE80) // MotoGoColors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawRRect(
      RRect.fromRectAndRadius(frameRect, const Radius.circular(16)),
      borderPaint,
    );

    // Draw corner accents
    final cornerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    const cornerLen = 24.0;
    const r = 16.0;
    final left = frameRect.left;
    final top = frameRect.top;
    final right = frameRect.right;
    final bottom = frameRect.bottom;

    // Top-left
    canvas.drawLine(Offset(left, top + r + cornerLen), Offset(left, top + r), cornerPaint);
    canvas.drawLine(Offset(left + r, top), Offset(left + r + cornerLen, top), cornerPaint);

    // Top-right
    canvas.drawLine(Offset(right, top + r + cornerLen), Offset(right, top + r), cornerPaint);
    canvas.drawLine(Offset(right - r, top), Offset(right - r - cornerLen, top), cornerPaint);

    // Bottom-left
    canvas.drawLine(Offset(left, bottom - r - cornerLen), Offset(left, bottom - r), cornerPaint);
    canvas.drawLine(Offset(left + r, bottom), Offset(left + r + cornerLen, bottom), cornerPaint);

    // Bottom-right
    canvas.drawLine(Offset(right, bottom - r - cornerLen), Offset(right, bottom - r), cornerPaint);
    canvas.drawLine(Offset(right - r, bottom), Offset(right - r - cornerLen, bottom), cornerPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
