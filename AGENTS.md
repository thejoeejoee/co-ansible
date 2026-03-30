# PROJECT KNOWLEDGE BASE

**Generated:** 2026-03-30
**Commit:** a74f910
**Branch:** feat/orb-inventory

## OVERVIEW

Ansible project deploying a CSOS livestreaming relay server: mediamtx (RTMP/SRT/WebRTC ingest + HLS output), Caddy (reverse proxy + TLS), Prometheus + Grafana + Node Exporter (telemetry), Tally Arbiter (tally lights, currently disabled).

## STRUCTURE

```
co-ansible/
├── playbooks/setup.yml      # Single entry point — imports all roles
├── inventory/
│   ├── csos.yml              # Production (csos.josefkolar.cz, root)
│   └── orb.yaml              # Local dev (OrbStack VM, non-root)
├── roles/
│   ├── base/                 # apt, ffmpeg, Docker (via geerlingguy.docker)
│   ├── stream_proxy/         # mediamtx binary + systemd + UFW + config
│   ├── web_proxy/            # Caddy (via caddy_ansible) + Caddyfile + UFW
│   ├── telemetry/            # Prometheus + Grafana + Node Exporter (Galaxy collections)
│   └── ta/                   # Tally Arbiter via Docker Compose (DISABLED in playbook)
├── requirements.yml          # Galaxy roles + collections
└── secrets.enc               # Ansible Vault encrypted secrets
```

## WHERE TO LOOK

| Task | Location | Notes |
|------|----------|-------|
| Add/change stream slots | `roles/stream_proxy/templates/mediamtx.yml` | Each path = one ingest slot |
| Change reverse proxy routes | `roles/web_proxy/templates/Caddyfile.j2` | Caddy config, Jinja2 templated |
| Add monitoring targets | `roles/telemetry/tasks/main.yml` | `prometheus_scrape_configs` inline |
| Grafana dashboards | `roles/telemetry/tasks/main.yml` | `grafana_dashboards` list with dashboard IDs |
| Secrets/passwords | `inventory/*.yml` or `secrets.enc` | Per-inventory vars, vault for prod |
| Enable Tally Arbiter | `playbooks/setup.yml` line 20-22 | Uncomment the `ta` role import |

## CONVENTIONS

- **Variable namespacing**: `rolename__variable` (double underscore) — e.g. `csos_stream_proxy__write_pass`, `web_proxy__domain`, `telemetry__grafana_admin_pass`
- **No ansible.cfg**: uses Ansible defaults
- **No linting config**: no ansible-lint, yamllint, or pre-commit
- **Galaxy roles wrapped in `block: become: true`**: required because `include_role` doesn't propagate `become` to Galaxy role tasks
- **Caddy config managed outside Galaxy role**: `caddy_config_update: false` disables Galaxy's config write; own `Deploy Caddyfile` task with `validate` + `notify: Restart caddy`
- **Restart over reload for Caddy**: TLS/listener changes require restart, not reload (SO_REUSEPORT limitation)

## ANTI-PATTERNS (THIS PROJECT)

- **Never use Caddy reload for TLS changes** — must restart; reload only applies route/handler changes
- **Never deploy Caddyfile without validation** — `caddy validate --config %s --adapter caddyfile` in copy task prevents broken configs from killing Caddy on restart
- **Do not add `become: true` to individual Galaxy tasks** — wrap the entire `include_role` in a `block` with `become: true`

## INVENTORY DIFFERENCES

| Aspect | `csos.yml` (prod) | `orb.yaml` (local dev) |
|--------|-------------------|------------------------|
| Host | `csos.josefkolar.cz` | `csos@orb` (OrbStack SSH) |
| User | `root` | `csos` (non-root, needs become) |
| TLS | Real certs (default) | `tls internal` (self-signed) |
| Domain | `csos.josefkolar.cz` | `csos.orb.local` |
| Secrets | `secrets.enc` (vault) | Inline dummy values |

## ROLE EXECUTION ORDER

`base` → `stream_proxy` / `telemetry` (parallel via `strategy: free`) → `web_proxy`

- `base` installs Docker (needed by `ta`)
- `web_proxy` reverse-proxies to mediamtx (8888/8889), Prometheus (9090), Grafana (3000)
- `telemetry` scrapes mediamtx (9998) and Caddy (2019) metrics

## COMMANDS

```bash
# Production deploy (full)
ansible-playbook -i inventory/csos.yml playbooks/setup.yml \
  -e @secrets.enc --vault-password-file .pass.env

# Local dev deploy (full)
ansible-playbook -i inventory/orb.yaml playbooks/setup.yml

# Single role (tag-based)
ansible-playbook -i inventory/orb.yaml playbooks/setup.yml --tags web_proxy

# Install Galaxy dependencies
ansible-galaxy install -r requirements.yml
```

## NOTES

- **OrbStack `.orb.local` proxy**: forces HTTPS to port 443 — cannot serve plain HTTP. Solved with `tls internal` (self-signed certs) controlled by `web_proxy__disable_tls` inventory var.
- **mediamtx config is 93 lines** — the largest template. Stream slots (paths) are hardcoded there, not dynamically generated.
- **Grafana `root_url`** in telemetry role derives from `web_proxy__domain` — cross-role dependency on `web_proxy` inventory var.
- **README is stale** — references `playbooks/templates/` which no longer exists (moved to `roles/stream_proxy/templates/`).
