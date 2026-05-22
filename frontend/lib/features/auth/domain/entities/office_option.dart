class OfficeOption {
  const OfficeOption({
    required this.id,
    required this.name,
    required this.code,
    required this.level,
  });

  final int id;
  final String name;
  final String code;
  final int level;

  factory OfficeOption.fromJson(Map<String, dynamic> source) {
    return OfficeOption(
      id: _readInt(source['id'], 'office.id'),
      name: _readString(source['nombre'], 'office.nombre'),
      code: _readString(source['codigo'], 'office.codigo'),
      level: _readInt(source['nivel'], 'office.nivel'),
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

int _readInt(dynamic source, String fieldName) {
  if (source is! int) {
    throw StateError('El campo $fieldName no tiene un formato valido.');
  }

  return source;
}
