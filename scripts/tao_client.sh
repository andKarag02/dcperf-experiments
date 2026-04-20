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
CLIENTS_PER_THREAD="${CLIENTS_PER_THREAD:-150}"

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
echo "[INFO] CLIENTS_PER_THREAD=$CLIENTS_PER_THREAD"
echo "[INFO] OPEN_FILES_LIMIT=$(ulimit -n)"

cat /proc/$$/limits | grep "open files" || true
which python || true
python --version || true

./benchpress_cli.py run tao_bench_custom -r client -i "{\"server_hostname\":\"${SERVER_HOSTNAME}\",\"server_memsize\":${SERVER_MEMSIZE_GB},\"warmup_time\":${WARMUP_TIME},\"test_time\":${TEST_TIME},\"server_port_number\":${SERVER_PORT},\"wait_after_warmup\":${WAIT_AFTER_WARMUP},\"clients_per_thread\":${CLIENTS_PER_THREAD}}"
