# syntax=docker/dockerfile:1
#
# Production image for the CI/CD demo site.
#   Stage 1 writes build metadata (build number, commit, branch, time) to build-info.json.
#   Stage 2 serves the static site from a non-root nginx image.
#
# Build:  docker build --build-arg BUILD_NUMBER=42 --build-arg GIT_COMMIT=$(git rev-parse --short HEAD) -t ci-cd-demo .

# ---------- Stage 1: build metadata ----------
FROM alpine:3.22 AS metadata

SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

ARG BUILD_NUMBER=local
ARG GIT_COMMIT=unknown
ARG GIT_BRANCH=unknown
ARG BUILD_DATE=unknown
ARG BUILD_URL=""

# Only allow safe characters so the values cannot break the JSON document.
RUN set -eu; \
    clean() { printf '%s' "$1" | tr -cd 'A-Za-z0-9._:/#+@-'; }; \
    printf '{\n  "buildNumber": "%s",\n  "gitCommit": "%s",\n  "gitBranch": "%s",\n  "buildDate": "%s",\n  "buildUrl": "%s"\n}\n' \
      "$(clean "$BUILD_NUMBER")" "$(clean "$GIT_COMMIT")" "$(clean "$GIT_BRANCH")" \
      "$(clean "$BUILD_DATE")" "$(clean "$BUILD_URL")" > /build-info.json; \
    cat /build-info.json

# ---------- Stage 2: runtime ----------
FROM nginxinc/nginx-unprivileged:1.29-alpine

ARG BUILD_NUMBER=local
ARG GIT_COMMIT=unknown
ARG BUILD_DATE=unknown

LABEL org.opencontainers.image.title="ci-cd-demo" \
      org.opencontainers.image.description="Static site delivered by a Jenkins + Docker + AWS ECR pipeline" \
      org.opencontainers.image.source="https://github.com/Aslam-space/ci-cd-pipeline-demo" \
      org.opencontainers.image.revision="${GIT_COMMIT}" \
      org.opencontainers.image.version="${BUILD_NUMBER}" \
      org.opencontainers.image.created="${BUILD_DATE}"

COPY --chown=nginx:nginx docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY --chown=nginx:nginx app/ /usr/share/nginx/html/
COPY --chown=nginx:nginx --from=metadata /build-info.json /usr/share/nginx/html/build-info.json

USER nginx
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8080/healthz || exit 1
