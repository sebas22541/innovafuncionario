import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

Future<void> downloadExcelFile({
  required String fileName,
  required Uint8List bytes,
}) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [
        XFile.fromData(
          bytes,
          name: fileName,
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ),
      ],
    ),
  );
}
