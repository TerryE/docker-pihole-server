## Docker-like LXCs under ProxMox

For reasons outside the scope of this project, I wanted to look at options for migrating my Home LAN services (various RPi4s running a Docker stack, my Home Assistant server, etc.)  onto a single Proxmox server running a mix of standard Home Assistant VM and LXCs for the rest.  I wanted to use native Proxmox LXCs rather than a Docker VM, so I wanted to migrate my existing Docker containers to native LXCs .  I initially used of the canned [Proxmox Helper Scripts](https://tteck.github.io/Proxmox/) to get familiar with Proxmox.  However, I prefer the git-tracked file-based approach that I have used with Docker in the past to the interactive Q&A method of configuring services that `tteck` uses. I couldn't any decent template online for this, and so I decided to implement my own by way of a simple project.  This is it.

## Overview

Each Docker-like project has a root directory within a sudo-enabled user account on my Proxmox server.  This root maps onto a git project and has a stardardised directory structure. It contains `bin` and `.data` sub-directory, plus one sub-directory per LXC being provisioned, using its hostname as the directory name.

-  All of the heavy lifting is done by the `bin/build-LXC.sh` script. (Though this still uses tteck's helper script `create_lxc.sh` to do LXC initial creation.)  In essence this build script uses the setup files in the LXC directory to create and provision the server from this configuration, and each based on a standard Proxmox OS template (mostly the latest Alpine temple).  It also adds up to three mount points to the LXC, and this these are (using `fred` as the example hostname): 
   -  `fred/bin` is mounted RO on `/usr/local/sbin`
   -  `fred/conf` is mounted RO on `/usr/local/conf`
   -  `.data/fred`(or its realpath if a symlink) is mounted RW on `/usr/local/data` if this `fred` sub directory exists.
-  Two small bash syntax conguration files `fred/.env` and `fred/configSettings` are sourced to define the configuration variables needed to customise the LXC creation.  This split is because the project as a whole is publicly viewable at Github, so the private settings such as SSH credentials are moved the `.env` file which is excluded from git by `.gitignore`.
-  Once the LXC has been created, then these `.env` and `fred/configSettings` are copied to the target `/tmp` directory. `/usr/local/sbin/target-bootstrap.sh` is then executed to do the server build.
-  To keep things simple, there is function to update a created LXC: the only way to update a service is to do delete and recreate the service.  However the `/usr/local/data` directory tree can be used to facilitate application persistence, as the  target bootstrap can map this onto any directories that need to persist across rebuilds. (For example the LEMP LXC hosting my Wordpress blog maps the `/var/www` and `var/lib/mysql/` directories in this `data` mountpoint).
-  This build script can optionally map the host development UID onto the corresponding UID in the host, but given that the host development account is a sudo one, I usually don't bother and access the `.data` subdirectoried by mapped UIC using sudo access.
