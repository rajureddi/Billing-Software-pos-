import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:counterday/services/image_optimizer.dart';

void main() {
  test('ImageOptimizer compresses large image to lightweight payload', () async {
    // Generate a 1200x900 image with varied colors (like a real photo)
    final rand = Random(42);
    final testImage = img.Image(width: 1200, height: 900);
    for (var y = 0; y < 900; y++) {
      for (var x = 0; x < 1200; x++) {
        testImage.setPixelRgb(
          x,
          y,
          (x * 3 + rand.nextInt(50)) % 255,
          (y * 2 + rand.nextInt(50)) % 255,
          (x + y + rand.nextInt(50)) % 255,
        );
      }
    }
    // Encode as high-quality uncompressed/lossless BMP or PNG (simulate 1-2MB raw photo)
    final rawBmpBytes = Uint8List.fromList(img.encodeBmp(testImage));
    expect(rawBmpBytes.length, greaterThan(1024 * 1024)); // > 1MB

    final result = await ImageOptimizer.optimize(rawBmpBytes, maxDimension: 800);

    // Should be compressed to < 85KB
    expect(result.compressedBytes, lessThan(85 * 1024));
    expect(result.width, lessThanOrEqualTo(800));
    expect(result.height, lessThanOrEqualTo(800));
    expect(result.base64.isNotEmpty, true);
    expect(result.savingsPercent, greaterThan(80.0)); // > 80% saved!
    expect(result.summary, contains('saved'));

    // Verify the base64 can be decoded back
    final decodedBytes = base64Decode(result.base64);
    final reloaded = img.decodeJpg(decodedBytes);
    expect(reloaded, isNotNull);
    expect(reloaded!.width, result.width);
  });
}
