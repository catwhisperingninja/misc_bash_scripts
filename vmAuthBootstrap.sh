#!/usr/bin/env bash
#
# vmAuthBootstrap.sh — non-interactive auth for the CLIs installed by vmFreshInstall.sh
#
#
# MODEL: one root credential unlocks everything.
#   Provide a Doppler SERVICE TOKEN (preferred) as DOPPLER_TOKEN, OR a
#   1Password service-account token as OP_SERVICE_ACCOUNT_TOKEN. Every other
#   per-CLI token is pulled from there — nothing secret is hardcoded here.
#
#   Doppler is the source of truth for *machine* tokens.
#   1Password "AgentOps" vault stays the home for SSH keys + interactive secrets.
#
# USAGE:
#   export DOPPLER_TOKEN=dp.st.prd.xxxx        # config-scoped service token
#   ./vmAuthBootstrap.sh
#
#   # or pull from 1Password instead of Doppler:
#   export OP_SERVICE_ACCOUNT_TOKEN=ops_xxx ; export SECRET_BACKEND=op
#   ./vmAuthBootstrap.sh
#
# Expected secret names (rename via the map below if yours differ):
#   GH_TOKEN, DIGITALOCEAN_ACCESS_TOKEN, VERCEL_TOKEN, SNYK_TOKEN,
#   TS_AUTHKEY, DOCKERHUB_USER, DOCKERHUB_TOKEN, AIKIDO_API_KEY,
#   CODERABBIT_API_KEY, SENTRY_AUTH_TOKEN, ANTHROPIC_API_KEY, MEM0_API_KEY
#
set -uo pipefail

SECRET_BACKEND="${SECRET_BACKEND:-doppler}"   # doppler | op
DOPPLER_PROJECT="${DOPPLER_PROJECT:-}"        # optional if token is config-scoped
DOPPLER_CONFIG="${DOPPLER_CONFIG:-prd}"
OP_VAULT="${OP_VAULT:-AgentOps}"

note(){ printf '\033[1;33m-- %s\033[0m\n' "$1"; }
ok(){   printf '\033[1;32m[ok]  %s\033[0m\n' "$1"; }
skip(){ printf '\033[1;90m[skip] %s\033[0m\n' "$1"; }
warn(){ printf '\033[1;31m[!!]  %s\033[0m\n' "$1"; }
have(){ command -v "$1" >/dev/null 2>&1; }

# ---- secret fetch ------------------------------------------------------------
secret() {  # secret NAME -> prints value or empty
  local name="$1" val=""
  if [ "$SECRET_BACKEND" = "op" ]; then
    val="$(op read "op://${OP_VAULT}/${name}/credential" 2>/dev/null)"
  else
    local args=(secrets get "$name" --plain)
    [ -n "$DOPPLER_PROJECT" ] && args+=(--project "$DOPPLER_PROJECT")
    [ -n "$DOPPLER_CONFIG" ]  && args+=(--config "$DOPPLER_CONFIG")
    val="$(doppler "${args[@]}" 2>/dev/null)"
  fi
  printf '%s' "$val"
}

# ---- preflight ---------------------------------------------------------------
if [ "$SECRET_BACKEND" = "doppler" ]; then
  have doppler || { warn "doppler CLI not found — run vmFreshInstall.sh first"; exit 1; }
  [ -n "${DOPPLER_TOKEN:-}" ] || warn "DOPPLER_TOKEN not set — relying on existing 'doppler setup' if present"
else
  have op || { warn "op CLI not found — run vmFreshInstall.sh first"; exit 1; }
  [ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ] || { warn "OP_SERVICE_ACCOUNT_TOKEN not set"; exit 1; }
fi

# ---- persist exports for tools that read env per-invocation -------------------
PROFILE="$HOME/.vm_cli_env"
: > "$PROFILE"
persist(){ echo "export $1=\"$2\"" >> "$PROFILE"; }

# ============================== gh ============================================
if have gh; then
  t="$(secret GH_TOKEN)"
  if [ -n "$t" ]; then echo "$t" | gh auth login --with-token && ok "gh" || warn "gh"; else skip "gh (no GH_TOKEN)"; fi
fi

# ============================== doctl ========================================
if have doctl; then
  t="$(secret DIGITALOCEAN_ACCESS_TOKEN)"
  if [ -n "$t" ]; then doctl auth init -t "$t" >/dev/null && ok "doctl" || warn "doctl"; else skip "doctl (no token)"; fi
fi

# ============================== vercel =======================================
# Vercel CLI needs no persistent login — it reads VERCEL_TOKEN or --token.
if have vercel; then
  t="$(secret VERCEL_TOKEN)"
  if [ -n "$t" ]; then persist VERCEL_TOKEN "$t"; ok "vercel (VERCEL_TOKEN persisted to ~/.vm_cli_env)"; else skip "vercel (no token)"; fi
fi

# ============================== snyk =========================================
if have snyk; then
  t="$(secret SNYK_TOKEN)"
  if [ -n "$t" ]; then snyk auth "$t" >/dev/null 2>&1 && ok "snyk" || warn "snyk"; else skip "snyk (no token)"; fi
fi

# ============================== tailscale ====================================
if have tailscale; then
  t="$(secret TS_AUTHKEY)"
  if [ -n "$t" ]; then sudo tailscale up --authkey "$t" --ssh && ok "tailscale" || warn "tailscale"; else skip "tailscale (no TS_AUTHKEY)"; fi
fi

# ============================== docker login =================================
if have docker; then
  u="$(secret DOCKERHUB_USER)"; t="$(secret DOCKERHUB_TOKEN)"
  if [ -n "$u" ] && [ -n "$t" ]; then echo "$t" | docker login -u "$u" --password-stdin >/dev/null 2>&1 && ok "docker login" || warn "docker login"; else skip "docker login (no creds)"; fi
fi

# ============================== sentry-cli ===================================
if have sentry-cli; then
  t="$(secret SENTRY_AUTH_TOKEN)"
  if [ -n "$t" ]; then persist SENTRY_AUTH_TOKEN "$t"; ok "sentry-cli (token persisted)"; else skip "sentry-cli (no token)"; fi
fi

# ============================== api keys (env-only) ==========================
for k in AIKIDO_API_KEY ANTHROPIC_API_KEY MEM0_API_KEY CODERABBIT_API_KEY; do
  v="$(secret "$k")"; [ -n "$v" ] && { persist "$k" "$v"; ok "$k persisted"; } || skip "$k (not in vault)"
done

# ============================== holdouts (cannot fully automate) =============
echo
warn "Interactive holdouts — these resist headless auth, do them once by hand:"
echo "  - coderabbit:  'cr auth login' opens a browser. (CODERABBIT_API_KEY persisted above if CI-mode is supported.)"
echo "  - claude code: Max-plan login is OAuth/browser. For API-key mode, ANTHROPIC_API_KEY is persisted in ~/.vm_cli_env."
echo "  - 1Password desktop/biometric unlock is separate from the 'op' service-account path used here."
echo
note "Add to your shell rc once:   [ -f ~/.vm_cli_env ] && source ~/.vm_cli_env"
ok "Auth bootstrap complete. Tokens that are env-only live in ~/.vm_cli_env (chmod 600 recommended)."
chmod 600 "$PROFILE" 2>/dev/null || true
