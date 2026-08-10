#!/usr/bin/env bash
set -Eeuo pipefail

pids=()
names=()
shutting_down=0

terminate_all() {
  shutting_down=1

  for pid in "${pids[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      kill -TERM "$pid" 2>/dev/null || true
    fi
  done

  set +e
  for pid in "${pids[@]}"; do
    wait "$pid"
  done
  set -e
}

start_service() {
  local name="$1"
  shift

  "$@" &
  local pid="$!"
  pids+=("$pid")
  names+=("$name")
  echo "Started ${name} with PID ${pid}"
}

wait_for_port() {
  local name="$1"
  local port="$2"
  local attempts="${3:-30}"
  local ready=1

  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if node -e '
      const net = require("node:net");
      const port = Number(process.argv[1]);
      const socket = net.createConnection({ host: "127.0.0.1", port });
      const done = (code) => {
        socket.destroy();
        process.exit(code);
      };
      socket.setTimeout(500, () => done(1));
      socket.once("connect", () => done(0));
      socket.once("error", () => done(1));
    ' "$port"; then
      ready=0
      echo "${name} is accepting connections on ${port}"
      break
    fi

    sleep 1
  done

  if [[ "$ready" -eq 0 ]]; then
    return 0
  fi

  echo "${name} did not become ready on ${port}" >&2
  terminate_all
  return 1
}

handle_signal() {
  echo "Received shutdown signal; stopping Bourbon services"
  terminate_all
  exit 0
}

trap handle_signal SIGTERM SIGINT

start_service "runtime-api" env PORT=3001 node /app/api/server.js
start_service "website" env PORT=3000 HOSTNAME=0.0.0.0 node /app/web/server.js
wait_for_port "runtime-api" 3001
wait_for_port "website" 3000
start_service "caddy" caddy run --config /app/Caddyfile --adapter caddyfile

set +e
wait -n "${pids[@]}"
status="$?"
set -e

if [[ "$shutting_down" -eq 0 ]]; then
  if [[ "$status" -eq 0 ]]; then
    status=1
  fi

  echo "A required Bourbon service exited unexpectedly; stopping container"
  terminate_all
  exit "$status"
fi
