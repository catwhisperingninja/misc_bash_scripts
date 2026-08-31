#!/usr/bin/env bash
#
# azure-sas-azcopy-extvol.sh
#
# New glacial upload driver — azcopy + container SAS, external-volume staging.
# Does NOT replace glacial-archive-driver.sh (left intact).
#
# Pipeline per top-level source folder:
#   tar (bsdtar) [ | zstd ]  ->  openssl sha256  ->  local integrity test
#   -> azcopy upload (SAS, resumable)  ->  size verify  ->  optional Archive tier
#   -> drop staged tar  (SOURCE never touched)
#
# Designed for huge folders: ~500 GB min, 1 TB+ typical, ~20 dirs total.
# Staging + ledger live on an external volume (WORKDIR), never the boot SSD.
#
# Auth: container (or account) SAS from .env — no account keys in the script.
# Optional az login path kept only for set-tier / blob show when SAS lacks
# those permissions.
#
# Usage:
#   cd /path/to/utils/azure-archive
#   # fill ../.env (or azure-archive/.env) with real values — see .env.example
#   ./azure-sas-azcopy-extvol.sh                 # all top-level folders
#   ./azure-sas-azcopy-extvol.sh MUSIC-TOOLS     # one folder (test)
#   ./azure-sas-azcopy-extvol.sh --dry-run
#   PARALLEL_TAR=2 ./azure-sas-azcopy-extvol.sh # up to 2 concurrent folder jobs
#
# Required .env keys (short names OR GLACIER_* aliases both work):
#   ACCT, CONTAINER, SRC_ROOT, WORKDIR
#   BLOB_SAS_URL  (preferred)  OR  BLOB_URL + BLOB_SAS_TOKEN
# Optional:
#   BLOB_PREFIX, ZSTD_LEVEL, SET_ARCHIVE_TIER, SLACK_WEBHOOK, PUBLIC_IP,
#   PARALLEL_TAR, MEDIA_HINTS, LEDGER, REQUIRE_PUBLIC_IP_MATCH

set -uo pipefail   # NOT -e: per-folder failures stay isolated

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------- load .env (never committed; gitignored) ----------
load_env() {
  local f
  for f in \
    "${GLACIER_ENV_FILE:-}" \
    "$SCRIPT_DIR/.env" \
    "$SCRIPT_DIR/../.env" \
    "$PWD/.env"
  do
    [ -n "$f" ] && [ -f "$f" ] || continue
    set -a
    # shellcheck disable=SC1090
    source "$f"
    set +a
    ENV_FILE_LOADED="$f"
    return 0
  done
  return 1
}
load_env || true

# ---------- config (short names win; GLACIER_* accepted as fallback) ----------
RG="${RG:-${GLACIER_RG:-rg-glacial-media}}"
ACCT="${ACCT:-${GLACIER_ACCT:-}}"
CONTAINER="${CONTAINER:-${GLACIER_CONTAINER:-archive}}"
SRC_ROOT="${SRC_ROOT:-${GLACIER_SRC:-}}"
WORKDIR="${WORKDIR:-${GLACIER_WORKDIR:-}}"
LEDGER="${LEDGER:-${GLACIER_LEDGER:-}}"
BLOB_PREFIX="${BLOB_PREFIX:-${GLACIER_BLOB_PREFIX:-glacial}}"
ZSTD_LEVEL="${ZSTD_LEVEL:-${GLACIER_ZSTD_LEVEL:-3}}"   # 3 = fast default for TB media; raise if you want smaller
SET_ARCHIVE_TIER="${SET_ARCHIVE_TIER:-${GLACIER_SET_ARCHIVE_TIER:-true}}"
SLACK_WEBHOOK="${SLACK_WEBHOOK:-${GLACIER_SLACK_WEBHOOK:-}}"
PUBLIC_IP="${PUBLIC_IP:-${GLACIER_PUBLIC_IP:-}}"
REQUIRE_PUBLIC_IP_MATCH="${REQUIRE_PUBLIC_IP_MATCH:-true}"
PARALLEL_TAR="${PARALLEL_TAR:-1}"                      # concurrent folder jobs; 1 = serial (safest on one disk)
AZCOPY_BUFFER_GB="${AZCOPY_BUFFER_GB:-2}"              # 24 GB RAM machine: keep modest
AZCOPY_CONCURRENCY_VALUE="${AZCOPY_CONCURRENCY_VALUE:-}"  # empty = azcopy auto
AZCOPY_LOG_LOCATION="${AZCOPY_LOG_LOCATION:-}"
# If set, reuse WORKDIR/<name>.tar[.zst] when present (skip tar). Handy for manual test tars.
REUSE_EXISTING_TAR="${REUSE_EXISTING_TAR:-false}"
DRY_RUN=false
ONLY_FOLDERS=()

# SAS: prefer full URL; accept the BOB_ typo as alias
BLOB_SAS_URL="${BLOB_SAS_URL:-${BOB_SAS_URL:-${GLACIER_BLOB_SAS_URL:-${GLACIER_BOB_SAS_URL:-}}}}"
BLOB_URL="${BLOB_URL:-${GLACIER_BLOB_URL:-}}"
BLOB_SAS_TOKEN="${BLOB_SAS_TOKEN:-${GLACIER_BLOB_SAS_TOKEN:-}}"

if [ -n "${MEDIA_HINTS:-${GLACIER_MEDIA_HINTS:-}}" ]; then
  # shellcheck disable=SC2206
  MEDIA_HINTS_ARR=( ${MEDIA_HINTS:-${GLACIER_MEDIA_HINTS}} )
else
  MEDIA_HINTS_ARR=(media video b-roll broll footage render photo image audio music MUSIC-TOOLS)
fi

# ---------- args ----------
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run|-n) DRY_RUN=true; shift ;;
    --parallel)   PARALLEL_TAR="${2:?}"; shift 2 ;;
    --reuse-tar)  REUSE_EXISTING_TAR=true; shift ;;
    --help|-h)
      sed -n '2,40p' "$0"
      exit 0
      ;;
    --) shift; ONLY_FOLDERS+=("$@"); break ;;
    -*)
      echo "unknown flag: $1" >&2
      exit 2
      ;;
    *) ONLY_FOLDERS+=("$1"); shift ;;
  esac
done

# ---------- helpers ----------
die()  { echo "[FATAL] $*" >&2; exit 1; }
ts()   { date '+%Y-%m-%d %H:%M:%S'; }
log()  { echo "[$(ts)] $*" | tee -a "$LOG"; }
notify() {
  log "$*"
  if [ -n "$SLACK_WEBHOOK" ]; then
    local payload
    payload=$(printf '%s' "$*" | python3 -c 'import json,sys; print(json.dumps({"text":sys.stdin.read()}))' 2>/dev/null) \
      || payload="{\"text\":\"notify-encode-failed\"}"
    curl -sS -X POST -H 'Content-type: application/json' --data "$payload" \
      "$SLACK_WEBHOOK" >/dev/null 2>&1 || true
  fi
}

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing tool: $1"; }

bytes_of() { stat -f%z "$1" 2>/dev/null; }

human_bytes() {
  awk -v b="${1:-0}" 'BEGIN{
    split("B KB MB GB TB PB", u, " ");
    x=b+0; i=1;
    while (x>=1024 && i<6) { x/=1024; i++ }
    printf "%.2f %s", x, u[i]
  }'
}

# Build destination base: https://acct.blob.core.windows.net/container  +  ?sas
# Accepts:
#   BLOB_SAS_URL  = full URL with or without trailing container path, with ?sas
#   BLOB_URL      = https://acct.blob.core.windows.net[/container]
#   BLOB_SAS_TOKEN = sp=... or ?sp=...
resolve_dest() {
  local base token
  if [ -n "$BLOB_SAS_URL" ]; then
    base="${BLOB_SAS_URL%%\?*}"
    token="${BLOB_SAS_URL#*\?}"
    if [ "$token" = "$BLOB_SAS_URL" ]; then
      token=""
    fi
  else
    base="$BLOB_URL"
    token="$BLOB_SAS_TOKEN"
  fi
  [ -n "$base" ] || die "set BLOB_SAS_URL or BLOB_URL"
  [ -n "$token" ] || die "set BLOB_SAS_URL (with ?sas) or BLOB_SAS_TOKEN"

  # strip trailing slash on base
  base="${base%/}"
  # if base is only account root, append container
  if [[ "$base" =~ \.blob\.core\.windows\.net$ ]]; then
    base="${base}/${CONTAINER}"
  fi
  # token without leading ?
  token="${token#\?}"

  DEST_BASE="$base"
  SAS_QUERY="$token"
  DEST_SAS_URL="${DEST_BASE}?${SAS_QUERY}"
}

blob_dest_url() {
  # $1 = blob path under container (e.g. glacial/MUSIC-TOOLS.tar)
  local path="$1"
  path="${path#/}"
  printf '%s/%s?%s' "$DEST_BASE" "$path" "$SAS_QUERY"
}

ledger_status() {
  [ -f "$LEDGER" ] || { echo ""; return; }
  awk -F'\t' -v f="$1" '$1==f{s=$2} END{print s}' "$LEDGER"
}

ledger_set() {
  # folder  status  detail
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$(ts)" "${3:-}" >> "$LEDGER"
}

is_media() {
  local n h
  n=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  for h in "${MEDIA_HINTS_ARR[@]}"; do
    h=$(printf '%s' "$h" | tr '[:upper:]' '[:lower:]')
    [[ "$n" == *"$h"* ]] && return 0
  done
  return 1
}

check_public_ip() {
  [ "$REQUIRE_PUBLIC_IP_MATCH" = "true" ] || return 0
  [ -n "$PUBLIC_IP" ] || {
    log "WARN: PUBLIC_IP unset — storage firewall may block you; set PUBLIC_IP in .env"
    return 0
  }
  local live
  live=$(curl -4 -fsS --max-time 8 ifconfig.me 2>/dev/null \
      || curl -4 -fsS --max-time 8 icanhazip.com 2>/dev/null \
      || true)
  live="${live//$'\n'/}"
  live="${live//$'\r'/}"
  if [ -z "$live" ]; then
    log "WARN: could not detect live public IP (offline?); continuing"
    return 0
  fi
  if [ "$live" != "$PUBLIC_IP" ]; then
    die "public IP mismatch: live=$live  PUBLIC_IP=$PUBLIC_IP  (update storage firewall allowlist + .env)"
  fi
  log "public IP OK: $live (matches PUBLIC_IP / storage allowlist)"
}

# ---------- preflight ----------
need_cmd tar
need_cmd openssl
need_cmd azcopy
need_cmd curl
need_cmd python3
need_cmd stat
need_cmd awk

[ -n "$ACCT" ]      || die "set ACCT"
[ -n "$CONTAINER" ] || die "set CONTAINER"
[ -n "$SRC_ROOT" ]  || die "set SRC_ROOT"
[ -n "$WORKDIR" ]   || die "set WORKDIR"
[ -d "$SRC_ROOT" ]  || die "SRC_ROOT not mounted: $SRC_ROOT"
mkdir -p "$WORKDIR" || die "cannot create WORKDIR: $WORKDIR"

# Refuse to stage on the boot volume — 500GB–1TB tars will kill the Mac SSD.
WORKDIR_DISK=$(df -P "$WORKDIR" 2>/dev/null | awk 'NR==2{print $1}')
BOOT_DISK=$(df -P /System/Volumes/Data 2>/dev/null | awk 'NR==2{print $1}')
if [ -n "$WORKDIR_DISK" ] && [ -n "$BOOT_DISK" ] && [ "$WORKDIR_DISK" = "$BOOT_DISK" ]; then
  die "WORKDIR resolves to the boot disk ($WORKDIR). Point it at the external scratch volume."
fi

if [ -z "$LEDGER" ]; then
  LEDGER="$WORKDIR/ledger.tsv"
fi
mkdir -p "$(dirname "$LEDGER")" 2>/dev/null || true
touch "$LEDGER" || die "cannot write ledger: $LEDGER"

LOG_DIR="$WORKDIR/logs"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/azcopy-extvol-$(date +%Y%m%d-%H%M%S).log"
if [ -z "$AZCOPY_LOG_LOCATION" ]; then
  AZCOPY_LOG_LOCATION="$LOG_DIR/azcopy-jobs"
fi
mkdir -p "$AZCOPY_LOG_LOCATION"
export AZCOPY_LOG_LOCATION
export AZCOPY_BUFFER_GB
if [ -n "$AZCOPY_CONCURRENCY_VALUE" ]; then
  export AZCOPY_CONCURRENCY_VALUE
fi
# Keep azcopy from prompting
export AZCOPY_AUTO_LOGIN_TYPE="${AZCOPY_AUTO_LOGIN_TYPE:-}"  # unused with SAS; explicit empty

resolve_dest
check_public_ip

# Quick SAS reachability probe (list/container properties via azcopy jobs isn't right;
# a zero-byte dry destination HEAD isn't exposed — use azcopy with a tiny put only in non-dry? skip.
# Instead: show resolved dest host (no SAS printed).
DEST_HOST="${DEST_BASE#https://}"
DEST_HOST="${DEST_HOST%%/*}"
log "env: ${ENV_FILE_LOADED:-<none loaded — relying on exported vars>}"
log "source:   $SRC_ROOT"
log "workdir:  $WORKDIR"
log "ledger:   $LEDGER"
log "dest:     ${DEST_HOST}/${CONTAINER}/${BLOB_PREFIX}/  (SAS auth)"
log "parallel: $PARALLEL_TAR   zstd_level: $ZSTD_LEVEL   archive_tier: $SET_ARCHIVE_TIER"
log "azcopy buffer: ${AZCOPY_BUFFER_GB}G"

# ---------- per-folder job ----------
process_folder() {
  local dir="$1"
  local base name arc sha blob_path dest_url sha_url
  local lsize rc

  base=$(basename "$dir")
  if [ "$(ledger_status "$base")" = "verified" ]; then
    log "skip (ledger=verified): $base"
    return 0
  fi

  if is_media "$base"; then
    name="${base}.tar"
    arc="$WORKDIR/$name"
    # Also accept a pre-built tar sitting next to the source (e.g. /Volumes/4TB_SCRATCH/MUSIC-TOOLS.tar)
    if [ ! -f "$arc" ] && [ -f "$SRC_ROOT/$name" ]; then
      arc="$SRC_ROOT/$name"
    fi
    log "TAR plain (media): $base -> $arc"
    if [ "$DRY_RUN" = true ]; then
      log "DRY-RUN: would tar -cf $WORKDIR/$name -C $SRC_ROOT $base"
    elif [ "$REUSE_EXISTING_TAR" = true ] && [ -f "$arc" ] && [ "$(bytes_of "$arc")" -gt 0 ]; then
      log "REUSE existing archive: $arc ($(human_bytes "$(bytes_of "$arc")"))"
      if ! tar -tf "$arc" >/dev/null 2>>"$LOG"; then
        notify "FAIL tar-test (reused): $base"
        ledger_set "$base" failed "tar-test-reuse"
        return 1
      fi
    else
      arc="$WORKDIR/$name"
      # same-volume read/write is slow; still correct. -f LAST.
      if ! tar -cf "$arc" -C "$SRC_ROOT" "$base" 2>>"$LOG"; then
        notify "FAIL tar: $base"
        ledger_set "$base" failed "tar"
        rm -f "$arc"
        return 1
      fi
      if ! tar -tf "$arc" >/dev/null 2>>"$LOG"; then
        notify "FAIL tar-test: $base"
        ledger_set "$base" failed "tar-test"
        rm -f "$arc"
        return 1
      fi
    fi
  else
    name="${base}.tar.zst"
    arc="$WORKDIR/$name"
    if [ ! -f "$arc" ] && [ -f "$SRC_ROOT/$name" ]; then
      arc="$SRC_ROOT/$name"
    fi
    log "TAR|zstd -T0 -$ZSTD_LEVEL: $base -> $arc"
    if [ "$DRY_RUN" = true ]; then
      log "DRY-RUN: would tar|zstd $base"
    elif [ "$REUSE_EXISTING_TAR" = true ] && [ -f "$arc" ] && [ "$(bytes_of "$arc")" -gt 0 ]; then
      log "REUSE existing archive: $arc ($(human_bytes "$(bytes_of "$arc")"))"
      need_cmd zstd
      if ! zstd -t "$arc" >/dev/null 2>>"$LOG"; then
        notify "FAIL zstd-test (reused): $base"
        ledger_set "$base" failed "zstd-test-reuse"
        return 1
      fi
    else
      arc="$WORKDIR/$name"
      need_cmd zstd
      if ! tar -c -C "$SRC_ROOT" "$base" 2>>"$LOG" \
          | zstd -T0 -"$ZSTD_LEVEL" -q >"$arc" 2>>"$LOG"; then
        notify "FAIL tar|zstd: $base"
        ledger_set "$base" failed "tar-zstd"
        rm -f "$arc"
        return 1
      fi
      if ! zstd -t "$arc" >/dev/null 2>>"$LOG"; then
        notify "FAIL zstd-test: $base"
        ledger_set "$base" failed "zstd-test"
        rm -f "$arc"
        return 1
      fi
    fi
  fi

  sha="${arc}.sha256"
  if [ "$DRY_RUN" = true ]; then
    log "DRY-RUN: would openssl dgst -sha256 $arc"
    lsize=0
  else
    log "SHA256 (openssl): $name"
    # portable sidecar: "<hex>  <filename>"
    local hex
    hex=$(openssl dgst -sha256 "$arc" 2>>"$LOG" | awk '{print $NF}')
    if [ -z "$hex" ] || [ "${#hex}" -ne 64 ]; then
      notify "FAIL sha256: $base"
      ledger_set "$base" failed "sha256"
      return 1
    fi
    printf '%s  %s\n' "$hex" "$name" >"$sha"
    lsize=$(bytes_of "$arc")
    log "local size: $(human_bytes "$lsize")  sha: ${hex:0:12}…"
  fi

  blob_path="${BLOB_PREFIX}/${name}"
  dest_url="$(blob_dest_url "$blob_path")"
  sha_url="$(blob_dest_url "${blob_path}.sha256")"

  log "UPLOAD azcopy: $blob_path"
  if [ "$DRY_RUN" = true ]; then
    log "DRY-RUN: azcopy copy $arc <dest-sas> --overwrite=false --put-md5 --check-length=true"
    ledger_set "$base" dry-run
    return 0
  fi

  # AzCopy: do not print the SAS URL into the main log line beyond host/path.
  # --overwrite=false protects against clobbering a good remote copy.
  # --put-md5 stores Content-MD5; --check-length validates transfer length.
  # IMPORTANT: with pipefail, still check PIPESTATUS[0] — tee would otherwise mask azcopy failures.
  azcopy copy "$arc" "$dest_url" \
        --overwrite=false \
        --put-md5 \
        --check-length=true \
        --log-level=INFO \
        2>&1 | tee -a "$LOG"
  if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    notify "FAIL azcopy upload: $base"
    ledger_set "$base" failed "azcopy-upload"
    return 1
  fi

  azcopy copy "$sha" "$sha_url" \
        --overwrite=true \
        --put-md5 \
        --check-length=true \
        --log-level=INFO \
        2>&1 | tee -a "$LOG"
  if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    notify "FAIL azcopy sha upload: $base"
    ledger_set "$base" failed "azcopy-sha"
    return 1
  fi

  # Size verify via az CLI if available + logged in; else via azcopy list is awkward with SAS —
  # fall back to `az storage blob show --sas-token`.
  local rsize=""
  if command -v az >/dev/null 2>&1; then
    rsize=$(az storage blob show \
      --account-name "$ACCT" \
      --container-name "$CONTAINER" \
      --name "$blob_path" \
      --sas-token "$SAS_QUERY" \
      --query properties.contentLength -o tsv 2>>"$LOG" || true)
  fi
  if [ -n "$rsize" ] && [ "$rsize" != "$lsize" ]; then
    notify "FAIL size mismatch $base local=$lsize remote=$rsize"
    ledger_set "$base" failed "size-mismatch"
    return 1
  fi
  if [ -n "$rsize" ]; then
    log "size verify OK: $rsize bytes"
  else
    log "WARN: could not read remote size (az missing or SAS lacks read); relying on azcopy --check-length"
  fi

  if [ "$SET_ARCHIVE_TIER" = "true" ]; then
    log "set-tier Archive: $blob_path"
    # Prefer azcopy set-properties (works with SAS that includes write/tier perms)
    azcopy set-properties "$dest_url" --block-blob-tier=Archive 2>&1 | tee -a "$LOG"
    if [ "${PIPESTATUS[0]}" -ne 0 ]; then
      # Fallback: az CLI
      if command -v az >/dev/null 2>&1; then
        az storage blob set-tier \
          --account-name "$ACCT" \
          --container-name "$CONTAINER" \
          --name "$blob_path" \
          --tier Archive \
          --sas-token "$SAS_QUERY" 2>&1 | tee -a "$LOG"
        [ "${PIPESTATUS[0]}" -eq 0 ] || notify "WARN set-tier failed (blob uploaded): $base"
      else
        notify "WARN set-tier failed (blob uploaded): $base"
      fi
    fi
  fi

  local hex_line
  hex_line=$(tr -d '\n' <"$sha" 2>/dev/null || true)
  ledger_set "$base" verified "$hex_line size=$lsize"
  # Only delete staged copies under WORKDIR — never a source-tree sibling tar the user built by hand
  # unless it lives inside WORKDIR.
  case "$arc" in
    "$WORKDIR"/*) rm -f "$arc" "$sha" ;;
    *) rm -f "$sha"; log "left pre-existing archive in place: $arc" ;;
  esac
  notify "OK verified: $base ($(human_bytes "$lsize"))"
  return 0
}

# ---------- folder list ----------
declare -a FOLDERS=()
if [ ${#ONLY_FOLDERS[@]} -gt 0 ]; then
  for f in "${ONLY_FOLDERS[@]}"; do
    if [ -d "$SRC_ROOT/$f" ]; then
      FOLDERS+=("$SRC_ROOT/$f")
    elif [ -d "$f" ]; then
      FOLDERS+=("$f")
    else
      die "folder not found under SRC_ROOT: $f"
    fi
  done
else
  while IFS= read -r d; do
    FOLDERS+=("$d")
  done < <(find "$SRC_ROOT" -mindepth 1 -maxdepth 1 -type d | sort)
fi

[ ${#FOLDERS[@]} -gt 0 ] || die "no folders to process under $SRC_ROOT"

notify "START glacial azcopy run — ${#FOLDERS[@]} folder(s), parallel=$PARALLEL_TAR, dest=${DEST_HOST}/${CONTAINER}/${BLOB_PREFIX}"

ok=0
fail=0

if [ "$PARALLEL_TAR" -le 1 ]; then
  for d in "${FOLDERS[@]}"; do
    if process_folder "$d"; then
      ok=$((ok + 1))
    else
      fail=$((fail + 1))
    fi
  done
else
  # Bounded parallel: background jobs with wait throttle.
  # WARNING: parallel tar on the SAME spinning disk often *slows* throughput.
  # Use PARALLEL_TAR>1 only when SRC and WORKDIR are different devices, or folders are small.
  log "parallel mode: max $PARALLEL_TAR concurrent jobs"
  declare -a pids=()
  declare -a pid_folder=()
  i=0
  for d in "${FOLDERS[@]}"; do
    # throttle
    while [ "$(jobs -rp | wc -l | tr -d ' ')" -ge "$PARALLEL_TAR" ]; do
      sleep 2
    done
    process_folder "$d" &
    pids+=("$!")
    pid_folder+=("$(basename "$d")")
    i=$((i + 1))
  done
  for idx in "${!pids[@]}"; do
    pid="${pids[$idx]}"
    if wait "$pid"; then
      ok=$((ok + 1))
    else
      fail=$((fail + 1))
      log "background job failed: ${pid_folder[$idx]} (pid $pid)"
    fi
  done
fi

notify "DONE — ok=$ok fail=$fail  log=$LOG  ledger=$LEDGER  (source untouched)"
[ "$fail" -eq 0 ] || exit 1
exit 0
