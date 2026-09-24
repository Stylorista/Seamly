import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart' as camera;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' as picker;

import '../services/seamly_api.dart';
import '../theme/seamly_theme.dart';
import '../widgets/common.dart';
import 'camera_capture_view.dart';

class CameraMeasurementScreen extends StatefulWidget {
  const CameraMeasurementScreen({
    super.key,
    required this.api,
    required this.active,
    required this.referenceHeightCm,
    required this.onBack,
    required this.onMeasurementsReady,
    required this.onColorSeasonAnalyzed,
    required this.onOpenShop,
    this.onOpenAccount,
    this.avatarBase64,
  });

  final SeamlyApi api;
  final bool active;
  final double? referenceHeightCm;
  final VoidCallback onBack;
  final ValueChanged<Map<String, double>> onMeasurementsReady;
  final ValueChanged<String> onColorSeasonAnalyzed;
  final VoidCallback onOpenShop;
  final VoidCallback? onOpenAccount;
  final String? avatarBase64;

  @override
  State<CameraMeasurementScreen> createState() =>
      _CameraMeasurementScreenState();
}

class _CameraMeasurementScreenState extends State<CameraMeasurementScreen>
    with WidgetsBindingObserver {
  final _picker = picker.ImagePicker();

  camera.CameraController? _cameraController;
  List<camera.CameraDescription> _cameras = const [];
  Uint8List? _photoBytes;
  Map<String, dynamic>? _result;
  Map<String, dynamic>? _colorResult;
  String? _error;
  String? _colorError;
  bool _cameraStarting = false;
  bool _analyzing = false;
  bool _analyzingColor = false;
  bool _instructionsAccepted = false;
  bool _preparationConfirmed = false;
  bool _consentConfirmed = false;
  bool _capturing = false;
  int _cameraGeneration = 0;
  int _scanGeneration = 0;
  Future<void> _cameraQueue = Future<void>.value();
  Timer? _previewTimer;
  bool _previewInFlight = false;
  bool _previewReady = false;
  String? _previewGuidance;
  List<double>? _previewBbox;

  bool get _busy => _capturing || _analyzing || _analyzingColor;
  bool _currentScan(int generation) =>
      mounted && widget.active && generation == _scanGeneration;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant CameraMeasurementScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active &&
        !oldWidget.active &&
        _instructionsAccepted &&
        _photoBytes == null &&
        !_capturing) {
      _startCamera();
    } else if (!widget.active && oldWidget.active) {
      _scanGeneration++;
      _capturing = false;
      _analyzing = false;
      _analyzingColor = false;
      _stopPreviewLoop();
      unawaited(_disposeCamera());
      _instructionsAccepted = false;
      _preparationConfirmed = false;
      _consentConfirmed = false;
      _photoBytes = null;
      _result = null;
      _colorResult = null;
      _error = null;
      _colorError = null;
      _previewReady = false;
      _previewGuidance = null;
      _previewBbox = null;
    } else if (widget.active && _instructionsAccepted && _photoBytes == null) {
      _startPreviewLoop();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.active) return;
if (state == AppLifecycleState.inactive) {
      _stopPreviewLoop();
      unawaited(_disposeCamera());
} else if (state == AppLifecycleState.resumed &&
        _instructionsAccepted &&
        _photoBytes == null &&
        !_capturing) {
      unawaited(_startCamera());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scanGeneration++;
    _stopPreviewLoop();
    unawaited(_disposeCamera());
    super.dispose();
  }

  Future<void> _queueCameraOperation(Future<void> Function() operation) {
    final next = _cameraQueue.then((_) => operation());
    // A failed native operation must not prevent later cleanup or a retry.
    _cameraQueue = next.catchError((Object _) {});
    return next;
  }

  Future<void> _disposeCamera() {
    _cameraGeneration++;
    _cameraStarting = false;
    final controller = _cameraController;
    _cameraController = null;
    return _queueCameraOperation(() async => controller?.dispose());
  }

  void _startPreviewLoop() {
    if (_previewTimer != null || !mounted || !widget.active) return;
    _previewTimer = Timer.periodic(
      const Duration(milliseconds: 1500),
      (_) => unawaited(_samplePreview()),
    );
    unawaited(_samplePreview());
  }

  void _stopPreviewLoop() {
    _previewTimer?.cancel();
    _previewTimer = null;
    _previewInFlight = false;
    _previewReady = false;
    _previewGuidance = null;
    _previewBbox = null;
  }

  Future<void> _samplePreview() async {
    if (!mounted ||
        !widget.active ||
        !_instructionsAccepted ||
        _photoBytes != null ||
        _busy ||
        _cameraStarting ||
        _previewInFlight) {
      return;
    }
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    final generation = _scanGeneration;
    _previewInFlight = true;
    try {
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      if (!_currentScan(generation) || _photoBytes != null) return;
      final result = await widget.api.previewBodyPhoto(imageBytes: bytes);
      if (!_currentScan(generation) || _photoBytes != null) return;
      final bbox = (result['bbox'] as List<dynamic>?)
          ?.map((value) => (value as num).toDouble())
          .toList();
      setState(() {
        _previewReady = result['ready'] == true;
        _previewGuidance = result['guidance']?.toString();
        _previewBbox = bbox;
      });
    } on Exception {
      // Preview is best-effort; keep the last known state.
    } finally {
      _previewInFlight = false;
      if (mounted &&
          widget.active &&
          _instructionsAccepted &&
          _photoBytes == null &&
          !_busy) {
        _startPreviewLoop();
      }
    }
  }

  Future<void> _startCamera({camera.CameraLensDirection? lens}) {
    final requestedGeneration = _cameraGeneration;
    return _queueCameraOperation(() async {
      if (requestedGeneration == _cameraGeneration) {
        await _initializeCamera(lens: lens);
      }
    });
  }

  Future<void> _initializeCamera({camera.CameraLensDirection? lens}) async {
    if (!mounted ||
        !widget.active ||
        !_instructionsAccepted ||
        _photoBytes != null ||
        _capturing ||
        _cameraStarting ||
        _cameraController?.value.isInitialized == true) {
      return;
    }
    final generation = ++_cameraGeneration;
    camera.CameraController? pending;
    bool current() =>
        mounted &&
        widget.active &&
        _instructionsAccepted &&
        _photoBytes == null &&
        generation == _cameraGeneration;
    setState(() {
      _cameraStarting = true;
      _error = null;
    });
    try {
      _cameras = await camera.availableCameras();
      if (!current()) return;
      if (_cameras.isEmpty) throw Exception('No camera found');
      final selected = _cameras.firstWhere(
        (item) =>
            item.lensDirection == (lens ?? camera.CameraLensDirection.back),
        orElse: () => _cameras.first,
      );
      pending = camera.CameraController(
        selected,
        camera.ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: camera.ImageFormatGroup.jpeg,
      );
      await pending.initialize();
      if (!current()) return;
      final ready = pending;
      pending = null;
      setState(() => _cameraController = ready);
      _startPreviewLoop();
    } on Exception {
      if (current()) {
        setState(
          () => _error =
              'Allow camera access to take a photo, or choose one from your gallery.',
        );
      }
    } finally {
      await pending?.dispose();
      if (current()) setState(() => _cameraStarting = false);
    }
  }

  Future<void> _switchCamera() async {
    if (_busy || _cameraStarting) return;
    final current = _cameraController?.description.lensDirection;
    final next = current == camera.CameraLensDirection.front
        ? camera.CameraLensDirection.back
        : camera.CameraLensDirection.front;
    await _disposeCamera();
    if (mounted && widget.active) await _startCamera(lens: next);
  }

  bool get _hasValidCalibration {
    final height = widget.referenceHeightCm;
    return height != null && height >= 120 && height <= 230;
  }

  bool _ensureCalibration() {
    if (!_hasValidCalibration) {
      setState(() {
        _error =
            'A verified height is missing from this account. Create or update your profile before scanning.';
      });
      return false;
    }
    if (!_instructionsAccepted || !_preparationConfirmed) {
      setState(() {
        _error =
            'Review and confirm the scan instructions before taking a photo.';
      });
      return false;
    }
    if (!_consentConfirmed) {
      setState(() {
        _error = 'Photo consent is required before measurement analysis.';
      });
      return false;
    }
    return true;
  }

  Future<void> _beginGuidedScan() async {
    if (!_hasValidCalibration) {
      setState(() {
        _error =
            'A verified height is missing from this account. Create or update your profile before scanning.';
      });
      return;
    }
    if (!_preparationConfirmed || !_consentConfirmed) return;
    setState(() {
      _instructionsAccepted = true;
      _error = null;
    });
    await _startCamera();
  }

  void _reviewInstructions() {
    _scanGeneration++;
    _stopPreviewLoop();
    unawaited(_disposeCamera());
    setState(() {
      _instructionsAccepted = false;
      _error = null;
    });
  }

  Future<void> _capture() async {
    if (_busy || _cameraStarting || !_ensureCalibration()) return;
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      await _choosePhoto(picker.ImageSource.camera);
      return;
    }
    final generation = _scanGeneration;
    setState(() => _capturing = true);
    try {
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      if (_currentScan(generation)) await _usePhoto(bytes);
    } on Exception {
      if (_currentScan(generation)) {
        setState(() => _error = 'The photo could not be captured. Try again.');
      }
    } finally {
      if (_currentScan(generation)) {
        setState(() => _capturing = false);
        _startPreviewLoop();
      }
    }
  }

  Future<void> _choosePhoto(picker.ImageSource source) async {
    if (_busy || !_ensureCalibration()) return;
    final generation = _scanGeneration;
    setState(() => _capturing = true);
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 1800,
        maxHeight: 2400,
        imageQuality: 88,
        requestFullMetadata: false,
      );
      if (file != null) {
        final bytes = await file.readAsBytes();
        if (_currentScan(generation)) await _usePhoto(bytes);
      }
    } on Exception {
      if (_currentScan(generation)) {
        setState(() => _error = 'The selected photo could not be opened.');
      }
    } finally {
      if (_currentScan(generation)) {
        setState(() => _capturing = false);
        if (_photoBytes == null) await _startCamera();
      }
    }
  }

  Future<void> _usePhoto(Uint8List bytes) async {
    if (!mounted || !widget.active) return;
    final generation = _scanGeneration;
    _stopPreviewLoop();
    unawaited(_disposeCamera());
    setState(() {
      _photoBytes = bytes;
      _result = null;
      _colorResult = null;
      _analyzing = true;
      _analyzingColor = false;
      _error = null;
      _colorError = null;
    });
    try {
      final result = await widget.api.analyzeBodyPhoto(
        imageBytes: bytes,
        referenceHeightCm: widget.referenceHeightCm!,
      );
      if (!_currentScan(generation)) return;
      final measurements = (result['measurements'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, (value as num).toDouble()),
      );
      if (result['person_detected'] == false) {
        throw const ApiException(
          'No full-body person was detected. Retake the photo with one person visible from head to toe.',
        );
      }
      setState(() => _result = result);
      final confidence =
          (result['measurement_confidence'] as Map<String, dynamic>?) ??
          const <String, dynamic>{};
      final displayable = (result['displayable_measurements'] as List<dynamic>?)
          ?.map((item) => item.toString())
          .toSet();
      final reliableFit = {'chest', 'waist', 'hip'}.every(
        (key) =>
            displayable?.contains(key) ??
            ((confidence[key] as num?)?.toDouble() ?? 0) >= 0.58,
      );
      if (reliableFit) {
        widget.onMeasurementsReady(measurements);
      }
      if (!_currentScan(generation)) return;
      setState(() {
        _analyzing = false;
        _analyzingColor = true;
      });
      try {
        final colorResult = await widget.api.analyzeAppearancePhoto(
          imageBytes: bytes,
        );
        if (!_currentScan(generation)) return;
        setState(() => _colorResult = colorResult);
        widget.onColorSeasonAnalyzed(colorResult['color_season'] as String);
      } on ApiException catch (error) {
        if (_currentScan(generation)) {
          setState(() => _colorError = error.message);
        }
      }
    } on ApiException catch (error) {
      if (_currentScan(generation)) setState(() => _error = error.message);
    } on Exception {
      if (_currentScan(generation)) {
        setState(
          () => _error = 'The photo could not be analyzed. Please try again.',
        );
      }
    } finally {
      if (_currentScan(generation)) {
        setState(() {
          _analyzing = false;
          _analyzingColor = false;
        });
      }
    }
  }

  Future<void> _retake() async {
    if (_busy) return;
    _scanGeneration++;
    _stopPreviewLoop();
    setState(() {
      _photoBytes = null;
      _result = null;
      _colorResult = null;
      _error = null;
      _colorError = null;
    });
    await _startCamera();
  }

  void _showResults() {
    if (_busy) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.85,
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 650),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Your scan',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close results',
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    if (_photoBytes != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Image.memory(
                          _photoBytes!,
                          height: 200,
                          fit: BoxFit.contain,
                          semanticLabel: 'Your full scan photo',
                        ),
                      ),
                    if (_colorResult != null)
                      _CameraColorResult(result: _colorResult!),
                    if (_colorError != null)
                      _ColorAnalysisUnavailable(message: _colorError!),
                    if (_result != null) ...[
                      const SizedBox(height: 16),
                      _MeasurementResults(
                        result: _result!,
                        onOpenShop: () {
                          Navigator.pop(sheetContext);
                          widget.onOpenShop();
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.active,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && widget.active) widget.onBack();
      },
      child: _instructionsAccepted
          ? CameraCaptureView(
              controller: _cameraController,
              starting: _cameraStarting,
              photoBytes: _photoBytes,
              busy: _busy,
              analyzingColor: _analyzingColor,
              error: _error,
              colorResult: _colorResult,
              hasResults: _result != null || _colorResult != null,
              previewReady: _previewReady,
              previewGuidance: _previewGuidance,
              previewBbox: _previewBbox,
              onBack: widget.onBack,
              onHelp: _reviewInstructions,
              onCapture: _capture,
              onRetake: _retake,
              onGallery: () => _choosePhoto(picker.ImageSource.gallery),
              onSwitch: _cameras.length > 1 ? _switchCamera : null,
              onRetry: _startCamera,
              onResults: _showResults,
            )
          : ColoredBox(
              color: SeamlyColors.cream,
              child: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              IconButton(
                                tooltip: 'Back home',
                                onPressed: widget.onBack,
                                icon: const Icon(Icons.arrow_back),
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Body scan',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _ScanPreparationCard(
                            referenceHeightCm: widget.referenceHeightCm,
                            preparationConfirmed: _preparationConfirmed,
                            consentConfirmed: _consentConfirmed,
                            onPreparationChanged: (value) => setState(
                              () => _preparationConfirmed = value ?? false,
                            ),
                            onConsentChanged: (value) => setState(
                              () => _consentConfirmed = value ?? false,
                            ),
                            onStart: _preparationConfirmed && _consentConfirmed
                                ? _beginGuidedScan
                                : null,
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            ErrorBanner(message: _error!),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class _ScanPreparationCard extends StatelessWidget {
  const _ScanPreparationCard({
    required this.referenceHeightCm,
    required this.preparationConfirmed,
    required this.consentConfirmed,
    required this.onPreparationChanged,
    required this.onConsentChanged,
    required this.onStart,
  });

  final double? referenceHeightCm;
  final bool preparationConfirmed;
  final bool consentConfirmed;
  final ValueChanged<bool?> onPreparationChanged;
  final ValueChanged<bool?> onConsentChanged;
  final VoidCallback? onStart;

  bool get _hasValidHeight =>
      referenceHeightCm != null &&
      referenceHeightCm! >= 120 &&
      referenceHeightCm! <= 230;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Prepare for your body scan',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 7),
            const Text(
              'Follow these steps before opening the camera so Seamly can estimate your measurements from a clear full-body photo.',
              style: TextStyle(height: 1.4),
            ),
            const SizedBox(height: 20),
            const _PreparationStep(
              icon: Icons.light_mode_outlined,
              title: 'Move to a well-lit area',
              detail:
                  'Use bright, even light from the front. Avoid strong shadows and a bright window behind you.',
            ),
            const _PreparationStep(
              icon: Icons.accessibility_new_rounded,
              title: 'Show your full body',
              detail:
                  'Face forward with your head and feet visible. Stand straight with your arms slightly away from your sides.',
            ),
            const _PreparationStep(
              icon: Icons.checkroom_outlined,
              title: 'Wear fitted clothing',
              detail:
                  'Avoid loose layers that hide your shoulders, waist, hips, or legs.',
            ),
            const _PreparationStep(
              icon: Icons.phone_iphone_rounded,
              title: 'Position the phone',
              detail:
                  'Keep it upright and steady, about 2–3 metres away, against a plain contrasting background.',
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: SeamlyColors.sand.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.straighten_rounded),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _hasValidHeight
                          ? 'Saved height: ${referenceHeightCm!.toStringAsFixed(0)} cm. This calibrates the measurement estimates.'
                          : 'Add a verified height to your profile before starting the scan.',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              key: const ValueKey('scan-preparation-checkbox'),
              value: preparationConfirmed,
              onChanged: onPreparationChanged,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                'I am in a well-lit area and can fit my full body inside the camera guide.',
                style: TextStyle(fontSize: 13.5),
              ),
            ),
            CheckboxListTile(
              key: const ValueKey('scan-consent-checkbox'),
              value: consentConfirmed,
              onChanged: onConsentChanged,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                'I consent to sending this photo to the configured scan API for in-memory measurement and color analysis.',
                style: TextStyle(fontSize: 13.5),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const ValueKey('start-guided-scan-button'),
              onPressed: _hasValidHeight ? onStart : null,
              icon: const Icon(Icons.photo_camera_rounded),
              label: const Text('Open camera for body scan'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Measurement results are estimates. Check them with a soft tape and the seller’s size chart before buying or altering clothing.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreparationStep extends StatelessWidget {
  const _PreparationStep({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: SeamlyColors.sand.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: SeamlyColors.sandText),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ColorAnalysisUnavailable extends StatelessWidget {
  const _ColorAnalysisUnavailable({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      color: const Color(0xFFFFF4E8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.light_mode_outlined, color: Color(0xFF9A5C18)),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Color analysis needs another photo',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: const TextStyle(fontSize: 12.5, height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraColorResult extends StatelessWidget {
  const _CameraColorResult({required this.result});

  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final palette = (result['palette'] as List<dynamic>).cast<String>();
    final metals = (result['metals'] as List<dynamic>).cast<String>();
    final warnings =
        (result['quality_warnings'] as List<dynamic>?)?.cast<String>() ??
        const <String>[];
    final confidence = ((result['confidence'] as num) * 100).round();
    final lighting = (((result['lighting_quality'] as num?) ?? 0) * 100)
        .round();
    final reliable = confidence >= 65 && lighting >= 60;

    return Card(
      key: const ValueKey('camera-color-analysis-result'),
      margin: EdgeInsets.zero,
      color: const Color(0xFFF4EEF5),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.palette_rounded, color: SeamlyColors.plum),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    '${result['color_season']} color direction',
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: reliable
                      ? const Color(0xFFE4F4E8)
                      : const Color(0xFFFFE8C7),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  reliable ? 'Good capture' : 'Retake advised',
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              '${result['complexion_direction']} • $confidence% color confidence • $lighting% lighting quality',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 15),
            Wrap(
              spacing: 9,
              runSpacing: 9,
              children: [
                for (final hex in palette.take(6))
                  Tooltip(
                    message: hex,
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: colorFromHex(hex),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: const [
                          BoxShadow(color: Colors.black12, blurRadius: 4),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 13),
            Text(
              'Recommended metals: ${metals.take(2).join(' • ')}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            for (final warning in warnings)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded, size: 17),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        warning,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 11),
            const Text(
              'Camera-based color is an estimate, not a guaranteed personal-color diagnosis. For the most reliable result, use bright indirect daylight, no filter, and verify the palette in more than one photo.',
              style: TextStyle(
                fontSize: 11.5,
                color: Colors.black54,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MeasurementResults extends StatelessWidget {
  const _MeasurementResults({required this.result, required this.onOpenShop});

  final Map<String, dynamic> result;
  final VoidCallback onOpenShop;

  static const labels = {
    'height': 'Height',
    'neck': 'Neck',
    'shoulder': 'Shoulder',
    'chest': 'Chest / bust',
    'underbust': 'Underbust',
    'waist': 'Natural waist',
    'high_hip': 'High hip',
    'hip': 'Full hip',
    'sleeve': 'Sleeve',
    'wrist': 'Wrist',
    'inseam': 'Inseam',
  };

  @override
  Widget build(BuildContext context) {
    final measurements = result['measurements'] as Map<String, dynamic>;
    final confidence = ((result['scan_confidence'] as num) * 100).round();
    final quality = ((result['image_quality'] as num) * 100).round();
    final personConfidence =
        (((result['person_confidence'] as num?) ?? 1) * 100).round();
    final measurementConfidence =
        (result['measurement_confidence'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};
    final explicitlyDisplayable =
        (result['displayable_measurements'] as List<dynamic>?)
            ?.map((item) => item.toString())
            .toSet();
    bool canShow(String key) =>
        explicitlyDisplayable?.contains(key) ??
        ((measurementConfidence[key] as num?)?.toDouble() ?? 1) >= 0.58;
    final hasReliableFit = {'chest', 'waist', 'hip'}.every(canShow);
    final warnings = (result['quality_warnings'] as List).cast<String>();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'AI body profile',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            Text(
              'Person detected $personConfidence%  •  Scan confidence $confidence%  •  Image quality $quality%',
            ),
            const SizedBox(height: 6),
            const Text(
              'Only measurements that pass the reliability threshold are shown. Hidden values need a guided or tape-measure scan.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 18),
            LayoutBuilder(
              builder: (context, constraints) {
                final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
                final columns = (constraints.maxWidth / (130 * scale))
                    .floor()
                    .clamp(1, 3);
                final width =
                    (constraints.maxWidth - (columns - 1) * 9) / columns;
                return Wrap(
                  spacing: 9,
                  runSpacing: 9,
                  children: [
                    for (final entry in labels.entries)
                      Container(
                        width: width,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: SeamlyColors.sand.withValues(alpha: 0.11),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.value,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.black54,
                              ),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              canShow(entry.key)
                                  ? '${(measurements[entry.key] as num).toStringAsFixed(1)} cm'
                                  : 'Not reliable',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: canShow(entry.key)
                                    ? Colors.black87
                                    : Colors.black38,
                                fontSize: canShow(entry.key) ? 14 : 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            for (final warning in warnings)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 17,
                      color: SeamlyColors.sandText,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        warning,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            Text(
              result['validation_status'] as String,
              style: const TextStyle(
                fontSize: 11.5,
                color: Colors.black54,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              result['disclaimer'] as String,
              style: const TextStyle(
                fontSize: 11.5,
                color: Colors.black54,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: hasReliableFit ? onOpenShop : null,
              icon: const Icon(Icons.shopping_cart_rounded),
              label: Text(
                hasReliableFit
                    ? 'Shop my verified fit'
                    : 'Retake for a reliable shop fit',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
