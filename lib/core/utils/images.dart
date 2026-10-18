import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';

/// Turns an image reference from the data layer into an [ImageProvider].
/// Mock data uses bundled assets; photos people take are local files until
/// they are uploaded; the real backend will return URLs, which are cached
/// on disk to save data.
ImageProvider? imageFor(String? ref) {
  if (ref == null || ref.isEmpty) return null;
  if (ref.startsWith('http')) return CachedNetworkImageProvider(ref);
  if (ref.startsWith('/') || ref.startsWith('file://')) {
    return FileImage(File(ref.replaceFirst('file://', '')));
  }
  return AssetImage(ref);
}
