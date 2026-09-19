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

assert_not_contains() {
  local unexpected="$1"
  if grep -Fq -- "${unexpected}" <<<"${CONFIG_OUTPUT}"; then
    echo "unexpected compose configuration: ${unexpected}" >&2
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
assert_contains "ONCUE_AUTH_X_CLIENT_ID: replace-with-a-local-x-client-id"
assert_contains "X_REDIRECT_URI: com.oncue.oncuemobile://oauth/x/callback"
assert_contains "VOICE_INTERNAL_SERVICE_TOKEN: replace-with-a-local-voice-token"
assert_contains "APNS_KEY_ID: replace-with-local-apns-key-id"
assert_contains "APNS_TEAM_ID: replace-with-local-apple-team-id"
assert_contains "APNS_BUNDLE_ID: com.oncue.oncueMobile"
assert_contains "APNS_PRIVATE_KEY_FILE: /run/secrets/apns-auth-key.p8"
assert_contains 'VOICE_JWT_PRIVATE_KEY: ""'
assert_contains "ONCUE_VOICE_SIGNALING_URL: ws://192.168.200.109:8000/v1/signaling"
assert_contains "ONCUE_VOICE_ICE_SERVERS_URLS: stun:192.168.200.109:3478,turn:192.168.200.109:3478?transport=udp,turn:192.168.200.109:3478?transport=tcp"
assert_contains 'ONCUE_LOCAL_TEST_CALL_ENABLED: "true"'
assert_contains 'ONCUE_VOICE_JWT_PUBLIC_KEY: ""'
assert_contains "BACKEND_INTERNAL_URL: http://oncue-backend:8080"
assert_contains "ONCUE_VOICE_RUNTIME: realtime"
assert_contains "REDIS_HOST: redis"
assert_contains "REDIS_PORT:"
assert_contains "ONCUE_VOICE_TURN_URLS: turn:coturn:3478?transport=udp,turn:coturn:3478?transport=tcp"
assert_contains "--external-ip=192.168.200.109"
assert_not_contains "ONCUE_VOICE_SIGNALING_URL: ws://localhost:8000/v1/signaling"
assert_not_contains "ONCUE_VOICE_ICE_SERVERS_URLS: stun:localhost:3478"

echo "compose config is valid"
