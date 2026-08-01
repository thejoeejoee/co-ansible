# csc role

Deploys [co-stream-control](https://github.com/thejoeejoee/co-stream-control) — FastAPI backend, plus two Nuxt SPAs (admin + gfx) built as pure static bundles — with a **native PostgreSQL 16** on the VM.

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│ VM                                                       │
│  PostgreSQL 16 (apt, systemd)          listen 127.0.0.1  │
│                                             ▲            │
│  Docker Compose                             │            │
│   └─ api    (FastAPI)     127.0.0.1:8100 ───┘            │
│              extra_hosts host.docker.internal            │
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

3. **Source repo**: `co-stream-control/` checked out alongside `co-ansible/`.
   Path is overridable via `csc__source_dir`.

4. **Production Dockerfile** for the API in the source repo: `api/Dockerfile.prod`.
   See [thejoeejoee/co-stream-control#67](https://github.com/thejoeejoee/co-stream-control/issues/67).
   admin + gfx have no runtime container — they are static SPAs built via
   `pnpm --filter <app> build` inside a throwaway builder (see
   `tasks/build_frontends.yml`), so no `Dockerfile.prod` is needed for them.

## Deploy

The role touches both `csc` (this role) and `web_proxy` (Caddyfile has the
three new sites), so run both tags together:

```bash
ansible-playbook -i inventory/csos.yml playbooks/setup.yml \
  --tags csc,web_proxy \
  -e @csos.enc --vault-password-file .pass.env
```

### Sub-tag deploys (touch only one component)

| Tag              | Runs                                                              |
| ---------------- | ----------------------------------------------------------------- |
| `csc`            | full deploy — postgres+db, source, install, admin+gfx **in parallel**, api |
| `csc_api`        | postgres+db, source, api container recreate, alembic migration      |
| `csc_admin`      | source, workspace install, admin SPA build only                     |
| `csc_gfx`        | source, workspace install, gfx SPA build only                       |

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
5. Throwaway `node:24-slim` container runs `pnpm install --frozen-lockfile`
   once, populating shared caches (see below). Then two build containers
   fire **in parallel** (via Ansible `async: 900 poll: 0`), each with its own
   `NUXT_PUBLIC_API_BASE` baked in (`ssr:false` means it's a build-time
   constant):
   - admin: `NUXT_PUBLIC_API_BASE=/api` (same-origin, relative)
   - gfx:   `NUXT_PUBLIC_API_BASE=https://csc.HOST/api` (cross-origin absolute)
   `wait_builds.yml` waits on both with `async_status`; whichever build was
   skipped by tag has its wait silently no-op'd by a `when` guard.
   Output is copied atomic-ish into `{{ csc__admin_dist }}` and `{{ csc__gfx_dist }}`.
   Explicit caches:
   - pnpm store at `{{ csc__home_dir }}/pnpm-store` (content-addressed tarballs)
   - node_modules trees at `{{ csc__home_dir }}/nm-cache/{root,admin,gfx,shared}`
     (bind-mounted into every build container so the source tree stays clean;
     build containers skip apt because native modules like better-sqlite3 are
     already compiled and cached under nm-cache/**)
6. `docker compose up --build` — the single `api` service on 127.0.0.1:{{ csc__api_port }}.
7. `docker compose run --rm api uv run alembic upgrade head` — schema migration.

## Auth model

| Surface                             | Auth                                                              |
| ----------------------------------- | ----------------------------------------------------------------- |
| `csc.HOST/*` (admin static)         | Caddy `basic_auth` via `credentials.csc`                          |
| `csc.HOST/api/*` (API)              | Caddy `basic_auth` via `credentials.csc` (same realm as admin)    |
| `csc.HOST/api/gfx/stream/*` (SSE)   | none — public per ADR-012 (slot slug is the obscurity token)      |
| `gfx.csc.HOST/*` (overlay)          | none — public, browser source for OBS/vMix                        |

The API itself runs with `CSC_PROXY_AUTH_ENABLED=false` — every request that
gets past Caddy is treated as the built-in dev admin user. Caddy is the sole
gatekeeper. To upgrade to real role-based auth later, put oauth2-proxy in
front of `csc.HOST/api/*` and flip `CSC_PROXY_AUTH_ENABLED=true`.

FastAPI is started with `uvicorn --root-path /api` so absolute URLs it
generates (openapi.json, Swagger UI, pagination Location headers) include the
prefix and stay correct end-to-end. Caddy strips `/api` before proxying so
FastAPI's route table stays at its native paths (`/health`, `/events`, ...).

## Overriding defaults

See `defaults/main.yml`. Common:

- `csc__source_dir` — path to `co-stream-control/` checkout
- `csc__api_port` — 127.0.0.1 bind for the api container
- `csc__admin_dist` / `csc__gfx_dist` — where Caddy reads the static bundles from
- `csc__log_level` — API `CSC_LOG_LEVEL`
