# openclaw-deploy

Tools to assist in setting up an OpenClaw instance on VPS or local.

The goal is to setup a working instance of the OpenClaw gateway on a
VPS. It will only support Debian based distributions, but might be
useful for other distributions as well.

There will be scripts and commands to:
* Install required OS packages;
* Install the OpenClaw gateway and run it as a systemd service;
* Setting up a reverse proxy based on nginx for secure access;
* Setup a vault for secrets.

The deployment scripts will be heavily inspired by the information
here: [openclaw fieldplaybook](https://www.openclawfieldplaybook.com). However I will not
be using Docker for the installation.

We will need to connect several services on a private network. For
this we will use [tailscale](https://tailscale.com) for connections,
[headscale](https://headscale.net) as the coordination server,

## Tested versions

Tested on Debian 13 (Trixie) on a Hetzner VPS.

| Component  | Version  |
|------------|----------|
| Tailscale  | 1.98.2   |
| PostgreSQL | 18.4     |
| SOPS       | 3.13.1   |
| age        | 1.2.1    |
| Headscale  | 0.28.0   |
| Node.js    | 24.15.0  |
| PM2        | 7.0.1    |
