import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:seamly/services/session_store.dart';

void main() {
  test('profile with null optional measurements decodes', () {
    final session = AccountSession.fromApi({
      'token': 'token',
      'profile': {
        'email': 'person@example.com',
        'height_cm': 165,
        'latest_measurements': {
          'height': 165.0,
          'neck': null,
          'chest': 94.0,
          'waist': 77.0,
          'hip': 103.0,
          'inseam': null,
        },
        'size_label': 'M',
      },
    });
    expect(session.measurements, {
      'height': 165.0,
      'chest': 94.0,
      'waist': 77.0,
      'hip': 103.0,
    });
  });

  test('missing measurements stay null', () {
    expect(measurementsFromJson(null), isNull);
    expect(measurementsFromJson('not a map'), isNull);
  });

  test(
    'pending sync survives restart and is cleared by sync or logout',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = PreferencesSessionStore();
      await store.saveMeasurementProfile(
        {'height': 165, 'chest': 101},
        'L',
        pendingSync: true,
      );
      expect(
        (await PreferencesSessionStore().read()).measurementsPendingSync,
        isTrue,
      );
      await store.saveMeasurementProfile({'height': 165, 'chest': 101}, 'L');
      expect(
        (await PreferencesSessionStore().read()).measurementsPendingSync,
        isFalse,
      );
      await store.saveMeasurementProfile(
        {'height': 165, 'chest': 101},
        'L',
        pendingSync: true,
      );
      await store.setAuthenticated(false);
      expect(
        (await PreferencesSessionStore().read()).measurementsPendingSync,
        isFalse,
      );
    },
  );

  test('only an explicit false marks the height unconfirmed', () {
    AccountSession session(Map<String, dynamic> extra) =>
        AccountSession.fromApi({
          'token': 'token',
          'profile': {
            'email': 'person@example.com',
            'height_cm': 165,
            ...extra,
          },
        });
    expect(session({'height_confirmed': false}).heightConfirmed, isFalse);
    expect(session({'height_confirmed': true}).heightConfirmed, isTrue);
    expect(session({}).heightConfirmed, isTrue);
  });

  test('a session cached before the height flag does not lock scans', () async {
    SharedPreferences.setMockInitialValues({
      'seamly.authenticated': true,
      'seamly.account_token': 'token',
      'seamly.account_email': 'person@example.com',
      'seamly.height_cm': 175.0,
    });
    expect((await PreferencesSessionStore().read()).heightConfirmed, isTrue);
    final store = PreferencesSessionStore();
    await store.saveAccountSession(
      const AccountSession(
        token: 'token',
        email: 'person@example.com',
        heightCm: 175,
      ),
    );
    expect((await PreferencesSessionStore().read()).heightConfirmed, isFalse);
  });
}
