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

  await downloadExcelFile(fileName: fileName, bytes: Uint8List.fromList(bytes));
}

Future<void> exportExcelWorkbookSheets({
  required String fileName,
  required List<ExcelWorkbookSheet> sheets,
}) async {
  if (sheets.isEmpty) {
    throw StateError('Debes enviar al menos una hoja para exportar.');
  }

  final excel = Excel.createExcel();
  final defaultSheet = excel.getDefaultSheet();

  for (final workbookSheet in sheets) {
    final sheet = excel[workbookSheet.sheetName];
    sheet.appendRow(
      workbookSheet.headers.map(_cellValue).toList(growable: false),
    );

    for (final row in workbookSheet.rows) {
      sheet.appendRow(row.map(_cellValue).toList(growable: false));
    }

    for (var column = 0; column < workbookSheet.headers.length; column++) {
      sheet.setColumnAutoFit(column);
    }
  }

  if (defaultSheet != null &&
      !sheets.any((sheet) => sheet.sheetName == defaultSheet)) {
    excel.delete(defaultSheet);
  }

  final bytes = excel.save();

  if (bytes == null) {
    throw StateError('No fue posible generar el archivo Excel.');
  }

  await downloadExcelFile(fileName: fileName, bytes: Uint8List.fromList(bytes));
}

class ExcelWorkbookSheet {
  const ExcelWorkbookSheet({
    required this.sheetName,
    required this.headers,
    required this.rows,
  });

  final String sheetName;
  final List<String> headers;
  final List<List<Object?>> rows;
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
