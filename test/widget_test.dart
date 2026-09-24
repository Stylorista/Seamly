import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seamly/app.dart';
import 'package:seamly/features/home_screen.dart';
import 'package:seamly/features/shop_screen.dart';
import 'package:seamly/services/session_store.dart';
import 'package:seamly/services/seamly_api.dart';

void main() {
  testWidgets('shows the one-second loader only when the app starts', (
    tester,
  ) async {
    _useMobileTestViewport(tester);
    await tester.pumpWidget(SeamlyApp(sessionStore: MemorySessionStore()));

    expect(find.byKey(const ValueKey('launch-logo')), findsOneWidget);
    expect(find.byKey(const ValueKey('sign-in-button')), findsNothing);

    await tester.pump(const Duration(milliseconds: 900));
    expect(find.byKey(const ValueKey('launch-logo')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sign-in-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('launch-logo')), findsNothing);
  });

  testWidgets('signs in a returning account and opens Home', (tester) async {
    _useMobileTestViewport(tester);
    final sessionStore = MemorySessionStore();
    await tester.pumpWidget(
      SeamlyApp(api: _FakeNewsApi(), sessionStore: sessionStore),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('See Your Size.\nKnow Your Style.\nShop With Confidence.'),
      findsOneWidget,
    );
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Create new account'), findsOneWidget);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'style@example.com');
    await tester.enterText(fields.at(1), 'fashion123');
    await tester.ensureVisible(find.byKey(const ValueKey('sign-in-button')));
    await tester.tap(find.byKey(const ValueKey('sign-in-button')));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(find.text('Scan your fit'), findsOneWidget);
  });

  testWidgets('returning users open Home directly', (tester) async {
    _useMobileTestViewport(tester);
    final sessionStore = MemorySessionStore(
      initialState: const SessionState(
        authenticated: true,
        welcomeCompleted: true,
        token: 'saved-test-token',
        email: 'style@example.com',
        heightCm: 165,
      ),
    );

    await tester.pumpWidget(
      SeamlyApp(api: _FakeNewsApi(), sessionStore: sessionStore),
    );
    await tester.pumpAndSettle();

    expect(find.text('Scan your fit'), findsOneWidget);
    expect(find.text('Welcome to'), findsNothing);
    expect(find.byKey(const ValueKey('sign-in-button')), findsNothing);
  });

  testWidgets('switches to create-account mode', (tester) async {
    _useMobileTestViewport(tester);
    await tester.pumpWidget(SeamlyApp(sessionStore: MemorySessionStore()));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Create new account'));
    await tester.tap(find.text('Create new account'));
    await tester.pumpAndSettle();

    expect(find.text('Create your profile'), findsOneWidget);
    expect(find.text('Seamly'), findsNothing);
    expect(
      find.text('See Your Size.\nKnow Your Style.\nShop With Confidence.'),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('auth-logo')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('auth-logo'))).width,
      greaterThanOrEqualTo(220),
    );
    expect(find.text('Create account'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(4));
    expect(find.text('Phone number · optional:'), findsNothing);
    expect(find.text('Height for camera calibration:'), findsNothing);
    expect(
      find.byKey(const ValueKey('terms-conditions-button')),
      findsOneWidget,
    );
  });

  testWidgets('auth actions stay readable with larger system text', (
    tester,
  ) async {
    _useMobileTestViewport(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(SeamlyApp(sessionStore: MemorySessionStore()));
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const ValueKey('switch-auth-mode-button')),
    );
    await tester.tap(find.byKey(const ValueKey('switch-auth-mode-button')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('create-button')));

    expect(
      tester.getSize(find.byKey(const ValueKey('create-button'))).height,
      greaterThanOrEqualTo(56),
    );
    expect(find.text('Create account'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home keeps daily essentials and reveals forecast on demand', (
    tester,
  ) async {
    _useMobileTestViewport(tester);
    await tester.pumpWidget(
      SeamlyApp(
        api: _FakeNewsApi(),
        initiallyAuthenticated: true,
        sessionStore: MemorySessionStore(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Today · Partly cloudy'), findsOneWidget);
    expect(find.textContaining('Tomorrow ·'), findsNothing);
    expect(find.text('Our Partners'), findsNothing);
    expect(find.text('Your relevant fashion'), findsNothing);
    expect(find.text('What to wear'), findsOneWidget);
    expect(find.text('Airy warm-weather layers'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('home-weather-details')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Tomorrow · Rain showers'), findsOneWidget);
  });

  testWidgets('home supports large text on a narrow screen', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 568),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: HomeScreen(
              api: _FakeNewsApi(),
              onSelectFeature: (_) {},
              sizeLabel: null,
              colorSeason: null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Forecast details'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forecast details'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Tomorrow · Rain showers'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop scan round trip preserves Home and city state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      SeamlyApp(
        api: _FakeNewsApi(),
        initiallyAuthenticated: true,
        sessionStore: MemorySessionStore(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change city'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Cebu');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final homeState = tester.state(find.byType(HomeScreen));
    await tester.ensureVisible(find.byKey(const ValueKey('home-start-scan')));
    await tester.tap(find.byKey(const ValueKey('home-start-scan')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-nav-Shop')), findsNothing);
    await tester.tap(find.byTooltip('Back home'));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(HomeScreen)), same(homeState));
    expect(find.textContaining('Cebu'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens the shopping workflow for an authenticated session', (
    tester,
  ) async {
    await tester.pumpWidget(
      SeamlyApp(
        api: _FakeNewsApi(),
        initiallyAuthenticated: true,
        sessionStore: MemorySessionStore(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Seamly'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('home-nav-Shop')));
    await tester.pumpAndSettle();

    expect(find.text('Shop'), findsOneWidget);
    expect(find.text('Unlock AI fit ranking'), findsOneWidget);
    expect(find.text('FROM THE SOURCE'), findsOneWidget);
    expect(find.text('Product source status'), findsOneWidget);

    await tester.tap(find.text('Measurements'));
    await tester.pumpAndSettle();

    expect(
      find.text('Measurements that fashion actually uses'),
      findsOneWidget,
    );
  });

  testWidgets('shop personalizes picks from AI scan measurements', (
    tester,
  ) async {
    _useMobileTestViewport(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: ShopScreen(
          api: _FakeNewsApi(),
          measurements: const {
            'height': 165,
            'chest': 94,
            'waist': 77,
            'hip': 103,
          },
          sizeLabel: null,
          colorSeason: 'Autumn',
          onOpenScanner: _ignore,
          onOpenMeasurements: _ignore,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your AI fit ranking is ready'), findsOneWidget);
    expect(find.textContaining('Suggested size L'), findsOneWidget);
    expect(find.text('For your size L'), findsWidgets);
    expect(find.text('Open exact listing'), findsOneWidget);
  });

  testWidgets('news tab filters the live-style feed by fashion category', (
    tester,
  ) async {
    _useMobileTestViewport(tester);
    final api = _FakeNewsApi();
    await tester.pumpWidget(
      SeamlyApp(
        api: api,
        initiallyAuthenticated: true,
        sessionStore: MemorySessionStore(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('home-nav-News')));
    await tester.pumpAndSettle();

    expect(find.text('Fashion Feed'), findsOneWidget);
    expect(find.text('ALL fashion update'), findsOneWidget);
    expect(find.text('Google News'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('news-category-y2k')));
    await tester.pumpAndSettle();

    expect(api.lastCategory, 'y2k');
    expect(find.text('Y2K fashion update'), findsOneWidget);
  });

  testWidgets('profile tab opens the curated feature hub', (tester) async {
    _useMobileTestViewport(tester);
    await tester.pumpWidget(
      SeamlyApp(
        initiallyAuthenticated: true,
        sessionStore: MemorySessionStore(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('home-nav-Profile')));
    await tester.pumpAndSettle();

    expect(find.text('Your style snapshot'), findsOneWidget);
    expect(find.text('Will it Fit?'), findsOneWidget);
    expect(find.text('In-the-Weather'), findsOneWidget);
    expect(find.text('Accessories'), findsOneWidget);
    expect(find.text('Color Analysis'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('profile-weather')));
    await tester.pumpAndSettle();
    expect(find.text('Today’s context'), findsOneWidget);
  });

  testWidgets('shows scan instructions before opening the body camera', (
    tester,
  ) async {
    _useMobileTestViewport(tester);
    final sessionStore = MemorySessionStore(
      initialState: const SessionState(
        authenticated: true,
        welcomeCompleted: true,
        token: 'scan-test-token',
        email: 'style@example.com',
        heightCm: 165,
      ),
    );
    await tester.pumpWidget(SeamlyApp(sessionStore: sessionStore));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('home-nav-Scan')));
    await tester.pump();

    expect(find.text('Styling your next look…'), findsNothing);
    expect(find.text('Prepare for your body scan'), findsOneWidget);
    expect(find.text('Move to a well-lit area'), findsOneWidget);
    expect(find.text('Show your full body'), findsOneWidget);
    final startButton = find.byKey(const ValueKey('start-guided-scan-button'));
    expect(tester.widget<FilledButton>(startButton).onPressed, isNull);

    await tester.ensureVisible(
      find.byKey(const ValueKey('scan-preparation-checkbox')),
    );
    await tester.tap(find.byKey(const ValueKey('scan-preparation-checkbox')));
    await tester.ensureVisible(
      find.byKey(const ValueKey('scan-consent-checkbox')),
    );
    await tester.tap(find.byKey(const ValueKey('scan-consent-checkbox')));
    await tester.pump();

    expect(tester.widget<FilledButton>(startButton).onPressed, isNotNull);
    await tester.ensureVisible(startButton);
    await tester.tap(startButton);
    await tester.pump();

    expect(find.text('Even light · Head to toe in frame'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('camera-preview-surface'))),
      const Size(430, 900),
    );
    expect(find.byTooltip('Take photo'), findsOneWidget);
  });
}

void _ignore() {}

class _FakeNewsApi extends SeamlyApi {
  String? lastCategory;

  @override
  Future<Map<String, dynamic>> loginAccount({
    required String email,
    required String password,
  }) async {
    return {
      'token': 'test-session-token',
      'is_new_account': false,
      'profile': {
        'id': 'test-user',
        'name': 'Style Tester',
        'email': email,
        'height_cm': 165.0,
        'latest_measurements': null,
        'size_label': null,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> fetchAccountProfile({
    required String token,
  }) async {
    return {
      'id': 'test-user',
      'name': 'Style Tester',
      'email': 'style@example.com',
      'height_cm': 165.0,
      'latest_measurements': null,
      'size_label': null,
    };
  }

  @override
  Future<Map<String, dynamic>> fetchFashionNews({
    required String category,
    int limit = 16,
  }) async {
    lastCategory = category;
    return {
      'category': category,
      'fetched_at': DateTime.now().toUtc().toIso8601String(),
      'items': [
        {
          'id': 'post-$category',
          'title': '${category.toUpperCase()} fashion update',
          'summary': 'A current fashion story selected for $category style.',
          'url': 'https://example.com/fashion/$category',
          'image_url': null,
          'publisher': 'Fashion Test Daily',
          'platform': 'Google News',
          'category': category,
          'published_at': DateTime.now().toUtc().toIso8601String(),
          'like_count': 320,
          'comment_count': 41,
        },
      ],
      'sources': [
        {'name': 'Google News', 'connected': true, 'note': 'Live RSS stories'},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> fetchHomeWeather({
    required String city,
    String? sizeLabel,
    String? colorSeason,
  }) async {
    return _homeWeatherResponse(city);
  }

  @override
  Future<Map<String, dynamic>> fetchShopProducts({int limit = 40}) async {
    return {
      'fetched_at': DateTime.now().toUtc().toIso8601String(),
      'catalog_mode': 'source_feed',
      'disclosure':
          'Every photo is supplied with the exact product record and opens that listing.',
      'items': [
        {
          'id': 'lazada-wrap-dress',
          'title': 'Source-linked wrap midi dress',
          'category': 'Dresses',
          'marketplace': 'Lazada',
          'seller': 'Test fashion seller',
          'product_url': 'https://www.lazada.com.ph/products/test-i123.html',
          'image_url': 'https://my-live-02.slatic.net/p/test.jpg',
          'image_source_url': 'https://my-live-02.slatic.net/p/test.jpg',
          'price_label': '₱1,290',
          'sizes': ['S', 'M', 'L'],
          'color_seasons': ['Autumn'],
          'source_updated_at': DateTime.now().toUtc().toIso8601String(),
        },
      ],
      'sources': [
        {
          'name': 'Shopee',
          'connected': false,
          'item_count': 0,
          'note': 'Connect an approved seller or affiliate product feed',
        },
        {
          'name': 'Lazada',
          'connected': true,
          'item_count': 1,
          'note': '1 exact source-linked listing',
        },
        {
          'name': 'Temu',
          'connected': false,
          'item_count': 0,
          'note': 'Connect an approved seller or affiliate product feed',
        },
      ],
    };
  }
}

Map<String, dynamic> _homeWeatherResponse(String city) => {
  'location': city,
  'region': 'Metro Manila',
  'country': 'Philippines',
  'timezone': 'Asia/Manila',
  'updated_at': DateTime.now().toUtc().toIso8601String(),
  'current': {
    'temperature_c': 30.0,
    'apparent_temperature_c': 35.0,
    'humidity_percent': 74,
    'wind_kmh': 12.0,
    'weather_code': 2,
    'condition': 'Partly cloudy',
    'is_day': true,
  },
  'tomorrow': {
    'date': '2026-09-04',
    'temperature_max_c': 31.0,
    'temperature_min_c': 25.0,
    'apparent_temperature_max_c': 36.0,
    'precipitation_probability': 58,
    'uv_index_max': 7.2,
    'weather_code': 80,
    'condition': 'Rain showers',
  },
  'fashion': [
    {
      'kind': 'outfit',
      'title': 'Airy warm-weather layers',
      'reason': 'Breathable pieces for today.',
    },
    {
      'kind': 'weather',
      'title': 'Rain-ready finishing pieces',
      'reason': 'Carry a compact umbrella.',
    },
    {
      'kind': 'fit',
      'title': 'Your fit starting point',
      'reason': 'Complete a body scan.',
    },
    {
      'kind': 'color',
      'title': 'Your color accent',
      'reason': 'Add your saved color profile.',
    },
  ],
  'source': 'Open-Meteo forecast',
};

void _useMobileTestViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(430, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
