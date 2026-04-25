#!/usr/bin/env bash
set -euo pipefail

RUNS="${RUNS:-5}"

SERVER_IP="${SERVER_IP:-192.168.1.10}"
CLIENT1="${CLIENT1:-192.168.1.11}"
CLIENT2="${CLIENT2:-192.168.1.12}"

MEMSIZE="${MEMSIZE:-16}"
WARMUP="${WARMUP:-900}"
TEST="${TEST:-300}"
PORT="${PORT:-11211}"

NUM_CLIENTS="${NUM_CLIENTS:-2}"
INTERFACE_NAME="${INTERFACE_NAME:-enp3s0f0}"
OPEN_FILES_LIMIT="${OPEN_FILES_LIMIT:-65536}"
WAIT_AFTER_WARMUP="${WAIT_AFTER_WARMUP:-5}"

STARTUP_WAIT="${STARTUP_WAIT:-20}"
COOLDOWN_WAIT="${COOLDOWN_WAIT:-25}"
# shellcheck disable=SC2206
LOADS=(${LOADS:-100 150 200 250 300 340 380 400})

BASE_RESULTS="${HOME}/DCPerf/exp_runs"
mkdir -p "$BASE_RESULTS"

log() {
  echo "[INFO] $*"
}

remote_ssh() {
  local host="$1"
  shift
  ssh -o BatchMode=yes -o StrictHostKeyChecking=no "$host" "$@"
}

remote_scp() {
  local src="$1"
  local dst="$2"
  scp -o BatchMode=yes -o StrictHostKeyChecking=no "$src" "$dst"
}

latest_local_file() {
  # shellcheck disable=SC2086
  ls -t $1 2>/dev/null | head -1 || true
}

extract_client_metrics() {
  local file="$1"
  python3 - "$file" <<'PY'
import csv, re, sys
from pathlib import Path

path = Path(sys.argv[1])
txt = path.read_text(encoding='utf-8', errors='ignore')

def grab(pattern: str) -> str:
    m = re.search(pattern, txt, re.MULTILINE)
    return m.group(1) if m else ""

# qps from JSON metrics block
qps = grab(r'"metrics":\s*\{[^}]*"qps":\s*([0-9.]+)')

# Prefer parsing the ALL STATS Gets row because columns are stable.
gets_row = None
for line in txt.splitlines():
    if re.match(r'^Gets\s+', line):
        gets_row = line.strip()
        break

avg = p50 = p99 = p999 = ""
if gets_row:
    cols = re.split(r'\s+', gets_row)
    # Expected layout:
    # Gets Ops/sec Hits/sec Misses/sec Avg.Lat p50 p99 p99.9 KB/sec
    # 0    1       2        3         4       5   6   7     8
    if len(cols) >= 8:
        avg = cols[4]
        p50 = cols[5] if len(cols) > 5 else ""
        p99 = cols[6] if len(cols) > 6 else ""
        p999 = cols[7] if len(cols) > 7 else ""

print(",".join([qps, avg, p50, p99, p999]))
PY
}

extract_server_metrics() {
  local file="$1"
  python3 - "$file" <<'PY'
import json, re, sys
from pathlib import Path

txt = Path(sys.argv[1]).read_text(encoding='utf-8', errors='ignore')
m = re.search(r'"metrics":\s*(\{.*?\})', txt, re.DOTALL)
if not m:
    print(",,,,,")
    sys.exit(0)
metrics = json.loads(m.group(1))
vals = [
    str(metrics.get("total_qps", "")),
    str(metrics.get("fast_qps", "")),
    str(metrics.get("slow_qps", "")),
    str(metrics.get("hit_ratio", "")),
    str(metrics.get("num_data_points", "")),
]
print(",".join(vals))
PY
}

build_load_aggregate() {
  local load="$1"
  local out_csv="$BASE_RESULTS/load_${load}_aggregate.csv"
  python3 - "$BASE_RESULTS" "$load" "$out_csv" <<'PY'
import csv
import sys
from pathlib import Path

base = Path(sys.argv[1]).expanduser()
load = sys.argv[2]
out_csv = Path(sys.argv[3]).expanduser()
summary = base / 'summary.csv'

rows = []
if summary.exists():
    with summary.open(newline='', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row.get('clients_per_thread') == str(load):
                rows.append(row)

if not rows:
    sys.exit(0)

numeric_fields = [
    'client1_qps','client1_avg_ms','client1_p50_ms','client1_p99_ms','client1_p999_ms',
    'client2_qps','client2_avg_ms','client2_p50_ms','client2_p99_ms','client2_p999_ms',
    'server_total_qps','server_fast_qps','server_slow_qps','server_hit_ratio','server_num_data_points'
]

def to_float(x):
    try:
        return float(x)
    except Exception:
        return None

agg = {'clients_per_thread': load, 'num_runs': len(rows)}
for field in numeric_fields:
    vals = [to_float(r.get(field, '')) for r in rows]
    vals = [v for v in vals if v is not None]
    if vals:
        agg[f'{field}_mean'] = sum(vals) / len(vals)
        agg[f'{field}_min'] = min(vals)
        agg[f'{field}_max'] = max(vals)
    else:
        agg[f'{field}_mean'] = ''
        agg[f'{field}_min'] = ''
        agg[f'{field}_max'] = ''

fieldnames = list(agg.keys())
with out_csv.open('w', newline='', encoding='utf-8') as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerow(agg)
PY
}

echo "TaoBench launcher starting"
echo "RUNS=$RUNS"
echo "SERVER_IP=$SERVER_IP"
echo "CLIENT1=$CLIENT1"
echo "CLIENT2=$CLIENT2"
echo "MEMSIZE=$MEMSIZE"
echo "WARMUP=$WARMUP"
echo "TEST=$TEST"
echo "PORT=$PORT"
echo "NUM_CLIENTS=$NUM_CLIENTS"
echo "INTERFACE_NAME=$INTERFACE_NAME"
echo "STARTUP_WAIT=${STARTUP_WAIT}s"
echo "COOLDOWN_WAIT=${COOLDOWN_WAIT}s"
echo "====================================="

SUMMARY="$BASE_RESULTS/summary.csv"
echo "load,run_id,run_dir,clients_per_thread,client1_qps,client1_avg_ms,client1_p50_ms,client1_p99_ms,client1_p999_ms,client2_qps,client2_avg_ms,client2_p50_ms,client2_p99_ms,client2_p999_ms,server_total_qps,server_fast_qps,server_slow_qps,server_hit_ratio,server_num_data_points" > "$SUMMARY"

for LOAD in "${LOADS[@]}"; do
  for REP in $(seq 1 "$RUNS"); do
    echo
    echo "====================================="
    echo "Starting run for CLIENTS_PER_THREAD=$LOAD (run $REP/$RUNS)"
    echo "====================================="

    RUN_DIR="load_${LOAD}_run${REP}_$(date +%Y%m%d_%H%M%S)"
    FULL_RUN_DIR="$BASE_RESULTS/$RUN_DIR"
    mkdir -p "$FULL_RUN_DIR"

    printf 'server_ip=%s\nmemsize=%s\nwarmup=%s\ntest=%s\nport=%s\nnum_clients=%s\ninterface_name=%s\nclients_per_thread=%s\nrun_id=%s\n' \
      "$SERVER_IP" "$MEMSIZE" "$WARMUP" "$TEST" "$PORT" "$NUM_CLIENTS" "$INTERFACE_NAME" "$LOAD" "$REP" \
      > "$FULL_RUN_DIR/run_info.txt"

    log "Cleaning previous processes..."
    pkill -f tao_bench || true
    pkill -f memcached || true
    remote_ssh "$CLIENT1" "pkill -f tao_bench || true" || true
    remote_ssh "$CLIENT2" "pkill -f tao_bench || true" || true
    sleep 2

    log "Starting server..."
    (
      cd ~/DCPerf
      SERVER_HOSTNAME="$SERVER_IP" \
      MEMSIZE_GB="$MEMSIZE" \
      WARMUP_TIME="$WARMUP" \
      TEST_TIME="$TEST" \
      PORT_START="$PORT" \
      NUM_CLIENTS="$NUM_CLIENTS" \
      INTERFACE_NAME="$INTERFACE_NAME" \
      OPEN_FILES_LIMIT="$OPEN_FILES_LIMIT" \
      ./tao_server.sh
    ) > "$FULL_RUN_DIR/server_console.log" 2>&1 &
    SERVER_PID=$!

    log "Waiting $STARTUP_WAIT seconds for server startup..."
    sleep "$STARTUP_WAIT"

    CLIENT_CMD="cd ~/DCPerf && SERVER_HOSTNAME=$SERVER_IP SERVER_MEMSIZE_GB=$MEMSIZE WARMUP_TIME=$WARMUP TEST_TIME=$TEST SERVER_PORT=$PORT WAIT_AFTER_WARMUP=$WAIT_AFTER_WARMUP OPEN_FILES_LIMIT=$OPEN_FILES_LIMIT CLIENTS_PER_THREAD=$LOAD ./tao_client.sh"

    log "Starting client1..."
    remote_ssh "$CLIENT1" "$CLIENT_CMD" > "$FULL_RUN_DIR/client1_console.log" 2>&1 &
    C1_PID=$!

    log "Starting client2..."
    remote_ssh "$CLIENT2" "$CLIENT_CMD" > "$FULL_RUN_DIR/client2_console.log" 2>&1 &
    C2_PID=$!

    log "Waiting for clients..."
    wait "$C1_PID"
    wait "$C2_PID"

    log "Waiting for server wrapper..."
    wait "$SERVER_PID" || true

    log "Collecting latest server metric log..."
    find ~/DCPerf -path '*/benchmark_metrics_*/*tao-bench-server*.log' -type f | sort | tail -n 1 > "$FULL_RUN_DIR/latest_server_log.txt" || true

    if [ -f "$FULL_RUN_DIR/latest_server_log.txt" ]; then
      LOGFILE=$(cat "$FULL_RUN_DIR/latest_server_log.txt")
      if [ -f "$LOGFILE" ]; then
        cp "$LOGFILE" "$FULL_RUN_DIR/server_metrics.log"
      fi
    fi

    log "Copying latest server result artifacts..."
    LATEST_SERVER_RUN=$(latest_local_file "$HOME/DCPerf/server_results/server_run_*.log")
    LATEST_SERVER_INFO=$(latest_local_file "$HOME/DCPerf/server_results/server_info_*.txt")
    LATEST_METRICS_DIR=$(ls -td ~/DCPerf/benchmark_metrics_* 2>/dev/null | head -1 || true)

    [ -n "$LATEST_SERVER_RUN" ] && cp "$LATEST_SERVER_RUN" "$FULL_RUN_DIR/" || true
    [ -n "$LATEST_SERVER_INFO" ] && cp "$LATEST_SERVER_INFO" "$FULL_RUN_DIR/" || true
    [ -n "$LATEST_METRICS_DIR" ] && cp -r "$LATEST_METRICS_DIR" "$FULL_RUN_DIR/benchmark_metrics_bundle" || true

    log "Pulling client artifacts..."
    C1_LAST_LOG=$(remote_ssh "$CLIENT1" "ls -t ~/DCPerf/client_results/client_run_*.log 2>/dev/null | head -1" || true)
    C1_LAST_LAT=$(remote_ssh "$CLIENT1" "ls -t ~/DCPerf/client_results/latency_*.txt 2>/dev/null | head -1" || true)
    C2_LAST_LOG=$(remote_ssh "$CLIENT2" "ls -t ~/DCPerf/client_results/client_run_*.log 2>/dev/null | head -1" || true)
    C2_LAST_LAT=$(remote_ssh "$CLIENT2" "ls -t ~/DCPerf/client_results/latency_*.txt 2>/dev/null | head -1" || true)

    [ -n "$C1_LAST_LOG" ] && remote_scp "$CLIENT1:$C1_LAST_LOG" "$FULL_RUN_DIR/client1_run.log" >/dev/null 2>&1 || true
    [ -n "$C1_LAST_LAT" ] && remote_scp "$CLIENT1:$C1_LAST_LAT" "$FULL_RUN_DIR/client1_latency.txt" >/dev/null 2>&1 || true
    [ -n "$C2_LAST_LOG" ] && remote_scp "$CLIENT2:$C2_LAST_LOG" "$FULL_RUN_DIR/client2_run.log" >/dev/null 2>&1 || true
    [ -n "$C2_LAST_LAT" ] && remote_scp "$CLIENT2:$C2_LAST_LAT" "$FULL_RUN_DIR/client2_latency.txt" >/dev/null 2>&1 || true

    C1_METRICS=",,,,"
    C2_METRICS=",,,,"
    S_METRICS=",,,,,"

    [ -f "$FULL_RUN_DIR/client1_latency.txt" ] && C1_METRICS=$(extract_client_metrics "$FULL_RUN_DIR/client1_latency.txt") || true
    [ -f "$FULL_RUN_DIR/client2_latency.txt" ] && C2_METRICS=$(extract_client_metrics "$FULL_RUN_DIR/client2_latency.txt") || true

    LOCAL_SERVER_RUN=$(latest_local_file "$FULL_RUN_DIR/server_run_*.log")
    [ -n "$LOCAL_SERVER_RUN" ] && S_METRICS=$(extract_server_metrics "$LOCAL_SERVER_RUN") || true

    echo "$LOAD,$REP,$RUN_DIR,$LOAD,$C1_METRICS,$C2_METRICS,$S_METRICS" >> "$SUMMARY"

    log "Run for load $LOAD (run $REP/$RUNS) completed."
    sleep "$COOLDOWN_WAIT"
  done

  build_load_aggregate "$LOAD"
  log "Aggregate CSV written for load $LOAD"
done

echo
echo "All runs completed."
echo "Summary: $SUMMARY"
