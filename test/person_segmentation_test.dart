import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:seamly/services/person_segmentation.dart';

void main() {
  test('override result is returned untouched', () async {
    final cleaned = Uint8List.fromList([1, 2, 3]);
    final service = PersonSegmentation(
      isolateForeground: (_) async => cleaned,
    );
    expect(await service.isolatePerson(Uint8List.fromList([9])), same(cleaned));
  });

  test('override returning null falls back to original', () async {
    final service = PersonSegmentation(
      isolateForeground: (_) async => null,
    );
    expect(await service.isolatePerson(Uint8List.fromList([9])), isNull);
  });

  test('unavailable native segmenter falls back gracefully', () async {
    // No platform channel in unit tests: must return null, never throw.
    final service = PersonSegmentation();
    expect(
      await service.isolatePerson(Uint8List.fromList(List.filled(200, 7))),
      isNull,
    );
  });
}
