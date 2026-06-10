import 'dart:typed_data';

Future<void> downloadExcelFile({
  required String fileName,
  required Uint8List bytes,
}) async {
  throw UnsupportedError(
    'La descarga de Excel solo esta disponible en la version web.',
  );
}
