import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:seamly/features/fashion_news_screen.dart';
import 'package:seamly/services/seamly_api.dart';
import 'package:seamly/services/session_store.dart';

const _storyUrl = 'https://example.com/fashion/story';

void main() {
  late List<String> copied;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    copied = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pumpNews(
    WidgetTester tester, {
    Future<void> Function(String, String)? share,
  }) async {
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FashionNewsScreen(
            api: _NewsApi(),
            shareStory: share ?? (_, _) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapAction(WidgetTester tester, String label) async {
    final action = find.text(label);
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
  }

  testWidgets('Share opens the share sheet with the story link', (
    tester,
  ) async {
    final shared = <String>[];
    await pumpNews(tester, share: (text, _) async => shared.add(text));
    await tapAction(tester, 'Share');
    expect(shared.single, contains(_storyUrl));
    expect(shared.single, contains('Runway report'));
    expect(copied, isEmpty);
  });

  testWidgets('Share copies the link when the share sheet fails', (
    tester,
  ) async {
    await pumpNews(
      tester,
      share: (_, _) async => throw PlatformException(code: 'unavailable'),
    );
    await tapAction(tester, 'Share');
    expect(copied, [_storyUrl]);
    expect(find.textContaining('Link copied'), findsOneWidget);
  });

  testWidgets('a like is saved on this phone and not added to source counts', (
    tester,
  ) async {
    await pumpNews(tester);
    await tapAction(tester, 'Like');
    expect(find.text('Liked'), findsOneWidget);
    expect(find.text('320'), findsOneWidget);
    expect(find.text('321'), findsNothing);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getStringList(likedStoriesPreferenceKey), ['story-1']);

    // A fresh screen (as after relaunch) restores the like.
    await tester.pumpWidget(const SizedBox());
    await pumpNews(tester);
    expect(find.text('Liked'), findsOneWidget);
  });

  test('logout clears saved likes', () async {
    SharedPreferences.setMockInitialValues({
      likedStoriesPreferenceKey: ['story-1'],
    });
    await PreferencesSessionStore().setAuthenticated(false);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getStringList(likedStoriesPreferenceKey), isNull);
  });
}

class _NewsApi extends SeamlyApi {
  @override
  Future<Map<String, dynamic>> fetchFashionNews({
    required String category,
    int limit = 16,
  }) async => {
    'category': category,
    'fetched_at': DateTime.now().toUtc().toIso8601String(),
    'items': [
      {
        'id': 'story-1',
        'title': 'Runway report',
        'summary': 'A current fashion story.',
        'url': _storyUrl,
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
