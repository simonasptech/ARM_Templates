#!/bin/bash
# This script obtains an SSL certificate for a specified domain and sets up automatic renewal using Certbot.

DOMAIN="@@DOMAIN@@"
EMAIL="Simon@aspirets.com"

# Obtain certificate
sudo certbot certonly --standalone -d "$DOMAIN" --agree-tos --email "$EMAIL" --non-interactive

# Set up automatic renewal with cron
CRON_JOB="0 3 * * * /usr/bin/certbot renew --quiet"
(crontab -l 2>/dev/null | grep -v 'certbot renew'; echo "$CRON_JOB") | crontab -

CONFIG_FILE="/etc/apparmor.d/usr.sbin.rsyslogd"
TMP_FILE=$(mktemp)

awk '
    /# rsyslog configuration/ {
        print
        print "/etc/letsencrypt/*/*/privkey.pem r,"
        print "/etc/letsencrypt/*/*/privkey*.pem r,"
        next
    }
    { print }
' "$CONFIG_FILE" > "$TMP_FILE" && sudo mv "$TMP_FILE" "$CONFIG_FILE"

sudo sed -i "s|/etc/ssl/certs/ca-certificates.crt|/etc/letsencrypt/live/@@DOMAIN@@/fullchain.pem|g" /etc/rsyslog.d/99-tls.conf
sudo sed -i "s|/etc/rsyslog.d/syslog-cert.pem|/etc/letsencrypt/live/@@DOMAIN@@/cert.pem|g" /etc/rsyslog.d/99-tls.conf
sudo sed -i "s|/etc/rsyslog.d/syslog-key.pem|/etc/letsencrypt/live/@@DOMAIN@@/privkey.pem|g" /etc/rsyslog.d/99-tls.conf

realfile=$(readlink -f /etc/letsencrypt/live/@@DOMAIN@@/privkey.pem)  
sudo chown root:syslog "$realfile"  
sudo chmod 640 "$realfile"
sudo chmod 755 /etc/letsencrypt  
sudo chmod 755 /etc/letsencrypt/live  
sudo chmod 755 "/etc/letsencrypt/live/@@DOMAIN@@"  
sudo chmod 755 /etc/letsencrypt/archive  
sudo chmod 755 "/etc/letsencrypt/archive/@@DOMAIN@@"

# Reload AppArmor to apply changes
sudo systemctl reload apparmor
# Reload rsyslog to apply changes
sudo systemctl reload rsyslog
# Restart rsyslog to ensure it picks up the new configuration
sudo systemctl restart rsyslog