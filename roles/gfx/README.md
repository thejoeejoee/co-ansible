# gfx role

Deploys orienteering-tv-graphics Flask control app and co-stream-gfx Go SSE proxy via Docker Compose.

## Prerequisites

1. **DNS**: Create an A record for `gfx.csos.josefkolar.cz` pointing to the VM's IP
2. **SSO**: users must be in the `admin` or `gfx` Casdoor group to reach the control panel — an admin assigns this via the Casdoor Groups page (see `roles/auth/README.md`); no per-role credentials to manage anymore
3. **Source repos**: Ensure `orienteering-tv-graphics/` and `co-stream-gfx/` are checked out alongside `co-ansible/`

## Deploy

Must include BOTH tags — `gfx` for the role, `web_proxy` because the Caddyfile template lives in the web_proxy role:

```bash
ansible-playbook -i inventory/csos.yml playbooks/setup.yml --tags gfx,web_proxy --vault-password-file pass.env
```

## Usage

Nuxt frontend (GitHub Pages): https://thejoeejoee.github.io/co-stream-gfx/?sse=https://gfx.csos.josefkolar.cz/_sse/default

Flask control panel: https://gfx.csos.josefkolar.cz/ (SSO required, `admin` or `gfx` group)

## Post-deploy

Upload initial event data via the Flask `/upload` endpoint (XML file).
