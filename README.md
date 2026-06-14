# Stuff I always install

For easy Ubuntu VM setup.

## VM bootstrap flow (Ubuntu remote environments)

Primary scripts:

- `vmFreshInstall.sh` installs system packages and CLIs (GUI tooling
  intentionally included).
- `vmAuthBootstrap.sh` performs non-interactive auth from Doppler or 1Password.

Recommended run order on a fresh VM:

1. `chmod +x vmFreshInstall.sh vmAuthBootstrap.sh`
2. `./vmFreshInstall.sh`
3. `source ~/.bashrc`
4. `newgrp docker` (or log out/in) so Docker group membership applies
5. `./vmAuthBootstrap.sh`

Notes:

- Doppler CLI is installed during `vmFreshInstall.sh` before auth bootstrap
  usage.
- `vmFreshInstall.sh` installs latest tagged `nvm`, then installs Node 18 and
  22, and sets default to 22.
- `~/.bashrc` is updated with `~/.local/bin`, nvm init lines, and
  `~/.vm_cli_env` sourcing.
- Kitty config is copied from `kitty/` to `~/.config/kitty/` during install.
- VS Code repo uses keyring-based `signed-by` configuration.
- Networking tooling uses modern packages (`iproute2`, `iputils-ping`) instead
  of `net-tools` and `bridge-utils`.

Production stance currently in use:

- Auto-upgrade/restart hardening (`unattended-upgrades`, `needrestart`) is
  intentionally deferred until failover is in place.
- Firewall policy is intentionally provider-managed (no `ufw` changes in these
  scripts).

## Fabric scripts

`yt_transcript.sh` is a new addition, credit to:
https://github.com/danielmiessler/fabric/issues/1498#issuecomment-2959879765

## Extensions I need but that don't properly install in Cursor

https://marketplace.visualstudio.com/items?itemName=Chadderbox.monokai-vibrant-amped
https://marketplace.visualstudio.com/items?itemName=IBM.output-colorizer

## Python scripts

### Text processors, basic utilities

#### `downgrade_md_headings.py`

Downgrades the entire heading hierarchy in markdown files.

##### Usage

Must be in the same directory. No copy is made; make a backup if necessary.

`python downgrade_md_headings.py <filename.md>`
