# gfx role

Deploys orienteering-tv-graphics Flask control app and co-stream-gfx Go SSE proxy via Docker Compose.

## Prerequisites

1. **DNS**: Create an A record for `gfx.csos.josefkolar.cz` pointing to the VM's IP
2. **Auth credentials**: Add to `inventory/csos.yml` as inline vault entries:
   ```bash
   ansible-vault encrypt_string --vault-password-file pass.env 'your-user' --name 'gfx__auth_user'
   ansible-vault encrypt_string --vault-password-file pass.env 'your-bcrypt-hash' --name 'gfx__auth_hash'
   ```
   Generate bcrypt hash: `caddy hash-password`
   Then add `gfx__auth_user` and `gfx__auth_hash` to `inventory/csos.yml` using `!vault |` inline syntax

3. **Source repos**: Ensure `orienteering-tv-graphics/` and `co-stream-gfx/` are checked out alongside `co-ansible/`

## Deploy

Must include BOTH tags — `gfx` for the role, `web_proxy` because the Caddyfile template lives in the web_proxy role:

```bash
ansible-playbook -i inventory/csos.yml playbooks/setup.yml --tags gfx,web_proxy --vault-password-file pass.env
```

## Usage

Nuxt frontend (GitHub Pages): https://thejoeejoee.github.io/co-stream-gfx/?sse=https://gfx.csos.josefkolar.cz/_sse/default

Flask control panel: https://gfx.csos.josefkolar.cz/ (basic_auth required)

## Post-deploy

Upload initial event data via the Flask `/upload` endpoint (XML file).

## Secrets

All sensitive variables (`gfx__auth_user`, `gfx__auth_hash`) are stored as inline vault-encrypted entries in `inventory/csos.yml` for secure storage and version control.
