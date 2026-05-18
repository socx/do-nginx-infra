# NGINX Infra for Multi-App Droplets (DigitalOcean)

This repository is an infrastructure-only repo for NGINX reverse-proxy configuration.

Your app code stays in separate repositories and deploys to one droplet:

- https://github.com/socx/mydomain
- https://github.com/socx/rms
- https://github.com/socx/asset-manager
- https://github.com/socx/golf-handicap-system

## What This Repo Provides

- Production-ready NGINX configs for:
  - IP-only mode with a base app at `/` and path-routed apps.
  - DNS mode for `www.mydomain.com`, `rms.mydomain.com`, `asset-manager.mydomain.com`, and `ghs.mydomain.com`.
  - HTTPS with redirects and TLS hardening.
- Reusable snippets for proxying, security headers, gzip, and SSL defaults.
- Ready-to-paste `systemd` service files for www, rms, asset-manager, and ghs.
- Ready-to-copy GitHub Actions workflows customized per app repo.

## Important Clarification About IP-Based Hostnames

Names like `rms.123.45.67.89` are usually not publicly resolvable DNS hostnames.

Before DNS exists, use one of these:

1. Path-based routes on bare IP (recommended).
2. Local machine `/etc/hosts` entries for personal testing.
3. Real DNS records for production.

Also note: Let's Encrypt does not issue certificates for bare IP addresses. For HTTPS before DNS, use self-signed/private CA certs or a load balancer with managed TLS.

## Folder Structure

- `sites-available/`: NGINX server block files.
- `sites-enabled/`: Symlinks to active server blocks.
- `snippets/`: Shared include fragments.
- `scripts/systemd-ready/`: Concrete service files, ready to copy.
- `scripts/systemd-templates/`: Generic service templates.
- `scripts/ci-ready/`: Repo-specific deploy workflows, ready to copy.
- `scripts/ci-templates/`: Generic workflow templates by runtime.

## Production Server Block Profiles

### Profile A: IP-Only (No DNS Yet)

Use `sites-available/production-ip.http.conf`.

This gives:

- `http://123.45.67.89/` -> mydomain frontend on `127.0.0.1:5172`
- `http://123.45.67.89/api/` -> mydomain API on `127.0.0.1:3002`
- `http://123.45.67.89/rms/` + `/rms/api/`
- `http://123.45.67.89/asset-manager/` + `/asset-manager/api/`
- `http://123.45.67.89/ghs/` + `/ghs/api/`

### Profile B: DNS HTTP

Use `sites-available/production-mydomain.http.conf`.

This gives:

- `http://www.mydomain.com`
- `http://rms.mydomain.com`
- `http://asset-manager.mydomain.com`
- `http://ghs.mydomain.com`

Each host routes `/api/` to its corresponding backend.

### Profile C: DNS HTTPS

Use `sites-available/production-mydomain.https.conf` with `snippets/ssl-common.conf`.

This gives:

- HTTP to HTTPS redirects.
- Apex redirect `https://mydomain.com` -> `https://www.mydomain.com`.
- TLS defaults suitable for production baseline.

## Step-by-Step Setup (DigitalOcean Style)

This follows the DigitalOcean server-block pattern: put files in `sites-available`, then symlink into `sites-enabled`.

### 1. Bootstrap Droplet

```bash
sudo apt update
sudo apt install -y nginx certbot python3-certbot-nginx git
sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'
sudo ufw --force enable
```

### 2. Clone This Infra Repo

```bash
sudo mkdir -p /opt/infra
sudo chown -R $USER:$USER /opt/infra
git clone https://github.com/socx/do-nginx-infra /opt/infra/do-nginx-infra
cd /opt/infra/do-nginx-infra
```

### 3. Install Snippets

```bash
sudo cp snippets/*.conf /etc/nginx/snippets/
```

### 4. Activate Profile

IP-only profile:

```bash
sudo cp sites-available/production-ip.http.conf /etc/nginx/sites-available/apps.conf
sudo ln -sfn /etc/nginx/sites-available/apps.conf /etc/nginx/sites-enabled/apps.conf
sudo rm -f /etc/nginx/sites-enabled/default
```

mydomain HTTP profile:

```bash
sudo cp sites-available/production-mydomain.http.conf /etc/nginx/sites-available/apps.conf
sudo ln -sfn /etc/nginx/sites-available/apps.conf /etc/nginx/sites-enabled/apps.conf
sudo rm -f /etc/nginx/sites-enabled/default
```

### 5. Validate and Reload NGINX

```bash
sudo nginx -t
sudo systemctl reload nginx
```

### 6. Add DNS Records

Create A records to the droplet IP:

- `mydomain.com`
- `www.mydomain.com`
- `rms.mydomain.com`
- `asset-manager.mydomain.com`
- `ghs.mydomain.com`

### 7. Issue HTTPS Certificates

```bash
sudo certbot --nginx -d mydomain.com -d www.mydomain.com
sudo certbot --nginx -d rms.mydomain.com
sudo certbot --nginx -d asset-manager.mydomain.com
sudo certbot --nginx -d ghs.mydomain.com
```

### 8. Switch to HTTPS Profile

```bash
sudo cp sites-available/production-mydomain.https.conf /etc/nginx/sites-available/apps.conf
sudo nginx -t && sudo systemctl reload nginx
```

## Ready-to-Paste Service Files

The following concrete service files are ready in `scripts/systemd-ready/`:

- `www-frontend.service`, `www-api.service`, `www-worker.service`
- `rms-frontend.service`, `rms-api.service`, `rms-worker.service`
- `asset-manager-frontend.service`, `asset-manager-api.service`, `asset-manager-worker.service`
- `ghs-frontend.service`, `ghs-api.service`, `ghs-worker.service`

Install all services:

```bash
sudo cp scripts/systemd-ready/*.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now \
  www-frontend www-api www-worker \
  rms-frontend rms-api rms-worker \
  asset-manager-frontend asset-manager-api asset-manager-worker \
  ghs-frontend ghs-api ghs-worker
```

These service files assume each tier is Node-based and contains matching scripts:

- Frontend/API: `npm run start`
- Worker: `npm run worker`

Exception:

- `rms-worker.service` is configured as Python and runs:
  - `/opt/apps/rms/worker/.venv/bin/python -m worker`

Working directories are concrete:

- `/opt/apps/mydomain/{frontend,api,worker}`
- `/opt/apps/rms/{frontend,api,worker}`
- `/opt/apps/asset-manager/{frontend,api,worker}`
- `/opt/apps/golf-handicap-system/{frontend,api,worker}`

## Per-Repo Deploy Workflows (Customized)

Ready-to-copy deploy workflows are in `scripts/ci-ready/`:

- `deploy-mydomain.yml`
- `deploy-rms.yml`
- `deploy-asset-manager.yml`
- `deploy-ghs.yml`

Copy each into the matching app repo as `.github/workflows/deploy.yml`.

Each workflow is customized to:

- deploy into the matching `/opt/apps/<repo>` folder.
- restart only matching services for that repo.
- run frontend build and API test before packaging.

Required repo secrets:

- `DROPLET_HOST`
- `DROPLET_USER`
- `DROPLET_SSH_KEY`

## Operational Checks

```bash
sudo nginx -t
sudo systemctl reload nginx
sudo systemctl status www-frontend www-api www-worker --no-pager
sudo systemctl status rms-frontend rms-api rms-worker --no-pager
sudo systemctl status asset-manager-frontend asset-manager-api asset-manager-worker --no-pager
sudo systemctl status ghs-frontend ghs-api ghs-worker --no-pager
```

## Notes on API Routing

This production profile uses same-host API routing by path (`/api`) for each app host/path to keep CORS simpler.