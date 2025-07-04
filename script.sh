#!/bin/bash
# This script contains post deployment configurations for a Debian-based system.

# Installs certbot for SSL certificate management
DOMAIN="@@DOMAIN@@"
EMAIL="Simon@email.com"
HOSTNAME="@@HOSTNAME@@"

# Change Hostname to Customer Name
sudo hostnamectl set-hostname "$HOSTNAME"

sudo apt install -y network-manager

# Obtain certificate
sudo certbot certonly --standalone -d "$DOMAIN" --agree-tos --email "$EMAIL" --non-interactive

# Set up automatic renewal with cron
CRON_JOB="0 3 * * * /usr/bin/certbot renew --quiet"
(crontab -l 2>/dev/null | grep -v 'certbot renew'; echo "$CRON_JOB") | crontab -


# Configure rsyslog to allow the use of Let's Encrypt private keys
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

# Amend the conf file to point to the correct certificate files
sudo sed -i "s|/etc/ssl/certs/ca-certificates.crt|/etc/ssl/certs/ca-certificates.crt|g" /etc/rsyslog.d/99-tls.conf
sudo sed -i "s|/etc/rsyslog.d/syslog-cert.pem|/etc/letsencrypt/live/@@DOMAIN@@/fullchain.pem|g" /etc/rsyslog.d/99-tls.conf
sudo sed -i "s|/etc/rsyslog.d/syslog-key.pem|/etc/letsencrypt/live/@@DOMAIN@@/privkey.pem|g" /etc/rsyslog.d/99-tls.conf

# Configure permissions for the syslog group to access the private key
realfile=$(readlink -f /etc/letsencrypt/live/@@DOMAIN@@/privkey.pem)  
sudo chown root:syslog "$realfile"  
sudo chmod 640 "$realfile"
sudo chmod 755 /etc/letsencrypt  
sudo chmod 755 /etc/letsencrypt/live  
sudo chmod 755 "/etc/letsencrypt/live/@@DOMAIN@@"  
sudo chmod 755 /etc/letsencrypt/archive  
sudo chmod 755 "/etc/letsencrypt/archive/@@DOMAIN@@"

# Add remote syslog configuration directory to conf file
sudo tee -a "/etc/rsyslog.d/99-tls.conf" >/dev/null << 'EOL'

$MaxMessageSize 64k

$template RemoteHostLogs,"/var/log/remote/%HOSTNAME%/%PROGRAMNAME%.log"
*.* -?RemoteHostLogs
EOL

# Create the remote log directory structure

sudo mkdir -p /var/log/remote
sudo chown syslog:syslog /var/log/remote
sudo chmod 755 /var/log/remote

# Create logrotate configuration for remote logs
sudo tee -a "/etc/logrotate.d/rsyslog.remote" >/dev/null << 'EOL'

/var/log/remote/*/*.log
        { 
        rotate 1
        hourly
        missingok
        notifempty
        compress
        sharedscripts
        postrotate
                /usr/lib/rsyslog/rsyslog-rotate
        endscript
        }
EOL

# Download and install the NinjaOne agent
sudo curl https://aspire.rmmservice.eu/ws/api/v2/generic-installer/NinjaOneAgent-i64.deb -L --output /tmp/NinjaOneAgent-i64.deb
sudo TOKENID="@@TOKENID@@" dpkg -i /tmp/NinjaOneAgent-i64.deb


# Reload AppArmor to apply changes
sudo systemctl reload apparmor
# Reload rsyslog to apply changes
sudo systemctl reload rsyslog
# Restart rsyslog to ensure it picks up the new configuration
sudo systemctl restart rsyslog