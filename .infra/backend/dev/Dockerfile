FROM node:22-alpine

WORKDIR /app

RUN apk add --no-cache openssl tzdata libc6-compat

ENV TZ=America/La_Paz
ENV DATABASE_URL=postgresql://postgres:postgres@db:5432/asistenciasQR?schema=public

COPY backend/package*.json ./
RUN npm ci

COPY backend/ ./
COPY frontend/assets/templates/credencial.pdf ./assets/templates/credencial.pdf
COPY .infra/backend/dev/start.sh ./start.sh
RUN npx prisma generate

EXPOSE 3000

CMD ["sh", "./start.sh"]
