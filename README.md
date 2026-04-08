# ČSOS Proxy Ansible

Ansible project deploying a ČSOS livestreaming relay server on Ubuntu 24.04. Components: [mediamtx](https://github.com/bluenviron/mediamtx) (RTMP/SRT ingest, HLS/WebRTC output), [Caddy](https://caddyserver.com/) (reverse proxy, TLS), Prometheus + Grafana + Node Exporter (telemetry).

## Connecting streams

Each stream has a **slot** — a unique identifier (mediamtx calls it a `path`). All slots use the `x/` prefix. RTMP for ingest (write), SRT for consumption (read).

| Slot | Write (RTMP) | Read (SRT) | HLS |
|------|-------------|------------|-----|
| `x/macos-stream` | `rtmp://HOST:1935/x/macos-stream?user=U&pass=P` | `srt://HOST:8890?streamid=read:x/macos-stream:U:P` | `https://HOST/hls/x/macos-stream/` |
| `x/pocket1` | `rtmp://HOST:1935/x/pocket1?user=U&pass=P` | `srt://HOST:8890?streamid=read:x/pocket1:U:P` | `https://HOST/hls/x/pocket1/` |
| `x/pocket2` | `rtmp://HOST:1935/x/pocket2?user=U&pass=P` | `srt://HOST:8890?streamid=read:x/pocket2:U:P` | `https://HOST/hls/x/pocket2/` |
| `x/drone1` | `rtmp://HOST:1935/x/drone1?user=U&pass=P` | `srt://HOST:8890?streamid=read:x/drone1:U:P` | `https://HOST/hls/x/drone1/` |
| `x/mobile1`–`x/mobile5` | `rtmp://HOST:1935/x/mobileN?user=U&pass=P` | `srt://HOST:8890?streamid=read:x/mobileN:U:P` | `https://HOST/hls/x/mobileN/` |
| `x/insta1` | `rtmp://HOST:1935/x/insta1?user=U&pass=P` | `srt://HOST:8890?streamid=read:x/insta1:U:P` | `https://HOST/hls/x/insta1/` |

`HOST` = `csos.josefkolar.cz` (prod) or `csos.orb.local` (local dev).

## Monitoring

### Grafana

Anonymous read-only access (no login required):

```
https://csos.josefkolar.cz/grafana/
```

The mediamtx dashboard shows per-slot thumbnail previews (auto-refreshed via FFmpeg snapshots), bandwidth, protocol connections, and error frames.

### Stream debugging

Preview via RTMP:
```shell
ffplay "rtmp://csos.josefkolar.cz:1935/SLOT?user=USER&pass=PASS"
```

HLS preview (no auth):
```
https://csos.josefkolar.cz/hls/SLOT/
```

Thumbnail snapshots (no auth, refreshed every 5s while stream is active):
```
https://csos.josefkolar.cz/snapshots/SLOT.jpg
```

## Administration

### Prerequisites

```shell
ansible-galaxy install -r requirements.yml
```

### Deploy

```shell
# Production
ansible-playbook -i inventory/csos.yml playbooks/setup.yml \
  -e @csos.enc --vault-password-file pass.env

# Local dev (OrbStack)
ansible-playbook -i inventory/orb.yaml playbooks/setup.yml

# Single role
ansible-playbook -i inventory/orb.yaml playbooks/setup.yml --tags web_proxy
```

### Secrets

Production secrets live in `csos.enc` (Ansible Vault). Local dev uses plaintext dummy values in `inventory/orb.yaml`.

Secrets are structured as a `credentials` dict with keys: `stream_write`, `stream_read`, `telemetry`, `gfx`.

### Configuration

| What | Where |
|------|-------|
| Stream slots | `roles/stream_proxy/templates/mediamtx.yml` |
| Reverse proxy routes | `roles/web_proxy/templates/Caddyfile.j2` |
| Monitoring targets | `roles/telemetry/tasks/main.yml` |
| Grafana dashboards | `roles/telemetry/files/mediamtx-dashboard.json` |
| Playbook entry point | `playbooks/setup.yml` |
