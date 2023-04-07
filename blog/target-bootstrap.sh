#! /bin/bash

# In-target initial provisioning of the Alpine blog LEMP stack LXC

cd /usr/local

# Alpine compontents needed in the LAMP webserver container

CORE='nginx certbot ghostscript imagemagick logrotate sudo redis tar dropbear'
PHP_MODS='cli fpm bcmath curl ctype dom exif fileinfo ftp gd iconv intl
      mbstring mysqli openssl phar pecl-imagick posix redis session
      simplexml sodium tokenizer xml xmlreader xmlwriter opcache zip'
PHP=$( for m in $PHP_MODS; do echo -n " php81-${m}"; done )
DB='mariadb mariadb-client'
GOODIES='iputils nmap procps tree util-linux xz'

apk add --no-cache ${CORE} ${PHP} ${DB} ${GOODIES}

# The preferred method of access is PCT enter or certificated SSH so the
# password is normally randomised, except for debugging

[[ -v $BLOG_PASSWORD && -n $BLOG_PASSWORD ]] || \
    BLOG_RNDPASS=$(head -c 64  </dev/urandom | tr -cd 'A-Za-z0-9#%&()*+,-.:<=>?@^_~')

# Add $BLOG_USER and sudo enable.  Clone SSH publicc keys from root
# This account will be mapped to the same UID:GID on the host.

addgroup -g $BLOG_UID $BLOG_USER
echo -e "${BLOG_PASSWORD}\n${BLOG_PASSWORD}" | \
    adduser -h /home/$BLOG_USER -g '' -s /bin/bash -G $BLOG_USER -u $BLOG_UID $BLOG_USER

echo -e "$BLOG_USER ALL=(ALL:ALL) NOPASSWD: ALL\n" > /etc/sudoers
USER_SSH="/home/$BLOG_USER/.ssh"

mkdir -m 700 $USER_SSH
cp -p /root/.ssh/authorized_keys $USER_SSH
chown $BLOG_USER:$BLOG_USER -R $USER_SSH

# Change root shell to bash

sed -i '/^root:/s!/ash!/bash!' /etc/passwd

#  Symlink Mysql and WWW trees to host bind mount to preserve these hierarchies over rebuild

rm -Rf /var/lib/mysql
ln -s /usr/local/data/mysql /var/lib/mysql
ln -s /usr/local/data/www /var/www/blog

# Unpack the /etc/letsencrypt folder

tar -C /etc -xzf /usr/local/data/letsencrypt/letsencrypt.tgz

# Tweak nginx config

sed -i "/^user /s/nginx/$BLOG_USER/;
        /^worker_processes /s/auto/3/
        /^ssl_session_cache /s/2m/1m" /etc/nginx/nginx.conf

cp /usr/local/conf/nginx.d/{blog-https,acme-challenge}.conf /etc/nginx/http.d

# Tweak PHP81 config

sed -i "/^ignore_repeated_errors/s/=.*/= On/
        /^;html_errors/s/.*/html_errors = Off/
        /^disable_functions/s/=.*/= "exec,system,passthru,popen,proc_open,shell_exec"/
        /^expose_php/s/=.*/= Off/
        /^upload_max_filesiz/s/=.*/= 4M/
        /session.cookie_samesite/s/=.*/= "Lax"/
        /opcache.memory_consumption/s/=.*/= 64/
        /opcache.max_accelerated_files/s/=.*/= 2000/" /etc/php81/php.ini

sed -i "/^user /s/=.*/= $BLOG_USER/
        /^group /s/=.*/= $BLOG_USER/
        /^listen /s/=.*/= 127.0.0.1:9000/
        /^pm.max_children /s/=.*/= 5/"  /etc/php81/php-fpm.d/www.conf

# Tweak redis config

sed -i "/databases /s/.*/databases 4/
        /^# maxmemory /s/.*/maxmemory 4mb/
        /^# maxmemory-policy /s/.*/maxmemory-policy allkeys-lru/" /etc/redis.conf

for s in dropbear mariadb nginx php-fpm81 redis redis-sentinel; do
  rc-update add $s default
  service $s start
done
