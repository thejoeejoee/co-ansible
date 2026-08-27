# auth

Centralized SSO gateway for CSOS: [Casdoor](https://casdoor.org) as the OIDC provider, [oauth2-proxy](https://oauth2-proxy.github.io/oauth2-proxy/) as the Caddy `forward_auth` gateway. Replaces the Zitadel-based design from PR #7 — see [issue #15](https://github.com/thejoeejoee/co-ansible/issues/15).

## Why Casdoor

Google auto-registration must default to **zero access**, with an admin manually promoting the user afterward — plus manual (non-Google) accounts. Casdoor is a single Go binary (SQLite-capable, no Postgres) with a web admin console for users/orgs/groups/providers, satisfying that requirement without a bespoke bootstrap action script.

## Sign-in is Google/GitHub only

Password-based account creation and login are disabled on every application — `auth__providers` in `defaults/main.yml` is the only way in. New users still get created automatically on first OAuth sign-in (`enableSignUp: true` + each provider's `canSignUp: true`); there's just no password form to create one manually.

This is enforced server-side, not just hidden in the UI — see the comment above the "Ensure OIDC applications" task in `tasks/reconcile.yml` for a real Casdoor bug this works around (`Application.IsPasswordEnabled()` ignores a signin method's "Hide password" rule; the fix is sending an explicitly empty `signinMethods` list instead).

To add a provider (e.g. GitHub), add its OAuth app credentials to inventory and add an entry to `auth__providers` — `tasks/reconcile.yml` picks it up on the next deploy, no bootstrap script changes needed.

## How default-deny works

New users — whether they sign up via Google or GitHub — start in the `{{ auth__org }}` organization with **zero group memberships**. Casdoor's default JWT format already emits a `groups` claim (a plain array of `org/group` strings) with no custom-claim configuration needed; oauth2-proxy reads it via `oidc_groups_claim = "groups"` and forwards it as the `X-Auth-Request-Groups` header, which Caddy's ACLs match against.

An admin assigns a user to `{{ auth__org }}/admin`, `{{ auth__org }}/production`, `{{ auth__org }}/demo`, or `{{ auth__org }}/gfx` via the Casdoor web UI (**Groups** page, or editing the user directly) — that's the entire "approve a user" flow. There's no custom action/webhook to maintain.

This was verified against a live Casdoor instance (not just documentation), including the exact JWT/`/api/userinfo` payload shape — see the PR history for the token dump.

## Infrastructure as code

`defaults/main.yml` is the single source of truth for what exists in Casdoor: `auth__org`, `auth__groups`, `auth__providers`, `auth__applications`, `auth__theme`. `tasks/reconcile.yml` runs on **every** deploy (not just the first) and upserts each one via `tasks/_ensure_object.yml` — a generic "GET by id, create if missing, update if it already exists and the call site opts into updates" helper. Add a group, rename a display name, add a provider, tweak the theme color: edit the data, redeploy, Casdoor converges.

Two deliberate exceptions to "update on every run":
- The JWT signing cert (`cert-{{ auth__org }}`) is create-once-only — regenerating it would invalidate every issued token.
- Application updates are scoped to specific `columns` (via Casdoor's `?columns=` query param) rather than a full-object replace, because `Application` also carries server-generated `clientId`/`clientSecret` that our declarative body doesn't know. A full-column update would blank them out and break oauth2-proxy/Grafana's already-configured OIDC clients.

## AI Assistant widget disabled

Casdoor ships a floating "AI Assistant" button that opens an iframe to an external `casbin.org`-hosted service. `auth__ai_assistant_url` defaults to `""`, which is Casdoor's own documented way to hide it (`docker-compose.yml.j2` passes it through as the `aiAssistantUrl` app.conf key). There's no other AI/agent-specific toggle in Casdoor itself — the "Agent-first" framing in its own docs refers to Casdoor optionally acting as an OIDC provider *for* AI agents/MCP clients, which this deployment doesn't use.

## Branding

`auth__theme` (color_primary, border_radius) is applied to the `{{ auth__org }}` organization's `themeData` with `isEnabled: true`. Casdoor resolves theme as application-level override → organization-level → global default (`web/src/Setting.js:getThemeData`), so setting it once at the organization level covers every application's login page uniformly.

## Does Casdoor send email?

Yes — via a `Provider` of category `Email` (SMTP), used for signup email verification, forgot-password codes, and invitation/notification emails. **None is configured here.** Since password-based signup is disabled, the email-verification and forgot-password flows aren't reachable anyway; Google/GitHub already verify the user's email themselves. If a future feature needs Casdoor-sent email (e.g. admin notifications when a new zero-group user signs up), add an `auth__providers` entry with `category: Email` and real SMTP credentials — `tasks/reconcile.yml`'s provider loop only assumes `category: OAuth` today and would need a small adjustment to branch on provider category.

## Prerequisites

1. **DNS**: `auth.{{ web_proxy__domain }}` must resolve to the VM (the browser-facing OAuth login redirect goes through this public hostname).
2. **Google OAuth**: create an OAuth client in Google Cloud Console with redirect URI `https://auth.{{ web_proxy__domain }}/callback`, and set `auth__google_client_id` / `auth__google_client_secret` in inventory.
3. **GitHub OAuth**: create an OAuth App in GitHub Developer Settings with the same callback pattern, and set `auth__github_client_id` / `auth__github_client_secret` in inventory.
4. **Secrets** (vault for prod, inline for `orb.yaml`): `auth__admin_pass`, `auth__oauth2_proxy_cookie_secret`, `auth__google_client_id`, `auth__google_client_secret`, `auth__github_client_id`, `auth__github_client_secret`.

## Reconcile flow (`tasks/reconcile.yml`, every deploy)

1. Log in as `built-in/admin` — tries `auth__admin_pass` first, falls back to Casdoor's well-known default (`123`, first boot only) and rotates it to `auth__admin_pass` via `/api/set-password` if that's what worked.
2. Upsert the `{{ auth__org }}` organization (incl. theme), the JWT signing cert (create-only), the groups, and the identity providers.
3. Upsert the `oauth2-proxy` and `grafana` OIDC applications with every configured provider attached (`signupGroup` left empty — see default-deny above) and password signin genuinely disabled.
4. Provision `testadmin`/`testdemo` accounts when `auth__provision_test_users` is set (local dev only), pre-assigned to their group. Since password login is disabled on the real applications, these accounts can't interactively sign in anymore — they only verify the bootstrap/group plumbing itself. End-to-end login testing needs real Google/GitHub OAuth app credentials, even in local dev.
5. Persist the generated client credentials as Ansible local facts and re-render `oauth2-proxy.cfg` with the real values.

All calls authenticate with a Casdoor admin **session cookie** (`/api/login` → `Set-Cookie` → forwarded on subsequent calls), not the built-in application's client credentials — those are publicly readable via the unauthenticated `GET /api/get-application?id=admin/app-built-in` endpoint by Casdoor's own design, so this role never depends on them.

## Scope note

This role only covers the auth backend (Casdoor + oauth2-proxy) and the ACL wiring for routes that already exist on `main` (HLS, WebRTC, Prometheus, Grafana, the legacy `gfx` control panel). It does not port PR #7's `/credentials` and `/demo` informational pages — those were unrelated content features bundled into that PR, not part of the auth swap.

## Deploy

```bash
ansible-playbook -i inventory/orb.yaml playbooks/setup.yml --tags auth,web_proxy,telemetry
```
