#!/usr/bin/env bash
set -euo pipefail

# One-command bootstrap for a DigitalOcean droplet.
# Installs NGINX and runtime deps, applies selected production config,
# installs snippets/systemd units, enables services, and reloads NGINX.

PROFILE="ip"
START_SERVICES="false"

usage() {
  cat <<'EOF'
Usage:
  sudo bash scripts/bootstrap.sh [--profile ip|dns-http|dns-https] [--start-services]

Options:
  --profile         NGINX profile to activate (default: ip)
  --start-services  Start services immediately after enable (default: disabled)
  -h, --help        Show this help

Examples:
  sudo bash scripts/bootstrap.sh --profile ip
  sudo bash scripts/bootstrap.sh --profile dns-http
  sudo bash scripts/bootstrap.sh --profile dns-https --start-services
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      PROFILE="${2:-}"
      shift 2
      ;;
    --start-services)
      START_SERVICES="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ "$EUID" -ne 0 ]]; then
  echo "Run as root. Example: sudo bash scripts/bootstrap.sh --profile ip"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

case "$PROFILE" in
  ip)
    SITE_SRC="$REPO_ROOT/sites-available/production-ip.http.conf"
    ;;
  dns-http)
    SITE_SRC="$REPO_ROOT/sites-available/production-mydomain.http.conf"
    ;;
  dns-https)
    SITE_SRC="$REPO_ROOT/sites-available/production-mydomain.https.conf"
    ;;
  *)
    echo "Invalid profile: $PROFILE"
    usage
    exit 1
    ;;
esac

echo "[1/8] Installing packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y nginx certbot python3-certbot-nginx git python3 python3-venv

echo "[2/8] Configuring firewall (ufw)"
if command -v ufw >/dev/null 2>&1; then
  ufw allow OpenSSH || true
  ufw allow 'Nginx Full' || true
fi

echo "[3/8] Installing NGINX snippets"
mkdir -p /etc/nginx/snippets
cp "$REPO_ROOT"/snippets/*.conf /etc/nginx/snippets/

echo "[4/8] Activating NGINX site profile: $PROFILE"
cp "$SITE_SRC" /etc/nginx/sites-available/apps.conf
ln -sfn /etc/nginx/sites-available/apps.conf /etc/nginx/sites-enabled/apps.conf
rm -f /etc/nginx/sites-enabled/default

echo "[5/8] Installing systemd units"
cp "$REPO_ROOT"/scripts/systemd-ready/*.service /etc/systemd/system/

echo "[6/8] Enabling services"
SERVICES=(
  www-web www-api www-worker
  rms-web rms-api rms-worker
  ams-web ams-api ams-worker
  ghs-web ghs-api ghs-worker
)

systemctl daemon-reload
systemctl enable "${SERVICES[@]}"

if [[ "$START_SERVICES" == "true" ]]; then
  echo "Starting services"
  systemctl restart "${SERVICES[@]}"
fi

echo "[7/8] Validating and reloading NGINX"
nginx -t
systemctl enable nginx
systemctl restart nginx

echo "[8/8] Status summary"
systemctl --no-pager --full status nginx | sed -n '1,20p' || true
if [[ "$START_SERVICES" == "true" ]]; then
  systemctl --no-pager --full status "${SERVICES[@]}" | sed -n '1,120p' || true
else
  echo "Services enabled but not started. Re-run with --start-services after app code is deployed."
fi

echo "Bootstrap complete. Active profile: $PROFILE"
