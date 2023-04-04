#! /bin/ash

# In-target initial provisioning of the Alpine OpenVPN LXC

cd /usr/local

PACKAGES='bash logrotate iputils nmap procps sudo tar tree util-linux xz'
apk add --no-cache ${PACKAGES}

#Add VPN User account which is needed for the PiVPN install but with SSH keyed login only

VPN_RNDPASS=$(head -c 64  </dev/urandom | tr -cd 'A-Za-z0-9#%&()*+,-.:<=>?@^_~')
VPN_HOME="/home/$VPN_USER"
addgroup -g $VPN_UID $VPN_USER
echo -e "${VPN_RNDPASSD}\n${VPN_RNDPASSD}" | \
  adduser -h $VPN_HOME -g '' -s /bin/bash -G $VPN_USER -u $VPN_UID $VPN_USER
echo -e "$VPN_USER ALL=(ALL:ALL) NOPASSWD: ALL\n" > /etc/sudoers

mkdir -m 700 $VPN_HOME/.ssh
cp -p /root/.ssh/authorized_keys $VPN_HOME/.ssh
chown $VPN_USER:$VPN_USER -R $VPN_HOME/.ssh

# Change root shell to bash
sed -i '/^root:/s!/ash!/bash!' /etc/passwd

# Configure OpenVPN and ensure it is started after a reboot

wget -O /tmp/install.sh https://install.pivpn.io
chmod 755 /tmp/install.sh
/tmp/install.sh --unattended /usr/local/conf/pivpn-init.conf
