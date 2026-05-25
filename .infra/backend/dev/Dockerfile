# syntax=docker/dockerfile:1.4
FROM node:22-alpine

WORKDIR /app

RUN apk add --no-cache openssl tzdata libc6-compat

ENV TZ=America/La_Paz
ENV DATABASE_URL=postgresql://postgres:postgres@db:5432/asistenciasQR?schema=public

COPY backend/package*.json ./
RUN --mount=type=cache,target=/root/.npm npm ci

COPY backend/ ./
COPY frontend/assets/templates/credencial.pdf ./assets/templates/credencial.pdf
RUN npx prisma generate

EXPOSE 3000

CMD ["sh", "-c", "npx prisma migrate deploy && npm run dev"]
