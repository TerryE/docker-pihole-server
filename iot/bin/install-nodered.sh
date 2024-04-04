#! /bin/bash
#
#  Note that since the Node-RED instillation is mapped to persistent data, this script will normally do an upgrade
#
exec 3>/dev/null

NODERED_USER="$USER"
NODERED_GROUP="$USER"
NODERED_HOME="$HOME"

EXTRANODES='
    node-red-contrib-credentials node-red-contrib-cron
    node-red-contrib-fs node-red-contrib-home-assistant-websocket
    node-red-contrib-time-range-switch
    node-red-dashboard node-red-node-mysql node-red-node-ping
    node-red-node-random node-red-node-smooth node-red-node-ui-duallineargauge
    node-red-node-ui-lineargauge node-red-node-ui-list node-red-node-ui-table
'

cd $NODERED_HOME
source <(grep PRETTY_NAME /etc/os-release)
echo -e "\nRunning Node-RED Install for user $NODERED_USER at $NODERED_HOME on $PRETTY_NAME\n"
echo -e "Versions: node: $(node -v 2>&3)"
echo -e "          npm:  $(npm -v 2>&3)\n"

sudo npm cache verify
set -vx
sudo npm install -g  --unsafe-perm --no-progress --no-update-notifier \
                 --no-audit --no-fund --loglevel=error \
                 node-red@latest 2>&1
mkdir -p .node-red/node_modules
cd .node-red   2>&3 >&3

# Node red creates a standard .config.runtime.json which overrides the credentialSecret so rm it.
rm .config.runtime.json
test -f settings.js && rm settings.js

sudo chown -Rf $NODERED_USER:$NODERED_GROUP node_modules 2>&3 >&3
sudo ln -sf /usr/local/conf/nodered/settings.js

sudo npm config set update-notifier false 2>&3 >&3

echo "Installing extra nodes: $EXTRANODES"
npm install --unsafe-perm --save --no-progress --no-update-notifier --no-audit --no-fund $EXTRANODES 2>&1

