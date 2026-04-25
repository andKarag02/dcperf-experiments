#!/usr/bin/env bash
set -euo pipefail

# Collect CPU, memory, network and disk utilization every second.
# Each metric group is written to a separate CSV inside OUTPUT_DIR.
#
# Usage:
#   OUTPUT_DIR=/path/to/run_dir/utilization \
#   INTERFACE=enp3s0f0 \
#   NODE_LABEL=server \
#   bash collect_utilization.sh &

OUTPUT_DIR="${OUTPUT_DIR:-$PWD/utilization}"
INTERFACE="${INTERFACE:-eth0}"
NODE_LABEL="${NODE_LABEL:-$(hostname -s 2>/dev/null || hostname)}"
INTERVAL_SECONDS="${INTERVAL_SECONDS:-1}"

mkdir -p "$OUTPUT_DIR"

CPU_CSV="$OUTPUT_DIR/cpu.csv"
MEM_CSV="$OUTPUT_DIR/memory.csv"
NET_CSV="$OUTPUT_DIR/network.csv"
DISK_CSV="$OUTPUT_DIR/disk.csv"

if [ ! -d "/sys/class/net/${INTERFACE}" ]; then
  echo "[ERROR] Network interface '${INTERFACE}' does not exist."
  exit 1
fi

ROOT_SRC="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
ROOT_DEV_REAL="$(readlink -f "$ROOT_SRC" 2>/dev/null || echo "$ROOT_SRC")"
ROOT_DEV_NAME="$(basename "$ROOT_DEV_REAL")"

get_cpu_totals() {
  awk '/^cpu / {print $2+$3+$4+$5+$6+$7+$8, $5+$6}' /proc/stat
}

get_mem_usage_percent() {
  awk '
    /^MemTotal:/ {t=$2}
    /^MemAvailable:/ {a=$2}
    END {
      if (t > 0) {
        used=t-a
        printf "%.2f", (used*100)/t
      } else {
        printf "0.00"
      }
    }' /proc/meminfo
}

get_rx_bytes() {
  cat "/sys/class/net/${INTERFACE}/statistics/rx_bytes"
}

get_tx_bytes() {
  cat "/sys/class/net/${INTERFACE}/statistics/tx_bytes"
}

get_disk_sectors() {
  awk -v dev="$ROOT_DEV_NAME" '$3 == dev {print $6, $10}' /proc/diskstats
}

write_headers() {
  [ -f "$CPU_CSV" ] || echo "timestamp,node_label,cpu_util_percent" > "$CPU_CSV"
  [ -f "$MEM_CSV" ] || echo "timestamp,node_label,mem_util_percent" > "$MEM_CSV"
  [ -f "$NET_CSV" ] || echo "timestamp,node_label,interface,rx_bytes_per_sec,tx_bytes_per_sec" > "$NET_CSV"
  [ -f "$DISK_CSV" ] || echo "timestamp,node_label,device,read_kb_per_sec,write_kb_per_sec" > "$DISK_CSV"
}

write_headers

read -r prev_cpu_total prev_cpu_idle <<<"$(get_cpu_totals)"
prev_rx="$(get_rx_bytes)"
prev_tx="$(get_tx_bytes)"
read -r prev_read_sectors prev_write_sectors <<<"$(get_disk_sectors || echo '0 0')"

cleanup() {
  echo "[INFO] collect_utilization.sh stopped"
  exit 0
}
trap cleanup SIGTERM SIGINT

echo "[INFO] Collecting utilization into: $OUTPUT_DIR"
echo "[INFO] INTERFACE=${INTERFACE} NODE_LABEL=${NODE_LABEL} ROOT_DEV=${ROOT_DEV_NAME:-unknown}"

while true; do
  ts="$(date +%s)"

  read -r curr_cpu_total curr_cpu_idle <<<"$(get_cpu_totals)"
  cpu_total_delta=$((curr_cpu_total - prev_cpu_total))
  cpu_idle_delta=$((curr_cpu_idle - prev_cpu_idle))
  if [ "$cpu_total_delta" -gt 0 ]; then
    cpu_util="$(awk -v t="$cpu_total_delta" -v i="$cpu_idle_delta" 'BEGIN {printf "%.2f", (1 - (i / t)) * 100}')"
  else
    cpu_util="0.00"
  fi
  echo "${ts},${NODE_LABEL},${cpu_util}" >> "$CPU_CSV"
  prev_cpu_total="$curr_cpu_total"
  prev_cpu_idle="$curr_cpu_idle"

  mem_util="$(get_mem_usage_percent)"
  echo "${ts},${NODE_LABEL},${mem_util}" >> "$MEM_CSV"

  curr_rx="$(get_rx_bytes)"
  curr_tx="$(get_tx_bytes)"
  rx_bps=$((curr_rx - prev_rx))
  tx_bps=$((curr_tx - prev_tx))
  if [ "$rx_bps" -lt 0 ]; then rx_bps=0; fi
  if [ "$tx_bps" -lt 0 ]; then tx_bps=0; fi
  echo "${ts},${NODE_LABEL},${INTERFACE},${rx_bps},${tx_bps}" >> "$NET_CSV"
  prev_rx="$curr_rx"
  prev_tx="$curr_tx"

  read -r curr_read_sectors curr_write_sectors <<<"$(get_disk_sectors || echo '0 0')"
  read_kbps="$(awk -v c="$curr_read_sectors" -v p="$prev_read_sectors" 'BEGIN {d=c-p; if (d<0) d=0; printf "%.2f", (d*512)/1024}')"
  write_kbps="$(awk -v c="$curr_write_sectors" -v p="$prev_write_sectors" 'BEGIN {d=c-p; if (d<0) d=0; printf "%.2f", (d*512)/1024}')"
  echo "${ts},${NODE_LABEL},${ROOT_DEV_NAME},${read_kbps},${write_kbps}" >> "$DISK_CSV"
  prev_read_sectors="$curr_read_sectors"
  prev_write_sectors="$curr_write_sectors"

  sleep "$INTERVAL_SECONDS"
done
