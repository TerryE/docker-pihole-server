#! /bin/bash

# If the current certificate is older than ~2 months, then create a certbot HTTP-01
# challenge response directory, run certbot and clean up

DOMAIN=ellisons.org.uk
FULLCHAIN=/etc/letsencrypt/live/blog.${DOMAIN}/fullchain.pem

if [ ! -f ${FULLCHAIN} ] || [ -n "$(find ${FULLCHAIN} -mtime +61)" ]; then
  echo "$(date -u) Checking / Renewing *.${DOMAIN} certificates" > /proc/1/fd/1
  mkdir /var/www/acme; chown www-data:www-data /var/www/acme
  certbot certonly -n -d blog.${DOMAIN},ha.${DOMAIN},ph.${DOMAIN} \
                   --webroot -w /var/www/acme > /proc/1/fd/1  2>&1
  rm -rf /var/www/acme
else
  echo "$(date -u) Skipping certificate renewal" > /proc/1/fd/1
fi
