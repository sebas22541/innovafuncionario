import 'package:flutter/material.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  static void open(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const PrivacyScreen()));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Privacidad y uso de la cuenta')),
    body: const SingleChildScrollView(
      padding: EdgeInsets.all(24),
      child: SelectableText(
        'Innova Funcionario · Innova Cochabamba\n\n'
        'Esta aplicación permite gestionar servicios y registros de funcionarios. '
        'Crear una cuenta no acredita una relación laboral ni asigna un cargo: '
        'la administración debe verificar y completar esa información. '
        'Usa tus propios datos y protege tu contraseña.\n\n'
        'Datos y finalidad\n'
        'Para crear una cuenta solicitamos nombres, primer apellido, CI y una '
        'contraseña. El CI se utiliza como usuario de acceso. La contraseña se '
        'almacena como un hash. Según las funciones utilizadas, se procesan '
        'datos del perfil, fotografía, oficina, cargo, contratos, asistencia, '
        'permisos de salida, almuerzos y calificaciones. Los administradores '
        'autorizados pueden consultar información según sus permisos.\n\n'
        'Permisos del dispositivo\n'
        'La cámara permite leer códigos QR. La ubicación se utiliza para validar '
        'asistencias y generar QR dinámicos cuando utilizas esas funciones. '
        'La galería se abre al seleccionar una foto de perfil. Puedes gestionar '
        'estos permisos desde los ajustes del dispositivo; denegarlos puede '
        'limitar las funciones que los necesitan.\n\n'
        'Servicios utilizados\n'
        'Los datos se envían al servidor de la aplicación. Las fotos y '
        'credenciales se almacenan en Cloudinary. Las notificaciones usan '
        'Firebase y el identificador de notificaciones del dispositivo.\n\n'
        'Conservación y eliminación\n'
        'Los datos de la cuenta se mantienen mientras exista la cuenta. '
        'Puedes eliminarla desde Configuración > Eliminar mi cuenta, '
        'confirmando tu contraseña. La eliminación es definitiva: borra la '
        'cuenta, su identidad QR, asistencias vinculadas, salidas, almuerzos, '
        'calificaciones, notificaciones, dispositivos, fotos y credenciales '
        'almacenadas por la aplicación. Los eventos compartidos permanecen '
        'sin referencia a tu cuenta como creador. Esta acción no elimina '
        'documentos descargados o copias previamente exportadas.\n\n'
        'Consultas sobre tus datos\n'
        'Contacta a la administración de Innova Cochabamba mediante los '
        'canales institucionales de soporte para consultas o correcciones '
        'de tu información.',
        style: TextStyle(fontSize: 16, height: 1.5),
      ),
    ),
  );
}
