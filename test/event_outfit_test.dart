import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:seamly/features/home_screen.dart';
import 'package:seamly/services/seamly_api.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('event planner card sits above the weather', (tester) async {
    _useViewport(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          api: _FakePlanApi(),
          onSelectFeature: (_) {},
          sizeLabel: null,
          colorSeason: null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('event-outfit-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('event-outfit-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('event-outfit-plan')), findsOneWidget);
    // Weather card still renders below.
    expect(find.text('Change city'), findsOneWidget);
  });

  testWidgets('empty event shows a hint instead of calling the api', (
    tester,
  ) async {
    _useViewport(tester);
    final api = _FakePlanApi();
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          api: api,
          onSelectFeature: (_) {},
          sizeLabel: null,
          colorSeason: null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const ValueKey('event-outfit-plan')));
    await tester.tap(find.byKey(const ValueKey('event-outfit-plan')));
    await tester.pumpAndSettle();

    expect(find.text('Tell us the event first (2+ characters).'), findsOneWidget);
    expect(api.planCalls, 0);
  });

  testWidgets('event without a date asks for the date', (tester) async {
    _useViewport(tester);
    final api = _FakePlanApi();
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          api: api,
          onSelectFeature: (_) {},
          sizeLabel: null,
          colorSeason: null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('event-outfit-field')),
      'garden wedding',
    );
    await tester.tap(find.byKey(const ValueKey('event-outfit-plan')));
    await tester.pumpAndSettle();

    expect(find.text('Pick the date of your event.'), findsOneWidget);
    expect(api.planCalls, 0);
  });

  testWidgets('full flow renders the planned outfit', (tester) async {    _useViewport(tester);
    final api = _FakePlanApi();
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          api: api,
          onSelectFeature: (_) {},
          sizeLabel: 'M',
          colorSeason: 'Autumn',
          measurements: const {'height': 165, 'chest': 94, 'waist': 77, 'hip': 103},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('event-outfit-field')),
      'garden wedding',
    );
    await tester.tap(find.byKey(const ValueKey('event-outfit-date')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const ValueKey('event-outfit-plan')));
    await tester.tap(find.byKey(const ValueKey('event-outfit-plan')));
    await tester.pumpAndSettle();

    expect(api.planCalls, 1);
    expect(api.lastEventText, 'garden wedding');
    expect(api.lastSizeLabel, 'M');
    expect(find.byKey(const ValueKey('event-outfit-result')), findsOneWidget);
    expect(find.textContaining('Garden Wedding look'), findsOneWidget);
    expect(find.textContaining('breathable'), findsOneWidget);
    expect(find.byKey(const ValueKey('event-outfit-inspiration')), findsOneWidget);
    expect(find.text('Style inspiration'), findsOneWidget);
    expect(
      find.text('Photos for ideas — not actual products.'),
      findsOneWidget,
    );
    expect(find.textContaining('Test Shooter'), findsOneWidget);
  });

  testWidgets('brief weather blip retries once automatically', (tester) async {
    _useViewport(tester);
    final api = _FakePlanApi()..failFirstPlanCall = true;
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          api: api,
          onSelectFeature: (_) {},
          sizeLabel: null,
          colorSeason: null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('event-outfit-field')),
      'office holiday party',
    );
    await tester.tap(find.byKey(const ValueKey('event-outfit-date')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const ValueKey('event-outfit-plan')));
    await tester.tap(find.byKey(const ValueKey('event-outfit-plan')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    expect(api.planCalls, 2);
    expect(find.byKey(const ValueKey('event-outfit-result')), findsOneWidget);
    expect(find.textContaining('temporarily unavailable'), findsNothing);
  });
}

class _FakePlanApi extends SeamlyApi {
  int planCalls = 0;
  String? lastEventText;
  String? lastSizeLabel;
  bool failFirstPlanCall = false;

  @override
  Future<Map<String, dynamic>> fetchHomeWeather({
    required String city,
    String? sizeLabel,
    String? colorSeason,
  }) async {
    return {
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
        'precipitation_probability': 20,
        'uv_index_max': 7.2,
        'weather_code': 2,
        'condition': 'Partly cloudy',
      },
      'fashion': [
        {
          'kind': 'outfit',
          'title': 'Airy warm-weather layers',
          'reason': 'Breathable pieces for today.',
        },
      ],
      'source': 'Open-Meteo forecast',
    };
  }

  @override
  Future<Map<String, dynamic>> planEventOutfit({
    required String eventText,
    required String city,
    required String eventDate,
    String? eventTime,
    String? style,
    String? sizeLabel,
    String? colorSeason,
    Map<String, double>? measurements,
  }) async {
    planCalls++;
    lastEventText = eventText;
    lastSizeLabel = sizeLabel;
    if (failFirstPlanCall && planCalls == 1) {
      throw const ApiException(
        'Live weather is temporarily unavailable. Please try again.',
      );
    }
    return {
      'event_text': eventText,
      'occasion': 'event',
      'style_used': 'classic',
      'city': city,
      'location': city,
      'event_datetime': '${eventDate}T${eventTime ?? '18:00'}',
      'timezone': 'Asia/Manila',
      'weather': {
        'temperature_c': 31.0,
        'feels_like_c': 34.0,
        'condition': 'Partly cloudy',
        'rain_probability': 10,
        'wind_kmh': 12.0,
        'uv_index_max': 7.0,
        'is_forecast': true,
      },
      'title': 'Garden Wedding look: Warm-weather occasion set',
      'summary': 'Elegant proportions with breathable fabrics.',
      'pieces': ['draped midi dress', 'low heeled sandals'],
      'fabrics': ['silk crepe', 'linen satin'],
      'palette': ['#B65C3A'],
      'styling_notes': ['Match metal accessories to your color profile.'],
      'fit_notes': [],
      'reasons': ['34° feels-like heat calls for breathable linen.'],
      'confidence': 0.8,
      'inspiration_images': [
        {
          'image_url': 'https://images.pexels.com/photo-one.jpg',
          'photographer': 'Test Shooter',
          'photographer_url': 'https://www.pexels.com/test',
          'alt': 'Classic outfit inspiration',
        },
        {
          'image_url': 'https://images.pexels.com/photo-two.jpg',
          'photographer': 'Second Lens',
          'photographer_url': 'https://www.pexels.com/second',
          'alt': 'Evening outfit inspiration',
        },
      ],
      'model_version': 'event-outfit-0.1.0',
      'disclaimer': 'Forecast-based suggestion.',
    };
  }
}

void _useViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(430, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
