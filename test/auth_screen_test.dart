import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seamly/features/auth_screen.dart';
import 'package:seamly/services/seamly_api.dart';
import 'package:seamly/services/session_store.dart';

void main() {
  Future<void> pumpAuth(
    WidgetTester tester,
    _GoogleApi api,
    void Function(AccountSession) onSession,
  ) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: AuthScreen(
          api: api,
          signInWithGoogle: () async => 'google-id-token',
          onAuthenticated: (session, _) async => onSession(session),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapGoogle(WidgetTester tester) async {
    final button = find.byKey(const ValueKey('google-sign-in-button'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('native Google sign-in exchanges the token with the API', (
    tester,
  ) async {
    final api = _GoogleApi();
    AccountSession? signedIn;
    await pumpAuth(tester, api, (session) => signedIn = session);
    await tapGoogle(tester);
    expect(api.exchangedTokens, ['google-id-token']);
    expect(signedIn?.email, 'person@example.com');
  });

  testWidgets('a failed Google exchange unlocks the button', (tester) async {
    final api = _GoogleApi()..fail = true;
    await pumpAuth(tester, api, (_) {});
    await tapGoogle(tester);
    expect(api.exchangedTokens, ['google-id-token']);
    expect(find.text('Google account could not be verified.'), findsOneWidget);
    final button = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('google-sign-in-button')),
    );
    expect(button.onPressed, isNotNull);
  });
}

class _GoogleApi extends SeamlyApi {
  final exchangedTokens = <String>[];
  bool fail = false;

  @override
  Future<Map<String, dynamic>> loginWithGoogle({required String idToken}) async {
    exchangedTokens.add(idToken);
    if (fail) throw const ApiException('Google account could not be verified.');
    return {
      'token': 'session-token',
      'is_new_account': false,
      'profile': {
        'email': 'person@example.com',
        'height_cm': 170,
        'latest_measurements': null,
      },
    };
  }
}
