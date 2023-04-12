#! /bin/bash

# In-target initial provisioning of the Debian Pihole + Unbound  LXC
# Note that Pihole isn't yet supported on Alpine, hence the use of Debian

cd /usr/local

# This script rebuilds the local DNS server, so we need to use a public DNS here

sed -i '3s/ .*/ 8.8.8.8/; 4d' /etc/resolv.conf

# Fix up locale so that the Pihole Perl scripts don't throw errors

sed -i '/en_US.UTF-8/s/^# //' /etc/locale.gen
locale-gen

# Install Unbound and Sudo

apt-get update; apt-get install -y unbound sudo

# Add $PIHOLE_USER and sudo enable.  Clone SSH publicc keys from root
# This account will be mapped to the same UID:GID on the host.

addgroup -gid $PIHOLE_GID $PIHOLE_USER
adduser --shell /bin/bash --uid $PIHOLE_UID --gid $PIHOLE_GID \
        --gecos '' --disabled-password  $PIHOLE_USER
echo -e "$PIHOLE_USER ALL=(ALL:ALL) NOPASSWD: ALL\n" >> /etc/sudoers

# Inherit SSH authorised keys from the Root account

USER_SSH="/home/$PIHOLE_USER/.ssh"
mkdir -m 700 $USER_SSH
cp -p /root/.ssh/authorized_keys $USER_SSH
chown $PIHOLE_USER:$PIHOLE_USER -R $USER_SSH

# Configure and start up Unbound

mv /etc/unbound/unbound.conf.d/{,05-}root-auto-trust-anchor-file.conf
cp /usr/local/conf/unbound.conf.d/*.conf /etc/unbound/unbound.conf.d
cp /usr/local/conf/unbound.conf.d/root.{hints,key} /etc/unbound/
service unbound restart

function createSetupVars {
    IP=''
    while [[ -z $IP ]]
        do sleep 1; IP=$(ip a s dev eth0 | awk '/inet /{print $2}'); done
    SUBNET=$( sed 's/\.[0-9]*\/[0-9]*//' <<< "$IP" )
    
    echo "
    PIHOLE_INTERFACE=eth0
    DNSMASQ_LISTENING=single
    IPV4_ADDRESS=
    QUERY_LOGGING=true
    DNSSEC=true
    BLOCKING_ENABLED=true
    API_QUERY_LOG_SHOW=all
    API_PRIVACY_MODE=false
    TEMPERATUREUNIT=C
    DNS_FQDN_REQUIRED=true
    DNS_BOGUS_PRIV=true
    PIHOLE_DNS_1=127.0.0.1#5053
    PIHOLE_DNS_2=127.0.0.1#5053
    REV_SERVER=true
    REV_SERVER_CIDR=${SUBNET}.0/24
    REV_SERVER_TARGET=${SUBNET}.1
    REV_SERVER_DOMAIN=home
    WEBUIBOXEDLAYOUT=traditional
    INSTALL_WEB_SERVER=true
    INSTALL_WEB_INTERFACE=true
    LIGHTTPD_ENABLED=true
    CACHE_SIZE=10000
    WEBPASSWORD='${PIHOLE_PWD}'" | sed 's/^ *//'
}

# Now install Pihole.  At this stage the setupVars need to be
# sufficient to allow the install script to do a full S/W install.

for i in 1 2; do PIHOLE_PWD=$(echo -n $PIHOLE_PWD| sha256sum | cut -b 1-64); done

mkdir -p /etc/pihole

createSetupVars > /etc/pihole/setupVars.conf

# Download the pihole installation script and do unattended install

wget -qO - https://install.pi-hole.net | bash -ls - --unattended

# Stop pihole to reconnect to persistent version, and restart

bash -lc "pihole disable"
pkill pihole-FTL
rm -R /etc/pihole

# Configure and start up pihole.  Note that /etc/pihole is preserved
# except setupVars.conf is reinitialised

ln -s /usr/local/data /etc/pihole
createSetupVars > /etc/pihole/setupVars.conf

bash -lc "pihole enable restartdns"
