# Ensuring Certbot Success
Do it in this exact order so Certbot can succeed:

Make sure all DNS A records already point to your droplet IP:
socx.org.uk
www.socx.org.uk
rms.socx.org.uk
ams.socx.org.uk
ghs.socx.org.uk

Activate HTTP-only nginx config first (no SSL cert file references):
sudo cp production-mydomain.http.conf /etc/nginx/sites-available/apps.conf
sudo ln -sfn /etc/nginx/sites-available/apps.conf /etc/nginx/sites-enabled/apps.conf
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx

Confirm port 80 is open in firewall/security group:
sudo ufw allow 'Nginx Full'
sudo ufw status

Obtain certificates with nginx plugin:
sudo certbot --nginx -d socx.org.uk -d www.socx.org.uk
sudo certbot --nginx -d rms.socx.org.uk
sudo certbot --nginx -d ams.socx.org.uk
sudo certbot --nginx -d ghs.socx.org.uk

Verify cert files exist:
sudo ls -la /etc/letsencrypt/live/socx.org.uk
sudo ls -la /etc/letsencrypt/live/www.socx.org.uk
sudo ls -la /etc/letsencrypt/live/rms.socx.org.uk
sudo ls -la /etc/letsencrypt/live/ams.socx.org.uk
sudo ls -la /etc/letsencrypt/live/ghs.socx.org.uk

Switch to HTTPS config:
sudo cp production-mydomain.https.conf /etc/nginx/sites-available/apps.conf
sudo nginx -t
sudo systemctl reload nginx

If certbot still fails, run this and share output:
sudo nginx -t
sudo certbot --nginx -v -d socx.org.uk -d www.socx.org.uk
sudo grep -R "ssl_certificate\|fullchain.pem\|privkey.pem" /etc/nginx

The key rule is: never point nginx at HTTPS cert paths before those cert files exist.