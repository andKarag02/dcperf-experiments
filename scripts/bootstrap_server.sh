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

echo "[INFO] bootstrap_server.sh completed"