#! /bin/bash

# In-target initial provisioning of the Alpine OpenVPN LXC

cd /usr/local
set -vx

ln -s /usr/local/data/terry /home

PACKAGES='dropbear iputils nmap procps sudo tar tree util-linux xz'
apk add --no-cache ${PACKAGES}

#Add VPN User account which is needed for the PiVPN install but with SSH keyed login only

VPN_RNDPASS=$(head -c 64  </dev/urandom | tr -cd 'A-Za-z0-9#%&()*+,-.:<=>?@^_~')
echo -e "${VPN_RNDPASSD}\n${VPN_RNDPASSD}" | adduser -g '' -s /bin/bash  $VPN_USER

echo -e "$VPN_USER ALL=(ALL:ALL) NOPASSWD: ALL\n" >> /etc/sudoers
mkdir -m 700 $VPN_HOME/.ssh
cp -p /root/.ssh/authorized_keys $VPN_HOME/.ssh
chown $VPN_USER:$VPN_USER -R $VPN_HOME/.ssh

# Configure OpenVPN and ensure it is started after a reboot

wget -qO - https://install.pivpn.io | bash -s - --unattended /usr/local/conf/pivpn-init.conf

cd /home/$VPN_USER
last_backup=$(ls -l pivpnbackup | tail -1 | sed  's/.*:.. //') || exit
service openvpn stop
tar -C / -xzpf pivpnbackup/$last_backup
