# Backend para el frontend iOS existente

El contrato de API, los modelos Prisma y las migraciones se sincronizaron con
`innovafuncionario.cochabamba.bo/backend`, que sirve de referencia para el frontend.
La carpeta `innovafuncionario.cochabamba.bo` se utilizó únicamente como lectura.

Se incluyen sesiones con refresh token, vinculación de dispositivos, biometría,
registro iOS, Sign in with Apple, eliminación de cuenta, lugares, inspecciones y
los campos actuales de eventos, usuarios y reportes. Se conservan las entradas
`api/index.ts` y `api/[...path].ts` de Vercel. El servidor inicializa el esquema
cuando recibe una solicitud; en Vercel no abre un puerto ni inicia el intervalo
periódico de roles. La autenticación sigue actualizando los roles temporales.

## Configuración del despliegue

Usar la raíz `innovafuncionario`, Node 22 y el `vercel.json` existente.
El build genera Prisma y verifica TypeScript; no aplica migraciones ni ejecuta seed.

Configurar las variables en Vercel usando `backend/.env.vercel.example` como guía.
Los archivos `.env.prod` locales no configuran las variables del proyecto Vercel.

- `DATABASE_URL`: la misma base de datos que la API de respaldo si ambas deben
  compartir usuarios, sesiones y dispositivos.
- `JWT_SECRET`: el mismo valor que el backend de respaldo. Se añadió a `.env.prod`
  local desde la referencia; también debe configurarse en Vercel.
- `PAYLOAD_ENCRYPTION_KEY`: exactamente la clave usada para compilar iOS. Las
  claves de los dos `.env.prod` locales ya coincidían al realizar la adaptación.
- `QR_DYNAMIC_SECRET` y `CALIFICACION_QR_SECRET`: usar los mismos valores en ambas
  APIs. Si se omite el segundo, se deriva de `DATABASE_URL`, como en la referencia.
- `APPLE_BUNDLE_ID`: `com.innovafuncionario.gamc.bo`, según el proyecto Xcode actual.
  `APPLE_TEAM_ID`, `APPLE_KEY_ID` y `APPLE_PRIVATE_KEY` deben corresponder a las
  credenciales reales de Apple; los archivos locales de referencia no las incluyen.
- Cloudinary y Firebase: configurar las credenciales de los servicios que ya usa
  la aplicación. La recepción de notificaciones requiere también la configuración
  existente de Firebase/APNs del proyecto iOS.

Antes de desplegar sobre una base antigua, revisar y aplicar las migraciones
pendientes contra esa base con el procedimiento habitual y una copia de respaldo.
Se añadieron las migraciones ausentes; se conservaron las migraciones existentes.
No se ejecutaron migraciones ni cambios contra la base de producción.

El frontend Release ya apunta primero a `https://innovafuncionario-jses.vercel.app`
y después a `https://innovafuncionarioapi.cochabamba.bo`.
Verificar que el despliegue se publique en ese proyecto de Vercel.

## Verificación local

Con Node 22.12 o superior dentro de la rama 22:

```powershell
npm ci
npm run build
cd backend
node --loader ts-node/esm --test tests/*.test.ts src/modules/reportes/services/previous-scanner.test.ts
```

Las pruebas de dispositivos y refresh crean bases temporales aisladas. Requieren
PostgreSQL local; `PG_TEST_BIN` permite indicar la carpeta `bin` (se verificaron
con PostgreSQL 15). La prueba de zona horaria requiere una base de prueba y
usuario explícitos y se omite si no se proporcionan.

No se realizó un despliegue remoto ni una prueba desde un iPhone. Para cerrar la
verificación en producción, comprobar login, refresh, biometría, acceso Apple y
lectura de datos con la compilación iOS que use la misma clave de cifrado.
El paquete distribuible de iOS es un IPA y se genera con Xcode en macOS.
