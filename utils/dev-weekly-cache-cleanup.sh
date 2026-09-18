#!/bin/bash
# macOS cache cleanup — runs every other boot

FLAG="$HOME/.local/state/cache-cleanup-next-run"

if [ ! -f "$FLAG" ]; then
    # Skip this boot, mark next boot for cleanup
    mkdir -p "$(dirname "$FLAG")"
    touch "$FLAG"
    logger "cache-cleanup: skipped (will run next boot)"
    exit 0
fi

# Run cleanup and remove flag so next boot skips
rm -f "$FLAG"

# Pause Spotlight indexing during cleanup
mdutil -a -i off 2>/dev/null

# User caches (safe to remove — apps rebuild as needed)
rm -rf ~/Library/Caches/com.todesktop.*.ShipIt
rm -rf ~/Library/Caches/Homebrew
rm -rf ~/Library/Caches/BraveSoftware
rm -rf ~/Library/Caches/node-gyp
rm -rf ~/Library/Caches/pip
rm -rf ~/Library/Caches/pnpm
rm -rf ~/Library/Caches/typescript
rm -rf ~/Library/Caches/snyk
rm -rf ~/Library/Caches/claude-cli-nodejs
rm -rf ~/Library/Caches/virtualenv
rm -rf ~/Library/Caches/ms-playwright

# Logs older than 7 days
find ~/Library/Logs -type f -mtime +7 -delete 2>/dev/null

# Purge inactive memory
purge 2>/dev/null

# Re-enable Spotlight indexing
mdutil -a -i on 2>/dev/null

logger "cache-cleanup: done"
