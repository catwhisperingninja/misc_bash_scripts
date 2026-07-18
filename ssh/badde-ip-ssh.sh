#!/usr/bin/env bash
# de-1p-ssh.sh — cut 1Password out of SSH entirely.
# Result: stock OpenSSH. Passphrases live in the macOS Keychain, unlocked at login.
# No agent socket, no biometric prompt, safe to run unattended from scripts. Free.
#
# Idempotent. Backs up first. Self-restores if the config won't parse.
# Portable: run it on every machine.

set -euo pipefail

CONFIG="${HOME}/.ssh/config"
STAMP="$(date +%Y%m%d-%H%M%S)"

[ -f "${CONFIG}" ] || { echo "!! no ${CONFIG} — nothing to do"; exit 1; }

BACKUP="${CONFIG}.bak-${STAMP}"
cp -p "${CONFIG}" "${BACKUP}"
echo "backup   -> ${BACKUP}"

# 1. Remove every IdentityAgent directive — both the 1Password socket AND the
#    'IdentityAgent none' opt-outs that only ever existed to escape it.
sed -i '' -E '/^[[:space:]]*IdentityAgent([[:space:]]|=)/d' "${CONFIG}"

# 2. Remove stale 1Password *comment* lines only. Never touches a Host line.
sed -i '' -E '/^[[:space:]]*#.*1[Pp]assword/d' "${CONFIG}"

# 3. Append global defaults LAST. ssh_config is first-match-wins, so putting this
#    at the end means your host-specific entries above still take precedence.
if ! grep -qE '^[[:space:]]*UseKeychain[[:space:]]+yes' "${CONFIG}"; then
  cat >> "${CONFIG}" <<'EOF'

# Stock OpenSSH. Passphrases stored in the macOS Keychain, unlocked at login.
# No agent socket, no biometric, unattended-script safe.
Host *
  AddKeysToAgent yes
  UseKeychain yes
EOF
  echo "config   -> appended Keychain defaults"
else
  echo "config   -> Keychain defaults already present"
fi

# 4. Parse check. Fail loudly and roll back rather than leave a broken config.
if ssh -G example.com >/dev/null 2>&1; then
  echo "config   -> parses clean"
else
  echo "!! config failed to parse — restoring ${BACKUP}"
  cp -p "${BACKUP}" "${CONFIG}"
  exit 1
fi

# 5. Load on-disk keys into the Keychain once. After this they load themselves.
shopt -s nullglob
found=0
for pub in "${HOME}"/.ssh/*.pub; do
  key="${pub%.pub}"
  [ -f "${key}" ] || continue
  found=1
  if ssh-add --apple-use-keychain "${key}" </dev/null >/dev/null 2>&1; then
    echo "keychain -> $(basename "${key}")"
  else
    echo "pending  -> $(basename "${key}") needs its passphrase once:"
    echo "            ssh-add --apple-use-keychain ${key}"
  fi
done
[ "${found}" -eq 1 ] || echo "note     -> no keypairs found in ~/.ssh"

cat <<EOF

Done. One manual step left (not scriptable):
  1Password -> Settings -> Developer -> uncheck "Use the SSH agent"

Verify:  ssh-add -l          # your keys, no prompt
Rollback: cp ${BACKUP} ${CONFIG}
EOF
