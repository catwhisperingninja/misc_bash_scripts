#!/usr/bin/env bash
#
# glacial-archive-driver.sh — batched, resumable, self-minding driver for the
# 14 TB → Azure Archive-tier Blob pipeline defined in glacial_archive_prep.md.
#
# It changes NONE of Laura's decisions. It just automates them across all folders:
#   per-folder tar (bsdtar) -> zstd for compressibles / plain for media
#   -> sha256 -> local integrity test -> upload (rclone keyless, or az)
#   -> verify (size + remote .sha256 diff) -> set-tier Archive -> Slack ping.
# Resumable via a ledger: a re-run skips folders already 'verified'.
#
# HARD RULE (from the spec): the SOURCE is never modified or deleted by this
# script. It only ever removes its own staged tar in $WORKDIR after verify.
#
# Auth: assumes you've run `az login` and been granted "Storage Blob Data
# Contributor" on the account (see glacial_archive_prep.md). Keyless. rclone
# uses the same az session via env_auth, so no account keys anywhere.
#
# macOS: `brew install zstd rclone azure-cli` first. The built-in `tar` is
# bsdtar (keeps xattrs/resource forks) — good, don't swap it for GNU tar.

set -uo pipefail   # NOT -e: per-folder failures are isolated, not fatal to the run.

# ===== CONFIG via environment — export these (or `source` a .env), then run =====
RG="${GLACIER_RG:-rg-glacial-media}"
ACCT="${GLACIER_ACCT:?set GLACIER_ACCT (storage account name)}"
CONTAINER="${GLACIER_CONTAINER:-archive}"
SRC_ROOT="${GLACIER_SRC:?set GLACIER_SRC (the 14TB drive mount)}"
WORKDIR="${GLACIER_WORKDIR:?set GLACIER_WORKDIR (staging dir, >= largest folder)}"
LEDGER="${GLACIER_LEDGER:-$WORKDIR/ledger.tsv}"
BLOB_PREFIX="${GLACIER_BLOB_PREFIX:-glacial}"
UPLOAD_TOOL="${GLACIER_UPLOAD_TOOL:-rclone}"      # rclone | az
RCLONE_REMOTE="${GLACIER_RCLONE_REMOTE:-azure}"
ZSTD_LEVEL="${GLACIER_ZSTD_LEVEL:-12}"
SET_ARCHIVE_TIER="${GLACIER_SET_ARCHIVE_TIER:-true}"
SLACK_WEBHOOK="${GLACIER_SLACK_WEBHOOK:-}"        # optional
if [ -n "${GLACIER_MEDIA_HINTS:-}" ]; then read -r -a MEDIA_HINTS <<< "$GLACIER_MEDIA_HINTS"
else MEDIA_HINTS=("media" "video" "b-roll" "broll" "footage" "render" "photo" "image" "audio" "music"); fi
# ================================================================================

LOG="$WORKDIR/archive-$(date +%Y%m%d-%H%M%S).log"

log()    { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG"; }
notify() {                                  # echo+log always; Slack if configured
  log "$*"
  [ -n "$SLACK_WEBHOOK" ] && curl -s -X POST -H 'Content-type: application/json' \
     --data "{\"text\":\"$(printf '%s' "$*" | sed 's/"/\\"/g')\"}" \
     "$SLACK_WEBHOOK" >/dev/null 2>&1 || true
}
die() { notify ":rotating_light: FATAL: $*"; exit 1; }

# ---------- preflight ----------
mkdir -p "$WORKDIR" || die "cannot create WORKDIR $WORKDIR"
touch "$LEDGER"
for t in tar shasum zstd az; do command -v "$t" >/dev/null || die "missing tool: $t"; done
[ "$UPLOAD_TOOL" = "rclone" ] && { command -v rclone >/dev/null || die "missing rclone"; }
az account show >/dev/null 2>&1 || die "not logged in — run: az login"
az storage container show --account-name "$ACCT" -n "$CONTAINER" --auth-mode login \
  >/dev/null 2>&1 || die "container $CONTAINER not reachable (check RBAC / firewall / IP allowlist)"
[ -d "$SRC_ROOT" ] || die "source $SRC_ROOT not mounted"

ledger_status() { awk -F'\t' -v f="$1" '$1==f{print $2}' "$LEDGER" | tail -1; }
ledger_set()    { printf '%s\t%s\t%s\n' "$1" "$2" "${3:-}" >> "$LEDGER"; }

is_media() {
  local n; n=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  for h in "${MEDIA_HINTS[@]}"; do [[ "$n" == *"$h"* ]] && return 0; done
  return 1
}

upload_blob() {  # $1 local file  $2 blob name
  if [ "$UPLOAD_TOOL" = "rclone" ]; then
    rclone copyto "$1" "${RCLONE_REMOTE}:${CONTAINER}/$2" -P --checksum 2>&1 | tee -a "$LOG"
    return "${PIPESTATUS[0]}"
  else
    az storage blob upload --account-name "$ACCT" --container-name "$CONTAINER" \
      --name "$2" --file "$1" --auth-mode login --overwrite false 2>&1 | tee -a "$LOG"
    return "${PIPESTATUS[0]}"
  fi
}

process_folder() {
  local dir="$1" base name arc sha blob
  base=$(basename "$dir")
  [ "$(ledger_status "$base")" = "verified" ] && { log "skip (done): $base"; return 0; }

  if is_media "$base"; then
    name="${base}.tar";       arc="$WORKDIR/$name"
    log "TAR (plain, media): $base"
    tar -cf "$arc" -C "$SRC_ROOT" "$base" 2>>"$LOG" || { notify ":x: tar failed: $base"; ledger_set "$base" failed; return 1; }
    tar -tf "$arc" >/dev/null 2>&1            || { notify ":x: tar test failed: $base"; ledger_set "$base" failed; return 1; }
  else
    name="${base}.tar.zst";   arc="$WORKDIR/$name"
    log "TAR|zstd (-T0 -$ZSTD_LEVEL): $base"
    tar -c -C "$SRC_ROOT" "$base" 2>>"$LOG" | zstd -T0 -"$ZSTD_LEVEL" -q > "$arc" 2>>"$LOG" \
      || { notify ":x: tar|zstd failed: $base"; ledger_set "$base" failed; return 1; }
    zstd -t "$arc" >/dev/null 2>&1            || { notify ":x: zstd test failed: $base"; ledger_set "$base" failed; return 1; }
  fi

  sha="${arc}.sha256"
  ( cd "$WORKDIR" && shasum -a 256 "$name" > "${name}.sha256" ) || { notify ":x: sha failed: $base"; ledger_set "$base" failed; return 1; }

  blob="${BLOB_PREFIX}/${name}"
  log "UPLOAD: $blob"
  upload_blob "$arc" "$blob"                 || { notify ":x: upload failed: $base"; ledger_set "$base" failed; return 1; }
  upload_blob "$sha" "${blob}.sha256"        || { notify ":x: sha upload failed: $base"; ledger_set "$base" failed; return 1; }

  # verify: remote size == local size, and remote .sha256 == local .sha256
  local lsize rsize
  lsize=$(stat -f%z "$arc")
  rsize=$(az storage blob show --account-name "$ACCT" --container-name "$CONTAINER" \
            --name "$blob" --auth-mode login --query properties.contentLength -o tsv 2>>"$LOG")
  [ "$lsize" = "$rsize" ] || { notify ":x: size mismatch $base (local $lsize / remote $rsize)"; ledger_set "$base" failed; return 1; }
  az storage blob download --account-name "$ACCT" --container-name "$CONTAINER" \
     --name "${blob}.sha256" --file "$WORKDIR/remote.sha256" --auth-mode login >/dev/null 2>&1
  diff -q "$sha" "$WORKDIR/remote.sha256" >/dev/null 2>&1 || { notify ":x: sha mismatch: $base"; ledger_set "$base" failed; return 1; }

  # tier the big payload to Archive; keep the tiny .sha256 on Cool so it's readable w/o rehydrate
  if [ "$SET_ARCHIVE_TIER" = "true" ]; then
    az storage blob set-tier --account-name "$ACCT" --container-name "$CONTAINER" \
       --name "$blob" --tier Archive --auth-mode login >/dev/null 2>&1 \
       || notify ":warning: set-tier Archive failed (uploaded+verified though): $base"
  fi

  ledger_set "$base" verified "$(cat "$sha")"
  rm -f "$arc" "$sha" "$WORKDIR/remote.sha256"   # clean STAGING only — never the source
  notify ":white_check_mark: verified + archived: $base ($(printf '%s' "$rsize" | awk '{printf "%.1f GB", $1/1073741824}'))"
  return 0
}

# ---------- run ----------
notify ":arrow_up: Glacial archive run started — source: $SRC_ROOT -> ${ACCT}/${CONTAINER}/${BLOB_PREFIX}"
ok=0; fail=0
# top-level folders only; each becomes one archive. (Sort for stable order.)
while IFS= read -r dir; do
  if process_folder "$dir"; then ok=$((ok+1)); else fail=$((fail+1)); fi
done < <(find "$SRC_ROOT" -mindepth 1 -maxdepth 1 -type d | sort)

notify ":checkered_flag: Run complete — $ok verified, $fail failed. Failures are isolated; re-run to retry only those. Source untouched. Log: $LOG"
[ "$fail" -eq 0 ] || exit 1
