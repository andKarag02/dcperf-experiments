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
# Tuned default used for the CloudLab experiment profile; override if your node cannot sustain it.
CLIENTS_PER_THREAD="${CLIENTS_PER_THREAD:-380}"
DISABLE_TLS="${DISABLE_TLS:-1}"

cd "$DCPERF_DIR"

if [ -f "$DCPERF_DIR/venv/bin/activate" ]; then
  # shellcheck disable=SC1091
  source "$DCPERF_DIR/venv/bin/activate"
else
  echo "[ERROR] Virtual environment not found at $DCPERF_DIR/venv"
  exit 1
fi

ulimit -n "$OPEN_FILES_LIMIT"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_DIR="$DCPERF_DIR/client_results"
mkdir -p "$RESULTS_DIR"

LOGFILE="$RESULTS_DIR/client_run_${TIMESTAMP}.log"
LATFILE="$RESULTS_DIR/latency_${TIMESTAMP}.txt"

echo "================ CLIENT CONFIG ================"
echo "SERVER_HOSTNAME=$SERVER_HOSTNAME"
echo "SERVER_MEMSIZE_GB=$SERVER_MEMSIZE_GB"
echo "WARMUP_TIME=$WARMUP_TIME"
echo "TEST_TIME=$TEST_TIME"
echo "SERVER_PORT=$SERVER_PORT"
echo "WAIT_AFTER_WARMUP=$WAIT_AFTER_WARMUP"
echo "CLIENTS_PER_THREAD=$CLIENTS_PER_THREAD"
echo "DISABLE_TLS=$DISABLE_TLS"
echo "OPEN_FILES_LIMIT=$(ulimit -n)"
echo "=============================================="

CLIENT_PARAMS="{
  \"server_hostname\":\"${SERVER_HOSTNAME}\",
  \"server_memsize\":${SERVER_MEMSIZE_GB},
  \"warmup_time\":${WARMUP_TIME},
  \"test_time\":${TEST_TIME},
  \"server_port_number\":${SERVER_PORT},
  \"wait_after_warmup\":${WAIT_AFTER_WARMUP},
  \"clients_per_thread\":${CLIENTS_PER_THREAD},
  \"disable_tls\":${DISABLE_TLS}
}"

./benchpress_cli.py run tao_bench_custom \
  -r client \
  -i "$CLIENT_PARAMS" \
  2>&1 | tee "$LOGFILE"

# Extract summary from the "Results report:" section to the latency file.
awk 'BEGIN{IGNORECASE=1} /Results report:/{flag=1} flag{print}' "$LOGFILE" > "$LATFILE" || true
if [ ! -s "$LATFILE" ]; then
  echo "[WARN] Latency summary file is empty; check $LOGFILE for benchmark output format changes."
fi

echo "[INFO] Done. Results in $RESULTS_DIR/"
