# DCPerf TaoBench Experiments

This repository provides a **fully reproducible setup** for deploying and running **TaoBench using DCPerf** on **CloudLab**.

It includes:

* CloudLab experiment profile
* Automated bootstrap scripts (server & clients)
* Client launch automation
* Stable and reproducible environment configuration

---

##  Experiment Topology

* **1 Server node** (TaoBench server)
* **2 Client nodes** (load generators)
* **Private LAN network**

Default private IP configuration:

| Node    | IP Address   |
| ------- | ------------ |
| server  | 192.168.1.10 |
| client1 | 192.168.1.11 |
| client2 | 192.168.1.12 |

---

##  Environment

* OS: Ubuntu 22.04
* Architecture: x86_64
* Network latency: < 0.2 ms (CloudLab LAN)
* Required tools installed automatically

---

##  Reproducibility

This setup is designed for **consistent and repeatable experiments**.

* **DCPerf version pinned to commit:**

```
9308c3e3c404e0466f0a2929f15ddcf62b2215f6
```

* Python environment:

  * Virtual environment (`venv`)
  * NumPy pinned to `1.26.4` (avoids TaoBench incompatibility)

* System configuration:

  * `ulimit -n = 65536`
  * `numactl` installed
  * fixed network topology

---

##  Setup Instructions

### 1. Create CloudLab Experiment

Use:

```
cloudlab/profile.py
```

Instantiate a 3-node experiment.

---

### 2. Server Setup

```bash
chmod +x ~/bootstrap_common.sh ~/bootstrap_server.sh
bash ~/bootstrap_server.sh
```

---

### 3. Client Setup (run on each client node)

**Option A — clone the repo and run directly (recommended):**

```bash
git clone https://github.com/andKarag02/dcperf-experiments.git ~/dcperf-experiments
bash ~/dcperf-experiments/scripts/bootstrap_client.sh
```

**Option B — one-liner (no SSH from server needed, run directly on each client via CloudLab web/SSH):**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/andKarag02/dcperf-experiments/main/scripts/bootstrap_client.sh)
```

> **Note:** you can run either option independently on each client node without cross-node SSH.
> Set up cross-node SSH only when you are ready to use `launch_clients.sh`.

---

##  Running the Experiment

### Start server

```bash
cd ~/DCPerf
./tao_server.sh
```

---

### Launch clients

From any node (typically server):

```bash
bash ~/launch_clients.sh
```

---

##  Run all experiments (automated)

For batch runs with multiple load levels and repetitions, use `run_all_experiments.sh` from the server node:

```bash
bash ~/dcperf-experiments/scripts/run_all_experiments.sh
```

**Configuration (via environment variables):**

```bash
RUNS=5                                    # Number of runs per load level
LOADS="100 150 200 250 300 340 380 400"   # Load levels (clients_per_thread)
MEMSIZE=16                                # Server memory in GB
WARMUP=900                                # Warmup time in seconds
TEST=300                                  # Test time in seconds
STARTUP_WAIT=20                           # Seconds to wait for server startup
COOLDOWN_WAIT=25                          # Seconds to wait between runs
```

**Results location:**

| File | Description |
| ---- | ----------- |
| `~/DCPerf/exp_runs/summary.csv` | One row per run with all client and server metrics |
| `~/DCPerf/exp_runs/load_<LOAD>_aggregate.csv` | Per-load mean/min/max aggregation across all runs |
| `~/DCPerf/exp_runs/load_<LOAD>_run<N>_<timestamp>/` | Raw logs and artifacts for each individual run |

---

##  Monitoring

On the server:

```bash
./monitor_tao.sh
```

Displays:

* running processes
* open file limits
* latest TaoBench logs

---

##  Common Issues (Solved)

This setup avoids known TaoBench/DCPerf problems:

* NumPy incompatibility → fixed by pinning version
* Too many open files → fixed via `ulimit`
* Missing `numactl`
* Unstable standalone mode → uses autoscale mode
* Log confusion → standardized execution

---

##  Repository Structure

```
.
├── cloudlab/
│   └── profile.py
├── scripts/
│   ├── bootstrap_common.sh
│   ├── bootstrap_server.sh
│   ├── bootstrap_client.sh
│   ├── launch_clients.sh
│   ├── tao_client.sh
│   ├── tao_server.sh
│   └── run_all_experiments.sh
├── docs/
│   └── runbook.md
└── README.md
```

---

##  Notes

* All scripts are **parameterized** via environment variables
* Default values can be overridden at runtime
* Designed for **academic experiments and benchmarking**


---

##  Use Case

This repository was developed as part of a **Diploma Thesis** focused on:

> Benchmarking and analyzing distributed workloads using TaoBench and DCPerf.

---

##  Author

* GitHub: andkarag02
