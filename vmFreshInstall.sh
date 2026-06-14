#!/usr/bin/env bash
#
# vmFreshInstall.sh — fresh Ubuntu VM/VPS bootstrap
# Repo: misc_bash_scripts (dev)
#
# Design notes:
#   - Idempotent: every step is guarded; safe to re-run.
#   - Non-fatal: one failed install does NOT abort the run. Failures are
#     collected and printed in a summary at the end (+ full log on disk).
#   - Node: nvm is installed from the latest release tag (runtime pinned),
#     then Node 18 + 22 are installed and Node 22 is set default/active.
#   - Auth is handled separately by vmAuthBootstrap.sh (run after this).
#
# Usage:
#   chmod +x vmFreshInstall.sh && ./vmFreshInstall.sh
#   ./vmFreshInstall.sh --npm-globals   # also install vercel/snyk/claude-code globals
#   ./vmFreshInstall.sh --grub-hyperv   # also apply Hyper-V 1080p grub fix
#
set -uo pipefail

# ----- flags -----
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DO_NPM_GLOBALS=0
DO_GRUB=0
for arg in "$@"; do
  case "$arg" in
    --npm-globals) DO_NPM_GLOBALS=1 ;;
    --grub-hyperv) DO_GRUB=1 ;;
    *) echo "Unknown flag: $arg" ;;
  esac
done

# ----- logging / helpers -----
LOG="$HOME/vmFreshInstall-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1
FAILED=()

step()  { printf '\n\033[1;32m==== %s ====\033[0m\n' "$1"; }
note()  { printf '\033[1;33m-- %s\033[0m\n' "$1"; }
have()  { command -v "$1" >/dev/null 2>&1; }
try()   { "$@" || { echo "!! FAILED: $*"; FAILED+=("$*"); }; }
apt_in(){ sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"; }
ensure_line_in_file() {
  local line="$1" file="$2"
  grep -Fqx "$line" "$file" 2>/dev/null || printf '%s\n' "$line" >> "$file"
}

echo "Logging to: $LOG"

# ============================================================
step "System update"
try sudo apt-get update
try sudo DEBIAN_FRONTEND=noninteractive apt-get -y upgrade

# ============================================================
step "Base packages"
try apt_in \
  ca-certificates curl wget gnupg lsb-release software-properties-common \
  build-essential git jq unzip iproute2 iputils-ping htop \
  openssh-server openssh-client yt-dlp gh libfuse2 asciinema \
  python3 python3-venv python3-pip pipx ffmpeg default-jdk
# default-jdk = Java for Maestri CLI (Laura flagged this)
try pipx ensurepath

# ============================================================
step "Doppler CLI (secrets)"
have doppler || try bash -c 'curl -Ls https://cli.doppler.com/install.sh | sudo sh'

# fastfetch via ppa (kept from original)
if ! have fastfetch; then
  try sudo add-apt-repository -y ppa:zhangsongcui3371/fastfetch
  try sudo apt-get update
  try apt_in fastfetch
fi

# ============================================================
step "Visual Studio Code"
if ! have code; then
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /tmp/microsoft.gpg
  sudo install -o root -g root -m 644 /tmp/microsoft.gpg /etc/apt/keyrings/microsoft.gpg
  echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/vscode stable main" \
    | sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null
  try sudo apt-get update
  try apt_in code
else note "code already installed"; fi

# ============================================================
step "Brave Browser"
have brave-browser || try bash -c 'curl -fsS https://dl.brave.com/install.sh | sh'

# ============================================================
step "Docker Engine (+ compose/buildx)"
if ! have docker; then
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  try sudo apt-get update
  # THIS is the line that was missing before — repo was added but nothing installed:
  try apt_in docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  try sudo usermod -aG docker "$USER"
  try sudo systemctl enable --now docker
  note "Log out/in (or 'newgrp docker') for group membership to take effect."
else note "docker already installed"; fi

# ============================================================
step "nvm + Node (latest nvm tag, Node 18 + 22, default 22)"
NVM_VERSION="${NVM_VERSION:-$(curl -fsSL https://api.github.com/repos/nvm-sh/nvm/releases/latest | jq -r .tag_name)}"
if [ -z "${NVM_VERSION:-}" ] || [ "$NVM_VERSION" = "null" ]; then
  NVM_VERSION="v0.40.3"
  note "Could not resolve latest nvm release tag; falling back to ${NVM_VERSION}."
fi
if [ ! -d "${NVM_DIR:-$HOME/.nvm}" ]; then
  try bash -c "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh | bash"
else note "nvm already present"; fi
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if [ -s "$NVM_DIR/nvm.sh" ]; then
  # shellcheck disable=SC1091
  . "$NVM_DIR/nvm.sh"
  try nvm install 18
  try nvm install 22
  try nvm alias default 22
  try nvm use 22
else
  note "nvm shell loader missing; skip Node installation."
fi

# ============================================================
step "Poetry (Python pkg manager — your standard)"
if ! have poetry; then
  try bash -c 'curl -sSL https://install.python-poetry.org | python3 -'
else note "poetry already installed"; fi
export PATH="$HOME/.local/bin:$PATH"

# ============================================================
step "Shell profile bootstrap (.bashrc)"
BASHRC="$HOME/.bashrc"
touch "$BASHRC"
ensure_line_in_file 'export PATH="$HOME/.local/bin:$PATH"' "$BASHRC"
ensure_line_in_file 'export NVM_DIR="$HOME/.nvm"' "$BASHRC"
ensure_line_in_file '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"' "$BASHRC"
ensure_line_in_file '[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"' "$BASHRC"
ensure_line_in_file '[ -f "$HOME/.vm_cli_env" ] && . "$HOME/.vm_cli_env"' "$BASHRC"
try bash -c ". \"$BASHRC\""

# ============================================================
step "Semgrep (pairs with Snyk in your CI/CD)"
have semgrep || try pipx install semgrep

# ============================================================
step "doctl (DigitalOcean CLI) — latest release"
if ! have doctl; then
  DOCTL_VERSION="${DOCTL_VERSION:-$(curl -fsSL https://api.github.com/repos/digitalocean/doctl/releases/latest | jq -r .tag_name | sed 's/^v//')}"
  if [ -n "${DOCTL_VERSION:-}" ] && [ "$DOCTL_VERSION" != "null" ]; then
    curl -fsSL "https://github.com/digitalocean/doctl/releases/download/v${DOCTL_VERSION}/doctl-${DOCTL_VERSION}-linux-amd64.tar.gz" -o /tmp/doctl.tar.gz \
      && tar -xzf /tmp/doctl.tar.gz -C /tmp \
      && sudo mv /tmp/doctl /usr/local/bin/doctl \
      && note "doctl ${DOCTL_VERSION} installed" \
      || { echo "!! FAILED: doctl"; FAILED+=("doctl"); }
  else echo "!! FAILED: doctl (couldn't resolve version)"; FAILED+=("doctl version"); fi
else note "doctl already installed"; fi

# ============================================================
step "Tailscale (tailnet for agent hub; Mullvad exit nodes attach here)"
have tailscale || try bash -c 'curl -fsSL https://tailscale.com/install.sh | sh'
note "Auth later: sudo tailscale up --authkey \$TS_AUTHKEY  (vmAuthBootstrap.sh)"

# ============================================================
step "1Password CLI (op) — AgentOps vault + auth-bootstrap root"
if ! have op; then
  curl -sS https://downloads.1password.com/linux/keys/1password.asc \
    | sudo gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg
  echo "deb [arch=amd64 signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/amd64 stable main" \
    | sudo tee /etc/apt/sources.list.d/1password.list
  sudo mkdir -p /etc/debsig/policies/AC2D62742012EA22/
  curl -sS https://downloads.1password.com/linux/debian/debsig/1password.pol \
    | sudo tee /etc/debsig/policies/AC2D62742012EA22/1password.pol >/dev/null
  sudo mkdir -p /usr/share/debsig/keyrings/AC2D62742012EA22
  curl -sS https://downloads.1password.com/linux/keys/1password.asc \
    | sudo gpg --dearmor --output /usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg
  try sudo apt-get update
  try apt_in 1password-cli
else note "op already installed"; fi

# ============================================================
step "Grafana Alloy (observability agent)"
if ! have alloy; then
  sudo mkdir -p /etc/apt/keyrings
  sudo wget -q -O /etc/apt/keyrings/grafana.asc https://apt.grafana.com/gpg-full.key
  sudo chmod 644 /etc/apt/keyrings/grafana.asc
  echo "deb [signed-by=/etc/apt/keyrings/grafana.asc] https://apt.grafana.com stable main" \
    | sudo tee /etc/apt/sources.list.d/grafana.list
  try sudo apt-get update
  try apt_in alloy
else note "alloy already installed"; fi

# ============================================================
step "kitty terminal (GUI VMs)"
if ! have kitty; then
  try bash -c 'curl -L https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin'
  # desktop integration
  ln -sf ~/.local/kitty.app/bin/kitty ~/.local/kitty.app/bin/kitten ~/.local/bin/ 2>/dev/null || true
  cp ~/.local/kitty.app/share/applications/kitty*.desktop ~/.local/share/applications/ 2>/dev/null || true
  note "kitty.conf + startup session shipped in repo: kitty/  (see README)"
else note "kitty already installed"; fi

# ============================================================
step "Kitty config sync (~/.config/kitty)"
if [ -f "$SCRIPT_DIR/kitty/kitty.conf" ] && [ -f "$SCRIPT_DIR/kitty/session.conf" ]; then
  mkdir -p "$HOME/.config/kitty"
  try cp "$SCRIPT_DIR/kitty/kitty.conf" "$HOME/.config/kitty/kitty.conf"
  try cp "$SCRIPT_DIR/kitty/session.conf" "$HOME/.config/kitty/session.conf"
  note "kitty config/session copied to ~/.config/kitty."
else
  note "Repo kitty config files not found at ./kitty; skipping copy."
fi

# ============================================================
step "CodeRabbit CLI (cr)"
have cr || try bash -c 'curl -fsSL https://cli.coderabbit.ai/install.sh | sh'

# ============================================================
step "Sentry CLI (releases / sourcemaps for observability)"
have sentry-cli || try bash -c 'curl -sL https://sentry.io/get-cli/ | sh'

# ============================================================
step "Aikido local scanner (Docker image — no apt package)"
if have docker; then
  try sudo bash -c 'for _ in $(seq 1 15); do docker info >/dev/null 2>&1 && exit 0; sleep 2; done; exit 1'
  try sudo docker pull aikidosecurity/local-scanner:latest
  note "Scan: docker run --rm -v \"\$(pwd):/app\" aikidosecurity/local-scanner scan /app --apikey \$AIKIDO_API_KEY ..."
else note "Skipping Aikido pull — docker not available yet."; fi

# ============================================================
# mem0: NOT a system binary. It's a library/API (Mem0). Install the SDK
# per-project with Poetry (poetry add mem0ai) and keep MEM0_API_KEY in Doppler.
note "mem0: per-project (poetry add mem0ai) + MEM0_API_KEY in Doppler — not installed globally."

# ============================================================
install_npm_globals() {
  step "npm globals (vercel, snyk, claude-code)"
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  # shellcheck disable=SC1091
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  if have node; then
    try npm install -g vercel snyk @anthropic-ai/claude-code
  else
    note "No active node — skipping. Run: nvm install 22 && nvm use 22, then: npm i -g vercel snyk @anthropic-ai/claude-code"
  fi
}
if [ "$DO_NPM_GLOBALS" -eq 1 ]; then install_npm_globals; else
  note "npm globals skipped (run with --npm-globals when you want global CLI installs)."
fi

# ============================================================
configure_grub_hyperv() {
  step "GRUB Hyper-V framebuffer (1920x1080)"
  sudo cp /etc/default/grub "/etc/default/grub.bak-$(date +%s)"
  sudo sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash video=hyperv_fb:1920x1080"/' /etc/default/grub
  sudo sed -i 's/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX="quiet splash video=hyperv_fb:1920x1080"/' /etc/default/grub
  try sudo update-grub
}
if [ "$DO_GRUB" -eq 1 ]; then
  configure_grub_hyperv
elif systemd-detect-virt 2>/dev/null | grep -qi microsoft; then
  note "Hyper-V detected — re-run with --grub-hyperv to apply the 1080p framebuffer fix."
fi

# ============================================================
step "Summary"
if [ "${#FAILED[@]}" -eq 0 ]; then
  printf '\033[1;32mAll steps completed with no recorded failures.\033[0m\n'
else
  printf '\033[1;31m%d step(s) failed — review and re-run (script is idempotent):\033[0m\n' "${#FAILED[@]}"
  for f in "${FAILED[@]}"; do echo "  - $f"; done
fi
echo "Full log: $LOG"
echo "Next: ./vmAuthBootstrap.sh   (non-interactive auth for the CLIs above)"
