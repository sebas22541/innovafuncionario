import 'dart:convert';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';

class Base64Avatar extends StatelessWidget {
  const Base64Avatar({
    super.key,
    required this.size,
    required this.fallbackLabel,
    this.photoSource,
    this.borderRadius,
  });

  final double size;
  final String fallbackLabel;
  final String? photoSource;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final resolvedBorderRadius =
        borderRadius ?? BorderRadius.circular(size * 0.26);
    final normalizedPhotoSource = photoSource?.trim();
    final hasPhoto = normalizedPhotoSource?.isNotEmpty == true;
    final photoUri = _tryParsePhotoUri(normalizedPhotoSource);
    final photoBytes = photoUri == null
        ? _cachedPhotoBytes(normalizedPhotoSource)
        : null;
    final cacheSize = (size * MediaQuery.devicePixelRatioOf(context)).round();

    return ClipRRect(
      borderRadius: resolvedBorderRadius,
      child: SizedBox(
        width: size,
        height: size,
        child: hasPhoto
            ? (photoUri != null
                  ? CachedNetworkImage(
                      imageUrl: photoUri.toString(),
                      memCacheWidth: cacheSize,
                      memCacheHeight: cacheSize,
                      maxWidthDiskCache: cacheSize,
                      maxHeightDiskCache: cacheSize,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                      placeholder: (_, _) =>
                          _AvatarFallback(size: size, label: fallbackLabel),
                      errorWidget: (_, _, _) =>
                          _AvatarFallback(size: size, label: fallbackLabel),
                    )
                  : photoBytes != null
                  ? Image.memory(
                      photoBytes,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          _AvatarFallback(size: size, label: fallbackLabel),
                    )
                  : _AvatarFallback(size: size, label: fallbackLabel))
            : _AvatarFallback(size: size, label: fallbackLabel),
      ),
    );
  }
}

final Map<String, Uint8List?> _decodedPhotoCache = <String, Uint8List?>{};

Uri? _tryParsePhotoUri(String? photoSource) {
  if (photoSource == null || photoSource.isEmpty) {
    return null;
  }

  final parsedUri = Uri.tryParse(photoSource);

  if (parsedUri == null) {
    return null;
  }

  if (parsedUri.scheme == 'http' || parsedUri.scheme == 'https') {
    return parsedUri;
  }

  return null;
}

Uint8List? _tryDecodePhotoBytes(String? photoSource) {
  if (photoSource == null || photoSource.isEmpty) {
    return null;
  }

  try {
    return base64Decode(photoSource);
  } catch (_) {
    return null;
  }
}

Uint8List? _cachedPhotoBytes(String? photoSource) {
  if (photoSource == null || photoSource.isEmpty) {
    return null;
  }

  return _decodedPhotoCache.putIfAbsent(
    photoSource,
    () => _tryDecodePhotoBytes(photoSource),
  );
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({required this.size, required this.label});

  final double size;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppPalette.orangeSoft,
      alignment: Alignment.center,
      child: Text(
        label.trim().isEmpty ? 'U' : label.trim().substring(0, 1).toUpperCase(),
        style: TextStyle(
          color: AppPalette.orange,
          fontSize: size * 0.34,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
