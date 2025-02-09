#! /bin/bash

# In-target initial provisioning of the IoT LXC running node.js, Node-RED, mariadb, mosquitto and Zigbee2MQTT

# Symlink persistent folders to host bind mount to preserve over rebuild

persist mariadb     /var/lib/mysql
persist mosquitto   /var/lib/mosquitto
persist nodered     /var/lib/nodered
persist zigbee2mqtt /var/lib/zigbee2mqtt
persist user        /home/$IOT_USER

addAccount IOT

# Install standard Alpine packages needed in the IOT container

package common
package add mariadb mariadb-client mosquitto mosquitto-openrc nodejs npm
package add zigbee2mqtt zigbee2mqtt-openrc git libcap openssl-dev zlib-dev
package install

# Confgure MariaDb: make db visible to SQL port visible to localhost
sed -i "/\[mysqld\]/a port=3306" /etc/my.cnf.d/mariadb-server.cnf
sed -i "/skip-networking/s/^/#/" /etc/my.cnf.d/mariadb-server.cnf

# Confgure MQTT: use MQTTUSER_* variables to set up the passwd file
cp -r conf/mosquitto /etc

( for u in ${!MQTTUSER_@}; do
      declare -l user="${u:9}"; declare -n val="$u"
      echo "$user:$val"
  done ) > /etc/mosquitto/passwd; chmod 600 /etc/mosquitto/passwd
mosquitto_passwd -U /etc/mosquitto/passwd

# Confgure MariaDb, MQTT & Zigbee2MTT
[[ -f /var/lib/zigbee2mqtt/configuration.yaml ]] ||
    cp  {conf,/var/lib}/zigbee2mqtt/configuration.yaml
sed 's/^ *//' << EOD > /etc/zigbee2mqtt/secret.yaml
    mqtt_password: $MQTTUSER_ZIGBEE
    network_key:   $ZIGBEE_NEYKEY
    pan_id:        $ZIGBEE_PANID
EOD
chmod 660 /etc/zigbee2mqtt/secret.yaml
chmod 664 /etc/zigbee2mqtt/configuration.yaml
chown root:zigbee2mqtt /etc/zigbee2mqtt/*.yaml

# Node-RED is installed using npm as a user mode app in the IOT user account.
# It also uses port 80 so we need to do the setcaps on the node runtine.

su -l $IOT_USER -c /usr/local/sbin/install-nodered.sh
ln -s /usr/local/sbin/init.d/nodered /etc/init.d/nodered

# Allow  user mode node execution to map Port 80
setcap cap_net_raw+ep          $(readlink -f $(which node))
setcap cap_net_bind_service+ep $(readlink -f $(which node))

mkdir /var/log/nodered; chown nodered /var/log/nodered

enableService mosquitto nodered mariadb zigbee2mqtt
