import 'package:camera/camera.dart' as camera;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Edge-to-edge viewfinder. Only controls consume safe-area insets.
class CameraCaptureView extends StatelessWidget {
  const CameraCaptureView({
    super.key,
    required this.controller,
    required this.starting,
    required this.photoBytes,
    required this.busy,
    required this.analyzingColor,
    required this.error,
    required this.colorResult,
    required this.hasResults,
    required this.onBack,
    required this.onHelp,
    required this.onCapture,
    required this.onRetake,
    required this.onGallery,
    required this.onSwitch,
    required this.onRetry,
    required this.onResults,
    this.previewReady = false,
    this.previewGuidance,
    this.previewBbox,
  });

  final camera.CameraController? controller;
  final bool starting;
  final Uint8List? photoBytes;
  final bool busy;
  final bool analyzingColor;
  final String? error;
  final Map<String, dynamic>? colorResult;
  final bool hasResults;
  final VoidCallback onBack;
  final VoidCallback onHelp;
  final VoidCallback onCapture;
  final VoidCallback onRetake;
  final VoidCallback onGallery;
  final VoidCallback? onSwitch;
  final VoidCallback onRetry;
  final VoidCallback onResults;
  final bool previewReady;
  final String? previewGuidance;
  final List<double>? previewBbox;

  @override
  Widget build(BuildContext context) {
    final captured = photoBytes != null;
    final ready = controller?.value.isInitialized == true;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
      child: Material(
        color: const Color(0xFF151515),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final landscape = constraints.maxWidth > constraints.maxHeight;
            return Stack(
              key: const ValueKey('camera-fullscreen'),
              fit: StackFit.expand,
              children: [
                ClipRect(
                  key: const ValueKey('camera-preview-surface'),
                  child: captured
                      ? Image.memory(
                          photoBytes!,
                          fit: BoxFit.cover,
                          semanticLabel: 'Captured photo preview',
                        )
                      : ready
                      ? kIsWeb
                          // Web video already cover-crops itself via CSS; our
                          // ratio-based cover box would crop it a second time.
                          ? controller!.buildPreview()
                          : _CoverPreview(controller: controller!)
                      : const ColoredBox(color: Color(0xFF151515)),
                ),
                if (ready && !captured)
                  const IgnorePointer(
                    child: CustomPaint(painter: _ThirdsGrid()),
                  ),
                if (ready && !captured && previewBbox != null)
                  IgnorePointer(
                    child: CustomPaint(
                      painter: _BodyOutlinePainter(
                        bbox: previewBbox!,
                        ready: previewReady,
                      ),
                    ),
                  ),
                const IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black54,
                          Colors.transparent,
                          Colors.transparent,
                          Colors.black87,
                        ],
                        stops: [0, 0.22, 0.55, 1],
                      ),
                    ),
                  ),
                ),
                if (!captured && !ready)
                  SafeArea(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        28,
                        70,
                        landscape ? 180 : 28,
                        landscape ? 24 : 180,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (starting)
                              const CircularProgressIndicator(
                                color: Colors.white,
                              )
                            else
                              const Icon(
                                Icons.no_photography_outlined,
                                size: 40,
                                color: Colors.white70,
                              ),
                            const SizedBox(height: 12),
                            Text(
                              starting
                                  ? 'Opening camera…'
                                  : 'Camera unavailable',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                SafeArea(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        12,
                        8,
                        landscape ? 160 : 12,
                        0,
                      ),
                      child: Row(
                        children: [
                          _RoundControl(
                            label: 'Back home',
                            icon: Icons.close,
                            onPressed: onBack,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              captured ? 'Your photo' : 'Body scan',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          _RoundControl(
                            label: 'Scan instructions',
                            icon: Icons.help_outline,
                            onPressed: !busy && !captured ? onHelp : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: Align(
                    alignment: landscape
                        ? Alignment.centerRight
                        : Alignment.bottomCenter,
                    child: Container(
                      width: landscape ? 160 : double.infinity,
                      constraints: landscape
                          ? null
                          : const BoxConstraints(maxWidth: 650),
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (error != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Text(
                                  error!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                  ),
                                ),
                              )
                            else if (busy)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Text(
                                  analyzingColor
                                      ? 'Checking your colors…'
                                      : captured
                                      ? 'Analyzing your measurements…'
                                      : 'Taking photo…',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              )
                            else if (!captured)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: Text(
                                  previewGuidance ??
                                      'Even light · Head to toe in frame',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: previewReady
                                        ? const Color(0xFF4ADE80)
                                        : Colors.white,
                                    fontSize: 14,
                                    fontWeight: previewReady
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                            if (colorResult != null && !busy) ...[
                              _PaletteSummary(result: colorResult!),
                              const SizedBox(height: 10),
                            ],
                            if (hasResults && !busy) ...[
                              FilledButton.icon(
                                key: const ValueKey('camera-view-results'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.black,
                                ),
                                onPressed: onResults,
                                icon: const Icon(Icons.keyboard_arrow_up),
                                label: const Text('View results'),
                              ),
                              const SizedBox(height: 12),
                            ],
                            if (!ready && !captured && !starting)
                              TextButton(
                                onPressed: busy ? null : onRetry,
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Retry camera'),
                              ),
                            Flex(
                              direction: landscape
                                  ? Axis.vertical
                                  : Axis.horizontal,
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _RoundControl(
                                  label: 'Choose photo',
                                  icon: Icons.photo_library_outlined,
                                  onPressed: busy || starting
                                      ? null
                                      : onGallery,
                                ),
                                SizedBox(
                                  width: landscape ? 0 : 30,
                                  height: landscape ? 14 : 0,
                                ),
                                SizedBox.square(
                                  dimension: 80,
                                  child: IconButton(
                                    key: const ValueKey('camera-shutter'),
                                    tooltip: captured
                                        ? 'Retake photo'
                                        : 'Take photo',
                                    onPressed: busy || starting
                                        ? null
                                        : captured
                                        ? onRetake
                                        : onCapture,
                                    style: IconButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      disabledForegroundColor: Colors.white54,
                                      side: const BorderSide(
                                        color: Colors.white,
                                        width: 5,
                                      ),
                                      backgroundColor: Colors.white12,
                                    ),
                                    icon: busy
                                        ? const SizedBox.square(
                                            dimension: 28,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 3,
                                              color: Colors.white,
                                            ),
                                          )
                                        : Icon(
                                            captured
                                                ? Icons.refresh
                                                : Icons.circle,
                                            size: captured ? 38 : 52,
                                          ),
                                  ),
                                ),
                                SizedBox(
                                  width: landscape ? 0 : 30,
                                  height: landscape ? 14 : 0,
                                ),
                                _RoundControl(
                                  label: 'Switch camera',
                                  icon: Icons.cameraswitch_outlined,
                                  onPressed: busy || starting || captured
                                      ? null
                                      : onSwitch,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CoverPreview extends StatelessWidget {
  const _CoverPreview({required this.controller});
  final camera.CameraController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<camera.CameraValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final orientation =
            value.previewPauseOrientation ??
            value.lockedCaptureOrientation ??
            value.deviceOrientation;
        final landscape =
            orientation == DeviceOrientation.landscapeLeft ||
            orientation == DeviceOrientation.landscapeRight;
        final ratio = landscape ? value.aspectRatio : 1 / value.aspectRatio;
        return FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: ratio * 1000,
            height: 1000,
            child: camera.CameraPreview(controller),
          ),
        );
      },
    );
  }
}

class _RoundControl extends StatelessWidget {
  const _RoundControl({
    required this.label,
    required this.icon,
    required this.onPressed,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: label,
    onPressed: onPressed,
    icon: Icon(icon),
    style: IconButton.styleFrom(
      minimumSize: const Size(48, 48),
      foregroundColor: Colors.white,
      disabledForegroundColor: Colors.white30,
      backgroundColor: Colors.black26,
    ),
  );
}

class _PaletteSummary extends StatelessWidget {
  const _PaletteSummary({required this.result});
  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 6,
    runSpacing: 6,
    children: [
      Text(
        '${result['color_season']} palette',
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
      for (final hex in (result['palette'] as List<dynamic>? ?? []).take(5))
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white70),
            color: Color(
              int.tryParse(hex.toString().replaceFirst('#', 'FF'), radix: 16) ??
                  0xFF999999,
            ),
          ),
        ),
    ],
  );
}

class _ThirdsGrid extends CustomPainter {
  const _ThirdsGrid();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 0.75;
    for (var index = 1; index < 3; index++) {
      final x = size.width * index / 3;
      final y = size.height * index / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BodyOutlinePainter extends CustomPainter {
  const _BodyOutlinePainter({required this.bbox, required this.ready});

  final List<double> bbox;
  final bool ready;

  @override
  void paint(Canvas canvas, Size size) {
    if (bbox.length < 4) return;
    final rect = Rect.fromLTWH(
      bbox[0] * size.width,
      bbox[1] * size.height,
      bbox[2] * size.width,
      bbox[3] * size.height,
    );
    final color = ready ? const Color(0xFF4ADE80) : Colors.white70;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ready ? 4 : 2
      ..color = color;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(28));
    if (ready) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 12
          ..color = color.withValues(alpha: 0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
    canvas.drawRRect(rrect, paint);
    final corner = 22.0;
    final cornerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ready ? 5 : 3
      ..strokeCap = StrokeCap.round
      ..color = color;
    void cornerPath(Offset start, Offset a, Offset b) {
      final path = Path()
        ..moveTo(start.dx + a.dx, start.dy + a.dy)
        ..lineTo(start.dx, start.dy)
        ..lineTo(start.dx + b.dx, start.dy + b.dy);
      canvas.drawPath(path, cornerPaint);
    }

    cornerPath(rect.topLeft, Offset(corner, 0), Offset(0, corner));
    cornerPath(rect.topRight, Offset(-corner, 0), Offset(0, corner));
    cornerPath(rect.bottomLeft, Offset(corner, 0), Offset(0, -corner));
    cornerPath(rect.bottomRight, Offset(-corner, 0), Offset(0, -corner));
  }

  @override
  bool shouldRepaint(covariant _BodyOutlinePainter oldDelegate) =>
      oldDelegate.ready != ready || oldDelegate.bbox != bbox;
}
