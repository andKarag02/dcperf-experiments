#!/usr/bin/env bash
set -euo pipefail

echo "[INFO] bootstrap_server.sh started"

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
  echo "        Re-run bootstrap_common.sh to recreate it."
  exit 1
fi

# ── Python headers for Boost.Python / C++ extensions ─────────────────────────

PYTHON3_BIN="$(command -v python3)"
PY_INCLUDE="$("$PYTHON3_BIN" -c 'import sysconfig; print(sysconfig.get_path("include"))')"
export CPATH="${PY_INCLUDE}${CPATH:+:${CPATH}}"
export CPLUS_INCLUDE_PATH="${PY_INCLUDE}${CPLUS_INCLUDE_PATH:+:${CPLUS_INCLUDE_PATH}}"
echo "[INFO] CPATH=${CPATH}"
echo "[INFO] CPLUS_INCLUDE_PATH=${CPLUS_INCLUDE_PATH}"

# ── Determine safe parallel job count ────────────────────────────────────────

# MB of RAM reserved per parallel compile job
MEM_MB_PER_JOB=1536

NPROC="$(nproc 2>/dev/null || echo 4)"
MEM_KB="$(grep MemAvailable /proc/meminfo | awk '{print $2}')"
# Allow MEM_MB_PER_JOB per compile job; cap at nproc
MAX_JOBS_MEM=$(( MEM_KB / (MEM_MB_PER_JOB * 1024) ))
[ "$MAX_JOBS_MEM" -lt 1 ] && MAX_JOBS_MEM=1
if [ "$MAX_JOBS_MEM" -lt "$NPROC" ]; then
  BUILD_JOBS="$MAX_JOBS_MEM"
else
  BUILD_JOBS="$NPROC"
fi
echo "[INFO] Using ${BUILD_JOBS} parallel build job(s) (${NPROC} CPUs, $(( MEM_KB / 1024 / 1024 )) GB available RAM)"
export MAKEFLAGS="-j${BUILD_JOBS}"

# ── Install TaoBench autoscale (with retry on fewer jobs) ────────────────────

install_tao_bench() {
  local jobs="${1:-${BUILD_JOBS}}"
  echo "[INFO] Installing TaoBench autoscale (MAKEFLAGS=-j${jobs})"
  MAKEFLAGS="-j${jobs}" ./benchpress_cli.py install tao_bench_autoscale
}

echo "[INFO] Attempting TaoBench autoscale install"
if ! install_tao_bench "${BUILD_JOBS}"; then
  echo "[WARN] Initial install failed with -j${BUILD_JOBS}; retrying with -j1"
  echo "[WARN] This is usually caused by insufficient memory during parallel compilation."
  # Clean any stale build artifacts before retry
  rm -rf "$HOME/DCPerf/benchmarks/tao_bench/build-folly" 2>/dev/null || true
  if ! install_tao_bench 1; then
    echo "[ERROR] TaoBench autoscale installation failed."
    echo "        Possible causes and fixes:"
    echo "          • Missing Python headers: sudo apt-get install -y python3-dev"
    echo "          • Missing build tools:    sudo apt-get install -y build-essential cmake"
    echo "          • Out of disk space:      df -h \$HOME"
    echo "          • Out of memory:          free -h"
    echo "        Check the build log above for the first error line."
    exit 1
  fi
fi

echo "[INFO] TaoBench autoscale installed successfully"

echo "[INFO] Creating tao_server.sh"
TAO_SERVER_SOURCE="${SCRIPT_DIR}/tao_server.sh"
if [ ! -f "${TAO_SERVER_SOURCE}" ]; then
  echo "[INFO] tao_server.sh not found locally -- downloading from GitHub"
  curl -fsSL "${REPO_RAW}/tao_server.sh" -o /tmp/tao_server.sh
  TAO_SERVER_SOURCE="/tmp/tao_server.sh"
fi

install -m 0755 "${TAO_SERVER_SOURCE}" "$HOME/DCPerf/tao_server.sh"

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
SSH_OPTS=(-o StrictHostKeyChecking=no -o ConnectTimeout=10)

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
EOF

chmod +x "$HOME/launch_clients.sh"

echo "[INFO] bootstrap_server.sh completed"
