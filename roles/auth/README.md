# auth

Centralized SSO gateway for CSOS: [Casdoor](https://casdoor.org) as the OIDC provider, [oauth2-proxy](https://oauth2-proxy.github.io/oauth2-proxy/) as the Caddy `forward_auth` gateway. Replaces the Zitadel-based design from PR #7 — see [issue #15](https://github.com/thejoeejoee/co-ansible/issues/15).

## Why Casdoor

Google auto-registration must default to **zero access**, with an admin manually promoting the user afterward — plus manual (non-Google) accounts. Casdoor is a single Go binary (SQLite-capable, no Postgres) with a web admin console for users/orgs/groups/providers, satisfying that requirement without a bespoke bootstrap action script.

## How default-deny works

New users — whether they sign up via Google or are created manually — start in the `{{ auth__org }}` organization with **zero group memberships**. Casdoor's default JWT format already emits a `groups` claim (a plain array of `org/group` strings) with no custom-claim configuration needed; oauth2-proxy reads it via `oidc_groups_claim = "groups"` and forwards it as the `X-Auth-Request-Groups` header, which Caddy's ACLs match against.

An admin assigns a user to `{{ auth__org }}/admin`, `{{ auth__org }}/production`, `{{ auth__org }}/demo`, or `{{ auth__org }}/gfx` via the Casdoor web UI (**Groups** page, or editing the user directly) — that's the entire "approve a user" flow. There's no custom action/webhook to maintain.

This was verified against a live Casdoor instance (not just documentation) before writing `tasks/bootstrap.yml` — see the PR description for the token payload.

## Prerequisites

1. **DNS**: `auth.{{ web_proxy__domain }}` must resolve to the VM (the `oauth2-proxy` container reaches Casdoor via that public hostname, hairpinning back through Caddy, same as the Zitadel design in PR #7).
2. **Google OAuth**: create an OAuth client in Google Cloud Console with redirect URI `https://auth.{{ web_proxy__domain }}/callback` (or `https://{{ web_proxy__domain }}/oauth2/callback` — check the exact one Casdoor renders once the `google` provider exists), and set `auth__google_client_id` / `auth__google_client_secret` in inventory.
3. **Secrets** (vault for prod, inline for `orb.yaml`): `auth__admin_pass`, `auth__oauth2_proxy_cookie_secret`, `auth__google_client_id`, `auth__google_client_secret`.

## Bootstrap flow (`tasks/bootstrap.yml`, first run only)

Runs once, gated on `ansible_local.auth_credentials` being undefined (persisted to `/etc/ansible/facts.d/auth_credentials.fact` at the end):

1. Log in as `built-in/admin` (Casdoor's well-known default password is `123` on first boot) and immediately rotate it to `auth__admin_pass` via `/api/set-password`.
2. Create the `{{ auth__org }}` organization, a JWT signing cert, the four groups, and a Google identity provider (`signupGroup` left empty — see above).
3. Create the `oauth2-proxy` and `grafana` OIDC applications, both with the Google provider attached.
4. Provision `testadmin`/`testdemo` accounts when `auth__provision_test_users` is set (local dev only), pre-assigned to their group.
5. Persist the generated client credentials as Ansible local facts and re-render `oauth2-proxy.cfg` with the real values.

All bootstrap API calls authenticate with a Casdoor admin **session cookie** (`/api/login` → `Set-Cookie` → forwarded on subsequent calls), not the built-in application's client credentials — those are publicly readable via the unauthenticated `GET /api/get-application?id=admin/app-built-in` endpoint by Casdoor's own design, so this role never depends on them.

## Scope note

This role only covers the auth backend (Casdoor + oauth2-proxy) and the ACL wiring for routes that already exist on `main` (HLS, WebRTC, Prometheus, Grafana, the legacy `gfx` control panel). It does not port PR #7's `/credentials` and `/demo` informational pages — those were unrelated content features bundled into that PR, not part of the auth swap.

## Deploy

```bash
ansible-playbook -i inventory/orb.yaml playbooks/setup.yml --tags auth,web_proxy,telemetry
```
