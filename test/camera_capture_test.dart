import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart' as camera;
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:seamly/features/camera_capture_view.dart';
import 'package:seamly/features/camera_measurement_screen.dart';
import 'package:seamly/services/seamly_api.dart';

final _photo = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a7l8AAAAASUVORK5CYII=',
);
const _description = CameraDescription(
  name: 'test-camera',
  lensDirection: CameraLensDirection.back,
  sensorOrientation: 90,
);
final _bodyResult = <String, dynamic>{
  'person_detected': true,
  'scan_confidence': 0.85,
  'image_quality': 0.9,
  'measurements': {
    for (final name in [
      'height',
      'neck',
      'shoulder',
      'chest',
      'underbust',
      'waist',
      'high_hip',
      'hip',
      'sleeve',
      'wrist',
      'inseam',
    ])
      name: 80.0,
  },
  'displayable_measurements': ['chest', 'waist', 'hip'],
  'quality_warnings': <String>[],
  'validation_status': 'Estimated measurements',
  'disclaimer': 'Confirm with a tape measure.',
};
const _colorResult = <String, dynamic>{
  'color_season': 'Soft Autumn',
  'palette': ['#9C7253', '#7A836C', '#DCB38A'],
  'metals': ['Gold'],
  'confidence': 0.8,
  'lighting_quality': 0.85,
  'complexion_direction': 'Warm',
};

void main() {
  for (final size in [
    const Size(430, 900),
    const Size(320, 568),
    const Size(844, 390),
  ]) {
    testWidgets('camera fills $size without stretching or clipping controls', (
      tester,
    ) async {
      _viewport(tester, size);
      final controller = _PreviewController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              padding: const EdgeInsets.only(top: 44, bottom: 24),
              textScaler: const TextScaler.linear(1.6),
            ),
            child: Scaffold(
              body: _view(
                controller: controller,
                previewReady: true,
                previewGuidance: 'Ready — hold still and take the photo.',
                previewBbox: const [0.3, 0.08, 0.4, 0.84],
              ),
            ),
          ),
        ),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('camera-preview-surface'))),
        size,
      );
      final previewSize = tester.getSize(find.byType(camera.CameraPreview));
      expect(previewSize.aspectRatio, closeTo(1080 / 1920, 0.001));
      expect(
        tester.widget<FittedBox>(find.byType(FittedBox)).fit,
        BoxFit.cover,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('camera-shutter')));
      final shutter = tester.getRect(
        find.byKey(const ValueKey('camera-shutter')),
      );
      expect(shutter.top, greaterThanOrEqualTo(44));
      expect(shutter.bottom, lessThanOrEqualTo(size.height - 24));
      expect(
        find.text('Ready — hold still and take the photo.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('landscape result controls scroll without overflowing', (
    tester,
  ) async {
    _viewport(tester, const Size(844, 390));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _view(
            captured: true,
            colorResult: _colorResult,
            hasResults: true,
            error:
                'Some measurements need another photo. Keep your whole body visible.',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('camera-shutter')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('color analysis disables gallery, retake and switch', (
    tester,
  ) async {
    _viewport(tester, const Size(430, 900));
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: _view(captured: true, busy: true))),
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('camera-shutter')))
          .onPressed,
      isNull,
    );
    for (final tooltip in ['Choose photo', 'Switch camera']) {
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) => widget is IconButton && widget.tooltip == tooltip,
              ),
            )
            .onPressed,
        isNull,
      );
    }
    expect(find.byKey(const ValueKey('camera-view-results')), findsNothing);
  });

  group('scan lifecycle', () {
    late CameraPlatform oldCamera;
    late ImagePickerPlatform oldPicker;
    late _NoCameraPlatform platform;
    late _PhotoPicker picker;
    setUp(() {
      oldCamera = CameraPlatform.instance;
      oldPicker = ImagePickerPlatform.instance;
      platform = _NoCameraPlatform();
      picker = _PhotoPicker();
      CameraPlatform.instance = platform;
      ImagePickerPlatform.instance = picker;
    });
    tearDown(() {
      CameraPlatform.instance = oldCamera;
      ImagePickerPlatform.instance = oldPicker;
    });

    testWidgets('leaving before camera discovery prevents initialization', (
      tester,
    ) async {
      _viewport(tester, const Size(430, 900));
      platform.discovery = Completer<List<CameraDescription>>();
      await tester.pumpWidget(_screen(_ScanApi()));
      await _acceptInstructions(tester);
      await tester.pumpWidget(const SizedBox());
      platform.discovery!.complete([_description]);
      await tester.pumpAndSettle();
      expect(platform.created, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'permission interruption waits for initializing camera cleanup',
      (tester) async {
        _viewport(tester, const Size(430, 900));
        final delayed = _DelayedCameraPlatform();
        CameraPlatform.instance = delayed;
        await tester.pumpWidget(_screen(_ScanApi()));
        await _acceptInstructions(tester);
        expect(delayed.operations, ['create 1']);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(delayed.operations, ['create 1']);
        delayed.firstCreation.complete(1);
        await tester.pumpAndSettle();
        expect(delayed.operations, ['create 1', 'dispose 1', 'create 2']);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        expect(delayed.operations.last, 'dispose 2');
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('late body response cannot save after leaving the camera', (
      tester,
    ) async {
      _viewport(tester, const Size(430, 900));
      final api = _ScanApi();
      var saved = 0;
      await tester.pumpWidget(_screen(api, onMeasurements: (_) => saved++));
      await _acceptInstructions(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Choose photo'));
      await tester.pump();
      expect(api.bodyCalls, 1);
      await tester.pumpWidget(
        _screen(api, active: false, onMeasurements: (_) => saved++),
      );
      api.body.complete(_bodyResult);
      await tester.pumpAndSettle();
      expect(saved, 0);
      expect(api.colorCalls, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('late color response is ignored after leaving', (tester) async {
      _viewport(tester, const Size(430, 900));
      final api = _ScanApi();
      var saved = 0;
      await tester.pumpWidget(_screen(api, onColor: (_) => saved++));
      await _acceptInstructions(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Choose photo'));
      await tester.pump();
      api.body.complete(_bodyResult);
      await tester.pump();
      expect(api.colorCalls, 1);
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('camera-shutter')))
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(
        _screen(api, active: false, onColor: (_) => saved++),
      );
      api.color.complete(_colorResult);
      await tester.pumpAndSettle();
      expect(saved, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'returning from gallery does not restart camera while waiting for photo',
      (tester) async {
        _viewport(tester, const Size(430, 900));
        picker.selection = Completer<XFile?>();
        await tester.pumpWidget(_screen(_ScanApi()));
        await _acceptInstructions(tester);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Choose photo'));
        await tester.pump();
        final discoveries = platform.discovered;
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(platform.discovered, discoveries);
        await tester.pumpWidget(const SizedBox());
        picker.selection!.complete(XFile.fromData(_photo));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('results remain readable on a small screen with large text', (
      tester,
    ) async {
      _viewport(tester, const Size(320, 568));
      final api = _ScanApi();
      api.body.complete(_bodyResult);
      api.color.complete(_colorResult);
      await tester.pumpWidget(_screen(api, textScale: 2));
      await _acceptInstructions(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Choose photo'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('camera-view-results')),
      );
      await tester.tap(find.byKey(const ValueKey('camera-view-results')));
      await tester.pumpAndSettle();
      expect(find.text('Your scan'), findsOneWidget);
      expect(find.text('Natural waist'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

void _viewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _acceptInstructions(WidgetTester tester) async {
  for (final key in [
    'scan-preparation-checkbox',
    'scan-consent-checkbox',
    'start-guided-scan-button',
  ]) {
    final target = find.byKey(ValueKey(key));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pump();
  }
}

Widget _screen(
  _ScanApi api, {
  bool active = true,
  ValueChanged<Map<String, double>>? onMeasurements,
  ValueChanged<String>? onColor,
  double textScale = 1,
}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(
    body: CameraMeasurementScreen(
      api: api,
      active: active,
      referenceHeightCm: 165,
      onBack: () {},
      onMeasurementsReady: onMeasurements ?? (_) {},
      onColorSeasonAnalyzed: onColor ?? (_) {},
      onOpenShop: () {},
    ),
  ),
);

CameraCaptureView _view({
  camera.CameraController? controller,
  bool captured = false,
  bool busy = false,
  Map<String, dynamic>? colorResult,
  bool hasResults = false,
  String? error,
  bool previewReady = false,
  String? previewGuidance,
  List<double>? previewBbox,
}) => CameraCaptureView(
  controller: controller,
  starting: false,
  photoBytes: captured ? _photo : null,
  busy: busy,
  analyzingColor: busy,
  error: error,
  colorResult: colorResult,
  hasResults: hasResults,
  previewReady: previewReady,
  previewGuidance: previewGuidance,
  previewBbox: previewBbox,
  onBack: () {},
  onHelp: () {},
  onCapture: () {},
  onRetake: () {},
  onGallery: () {},
  onSwitch: () {},
  onRetry: () {},
  onResults: () {},
);

class _PreviewController extends camera.CameraController {
  _PreviewController() : super(_description, ResolutionPreset.high) {
    value = value.copyWith(
      isInitialized: true,
      previewSize: const Size(1920, 1080),
      deviceOrientation: DeviceOrientation.portraitUp,
    );
  }
  @override
  Widget buildPreview() => const ColoredBox(color: Colors.blueGrey);
}

class _NoCameraPlatform extends CameraPlatform {
  Completer<List<CameraDescription>>? discovery;
  int created = 0;
  int discovered = 0;
  @override
  Future<List<CameraDescription>> availableCameras() {
    discovered++;
    return discovery?.future ?? Future.value([]);
  }

  @override
  Future<int> createCamera(
    CameraDescription cameraDescription,
    ResolutionPreset? resolutionPreset, {
    bool enableAudio = false,
  }) async {
    created++;
    throw StateError('No camera should be initialized in this test');
  }
}

class _PhotoPicker extends ImagePickerPlatform {
  Completer<XFile?>? selection;
  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) => selection?.future ?? Future.value(XFile.fromData(_photo));
}

class _DelayedCameraPlatform extends _NoCameraPlatform {
  final firstCreation = Completer<int>();
  final operations = <String>[];
  @override
  Future<List<CameraDescription>> availableCameras() async => [_description];
  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();
  @override
  Future<int> createCamera(
    CameraDescription cameraDescription,
    ResolutionPreset? resolutionPreset, {
    bool enableAudio = false,
  }) {
    created++;
    operations.add('create $created');
    return created == 1 ? firstCreation.future : Future.value(created);
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(
        CameraInitializedEvent(
          cameraId,
          1920,
          1080,
          ExposureMode.auto,
          true,
          FocusMode.auto,
          true,
        ),
      );
  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) => Stream.multi((_) {});
  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {}
  @override
  Future<void> dispose(int cameraId) async =>
      operations.add('dispose $cameraId');
  @override
  Widget buildPreview(int cameraId) => const ColoredBox(color: Colors.blueGrey);
}

class _ScanApi extends SeamlyApi {
  final body = Completer<Map<String, dynamic>>();
  final color = Completer<Map<String, dynamic>>();
  int bodyCalls = 0;
  int colorCalls = 0;
  int previewCalls = 0;
  @override
  Future<Map<String, dynamic>> previewBodyPhoto({
    required Uint8List imageBytes,
  }) {
    previewCalls++;
    return Future.value({
      'ready': false,
      'person_detected': false,
      'person_confidence': 0.0,
      'guidance': 'Stand fully visible in the frame.',
      'bbox': null,
    });
  }

  @override
  Future<Map<String, dynamic>> analyzeBodyPhoto({
    required Uint8List imageBytes,
    required double referenceHeightCm,
  }) {
    bodyCalls++;
    return body.future;
  }

  @override
  Future<Map<String, dynamic>> analyzeAppearancePhoto({
    required Uint8List imageBytes,
  }) {
    colorCalls++;
    return color.future;
  }
}
