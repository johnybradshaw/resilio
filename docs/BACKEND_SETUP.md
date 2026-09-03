# Terraform Backend Setup — Linode Object Storage

Remote state for this project lives in a Linode Object Storage bucket using
Terraform's S3-compatible backend, with credentials held in 1Password.

## Why this shape

| Concern | Decision |
|---|---|
| Public repository | **Partial backend.** `provider.tf` holds an empty `backend "s3" {}`; bucket, region and key live in `backend.tfvars`, which is gitignored. No infrastructure detail is committed. |
| Credentials | Read from 1Password into environment variables at the start of a session. Never written to a file in the repo. |
| State locking | `use_lockfile = true` (Terraform >= 1.10). Linode has no DynamoDB equivalent; S3-native locking works against Linode Object Storage. |
| State recovery | Bucket versioning is enabled, so every prior state revision is retained. |
| Bucket ownership | The state bucket is created **out of band** and is deliberately *not* a Terraform resource. A bucket managed by the state it holds would be destroyed mid-`destroy`, orphaning the state. |

## Prerequisites

- Terraform **>= 1.10** (`use_lockfile`). This repo pins `>= 1.5.0` for the
  root module, but the backend features documented here need 1.10+.
- [1Password CLI](https://developer.1password.com/docs/cli/get-started/), signed in.
- `linode-cli`, authenticated against the target account.

## One-time setup

### Step 1 — Create the bucket

Pick a region from `linode-cli object-storage clusters-list`. A region that is
*not* one of your deployment regions keeps state independent of the
infrastructure it describes.

```bash
TOKEN=$(awk -F' *= *' '/^token/{print $2; exit}' ~/.config/linode-cli)
BUCKET="terraform-state-$(openssl rand -hex 3)"   # unguessable, not committed

curl -sS -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"label\":\"${BUCKET}\",\"region\":\"fr-par\",\"acl\":\"private\",\"cors_enabled\":false}" \
  https://api.linode.com/v4/object-storage/buckets
```

`linode-cli` has no bucket-create action in current versions; the API call above
is the supported route.

### Step 2 — Create a bucket-scoped access key

Scope the key to the state bucket alone. A full-account Object Storage key in a
Terraform session is a blast-radius problem for no benefit.

```bash
curl -sS -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"label\":\"terraform-state\",
       \"regions\":[\"fr-par\"],
       \"bucket_access\":[{\"region\":\"fr-par\",
                           \"bucket_name\":\"${BUCKET}\",
                           \"permissions\":\"read_write\"}]}" \
  https://api.linode.com/v4/object-storage/keys > ~/.config/tfstate-key.json
chmod 600 ~/.config/tfstate-key.json
```

Confirm the response shows `"limited": true`. If it shows `false`, the
`bucket_access` block was rejected and you have an account-wide key — revoke it
and retry.

### Step 3 — Enable bucket versioning

Versioning is what makes a corrupted or truncated state recoverable.

```bash
export AWS_ACCESS_KEY_ID=$(jq -r .access_key ~/.config/tfstate-key.json)
export AWS_SECRET_ACCESS_KEY=$(jq -r .secret_key ~/.config/tfstate-key.json)

aws s3api put-bucket-versioning \
  --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled \
  --endpoint-url https://fr-par-1.linodeobjects.com

aws s3api get-bucket-versioning \
  --bucket "$BUCKET" \
  --endpoint-url https://fr-par-1.linodeobjects.com
```

### Step 4 — Store the credentials in 1Password

Vault `secrets.resilio`, item `terraform-state-backend`:

```bash
op item create \
  --category="API Credential" \
  --title="terraform-state-backend" \
  --vault="secrets.resilio" \
  "access_key_id[password]=$(jq -r .access_key ~/.config/tfstate-key.json)" \
  "secret_access_key[password]=$(jq -r .secret_key ~/.config/tfstate-key.json)" \
  "bucket[text]=${BUCKET}" \
  "region[text]=fr-par-1" \
  "endpoint[text]=https://fr-par-1.linodeobjects.com"
```

Then remove the local copy:

```bash
rm -P ~/.config/tfstate-key.json
```

> **Service accounts cannot create vaults or items, and cannot read
> `Private`/`Personal` vaults.** If `OP_SERVICE_ACCOUNT_TOKEN` is set in your
> shell it takes precedence over your personal session and this command will
> fail. Run it in a shell where that variable is unset.

### Step 5 — Configure and initialise

```bash
cp backend.tfvars.example backend.tfvars
# edit bucket / region / endpoint to match Steps 1-3

git check-ignore -v backend.tfvars     # must report a match

source scripts/setup-backend-credentials.sh
terraform init -backend-config=backend.tfvars
```

## Migrating existing local state

```bash
# 1. Back up, outside the repo
cp terraform.tfstate ~/tfstate-backup-$(date +%F).json

# 2. Record what you expect to migrate
terraform state list | wc -l

# 3. Migrate
source scripts/setup-backend-credentials.sh
terraform init -backend-config=backend.tfvars -migrate-state

# 4. Verify the counts match BEFORE trusting the migration
terraform state list | wc -l
aws s3 ls "s3://$BUCKET/" --recursive \
  --endpoint-url https://fr-par-1.linodeobjects.com

# 5. Only once verified
rm terraform.tfstate terraform.tfstate.backup terraform.tfstate.*.backup
```

A successful `init` exit code is **not** evidence the state migrated. Compare
resource counts between the old and new state before deleting anything.

## Daily workflow

```bash
source scripts/setup-backend-credentials.sh
terraform plan
terraform apply
```

The credentials live only in the shell environment and vanish when it closes.

## Backend arguments

Terraform 1.6 **removed** several S3 backend arguments. Configuration copied
from older guides will fail `terraform init`.

| Removed / deprecated | Current |
|---|---|
| `endpoint = "..."` | `endpoints = { s3 = "..." }` |
| `force_path_style = true` | `use_path_style = true` |
| `dynamodb_table = "..."` | `use_lockfile = true` |

Linode-specific arguments:

- `skip_credentials_validation`, `skip_metadata_api_check`,
  `skip_region_validation`, `skip_requesting_account_id` — Linode is not AWS,
  so the AWS preflight checks must be skipped.
- `skip_s3_checksum = true` — Linode's Ceph gateway rejects newer AWS checksum
  headers.

`region` is the Object Storage endpoint id (`fr-par-1`, `gb-lon-1`,
`us-east-1`, …), not the Linode compute region (`fr-par`, `eu-west`).

## State locking

`use_lockfile = true` writes a `<key>.tflock` object for the duration of an
operation and deletes it afterwards. This is verified working against Linode
Object Storage.

If an operation is killed mid-run the lock object can survive. Clear it with:

```bash
terraform force-unlock <LOCK_ID>
```

Only do this once you are certain no other operation is running.

## Troubleshooting

**`Error: Invalid backend configuration argument`** — you are using removed
argument names. See the table above.

**`403 Forbidden` / `SignatureDoesNotMatch`** — credentials not loaded, or the
key is scoped to a different bucket. Re-run
`source scripts/setup-backend-credentials.sh` and confirm both variables are
set (`[ -n "$AWS_ACCESS_KEY_ID" ] && echo set`). Never echo their values.

**`NoSuchBucket`** — `region` is set to the compute region rather than the
Object Storage endpoint id, or `endpoints.s3` points at the wrong cluster.

**`Error acquiring the state lock`** — a stale `.tflock` object. Confirm nothing
else is running, then `terraform force-unlock <LOCK_ID>`.

**1Password read fails** — the service-account token in your shell takes
precedence over your personal session, and service accounts cannot read
`Private`/`Personal` vaults. Ensure the item is in a shared vault the account
has been granted.

## Security notes

- `backend.tfvars`, `terraform.tfvars` and `*.tfstate*` are gitignored.
  Verify with `git check-ignore -v <file>` after any `.gitignore` change.
- State contains every sensitive value in the configuration in **plaintext**.
  Treat the bucket as a secret store: private ACL, bucket-scoped key, no public
  access.
- Never print credential values. Use `[ -n "$VAR" ]` or `${#VAR}` to confirm a
  variable is set.

## Additional resources

- [Terraform S3 backend](https://developer.hashicorp.com/terraform/language/backend/s3)
- [Linode Object Storage](https://techdocs.akamai.com/cloud-computing/docs/object-storage)
- [1Password CLI](https://developer.1password.com/docs/cli/)
