FROM ghcr.io/cirruslabs/flutter:3.38.5 AS build

USER root
WORKDIR /app

COPY frontend/pubspec.yaml frontend/pubspec.lock ./
RUN flutter pub get

COPY frontend/lib ./lib
COPY frontend/assets ./assets
COPY frontend/web ./web

ARG BACKEND_BASE_URL=
ARG PAYLOAD_ENCRYPTION_KEY=
ARG APP_VERSION=
RUN flutter clean && \
    flutter pub get && \
    flutter analyze --no-pub
RUN set -eux; \
    if [ -n "$BACKEND_BASE_URL" ] || [ -n "$PAYLOAD_ENCRYPTION_KEY" ]; then \
      flutter build web --release --no-wasm-dry-run \
        --no-web-resources-cdn \
        --dart-define=BACKEND_BASE_URL="$BACKEND_BASE_URL" \
        --dart-define=PAYLOAD_ENCRYPTION_KEY="$PAYLOAD_ENCRYPTION_KEY"; \
    else \
      flutter build web --release --no-wasm-dry-run --no-web-resources-cdn; \
    fi
RUN sed -i 's#https://unpkg.com/@zxing/library@0.21.3#vendor/zxing-library-0.21.3.js#g' /app/build/web/main.dart.js
RUN APP_VERSION_VALUE="${APP_VERSION:-$(date -u +%Y%m%d%H%M%S)}" && \
    printf '{"version":"%s"}\n' "$APP_VERSION_VALUE" > /app/build/web/app-version.json

FROM nginx:alpine

RUN apk add --no-cache tzdata && \
    ln -snf /usr/share/zoneinfo/America/La_Paz /etc/localtime && \
    echo America/La_Paz > /etc/timezone

COPY --from=build /app/build/web /usr/share/nginx/html
COPY .infra/frontend/prod/nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
