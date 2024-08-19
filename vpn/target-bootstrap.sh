#! /bin/bash

# In-target initial provisioning of the Alpine OpenVPN LXC

ln -s /usr/local/data/$VPN_USER /home
VPN_HOME="/home/$VPN_USER"

# Install some debug stuff and add VPN User account which is needed for the PiVPN install
# but with SSH keyed login only

setup-apkrepos -c1
package common
package add curl
package install

addAccount VPN

# Configure OpenVPN
  
cd $VPN_HOME
sed s/^..// << EOD  > /tmp/$$.conf
  dhcpReserv=0
  install_home=/home/$VPN_USER
  install_user=$VPN_USER
  IPv4dev=eth0
  pivpnDNS1=$(sed -n '2s/nameserver.//;2p' /etc/resolv.conf)
  pivpnDNS2=
  pivpnenableipv6=0
  pivpnENCRYPT=256
  pivpnHOST=$VPN_EXT_HOST
  pivpnNET=10.183.31.0
  pivpnPORT=1194
  pivpnPROTO=udp
  subnetClass=24
  TWO_POINT_FOUR=1
  UNATTUPG=1
  USE_PREDEFINED_DH_PARAM=1
  VPN=openvpn
EOD

wget -qO - https://install.pivpn.io | bash -ls - --unattended /tmp/$$.conf

export PATH=/usr/sbin:$PATH
service openvpn stop

# Remove Plaform setting as these are recreated if omitted
sed -i '/PLAT=/d; /OSCN=/d' /etc/pivpn/openvpn/setupVars.conf

tar -C / -xzf $(ls -1 pivpnbackup/*.tgz | tail -1)

enableService openvpn
echo Y |/usr/local/bin/pivpn -d
