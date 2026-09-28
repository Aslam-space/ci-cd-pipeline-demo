#!/usr/bin/env bash
# Deploy an image as the live container, with a health gate and automatic rollback.
#
#   1. Pull the image (logging in to ECR first if it is an ECR image).
#   2. Stop the running container and keep it as "<name>-previous".
#   3. Start the new container and wait for its Docker HEALTHCHECK.
#   4. Healthy   -> remove the previous container.
#      Unhealthy -> remove the new container and restart the previous one.
#
# Usage:
#   scripts/deploy.sh <image>
#   IMAGE=<image> scripts/deploy.sh
#
# Environment:
#   CONTAINER_NAME  (default: ci-cd-container)
#   HOST_PORT       (default: 80)
#   HEALTH_TIMEOUT  seconds to wait for a healthy container (default: 60)
#   AWS_REGION      used for ECR login (default: parsed from the image, else ap-south-1)
set -euo pipefail

IMAGE="${1:-${IMAGE:-}}"
CONTAINER_NAME="${CONTAINER_NAME:-ci-cd-container}"
HOST_PORT="${HOST_PORT:-80}"
CONTAINER_PORT=8080
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-60}"
PREVIOUS="${CONTAINER_NAME}-previous"

[[ -n "$IMAGE" ]] || { echo "usage: $0 <image>" >&2; exit 2; }

log() { echo "[deploy] $*"; }

container_exists() { docker container inspect "$1" >/dev/null 2>&1; }

wait_healthy() {
    local name="$1" status
    for ((i = 0; i < HEALTH_TIMEOUT; i++)); do
        status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$name" 2>/dev/null || echo missing)"
        case "$status" in
            healthy) return 0 ;;
            unhealthy | exited | dead | missing) return 1 ;;
        esac
        sleep 1
    done
    return 1
}

# ---------- 1. Pull ----------
if [[ "$IMAGE" =~ ^([0-9]{12})\.dkr\.ecr\.([a-z0-9-]+)\.amazonaws\.com/ ]]; then
    registry="${IMAGE%%/*}"
    region="${AWS_REGION:-${BASH_REMATCH[2]}}"
    log "Logging in to ECR ${registry}"
    aws ecr get-login-password --region "$region" | docker login --username AWS --password-stdin "$registry"
fi

if [[ "$IMAGE" == */* ]]; then
    log "Pulling ${IMAGE}"
    docker pull "$IMAGE"
else
    log "Using local image ${IMAGE}"
    docker image inspect "$IMAGE" >/dev/null
fi

# ---------- 2. Park the current container ----------
container_exists "$PREVIOUS" && docker rm -f "$PREVIOUS" >/dev/null
if container_exists "$CONTAINER_NAME"; then
    log "Stopping current container (kept as ${PREVIOUS} for rollback)"
    docker stop "$CONTAINER_NAME" >/dev/null
    docker rename "$CONTAINER_NAME" "$PREVIOUS"
fi

# ---------- 3. Start the new container ----------
log "Starting ${IMAGE} on port ${HOST_PORT}"
docker run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    --read-only \
    --tmpfs /tmp \
    --cap-drop ALL \
    --security-opt no-new-privileges \
    -p "${HOST_PORT}:${CONTAINER_PORT}" \
    "$IMAGE" >/dev/null

# ---------- 4. Health gate ----------
if wait_healthy "$CONTAINER_NAME"; then
    log "✅ New container is healthy"
    container_exists "$PREVIOUS" && docker rm "$PREVIOUS" >/dev/null
    docker image prune -f >/dev/null || true
    docker ps --filter "name=^${CONTAINER_NAME}$"
    exit 0
fi

log "❌ New container failed its health check, rolling back"
docker logs --tail 50 "$CONTAINER_NAME" >&2 || true
docker rm -f "$CONTAINER_NAME" >/dev/null || true

if container_exists "$PREVIOUS"; then
    docker rename "$PREVIOUS" "$CONTAINER_NAME"
    docker start "$CONTAINER_NAME" >/dev/null
    if wait_healthy "$CONTAINER_NAME"; then
        log "↩️  Rolled back to the previous container"
    else
        log "⚠️  Previous container also failed to become healthy"
    fi
else
    log "No previous container to roll back to"
fi
exit 1
