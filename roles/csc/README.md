# csc role

Deploys [co-stream-control](https://github.com/thejoeejoee/co-stream-control) — FastAPI backend + two Nuxt SPAs (admin + gfx) built as pure static bundles — with **native PostgreSQL 16** on the VM and (optionally) the ADR-044 **DMR 5G tile stack** (self-hosted OpenTopoData + tile-mirror sidecar).

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ VM                                                              │
│  PostgreSQL 16 (apt, systemd)                 listen 127.0.0.1  │
│                                                    ▲            │
│  Docker Compose                                    │            │
│   ├─ api             (FastAPI)     127.0.0.1:8100 ─┤            │
│   │                  extra_hosts host.docker.internal           │
│   │                  vols: heightmap_cache, otd_tiles (:ro)     │
│   │                                                             │
│   ├─ otd  (opt.)     (OpenTopoData) 127.0.0.1:5001              │
│   │                  vols: otd_tiles (:ro)                      │
│   │                                                             │
│   └─ dmr5g-mirror    (sidecar, no port)                         │
│                      extra_hosts host.docker.internal ──────────┘
│                      vols: otd_tiles (rw)
│                                                          │
│  Static SPA bundles (built once per deploy in throwaway  │
│  node:24-slim container; Caddy serves them directly)     │
│    /home/csc/admin/   (Nuxt admin, ssr:false)            │
│    /home/csc/gfx/     (Nuxt gfx,   ssr:false)            │
│                                                          │
│  Caddy (web_proxy role)                                  │
│    csc.HOST/api/gfx/stream/* → api (SSE, no auth)        │
│    csc.HOST/api/*            → api (basic_auth)          │
│    csc.HOST/*                → admin static (basic_auth) │
│    gfx.csc.HOST/*            → gfx static  (no auth)     │
└──────────────────────────────────────────────────────────┘
```

The `otd` + `dmr5g-mirror` services are gated by `csc__dmr5g_enabled` (default `true`). When disabled, the api's DemSource cascade (ADR-043) silently falls through to Copernicus GLO-30 (~4 m RMSE) instead of DMR 5G (~0.18 m RMSE). Only useful on deployments handling Czech events; safe to disable elsewhere.

## Prerequisites

1. **DNS**: two A records → VM IP
   - `csc.csos.josefkolar.cz` — admin SPA + API mount at `/api/*` + public SSE at `/api/gfx/stream/*`
   - `gfx.csc.csos.josefkolar.cz` — public GFX overlay (browser source for OBS/vMix)

2. **Vault secrets** in `csos.enc`:
   ```yaml
   credentials:
     csc:                    # basic_auth on csc.HOST (admin static + /api/*)
       - { user: admin, pass: <secret> }
     csc_db:                 # native PostgreSQL role + database
       user: csc
       pass: <secret>
       name: csc
   ```

3. **Source repo**: `co-stream-control/` checked out alongside `co-ansible/`. Path overridable via `csc__source_dir`.

4. **Production Dockerfile** for the API in the source repo: `api/Dockerfile.prod` (uv workspace-aware per ADR-045). admin + gfx have no runtime container — they are static SPAs built via `pnpm --filter <app> build` inside a throwaway builder.

5. **DMR 5G stack (optional)** — needs `otd/Dockerfile` and `otd/config.yaml` in the source repo. Disable by setting `csc__dmr5g_enabled: false` in inventory. The OpenTopoData image builds from the `ajnisbet/opentopodata` git tag `v1.10.0` at compose-up time (no image pull); `platforms: linux/amd64` works around an expired Apache Arrow apt-repo signing key in their arm64 Dockerfile.

## Deploy

The role touches both `csc` (this role) and `web_proxy` (Caddyfile has the three new sites), so run both tags together:

```bash
ansible-playbook -i inventory/csos.yml playbooks/setup.yml \
  --tags csc,web_proxy \
  -e @csos.enc --vault-password-file .pass.env
```

### Sub-tag deploys (touch only one component)

| Tag              | Runs                                                                       |
| ---------------- | -------------------------------------------------------------------------- |
| `csc`            | full deploy — postgres+db, source, install, admin+gfx **in parallel**, compose (api + optional dmr5g stack), api migrate |
| `csc_api`        | postgres+db, source, compose, alembic migration                            |
| `csc_admin`      | source, workspace install, admin SPA build only                            |
| `csc_gfx`        | source, workspace install, gfx SPA build only                              |

Sub-tags compose: `--tags csc_api,csc_admin` runs postgres + db + source + install + admin build + api recreate + migrate (skips gfx). Under `--tags csc`, both frontend builds fire asynchronously and are awaited together, so the full deploy takes roughly `install + max(admin_build, gfx_build)` instead of `install + admin_build + gfx_build`.

Local dev on OrbStack:

```bash
ansible-playbook -i inventory/orb.yaml playbooks/setup.yml \
  --tags csc,web_proxy
```

## What happens on deploy

1. `postgresql-16` apt-installed, `listen_addresses = '127.0.0.1'`, `pg_hba.conf` allows the Docker bridge subnet.
2. `csc` role + `csc` database created (idempotent, password from vault).
3. `co-stream-control/` rsynced to `{{ csc__home_dir }}/src/` (default `/home/csc/src/`).
4. `api.env` + `docker-compose.yml` rendered from inventory vars.
5. Throwaway `node:24-slim` container runs `pnpm install --frozen-lockfile` once, populating shared caches. Then two build containers fire **in parallel** (via Ansible `async: 900 poll: 0`), each with its own `NUXT_PUBLIC_API_BASE` baked in (`ssr:false` means it's a build-time constant):
   - admin: `NUXT_PUBLIC_API_BASE=/api` (same-origin, relative)
   - gfx:   `NUXT_PUBLIC_API_BASE=https://csc.HOST/api` (cross-origin absolute)
   `wait_builds.yml` waits on both with `async_status`; whichever build was skipped by tag has its wait silently no-op'd by a `when` guard. Explicit caches:
   - pnpm store at `{{ csc__home_dir }}/pnpm-store` (content-addressed tarballs)
   - node_modules trees at `{{ csc__home_dir }}/nm-cache/{root,admin,gfx,shared}`
6. `docker compose up --build` — the `api` service (always) + `otd` + `dmr5g-mirror` (when `csc__dmr5g_enabled`).
7. `docker compose run --rm api uv run alembic upgrade head` — schema migration.

## Auth model

| Surface                             | Auth                                                              |
| ----------------------------------- | ----------------------------------------------------------------- |
| `csc.HOST/*` (admin static)         | Caddy `basic_auth` via `credentials.csc`                          |
| `csc.HOST/api/*` (API)              | Caddy `basic_auth` via `credentials.csc` (same realm as admin)    |
| `csc.HOST/api/gfx/stream/*` (SSE)   | none — public per ADR-012 (slot slug is the obscurity token)      |
| `gfx.csc.HOST/*` (overlay)          | none — public, browser source for OBS/vMix                        |

The API itself runs with `CSC_PROXY_AUTH_ENABLED=false` — every request that gets past Caddy is treated as the built-in dev admin user. Caddy is the sole gatekeeper. To upgrade to real role-based auth later, put oauth2-proxy in front of `csc.HOST/api/*` and flip `CSC_PROXY_AUTH_ENABLED=true`.

FastAPI is started with `uvicorn --root-path /api` so absolute URLs it generates (openapi.json, Swagger UI, pagination Location headers) include the prefix and stay correct end-to-end. Caddy strips `/api` before proxying so FastAPI's route table stays at its native paths (`/health`, `/events`, ...).

## DMR 5G stack (ADR-044 + ADR-046)

When `csc__dmr5g_enabled: true` (default), the compose stack gains:

- `otd`: OpenTopoData serving the DMR 5G VRT at `http://otd:5000/v1`, reached by the api's DemSource cascade. Bound on `127.0.0.1:{{ csc__otd_port }}` for operator debug (curl'able from the VM).
- `dmr5g-mirror`: LISTEN/NOTIFY-driven sidecar that walks the CUZK CDN, downloads tiles into the shared `otd_tiles` volume, and updates the VRT mosaic. Belt-and-braces 30 s poll interval catches missed signals. `stop_grace_period: 2m` matches the sidecar's in-flight drain window.
- Shared named volume `otd_tiles`. Writer: `dmr5g-mirror`. Readers: `otd` (raster serving) and `api` (rasterio direct reads via `CSC_DMR5G_VRT_PATH`, slice 2.5). Api mount is read-only.

Disable via `csc__dmr5g_enabled: false` in inventory. The api's DemSource cascade then falls through to Copernicus GLO-30 (~4 m RMSE) — same behaviour as with the stack up but the CDN empty. No config change needed on the api side; `CSC_OTD_BASE_URL` / `CSC_DMR5G_VRT_PATH` are simply omitted from `api.env`.

## Overriding defaults

See `defaults/main.yml`. Common:

- `csc__source_dir` — path to `co-stream-control/` checkout
- `csc__api_port` — 127.0.0.1 bind for the api container
- `csc__admin_dist` / `csc__gfx_dist` — where Caddy reads the static bundles from
- `csc__log_level` — API + sidecar `CSC_LOG_LEVEL`
- `csc__heightmap_cache_dir` — path inside the api container where the ADR-046 heightmap PNG cache lives (mounted from a named volume so it survives restarts)
- `csc__dmr5g_enabled` — turn the OTD + sidecar stack on/off
- `csc__otd_port` — 127.0.0.1 bind for the OTD debug port
- `csc__dmr5g_concurrency` — parallel HTTP fetches the sidecar opens against the CUZK CDN
