#! /bin/bash
#
#  Note that since the Node-RED instillation is mapped to persistent data, this script will normally do an upgrade
#  This script is run in the $IOT_USER account
exec 3>/dev/null

NODERED_USER="$USER"
NODERED_GROUP="$USER"
NODERED_HOME="$HOME"
cd $NODERED_HOME

EXTRANODES=$(grep '"name": "node-red-node'  .node-red/.config.nodes.json | cut -d \" -f 4)

source <(grep PRETTY_NAME /etc/os-release)

echo -e "\nRunning Node-RED Install for user $NODERED_USER at $NODERED_HOME on $PRETTY_NAME\n"
echo -e "Versions: node: $(node -v 2>&3)"
echo -e "          npm:  $(npm -v 2>&3)\n"

sudo npm install -g  --unsafe-perm --no-progress --no-update-notifier --no-audit \
                 --no-fund --loglevel=error  node-red@latest 2>&1

mkdir -p .node-red/node_modules

cd .node-red   2>&3 >&3

# Node red creates a standard .config.runtime.json which overrides the credentialSecret so rm it.
rm .config.runtime.json
test -f settings.js && rm settings.js
sudo ln -sf /usr/local/conf/nodered/settings.js

sudo chown -Rf $NODERED_USER:$NODERED_GROUP node_modules 2>&3 >&3

sudo npm config set update-notifier false 2>&3 >&3

echo "Installing extra nodes: $EXTRANODES"
npm install --unsafe-perm --save --no-progress --no-update-notifier --no-audit --no-fund $EXTRANODES 2>&1

