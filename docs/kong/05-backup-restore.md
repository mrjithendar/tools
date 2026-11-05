# 05 — Backup, restore, upgrades

> **No high availability.** One PostgreSQL pod on one minikube node container, on one host. If that host's disk,
> the `mk4-m03` container or its hostPath directory is lost, Kong's configuration is gone until you restore a
> backup, and the gateway (every site) is down meanwhile. Kong keeps serving from its in-memory cache for a while
> if only PostgreSQL stops, but a Kong restart without the database fails.

## What the Kong database holds

Every Service, Route, Upstream, Plugin and Consumer; basic-auth passwords (salted hashes); key-auth keys
**as given, in plain text**; the two Certificates and **their private keys** (from cert-sync); plugin settings,
which may include tokens. A full backup is therefore a secret. Two kinds of backup, for two purposes:

| Backup | Contains secrets | Where it lives | Purpose |
|---|---|---|---|
| Encrypted `pg_dump` (custom format) | yes | outside every repository and outside this Google Drive folder, encrypted | restore |
| Reviewed decK export (`kong-config/exports/kong.yaml`) | no (redacted) | Git (tools) | review and diff of UI changes |

## 1. Full backup: pg_dump

Prerequisite, once: an encryption key pair outside the repositories, e.g. with [age](https://age-encryption.org)
(`brew install age`):

```bash
mkdir -p ~/.config/kong-backup && chmod 700 ~/.config/kong-backup
age-keygen -o ~/.config/kong-backup/key.txt      # keep a copy in your password manager; losing it loses the backups
age-keygen -y ~/.config/kong-backup/key.txt      # prints the public recipient: age1… (<AGE-RECIPIENT>)
```

Backup (the dump never touches the disk unencrypted; the superuser uses the pod's local socket, so no password
crosses the command line):

```bash
mkdir -p ~/Backups/kong && chmod 700 ~/Backups/kong        # NOT under "My Drive/Work": that folder syncs to Google Drive
kubectl --context mk4 -n kong exec kong-postgres-0 -c postgres -- \
  pg_dump -U postgres -d kong --format=custom --no-owner \
  | age -r <AGE-RECIPIENT> > ~/Backups/kong/kong-$(date +%Y%m%d-%H%M).pgdump.age
ls -l ~/Backups/kong | tail -3                               # non-zero size
age -d -i ~/.config/kong-backup/key.txt "$(ls -t ~/Backups/kong/kong-*.pgdump.age | head -1)" | head -c 5; echo   # PGDMP
```

When: before the cutover, before every upgrade, after each Kong Manager change session, and weekly. Copy the
encrypted files off the host and Mac (external disk or a storage service). The `.age` files are safe to store
anywhere because only the key decrypts them.

## 2. Reviewed export for Git

After a Kong Manager session, record what changed (tunnel open, 03):

```bash
cd tools
deck gateway dump --kong-addr http://localhost:8001 --skip-consumers -o - \
  | python3 kong-config/redact_export.py > kong-config/exports/kong.yaml
git diff kong-config/exports/kong.yaml       # exactly what changed in Kong since the last reviewed export
```

- Always the same file, so `git diff` against the last committed export is the review of UI changes. The first
  export after the seed import should differ from the seed only by Kong's defaults and ids.
- No `select_tags` here: the export covers everything, including entities created in Kong Manager.
- `redact_export.py` drops consumers and credential collections, replaces certificate and key text, and replaces
  plugin fields named like secrets. Read the diff before committing anyway.
- `deck gateway diff kong-config/exports/kong.yaml` (without sync) shows what Kong would change to match the export,
  i.e. what was changed in the UI since the export, read in reverse.
- **Never `deck gateway sync` this file:** it lacks Consumers and real certificates, so a sync would delete them.

Credential-bearing entities (Consumers, basic-auth, key-auth, ACL memberships) are created by hand (04) and are
backed up only inside the encrypted pg_dump. Optionally, a full decK dump including them can be kept the same way:
`deck gateway dump --kong-addr http://localhost:8001 -o - | age -r <AGE-RECIPIENT> > ~/Backups/kong/kong-deck-$(date +%Y%m%d).yaml.age`.

## 3. Restore (tested order)

Order: stop writers → recreate the database → restore → check schema → start Kong → verify. "Tested" means
drilled with step 3.6 below; it has not been run on mk4 yet (README, Unverified).

```bash
K="kubectl --context mk4 -n kong"
DUMP=~/Backups/kong/kong-YYYYMMDD-HHMM.pgdump.age

# 3.1 Stop Kong (traffic stops: every site is down until 3.5)
$K scale deploy/kong --replicas=0 && $K wait --for=delete pod -l app.kubernetes.io/name=kong --timeout=120s

# 3.2 Recreate the database, owned by the kong role
$K exec kong-postgres-0 -c postgres -- psql -U postgres -v ON_ERROR_STOP=1 \
  -c 'DROP DATABASE IF EXISTS kong WITH (FORCE)' -c 'CREATE DATABASE kong OWNER kong'

# 3.3 Restore as the kong role
age -d -i ~/.config/kong-backup/key.txt "$DUMP" \
  | $K exec -i kong-postgres-0 -c postgres -- pg_restore -U postgres -d kong --no-owner --role=kong --exit-on-error

# 3.4 Schema must match the running image (expect exit 0; 5 means the dump is older: run the upgrade's `up` Job)
$K run kong-migrations-check --rm -i --restart=Never --image=kong:3.9.4 \
  --labels=app.kubernetes.io/name=kong-migrations \
  --overrides='{"spec":{"containers":[{"name":"c","image":"kong:3.9.4","command":["kong","migrations","list"],"envFrom":[{"configMapRef":{"name":"kong-config"}}],"env":[{"name":"KONG_PG_PASSWORD","valueFrom":{"secretKeyRef":{"name":"kong-postgres","key":"kong-password"}}},{"name":"KONG_PREFIX","value":"/tmp/kong"}]}]}}'

# 3.5 Start Kong; its init container waits for a usable schema
$K scale deploy/kong --replicas=1 && $K rollout status deploy/kong --timeout=300s
```

3.6 Verify, then drill: `curl` checks from 06 step 8, and the entity counts below match those recorded at backup
time. To drill without touching the live database, restore into a scratch database and compare:

```bash
$K exec kong-postgres-0 -c postgres -- psql -U postgres -c 'CREATE DATABASE kong_restore_test OWNER kong'
age -d -i ~/.config/kong-backup/key.txt "$DUMP" | $K exec -i kong-postgres-0 -c postgres -- pg_restore -U postgres -d kong_restore_test --no-owner --role=kong --exit-on-error
for db in kong kong_restore_test; do $K exec kong-postgres-0 -c postgres -- psql -U postgres -d $db -Atc \
  "select '$db', (select count(*) from services), (select count(*) from routes), (select count(*) from plugins), (select count(*) from consumers)"; done
$K exec kong-postgres-0 -c postgres -- psql -U postgres -c 'DROP DATABASE kong_restore_test'
```

### Restore with decK (only when no pg_dump exists)

The single permitted use of `deck gateway sync` against the live gateway: restoring from the encrypted full decK
dump into an empty or broken database. Decrypt to a temporary file, `deck gateway validate`, `deck gateway diff`,
read the diff, then `deck gateway sync`, and delete the plaintext file. cert-sync re-uploads the two
certificates within 5 minutes.

### Lost PostgreSQL volume

If `kong-postgres-0` starts with an empty directory (node data lost, or the pod ran on another node), the image
initialises a new cluster and its init script creates an empty `kong` database and role from the Secret. Kong's
init container then waits (exit 3, needs bootstrap). Do not run a bootstrap by hand unless you mean to start again
from the seed; restore instead with 3.2–3.5.

## 4. Password rotation

```bash
# kong role (Kong's database login); the Secret update and the role change must match.
# Use a generated password without quotes (create-secrets.sh style): it is embedded in SQL here.
read -r -s -p 'new kong password: ' PW; echo
printf "ALTER ROLE kong PASSWORD '%s';" "$PW" | kubectl --context mk4 -n kong exec -i kong-postgres-0 -c postgres -- psql -U postgres -v ON_ERROR_STOP=1 -q
kubectl --context mk4 -n kong get secret kong-postgres -o json \
  | PW="$PW" python3 -c 'import json,sys,base64,os; s=json.load(sys.stdin); s["data"]["kong-password"]=base64.b64encode(os.environ["PW"].encode()).decode(); print(json.dumps(s))' \
  | kubectl --context mk4 apply -f - >/dev/null
unset PW
kubectl --context mk4 -n kong rollout restart deploy/kong
```

## 5. Upgrades (e.g. 3.9.4 → 3.9.5)

Kong's two-step migrations: `up` adds the new schema while old nodes keep working, `finish` removes what only old
nodes needed. With one node the window is short, but the order still matters.

1. Read the release's CHANGELOG for breaking changes and new migrations. Confirm the image is OSS
   (`kong:3.9.x` Docker Official Image) and supports arm64.
2. Full backup (section 1).
3. `sed 's/NEW_VERSION/3.9.5/g' deploy/minikube/kong/upgrade/migrations-up-job.yaml | kubectl --context mk4 apply -f -`
   and `kubectl --context mk4 -n kong wait --for=condition=complete job/kong-migrations-up-3.9.5 --timeout=600s`.
   Kong's migration mutex stops a second run; `up` exits when another node holds it.
4. Change `kong:3.9.4` to `kong:3.9.5` in `templates/kong-deployment.yaml` (and the init container), then
   `terraform -chdir=minikube-infrastructure apply -var-file=vars/mk4.tfvars` (or push; CI applies). The init container accepts exit 4 (`finish` pending).
5. Verify (06 step 8).
6. `sed 's/NEW_VERSION/3.9.5/g' deploy/minikube/kong/upgrade/migrations-finish-job.yaml | kubectl --context mk4 apply -f -`
   and wait for completion. After `finish`, the old version cannot run against this database: rollback from here
   is a restore.
7. Leave the completed bootstrap Job `kong-migrations-bootstrap-3-9-4` alone; it records the first install and does
   nothing.
