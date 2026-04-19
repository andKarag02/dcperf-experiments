#!/usr/bin/env bash
set -euo pipefail

echo "[INFO] bootstrap_server.sh started"

bash "$HOME/bootstrap_common.sh"

cd "$HOME/DCPerf"

if [ -f "$HOME/DCPerf/venv/bin/activate" ]; then
  # shellcheck disable=SC1091
  source "$HOME/DCPerf/venv/bin/activate"
else
  echo "[ERROR] Virtual environment not found at $HOME/DCPerf/venv"
  exit 1
fi

echo "[INFO] Installing TaoBench autoscale"
./benchpress_cli.py install tao_bench_autoscale

echo "[INFO] Creating tao_server.sh"
cat > "$HOME/DCPerf/tao_server.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

DCPERF_DIR="${HOME}/DCPerf"
INTERFACE_NAME="${INTERFACE_NAME:-eno1}"
SERVER_HOSTNAME="${SERVER_HOSTNAME:-192.168.1.10}"
NUM_CLIENTS="${NUM_CLIENTS:-2}"
MEMSIZE_GB="${MEMSIZE_GB:-16}"
WARMUP_TIME="${WARMUP_TIME:-300}"
TEST_TIME="${TEST_TIME:-300}"
PORT_START="${PORT_START:-11211}"
OPEN_FILES_LIMIT="${OPEN_FILES_LIMIT:-65536}"

cd "$DCPERF_DIR"

if [ -f "$DCPERF_DIR/venv/bin/activate" ]; then
  # shellcheck disable=SC1091
  source "$DCPERF_DIR/venv/bin/activate"
else
  echo "[ERROR] Virtual environment not found at $DCPERF_DIR/venv"
  exit 1
fi

ulimit -n "$OPEN_FILES_LIMIT"

echo "[INFO] TaoBench server run configuration"
echo "[INFO] INTERFACE_NAME=$INTERFACE_NAME"
echo "[INFO] SERVER_HOSTNAME=$SERVER_HOSTNAME"
echo "[INFO] NUM_CLIENTS=$NUM_CLIENTS"
echo "[INFO] MEMSIZE_GB=$MEMSIZE_GB"
echo "[INFO] WARMUP_TIME=$WARMUP_TIME"
echo "[INFO] TEST_TIME=$TEST_TIME"
echo "[INFO] PORT_START=$PORT_START"
echo "[INFO] OPEN_FILES_LIMIT=$(ulimit -n)"

cat /proc/$$/limits | grep "open files" || true
which numactl || true
which python || true
python --version || true

./benchpress_cli.py run tao_bench_autoscale -i "{\"interface_name\":\"${INTERFACE_NAME}\",\"server_hostname\":\"${SERVER_HOSTNAME}\",\"num_clients\":${NUM_CLIENTS},\"memsize\":${MEMSIZE_GB},\"warmup_time\":${WARMUP_TIME},\"test_time\":${TEST_TIME},\"port_number_start\":${PORT_START}}"
EOF

chmod +x "$HOME/DCPerf/tao_server.sh"

echo "[INFO] Creating monitor_tao.sh"
cat > "$HOME/DCPerf/monitor_tao.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cd "$HOME/DCPerf"

echo "==== Open file limits ===="
ulimit -n || true
cat /proc/$$/limits | grep "open files" || true
echo

echo "==== Processes ===="
ps -ef | grep -E 'tao_bench|numactl|taskset' | grep -v grep || true
echo

echo "==== Live logs ===="
ls -1t tao-bench-server-*.log 2>/dev/null | head || true
echo

LATEST="$(ls -1t tao-bench-server-*.log 2>/dev/null | head -n 1 || true)"
if [ -n "${LATEST}" ]; then
  echo "==== tail -n 20 ${LATEST} ===="
  tail -n 20 "${LATEST}"
else
  echo "No live tao-bench server log in current directory."
fi
EOF

chmod +x "$HOME/DCPerf/monitor_tao.sh"

echo "[INFO] Creating launch_clients.sh"
cat > "$HOME/launch_clients.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

CLIENT1_HOST="${CLIENT1_HOST:-192.168.1.11}"
CLIENT2_HOST="${CLIENT2_HOST:-192.168.1.12}"
SSH_USER="${SSH_USER:-$(whoami)}"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10"

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
  ssh ${SSH_OPTS} "${SSH_USER}@${host}" "env ${REMOTE_ENV} bash \$HOME/DCPerf/tao_client.sh" \
    2>&1 | sed "s/^/[${label}] /" &
}

run_client "$CLIENT1_HOST" "client1"
run_client "$CLIENT2_HOST" "client2"

echo "[INFO] Waiting for both clients to finish..."
wait
echo "[INFO] All clients completed."
EOF

chmod +x "$HOME/launch_clients.sh"

echo "[INFO] bootstrap_server.sh completed"