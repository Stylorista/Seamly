import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';
import 'package:image/image.dart' as img;

/// On-device person segmentation (Google ML Kit, free, offline after install).
///
/// [isolatePerson] returns JPEG bytes with the background replaced by white
/// so the silhouette estimator sees a clean subject, or `null` when
/// segmentation is unavailable — callers must then use the original photo.
/// Web is unsupported by the plugin and always falls back.
class PersonSegmentation {
  PersonSegmentation({
    Future<Uint8List?> Function(Uint8List photoBytes)? isolateForeground,
  }) : _override = isolateForeground;

  final Future<Uint8List?> Function(Uint8List photoBytes)? _override;
  SelfieSegmenter? _segmenter;

  Future<Uint8List?> isolatePerson(Uint8List jpegBytes) async {
    final override = _override;
    if (override != null) return override(jpegBytes);
    if (kIsWeb) return null;
    try {
      final original = img.decodeImage(jpegBytes);
      if (original == null || original.width < 96 || original.height < 160) {
        return null;
      }
      final directory = await Directory.systemTemp.createTemp('seamly-seg');
      try {
        final path = '${directory.path}/input.jpg';
        await File(path).writeAsBytes(jpegBytes, flush: true);
        final segmenter = _segmenter ??= SelfieSegmenter(
          mode: SegmenterMode.single,
        );
        final mask = await segmenter.processImage(
          InputImage.fromFilePath(path),
        );
        if (mask == null) return null;
        return _compositeWhite(original, mask);
      } finally {
        try {
          await directory.delete(recursive: true);
        } catch (_) {
          // Best-effort temp cleanup.
        }
      }
    } catch (_) {
      return null;
    }
  }

  Uint8List? _compositeWhite(img.Image original, SegmentationMask mask) {
    final width = original.width;
    final height = original.height;
    if (mask.width <= 0 ||
        mask.height <= 0 ||
        mask.confidences.length < mask.width * mask.height) {
      return null;
    }
    var foreground = 0;
    for (var y = 0; y < height; y++) {
      final maskY = (y * mask.height / height).floor().clamp(0, mask.height - 1);
      for (var x = 0; x < width; x++) {
        final maskX = (x * mask.width / width).floor().clamp(0, mask.width - 1);
        if (mask.confidences[maskY * mask.width + maskX] >= 0.5) {
          foreground++;
        } else {
          original.setPixelRgba(x, y, 255, 255, 255, 255);
        }
      }
    }
    // No believable person found: keep the original photo untouched.
    if (foreground < width * height * 0.03) return null;
    return Uint8List.fromList(img.encodeJpg(original, quality: 90));
  }

  Future<void> dispose() async {
    try {
      await _segmenter?.close();
    } catch (_) {
      // Best-effort native cleanup.
    }
    _segmenter = null;
  }
}
