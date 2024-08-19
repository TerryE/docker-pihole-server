## Docker-like LXCs under ProxMox

My home LAN services used to run on RPi4s with one hosting Home Assistant (HA) OS, another a Docker host and a dedicated service.  I decided to rationalise this by moving everything onto a spare linux development laptop using it as  lid-closed  battery-backed headless Proxmox host, with a standard HA VM and the other services migrated to unprivileged Proxmox LXCs.

Whilst, I found the [Proxmox Helper Scripts](https://tteck.github.io/Proxmox/) as a useful starting point to get me started and become familiar with Proxmox, I prefer using git-based lifecycle with a file-based hierarchy, and I disliked the interactive Q&A approach to LXC configuration that the helper scripts use.  I therefore decided to move away from using these helper scripts, so I created this project because I couldn't find a decent git-friendly alternative on Internet.

## Overview

I use a sudo-enabled sysadmin account on the Proxmox server for this devevelopment / admin work, with a single git-controlled `lxcs` top-level directory (TLD) hierarchy with one sub-directory per LXC that largely follows my standard Docker Compose projects structure.  All LXC sub-directories within this TLD contain the following:

-  **`configSettings`**  This is a sourced file (in bash syntax) to set various build parameters and define callback hooks.  As this file is accessible in a protentially public git repo, it cannot contain and secret or private data such as passwords and sensitive settings that might compromise security if published publically.  Hence a companion
-   **`.env`** file is used to declare any private build parameters; this is in the `.gitignore` category and thus excluded from `git` control.
-   **`build-target.sh`**  This is called on the target during provisoning to do the initial build of the target.

There are also three standard subdirectory hierarchies are mounted to a corresponding `/usr/local/<dir>` mount point within the LXC:
-   **`conf`**.  Mounted RO as `/usr/local/conf`.  This is used by `build-target.sh` to configure the LXC typically by copying or symlinking files or directories into the corresponding `/etc` locations needed to run the LXC.
-   **`bin`**.  Mounted RO as `/usr/local/sbin`.  This contains any non-disto scripts used in the LXC.  Again `build-target.sh` can execute or symlink these as necessary.
-   **`data`**.  Mounted RW as `/usr/local/data`.  This is used to contain any updatable content that needs to persist across LXC rebuild.  If this entry is a symlink, then its realpath is used for the mount point.

The common `build_lxc.sh` script controls the entire build process for all containers, using the `configSettings`, `.env` and `build-target.sh` for any one container.  This script encapsulates all `pct` actions needed to build the LXC.  The script also support callbacks to hooks defined within the `configSettings` to facilitate mapping service UID to the corresponding host UIDs, adding extra mount points and supporting USB devices.  Once the LXC has been created based on the configuation setting, the script then starts the LXC for the first time, and pipes `.env`, `configSettings` and `target-bootstrap.sh` into bash executing on the target container.  This enables the target bootstrap to do the first time provision using the `.env`, `configSettings` as well as any other scripts in the `/usr/local/sbin` directory.

## Discussion

I track the configuration of each container under git, so sysadmin access within any container is only used to debug issues before updating the `lxcs` files and executing a `bin/build-LXC.sh` with the `--rebuild` option to do a controlled rebuild of the container.  Clearly any state or data that must persist across rebuild must be mapped or symlinked within the `data` mount (or other RW mount if defined by callback).

The heavy lifting is done by `bin/build-LXC.sh`, so it is quite complex.  However, it is a single script that is common to all LXC builds and rarely needs changing.  The main LXC-specific work is done by the `target-bootstrap.sh` script and this is what takes the most effect when developing a new LXC configuration.  Because the only supported method of updating the configuration of an LXC is to delete and then recreate it (the `--rebuid` flag does this automatically), `target-bootstrap.sh` only needs to do initial provisioning and setup, albeit including relinking to `/usr/local/data` hierarchy to reacquire persistent state.

I prefer to base my LXCs on the latest Alpine OS template, simply because this is extremely lean and is fast to build and it is well suited to most services.  Other base OS templates can be used, but the build script currently only supports Debian as an alternative to Alpine.

`GNU bash` is used as the standard scripting engine on the Proxmox host and all containers.  This isn't included by defalt in the Alpine OS template, so the build script installs it as a first step in Alpine builds.
 
Where practical my build target scripts are based largely on standard distro packages.  However, I also use best of cless 3rd party build scripts, where this makes sense.  For example, the `vpn` and `pihole` containers provide VPN access and ad-block DNS management; their build scripts use the excellent [Pi-hole](https://pi-hole.net/) and [PiVPN](https://www.pivpn.io/) installs in unattended mode to do all of the heavy lifting.  These LXCs use a Debian template OS as recommended by the install documentation.

I have also taken the pragmatic attitude to maintaining some sysadmin constistency across all LXCs.  For example I often use rsync to backup / maintain containers during debug, etc.,  so `sshd` is used for remote access to each container instead of `dropbear`, and the server keys are maintained in `data` so that I don't need to renew known-hosts after each rebuild.  I also add some common utilities such as `vim` because I hate using the minimal `busybox vi` implementation.

The build script runs at user privilege and uses `sudo` to execute any privileged commands such as `pct`.  This `bin` is pathed in my environment, so a typical rebuild command might be:
```bash
build_lxc.sh pihole --rebuild |& tee /tmp/pihole.log
```

Result of this is that my `lxcs` hiearchy of some 30 files in git and 6 small `.env` files totalling about 1.1K source lines is sufficient to allow my to build my 6 LXCs.  The entire `lxcs` directory including the persistent `.data` hierachies is only 450 Mb with 90% of this being my WordPress blog and the `pihole-FTL.db` file.  This is small enough to be backed up nightly using `rsync`.
