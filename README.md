# NGINX Infra for Multi-App Droplets (DigitalOcean)

This repository is an infrastructure-only repo for NGINX reverse-proxy configuration.

Your app code stays in separate repositories (for example `rms`, `asset-manager`, `golf-handicap-system`) and gets deployed by GitHub Actions into one droplet.

## What This Repo Provides

- Reusable NGINX snippets for proxying, gzip, and headers.
- Server block templates for:
	- IP-only access (no domain yet) with path routing.
	- Single domain with subdomains.
	- Multiple separate domains.
- CI workflow templates for Node, Python, and Go app repos.
- `systemd` unit templates to keep frontend, API, and worker processes running.

## Important Clarification About IP-Based Hostnames

Names like `rms.123.45.67.89` are usually not valid publicly resolvable DNS records.

Use one of these until DNS is ready:

1. Path-based routes on bare IP (recommended initially):
	 - `http://123.45.67.89/rms/`
	 - `http://123.45.67.89/asset-manager/`
	 - `http://123.45.67.89/ghs/`
2. Local machine `/etc/hosts` entries (for your own testing only).
3. Real DNS records (best for production).

Also note: Let's Encrypt does not issue certificates for bare IP addresses. For HTTPS before DNS, use self-signed/private CA certs or a cloud load balancer with managed TLS.

## Folder Structure

- `sites-available/`: NGINX server block files you choose from.
- `sites-enabled/`: Symlinks to active server block files.
- `snippets/`: Shared include fragments.
- `scripts/ci-templates/`: GitHub Actions templates to copy into each app repo.
- `scripts/systemd-templates/`: Service unit templates for runtime processes.

## Server Block Options

### Option A: No Domain Yet (IP + Paths)

Use `sites-available/ip-only-paths.http.conf`.

Maps these local services:

- RMS frontend: `127.0.0.1:5173`, API: `127.0.0.1:3000`
- Asset Manager frontend: `127.0.0.1:5174`, API: `127.0.0.1:3004`
- GHS frontend: `127.0.0.1:5175`, API: `127.0.0.1:3005`

Public routes become:

- `/rms/` and `/rms/api/`
- `/asset-manager/` and `/asset-manager/api/`
- `/ghs/` and `/ghs/api/`

### Option B: One Main Domain + Subdomains

Use:

- HTTP only: `sites-available/subdomains.http.conf`
- HTTPS: `sites-available/subdomains.https.conf`

Example hostnames:

- `rms.example.com`, `api.rms.example.com`
- `asset-manager.example.com`, `api.asset-manager.example.com`
- `ghs.example.com`, `api.ghs.example.com`

### Option C: Separate Domains per App

Use:

- HTTP only: `sites-available/multi-domains.http.conf`
- HTTPS: `sites-available/multi-domains.https.conf`

Example hostnames:

- `rms.example.com`, `api.rms.example.com`
- `asset-manager.app`, `api.asset-manager.app`
- `golf-handicap-system.dev`, `api.golf-handicap-system.dev`

## Step-by-Step Setup (DigitalOcean Droplet)

The flow below follows the DigitalOcean server-block pattern (`sites-available` + symlink into `sites-enabled`).

### 1. Bootstrap Droplet

```bash
sudo apt update
sudo apt install -y nginx certbot python3-certbot-nginx git
sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'
sudo ufw --force enable
```

### 2. Clone This Infra Repo on Droplet

```bash
sudo mkdir -p /opt/infra
sudo chown -R $USER:$USER /opt/infra
git clone https://github.com/socx/do-nginx-infra /opt/infra/do-nginx-infra
cd /opt/infra/do-nginx-infra
```

### 3. Copy Shared Snippets

```bash
sudo cp snippets/*.conf /etc/nginx/snippets/
```

### 4. Pick and Activate One Site File

IP-only example:

```bash
sudo cp sites-available/ip-only-paths.http.conf /etc/nginx/sites-available/apps.conf
sudo ln -sfn /etc/nginx/sites-available/apps.conf /etc/nginx/sites-enabled/apps.conf
```

Subdomain HTTP example:

```bash
sudo cp sites-available/subdomains.http.conf /etc/nginx/sites-available/apps.conf
sudo ln -sfn /etc/nginx/sites-available/apps.conf /etc/nginx/sites-enabled/apps.conf
```

Disable Ubuntu default site if needed:

```bash
sudo rm -f /etc/nginx/sites-enabled/default
```

### 5. Validate and Reload NGINX

```bash
sudo nginx -t
sudo systemctl reload nginx
```

### 6. Set Up DNS (When Ready)

Create `A` records to droplet IP.

Subdomain model example:

- `rms.example.com` -> droplet IP
- `api.rms.example.com` -> droplet IP
- `asset-manager.example.com` -> droplet IP
- `api.asset-manager.example.com` -> droplet IP
- `ghs.example.com` -> droplet IP
- `api.ghs.example.com` -> droplet IP

### 7. Enable HTTPS (When DNS Exists)

Start from HTTP config first (`subdomains.http.conf` or `multi-domains.http.conf`), then request certificates:

```bash
sudo certbot --nginx -d rms.example.com -d api.rms.example.com
sudo certbot --nginx -d asset-manager.example.com -d api.asset-manager.example.com
sudo certbot --nginx -d ghs.example.com -d api.ghs.example.com
```

Then switch to HTTPS site file in this repo if you want explicit cert paths:

```bash
sudo cp sites-available/subdomains.https.conf /etc/nginx/sites-available/apps.conf
sudo nginx -t && sudo systemctl reload nginx
```

## Deploying Each App Repo (Frontend/API/Worker)

Each app repo should deploy its own artifacts to the droplet and restart only its own services.

Suggested service naming pattern per app:

- `rms-frontend.service`
- `rms-api.service`
- `rms-worker.service`

Worker services are not exposed through NGINX.

### 1. Create Service Units

Copy and adapt templates from:

- `scripts/systemd-templates/node-app.service.template`
- `scripts/systemd-templates/python-app.service.template`
- `scripts/systemd-templates/go-app.service.template`

Install an example service:

```bash
sudo cp /opt/infra/do-nginx-infra/scripts/systemd-templates/node-app.service.template /etc/systemd/system/rms-api.service
# Edit placeholders: <APP_NAME>, <PORT>, <ENTRYPOINT_JS>
sudo systemctl daemon-reload
sudo systemctl enable --now rms-api.service
sudo systemctl status rms-api.service --no-pager
```

Repeat for frontend and worker services.

### 2. Add GitHub Actions in Each App Repo

Copy one template into app repo `.github/workflows/deploy.yml`:

- Node app: `scripts/ci-templates/deploy-node.yml`
- Python app: `scripts/ci-templates/deploy-python.yml`
- Go app: `scripts/ci-templates/deploy-go.yml`

Set these repository secrets in each app repo:

- `DROPLET_HOST`: droplet public IP
- `DROPLET_USER`: SSH user (for example `root` or deploy user)
- `DROPLET_SSH_KEY`: private key matching droplet authorized key
- `APP_NAME`: deployment folder name under `/opt/apps`
- `SYSTEMD_SERVICE`: service to restart (for example `rms-api`)

### 3. Example Mapping for Your Apps

- `rms` repo:
	- Frontend service binds `127.0.0.1:5173`
	- API service binds `127.0.0.1:3000`
	- Worker runs as background service (no public port)
- `asset-manager` repo:
	- Frontend `127.0.0.1:5174`
	- API `127.0.0.1:3004`
	- Worker as service
- `golf-handicap-system` repo:
	- Frontend `127.0.0.1:5175`
	- API `127.0.0.1:3005`
	- Worker as service

## Operational Checks

After each deployment:

```bash
sudo nginx -t
sudo systemctl reload nginx
sudo systemctl status rms-frontend rms-api rms-worker --no-pager
sudo systemctl status asset-manager-frontend asset-manager-api asset-manager-worker --no-pager
sudo systemctl status ghs-frontend ghs-api ghs-worker --no-pager
```

## Notes on Frontend -> API Calls

- If frontend and API share the same hostname, route API as `/api` to avoid CORS complexity.
- If frontend and API are on different subdomains, configure backend CORS allowlist explicitly.

## Next Improvements

- Add blue/green deployment folders (`/opt/apps/<app>/releases/...`) and symlink switching.
- Add health checks in workflows before restarting services.
- Add a rollback command per app in CI.