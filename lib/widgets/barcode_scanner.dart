import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme.dart';

/// Opens the camera and returns the first barcode or QR code it reads,
/// or a code typed by hand. Returns null if cancelled.
Future<String?> scanCode(BuildContext context, {String? title}) {
  return Navigator.of(context).push<String>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _ScannerScreen(title: title ?? 'Scan barcode or QR'),
  ));
}

class _ScannerScreen extends StatefulWidget {
  const _ScannerScreen({required this.title});

  final String title;

  @override
  State<_ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<_ScannerScreen> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _finish(String code) {
    if (_done || code.trim().isEmpty) return;
    _done = true;
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(code.trim());
  }

  void _onDetect(BarcodeCapture capture) {
    final code = capture.barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .where((v) => v.trim().isNotEmpty)
        .firstOrNull;
    if (code != null) _finish(code);
  }

  Future<void> _typeCode() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Type the code'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Barcode / QR text',
            prefixIcon: Icon(Icons.qr_code_2),
          ),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Use code')),
        ],
      ),
    );
    controller.dispose();
    if (code != null) _finish(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Torch',
            icon: const Icon(Icons.flashlight_on_outlined),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _CameraError(
              code: error.errorCode.name,
              onTypeCode: _typeCode,
            ),
          ),
          const IgnorePointer(child: CustomPaint(painter: _FramePainter())),
          Positioned(
            left: 24,
            right: 24,
            bottom: 32,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Point the camera at the barcode or QR code',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 15),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    minimumSize: const Size(220, 48),
                  ),
                  onPressed: _typeCode,
                  icon: const Icon(Icons.keyboard_outlined),
                  label: const Text('Type code'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.code, required this.onTypeCode});

  final String code;
  final VoidCallback onTypeCode;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Brand.navy,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined,
                  color: Colors.white, size: 48),
              const SizedBox(height: 12),
              const Text(
                'The camera could not start.\n'
                'Allow camera access for OSHU Stock in the phone settings, '
                'or type the code instead.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 4),
              Text('($code)',
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onTypeCode,
                icon: const Icon(Icons.keyboard_outlined),
                label: const Text('Type code'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Darkens the camera view outside a rounded scanning window.
class _FramePainter extends CustomPainter {
  const _FramePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width * 0.78;
    final h = w * 0.62;
    final rect = Rect.fromCenter(
        center: Offset(size.width / 2, size.height * 0.42), width: w, height: h);
    final window = RRect.fromRectAndRadius(rect, const Radius.circular(20));

    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRRect(window),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );
    canvas.drawRRect(
      window,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Brand.yellow,
    );
    // A red guide line across the middle, like a barcode reader.
    canvas.drawLine(
      Offset(rect.left + 16, rect.center.dy),
      Offset(rect.right - 16, rect.center.dy),
      Paint()
        ..strokeWidth = 2
        ..color = Brand.red.withValues(alpha: 0.85),
    );
  }

  @override
  bool shouldRepaint(_FramePainter old) => false;
}
