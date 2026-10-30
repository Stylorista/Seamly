import 'package:flutter_test/flutter_test.dart';
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
}
