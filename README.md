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
9388c3e3c404e0466f0a2929f15ddcf62b2215f6
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

### 3. Client Setup (run on both clients)

```bash
chmod +x ~/bootstrap_common.sh ~/bootstrap_client.sh
bash ~/bootstrap_client.sh
```

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
│   └── launch_clients.sh
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
