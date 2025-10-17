#!/bin/bash

log() { echo ">>> $*"; }
warn() { echo "!!! WARN: $*"; }
cmd_exists() { command -v "$1" >/dev/null 2>&1; }
brew_outdated() { brew outdated --quiet | grep -qx "$1"; }
ask_yes_no() {
  while true; do
    read -r -p "$1 [yes/no]: " ans
    case "$ans" in
      yes|y|Y) return 0 ;;
      no|n|N) return 1 ;;
      *) echo "Please answer yes or no." ;;
    esac
  done
}

echo "=== Colima/Docker bootstrap (semi-verbose) ==="
echo

echo "=== Step 0: Environment and tool versions ==="
echo "Host: $(uname -srm)"
echo "macOS: $(sw_vers -productVersion)"
echo "Colima: $(colima version)"
echo "Docker: $(docker --version)"
echo "Docker Compose: $(docker compose version)"
echo

echo "=== Step 0a: Homebrew detection & PATH info (no changes made) ==="
if cmd_exists brew; then
  BREW_PREFIX=$(HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1 brew --prefix 2>/dev/null)
  log "Homebrew detected at: $BREW_PREFIX"
else
  warn "Homebrew not found in PATH. Upgrades will be skipped."
  echo "Tip: export PATH=\"/opt/homebrew/bin:$PATH\""
fi
echo

echo "=== Step 0b: Colima status & binary origins (no changes made) ==="
COLIMA_STATUS="Unknown"
if cmd_exists colima; then
  COLIMA_STATUS=$(colima status 2>/dev/null | awk -F': *' '/^Status/ {print $2}')
  [ -z "$COLIMA_STATUS" ] && COLIMA_STATUS="Unknown"
else
  COLIMA_STATUS="Not Installed"
fi
echo "Colima binary: $(command -v colima 2>/dev/null || echo 'not found')"
echo "Docker binary: $(command -v docker 2>/dev/null || echo 'not found')"
echo "Colima status: $COLIMA_STATUS"
if cmd_exists brew; then
  if brew list --versions colima >/dev/null 2>&1; then
    log "colima is Homebrew-managed"
  else
    warn "colima not listed by Homebrew; will not attempt to upgrade colima"
  fi
  if brew list --versions docker >/dev/null 2>&1; then
    log "docker is Homebrew-managed"
  else
    warn "docker not listed by Homebrew; will not attempt to upgrade docker"
  fi
fi
echo

echo "=== Step 0c: Safe upgrade checks (targeted; gated) ==="
if cmd_exists brew; then
  CANDIDATES=()
  for formula in colima docker; do
    if HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1 brew list --versions "$formula" >/dev/null 2>&1; then
      CANDIDATES+=("$formula")
    fi
  done
  OUTDATED_LIST=()
  if [ ${#CANDIDATES[@]} -gt 0 ]; then
    for formula in "${CANDIDATES[@]}"; do
      if HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1 brew_outdated "$formula"; then
        OUTDATED_LIST+=("$formula")
      fi
    done
  fi
  if [ ${#OUTDATED_LIST[@]} -gt 0 ]; then
    echo "Outdated: ${OUTDATED_LIST[*]}"
    if [ "$COLIMA_STATUS" = "Running" ]; then
      warn "Colima is Running; skipping upgrades to avoid disruption."
      if ask_yes_no "Continue script run without upgrades?"; then
        log "Continuing without upgrades."
      else
        log "Exiting per user choice."
        exit 0
      fi
    else
      if ask_yes_no "Upgrades available. Run 'brew update' then upgrade now?"; then
        log "Refreshing Homebrew metadata (brew update)"
        HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1 brew update >/dev/null 2>&1 || true
        for formula in "${OUTDATED_LIST[@]}"; do
          log "Upgrading $formula"
          HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1 brew upgrade "$formula" >/dev/null 2>&1 || true
        done
      else
        if ask_yes_no "Continue script run without upgrades?"; then
          log "Continuing without upgrades."
        else
          log "Exiting per user choice."
          exit 0
        fi
      fi
    fi
  else
    log "No targeted upgrades (colima/docker) needed"
  fi
else
  warn "Skipping upgrades: Homebrew not available."
fi
echo

echo "=== Step 1: Start Colima (docker runtime) ==="
if [ "$COLIMA_STATUS" = "Running" ]; then
  log "Colima already running; skipping start"
else
  colima start --runtime docker --arch aarch64 --cpu 4 --memory 4 --disk 60
fi
echo

echo "=== Step 2: Docker contexts (list, select 'colima', show) ==="
docker context ls
if ! docker context use colima; then
  warn "Failed to switch to 'colima' context."
  echo "Troubleshooting:"
  echo "  colima start"
  echo "  docker context ls"
  echo "  docker context create colima --docker host=unix://$HOME/.colima/default/docker.sock"
  echo "  docker context use colima"
fi
docker context show
if docker context show | grep -q "desktop-linux"; then
  warn "Docker Desktop context detected. Prefer 'colima'."
  echo "Tip: docker context rm desktop-linux || true"
  echo "     docker context use colima"
fi
echo

echo "=== Step 3: Docker info and basic checks ==="
docker --version
echo
if ! docker system info --format '{{.Name}}  {{.ServerVersion}}  {{.OSType}}/{{.Architecture}}'; then
  warn "Cannot connect to Docker daemon."
  echo "Troubleshooting:"
  echo "  colima start"
  echo "  docker context use colima"
  echo "  docker ps"
fi
echo
if ! docker ps; then
  warn "Failed to list containers (docker ps)."
  echo "Troubleshooting:"
  echo "  colima start"
  echo "  docker context use colima"
  echo "  docker ps"
fi
echo

echo "=== Step 4: Docker Compose version ==="
if ! docker compose version; then
  warn "'docker compose' not found or failed. Attempting repair via Homebrew."
  if cmd_exists brew; then
    log "Reinstalling docker-compose formula"
    brew reinstall docker-compose
    mkdir -p "$HOME/.docker/cli-plugins"
    if [ -z "${BREW_PREFIX:-}" ]; then
      BREW_PREFIX=$(brew --prefix 2>/dev/null)
    fi
    if [ -n "${BREW_PREFIX:-}" ]; then
      ln -sfn "$BREW_PREFIX/opt/docker-compose/bin/docker-compose" "$HOME/.docker/cli-plugins/docker-compose"
    else
      warn "Could not determine BREW_PREFIX for compose plugin symlink"
    fi
    if ! docker compose version; then
      warn "Compose still unavailable."
      echo "Troubleshooting:"
      echo "  brew reinstall docker-compose"
      echo "  mkdir -p ~/.docker/cli-plugins"
      echo "  ln -sfn $(brew --prefix)/opt/docker-compose/bin/docker-compose ~/.docker/cli-plugins/docker-compose"
      echo "  docker compose version"
    fi
  else
    warn "Homebrew not available for compose repair."
  fi
fi
echo

echo "=== Step 5: Quick test: hello-world ==="
docker run --rm hello-world
echo

echo "=== Step 6: Optional compose sanity test (busybox) ==="
tmpdir=$(mktemp -d) && cd "$tmpdir"
printf "%s\n" "services:" "  hello:" "    image: busybox:1.36" "    command: ['sh','-lc','echo compose-ok && uname -m']" > compose.yaml
docker compose up --quiet-pull --abort-on-container-exit
docker compose down -v --remove-orphans
cd - && rm -rf "$tmpdir"
echo

echo "=== Final: Colima status ==="
colima status

# Environment override warnings
if [ -n "${DOCKER_HOST:-}" ] || [ -n "${DOCKER_CONTEXT:-}" ]; then
  warn "Environment variables may override Docker context."
  echo "Tip: unset DOCKER_HOST DOCKER_CONTEXT; docker context use colima"
fi
