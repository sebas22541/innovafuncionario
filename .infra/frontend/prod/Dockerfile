# syntax=docker/dockerfile:1.4
FROM ghcr.io/cirruslabs/flutter:stable AS build

USER root
WORKDIR /app

COPY frontend/pubspec.yaml frontend/pubspec.lock ./
RUN --mount=type=cache,target=/root/.pub-cache flutter pub get

COPY frontend/lib ./lib
COPY frontend/assets ./assets
COPY frontend/web ./web

ARG BACKEND_BASE_URL=
RUN if [ -n "$BACKEND_BASE_URL" ]; then \
      flutter build web --release --dart-define=BACKEND_BASE_URL=$BACKEND_BASE_URL; \
    else \
      flutter build web --release; \
    fi

FROM nginx:alpine

RUN apk add --no-cache tzdata && \
    ln -snf /usr/share/zoneinfo/America/La_Paz /etc/localtime && \
    echo America/La_Paz > /etc/timezone

COPY --from=build /app/build/web /usr/share/nginx/html
COPY .infra/frontend/prod/nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
