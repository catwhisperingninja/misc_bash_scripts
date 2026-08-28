#!/usr/bin/env bash
#
# wipe-disk.sh — deliberate, guard-railed erase of an EXTERNAL disk on macOS.
#
# Two modes:
#   --full   full zero-fill of the whole surface (hours; verifies every sector)
#   --quick  zero the first ~10 GB to blow away partition tables (minutes;
#            usually enough to un-wedge a "screwed up" drive), then repartition
# Then (default) repartitions to a fresh GPT + APFS volume so the disk is reusable.
#
# DESTRUCTIVE AND IRREVERSIBLE. Safeguards: refuses the boot disk, requires the
# whole-disk device (not a slice), prints the target's identity, and demands a
# typed "ERASE" confirmation. None of that replaces you eyeballing `diskutil list`.
#
# Usage:
#   ./wipe-disk.sh /dev/diskN                 # interactive; asks full vs quick
#   ./wipe-disk.sh --quick /dev/diskN
#   ./wipe-disk.sh --full  /dev/diskN
#   ./wipe-disk.sh --full --no-repartition /dev/diskN
#
# During dd, press Ctrl+T for a progress line (macOS dd has no status=progress).
#
set -euo pipefail

MODE="ask"; REPARTITION=1; DISK=""
while [ $# -gt 0 ]; do
  case "$1" in
    --full)           MODE="full" ;;
    --quick)          MODE="quick" ;;
    --no-repartition) REPARTITION=0 ;;
    /dev/disk*|/dev/rdisk*) DISK="$1" ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac; shift
done
[ -n "$DISK" ] || { echo "usage: $0 [--full|--quick] [--no-repartition] /dev/diskN" >&2; exit 2; }
command -v diskutil >/dev/null || { echo "diskutil not found — this is macOS-only." >&2; exit 1; }

# Normalize to whole-disk block + raw nodes; reject slices/partitions.
BASE="${DISK#/dev/}"; BASE="${BASE#r}"
[[ "$BASE" =~ ^disk[0-9]+$ ]] || { echo "Give the WHOLE disk (e.g. /dev/disk3), not a partition/slice." >&2; exit 2; }
DISKDEV="/dev/$BASE"; RAWDEV="/dev/r$BASE"

# Refuse the disk backing "/".
ROOT_DISK=$(diskutil info / 2>/dev/null | awk -F': *' '/Part of Whole/{print $2}' | tr -d ' ')
if [ -n "$ROOT_DISK" ] && [ "$BASE" = "$ROOT_DISK" ]; then
  echo "REFUSING: $DISKDEV is the boot disk ($ROOT_DISK)." >&2; exit 1
fi

echo "=== Target: $DISKDEV ==="
diskutil list "$DISKDEV" || { echo "No such disk." >&2; exit 1; }
echo
diskutil info "$DISKDEV" | grep -E 'Device / Media Name|Volume Name|Disk Size|Internal|Removable|Protocol' || true
echo

read -r -p "Type ERASE to wipe $DISKDEV (irreversible): " CONF
[ "$CONF" = "ERASE" ] || { echo "Aborted."; exit 1; }

if [ "$MODE" = "ask" ]; then
  read -r -p "Full zero-fill (hours) or quick header wipe (minutes)? [full/quick]: " MODE
fi

echo ">> Unmounting $DISKDEV"
diskutil unmountDisk "$DISKDEV"

case "$MODE" in
  full)  echo ">> Full zero-fill of $RAWDEV — press Ctrl+T for progress"
         sudo dd if=/dev/zero of="$RAWDEV" bs=64m ;;
  quick) echo ">> Zeroing first 10 GB of $RAWDEV (partition tables)"
         sudo dd if=/dev/zero of="$RAWDEV" bs=1m count=10240 ;;
  *) echo "Unknown mode: $MODE (want full|quick)" >&2; exit 2 ;;
esac

if [ "$REPARTITION" = "1" ]; then
  echo ">> Repartitioning $DISKDEV -> GPT + APFS 'Scratch'"
  diskutil eraseDisk APFS Scratch GPT "$DISKDEV"
fi
echo "Done. $DISKDEV is wiped${REPARTITION:+ and repartitioned}."
