"""Make a decK dump safe to commit: read it on stdin, write the reviewed copy on stdout.

    deck gateway dump --kong-addr http://localhost:8001 --skip-consumers -o - \
      | python3 kong-config/redact_export.py > kong-config/exports/kong.yaml

Drops consumers and every credential collection (in case --skip-consumers was forgotten), keeps Certificates and
SNIs but replaces their key and certificate text (cert-sync owns them), and replaces any plugin or vault field whose
name suggests a secret. The result is for review and `git diff` only: it cannot restore credentials, and
`deck gateway sync` with it would delete every Consumer. Full backups are encrypted pg_dumps (05-backup-restore.md).
"""
import sys

import yaml

DROP = {'consumers', 'consumer_groups', 'acls', 'basicauth_credentials', 'keyauth_credentials', 'hmacauth_credentials',
        'jwt_secrets', 'oauth2_credentials', 'mtls_auth_credentials', 'vaults'}
SECRET_WORDS = ('password', 'secret', 'token', 'private', 'credential', 'api_key', 'apikey', 'auth_header', 'key')
REDACTED = '<REDACTED>'


def secretish(name):
    name = str(name).lower()
    return any(word in name for word in SECRET_WORDS) and name not in ('key_names', 'key_in_header', 'key_in_query',
                                                                       'key_in_body', 'hide_credentials', 'keepalive')


def scrub(value):
    if isinstance(value, dict):
        return {k: (REDACTED if secretish(k) and isinstance(v, (str, int)) and v not in (None, '') else scrub(v))
                for k, v in value.items()}
    if isinstance(value, list):
        return [scrub(v) for v in value]
    return value


def main():
    state = yaml.safe_load(sys.stdin) or {}
    for name in DROP:
        state.pop(name, None)
    for cert in state.get('certificates', []):
        for field in ('cert', 'key', 'cert_alt', 'key_alt'):
            if cert.get(field):
                cert[field] = '<REDACTED: managed by cert-sync>'
    for collection in ('plugins', 'services'):
        state[collection] = scrub(state.get(collection, [])) if collection in state else None
        if state[collection] is None:
            state.pop(collection)
    yaml.safe_dump(state, sys.stdout, sort_keys=False, default_flow_style=False, width=120)


if __name__ == '__main__':
    main()
