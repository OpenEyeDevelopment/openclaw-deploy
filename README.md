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
here: https://www.openclawfieldplaybook.com. However I will not
be using Docker for the installation.

We will need to connect several services on a private network. For
this we will use tailscale (tailscale.com)for connections,
headscale (https://headscale.net) as the coordination server,
