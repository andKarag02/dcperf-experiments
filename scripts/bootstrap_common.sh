#!/usr/bin/env bash
set -euo pipefail

echo "[INFO] bootstrap_common.sh started"

DCPERF_REPO="https://github.com/facebookresearch/DCPerf.git"
DCPERF_COMMIT="9308c3e3c404e0466f0a2929f15ddcf62b2215f6"
DCPERF_DIR="$HOME/DCPerf"
VENV_DIR="$DCPERF_DIR/venv"

# ── Prerequisite checks ────────────────────────────────────────────────────────

echo "[INFO] Checking prerequisites"

# Disk space: require at least 20 GB free on the home filesystem
AVAIL_KB=$(df --output=avail "$HOME" | tail -1)
REQUIRED_KB=$((20 * 1024 * 1024))
if [ "$AVAIL_KB" -lt "$REQUIRED_KB" ]; then
  AVAIL_GB=$(( AVAIL_KB / 1024 / 1024 ))
  echo "[ERROR] Insufficient disk space: ${AVAIL_GB} GB available, 20 GB required."
  echo "        Free up disk space and re-run this script."
  exit 1
fi
echo "[INFO] Disk space OK ($(( AVAIL_KB / 1024 / 1024 )) GB free)"

# Memory: require at least 8 GB RAM
TOTAL_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
REQUIRED_MEM_KB=$((8 * 1024 * 1024))
if [ "$TOTAL_KB" -lt "$REQUIRED_MEM_KB" ]; then
  TOTAL_GB=$(( TOTAL_KB / 1024 / 1024 ))
  echo "[WARN] System has only ${TOTAL_GB} GB of RAM; builds may be slow or fail."
  echo "       Recommended minimum is 8 GB."
fi
echo "[INFO] Memory: $(( TOTAL_KB / 1024 / 1024 )) GB total"

# ── System package installation ────────────────────────────────────────────────

export DEBIAN_FRONTEND=noninteractive

echo "[INFO] Updating apt cache"
sudo apt-get update -q

echo "[INFO] Installing common packages"
sudo apt-get install -y \
  git \
  python3 \
  python3-pip \
  python3-venv \
  python3-dev \
  build-essential \
  cmake \
  wget \
  curl \
  numactl \
  iproute2 \
  ethtool \
  jq \
  tmux \
  ca-certificates

# ── Python dev headers validation ─────────────────────────────────────────────

echo "[INFO] Verifying Python development headers"
PYTHON3_BIN="$(command -v python3)"
PY_VERSION="$("$PYTHON3_BIN" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
PY_INCLUDE="$("$PYTHON3_BIN" -c 'import sysconfig; print(sysconfig.get_path("include"))')"

if [ ! -f "${PY_INCLUDE}/pyconfig.h" ]; then
  echo "[ERROR] Python development headers not found: ${PY_INCLUDE}/pyconfig.h missing."
  echo "        Try: sudo apt-get install -y python${PY_VERSION}-dev"
  exit 1
fi
echo "[INFO] Python headers found: ${PY_INCLUDE}/pyconfig.h"

# Export include paths so Boost.Python and other C++ extensions can find them
export CPATH="${PY_INCLUDE}${CPATH:+:${CPATH}}"
export CPLUS_INCLUDE_PATH="${PY_INCLUDE}${CPLUS_INCLUDE_PATH:+:${CPLUS_INCLUDE_PATH}}"
echo "[INFO] Exported CPATH=${CPATH}"
echo "[INFO] Exported CPLUS_INCLUDE_PATH=${CPLUS_INCLUDE_PATH}"

# ── DCPerf clone / checkout ────────────────────────────────────────────────────

if [ ! -d "$DCPERF_DIR" ]; then
  echo "[INFO] Cloning DCPerf"
  git clone "$DCPERF_REPO" "$DCPERF_DIR"
else
  echo "[INFO] DCPerf already exists at $DCPERF_DIR"
fi

cd "$DCPERF_DIR"

echo "[INFO] Fetching all refs/tags"
git fetch --all --tags

echo "[INFO] Checking out pinned DCPerf commit: $DCPERF_COMMIT"
git checkout "$DCPERF_COMMIT"
git reset --hard "$DCPERF_COMMIT"

echo "[INFO] Current DCPerf revision"
git rev-parse HEAD
git rev-parse --short HEAD
git describe --tags --always || true

# ── Python virtual environment ─────────────────────────────────────────────────

if [ ! -d "$VENV_DIR" ]; then
  echo "[INFO] Creating virtual environment"
  python3 -m venv "$VENV_DIR"
fi

echo "[INFO] Activating virtual environment"
# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"

echo "[INFO] Upgrading pip tooling"
python -m pip install --upgrade pip setuptools wheel

echo "[INFO] Installing Python dependencies"
python -m pip install \
  "numpy==1.26.4" \
  click \
  tabulate \
  pandas \
  pyyaml \
  psutil \
  matplotlib

echo "[INFO] Verifying Python packages"
python - <<'PY'
import sys
mods = ["numpy", "click", "tabulate", "pandas", "yaml", "psutil", "matplotlib"]
print("Python:", sys.executable)
for m in mods:
    mod = __import__(m)
    print(f"{m}: OK ({getattr(mod, '__file__', 'built-in')})")
PY

# ── Final validation ───────────────────────────────────────────────────────────

echo "[INFO] Verifying numactl"
which numactl
numactl --show >/dev/null 2>&1 || true

echo "[INFO] bootstrap_common.sh completed"