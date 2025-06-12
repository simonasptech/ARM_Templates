#!/bin/bash
# This script obtains an SSL certificate for a specified domain and sets up automatic renewal using Certbot.

DOMAIN="2306.aspirenet.uk"
EMAIL="Simon@aspirets.com"

# Obtain certificate
sudo certbot certonly --standalone -d "$DOMAIN" --agree-tos --email "$EMAIL" --non-interactive

# Set up automatic renewal with cron
CRON_JOB="0 3 * * * /usr/bin/certbot renew --quiet"
(crontab -l 2>/dev/null | grep -v 'certbot renew'; echo "$CRON_JOB") | crontab -
