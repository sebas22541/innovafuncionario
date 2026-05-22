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
2. Cambia `POSTGRES_PASSWORD` y `QR_DYNAMIC_SECRET`.
3. Si el frontend y backend estaran bajo un dominio, define `BACKEND_BASE_URL`.

```bash
docker compose -f docker-compose-prod.yml --env-file .env.docker up --build -d
```

El frontend queda en `http://localhost:8080` y el backend en `http://localhost:3000`.
En desarrollo, PostgreSQL se expone al host en `localhost:5433`; en produccion queda solo dentro de la red Docker.

## Jenkins

Para Jenkins puedes usar estos comandos dentro del job/pipeline:

```bash
docker compose -f docker-compose-prod.yml --env-file .env.docker build
docker compose -f docker-compose-prod.yml --env-file .env.docker up -d
```

Las migraciones de Prisma se ejecutan automaticamente al iniciar el contenedor del backend con `npx prisma migrate deploy`.
