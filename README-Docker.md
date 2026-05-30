# Docker

Este proyecto queda preparado con:

- Backend Node/TypeScript + Prisma en el puerto `3000`.
- Frontend Flutter web servido con Nginx en el puerto `8080`.
- PostgreSQL 16 con volumen persistente.

## Levantar en desarrollo

```bash
docker compose -f docker-compose-dev.yml --env-file .env.docker.example up --build
```

## Levantar en produccion

1. Copia `.env.docker.example` a `.env.docker`.
2. Cambia `POSTGRES_PASSWORD`, `QR_DYNAMIC_SECRET` y las variables de Cloudinary.
3. Si el frontend y backend estaran bajo un dominio, define `BACKEND_BASE_URL`.

```bash
docker compose -f docker-compose-prod.yml --env-file .env.docker up --build -d
```

El frontend queda en `http://localhost:8080` y el backend en `http://localhost:3000`.
En desarrollo, PostgreSQL se expone al host en `localhost:5433`; en produccion queda solo dentro de la red Docker.

## Variables de entorno

Para ejecutar el backend sin Docker se usa `backend/.env`.

Ejemplos disponibles:

- `backend/.env.example`: plantilla general del backend.
- `backend/.env.development.example`: plantilla para desarrollo local.
- `backend/.env.production.example`: plantilla para produccion.
- `.env.docker.example`: plantilla para Docker Compose y Jenkins.

No subas archivos `.env` reales al repositorio. En el servidor crea `.env.docker` con valores reales.

## Jenkins

Para Jenkins puedes usar estos comandos dentro del job/pipeline:

```bash
docker compose -f docker-compose-prod.yml --env-file .env.docker build
docker compose -f docker-compose-prod.yml --env-file .env.docker up -d
```

Las migraciones de Prisma se ejecutan automaticamente al iniciar el contenedor del backend con `npx prisma migrate deploy`.

## Logs del backend

En Docker los logs persistentes quedan en:

- Produccion: `./logs/backend/`
- Desarrollo: `./logs/backend-dev/`

Archivos principales:

- `backend-access.log`: una linea JSON por request con `requestId`, ruta, metodo, estado HTTP, duracion, IP y usuario.
- `backend-error.log`: errores HTTP 4xx/5xx, errores internos con `stack`, promesas rechazadas y excepciones no capturadas.
- `backend-app.log`: eventos generales del backend, como arranque y apagado.

Para verlos en el servidor:

```bash
tail -f logs/backend/backend-error.log
tail -f logs/backend/backend-access.log
docker compose -f docker-compose-prod.yml --env-file .env.docker logs -f backend
```
