import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class OptimizedImage {
  final String base64;
  final int originalBytes;
  final int compressedBytes;
  final int width;
  final int height;

  const OptimizedImage({
    required this.base64,
    required this.originalBytes,
    required this.compressedBytes,
    required this.width,
    required this.height,
  });

  double get savingsPercent {
    if (originalBytes <= 0) return 0.0;
    final saved = (originalBytes - compressedBytes) / originalBytes * 100;
    return saved.clamp(0.0, 99.9);
  }

  String get summary {
    String formatBytes(int b) {
      if (b < 1024) return '$b B';
      if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
      return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    }

    return '${formatBytes(originalBytes)} → ${formatBytes(compressedBytes)} (${savingsPercent.toStringAsFixed(1)}% saved)';
  }
}

/// Professional background image optimizing engine.
/// Offloads all heavy decoding, EXIF rotation, bilinear resizing,
/// and adaptive compression to a background isolate (compute)
/// so the POS and billing UI remains 100% smooth without any lag.
class ImageOptimizer {
  /// Maximum dimension for product catalog display (retina-crisp).
  static const int defaultMaxDimension = 800;

  /// Target JPEG quality for maximum visual fidelity with minimal file footprint.
  static const int defaultQuality = 82;

  /// Optimizes raw bytes (e.g. 5MB - 10MB camera/gallery photo)
  /// into a lightweight, high-clarity base64 string (~35KB - 65KB).
  static Future<OptimizedImage> optimize(
    Uint8List rawBytes, {
    int maxDimension = defaultMaxDimension,
    int quality = defaultQuality,
  }) async {
    // Run in background isolate via Flutter compute
    return compute(
      _isolateWorker,
      _OptimizerParams(
        rawBytes: rawBytes,
        maxDimension: maxDimension,
        quality: quality,
      ),
    );
  }
}

class _OptimizerParams {
  final Uint8List rawBytes;
  final int maxDimension;
  final int quality;

  _OptimizerParams({
    required this.rawBytes,
    required this.maxDimension,
    required this.quality,
  });
}

OptimizedImage _isolateWorker(_OptimizerParams params) {
  final originalLength = params.rawBytes.length;

  // 1. Decode image from any common format (JPEG, PNG, WebP, TIFF, BMP, etc.)
  final rawDecoded = img.decodeImage(params.rawBytes);
  if (rawDecoded == null) {
    throw ArgumentError('Unsupported or corrupted image format.');
  }

  // 2. Automatically correct camera rotation using EXIF metadata
  img.Image image = img.bakeOrientation(rawDecoded);

  // 3. Compute target dimensions keeping aspect ratio
  int targetW = image.width;
  int targetH = image.height;
  final maxDim = math.max(targetW, targetH);

  if (maxDim > params.maxDimension) {
    final scale = params.maxDimension / maxDim;
    targetW = (image.width * scale).round();
    targetH = (image.height * scale).round();

    // High quality bilinear resize
    image = img.copyResize(
      image,
      width: targetW,
      height: targetH,
      interpolation: img.Interpolation.linear,
    );
  }

  // 4. Compress to JPEG with adaptive quality targeting < 85KB
  int q = params.quality;
  Uint8List compressed = Uint8List.fromList(
    img.encodeJpg(image, quality: q),
  );

  while (compressed.length > 85 * 1024 && q > 45) {
    q -= 15;
    compressed = Uint8List.fromList(
      img.encodeJpg(image, quality: q),
    );
  }

  // If extreme high-frequency noise still exceeds budget, scale down dimension
  while (compressed.length > 85 * 1024 && (image.width > 400 || image.height > 400)) {
    final scale = 0.8;
    image = img.copyResize(
      image,
      width: (image.width * scale).round(),
      height: (image.height * scale).round(),
      interpolation: img.Interpolation.linear,
    );
    compressed = Uint8List.fromList(
      img.encodeJpg(image, quality: q),
    );
  }

  final base64String = base64Encode(compressed);

  return OptimizedImage(
    base64: base64String,
    originalBytes: originalLength,
    compressedBytes: compressed.length,
    width: image.width,
    height: image.height,
  );
}
