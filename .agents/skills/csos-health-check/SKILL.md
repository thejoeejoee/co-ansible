---
name: csos-health-check
description: Check health of the csos.josefkolar.cz production relay host — load, memory, disk, systemd services, Docker containers, and reconcile running state against the current Ansible playbook. Use when asked to "check csos health", "is csos ok", "how is the stream server", "check the host", or investigate production issues.
compatibility: opencode
---

# CSOS Host Health Check

Production host: `root@csos.josefkolar.cz` (2 vCPU, 4 GB RAM, Ubuntu 24.04). Access via SSH as root.

## Step 1 — One-shot system + service snapshot

Single SSH round-trip covers uptime, load, memory, disk, top processes, systemd services, and docker containers:

```bash
ssh -o ConnectTimeout=10 root@csos.josefkolar.cz '
echo "---UPTIME---"      && uptime
echo "---MEM---"         && free -h
echo "---DISK---"        && df -h /
echo "---LOAD---"        && cat /proc/loadavg && echo "cores: $(nproc)"
echo "---TOP CPU---"     && ps aux --sort=-%cpu | head -10
echo "---SERVICES---"    && systemctl is-active csos-mediamtx caddy prometheus grafana-server node_exporter
echo "---DOCKER---"      && docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
'
```

## Step 2 — Interpret

### Load
- **2 vCPUs**, so healthy load ≤ 1.5, saturated at 2.0, overloaded > 2.5 sustained.
- ffmpeg restreams eat CPU — 1.5–2.0 load under active streaming is normal.

### Memory
- Baseline idle ~1 GB used.
- Grafana is the biggest consumer (~400 MB). ffmpeg + mediamtx together ~200 MB.
- Swap in use is normal on this box (small swap, occasional page-outs); alarming only if `si`/`so` in `vmstat` are non-zero and growing.

### Disk
- `/dev/mapper/lv-root` — watch for > 80%. mediamtx HLS segments and snapshots don't accumulate (short retention), but check `/var/log/journal` if usage jumps.

### Expected services (systemd)

| Unit | Role | Expected |
|------|------|----------|
| `csos-mediamtx.service` | stream_proxy | active |
| `caddy.service` | web_proxy | active |
| `prometheus.service` | telemetry | active |
| `grafana-server.service` | telemetry | active |
| `node_exporter.service` | telemetry | active |

⚠️ **Do NOT check `mediamtx` — the unit is named `csos-mediamtx`.**

### Expected Docker containers

Per current `playbooks/setup.yml` (as of 2026-03-30):

| Container | Compose location | Notes |
|-----------|------------------|-------|
| `csc-api-1` | `/home/csc/docker-compose.yml` | New graphics app — the ONLY expected container |

**Disabled / removed** (do not expect running):
- `gfx-gfx-control-1`, `gfx-gfx-proxy-1` — `gfx` role commented out in `playbooks/setup.yml`
- `auth-*` (Zitadel + oauth2-proxy) — removed, compose at `/opt/auth/` retained but not deployed

Any other container running = unexpected, worth investigating (not deployed by Ansible).

## Step 3 — Deeper checks (if something looks wrong)

### mediamtx not streaming
```bash
ssh root@csos.josefkolar.cz 'systemctl status csos-mediamtx --no-pager -l | head -30'
ssh root@csos.josefkolar.cz 'journalctl -u csos-mediamtx -n 50 --no-pager'
```

Check restream ffmpeg children under the cgroup — should see 2× ffmpeg (YouTube + Facebook) + 3× snapshot loops.

### Caddy failing
```bash
ssh root@csos.josefkolar.cz 'caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile'
ssh root@csos.josefkolar.cz 'journalctl -u caddy -n 30 --no-pager'
```

TLS/listener changes require **restart, not reload** (SO_REUSEPORT limitation, per `AGENTS.md`).

### Telemetry endpoints
- Grafana: `https://csos.josefkolar.cz/grafana/` (anonymous read-only)
- Prometheus: reverse-proxied by Caddy, admin only
- mediamtx metrics: `http://127.0.0.1:9998/metrics` (behind Caddy)
- Caddy admin: `http://127.0.0.1:2019/metrics`

### Disk pressure
```bash
ssh root@csos.josefkolar.cz 'du -sh /var/log/journal /var/mediamtx /var/lib/docker 2>/dev/null | sort -h'
```

## Step 4 — Grafana MCP (optional richer view)

If the `scif-monitoring` Grafana MCP is available, query node_exporter series directly:

- **Datasource discovery**: `list_datasources(type="prometheus")` — do NOT hardcode UIDs.
- **Load 5m**: `node_load5{instance=~"csos.*"}`
- **Memory available**: `node_memory_MemAvailable_bytes{instance=~"csos.*"} / node_memory_MemTotal_bytes{instance=~"csos.*"}`
- **Disk free /**: `node_filesystem_avail_bytes{instance=~"csos.*",mountpoint="/"} / node_filesystem_size_bytes{instance=~"csos.*",mountpoint="/"}`
- **mediamtx up**: `up{job="mediamtx"}`

Preferred for trends. SSH is preferred for a fast point-in-time snapshot.

## What NOT to do

1. **Never check `systemctl is-active mediamtx`** — the unit is `csos-mediamtx`. The bare name is unused and returns `inactive`, which is misleading.
2. **Never `docker rm -f` unexpected containers without asking** — they may be user-managed apps not in this repo.
3. **Never `caddy reload` after TLS changes** — must restart. Reload only handles route/handler changes.
4. **Never assume gfx is running** — the role is disabled in `playbooks/setup.yml` as of 2026-03-30.
5. **Never SSH with `-o StrictHostKeyChecking=no` on first contact without noting it** — the host key should already be trusted.

## Quick verdict rubric

- ✅ **Healthy**: load ≤ 2, mem available > 1 Gi, disk / < 75%, all 5 systemd units active, only `csc-api-1` in docker.
- ⚠️ **Warn**: load 2–2.5 sustained, disk 75–90%, swap growing, unexpected container running.
- 🚨 **Critical**: any systemd unit inactive/failed, load > 3, disk > 90%, `csos-mediamtx` not streaming (no ffmpeg children).
