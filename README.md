# ČSOS Proxy Ansible

Ansible project deploying a ČSOS livestreaming relay server on Ubuntu 24.04. Components: [mediamtx](https://github.com/bluenviron/mediamtx) (RTMP/SRT ingest, HLS output), [Caddy](https://caddyserver.com/) (reverse proxy, TLS), Prometheus + Grafana + Node Exporter (telemetry), Tally Arbiter (tally lights, currently disabled).

## Connecting streams

Each stream has a **slot** — a unique identifier (mediamtx calls it a `path`). RTMP for ingest (write), SRT for consumption (read).

| Slot | Write (RTMP) | Read (SRT) | HLS |
|------|-------------|------------|-----|
| `macos-stream` | `rtmp://csos.josefkolar.cz:1935/macos-stream?user=USER&pass=PASS` | `srt://csos.josefkolar.cz:8890?streamid=read:macos-stream:USER:PASS` | `https://csos.josefkolar.cz/hls/macos-stream/` |
| `pocket1` | `rtmp://csos.josefkolar.cz:1935/pocket1?user=USER&pass=PASS` | `srt://csos.josefkolar.cz:8890?streamid=read:pocket1:USER:PASS` | `https://csos.josefkolar.cz/hls/pocket1/` |
| `pocket2` | `rtmp://csos.josefkolar.cz:1935/pocket2?user=USER&pass=PASS` | `srt://csos.josefkolar.cz:8890?streamid=read:pocket2:USER:PASS` | `https://csos.josefkolar.cz/hls/pocket2/` |
| `drone1` | `rtmp://csos.josefkolar.cz:1935/drone1?user=USER&pass=PASS` | `srt://csos.josefkolar.cz:8890?streamid=read:drone1:USER:PASS` | `https://csos.josefkolar.cz/hls/drone1/` |
| `x/drone1` | `rtmp://csos.josefkolar.cz:1935/x/drone1?user=USER&pass=PASS` | `srt://csos.josefkolar.cz:8890?streamid=read:x/drone1:USER:PASS` | `https://csos.josefkolar.cz/hls/x/drone1/` |
| `x/mobile1` | `rtmp://csos.josefkolar.cz:1935/x/mobile1?user=USER&pass=PASS` | `srt://csos.josefkolar.cz:8890?streamid=read:x/mobile1:USER:PASS` | `https://csos.josefkolar.cz/hls/x/mobile1/` |
| `x/mobile2` | `rtmp://csos.josefkolar.cz:1935/x/mobile2?user=USER&pass=PASS` | `srt://csos.josefkolar.cz:8890?streamid=read:x/mobile2:USER:PASS` | `https://csos.josefkolar.cz/hls/x/mobile2/` |
| `x/mobile3` | `rtmp://csos.josefkolar.cz:1935/x/mobile3?user=USER&pass=PASS` | `srt://csos.josefkolar.cz:8890?streamid=read:x/mobile3:USER:PASS` | `https://csos.josefkolar.cz/hls/x/mobile3/` |
| `x/mobile4` | `rtmp://csos.josefkolar.cz:1935/x/mobile4?user=USER&pass=PASS` | `srt://csos.josefkolar.cz:8890?streamid=read:x/mobile4:USER:PASS` | `https://csos.josefkolar.cz/hls/x/mobile4/` |
| `x/mobile5` | `rtmp://csos.josefkolar.cz:1935/x/mobile5?user=USER&pass=PASS` | `srt://csos.josefkolar.cz:8890?streamid=read:x/mobile5:USER:PASS` | `https://csos.josefkolar.cz/hls/x/mobile5/` |
| `insta1` | `rtmp://csos.josefkolar.cz:1935/insta1?user=USER&pass=PASS` | `srt://csos.josefkolar.cz:8890?streamid=read:insta1:USER:PASS` | `https://csos.josefkolar.cz/hls/insta1/` |
| `x/insta1` | `rtmp://csos.josefkolar.cz:1935/x/insta1?user=USER&pass=PASS` | `srt://csos.josefkolar.cz:8890?streamid=read:x/insta1:USER:PASS` | `https://csos.josefkolar.cz/hls/x/insta1/` |

`x/` prefixed slots are aliases required by the "IRL smth" Android app.

## Monitoring and debugging

### Stream debugging

Preview a stream via RTMP:
```shell
ffplay "rtmp://csos.josefkolar.cz:1935/SLOT?user=USER&pass=PASS"
```

Raw HLS endpoint (no auth):
```
http://csos.josefkolar.cz:8888/SLOT/
```

### Telemetry

Grafana and Prometheus are behind basic auth at:

```
https://csos.josefkolar.cz/grafana/
https://csos.josefkolar.cz/prometheus/
```

## Administration

### Prerequisites

```shell
ansible-galaxy install -r requirements.yml
```

### Deploy

```shell
# Production
ansible-playbook -i inventory/csos.yml playbooks/setup.yml --vault-password-file pass.env

# Local dev (OrbStack)
ansible-playbook -i inventory/orb.yaml playbooks/setup.yml --vault-password-file pass.env
```

### Secrets

Stored as inline `!vault` encrypted values in inventory files (`inventory/csos.yml`, `inventory/orb.yaml`).

Required variables:
```
csos_stream_proxy__write_pass
csos_stream_proxy__read_pass
telemetry__grafana_admin_user
telemetry__grafana_admin_pass
web_proxy__basic_auth_user
web_proxy__basic_auth_pass_hash
```

### Configuration

| What | Where |
|------|-------|
| Stream slots | `roles/stream_proxy/templates/mediamtx.yml` |
| Reverse proxy routes | `roles/web_proxy/templates/Caddyfile.j2` |
| Monitoring targets | `roles/telemetry/tasks/main.yml` |
| Playbook entry point | `playbooks/setup.yml` |
