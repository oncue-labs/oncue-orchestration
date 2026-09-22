#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.local.yml"
ENV_FILE="${1:-${ROOT_DIR}/.env}"
PROJECT_NAME="${COMPOSE_PROJECT_NAME:-oncue-smoke}"
WAIT_ATTEMPTS="${ONCUE_COMPOSE_WAIT_ATTEMPTS:-60}"
WAIT_INTERVAL="${ONCUE_COMPOSE_WAIT_INTERVAL_SECONDS:-2}"

if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
  echo "docker compose is required to run the local stack smoke test" >&2
  exit 1
fi

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "environment file not found: ${ENV_FILE}" >&2
  echo "copy .env.template to .env.local and fill local values first" >&2
  exit 1
fi

COMPOSE=(
  docker compose
  --project-name "${PROJECT_NAME}"
  --env-file "${ENV_FILE}"
  --file "${COMPOSE_FILE}"
)

cleanup() {
  if [[ "${KEEP_COMPOSE_STACK:-0}" != "1" ]]; then
    "${COMPOSE[@]}" down --remove-orphans >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT

wait_for_container() {
  local service="$1"
  local expected="$2"
  local attempt
  local container_id
  local status

  for ((attempt = 1; attempt <= WAIT_ATTEMPTS; attempt++)); do
    container_id="$("${COMPOSE[@]}" ps --quiet "${service}")"
    if [[ -n "${container_id}" ]]; then
      if [[ "${expected}" == "healthy" ]]; then
        status="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "${container_id}")"
      else
        status="$(docker inspect --format '{{.State.Status}}' "${container_id}")"
      fi

      if [[ "${status}" == "${expected}" ]]; then
        return 0
      fi

      if [[ "${status}" == "exited" || "${status}" == "dead" ]]; then
        echo "${service} stopped before reaching ${expected}" >&2
        return 1
      fi
    fi

    sleep "${WAIT_INTERVAL}"
  done

  echo "timed out waiting for ${service} to become ${expected}" >&2
  return 1
}

wait_for_http() {
  local service_name="$1"
  local url="$2"
  local attempt

  for ((attempt = 1; attempt <= WAIT_ATTEMPTS; attempt++)); do
    if curl --fail --silent --show-error "${url}" >/dev/null 2>&1; then
      return 0
    fi
    sleep "${WAIT_INTERVAL}"
  done

  echo "timed out waiting for ${service_name} HTTP endpoint: ${url}" >&2
  return 1
}

compose_host_endpoint() {
  local service="$1"
  local container_port="$2"
  local attempt
  local endpoint

  for ((attempt = 1; attempt <= WAIT_ATTEMPTS; attempt++)); do
    endpoint="$("${COMPOSE[@]}" port "${service}" "${container_port}" 2>/dev/null || true)"
    if [[ -n "${endpoint}" ]]; then
      printf '%s' "${endpoint}"
      return 0
    fi
    sleep "${WAIT_INTERVAL}"
  done

  echo "timed out waiting for ${service} port mapping" >&2
  return 1
}

echo "validating Compose configuration"
"${COMPOSE[@]}" config --quiet

echo "starting local stack"
"${COMPOSE[@]}" up --build --detach

echo "waiting for container health"
wait_for_container mysql healthy
wait_for_container redis healthy
wait_for_container oncue-backend healthy
wait_for_container oncue-voice healthy
wait_for_container coturn running

echo "checking host health endpoints"
backend_endpoint="$(compose_host_endpoint oncue-backend 8080)"
voice_endpoint="$(compose_host_endpoint oncue-voice 8000)"
wait_for_http oncue-backend "http://${backend_endpoint}/actuator/health"
wait_for_http oncue-voice "http://${voice_endpoint}/health"

echo "checking service-to-service connectivity"
"${COMPOSE[@]}" exec --no-TTY oncue-backend \
  wget --quiet --output-document=- http://oncue-voice:8000/health >/dev/null
"${COMPOSE[@]}" exec --no-TTY oncue-voice \
  python -c 'import urllib.request; urllib.request.urlopen("http://oncue-backend:8080/actuator/health")'
"${COMPOSE[@]}" exec --no-TTY oncue-voice \
  python -c 'import redis; assert redis.Redis(host="redis", port=6379).ping()'

echo "compose smoke test passed"
