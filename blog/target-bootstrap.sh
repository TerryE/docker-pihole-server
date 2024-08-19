#! /bin/bash

# In-target initial provisioning of the Alpine blog LEMP stack LXC

# Alpine compontents needed in the LAMP webserver container

package common
package php bcmath bz2 cli ctype curl dom exif fileinfo fpm ftp gd iconv intl \
            mbstring mysqli opcache openssl pecl-imagick phar posix redis \
	          session simplexml sodium tokenizer xml xmlreader xmlwriter zip
package add certbot ghostscript imagemagick mariadb mariadb-client nginx redis
package install

addAccount BLOG

# Symlink persistent folders to host bind mount to preserve over rebuild

persist mysql       /var/lib/mysql
persist letsencrypt /etc/letsencrypt
persist www         /var/www/blog

# Tweak copy nginx config
cp -rv /usr/local/conf/nginx /etc
sed -i "/^user /s/nginx/$BLOG_USER/
        /^worker_processes /s/auto/3/
        /^ssl_session_cache /s/2m/1m/" /etc/nginx/nginx.conf

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

enableService mariadb nginx php-fpm81 redis redis-sentinel
