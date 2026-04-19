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

# ── Python headers for Boost.Python / C++ extensions ─────────────────────────

PYTHON3_BIN="$(command -v python3)"
PY_INCLUDE="$("$PYTHON3_BIN" -c 'import sysconfig; print(sysconfig.get_path("include"))')"
export CPATH="${PY_INCLUDE}${CPATH:+:${CPATH}}"
export CPLUS_INCLUDE_PATH="${PY_INCLUDE}${CPLUS_INCLUDE_PATH:+:${CPLUS_INCLUDE_PATH}}"
echo "[INFO] CPATH=${CPATH}"
echo "[INFO] CPLUS_INCLUDE_PATH=${CPLUS_INCLUDE_PATH}"

# ── Determine safe parallel job count ────────────────────────────────────────

MEM_MB_PER_JOB=1536

NPROC="$(nproc 2>/dev/null || echo 4)"
MEM_KB="$(grep MemAvailable /proc/meminfo | awk '{print $2}')"
MAX_JOBS_MEM=$(( MEM_KB / (MEM_MB_PER_JOB * 1024) ))
[ "$MAX_JOBS_MEM" -lt 1 ] && MAX_JOBS_MEM=1
if [ "$MAX_JOBS_MEM" -lt "$NPROC" ]; then
  BUILD_JOBS="$MAX_JOBS_MEM"
else
  BUILD_JOBS="$NPROC"
fi
echo "[INFO] Using ${BUILD_JOBS} parallel build job(s) (${NPROC} CPUs, $(( MEM_KB / 1024 / 1024 )) GB available RAM)"
export MAKEFLAGS="-j${BUILD_JOBS}"

# ── Install tao_bench_custom (with retry on fewer jobs) ──────────────────────

install_tao_bench_custom() {
  local jobs="${1:-${BUILD_JOBS}}"
  echo "[INFO] Installing tao_bench_custom (MAKEFLAGS=-j${jobs})"
  MAKEFLAGS="-j${jobs}" ./benchpress_cli.py install tao_bench_custom
}

echo "[INFO] Attempting tao_bench_custom install"
if ! install_tao_bench_custom "${BUILD_JOBS}"; then
  echo "[WARN] Initial install failed with -j${BUILD_JOBS}; retrying with -j1"
  echo "[WARN] This is usually caused by insufficient memory during parallel compilation."
  rm -rf "$HOME/DCPerf/benchmarks/tao_bench/build-folly" 2>/dev/null || true
  if ! install_tao_bench_custom 1; then
    echo "[ERROR] tao_bench_custom installation failed."
    echo "        Possible causes and fixes:"
    echo "          • Missing Python headers: sudo apt-get install -y python3-dev"
    echo "          • Missing build tools:    sudo apt-get install -y build-essential cmake"
    echo "          • Out of disk space:      df -h \$HOME"
    echo "          • Out of memory:          free -h"
    echo "        Check the build log above for the first error line."
    exit 1
  fi
fi

echo "[INFO] tao_bench_custom installed successfully"

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