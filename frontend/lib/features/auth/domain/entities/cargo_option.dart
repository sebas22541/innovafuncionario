class CargoOption {
  const CargoOption({required this.code, required this.name});

  final String code;
  final String name;

  factory CargoOption.fromJson(Map<String, dynamic> source) {
    return CargoOption(
      code: _readString(source['codigo'], 'cargo.codigo'),
      name: _readString(source['cargo'], 'cargo.cargo'),
    );
  }

  String get displayLabel => '$name | Cod. $code';
}

String _readString(dynamic source, String fieldName) {
  if (source is! String) {
    throw StateError('El campo $fieldName no tiene un formato valido.');
  }

  return source;
}
