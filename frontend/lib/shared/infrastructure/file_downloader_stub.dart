import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

Future<void> downloadFile({
  required String fileName,
  required Uint8List bytes,
  required String mimeType,
}) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile.fromData(bytes, name: fileName, mimeType: mimeType)],
    ),
  );
}
