import 'dart:typed_data';

import 'package:excel/excel.dart';
<<<<<<< HEAD
import 'package:share_plus/share_plus.dart';
=======

import 'excel_file_downloader.dart';
>>>>>>> 83bbe3119e470b5b1c7d696cc8f396c08c49bec2

Future<void> exportExcelWorkbook({
  required String fileName,
  required String sheetName,
  required List<String> headers,
  required List<List<Object?>> rows,
}) async {
  final excel = Excel.createExcel();
  final defaultSheet = excel.getDefaultSheet();
  final sheet = excel[sheetName];

  if (defaultSheet != null && defaultSheet != sheetName) {
    excel.delete(defaultSheet);
  }

  sheet.appendRow(headers.map(_cellValue).toList(growable: false));

  for (final row in rows) {
    sheet.appendRow(row.map(_cellValue).toList(growable: false));
  }

  for (var column = 0; column < headers.length; column++) {
    sheet.setColumnAutoFit(column);
  }

  final bytes = excel.save();

  if (bytes == null) {
    throw StateError('No fue posible generar el archivo Excel.');
  }

<<<<<<< HEAD
  await SharePlus.instance.share(
    ShareParams(
      files: [
        XFile.fromData(
          Uint8List.fromList(bytes),
          name: fileName,
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ),
      ],
    ),
=======
  await downloadExcelFile(
    fileName: fileName,
    bytes: Uint8List.fromList(bytes),
>>>>>>> 83bbe3119e470b5b1c7d696cc8f396c08c49bec2
  );
}

CellValue _cellValue(Object? value) {
  if (value == null) {
    return TextCellValue('');
  }

  if (value is int) {
    return IntCellValue(value);
  }

  if (value is double) {
    return DoubleCellValue(value);
  }

  if (value is bool) {
    return BoolCellValue(value);
  }

  if (value is DateTime) {
    return DateTimeCellValue.fromDateTime(value);
  }

  return TextCellValue(value.toString());
}
