# PROJECT KNOWLEDGE BASE

**Generated:** 2026-08-18
**Commit:** feat/orb-inventory + csc DMR 5G stack

## OVERVIEW

Ansible project deploying a CSOS livestreaming relay server: mediamtx (RTMP/SRT/WebRTC ingest + HLS output), Caddy (reverse proxy + TLS), Prometheus + Grafana + Node Exporter (telemetry), Tally Arbiter (tally lights, currently disabled), and the **co-stream-control** stack (FastAPI + admin/gfx Nuxt SPAs + native PostgreSQL 16 + optional ADR-044 DMR 5G tile mirror).

## STRUCTURE

```
co-ansible/
├── playbooks/setup.yml       # Single entry point — imports all roles
├── inventory/
│   ├── csos.yml              # Production (csos.josefkolar.cz, root)
│   └── orb.yaml              # Local dev (OrbStack VM, non-root)
├── roles/
│   ├── base/                 # apt, ffmpeg, Docker (via geerlingguy.docker)
│   ├── auth/                 # Casdoor (OIDC) + oauth2-proxy (Caddy forward_auth gateway)
│   ├── stream_proxy/         # mediamtx binary + systemd + UFW + config
│   ├── web_proxy/            # Caddy (via caddy_ansible) + Caddyfile + UFW
│   │                         # Templates ALSO carry the csc.HOST + gfx.csc.HOST sites
│   ├── telemetry/            # Prometheus + Grafana + Node Exporter (Galaxy collections)
│   ├── csc/                  # co-stream-control stack (FastAPI + admin/gfx SPAs
│   │                         # + PostgreSQL 16 + optional DMR 5G tile stack)
│   ├── gfx/                  # LEGACY: orienteering-tv-graphics gfx.
│   │                         # DISABLED in playbook; superseded by csc's gfx SPA.
│   └── ta/                   # Tally Arbiter via Docker Compose (DISABLED in playbook)
├── requirements.yml          # Galaxy roles + collections
└── csos.enc                  # Ansible Vault encrypted secrets
```

## WHERE TO LOOK

| Task | Location | Notes |
|------|----------|-------|
| Add/change stream slots | `roles/stream_proxy/templates/mediamtx.yml` | Each path = one ingest slot |
| Change reverse proxy routes | `roles/web_proxy/templates/Caddyfile.j2` | Caddy config, Jinja2 templated |
| Add monitoring targets | `roles/telemetry/tasks/main.yml` | `prometheus_scrape_configs` inline |
| Grafana dashboards | `roles/telemetry/tasks/main.yml` | `grafana_dashboards` list with dashboard IDs |
| Secrets/passwords | `inventory/*.yml` or `csos.enc` | Per-inventory vars, vault for prod |
| SSO / group ACLs | `roles/auth/` + `require_group` snippet in `roles/web_proxy/templates/Caddyfile.j2` | Casdoor groups (`{{ auth__org }}/admin` etc.); new users get none by default |
| csc container / env / compose | `roles/csc/templates/{api.env,docker-compose.yml}.j2` | Prod compose stack for co-stream-control |
| csc frontend build knobs | `roles/csc/tasks/{install,build_admin,build_gfx}.yml` | Node throwaway containers + pnpm caches |
| DMR 5G tile stack on/off | `roles/csc/defaults/main.yml` → `csc__dmr5g_enabled` | Adds `otd` + `dmr5g-mirror` services |
| Enable legacy gfx role | `playbooks/setup.yml` — uncomment the `gfx` import | Superseded by csc's own gfx SPA |
| Enable Tally Arbiter | `playbooks/setup.yml` — uncomment the `ta` role import | Currently off |

## CONVENTIONS

- **Variable namespacing**: `rolename__variable` (double underscore) — e.g. `csos_stream_proxy__write_pass`, `web_proxy__domain`, `telemetry__grafana_admin_pass`, `csc__dmr5g_enabled`
- **No ansible.cfg**: uses Ansible defaults
- **No linting config**: no ansible-lint, yamllint, or pre-commit
- **Galaxy roles wrapped in `block: become: true`**: required because `include_role` doesn't propagate `become` to Galaxy role tasks
- **Caddy config managed outside Galaxy role**: `caddy_config_update: false` disables Galaxy's config write; own `Deploy Caddyfile` task with `validate` + `notify: Restart caddy`
- **Restart over reload for Caddy**: TLS/listener changes require restart, not reload (SO_REUSEPORT limitation)
- **Sub-tag deploys on csc**: `csc_api`, `csc_admin`, `csc_gfx` compose — see `roles/csc/README.md`

## ANTI-PATTERNS (THIS PROJECT)

- **Never use Caddy reload for TLS changes** — must restart; reload only applies route/handler changes
- **Never deploy Caddyfile without validation** — `caddy validate --config %s --adapter caddyfile` in copy task prevents broken configs from killing Caddy on restart
- **Do not add `become: true` to individual Galaxy tasks** — wrap the entire `include_role` in a `block` with `become: true`
- **Never raise `csc__api_workers` above 1** — the API is single-process by design (ADR-023 in co-stream-control). Its SSE fan-out, admin invalidation bus, and background OResults pollers/replay ticker are in-memory per-process singletons. `workers > 1` silently drops gfx frames and double-runs pollers.

## INVENTORY DIFFERENCES

| Aspect | `csos.yml` (prod) | `orb.yaml` (local dev) |
|--------|-------------------|------------------------|
| Host | `csos.josefkolar.cz` | `csos@orb` (OrbStack SSH) |
| User | `root` | `csos` (non-root, needs become) |
| TLS | Real certs (default) | `tls internal` (self-signed) |
| Domain | `csos.josefkolar.cz` | `csos.orb.local` |
| Secrets | `csos.enc` (vault) | Inline dummy values |

## ROLE EXECUTION ORDER

`base` → `auth` → `stream_proxy` / `telemetry` / `csc` (parallel via `strategy: free`) → `web_proxy`

- `base` installs Docker (needed by `ta`, `csc`, `auth`)
- `auth` deploys Casdoor + oauth2-proxy and (first run only) bootstraps the org/groups/applications; `telemetry` (Grafana OIDC) and `web_proxy` (Caddyfile ACLs) both consume its output, so it must run before them
- `web_proxy` reverse-proxies to mediamtx (8888/8889), Prometheus (9090), Grafana (3000), Casdoor (8000), oauth2-proxy (4180), and `csc` (127.0.0.1:8100 for api, static bundles for admin + gfx)
- `telemetry` scrapes mediamtx (9998) and Caddy (2019) metrics; Grafana itself logs in via Casdoor OIDC
- `csc` installs PostgreSQL 16 natively, deploys the FastAPI container, builds admin + gfx as static SPAs, and (optionally) runs the ADR-044 DMR 5G tile stack (`otd` + `dmr5g-mirror`)

## COMMANDS

```bash
# Production deploy (full)
ansible-playbook -i inventory/csos.yml playbooks/setup.yml \
  -e @csos.enc --vault-password-file .pass.env

# Local dev deploy (full)
ansible-playbook -i inventory/orb.yaml playbooks/setup.yml

# Single role (tag-based)
ansible-playbook -i inventory/orb.yaml playbooks/setup.yml --tags web_proxy

# csc sub-tag deploys — see roles/csc/README.md for the tag-composition table
ansible-playbook -i inventory/csos.yml playbooks/setup.yml \
  --tags csc,web_proxy -e @csos.enc --vault-password-file .pass.env
ansible-playbook -i inventory/csos.yml playbooks/setup.yml \
  --tags csc_admin -e @csos.enc --vault-password-file .pass.env

# Install Galaxy dependencies
ansible-galaxy install -r requirements.yml
```

## NOTES

- **OrbStack `.orb.local` proxy**: forces HTTPS to port 443 — cannot serve plain HTTP. Solved with `tls internal` (self-signed certs) controlled by `web_proxy__disable_tls` inventory var.
- **mediamtx config is 93 lines** — the largest template. Stream slots (paths) are hardcoded there, not dynamically generated.
- **Grafana `root_url`** in telemetry role derives from `web_proxy__domain` — cross-role dependency on `web_proxy` inventory var.
- **csc api uses a single, workspace-aware `api/Dockerfile`** (ADR-045 in co-stream-control): dev and prod share the same image — the compose files differ only in the CMD override (`--reload` in dev, `--root-path /api --workers 1` in prod). The compose ``context`` is the whole repo root because the API image needs the workspace root pyproject + lockfile + `packages/py-shared` sources at build time.
- **DMR 5G stack default-on**: `csc__dmr5g_enabled: true`. Adds ~1–2 GB of tiles per Czech event over time on the shared `otd_tiles` volume. Set to `false` in inventory for deployments that don't handle Czech events — the api cascades to Copernicus GLO-30 with no config change on the api side.
- **README is stale in one spot** — references `playbooks/templates/` which no longer exists (moved to `roles/stream_proxy/templates/`).
- **Casdoor's `app-built-in` client secret is publicly readable** via unauthenticated `GET /api/get-application?id=admin/app-built-in` (Casdoor's own design — the app exists so anyone can look up its OIDC metadata). `roles/auth/tasks/reconcile.yml` deliberately authenticates with a `built-in/admin` session cookie instead, never with that client secret.
- **Casdoor's default `built-in/admin` password is `123`** on first boot of an empty SQLite volume. `reconcile.yml` rotates it to `auth__admin_pass` via `/api/set-password` on that first run — don't skip that step if hand-rolling a Casdoor deploy outside this role.
- **Casdoor `groups` claim is namespaced `{{ auth__org }}/<name>`**, not bare group names — Caddyfile ACLs and Grafana's `role_attribute_path` must match on the prefixed form.
- **`roles/auth/tasks/reconcile.yml` runs on every deploy, not just the first** — `defaults/main.yml`'s `auth__groups`/`auth__providers`/`auth__applications` are the declarative source of truth; editing them and redeploying is enough to change Casdoor's state (see `roles/auth/README.md`).
- **Casdoor bug: `Application.IsPasswordEnabled()` ignores the "Hide password" signin-method rule** — it only checks whether *any* entry named "Password" exists. The only way to actually disable password login server-side is an explicitly empty `signinMethods` list (falls through to the `enablePassword` bool, which the buggy check doesn't skip). Don't "fix" this by adding a Password entry with `rule: "Hide password"` — it looks right in the UI but doesn't block a direct `/api/login` call.
