import 'dart:convert';

import 'package:mobile_scanner/mobile_scanner.dart';

import '../../domain/entities/qr_scan_result.dart';

class QrScanResultModel {
  const QrScanResultModel({
    required this.value,
    required this.displayValue,
    required this.format,
    required this.payloadType,
    required this.payloadFields,
    required this.scannedAt,
  });

  factory QrScanResultModel.fromBarcode(Barcode barcode) {
    final rawValue = (barcode.rawValue ?? barcode.displayValue ?? '').trim();
    final displayValue = (barcode.displayValue ?? rawValue).trim();
    final parsedPayload = _parsePayload(rawValue);

    return QrScanResultModel(
      value: rawValue,
      displayValue: displayValue,
      format: _formatName(barcode.format.name),
      payloadType: parsedPayload.type,
      payloadFields: parsedPayload.fields,
      scannedAt: DateTime.now(),
    );
  }

  final String value;
  final String displayValue;
  final String format;
  final String payloadType;
  final Map<String, String> payloadFields;
  final DateTime scannedAt;

  QrScanResult toEntity() {
    return QrScanResult(
      value: value,
      displayValue: displayValue,
      format: format,
      payloadType: payloadType,
      payloadFields: payloadFields,
      scannedAt: scannedAt,
    );
  }

  static String _formatName(String source) {
    return source
        .replaceAllMapped(RegExp(r'([A-Z])'), (match) => ' ${match.group(0)}')
        .trim()
        .toUpperCase();
  }

  static _ParsedPayload _parsePayload(String rawValue) {
    final normalizedValue = rawValue.trim();

    if (normalizedValue.isEmpty) {
      return const _ParsedPayload(type: 'VACIO', fields: {});
    }

    if (_isAppQrExternalId(normalizedValue)) {
      return _ParsedPayload(
        type: 'ID_EXTERNO',
        fields: {'idExterno': normalizedValue},
      );
    }

    final decodedJson = _tryDecodeJson(normalizedValue);
    if (decodedJson != null) {
      return _ParsedPayload(
        type: 'JSON',
        fields: _flattenDynamicValue(decodedJson),
      );
    }

    final uri = Uri.tryParse(normalizedValue);
    if (uri != null && uri.hasScheme) {
      final fields = <String, String>{};

      if (uri.scheme.isNotEmpty) {
        fields['protocolo'] = uri.scheme;
      }
      if (uri.host.isNotEmpty) {
        fields['dominio'] = uri.host;
      }
      if (uri.path.isNotEmpty && uri.path != '/') {
        fields['ruta'] = uri.path;
      }
      if (uri.fragment.isNotEmpty) {
        fields['fragmento'] = uri.fragment;
      }

      for (final entry in uri.queryParameters.entries) {
        fields['parametro.${entry.key}'] = entry.value;
      }

      return _ParsedPayload(type: 'URL', fields: fields);
    }

    final keyValueFields = _tryParseKeyValuePairs(normalizedValue);
    if (keyValueFields.isNotEmpty) {
      return _ParsedPayload(type: 'CLAVE_VALOR', fields: keyValueFields);
    }

    return const _ParsedPayload(type: 'TEXTO', fields: {});
  }

  static bool _isAppQrExternalId(String value) {
    final normalized = value.trim().toUpperCase();

    return RegExp(
      r'^(QREXT-[A-F0-9]{20}|USR-\d+-[A-F0-9]{12}|AUTOQR:[A-F0-9]+|DQR1\.QREXT-[A-F0-9]{20}\.[0-9A-Z]+\.[A-F0-9]{16})$',
    ).hasMatch(normalized);
  }

  static Object? _tryDecodeJson(String source) {
    try {
      return jsonDecode(source);
    } on FormatException {
      return null;
    }
  }

  static Map<String, String> _flattenDynamicValue(
    Object value, {
    String prefix = '',
  }) {
    final fields = <String, String>{};

    if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key.toString();
        final nextPrefix = prefix.isEmpty ? key : '$prefix.$key';
        fields.addAll(_flattenDynamicValue(entry.value, prefix: nextPrefix));
      }
      return fields;
    }

    if (value is List) {
      for (var index = 0; index < value.length; index++) {
        final nextPrefix = prefix.isEmpty ? 'item.$index' : '$prefix.$index';
        fields.addAll(_flattenDynamicValue(value[index], prefix: nextPrefix));
      }
      return fields;
    }

    if (prefix.isNotEmpty) {
      fields[prefix] = value.toString();
    }

    return fields;
  }

  static Map<String, String> _tryParseKeyValuePairs(String source) {
    final fields = <String, String>{};
    final normalizedSource = source.replaceAll(';', '&');
    final pairs = normalizedSource.split('&');

    for (final pair in pairs) {
      final trimmedPair = pair.trim();
      if (trimmedPair.isEmpty || !trimmedPair.contains('=')) {
        continue;
      }

      final separatorIndex = trimmedPair.indexOf('=');
      final key = trimmedPair.substring(0, separatorIndex).trim();
      final value = trimmedPair.substring(separatorIndex + 1).trim();

      if (key.isEmpty || value.isEmpty) {
        continue;
      }

      fields[key] = value;
    }

    return fields;
  }
}

class _ParsedPayload {
  const _ParsedPayload({required this.type, required this.fields});

  final String type;
  final Map<String, String> fields;
}
