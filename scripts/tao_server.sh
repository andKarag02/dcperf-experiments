#!/usr/bin/env bash
set -euo pipefail

DCPERF_DIR="${HOME}/DCPerf"
INTERFACE_NAME="${INTERFACE_NAME:-enp3s0f0}"
SERVER_HOSTNAME="${SERVER_HOSTNAME:-192.168.1.10}"
NUM_CLIENTS="${NUM_CLIENTS:-2}"
MEMSIZE_GB="${MEMSIZE_GB:-16}"
WARMUP_TIME="${WARMUP_TIME:-300}"
TEST_TIME="${TEST_TIME:-300}"
PORT_START="${PORT_START:-11211}"
OPEN_FILES_LIMIT="${OPEN_FILES_LIMIT:-65536}"

cd "$DCPERF_DIR"

if [ -f "$DCPERF_DIR/venv/bin/activate" ]; then
    source "$DCPERF_DIR/venv/bin/activate"
fi

ulimit -n "$OPEN_FILES_LIMIT"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_DIR="$DCPERF_DIR/server_results"
mkdir -p "$RESULTS_DIR"

CONSOLE_LOG="$RESULTS_DIR/server_run_${TIMESTAMP}.log"
INFO_FILE="$RESULTS_DIR/server_info_${TIMESTAMP}.txt"
METRICS_LIST="$RESULTS_DIR/server_metrics_files_${TIMESTAMP}.txt"

{
  echo "[INFO] TaoBench server run configuration"
  echo "[INFO] TIMESTAMP=$TIMESTAMP"
  echo "[INFO] INTERFACE_NAME=$INTERFACE_NAME"
  echo "[INFO] SERVER_HOSTNAME=$SERVER_HOSTNAME"
  echo "[INFO] NUM_CLIENTS=$NUM_CLIENTS"
  echo "[INFO] MEMSIZE_GB=$MEMSIZE_GB"
  echo "[INFO] WARMUP_TIME=$WARMUP_TIME"
  echo "[INFO] TEST_TIME=$TEST_TIME"
  echo "[INFO] PORT_START=$PORT_START"
  echo "[INFO] OPEN_FILES_LIMIT=$(ulimit -n)"
  echo
  echo "[INFO] Host info"
  hostname || true
  echo
  echo "[INFO] Open files limit"
  cat /proc/$$/limits | grep "open files" || true
  echo
  echo "[INFO] numactl"
  which numactl || true
  echo
  echo "[INFO] Interface/IP info"
  ip -br a || true
  echo
  echo "[INFO] Route checks"
  ip route || true
} | tee "$INFO_FILE"

SERVER_PARAMS="{
  \"interface_name\":\"${INTERFACE_NAME}\",
  \"server_hostname\":\"${SERVER_HOSTNAME}\",
  \"num_clients\":${NUM_CLIENTS},
  \"memsize\":${MEMSIZE_GB},
  \"warmup_time\":${WARMUP_TIME},
  \"test_time\":${TEST_TIME},
  \"port_number_start\":${PORT_START},
  \"disable_tls\":1
}"

./benchpress_cli.py run tao_bench_autoscale \
  -i "$SERVER_PARAMS" \
    2>&1 | tee "$CONSOLE_LOG"

echo "[INFO] Collecting benchmark metric files..."
find "$DCPERF_DIR" -path '*/benchmark_metrics_*/*tao-bench-server*.log' -type f | sort > "$METRICS_LIST" || true

echo "[INFO] Latest matching metric files:"
tail -n 20 "$METRICS_LIST" 2>/dev/null || true

echo "[INFO] Done. Results in $RESULTS_DIR/"
ls -la "$RESULTS_DIR/" || true
