# syntax=docker/dockerfile:1
FROM --platform=$BUILDPLATFORM debian:bookworm-slim AS dashboard
ARG FLUTTER_VERSION=3.47.7
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git unzip xz-utils libglu1-mesa \
    && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch ${FLUTTER_VERSION} \
    https://github.com/flutter/flutter.git /opt/flutter
ENV PATH="/opt/flutter/bin:${PATH}"
RUN flutter config --no-analytics --enable-web && flutter precache --web
WORKDIR /dashboard
COPY packages/shorecat_dashboard/ ./
RUN flutter pub get --enforce-lockfile \
    && flutter build web --release --no-web-resources-cdn

FROM dart:3.13.5-sdk AS server
WORKDIR /src
COPY pubspec.yaml pubspec.lock ./
COPY packages/shorecat_core/ packages/shorecat_core/
COPY packages/shorecat_server/ packages/shorecat_server/
COPY packages/shorecat_updater/ packages/shorecat_updater/
COPY packages/shorecat_cli/ packages/shorecat_cli/
RUN dart pub get --enforce-lockfile \
    && dart compile exe packages/shorecat_server/bin/shorecat_server.dart \
       -o /shorecat_server

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --uid 10001 --create-home shorecat \
    && mkdir /data && chown shorecat:shorecat /data
COPY --from=server /shorecat_server /app/shorecat_server
COPY --from=dashboard /dashboard/build/web/ /app/dashboard/
ENV SHORECAT_DATA=/data \
    SHORECAT_HOST=0.0.0.0 \
    SHORECAT_PORT=8080 \
    SHORECAT_DASHBOARD=/app/dashboard
USER shorecat
WORKDIR /app
VOLUME ["/data"]
EXPOSE 8080
STOPSIGNAL SIGTERM
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD ["/app/shorecat_server", "--health-check"]
ENTRYPOINT ["/app/shorecat_server"]
