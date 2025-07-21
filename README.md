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

### Secrets

Defaults are stored in secrets.enc, which is encrypted with Ansible Vault.

Needed secrets:
```
csos_stream_proxy__write_pass
csos_stream_proxy__read_pass
```

### Logs

Nominal run:

```
PLAY [Setup CSOS stream proxy]

TASK [Gathering Facts]
ok: [csos.josefkolar.cz]

TASK [Apt update]
changed: [csos.josefkolar.cz]

TASK [Download mediamtx]
ok: [csos.josefkolar.cz]

TASK [Install mediamtx]
ok: [csos.josefkolar.cz]

TASK [UFW allow RTMP]
ok: [csos.josefkolar.cz]

TASK [UFW allow HLS]
ok: [csos.josefkolar.cz]

TASK [UFW allow SRT]
ok: [csos.josefkolar.cz]

TASK [Prepare mediamtx config directory]
ok: [csos.josefkolar.cz]

TASK [Prepare config]
ok: [csos.josefkolar.cz]

TASK [Mediamtx systemd service is prepared]
ok: [csos.josefkolar.cz]

TASK [Mediamtx systemd service is reloaded]
ok: [csos.josefkolar.cz]

TASK [Mediamtx systemd service is enabled]
ok: [csos.josefkolar.cz]

TASK [Mediamtx systemd service is started]
ok: [csos.josefkolar.cz]

PLAY RECAP
csos.josefkolar.cz         : ok=13   changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```