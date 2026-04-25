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
TAO_CLIENT_SOURCE="${SCRIPT_DIR}/tao_client.sh"
if [ ! -f "${TAO_CLIENT_SOURCE}" ]; then
  echo "[INFO] tao_client.sh not found locally — downloading from GitHub"
  curl -fsSL "${REPO_RAW}/tao_client.sh" -o /tmp/tao_client.sh
  TAO_CLIENT_SOURCE="/tmp/tao_client.sh"
fi

install -m 0755 "${TAO_CLIENT_SOURCE}" "$HOME/DCPerf/tao_client.sh"

echo "[INFO] bootstrap_client.sh completed"
