## Docker-like LXCs under ProxMox

My home LAN services used to run on three RPi4s (hosting my Home Assistant installation, a Docker stack, and another service). I decided to rationalise theses services by migrating them onto a single Proxmox server hosting a standard Home Assistant VM, and to use native Proxmox unprivileged LXCs for the remaining services. I therefore needed to migrate my existing Docker containers to native LXCs.

I initially used the canned [Proxmox Helper Scripts](https://tteck.github.io/Proxmox/) to get started and to get familiar with Proxmox;  However, I dislike the interactive Q&A method for configuring services that the helper scripts use, and so I wanted to move to the Docker Compose approach af having a file based hierarchy under the git-tracked control.   I couldn't any decent template online for this approach under Proxmox, and so I decided to implement this simple project.

## Overview

I use a sudo-enabled account on my Proxmox server for this devevelopment / admin work.  A set of LXCs (roughly equivalent to a Docker Compose project) is maintained within a single directory hierachy. This hierarchy is initalised as a git project, and it has a stardardised directory structure:  there is a top level  `bin` and `.data` sub-directory; plus one sub-directory per LXC being provisioned, with the convention that the container's hostname is the sub-directory name.

-  The common `bin/build_lxc.sh` script controls the build process, using the setup files in the LXC directory to create and provision the container from this configuration, based on a standard Proxmox OS template.  The script adds up to three mount points to the LXC if the corresponding host sub-directory exists; these are (using `fred` as the example hostname):
   -  `fred/bin` is mounted RO on `/usr/local/sbin`
   -  `fred/conf` is mounted RO on `/usr/local/conf`
   -  `.data/fred` its realpath is mounted RW on `/usr/local/data`.  This allows the project to use a sylink to an external file tree.
-  Two small bash syntax configuration files `fred/.env` and `fred/configSettings` are sourced to define the configuration variables needed to customise the LXC creation.  This split is to separate the public and private settings: `configSettings` is controlled under git and hence is viewable according to the projects visibility defined under Github; `.env` is excluded from git by `.gitignore`, and can be used to define private cpnfiguration parameters
-  This build script can also optionally map the host development UID onto the corresponding UID in the host, but given that the host development account is a sudo one, I usually don't bother and access the `.data` subdirectoried by mapped UIC using sudo access.
-  The provisoining of the target is done by the bash script `target-bootstrap.sh`, so once the LXC has been created, `.env`, `configSettings` and `target-bootstrap.sh` is then piped into bash executing on the target container.  Prefixing the `.env`, `configSettings` makes these settings available to the bootstrap script

## Discussion

The heavy lifting is done by `bin/build-LXC.sh`: this is this quite complex, but it is a single script that is common to all LXC builds.  The main LXC-specific work is done by the `target-bootstrap.sh` script and this is what takes the most effect is developing a new LXC configuration.

Most of my LXCs are based on the latest Alpine OS template, simply because this is lean and fast to build and is well suited to most services.  However another base OS template can be used; for example  the `pihole` install script supports Debian, but not Alpine, and so I have use a Debian OS template for my `pihole` containe.

To keep things simple, `target-bootstrap.sh` only does initial provisioning and setup: there are no modification functions and the method of modifying a container configuration is to delete the container and then recreate it.  (The `--rebuid` flag will to this delete automatically).  However as with Docker volumes, the host served `/usr/local/data` mount point and its content will persist over such a rebuild, and this can be used to facilitate application persistence: for example my WordPress blog is served by a LEMP stack on an LXC which  maps its `/var/www` and `var/lib/mysql/` directories in this `data` mountpoint, and hence the Blog content persists over a recreate.

`bin/build-LXC.sh` itself runs at user privilege and it uses `sudo` to execute any privileged commands such as `pct`.

Again to keep things simple, I use `bash` as my scripting enging for both host and `LXC` scripts.  Alpine doesn't have `bash` installed by default, so in the case of Alpine builds, the build script installs it as a prologue before running the target bootstrap.
