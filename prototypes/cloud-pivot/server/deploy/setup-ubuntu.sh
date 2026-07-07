#!/usr/bin/env bash
# BNS sync server — one-shot setup for a fresh Ubuntu VPS (tested target:
# Ubuntu 22.04/24.04). Run as root ONCE; the service itself never runs as root.
#
#   sudo bash setup-ubuntu.sh
#
# What it does (idempotent):
#   1. Installs Node.js LTS if missing (Ubuntu's own package is fine — the
#      server needs nothing but the Node runtime).
#   2. Creates the unprivileged "bns" system user + /opt/bns/data.
#   3. Installs bns-server.mjs + the hardened systemd unit, enables it.
#   4. Prints the next manual steps (nginx + certbot + adduser).
set -euo pipefail

if [[ $EUID -ne 0 ]]; then echo "run with sudo (setup only — the service runs unprivileged)"; exit 1; fi
HERE="$(cd "$(dirname "$0")" && pwd)"

echo "== 1/4 node =="
if ! command -v node >/dev/null 2>&1; then
  apt-get update -qq && apt-get install -y -qq nodejs
fi
node --version

echo "== 2/4 user + directories =="
id -u bns >/dev/null 2>&1 || adduser --system --group --home /opt/bns --shell /usr/sbin/nologin bns
mkdir -p /opt/bns/data
cp "$HERE/../bns-server.mjs" /opt/bns/bns-server.mjs
chown -R bns:bns /opt/bns
chmod 750 /opt/bns /opt/bns/data

echo "== 3/4 systemd =="
cp "$HERE/bns-sync.service" /etc/systemd/system/bns-sync.service
systemctl daemon-reload
systemctl enable --now bns-sync
sleep 1
systemctl --no-pager --lines=5 status bns-sync || true

echo "== 4/4 done — manual steps =="
cat <<'EOF'

Next (your usual site flow):
  1. nginx + SSL:   cp nginx-bns.conf to sites-available, edit domain,
                    certbot --nginx -d <your-domain>
  2. First account: sudo -u bns node /opt/bns/bns-server.mjs adduser <name> --data-dir /opt/bns/data
                    (token prints ONCE — hand it to the customer with the domain)
  3. Watch disk:    sudo -u bns node /opt/bns/bns-server.mjs stats --data-dir /opt/bns/data
  4. Logs:          journalctl -u bns-sync -f

The service listens on 127.0.0.1:8787 only via nginx; accounts exist only
via this box's CLI. Nothing else to configure, nothing else to break.
EOF
