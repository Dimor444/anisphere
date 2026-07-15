import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_image_compress/flutter_image_compress.dart';

/// The image cannot be decoded or cannot be compressed under
/// [PostImageCompressor.maxBytes] — the post must not be published with it,
/// because the Storage rule would reject the upload.
class ImageCompressException implements Exception {
  final String message;
  const ImageCompressException(this.message);

  @override
  String toString() => 'ImageCompressException: $message';
}

/// Recompresses a picked post image to a JPEG that the `posts/` Storage rule
/// (`size < 1 MB`, `image/jpeg`) is guaranteed to accept: longest edge capped
/// at [_maxEdge], quality stepped down from [_startQuality] to a hard floor of
/// [_minQuality], then a final size assertion. HEIC/HEIF input is decoded by
/// the native side (iOS 11+ / Android API 28+) and always re-encoded as JPEG.
class PostImageCompressor {
  PostImageCompressor._();

  /// Hard ceiling asserted before any upload starts. Kept ~5% under the
  /// rule's 1 MiB (1,048,576) so a passing client can never race the rule.
  static const int maxBytes = 1000 * 1000;

  /// The quality loop aims below this so typical output lands well clear of
  /// [maxBytes], not just barely under it.
  static const int _targetBytes = 900 * 1000;

  static const int _maxEdge = 1080;
  static const int _startQuality = 85;
  static const int _qualityStep = 10;
  static const int _minQuality = 40;

  /// Compresses the image at [path]; throws [ImageCompressException] if the
  /// result cannot be brought under [maxBytes].
  static Future<Uint8List> compress(String path) async {
    final (srcW, srcH) = await _probeSize(path);
    // Exact target dims (longest edge = _maxEdge, aspect kept) when the
    // engine could decode the header; the plugin scales so both dims end up
    // >= min* without upscaling, so matching-ratio mins yield exactly this.
    var minWidth = _maxEdge;
    var minHeight = _maxEdge;
    if (srcW > 0 && srcH > 0) {
      if (srcW >= srcH) {
        minWidth = math.min(srcW, _maxEdge);
        minHeight = (minWidth * srcH / srcW).round();
      } else {
        minHeight = math.min(srcH, _maxEdge);
        minWidth = (minHeight * srcW / srcH).round();
      }
    }

    Uint8List? out;
    var quality = _startQuality;
    while (true) {
      out = await FlutterImageCompress.compressWithFile(
        path,
        minWidth: minWidth,
        minHeight: minHeight,
        quality: quality,
        format: CompressFormat.jpeg,
      );
      if (out == null) {
        throw const ImageCompressException('image could not be decoded');
      }
      if (out.length <= _targetBytes || quality <= _minQuality) break;
      quality = math.max(_minQuality, quality - _qualityStep);
    }

    if (out.length >= maxBytes) {
      throw ImageCompressException(
          'still ${out.length} bytes at quality $_minQuality (limit $maxBytes)');
    }
    return out;
  }

  /// Image dimensions from the encoded header — no full decode. Returns
  /// (0, 0) when the engine lacks a codec for the format (e.g. HEIC on some
  /// platforms); the caller then falls back to shortest-edge-1080 mins and
  /// the native side of flutter_image_compress does the decoding.
  static Future<(int, int)> _probeSize(String path) async {
    try {
      final buffer = await ui.ImmutableBuffer.fromFilePath(path);
      try {
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        final size = (descriptor.width, descriptor.height);
        descriptor.dispose();
        return size;
      } finally {
        buffer.dispose();
      }
    } catch (_) {
      return (0, 0);
    }
  }
}
