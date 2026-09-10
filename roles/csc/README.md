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
│  Static SPA bundles (built on the control node by        │
│  default, rsynced in; Caddy serves them directly)        │
│    /home/csc/admin/   (Nuxt admin, ssr:false)            │
│    /home/csc/gfx/     (Nuxt gfx,   ssr:false)            │
│                                                          │
│  Caddy (web_proxy role)                                  │
│    csc.HOST/api/gfx/stream/* → api (SSE, no auth)        │
│    csc.HOST/api/gfx-assets/* → api (no auth)             │
│    csc.HOST/api/gps-seuranta/*/map.jpg → api (no auth)   │
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

4. **Single unified `api/Dockerfile`** in the source repo (uv workspace-aware per ADR-045). Dev and prod share the same image — the compose files differ only in the CMD override. admin + gfx have no runtime container — they are static SPAs built via `pnpm --filter ./<app> build` on the control node (or, under `remote_build`, inside a throwaway builder on the VM).

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
| `csc`            | full deploy — everything below, admin+gfx built **in parallel**             |
| `csc_db`         | native PostgreSQL only: apt install, `pg_hba`, UFW, `csc` role + database   |
| `csc_api`        | api only: source, `compose up api`, alembic migration                      |
| `csc_admin`      | source, workspace install, admin SPA build only                            |
| `csc_gfx`        | source, workspace install, gfx SPA build only                              |
| `csc_otd`        | DMR 5G only: source, `compose up otd dmr5g-mirror` (no-op when `csc__dmr5g_enabled: false`) |

Add `remote_build` to any of these to build admin/gfx on the VM instead of locally — see [Build location](#build-location).

Every sub-tag first rsyncs the source and re-renders `api.env` + `docker-compose.yml` — those are cheap and shared. Beyond that the tags are disjoint, and each compose call is scoped with `services:`, so `--tags csc_api` rebuilds and recreates *only* the api container (the DMR containers keep running untouched), and `--tags csc_otd` never bounces the api.

`csc_db` is deliberately **not** pulled in by `csc_api`: provisioning Postgres is an apt-install that rarely changes, and leaving it out is what makes an api redeploy fast. A first-ever deploy to a fresh VM must therefore use `--tags csc` (or `csc_db,csc_api`).

Sub-tags compose freely: `--tags csc_api,csc_admin` runs source + install + admin build + api recreate + migrate, skipping gfx. Under `--tags csc`, both frontend builds fire asynchronously and are awaited together, so the full deploy takes roughly `install + max(admin_build, gfx_build)` instead of `install + admin_build + gfx_build`.

```bash
# fast api-only redeploy (prod)
ansible-playbook -i inventory/csos.yml playbooks/setup.yml \
  --tags csc_api -e @csos.enc --vault-password-file .pass.env
```

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
5. `pnpm install --frozen-lockfile`, then the two SPA builds fire **in parallel** (via Ansible `async: 900 poll: 0`), each with its own `NUXT_PUBLIC_API_BASE` baked in (`ssr:false` means it's a build-time constant):
   - admin: `NUXT_PUBLIC_API_BASE=/api` (same-origin, relative)
   - gfx:   `NUXT_PUBLIC_API_BASE=https://csc.HOST/api` (cross-origin absolute)

   `wait_builds.yml` waits on both with `async_status`; whichever build was skipped by tag has its wait silently no-op'd by a `when` guard. **Where** this runs is the one knob — see [Build location](#build-location) below.
6. `publish_bundles.yml` rsyncs `<app>/.output/public/` into `{{ csc__admin_dist }}` / `{{ csc__gfx_dist }}` with `--delete`. No-op under `remote_build` (the builders wrote there directly).
7. `docker compose up --build api` — service-scoped, so nothing else in the project is touched.
8. `docker compose run --rm api uv run alembic upgrade head` — schema migration.
9. `docker compose up --build otd dmr5g-mirror` (when `csc__dmr5g_enabled`) — last, so the mirror's LISTEN/NOTIFY tables already exist.

## Build location

The admin + gfx Nuxt builds run **on the control node** by default — the machine
you type `ansible-playbook` on. A dev laptop has the toolchain, a warm pnpm
store and the cores; a small VM has none of the three, and a Nuxt build is by
far the heaviest thing this role does. Only the finished `.output/public/` tree
crosses the wire, as an rsync delta.

```bash
# default — admin/gfx built locally, bundles rsynced to the VM
ansible-playbook -i inventory/csos.yml playbooks/setup.yml \
  --tags csc -e @csos.enc --vault-password-file .pass.env

# opt out — builds run in throwaway node:24-slim containers on the VM
ansible-playbook -i inventory/csos.yml playbooks/setup.yml \
  --tags csc,remote_build -e @csos.enc --vault-password-file .pass.env
```

`remote_build` is a **switch, not a selector**: it doesn't pick any tasks of its
own, it only flips `csc__build_remote` (which reads `ansible_run_tags`). Keep
`csc` — or `csc_admin` / `csc_gfx` — in the tag list to actually select the
builds. For a host that should *always* build remotely, set the variable in
inventory instead of remembering the tag:

```yaml
csc__build_remote: true
```

| | control node (default) | `remote_build` |
|---|---|---|
| deps | `pnpm install --frozen-lockfile` in `csc__source_dir` | throwaway `node:24-slim`, deps into `{{ csc__home_dir }}/nm-cache/**` |
| build | `pnpm --filter ./<app> build` in the checkout | `node:24-slim` container per app |
| caches | the checkout's own `node_modules` + pnpm store | `{{ csc__home_dir }}/pnpm-store`, `nm-cache/{root,admin,gfx,shared}` |
| VM needs | rsync only | docker + ~2 GB of node deps + build RAM |
| ships | `.output/public/` rsync delta | nothing — built in place |

Caveats for the local path:

- It builds **in the checkout**, so `admin/.output` and `gfx/.output` get
  overwritten, and `gfx`'s bundle is baked against the deploy target's domain
  (`https://csc.{{ web_proxy__domain }}/api`), not localhost.
- `pnpm` must resolve on the PATH `ansible-playbook` inherits. If it's a shim
  that only exists in an interactive shell, point `csc__pnpm_bin` at the
  absolute path.
- `--frozen-lockfile` still applies: the bundle is built from what
  `pnpm-lock.yaml` pins, not from a drifted local tree.
- If that install fails, the role **deletes the checkout's `node_modules`**
  (root, `admin`, `gfx`, `packages/shared`) and installs once more. A
  long-lived `node_modules` linked from an older `pnpm-lock.yaml` is the
  common cause — `.npmrc` sets `node-linker=hoisted`, so the tree is flat and
  a package's install script can still resolve the very version it is
  replacing (esbuild fails this way: `Expected "0.28.2" but got "0.28.1"`).
  Only the linked tree goes; the pnpm store is untouched, so the reinstall is
  mostly hardlinks. A missing `pnpm` is caught by its own task first, so it
  can never trigger the wipe.

Docker images (`api`, `otd`, `dmr5g-mirror`) are **not** covered by this switch —
they always build on the target. They're linux/amd64; emulating that on an
arm64 laptop and shipping the layers over ssh is slower than letting the VM
build them natively.

## Auth model

| Surface                             | Auth                                                              |
| ----------------------------------- | ----------------------------------------------------------------- |
| `csc.HOST/*` (admin static)         | Caddy `basic_auth` via `credentials.csc`                          |
| `csc.HOST/api/*` (API)              | Caddy `basic_auth` via `credentials.csc` (same realm as admin)    |
| `csc.HOST/api/gfx/stream/*` (SSE)   | none — public per ADR-012 (slot slug is the obscurity token)      |
| `csc.HOST/api/gfx-assets/*`         | none — public assets (ADR-046 heightmap PNGs)                     |
| `csc.HOST/api/gps-seuranta/*/map.jpg` | none — public raster proxy                                      |
| `gfx.csc.HOST/*` (overlay)          | none — public, browser source for OBS/vMix                        |

The three public `/api/*` carve-outs exist because the gfx overlay is served
from a different origin (`gfx.csc.HOST`) and fetches them cross-origin with no
credentials. Behind `basic_auth` they return 401, and a 401 carries no
`Access-Control-Allow-Origin`, so the browser reports it as a CORS error rather
than an auth error. The API already returns these routes with
`Access-Control-Allow-Origin: *`. The gps-seuranta carve-out is scoped to
`map.jpg` specifically — the rest of that namespace has admin-only POST routes.

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
- `csc__build_remote` — build admin/gfx on the target instead of the control node (see [Build location](#build-location))
- `csc__pnpm_bin` — pnpm executable used for control-node builds
