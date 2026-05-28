# syntax=docker/dockerfile:1.4
FROM ghcr.io/cirruslabs/flutter:3.38.5 AS build

USER root
WORKDIR /app

COPY frontend/pubspec.yaml frontend/pubspec.lock ./
RUN --mount=type=cache,target=/root/.pub-cache flutter pub get

COPY frontend/lib ./lib
COPY frontend/assets ./assets
COPY frontend/web ./web

ARG BACKEND_BASE_URL=
ARG PAYLOAD_ENCRYPTION_KEY=
RUN if [ -n "$BACKEND_BASE_URL" ] || [ -n "$PAYLOAD_ENCRYPTION_KEY" ]; then \
      flutter build web --release --no-wasm-dry-run \
        --dart-define=BACKEND_BASE_URL="$BACKEND_BASE_URL" \
        --dart-define=PAYLOAD_ENCRYPTION_KEY="$PAYLOAD_ENCRYPTION_KEY"; \
    else \
      flutter build web --release --no-wasm-dry-run; \
    fi

FROM nginx:alpine

RUN apk add --no-cache tzdata && \
    ln -snf /usr/share/zoneinfo/America/La_Paz /etc/localtime && \
    echo America/La_Paz > /etc/timezone

COPY --from=build /app/build/web /usr/share/nginx/html
COPY .infra/frontend/prod/nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
