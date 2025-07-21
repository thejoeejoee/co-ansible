# ČSOS Stream Proxy Ansible

Ansible playbook to deploy stream proxy server for ČSOS livestreaming purposes.

Uses mediamtx under the hood.

Slot == unique identifier for single stream (in terminology of mediamtx it's called `path`)

## Streaming

Slots are configured in `playbooks/templates/mediamtx.yml` and are used as follows:

### Upstreams

from capture devices to the proxy server:

```
rtmp://csos.josefkolar.cz:1935/SLOT?user=USER&pass=PASS
```

### Downstreams

from the proxy server to the switcher/consumer:

```
srt://csos.josefkolar.cz:8890?streamid=read:SLOT:USER:PASS
```

### Debugging

```shell
ffplay "rtmp://csos.josefkolar.cz:1935/SLOT?user=USER&pass=PASS"
```
```
http://csos.josefkolar.cz:8888/SLOT/
```

## Deployment

Tested on Ubuntu 24.04, deployed by Ansible -- see `playbooks/setup.yaml` and `playbooks/templates/` for details.

```shell
ansible-playbook -i inventory/csos.yaml playbooks/setup.yaml \
  -e @secrets.enc --vault-password-file .pass.env
```

## Secrets

Defaults are stored in secrets.enc, which is encrypted with Ansible Vault.

Needed secrets:
```
csos_stream_proxy__write_pass
csos_stream_proxy__read_pass
```