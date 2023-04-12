#! /bin/bash

# In-target initial provisioning of the Alpine or Debian OpenVPN LXC

cd /usr/local

ln -s /usr/local/data/$VPN_USER /home
VPN_HOME="/home/$VPN_USER"

# Install some debug stuff and add VPN User account which is needed for the PiVPN install
# but with SSH keyed login only

if [[ -f /etc/debian_version ]] ;then   # Debian build

    sed -i '/en_US.UTF-8/s/^# //' /etc/locale.gen
    locale-gen
    apt-get install -y curl nmap sudo
    adduser --gecos '' --disabled-password  $VPN_USER

else                                    # Apline build

    apk add --no-cache logrotate curl nmap procps sudo tar tree util-linux iputils xz
    VPN_RNDPASS=$(head -c 64  </dev/urandom | tr -cd 'A-Za-z0-9#%&()*+,-.:<=>?@^_~')
    echo -e "${VPN_RNDPASSD}\n${VPN_RNDPASSD}" | adduser -g '' -s /bin/bash  $VPN_USER

fi

echo -e "$VPN_USER ALL=(ALL:ALL) NOPASSWD: ALL\n" >> /etc/sudoers

mkdir -m 700 $VPN_HOME/.ssh
cp -p /root/.ssh/authorized_keys $VPN_HOME/.ssh
chown $VPN_USER:$VPN_USER -R $VPN_HOME/.ssh

# Configure OpenVPN and ensure it is started after a reboot

wget -qO - https://install.pivpn.io | bash -ls - --unattended /usr/local/conf/pivpn-init.conf

cd $VPN_HOME
last_backup=$(ls -l pivpnbackup | tail -1 | sed  's/.*:.. //') || exit

service openvpn stop
tar -C / -xzpf pivpnbackup/$last_backup

# Remove Plaform setting as these are recreated if omitted
sed -i '/PLAT=/d; /OSCN=/d' /etc/pivpn/openvpn/setupVars.conf

reboot