## Docker-like LXCs under ProxMox

My home LAN services used to run on three RPi4s (hosting my Home Assistant installation, a Docker stack, and another service). I wanted to rationalise theses services by migrating them all onto a single Proxmox server hosting a standard Home Assistant VM, and using native Proxmox unprivileged LXCs for the remaining services.

I therefore needed to migrate my existing Docker containers to native LXCs, so I initially used the canned [Proxmox Helper Scripts](https://tteck.github.io/Proxmox/) to get me started and to get me familiar with Proxmox;  However, I dislike the interactive Q&A method for configuring services that these helper scripts use, and I wanted to move to  a git-controlled a file based hierarchy, as this has been my preferred approach for various development projects and the Docker Compose project that I used for Docker setups.   I couldn't any decent template online for this approach under Proxmox, and so I decided to implement this simple project.

## Overview

I use a sudo-enabled account on my Proxmox server for this devevelopment / admin work, with a set of LXCs (roughly equivalent to a Docker Compose project) maintained within a single `lxcs` directory hierachy.  This hierarchy is initalised as a git project, and it has a stardardised directory structure:  there is a top level  `bin` and `.data` sub-directory; plus one sub-directory per LXC being provisioned, with the convention that each container's hostname is the sub-directory name.

The common `bin/build_lxc.sh` script controls the entire build process for all containers.  This uses setup files in the LXC directory to create and provision the container from this configuration, based on a standard Proxmox OS template.  The script adds up to three mount points to the LXC if the corresponding host sub-directory exists; these are (using `fred` as the example hostname):
-  `fred/bin` is mounted RO on `/usr/local/sbin`
-  `fred/conf` is mounted RO on `/usr/local/conf`
-  `.data/fred` is mounted RW on `/usr/local/data`. In this case the directory is resolved to its realpath as `pct` won't accept symlinks, and allows the conainter mount to resolve a sylink to an external file tree.
-  Two small and mandatory bash syntax configuration files `fred/.env` and `fred/configSettings` are sourced to define the configuration variables needed to customise the LXC creation. The first  is excluded from git by `.gitignore` whilst the second  is controlled under git and hence is viewable according to the projects visibility defined under Github. This split allows separate public and private settings, with `.env`, used to define any private configuration parameters.
-  This build script can also optionally map the host development UID onto the corresponding UID in the host, but given that the host development account is a sudo one, I usually don't bother as I can use sudo to access the `.data` subdirectoried if needed.
-  The provisoining of the target container itself is done by the bash script `target-bootstrap.sh`, so once the LXC has been created, the `.env`, `configSettings` and `target-bootstrap.sh` are then piped into bash executing on the target container.  By prefixing the `.env`, `configSettings` files, this makes these settings available to the bootstrap script.

## Discussion

The heavy lifting is done by `bin/build-LXC.sh`, so this is this quite complex.  However, it is a single script that is common to all LXC builds and rarely needs changing.  The main LXC-specific work is done by the `target-bootstrap.sh` script and this is what takes the most effect when developing a new LXC configuration.

I prefer to base my LXCs on the latest Alpine OS template, simply because this is extremely lean and is fast to build and it is well suited to most services.  However other base OS templates can be used; for example  the `pihole` install script supports Debian, but not Alpine, and so I have use a Debian OS template for my `pihole` container.

To keep things simple, `target-bootstrap.sh` only does initial provisioning and setup: there are no modification functions and the method of modifying a container configuration is to delete the container and then recreate it.  (The `--rebuid` flag will to this delete automatically).  However as with Docker volumes, the host served `/usr/local/data` mount point and its content will persist over such a rebuild, and this can be used to facilitate application persistence: for example my WordPress blog is served by a LEMP stack on an LXC which  maps its `/var/www` and `var/lib/mysql/` directories in this `data` mountpoint, and hence the Blog content persists over a recreate.

`bin/build-LXC.sh` itself runs at user privilege and it uses `sudo` to execute any privileged commands such as `pct`.  This `bin` is pathed in my environment, so a typical rebuild command might be:
```bash
build_lxc pihole --rebuild |& tee /tmp/pihole.log
```
Again to keep things simple, I use `bash` as my scripting enging for both host and `LXC` scripts.  Alpine doesn't have `bash` installed by default, so in the case of Alpine builds, the build script installs it as a prologue before running the target bootstrap.

Result of this is that my `lxcs` hiearchy of some 30 files in git and 6 small `.env` files totalling about 1.1K source lines is sufficient to allow my to build my 6 LXCs.  The entire `lxcs` directory including the persistent `.data` hierachies is only 450 Mb with 90% of this being my WordPress blog and the `pihole-FTL.db` file.  This is small enough to be backed up nightly using `rsync`.

This does exclude one vsFTP file hierachy used to mirror temporary data for review.