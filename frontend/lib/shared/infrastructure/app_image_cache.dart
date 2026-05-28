import 'package:flutter/painting.dart';

class AppImageCache {
  const AppImageCache._();

  static void configure() {
    final imageCache = PaintingBinding.instance.imageCache;

    imageCache.maximumSize = 3000;
    imageCache.maximumSizeBytes = 512 * 1024 * 1024;
  }
}
