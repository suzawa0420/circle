#!/usr/bin/env bash
# Install the deterministic OGP renderer without restarting the application.
set -euo pipefail
if ! command -v rsvg-convert >/dev/null 2>&1; then
  sudo -n dnf install -y librsvg2-tools
fi
rsvg-convert --version
# Japanese fonts are already installed on both AL2023 servers.
test -n "$(fc-list :lang=ja family)"
