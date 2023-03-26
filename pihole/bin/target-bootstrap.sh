#! /bin/bash

# In-target initial provisioning of the Debian Pihole + Unbound  LXC
# Note that Pihole isn't yet supported on Alpine, hence the use of Debian

cd /usr/local
source /tmp/.env  # Pick up private environment

# This script rebuild the local DNS server, so we need to use a public DNS here

sed '3s/ .*/ 8.8.8.8/' /etc/resolv.conf

# Need to fix up locale so that the Pihole Perl scripts don't throw errors

sed -i '/en_US.UTF-8/s/^# //' /etc/locale.gen
locale-gen

apt-get update; apt-get install -y unbound sudo

# Add $PIHOLE_USER and sudo enable.  Clone SSH publicc keys from root
# This account will be mapped to the same UID:GID on the host.

addgroup -gid $PIHOLE_GID $PIHOLE_USER
adduser --shell /bin/bash --uid $PIHOLE_UID --gid $PIHOLE_GID \
        --gecos '' --disabled-password  $PIHOLE_USER

echo -e "$PIHOLE_USER ALL=(ALL:ALL) NOPASSWD: ALL\n" >> /etc/sudoers
USER_SSH="/home/$PIHOLE_USER/.ssh"

mkdir -m 700 $USER_SSH
cp -p /root/.ssh/authorized_keys $USER_SSH
chown $PIHOLE_USER:$PIHOLE_USER -R $USER_SSH

# Configure and start up unbound

mv /etc/unbound/unbound.conf.d/{,05-}root-auto-trust-anchor-file.conf
cp /usr/local/conf/unbound.conf.d/*.conf /etc/unbound/unbound.conf.d
cp /usr/local/conf/unbound.conf.d/root.{hints,key} /etc/unbound/
service unbound restart

# Install Pihole.  At this stage the setupVars need to be sufficient
# to allow the install script to do a full S/W install.

mkdir -p /etc/pihole; echo '
BLOCKING_ENABLED=true
CACHE_SIZE=10000
DHCP_ACTIVE=false
DNS_BOGUS_PRIV=true
DNS_FQDN_REQUIRED=true
DNSMASQ_LISTENING=local
INSTALL_WEB_INTERFACE=true
INSTALL_WEB_SERVER=true
LIGHTTPD_ENABLED=true
PIHOLE_DNS_1='127.0.0.1#5053'
PIHOLE_DNS_2='127.0.0.1#5053'
PIHOLE_INTERFACE=''
QUERY_LOGGING=true
TEMPERATUREUNIT="C"
WEBPASSWORD=""' > /etc/pihole/setupVars.conf

wget -O /tmp/pihole-install.sh https://install.pi-hole.net
chmod +x /tmp/pihole-install.sh
bash -lc "/tmp/pihole-install.sh --unattended"

# Now stop pihole to reconnect to persistent version, and restart

bash -lc "pihole disable"
pkill pihole-FTL
rm -R /etc/pihole


# Configure and start up pihole.  Note that /etc/pihole is preserved
# except setupVars.conf is reinitialised

ln -s /usr/local/data /etc/pihole

PIHOLE_PWD=$(echo -n $PIHOLE_PWD| sha256sum | cut -b 1-64)
PIHOLE_PWD=$(echo -n $PIHOLE_PWD| sha256sum | cut -b 1-64)
sed "/WEBPASSWORD=/s/=.*/=$PIHOLE_PWD/" \
  /usr/local/conf/pihole/setupVars.conf > /etc/pihole/setupVars.conf

bash -lc "pihole enable restartdns"
