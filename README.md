# openclaw-deploy

Tools to assist in setting up an
[OpenClaw](https://www.openclawfieldplaybook.com) instance on a VPS or local
machine, without Docker. Targets Debian-based distributions.

The goal is a working OpenClaw gateway on a VPS, connected to a private
Tailscale network coordinated by a self-hosted
[Headscale](https://headscale.net) server.

Scripts cover:

- Installing required OS packages
- Installing the OpenClaw gateway as a systemd user service
- Configuring a Headscale coordination server with nginx reverse proxy and
  Let's Encrypt TLS
- Nightly PostgreSQL backups
- Setting up a local client to connect to the remote gateway

Secrets (API keys, tokens) are kept out of the repository in a `.env-secret`
file and substituted at deploy time.

## Getting started

The first step on a fresh VPS is to get the repository onto the server. Two
paths are available depending on what you have access to.

### Option A — rsync from a local clone

If you have a local clone of this repository:

```bash
rsync scripts/bootstrap.sh root@<vps-ip>:~/
ssh root@<vps-ip> bash bootstrap.sh
```

### Option B — curl directly on the server

If you have SSH access to the server and it already has `curl`:

```bash
BASE=https://raw.githubusercontent.com/OpenEyeDevelopment/openclaw-deploy/main
curl -fsSL "${BASE}/scripts/bootstrap.sh" -o bootstrap.sh
bash bootstrap.sh
```

### Bootstrap options

Both paths run the same `bootstrap.sh` script, which installs `git` and clones
this repository to `~/openclaw-deploy`. Optional arguments:

| Argument | Default | Description |
|---|---|---|
| `-r`, `--repository` | this repo | Clone from a fork instead |
| `-b`, `--branch` | `main` | Check out a different branch |

Example with a fork on a feature branch:

```bash
bash bootstrap.sh -r https://github.com/you/openclaw-deploy.git -b my-feature
```

### Keeping the server up to date

After the initial bootstrap, pull new commits from the repository with:

```bash
bash ~/openclaw-deploy/scripts/update-repo.sh
```

This resets any local changes, removes untracked files, and pulls the latest
commit. If there are local changes it will ask for confirmation first. Use
`--force` to skip the prompt.

### After bootstrap

Once the repository is on the server:

1. Copy the sample secrets file and fill in your values:
   ```bash
   cd ~/openclaw-deploy
   cp .env-secret.sample .env-secret
   vim .env-secret
   ```
2. Edit `/etc/headscale/config.yaml` for your domain.
3. Run the setup scripts in order:
   ```bash
   sudo bash scripts/vps_bootstrap.sh
   sudo bash scripts/setup_headscale.sh
   sudo bash scripts/setup_openclaw.sh
   sudo bash scripts/setup_postgresql_backup.sh
   ```

## Tested versions

Tested on Debian 13 (Trixie) on a Hetzner VPS.

| Component  | Version |
|------------|---------|
| Tailscale  | 1.98.2  |
| PostgreSQL | 18.4    |
| SOPS       | 3.13.1  |
| age        | 1.2.1   |
| Headscale  | 0.28.0  |
| Node.js    | 24.15.0 |
