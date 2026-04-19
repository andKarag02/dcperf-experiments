#!/usr/bin/env bash
set -euo pipefail

echo "[INFO] bootstrap_common.sh started"

DCPERF_REPO="https://github.com/facebookresearch/DCPerf.git"
DCPERF_COMMIT="9308c3e3c404e0466f0a2929f15ddcf62b2215f6"
DCPERF_DIR="$HOME/DCPerf"
VENV_DIR="$DCPERF_DIR/venv"

export DEBIAN_FRONTEND=noninteractive

echo "[INFO] Updating apt cache"
sudo apt update

echo "[INFO] Installing common packages"
sudo apt install -y \
  git \
  python3 \
  python3-pip \
  python3-venv \
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

echo "[INFO] Verifying numactl"
which numactl
numactl --show >/dev/null 2>&1 || true

echo "[INFO] bootstrap_common.sh completed"