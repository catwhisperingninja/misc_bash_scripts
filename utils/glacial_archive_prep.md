# Automation & operational notes — added 2026-08-28

This pipeline is now driven by **`glacial-archive-driver.sh`** (same folder): it runs the
per-folder `tar` -> `sha256` -> upload -> verify -> Archive-tier flow across the whole
source tree, resumably (a ledger skips folders already `verified`), isolates per-folder
failures, posts progress to Slack, and never touches the source. The spec below is the
source of truth; the script just executes it.

**Direct-to-container, no VM.** Upload straight to the Blob container via `az` / `rclone`
-- no Azure VM in the path, so no compute bill. The VNet + NSG are network hygiene only;
the gate on the Mac-at-home upload is the **storage-account firewall IP allowlist** (see
Netsec checklist), not the NSG. Home public IP confirmed stable (~4 yrs) -> no allowlist churn.

**Keyless auth.** `az login` + `Storage Blob Data Contributor` RBAC + `--auth-mode login`.
rclone rides the same session with `env_auth = true`. No account keys, no SAS, no secret manager.

**Upload tool:** `rclone` by default (best resume across overnight drops); `az` as fallback.

**Staging space.** The driver stages one folder's tar at a time before upload, so it needs
scratch >= your largest single folder. Prep: wipe the dead 4 TB Time Machine drive with
**`wipe-disk.sh`** (same folder) and set the driver's `WORKDIR` to it. If scratch is tight,
the plain-tar (media) path can stream instead --
`tar -c FOLDER | tee >(shasum -a256 >f.sha256) | rclone rcat azure:archive/glacial/f.tar` --
trading weaker mid-file resume for ~no scratch.

**Companion scripts in this folder**
- `glacial-archive-driver.sh` -- batched, resumable, self-minding archive runner.
- `wipe-disk.sh` -- guard-railed macOS disk erase (full zero-fill or quick header wipe +
  repartition); refuses the boot disk, requires a typed `ERASE`. Reclaims the old Time
  Machine drive as staging.

---

tar's the right call — better than zip here: it preserves Mac metadata, permissions, and symlinks, has no practical size limit, and streams cleanly. Zip is weaker on POSIX/Mac attributes. So no worries on the format itself.
But the honest reframe: what protects you from corruption isn't the archive format — it's the pipeline around it. tar has no whole-file integrity check baked in, so wrap it in a few layers and "no worry" becomes real:

# per-dir tars

1. Per-folder tars, not one monster. tar each big folder separately. If something ever corrupts, it's one folder to redo, not the whole night — and you verify/re-upload pieces independently.
2. Checksum everything.

# already-compressed media (b-roll, video, images) → plain tar, don't waste CPU compressing

tar -cf media.tar "Media Folder"
shasum -a 256 media.tar > media.tar.sha256

# compressible stuff (text/code/uncompressed) → zstd: multithreaded, far faster than gzip on 100s of GB
tar -c "Folder" | zstd -T0 > folder.tar.zst      # bump to -T0 -12 if you want smaller and have the CPU hours
shasum -a 256 folder.tar.zst > folder.tar.zst.sha256
Keep those .sha256 files — they're how future-you proves a restore came back bit-identical.
3. Upload with the AWS CLI, not a naive stream. aws s3 cp does multipart upload automatically for big files — chunks them, validates each part's checksum, retries on drops. That's exactly "upload big chunks without corrupting them," handled:
aws s3 cp folder.tar.zst s3://your-bucket/archive/ --storage-class DEEP_ARCHIVE
(If you want bulletproof resume across an overnight connection drop, rclone to S3 is even better — it's chunked, checksummed, and resumable across restarts.)
4. Verify before you delete the source. Test the archive locally first (zstd -t folder.tar.zst, or tar -tf to list it), confirm the checksum, upload, and only then let go of the original. The rule from before still rules: source stays until the cloud copy is proven.
Two notes: use the built-in macOS tar (bsdtar) — it keeps Mac xattrs/resource forks that GNU tar can silently drop. And given your threat model, if any of this is sensitive, encrypt the tar client-side before upload (age or gpg) — one extra step, and it's your data, not Amazon's.

---

# Azure Blob (glacial / Archive tier) — same pipeline, different upload leg

Target: ~14TB media perma-backup. StorageV2 + LRS + Cool default + Archive after verify.
No HNS / SFTP / NFSv3 on this account (one-way-ish door; not needed for tar uploads).
Auth: `az login` + RBAC — avoid storage account keys / connection strings.

## Auth (no keys)

```bash
az login
az account list -o table
az account set --subscription "YOUR_SUB_NAME_OR_ID"
```

Tenant Owner is control-plane; blob upload still needs **data-plane** RBAC:

```bash
az role assignment create \
  --role "Storage Blob Data Contributor" \
  --assignee "$(az ad signed-in-user show --query id -o tsv)" \
  --scope "$(az storage account show -g "$RG" -n "$ACCT" --query id -o tsv)"
```

Use `--auth-mode login` on all blob commands. Skip account keys unless something forces them.
Managed identity: optional later (helps Azure-side runners/VMs, not your Mac). Local unattended later = service principal + same RBAC, still no account keys.

## Variables

```bash
RG=rg-glacial-media
ACCT=yourstorageacct01          # 3–24 lowercase alphanumeric, globally unique
LOC=westus2                     # Azure name for US West 2
CONTAINER=archive
VNET=vnet-glacial
SUBNET=default
NSG=nsg-glacial-default
# Set at run time only — do NOT commit a real public IP to this repo
MY_IP="YOUR_PUBLIC_IPV4"            # e.g. export MY_IP=$(curl -4 -s ifconfig.me) in the shell, not in git
# standard private 10.x space (not a public IP)
VNET_CIDR=10.0.0.0/16
SUBNET_CIDR=10.0.0.0/24
```

## Resource group + storage account (create-time choices)

```bash
az group create -n "$RG" -l "$LOC"

az storage account create \
  -g "$RG" \
  -n "$ACCT" \
  -l "$LOC" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --access-tier Cool \
  --allow-blob-public-access false \
  --min-tls-version TLS1_2 \
  --https-only true \
  --enable-hierarchical-namespace false
```

Portal gotchas: Standard (not Premium block blob — no Archive tier), LRS, Data Lake/HNS **No**, SFTP **No**.
HNS / SFTP / NFS can wait forever on this vault. MI / SMB / Azure Files can be added later.

## Same-region VNet + NSG (subnet hygiene)

NSG protects **NICs/subnets** (VMs, private endpoints' effective path, etc.).
Storage is **not** "inside" the subnet unless you add a **private endpoint**. For Mac-at-home uploads, the control that matters most is the **storage account firewall** (allow your public IP). VNet+NSG is still right as the network home for anything you colocate later.

```bash
# VNet + subnet
az network vnet create \
  -g "$RG" -n "$VNET" -l "$LOC" \
  --address-prefix "$VNET_CIDR" \
  --subnet-name "$SUBNET" \
  --subnet-prefix "$SUBNET_CIDR"

# NSG: default deny inbound; allow mgmt/web only from YOUR public IP
az network nsg create -g "$RG" -n "$NSG" -l "$LOC"

# higher priority number = lower precedence; put allows first (100–130), deny-all last
for pair in "100:22:SSH" "110:3389:RDP" "120:443:HTTPS" "130:80:HTTP"; do
  prio=${pair%%:*}; rest=${pair#*:}; port=${rest%%:*}; name=${rest#*:}
  az network nsg rule create \
    -g "$RG" --nsg-name "$NSG" -n "Allow-${name}-From-Home" \
    --priority "$prio" --direction Inbound --access Allow --protocol Tcp \
    --source-address-prefixes "$MY_IP" --source-port-ranges '*' \
    --destination-address-prefixes '*' --destination-port-ranges "$port"
done

az network nsg rule create \
  -g "$RG" --nsg-name "$NSG" -n DenyAllInbound \
  --priority 4096 --direction Inbound --access Deny --protocol '*' \
  --source-address-prefixes '*' --source-port-ranges '*' \
  --destination-address-prefixes '*' --destination-port-ranges '*'

# associate NSG with subnet
az network vnet subnet update \
  -g "$RG" --vnet-name "$VNET" -n "$SUBNET" \
  --network-security-group "$NSG"
```

Outbound: leave default allow unless you have a reason to lock it (breaks updates/package pulls on VMs).
Azure's built-in `AllowVnetInBound` / `AllowAzureLoadBalancerInBound` baselines still apply alongside your rules — fine.

Optional later (stronger, more moving parts): **private endpoint** for blob on this subnet + DNS. Not required for IP-allowlisted public endpoint.

## Storage network: public access locked to your IP (+ VNet if you want)

"Public blob access disallowed" (`--allow-blob-public-access false`) = no anonymous $web/container public read.
Separately, **storage firewall** restricts who can reach the data plane at all:

```bash
# deny by default; allow your home public IP
az storage account update \
  -g "$RG" -n "$ACCT" \
  --default-action Deny \
  --public-network-access Enabled

az storage account network-rule add \
  -g "$RG" -n "$ACCT" \
  --ip-address "$MY_IP"

# optional: allow the VNet subnet (needs Microsoft.Storage service endpoint on subnet first)
az network vnet subnet update \
  -g "$RG" --vnet-name "$VNET" -n "$SUBNET" \
  --service-endpoints Microsoft.Storage

az storage account network-rule add \
  -g "$RG" -n "$ACCT" \
  --vnet-name "$VNET" \
  --subnet "$SUBNET"
```

Notes:
- Home IP changes → re-run `network-rule add` (and remove stale IPs).
- `az` from your Mac hits storage via the **IP allowlist**, not via the VNet, unless you VPN/bastion into the VNet.
- Portal "exceptions: Allow trusted Azure services" — enable if backup/monitoring tooling needs it; otherwise leave off.
- Do **not** set `--public-network-access Disabled` unless private endpoint + DNS is already working — you'll lock yourself out from home.

## Container

```bash
az storage container create \
  --account-name "$ACCT" \
  -n "$CONTAINER" \
  --auth-mode login \
  --public-access off
```

## Local archive (unchanged)

```bash
# media (already compressed) → plain tar
tar -cf media.tar "Media Folder"
shasum -a 256 media.tar > media.tar.sha256

# compressible → zstd
tar -c "Folder" | zstd -T0 > folder.tar.zst
shasum -a 256 folder.tar.zst > folder.tar.zst.sha256

zstd -t folder.tar.zst    # or: tar -tf media.tar
```

## Upload + Archive tier

`az storage blob upload` multipart-chunks large files. Upload first (Cool/Hot), verify, then tier down.

```bash
az storage blob upload \
  --account-name "$ACCT" \
  --container-name "$CONTAINER" \
  --name "glacial/folder.tar.zst" \
  --file folder.tar.zst \
  --auth-mode login \
  --overwrite false

az storage blob upload \
  --account-name "$ACCT" \
  --container-name "$CONTAINER" \
  --name "glacial/folder.tar.zst.sha256" \
  --file folder.tar.zst.sha256 \
  --auth-mode login \
  --overwrite false

# big payload → Archive; keep tiny .sha256 on Cool/Hot so you can read it without rehydrate
az storage blob set-tier \
  --account-name "$ACCT" \
  --container-name "$CONTAINER" \
  --name "glacial/folder.tar.zst" \
  --tier Archive \
  --auth-mode login
```

Overnight resume: rclone → Azure Blob is stronger across drops than raw az; then `set-tier` with az.

```bash
# rclone config → type azureblob, auth via az / SP (not account key if you can help it)
rclone copy folder.tar.zst azure:archive/glacial/ -P --checksum
```

## Verify before delete source

```bash
az storage blob show \
  --account-name "$ACCT" \
  --container-name "$CONTAINER" \
  --name "glacial/folder.tar.zst" \
  --auth-mode login -o jsonc
# contentLength == local size; blobTier == Archive

az storage blob download \
  --account-name "$ACCT" \
  --container-name "$CONTAINER" \
  --name "glacial/folder.tar.zst.sha256" \
  --file /tmp/remote.sha256 \
  --auth-mode login
diff -u folder.tar.zst.sha256 /tmp/remote.sha256
```

## Restore (Archive rehydrate — hours)

```bash
az storage blob set-tier \
  --account-name "$ACCT" \
  --container-name "$CONTAINER" \
  --name "glacial/folder.tar.zst" \
  --tier Cool \
  --rehydrate-priority Standard \
  --auth-mode login

# when rehydrate complete:
az storage blob download \
  --account-name "$ACCT" \
  --container-name "$CONTAINER" \
  --name "glacial/folder.tar.zst" \
  --file folder.tar.zst \
  --auth-mode login

shasum -a 256 -c folder.tar.zst.sha256
```

## AWS → Azure map

| AWS | Azure |
|---|---|
| `aws s3 cp … --storage-class DEEP_ARCHIVE` | `az storage blob upload` then `set-tier --tier Archive` |
| bucket | storage account + container |
| IAM profile | `az login` + RBAC (`Storage Blob Data Contributor`) |
| multipart | built into `blob upload` / rclone |

## Netsec checklist (your basics, tightened)

- [x] Sep RG, same region (`westus2`) for RG / VNet / storage
- [x] StorageV2 LRS, cheap vault; Archive is blob **tier**, not a SKU
- [x] `--allow-blob-public-access false` (no anonymous public blobs)
- [x] Storage firewall `--default-action Deny` + allow **your public IP**
- [x] VNet `10.0.0.0/16`, subnet `default` `10.0.0.0/24`, new NSG associated
- [x] NSG allow TCP 22/3389/80/443 **only from your IP**; explicit deny-all inbound at 4096
- [x] No storage account keys in scripts — Owner + data-plane RBAC + `--auth-mode login`
- [ ] Remember: NSG ≠ storage firewall (both useful; different layers)
- [ ] Mac upload path = storage IP allowlist (update when home IP changes)
- [ ] Private endpoint optional later; don't disable public network access until that works
- [ ] HNS/SFTP/NFS left off on purpose
- [ ] Source stays on disk until remote size + sha256 verified

