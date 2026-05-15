# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`openclaw-deploy` provides scripts and tooling to deploy an [OpenClaw](https://www.openclawfieldplaybook.com) gateway instance on a VPS or local machine without Docker. Targets Debian-based distributions.

## Planned Components

- **OS package installation** — scripts to install required system dependencies
- **OpenClaw gateway** — install and run as a systemd service
- **nginx reverse proxy** — secure HTTPS access to the gateway
- **Vault** — secrets management
- **Tailscale / Headscale** — private network mesh using Tailscale (client) with Headscale as the self-hosted coordination server

## Conventions (to establish as the project grows)

- Scripts should be Debian/Ubuntu compatible (apt-based)
- No Docker — all services run natively on the host
- Systemd is the service manager
- Headscale replaces the Tailscale coordination server for a fully self-hosted setup
