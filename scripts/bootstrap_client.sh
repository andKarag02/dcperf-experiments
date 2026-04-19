#!/usr/bin/env bash
set -euo pipefail

echo "[INFO] bootstrap_client.sh started"

# Locate bootstrap_common.sh next to this script.
# If not found (e.g. run via `curl | bash`), download it from GitHub.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "$HOME")"
COMMON_SCRIPT="${SCRIPT_DIR}/bootstrap_common.sh"
REPO_RAW="https://raw.githubusercontent.com/andKarag02/dcperf-experiments/main/scripts"

if [ ! -f "${COMMON_SCRIPT}" ]; then
  echo "[INFO] bootstrap_common.sh not found locally — downloading from GitHub"
  curl -fsSL "${REPO_RAW}/bootstrap_common.sh" -o /tmp/bootstrap_common.sh
  COMMON_SCRIPT="/tmp/bootstrap_common.sh"
fi

bash "${COMMON_SCRIPT}"

cd "$HOME/DCPerf"

if [ -f "$HOME/DCPerf/venv/bin/activate" ]; then
  # shellcheck disable=SC1091
  source "$HOME/DCPerf/venv/bin/activate"
else
  echo "[ERROR] Virtual environment not found at $HOME/DCPerf/venv"
  exit 1
fi

echo "[INFO] Creating tao_client.sh"
cat > "$HOME/DCPerf/tao_client.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

DCPERF_DIR="${HOME}/DCPerf"
SERVER_HOSTNAME="${SERVER_HOSTNAME:-192.168.1.10}"
SERVER_MEMSIZE_GB="${SERVER_MEMSIZE_GB:-16}"
WARMUP_TIME="${WARMUP_TIME:-300}"
TEST_TIME="${TEST_TIME:-300}"
SERVER_PORT="${SERVER_PORT:-11211}"
WAIT_AFTER_WARMUP="${WAIT_AFTER_WARMUP:-5}"
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

echo "[INFO] TaoBench client run configuration"
echo "[INFO] SERVER_HOSTNAME=$SERVER_HOSTNAME"
echo "[INFO] SERVER_MEMSIZE_GB=$SERVER_MEMSIZE_GB"
echo "[INFO] WARMUP_TIME=$WARMUP_TIME"
echo "[INFO] TEST_TIME=$TEST_TIME"
echo "[INFO] SERVER_PORT=$SERVER_PORT"
echo "[INFO] WAIT_AFTER_WARMUP=$WAIT_AFTER_WARMUP"
echo "[INFO] OPEN_FILES_LIMIT=$(ulimit -n)"

cat /proc/$$/limits | grep "open files" || true
which python || true
python --version || true

./benchpress_cli.py run tao_bench_custom -r client -i "{\"server_hostname\":\"${SERVER_HOSTNAME}\",\"server_memsize\":${SERVER_MEMSIZE_GB},\"warmup_time\":${WARMUP_TIME},\"test_time\":${TEST_TIME},\"server_port_number\":${SERVER_PORT},\"wait_after_warmup\":${WAIT_AFTER_WARMUP}}"
EOF

chmod +x "$HOME/DCPerf/tao_client.sh"

echo "[INFO] bootstrap_client.sh completed"