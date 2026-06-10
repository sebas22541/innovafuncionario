import 'dart:typed_data';

import 'package:excel/excel.dart';

import 'excel_file_downloader.dart';

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

  await downloadExcelFile(
    fileName: fileName,
    bytes: Uint8List.fromList(bytes),
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
