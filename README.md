# ČSOS Proxy Ansible

Ansible project deploying a ČSOS livestreaming relay server on Ubuntu 24.04. Components: [mediamtx](https://github.com/bluenviron/mediamtx) (RTMP/SRT ingest, HLS output), [Caddy](https://caddyserver.com/) (reverse proxy, TLS), Prometheus + Grafana + Node Exporter (telemetry), Tally Arbiter (tally lights, currently disabled).

## Connecting streams

Each stream has a **slot** — a unique identifier (mediamtx calls it a `path`).

### Ingest (capture device → server)

```
rtmp://csos.josefkolar.cz:1935/SLOT?user=USER&pass=PASS
```

### Consumption (server → switcher)

```
srt://csos.josefkolar.cz:8890?streamid=read:SLOT:USER:PASS
```

### HLS playback

```
https://csos.josefkolar.cz/hls/SLOT/
```

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
