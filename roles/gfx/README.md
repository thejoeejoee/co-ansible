# gfx role

Deploys orienteering-tv-graphics Flask control app and co-stream-gfx Go SSE proxy via Docker Compose.

## Prerequisites

1. **DNS**: Create an A record for `gfx.csos.josefkolar.cz` pointing to the VM's IP
2. **SSO**: User must be a member of the `gfx` group in Zitadel (managed by the `auth` role)
3. **Source repos**: Ensure `orienteering-tv-graphics/` and `co-stream-gfx/` are checked out alongside `co-ansible/`

## Deploy

Must include BOTH tags — `gfx` for the role, `web_proxy` because the Caddyfile template lives in the web_proxy role:

```bash
ansible-playbook -i inventory/csos.yml playbooks/setup.yml --tags gfx,web_proxy --vault-password-file pass.env
```

## Usage

Nuxt frontend (GitHub Pages): https://thejoeejoee.github.io/co-stream-gfx/?sse=https://gfx.csos.josefkolar.cz/_sse/default

Flask control panel: https://gfx.csos.josefkolar.cz/ (SSO required, gfx group)

## Post-deploy

Upload initial event data via the Flask `/upload` endpoint (XML file).


