import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;

/// Compress an image file to reduce upload size.
/// Returns the path to the compressed file (may be the original if compression
/// is not needed or fails).
///
/// - [maxWidth] / [maxHeight]: longest edge constraint (default 1200px)
/// - [quality]: JPEG quality 0-100 (default 70)
/// - [maxBytes]: skip compression if the file is already smaller than this
class ImageCompressUtil {
  static const int _defaultMaxDimension = 1200;
  static const int _defaultQuality = 70;
  static const int _defaultMaxBytes = 500 * 1024; // 500 KB

  /// Compress a single image. Returns the compressed file path.
  static Future<String> compress(
    String sourcePath, {
    int maxWidth = _defaultMaxDimension,
    int maxHeight = _defaultMaxDimension,
    int quality = _defaultQuality,
    int skipIfSmallerThan = _defaultMaxBytes,
  }) async {
    try {
      final file = File(sourcePath);
      if (!file.existsSync()) return sourcePath;

      final bytes = await file.length();
      if (bytes <= skipIfSmallerThan) {
        if (kDebugMode) debugPrint('ImageCompress: skipping $sourcePath (${(bytes / 1024).toStringAsFixed(0)} KB <= threshold)');
        return sourcePath;
      }

      final ext = p.extension(sourcePath).toLowerCase();
      // Only compress raster image formats
      if (!['.jpg', '.jpeg', '.png', '.webp', '.heic', '.heif'].contains(ext)) {
        return sourcePath;
      }

      final targetPath = _tempPath(sourcePath);

      final result = await FlutterImageCompress.compressAndGetFile(
        sourcePath,
        targetPath,
        minWidth: maxWidth,
        minHeight: maxHeight,
        quality: quality,
        format: CompressFormat.jpeg,
      );

      if (result == null) {
        if (kDebugMode) debugPrint('ImageCompress: compression returned null for $sourcePath');
        return sourcePath;
      }

      final compressedSize = await File(result.path).length();
      if (kDebugMode) {
        debugPrint(
          'ImageCompress: ${(bytes / 1024).toStringAsFixed(0)} KB -> ${(compressedSize / 1024).toStringAsFixed(0)} KB '
          '(${((1 - compressedSize / bytes) * 100).toStringAsFixed(0)}% reduction)',
        );
      }

      return result.path;
    } catch (e) {
      if (kDebugMode) debugPrint('ImageCompress: error compressing $sourcePath: $e');
      return sourcePath; // fallback to original
    }
  }

  /// Compress multiple images. Calls [onProgress] with (completed, total) after
  /// each file finishes.
  static Future<List<String>> compressAll(
    List<String> paths, {
    void Function(int completed, int total)? onProgress,
    int maxWidth = _defaultMaxDimension,
    int maxHeight = _defaultMaxDimension,
    int quality = _defaultQuality,
  }) async {
    final results = <String>[];
    for (var i = 0; i < paths.length; i++) {
      final compressed = await compress(
        paths[i],
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        quality: quality,
      );
      results.add(compressed);
      onProgress?.call(i + 1, paths.length);
    }
    return results;
  }

  static String _tempPath(String original) {
    final dir = Directory.systemTemp.path;
    final name = p.basenameWithoutExtension(original);
    final ts = DateTime.now().microsecondsSinceEpoch;
    return '$dir/compressed_${name}_$ts.jpg';
  }
}
