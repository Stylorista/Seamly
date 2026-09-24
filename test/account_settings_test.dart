import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:seamly/app.dart';
import 'package:seamly/features/camera_measurement_screen.dart';
import 'package:seamly/services/session_store.dart';
import 'package:seamly/services/seamly_api.dart';
import 'package:seamly/widgets/account_avatar.dart';

const _pixel =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a7l8AAAAASUVORK5CYII=';
const _initial = SessionState(
  authenticated: true,
  welcomeCompleted: true,
  token: 'account-token',
  email: 'person@example.com',
  name: 'Test Person',
  heightCm: 165,
  measurements: {'height': 165, 'chest': 96, 'waist': 78, 'hip': 104},
  sizeLabel: 'M',
);

void main() {
  Future<MemorySessionStore> openAccount(
    WidgetTester tester,
    _AccountApi api, {
    Size viewport = const Size(390, 844),
  }) async {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = MemorySessionStore(initialState: _initial);
    await tester.pumpWidget(SeamlyApp(api: api, sessionStore: store));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('header-account')));
    await tester.pumpAndSettle();
    expect(find.text('My account'), findsOneWidget);
    return store;
  }

  testWidgets('header profile saves real height and resets stale scan values', (
    tester,
  ) async {
    final api = _AccountApi();
    final store = await openAccount(tester, api);
    await tester.enterText(
      find.byKey(const ValueKey('account-name')),
      'Updated Person',
    );
    await tester.enterText(
      find.byKey(const ValueKey('account-height')),
      '178.5',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('account-save')));
    await tester.tap(find.byKey(const ValueKey('account-save')));
    await tester.pumpAndSettle();
    expect(api.height, 178.5);
    expect((await store.read()).heightCm, 178.5);
    expect((await store.read()).measurements, isNull);
    expect((await store.read()).sizeLabel, isNull);
    await tester.pageBack();
    await tester.pumpAndSettle();
    final scanner = tester.widget<CameraMeasurementScreen>(
      find.byType(CameraMeasurementScreen, skipOffstage: false),
    );
    expect(scanner.referenceHeightCm, 178.5);
    expect(find.textContaining('Size M saved'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid height and failed saves do not alter cached account', (
    tester,
  ) async {
    final api = _AccountApi()..failSave = true;
    final store = await openAccount(tester, api);
    await tester.enterText(find.byKey(const ValueKey('account-height')), '0');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('account-save')));
    await tester.tap(find.byKey(const ValueKey('account-save')));
    await tester.pumpAndSettle();
    expect(
      find.text('Enter your actual height from 120 to 230 cm.'),
      findsOneWidget,
    );
    expect(api.saveCalls, 0);
    await tester.enterText(find.byKey(const ValueKey('account-height')), '176');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('account-save')));
    await tester.tap(find.byKey(const ValueKey('account-save')));
    await tester.pumpAndSettle();
    expect(find.text('Save failed for test.'), findsOneWidget);
    expect((await store.read()).heightCm, 165);
  });

  testWidgets('chosen picture persists to account and appears in header', (
    tester,
  ) async {
    final previous = ImagePickerPlatform.instance;
    final picker = _ProfilePicker();
    ImagePickerPlatform.instance = picker;
    addTearDown(() => ImagePickerPlatform.instance = previous);
    final api = _AccountApi();
    final store = await openAccount(tester, api);
    await tester.tap(find.byKey(const ValueKey('account-change-photo')));
    await tester.pumpAndSettle();
    expect(api.avatar, isNull); // Choosing alone does not upload the picture.
    await tester.ensureVisible(find.byKey(const ValueKey('account-save')));
    await tester.tap(find.byKey(const ValueKey('account-save')));
    await tester.pumpAndSettle();
    expect(api.avatar, _pixel);
    expect((await store.read()).avatarBase64, _pixel);
    await tester.pageBack();
    await tester.pumpAndSettle();
    final avatar = tester.widget<AccountAvatar>(
      find.descendant(
        of: find.byKey(const ValueKey('header-account')),
        matching: find.byType(AccountAvatar),
      ),
    );
    expect(avatar.base64Photo, _pixel);
    await tester.tap(find.byKey(const ValueKey('header-account')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove photo'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('account-save')));
    await tester.tap(find.byKey(const ValueKey('account-save')));
    await tester.pumpAndSettle();
    expect(api.avatar, isNull);
    expect((await store.read()).avatarBase64, isNull);
    expect(tester.takeException(), isNull);
  });

  for (final offline in [false, true]) {
    testWidgets(
      'logout clears account and ignores late refresh (offline: $offline)',
      (tester) async {
        final api = _AccountApi()..offlineLogout = offline;
        api.refresh = Completer<Map<String, dynamic>>();
        final store = await openAccount(tester, api);
        await tester.ensureVisible(
          find.byKey(const ValueKey('account-logout')),
        );
        await tester.tap(find.byKey(const ValueKey('account-logout')));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Log out'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('sign-in-button')), findsOneWidget);
        expect(api.logoutCalls, 1);
        api.refresh!.complete(api.profile);
        await tester.pumpAndSettle();
        final saved = await store.read();
        expect(saved.authenticated, isFalse);
        expect(saved.token, isNull);
        expect(saved.heightCm, isNull);
        expect(saved.avatarBase64, isNull);
        expect(saved.measurements, isNull);
        expect(saved.name, isNull);
        expect(find.byKey(const ValueKey('header-account')), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'narrow large-text account editor keeps save and logout reachable',
    (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openAccount(tester, _AccountApi(), viewport: const Size(320, 568));
      await tester.ensureVisible(find.byKey(const ValueKey('account-save')));
      await tester.ensureVisible(find.byKey(const ValueKey('account-logout')));
      expect(
        tester.getSize(find.byKey(const ValueKey('account-logout'))).height,
        greaterThanOrEqualTo(48),
      );
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'preferences restore picture and height, then remove account data on logout',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = PreferencesSessionStore();
      await store.saveAccountSession(
        const AccountSession(
          token: 'token',
          email: 'person@example.com',
          heightCm: 178,
          name: 'Person',
          avatarBase64: _pixel,
        ),
      );
      final restored = await PreferencesSessionStore().read();
      expect(restored.avatarBase64, _pixel);
      expect(restored.name, 'Person');
      expect(restored.heightCm, 178);
      await store.setAuthenticated(false);
      final cleared = await PreferencesSessionStore().read();
      expect(cleared.token, isNull);
      expect(cleared.avatarBase64, isNull);
      expect(cleared.name, isNull);
      expect(cleared.heightCm, isNull);
    },
  );
}

class _ProfilePicker extends ImagePickerPlatform {
  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async => XFile.fromData(base64Decode(_pixel));
}

class _AccountApi extends SeamlyApi {
  String name = 'Test Person';
  double height = 165;
  String? avatar;
  bool failSave = false;
  bool offlineLogout = false;
  int saveCalls = 0;
  int logoutCalls = 0;
  Completer<Map<String, dynamic>>? refresh;
  Map<String, dynamic> get profile => {
    'name': name,
    'email': 'person@example.com',
    'height_cm': height,
    'avatar_base64': avatar,
    'latest_measurements': height == 165 ? _initial.measurements : null,
    'size_label': height == 165 ? 'M' : null,
  };
  @override
  Future<Map<String, dynamic>> fetchAccountProfile({required String token}) =>
      refresh?.future ?? Future.value(profile);
  @override
  Future<Map<String, dynamic>> updateAccountProfile({
    required String token,
    required String name,
    required double heightCm,
    String? avatarBase64,
    bool updateAvatar = false,
  }) async {
    saveCalls++;
    if (failSave) throw const ApiException('Save failed for test.');
    this.name = name;
    height = heightCm;
    if (updateAvatar) avatar = avatarBase64;
    return profile;
  }

  @override
  Future<void> logoutAccount({required String token}) async {
    logoutCalls++;
    if (offlineLogout) throw const ApiException('Offline');
  }

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
