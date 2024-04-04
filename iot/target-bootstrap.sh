#! /bin/bash

# In-target initial provisioning of the IoT LXC running node.js, Node-RED, mariadb, mosquitto and Zigbee2MQTT
#
# /usr/local/data is mounted RW and used to maintain persistent data
# /usr/local/conf is mounted RO and used for any host-hosted configuration
# /usr/local/sbin is mounted RO and used for any host-hosted (set-up) scripts
#
# The RW data and RO config are in the respective nodered, mariadb, mosquitto and zigbee2mqtt sub-dirs.

cd /usr/local

ln -s /usr/local/data/mariadb     /var/lib/mysql
ln -s /usr/local/data/mosquitto   /var/lib/mosquitto
ln -s /usr/local/data/nodered     /var/lib/nodered
ln -s /usr/local/data/zigbee2mqtt /var/lib/zigbee2mqtt

# Install standard Alpine packages needed in the IOT container

CORE='logrotate sudo tar mariadb mariadb-client npm nodejs mosquitto zigbee2mqtt zigbee2mqtt-openrc'
LIBS='libcap openssl-dev zlib-dev'
GOODIES='iputils nmap procps tree util-linux xz'

apk add --no-cache ${CORE} ${LIBS} ${GOODIES}

# The preferred method of access is PCT enter so root password is randomised, unless debugging

[[ -v $IOT_PASSWORD && -n $IOT_PASSWORD ]] || \
    IOT_RNDPASS=$(head -c 64  </dev/urandom | tr -cd 'A-Za-z0-9#%&()*+,-.:<=>?@^_~')

# Add IOT user and sudo enable.  This account will be mapped to the same UID:GID on the host.
# Node-RED runs in usermode within this account.

addgroup -g $IOT_UID $IOT_USER
echo -e "${IOT_PASSWORD}\n${IOT_PASSWORD}" | \
adduser -h /home/$IOT_USER -g '' -s /bin/bash -G $IOT_USER -u $IOT_UID $IOT_USER
ln -s /usr/local/data/nodered /home/$IOT_USER/.node-red
echo -e "$IOT_USER ALL=(ALL:ALL) NOPASSWD: ALL\n" >> /etc/sudoers

# Change root shell to bash

sed -i '/^root:/s!/ash!/bash!' /etc/passwd

# Do some post install cleanup

apk upgrade --update
npm cache verify
rm -rf /root/src /var/cache/apk/* /root/.npm /root/.node-gyp
apk search --update

# Now fixup mosquitto configs by replacing the default install config with the mounted ones.

mv /etc/mosquitto{,_old}
ln -s /usr/local/conf/mosquitto /etc/mosquitto

# Zigbee2mqtt is run as a usermode app in the zigbee2mqtt account.  It is non-standard in that conf and
# data are RW and live in the /var/lib subdir.  The confversions are used to initialise this subdir.

for f in configuration secret; do
  test -L /var/lib/zigbee2mqtt/$f.yaml && rm /var/lib/zigbee2mqtt/$f.yaml
  test -f /var/lib/zigbee2mqtt/$f.yaml || cp {/usr/local/conf,/var/lib}/zigbee2mqtt/$f.yaml
  chown -LR zigbee2mqtt:zigbee2mqtt /var/lib/zigbee2mqtt/
done

# Node-RED is installed using npm as a user mode app in the IOT user account.  It also uses
# port 80 so we need to do the setcaps on the node runtine.

su -l $IOT_USER -c /usr/local/sbin/install-nodered.sh
ln -s /usr/local/sbin/initd-nodered /etc/init.d/nodered

# Allow  user mode node execution to map Port 80
sudo setcap cap_net_raw+ep          $(readlink -f $(which node))
sudo setcap cap_net_bind_service+ep $(readlink -f $(which node))

# overwrite the default MariaDB conf

cp /usr/local/conf/mariadb/mariadb-server.cnf /etc/my.cnf.d

for s in mosquitto nodered mariadb zigbee2mqtt; do
  rc-update add $s default
  service $s start
done
