# Preparación para App Store

Cambios incluidos: registro público desde la bienvenida, privacidad accesible antes y después del acceso, eliminación definitiva con contraseña en Configuración y nombre visible Innova Funcionario. Los permisos de cámara, ubicación en uso y galería ya tienen descripciones en Info.plist. El objetivo mínimo pasa a iOS 15 por las dependencias de Firebase.

## Servidor: obligatorio antes de distribuir

Desplegar el backend actualizado y aplicar `backend/prisma/migrations/20261012_account_deletion/migration.sql` con el flujo habitual de Prisma (`npx prisma migrate deploy` en backend, con DATABASE_URL del entorno correcto). Regenerar el cliente (`npm run prisma:generate`). No se ha ejecutado esta migración contra producción.

`POST /api/auth/signup` crea una cuenta con CI, nombres, apellido, contraseña de al menos 8 caracteres y aceptación de privacidad. Ignora roles y datos laborales enviados por el cliente; asigna OPERADOR. Un administrador debe verificar/completar la información laboral. El registro administrativo existente continúa protegido.

`DELETE /api/auth/account` exige el token vigente y `currentPassword`. Borra archivos de Cloudinary antes de completar una transacción que elimina la cuenta, persona y datos relacionados. Los eventos compartidos se conservan sin creador; los documentos ya exportados quedan fuera de este flujo. Si Cloudinary falla, devuelve error y permite reintentar. Verificar la configuración de Cloudinary en producción. Una eliminación exitosa invalida los tokens al desaparecer el usuario.

## Pendientes del titular de la aplicación

- Sustituir `com.example.qr` en Runner y RunnerTests por el Bundle ID registrado en Apple Developer y seleccionar el equipo de firma en Xcode. No inventar un identificador o equipo.
- Revisar el texto de privacidad incluido con el responsable institucional, especialmente contacto, registros del servidor, copias de seguridad, conservación de documentos laborales y exportaciones. Publicar una URL HTTPS estable con la política completa y consignarla en App Store Connect. La pantalla incluida no sustituye la URL pública requerida por Apple.
- Completar App Privacy según los datos y SDK reales: identificadores/CI, nombre, datos laborales, fotografía, ubicación, registros y tokens/dispositivo cuando corresponda. Comprobar los manifiestos de privacidad y las API con motivo requerido de los plugins al archivar; no declarar datos ni motivos sin revisar el informe de Xcode.
- Configurar Firebase para el Bundle ID de iOS (GoogleService-Info.plist o FlutterFire), APNs y las capacidades Push Notifications/Background Modes si se publicarán notificaciones. El repositorio no incluye GoogleService-Info.plist ni configuración de firma para iOS.
- Preparar iconos definitivos, capturas de iPhone/iPad según los dispositivos admitidos, descripción, categoría, edad, URL de soporte y derechos del contenido. Confirmar las declaraciones de cifrado/exportación según la implementación real.
- Facilitar a Apple una cuenta de revisión funcional con datos de ejemplo y las instrucciones para probar asistencia/QR, ubicación y eliminación. La cuenta debe poder eliminarse; crear otra para revisiones posteriores. Explicar que las funciones laborales requieren cuenta.

## Comprobación en un Mac

1. Ejecutar `flutter pub get`, `cd ios` y `pod install`.
2. Abrir Runner.xcworkspace en Xcode, configurar firma/identificador y resolver las capacidades de Firebase.
3. Con un servidor de pruebas, crear una cuenta desde el inicio, cerrar sesión e ingresar con el CI y la contraseña elegida. Comprobar que la contraseña predeterminada por CI no accede a una cuenta creada por registro público.
4. Comprobar permisos concedidos y denegados, dispositivos pequeños, teclado, red sin conexión y errores de registro.
5. Eliminar una cuenta de prueba: contraseña errónea debe fallar; cancelar no debe borrar; confirmar debe cerrar sesión. Verificar en servidor y Cloudinary que desaparezcan usuario, persona, registros y archivos. Comprobar que el token anterior no funcione y que otra cuenta siga intacta.
6. Compilar `flutter build ipa --release` y probar el archivo firmado mediante TestFlight antes de enviarlo a revisión. Windows no permite validar ni generar este archivo de iOS.

No se ha subido esta aplicación a App Store Connect ni se garantiza aprobación.

Referencias oficiales consultadas:
- https://developer.apple.com/support/offering-account-deletion-in-your-app/
- https://developer.apple.com/app-store/review/
- https://developer.apple.com/app-store/review/guidelines/
- https://firebase.google.com/docs/flutter/setup
