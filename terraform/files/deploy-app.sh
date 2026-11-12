#!/usr/bin/env bash
# Deploys an image, smoke tests /health, and rolls back to the previous image on failure.
# Usage: deploy-app.sh <image-ref> [app-version]
set -euo pipefail

APP_NAME="devops-task"
STATE_DIR="/opt/${APP_NAME}"
STATE_FILE="${STATE_DIR}/current"
CONF_FILE="${STATE_DIR}/deploy.conf"

IMAGE="${1:?usage: deploy-app.sh <image-ref> [app-version]}"
APP_VERSION="${2:-${IMAGE##*:}}"

# shellcheck source=/dev/null
source "${CONF_FILE}"

log() {
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}

run_container() {
  local image="$1" version="$2"
  docker rm -f "${APP_NAME}" >/dev/null 2>&1 || true
  docker run -d \
    --name "${APP_NAME}" \
    --restart unless-stopped \
    --read-only \
    --tmpfs /tmp \
    --security-opt no-new-privileges:true \
    --memory 128m \
    --cpus 0.5 \
    -p "${APP_PORT}:8080" \
    -e PORT=8080 \
    -e LOG_LEVEL=info \
    -e ENV_NAME="${ENV_NAME}" \
    -e APP_VERSION="${version}" \
    --log-driver awslogs \
    --log-opt "awslogs-region=${REGION}" \
    --log-opt "awslogs-group=${LOG_GROUP}" \
    --log-opt "awslogs-stream=${APP_NAME}" \
    "${image}" >/dev/null
}

# smoke_test() {
#   local i
#   for i in $(seq 1 15); do
#     if curl -fsS --max-time 3 "http://localhost:${APP_PORT}/health" >/dev/null; then
#       return 0
#     fi
#     sleep 2
#   done
#   return 1
# }


smoke_test() {
  for _ in {1..15}; do
    if curl -fsS --max-time 3 "http://localhost:${APP_PORT}/health" >/dev/null; then
      return 0
    fi
    sleep 2
  done
  return 1
}


PREV_IMAGE=""
PREV_VERSION=""
if [[ -f "${STATE_FILE}" ]]; then
  read -r PREV_IMAGE PREV_VERSION < "${STATE_FILE}" || true
fi

log "Logging in to ${REGISTRY}"
aws ecr get-login-password --region "${REGION}" \
  | docker login --username AWS --password-stdin "${REGISTRY}" >/dev/null

log "Pulling ${IMAGE}"
docker pull "${IMAGE}" >/dev/null

log "Starting ${IMAGE} (version ${APP_VERSION})"
run_container "${IMAGE}" "${APP_VERSION}"

if smoke_test; then
  echo "${IMAGE} ${APP_VERSION}" > "${STATE_FILE}"
  log "Deploy succeeded"
  exit 0
fi

log "Smoke test failed"
docker logs --tail 30 "${APP_NAME}" || true

if [[ -n "${PREV_IMAGE}" ]]; then
  log "Rolling back to ${PREV_IMAGE}"
  run_container "${PREV_IMAGE}" "${PREV_VERSION}"
  if smoke_test; then
    log "Rollback succeeded"
  else
    log "Rollback FAILED, manual action needed"
  fi
else
  log "No previous image, removing failed container"
  docker rm -f "${APP_NAME}" >/dev/null 2>&1 || true
fi

exit 1