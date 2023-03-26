== Docker-like LXCs under ProxMox

For various reasons outside the scope of this project itself, I wanted to look at options for
migrating the Docker stack and other service onto a single Proxmox server running a mix
of VMs and LXCs, and to migrate my existing Docker containers onto native Proxmox LXCs. I
initially some of the canned [Proxxmox Helper Scripts](https://tteck.github.io/Proxmox/), but
I really dislike their interactive Q&A method of configuring services and far prefer the
file-based approach that I have used with Docker and that could be tracked using Git. After a
quick Interney seach, I couldn'd any decent template online, and so I decided to implement my
own by way of a simple project.  This is it.

== Overview

Each Docker-like project has a root directory within a sudo-enabled user account on the
Proxmox server.  This root maps onto a git project and has a stardardised directory structure.
It contains `bin` and `.data` sub-directory, plus one sub-directory per LXC being provisioned,
using its hostname as the directory name.

-  All of the heavy lifting is done by the `bin/build-LXC.sh` script. (Though tteck's helper script `create_lxc.sh` is called to do LXC initial creation.)  In essence this build script uses the files in the LXC directory to create and provision the server from configuration in the LXC directory, and standard proxmox OS template (mostly the latest Alpine temple).  It also adds up to three mount points to the LXC, and this case of host `fred` these are
   -  `fred/bin` is mounted RO on `/usr/local/sbin`
   -  `fred/conf` is mounted RO on `/usr/local/conf`
   -  `.data/fred`(or its realpath if a symlink) is mounted RW on `/usr/local/data` if this `fred` sub directory exists.
-  Two small bash syntax conguration files `fred/.env` and `fred/configSettings` are sourced to define the configuration variables needed to customise the LXC creation.  This split is because the project as a whole is publicly viewable at Github, so the truly private settings such as SSH credentials are moved the `.env` file and thid is excluded from git by `.gitignore`.
-  Once the LXC has been created, then these `.env` and `fred/configSettings` are copied to the target `/tmp` directory and `/usr/local/sbin/target-bootstrap.sh` is executed to do the server build.
-  There is no means of doing an automatic update: the only way to update a service is to do a rebuild.  However`/usr/local/data` directory can be used to facilitate application persistence, as the  target bootstrap can use this to all directory structures to persist across rebuilds. (For example my LEMP LXC hosting my Wordpress blog map the `/var/www` and `var/lib/mysql/` directories in this `data` mountpoint).
-  This build script can optionally map the host development UID onto the corresponding UID in the host, but given that the host development account is a sudo one, I usually don't bother and access the `.data` subdirectoried by mapped UIC using sudo access.