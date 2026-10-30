import 'dart:convert';
import 'dart:typed_data';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:seamly/app.dart';
import 'package:seamly/features/measurements_screen.dart';
import 'package:seamly/services/seamly_api.dart';
import 'package:seamly/services/session_store.dart';

const _saved = {'height': 165.0, 'chest': 96.0, 'waist': 78.0, 'hip': 104.0};
const _initial = SessionState(
  authenticated: true,
  welcomeCompleted: true,
  token: 'account-token',
  email: 'person@example.com',
  name: 'Test Person',
  heightCm: 165,
  measurements: _saved,
  sizeLabel: 'M',
  heightConfirmed: true,
);
final _photo = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a7l8AAAAASUVORK5CYII=',
);

void main() {
  late CameraPlatform oldCamera;
  late ImagePickerPlatform oldPicker;
  setUp(() {
    oldCamera = CameraPlatform.instance;
    oldPicker = ImagePickerPlatform.instance;
    CameraPlatform.instance = _NoCameraPlatform();
    ImagePickerPlatform.instance = _PhotoPicker();
  });
  tearDown(() {
    CameraPlatform.instance = oldCamera;
    ImagePickerPlatform.instance = oldPicker;
  });

  Future<MemorySessionStore> openApp(
    WidgetTester tester,
    _FitApi api, {
    MemorySessionStore? store,
  }) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final opened = store ?? MemorySessionStore(initialState: _initial);
    await tester.pumpWidget(SeamlyApp(api: api, sessionStore: opened));
    await tester.pumpAndSettle();
    return opened;
  }

  Future<void> relaunch(
    WidgetTester tester,
    _FitApi api,
    MemorySessionStore store,
  ) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await openApp(tester, api, store: store);
  }

  Future<void> openMeasurements(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('home-nav-Shop')));
    await tester.pumpAndSettle();
    final button = find.widgetWithText(OutlinedButton, 'Measurements');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  Future<void> submitForm(WidgetTester tester) async {
    final button = find.text('Save and recommend my size');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Future<void> scanFromGallery(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('home-nav-Scan')));
    await tester.pumpAndSettle();
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
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Choose photo'));
    await tester.pumpAndSettle();
  }

  testWidgets('an unconfirmed height locks the scan until confirmed', (
    tester,
  ) async {
    final api = _FitApi()..heightConfirmed = false;
    final store = await openApp(
      tester,
      api,
      store: MemorySessionStore(
        initialState: const SessionState(
          authenticated: true,
          welcomeCompleted: true,
          token: 'account-token',
          email: 'person@example.com',
          name: 'Test Person',
          heightCm: 165,
          measurements: _saved,
          sizeLabel: 'M',
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('home-nav-Scan')));
    await tester.pumpAndSettle();
    final start = find.byKey(const ValueKey('start-guided-scan-button'));
    for (final key in ['scan-preparation-checkbox', 'scan-consent-checkbox']) {
      await tester.ensureVisible(find.byKey(ValueKey(key)));
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pump();
    }
    expect(find.textContaining('Is 165 cm your real height?'), findsOneWidget);
    expect(tester.widget<FilledButton>(start).onPressed, isNull);

    final confirm = find.byKey(const ValueKey('confirm-height-button'));
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(api.confirmCalls, 1);
    expect(find.byKey(const ValueKey('confirm-height-button')), findsNothing);
    expect(tester.widget<FilledButton>(start).onPressed, isNotNull);
    expect((await store.read()).heightConfirmed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the form starts empty instead of sample measurements', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MeasurementsScreen(
            api: _FitApi(),
            referenceHeightCm: 172,
            onMeasurementsSaved: (_, _) async {},
          ),
        ),
      ),
    );
    final chest = tester.widget<TextFormField>(field('Chest / bust *'));
    final height = tester.widget<TextFormField>(field('Height *'));
    expect(chest.controller!.text, isEmpty);
    expect(height.controller!.text, '172.0');
  });

  testWidgets('typed measurements save to the account and this phone', (
    tester,
  ) async {
    final api = _FitApi();
    final store = await openApp(tester, api);
    await openMeasurements(tester);
    await tester.enterText(field('Chest / bust *'), '101');
    await submitForm(tester);

    expect(api.synced.single['chest'], 101.0);
    expect(api.syncedSizes.single, 'L');
    final restored = await store.read();
    expect(restored.measurements?['chest'], 101.0);
    expect(restored.sizeLabel, 'L');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed account sync keeps values on this phone and says so', (
    tester,
  ) async {
    final api = _FitApi()..failSync = true;
    final store = await openApp(tester, api);
    await openMeasurements(tester);
    await tester.enterText(field('Chest / bust *'), '101');
    await submitForm(tester);

    final restored = await store.read();
    expect(restored.measurements?['chest'], 101.0);
    expect(restored.sizeLabel, 'L');
    expect(restored.measurementsPendingSync, isTrue);
    expect(find.textContaining('Saved on this phone'), findsOneWidget);
  });

  testWidgets('unsynced values are sent to the account on the next launch', (
    tester,
  ) async {
    final api = _FitApi()..failSync = true;
    final store = await openApp(tester, api);
    await openMeasurements(tester);
    await tester.enterText(field('Chest / bust *'), '101');
    await submitForm(tester);

    api.failSync = false;
    await relaunch(tester, api, store);
    expect(api.synced.single['chest'], 101.0);
    final restored = await store.read();
    expect(restored.measurements?['chest'], 101.0);
    expect(restored.measurementsPendingSync, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an offline launch keeps newer unsynced values on this phone', (
    tester,
  ) async {
    final api = _FitApi()..failSync = true;
    final store = await openApp(tester, api);
    await openMeasurements(tester);
    await tester.enterText(field('Chest / bust *'), '101');
    await submitForm(tester);

    await relaunch(tester, api, store);
    final restored = await store.read();
    expect(restored.measurements?['chest'], 101.0);
    expect(restored.sizeLabel, 'L');
    expect(restored.measurementsPendingSync, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a changed account height drops stale unsynced values', (
    tester,
  ) async {
    final api = _FitApi()..failSync = true;
    final store = await openApp(tester, api);
    await openMeasurements(tester);
    await tester.enterText(field('Chest / bust *'), '101');
    await submitForm(tester);

    api.serverHeight = 172;
    await relaunch(tester, api, store);
    final restored = await store.read();
    expect(restored.heightCm, 172);
    expect(restored.measurements?['chest'], isNot(101.0));
    expect(restored.measurementsPendingSync, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a scan whose size fails never keeps the old size', (
    tester,
  ) async {
    final api = _FitApi()..failSize = true;
    final store = await openApp(tester, api);
    await scanFromGallery(tester);

    expect(api.synced.single['chest'], 110.0);
    expect(api.syncedSizes.single, isNull);
    final restored = await store.read();
    expect(restored.measurements?['chest'], 110.0);
    expect(restored.sizeLabel, isNull);
    expect(find.textContaining('size could not be calculated'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FitApi extends SeamlyApi {
  bool failSize = false;
  bool failSync = false;
  double serverHeight = 165;
  bool heightConfirmed = true;
  int confirmCalls = 0;
  final synced = <Map<String, double>>[];
  final syncedSizes = <String?>[];

  @override
  Future<Map<String, dynamic>> fetchAccountProfile({
    required String token,
  }) async => {
    'name': 'Test Person',
    'email': 'person@example.com',
    'height_cm': serverHeight,
    'height_confirmed': heightConfirmed,
    'avatar_base64': null,
    'latest_measurements': serverHeight == 165 ? _saved : null,
    'size_label': serverHeight == 165 ? 'M' : null,
  };

  @override
  Future<Map<String, dynamic>> updateAccountProfile({
    required String token,
    required String name,
    required double heightCm,
    String? avatarBase64,
    bool updateAvatar = false,
  }) async {
    confirmCalls++;
    heightConfirmed = true;
    serverHeight = heightCm;
    return fetchAccountProfile(token: token);
  }

  @override
  Future<Map<String, dynamic>> recommendSize({
    required Map<String, double> measurements,
    required String fitPreference,
  }) async {
    if (failSize) throw const ApiException('Sizing is offline.');
    return {
      'recommended_size': 'L',
      'confidence': 0.8,
      'alternatives': [
        {'label': 'L', 'probability': 0.8},
      ],
      'fit_notes': ['Test note'],
      'disclaimer': 'Test disclaimer',
    };
  }

  @override
  Future<Map<String, dynamic>> saveAccountMeasurements({
    required String token,
    required Map<String, double> measurements,
    String? sizeLabel,
    double? scanConfidence,
  }) async {
    if (failSync) throw const ApiException('Account sync is offline.');
    synced.add(measurements);
    syncedSizes.add(sizeLabel);
    return {
      'name': 'Test Person',
      'email': 'person@example.com',
      'height_cm': serverHeight,
      'avatar_base64': null,
      'latest_measurements': measurements,
      'size_label': sizeLabel,
    };
  }

  @override
  Future<Map<String, dynamic>> analyzeBodyPhoto({
    required Uint8List imageBytes,
    required double referenceHeightCm,
  }) async => {
    'person_detected': true,
    'scan_confidence': 0.85,
    'image_quality': 0.9,
    'measurements': {
      'height': 165.0,
      'chest': 110.0,
      'waist': 90.0,
      'hip': 112.0,
    },
    'displayable_measurements': ['chest', 'waist', 'hip'],
    'quality_warnings': <String>[],
    'validation_status': 'Estimated measurements',
    'disclaimer': 'Confirm with a tape measure.',
  };

  @override
  Future<Map<String, dynamic>> analyzeAppearancePhoto({
    required Uint8List imageBytes,
  }) async => {
    'color_season': 'Soft Autumn',
    'palette': ['#9C7253', '#7A836C', '#DCB38A'],
    'metals': ['Gold'],
    'confidence': 0.8,
    'lighting_quality': 0.85,
    'complexion_direction': 'Warm',
  };

  @override
  Future<Map<String, dynamic>> fetchHomeWeather({
    required String city,
    String? sizeLabel,
    String? colorSeason,
  }) async => throw const ApiException('No test weather');

  @override
  Future<Map<String, dynamic>> fetchShopProducts({int limit = 40}) async => {
    'items': <dynamic>[],
    'sources': <dynamic>[],
    'catalog_mode': 'setup_required',
    'disclosure': 'Test feed',
  };
}

class _NoCameraPlatform extends CameraPlatform {
  @override
  Future<List<CameraDescription>> availableCameras() async => [];
}

class _PhotoPicker extends ImagePickerPlatform {
  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async => XFile.fromData(_photo);
}
