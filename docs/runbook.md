# DCPerf TaoBench – Experiment Runbook

Step-by-step guide for running a TaoBench experiment on CloudLab.

---

## 1. Create the CloudLab Experiment

1. Log in to [CloudLab](https://cloudlab.us).
2. Create a new experiment using `cloudlab/profile.py`.
3. Wait until all three nodes (`server`, `client1`, `client2`) reach **Ready** state.

Default hardware type: **c6220** — override via the `hardware_type` profile parameter.

---

## 2. Copy Bootstrap Scripts to Each Node

SSH into each node and download the scripts from this repository:

```bash
# On server
curl -sSL https://raw.githubusercontent.com/andKarag02/dcperf-experiments/main/scripts/bootstrap_common.sh -o ~/bootstrap_common.sh
curl -sSL https://raw.githubusercontent.com/andKarag02/dcperf-experiments/main/scripts/bootstrap_server.sh -o ~/bootstrap_server.sh
chmod +x ~/bootstrap_common.sh ~/bootstrap_server.sh

# On client1 and client2
curl -sSL https://raw.githubusercontent.com/andKarag02/dcperf-experiments/main/scripts/bootstrap_common.sh -o ~/bootstrap_common.sh
curl -sSL https://raw.githubusercontent.com/andKarag02/dcperf-experiments/main/scripts/bootstrap_client.sh -o ~/bootstrap_client.sh
chmod +x ~/bootstrap_common.sh ~/bootstrap_client.sh
```

---

## 3. Bootstrap All Nodes

Run the appropriate bootstrap script on **each** node. Bootstrap can run in parallel across nodes.

```bash
# On server
bash ~/bootstrap_server.sh

# On client1 and client2
bash ~/bootstrap_client.sh
```

Bootstrap installs system packages, clones DCPerf at the pinned commit, creates a Python virtual environment, and generates the runtime scripts (`tao_server.sh`, `tao_client.sh`, `launch_clients.sh`).

---

## 4. Start the TaoBench Server

On the **server** node:

```bash
cd ~/DCPerf
./tao_server.sh
```

Default configuration (override via environment variables):

| Variable | Default | Description |
|---|---|---|
| `INTERFACE_NAME` | `eno1` | Network interface facing the LAN |
| `SERVER_HOSTNAME` | `192.168.1.10` | Server IP on the private LAN |
| `NUM_CLIENTS` | `2` | Number of client nodes |
| `MEMSIZE_GB` | `16` | Memory size allocated to TaoBench |
| `WARMUP_TIME` | `300` | Warm-up duration (seconds) |
| `TEST_TIME` | `300` | Measurement duration (seconds) |
| `PORT_START` | `11211` | Starting memcached port |
| `OPEN_FILES_LIMIT` | `65536` | `ulimit -n` value |

Example — override memory and test time:

```bash
MEMSIZE_GB=32 TEST_TIME=600 ./tao_server.sh
```

---

## 5. Launch the Clients

From the **server** node (once the server is running and past the warm-up phase):

```bash
bash ~/launch_clients.sh
```

Both clients run in parallel. Their combined output is streamed to the terminal, prefixed with `[client1]` / `[client2]`.

Configuration is forwarded via the same environment variables listed above (except `INTERFACE_NAME`, `MEMSIZE_GB`, and `NUM_CLIENTS` which are server-only).

---

## 6. Monitor the Server

In a separate terminal on the **server**:

```bash
cd ~/DCPerf
./monitor_tao.sh
```

Displays:

* Open file limits
* Running `tao_bench` / `numactl` processes
* Tail of the latest server log

---

## 7. Collect Results

TaoBench writes JSON result files to `~/DCPerf/`. After the test completes:

```bash
ls ~/DCPerf/benchmarks/tao_bench/
```

Key metrics reported by `benchpress_cli.py`:

* **QPS** — queries per second (aggregate across all clients)
* **P99 latency** — 99th-percentile response time

---

## 8. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Too many open files` | `ulimit` not applied | Ensure `OPEN_FILES_LIMIT` is set and `ulimit -n` succeeds |
| `numpy` import error | Wrong numpy version | Re-run bootstrap; numpy is pinned to `1.26.4` |
| Client cannot reach server | Wrong IP / interface | Check `SERVER_HOSTNAME` and `INTERFACE_NAME` |
| `numactl` not found | Package missing | Re-run `bootstrap_common.sh` |
| Server exits immediately | Autoscale mode error | Check latest `tao-bench-server-*.log` in `~/DCPerf/` |
| `pyconfig.h: No such file or directory` | Python dev headers missing | `sudo apt-get install -y python3-dev` then re-run bootstrap |
| Build fails with out-of-memory | Too many parallel jobs | Bootstrap now auto-detects safe job count; retry with `MAKEFLAGS=-j1` |
| `ModuleNotFoundError` during install | venv not activated | Bootstrap now always activates venv; re-run `bootstrap_server.sh` |

---

## 9. Running Multiple Experiments (Bulk Runs)

Use `scripts/run_all_experiments.sh` to sweep across multiple load levels and repeat each measurement N times automatically. The script handles server/client lifecycle, metric collection, SSH artifact retrieval, and CSV aggregation in a single command.

### Quick Start

Download the script to the **server** node and run it:

```bash
# Download
curl -sSL https://raw.githubusercontent.com/andKarag02/dcperf-experiments/main/scripts/run_all_experiments.sh \
     -o ~/run_all_experiments.sh
chmod +x ~/run_all_experiments.sh

# Run with defaults (5 repetitions, loads 100–400)
bash ~/run_all_experiments.sh
```

Or execute directly without saving:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/andKarag02/dcperf-experiments/main/scripts/run_all_experiments.sh)
```

### Parameter Reference

All parameters are controlled via environment variables. Defaults reflect a standard CloudLab experiment.

| Variable | Default | Description |
|---|---|---|
| `RUNS` | `5` | Number of repetitions per load level |
| `LOADS` | `"100 150 200 250 300 340 380 400"` | Space-separated list of `CLIENTS_PER_THREAD` values to test |
| `SERVER_IP` | `192.168.1.10` | Server node IP on the private LAN |
| `CLIENT1` | `192.168.1.11` | Client 1 node IP |
| `CLIENT2` | `192.168.1.12` | Client 2 node IP |
| `MEMSIZE` | `16` | Server memory size in GB |
| `WARMUP` | `900` | Server warm-up duration in seconds |
| `TEST` | `300` | Measurement duration in seconds |
| `PORT` | `11211` | Starting memcached port |
| `INTERFACE_NAME` | `enp3s0f0` | Network interface name on the server |
| `STARTUP_WAIT` | `20` | Seconds to wait after starting the server before launching clients |
| `COOLDOWN_WAIT` | `25` | Seconds to wait between consecutive runs |
| `OPEN_FILES_LIMIT` | `65536` | `ulimit -n` value applied on server and clients |

### Usage Examples

```bash
# Example 1: Default run — 5 repetitions, loads 100 to 400
bash ~/run_all_experiments.sh

# Example 2: 10 repetitions with a custom load range
RUNS=10 LOADS="50 100 200 400" bash ~/run_all_experiments.sh

# Example 3: Single load, 3 repetitions, shorter test duration
LOADS="200" RUNS=3 WARMUP=300 TEST=120 bash ~/run_all_experiments.sh

# Example 4: Override network interface and memory size
INTERFACE_NAME=eth0 MEMSIZE=32 WARMUP=1200 TEST=600 RUNS=5 \
  bash ~/run_all_experiments.sh

# Example 5: Custom IPs and one-liner curl execution
SERVER_IP=10.0.0.1 CLIENT1=10.0.0.2 CLIENT2=10.0.0.3 \
  bash <(curl -fsSL https://raw.githubusercontent.com/andKarag02/dcperf-experiments/main/scripts/run_all_experiments.sh)
```

### Output Structure

All results are written to `~/DCPerf/exp_runs/`:

```
~/DCPerf/exp_runs/
├── summary.csv                           # Master CSV — one row per run
├── load_100_aggregate.csv                # Mean/min/max stats for load 100
├── load_150_aggregate.csv                # Mean/min/max stats for load 150
├── ...
├── load_100_run1_20260420_123456/
│   ├── run_info.txt                      # Run metadata (IPs, params)
│   ├── server_console.log                # Server stdout/stderr
│   ├── client1_console.log               # Client 1 stdout/stderr
│   ├── client2_console.log               # Client 2 stdout/stderr
│   ├── client1_latency.txt               # Client 1 latency metrics
│   ├── client2_latency.txt               # Client 2 latency metrics
│   ├── server_run_*.log                  # Server metrics JSON
│   └── benchmark_metrics_bundle/         # Detailed server metrics directory
└── load_100_run2_20260420_124000/
    └── ...
```

### Interpreting the Results

**`summary.csv`** — one row per individual run with columns:

| Column | Description |
|---|---|
| `load` | `CLIENTS_PER_THREAD` value used for this run |
| `run_id` | Repetition number within the load (1…RUNS) |
| `run_dir` | Directory name containing run artifacts |
| `clients_per_thread` | Same as `load` |
| `client1_qps` / `client2_qps` | Queries per second reported by each client |
| `client1_avg_ms` / `client2_avg_ms` | Average GET latency in milliseconds |
| `client1_p50_ms` / `client2_p50_ms` | 50th-percentile (median) GET latency |
| `client1_p99_ms` / `client2_p99_ms` | 99th-percentile GET latency |
| `client1_p999_ms` / `client2_p999_ms` | 99.9th-percentile GET latency |
| `server_total_qps` | Total QPS reported by the server |
| `server_fast_qps` / `server_slow_qps` | Fast vs. slow query breakdown |
| `server_hit_ratio` | Cache hit ratio |
| `server_num_data_points` | Number of measurement intervals aggregated |

**`load_XXX_aggregate.csv`** — one row per load level with `_mean`, `_min`, and `_max` suffixed columns for every numeric metric above. Use this file to compare performance across load levels and identify saturation points.

---

## Environment Summary

| Item | Value |
|---|---|
| OS | Ubuntu 22.04 LTS (x86_64) |
| DCPerf commit | `9388c3e3c404e0466f0a2929f15ddcf62b2215f6` |
| NumPy | `1.26.4` |
| Server IP | `192.168.1.10` |
| Client 1 IP | `192.168.1.11` |
| Client 2 IP | `192.168.1.12` |
