#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.local.yml"
ENV_FILE="${ROOT_DIR}/.env.example"
BACKEND_CONTEXT="$(cd "${ROOT_DIR}/../../oncue-backend" && pwd)"
VOICE_CONTEXT="$(cd "${ROOT_DIR}/../../oncue-voice" && pwd)"

if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
  echo "docker compose is required to validate the local stack" >&2
  exit 1
fi

CONFIG_OUTPUT="$(docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" config)"

assert_contains() {
  local expected="$1"
  if ! grep -Fq -- "${expected}" <<<"${CONFIG_OUTPUT}"; then
    echo "missing compose configuration: ${expected}" >&2
    exit 1
  fi
}

for service in mysql redis oncue-backend oncue-voice coturn; do
  assert_contains "  ${service}:"
done

assert_contains "context: ${BACKEND_CONTEXT}"
assert_contains "context: ${VOICE_CONTEXT}"
assert_contains "healthcheck:"
assert_contains "DB_URL: jdbc:mysql://mysql:3306/oncue"
assert_contains "REDIS_HOST: redis"
assert_contains "VOICE_INTERNAL_SERVICE_TOKEN: replace-with-a-local-voice-token"
assert_contains "ONCUE_VOICE_SIGNALING_URL: ws://localhost:8000/v1/signaling"
assert_contains "BACKEND_INTERNAL_URL: http://oncue-backend:8080"
assert_contains "ONCUE_VOICE_TURN_URLS: turn:localhost:3478?transport=udp,turn:localhost:3478?transport=tcp"

echo "compose config is valid"
