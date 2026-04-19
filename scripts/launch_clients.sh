#!/usr/bin/env bash
set -euo pipefail

# Launch TaoBench clients on both client nodes in parallel.
# Run this from the server (or any node with SSH access to both clients).

CLIENT1_HOST="${CLIENT1_HOST:-192.168.1.11}"
CLIENT2_HOST="${CLIENT2_HOST:-192.168.1.12}"
SSH_USER="${SSH_USER:-$(whoami)}"
SSH_OPTS=(-o StrictHostKeyChecking=no -o ConnectTimeout=10)

# Propagate configurable parameters to each client
SERVER_HOSTNAME="${SERVER_HOSTNAME:-192.168.1.10}"
SERVER_MEMSIZE_GB="${SERVER_MEMSIZE_GB:-16}"
WARMUP_TIME="${WARMUP_TIME:-300}"
TEST_TIME="${TEST_TIME:-300}"
SERVER_PORT="${SERVER_PORT:-11211}"
WAIT_AFTER_WARMUP="${WAIT_AFTER_WARMUP:-5}"
OPEN_FILES_LIMIT="${OPEN_FILES_LIMIT:-65536}"

REMOTE_ENV="SERVER_HOSTNAME=${SERVER_HOSTNAME} \
SERVER_MEMSIZE_GB=${SERVER_MEMSIZE_GB} \
WARMUP_TIME=${WARMUP_TIME} \
TEST_TIME=${TEST_TIME} \
SERVER_PORT=${SERVER_PORT} \
WAIT_AFTER_WARMUP=${WAIT_AFTER_WARMUP} \
OPEN_FILES_LIMIT=${OPEN_FILES_LIMIT}"

run_client() {
  local host="$1"
  local label="$2"
  echo "[INFO] Starting TaoBench client on ${label} (${host})"
  # shellcheck disable=SC2029
  ssh "${SSH_OPTS[@]}" "${SSH_USER}@${host}" "env ${REMOTE_ENV} bash \$HOME/DCPerf/tao_client.sh" \
    2>&1 | sed "s/^/[${label}] /" &
}

run_client "$CLIENT1_HOST" "client1"
run_client "$CLIENT2_HOST" "client2"

echo "[INFO] Waiting for both clients to finish..."
wait
echo "[INFO] All clients completed."
