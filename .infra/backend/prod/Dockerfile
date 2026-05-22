FROM node:22-alpine

WORKDIR /app

RUN apk add --no-cache openssl tzdata libc6-compat

ENV TZ=America/La_Paz
ENV NODE_ENV=production
ENV DATABASE_URL=postgresql://postgres:postgres@db:5432/asistenciasQR?schema=public

COPY backend/package*.json ./
RUN npm ci --include=dev

COPY backend/ ./
RUN npx prisma generate

EXPOSE 3000

CMD ["sh", "-c", "npx prisma migrate deploy && npm start"]
