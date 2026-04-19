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

## Environment Summary

| Item | Value |
|---|---|
| OS | Ubuntu 22.04 LTS (x86_64) |
| DCPerf commit | `9388c3e3c404e0466f0a2929f15ddcf62b2215f6` |
| NumPy | `1.26.4` |
| Server IP | `192.168.1.10` |
| Client 1 IP | `192.168.1.11` |
| Client 2 IP | `192.168.1.12` |
