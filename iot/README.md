## Image Documentation

- **MariaDB**.  [Offical Image](https://hub.docker.com/_/mariadb).
- **Nginx**. [Offical Image](https://hub.docker.com/_/nginx).  This configuration is complex and covered below.
- **Pihole**. [Pihole Image](https://hub.docker.com/r/pihole/pihole).
- **WireGuard**.  [GitHub page](https://github.com/linuxserver/docker-wireguard) and [ Quickstart Guide](https://www.wireguard.com/quickstart/)

## Host Platform

The Host system is a 4Gb RPi4 booting off a USB3-attached SSD and running Pi OS 64bit Lite.  The SSD is partioned into a boot partition, an 8Gb root partition (as pretty much everything is run in Docker), with the remainder an LVM2 PV.  `/varlib/docker` is mounted from an LVM2 LV.

## Initialising containers

This stack uses the `MariaDB`, `Pihole` and `Wireguard` provided images without further building, and the associated running containers are customised through the Docker Compose file, with their configuration and initialisation as "out-of-the-box" as practical.  These could be customised during service provisioning as follows, but this isn't currently needed.

-   `db`.  Any scripts `*.sh` in  `/docker-entrypoint-initdb.d/` are executed at container start.
-   `pihole`  Uses `S6` for system startup. The system enumerates and executes any scripts in `/etc/cont-init.d/` so I could add a `10-customize.sh` in here to do tweaking such as dropping `PHP_FCGI_CHILDREN` to 2 in `15-fastcgi-php.conf` in `/etc/lighttpd/conf-enabled/`.
-   `wireguard` also uses `S6` for system startup, so I can add a script into `/etc/cont-init.d/` if required.

The remaining services in the stack `fpm`, `ftp`, `nginx` and `redis` use a common alpine image that is based on `nginx:1.21-apline`, but with the extra apline components added that are needed to run these services.  See [fpm/Dockerfile](fpm/Dockerfile) for this extended image build.  

Each of these services maps `<service>/bin` to `/usr/local/sbin` and the service startup executes `docker-entrypoint.sh` within this folder to set up context for the running service.  This script will typically copy any new or replaced configuration files in the appropriate `/etc` folder and if files need to be modified, then execute `sed` commands is hooked into the service initialisation by `ro` volume mapping from the corresponding `<service>/bin` file or directory. This entrypoint script also adds any required users and groups needed by the running service.

Where appropriate environment variables and _Docker secrets_ are used to customise the context.  

## The Nginx configuration.

-  Vhost `pihole2.home:80/admin` is forward proxied to `pihole:80`
-  Vhost `*.ellisons.org.uk:8880/.well-known/acme-challenge` is mapped to fixed location to enable serving `certbot` HTTP-01 challenges to renew the various `ellisons.org.uk` HTTPS certificates.
-  All other port 80 requested are 301 redirected to the corresponding HTTPS request.
-  Vhost `blog.ellisons.org.uk:443` is my blog and processed by Wordpress.
-  Vhost `ph.ellisons.org.uk:443` contains various adhoc scripts.

## Let's Encrypt certificate renewal

This is carried out if needed as part of the nginx startup.  Since the entire stack is updated and reloaded weekly, this startup renewel is done sufficiently frequently to ensure timely renewal of the certificates.  This host renewal script also passes any updated certificates to my Hass.os system.

## TODO

-   `wireguard`. Generate new key.  Add IP routing.
-   (`cron`).
    - Backup script.

