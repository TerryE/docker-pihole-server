#!/usr/bin/env bash

# This script configures and provisions a named Proxmox LXC by using four files within the
# project hiearchy directiry:
#
#    <name>configSettings  This is a sourced bash syntax file to set various build parameters
#                          and define callback hooks
#    <name>.env            Also used to declare set various build parameters.
#    <name>/bin/build-target.sh  This is called on the tartget once during provisoning.
#    <name>/bin/startup..sh  If this file exists then it is added as a cron root @reboot target
#                          and is called on LXC startup with normal crontab sequence precedence
#
# Files within the project ifile tree are control under git.  Note that the .env files are in
# the .gitignore category are are not published to GitHub.  This are used to maintain secret /
# private data that might compromise security if published publically.
#
# Note that this process is broken into funtion chunks, so variables are only global for a reason.

function setupErrorHandling {
    set -Eeuo pipefail
    trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
    function error_handler {
        local line_no="$1" cmd="$2" status="$?"
        local error_message="✗ error in line $line_no: exit code $status: while executing command $cmd"
        echo -e "\n$error_message\n"
    }
    function msg_info  { echo -e " - $1"; }
    function msg_error { echo -e " ✗ $1"; exit 1; }
    function msg_ok    { echo -e " ✓ $1"; }
}

function setRoot {
    SCRIPT_PATH="$(dirname $(realpath $0))" # This script is in the project bin directory
    PROJECT_PATH="$(dirname $SCRIPT_PATH)"
    ROOT_DIR=$1
    ROOT_PATH="$PROJECT_PATH/$ROOT_DIR"
    DATA_PATH=$(realpath $PROJECT_PATH/.data)
    # Check root path is valig because all should include a .env file and a bin sub directory.
    [[ -f "$ROOT_PATH/.env" && -d "$ROOT_PATH/bin" ]] ||
         msg_error "Usage is build-LXR.sh <subdir> [<options>]"
}

function setOptionDefaults {
    # The build proces uses a number of global parameters. The defaults for these are set here, but
    # note the convention that none include an underscore.  Such bareword parameters can be
    # subsequently overriden by .env, configSettings or commandline option

    APP=""
    MAP="1"
    REBUILD=""
    VERBOSE="no"
    
    BRIDGE="vmbr0"
    CORES=1
    CTID=""
    DISABLEIP6="1"
    DISK="0.5"
    DNS=$(grep nameserver /etc/resolv.conf | head -1 |awk '{ print $2; }')
    DOMAIN="home"
    FEATURES="nesting=1"
    GATEWAY=""
    HOST=""
    MACADDR=""
    MTU=""
    NET="dhcp"
    OSTYPE="alpine"
    OSVERSION="3.17"
    PASSWORD="$(head -c 128 /dev/urandom| tr -cd "[:alnum:]#$%&()*+,-.:<=")"
    PRIVTYPE=1
    RAM=128
    SSHKEYS=$(realpath ~/.ssh/authorized_keys)
    VLAN=""
}

function setEnvOptOverrides {
    # The container's .env and configSettings file can override the above global parameters.  If the
    # OPT_xxxx settings are used, then this function logs  parameters and updated values.  Note that
    # the configSettings are often defaults so the file can be omitted, but everyone has secrets ;-?
    source $ROOT_PATH/.env
    [[ -f $ROOT_PATH/configSettings ]] && source $ROOT_PATH/configSettings

    for v in ${!OPT_*}; do
        declare -n from=$v to=${v:4}
        [[ -v to ]] || msg_error "Unknown option $V"
        msg_info "${v:4} changed from default ($to) to $from"
        to=$from
    done
}

function setCommandLinevOptOverrides {
    # Command line options (e.g. --ram 256) can override the corresponding setup option
    while [[ $# -gt 0 ]]; do
        declare -u name=${1:2}; declare -n var=$name; declare val="1"
        [[ ${1:0:2} = "--"  && -v var  ]] || msg_error "Unknown option $1"
        shift
        [[ $# -gt 0 && ${1:0:2} != "--" ]] && ( val=$1; shift )
        msg_info "$name changed from $var to $val"
        var=$val
    done
}
function runHhook {
    # the configSettings script can define a number of callback hooks which can be invoked
    # during this build process, E.g. "runHook someHook fred" will run the function HOOK_someHook
    # if it has been defined in configSettings  with the parameter fred.  The bash syntax for
    # manipulating functions by references is arcaine, but it does the job.
    local v=$1; shift;
    (declare -F HOOK_$v) 2>&1 >/dev/null && (HOOK_$v $*);
    return 0
}

function fixupVariableDefaults {
    # Some variables need there values fixed up
    [[ $VERBOSE = "1" ]] && VERBOSE="yes"
    [[ $VERBOSE = "yes" ]] && set -x
    [[ -z $CTID ]] && CTID=$(sudo pvesh get /cluster/nextid)
    [[ -z $HOST ]] && HOST=$ROOT_DIR
    [[ $FEATURES =~ keyctl= || $PRIVTYPE = "0" ]]  || FEATURES="${FEATURES},keyctl=1"
}

function map_UID {
    # Most LXCas have one UID:GID mapped to the same UID:GID on the host
    local -i ctid=${1:-$CTID} id=${2:-1000} base=${3:-100000}
    local -i idm1=$((id-1)) id_1=$((id+1)) base_id_1=$((base+id+1))
    local -i baseres=$((0x10000-id_1))
    grep -q ":$id:" /etc/subuid  ||
        echo "root:$id:1" | sudo tee -a /etc/subuid > /dev/null
    grep -q ":$id:" /etc/subgid  ||
        echo "root:$id:1" | sudo tee -a /etc/subuid > /dev/null

    cat << END | sed 's/^ *//' | sudo tee -a /etc/pve/lxc/$CTID.conf > /dev/null
        lxc.idmap = u 0 $base $id
        lxc.idmap = u $id $id 1
        lxc.idmap = u $id_1 $base_id_1 $baseres
        lxc.idmap = g 0 $base $id
        lxc.idmap = g $id $id 1
        lxc.idmap = g $id_1 $base_id_1 $baseres
END
    runHhook mapping
}

function create_LXC {
    # Create the LXK.  Tteck (tteckster) already has a script for this, so I use it to do the
    # work.  (See source for its MIT License).
    local tteck_ver="tteck/Proxmox/44c614f65dc849b4331920926b1f15e55b1de2bb/ct"

    local -i ctid=${1:-$CTID}

    # If the --rebuild flag is set, then destry the previous instance of the LXR
    (( REBUILD == 1 )) && [[ -f "/etc/pve/lxc/$ctid.conf" ]] && (
        msg_info "Remove the old container version"
        sudo pct destroy $ctid --force 1
        )
    local TEMP_DIR=$(mktemp -d); pushd $TEMP_DIR >/dev/null

    msg_info "Createthe new LXC Container"
 
# The following exported variables are parameters to Tteck's createLXC script to screate the
# blank template LXC, just 'cos that's the way he does it. Not worth reinventing the wheel :-)
    local PCT_OPTIONS=$(echo "
        --hostname $HOST
        --features $FEATURES
        --net0 name=eth0,bridge=${BRIDGE},ip=${NET}\
                ${MACADDR:+,hwaddr=$MACADDR}${GATEWAY:+,gw=$GATEWAY}\
                ${VLAN:+,tag=$VLAN}${MTU:+,mtu=$MTU}
        --onboot 1
        --cores $CORES
        --memory $RAM
        --unprivileged $PRIVTYPE
        ${DOMAIN:+--searchdomain $DOMAIN}
        ${DNNS:+--nameserver $DNS}
        ${PASSWORD:+--password $PASSWORD}
        ${SSHKEYS:+--ssh-public-keys $SSHKEYS}" |
            xargs | sed 's/  *,/,/' )

    wget -qLO - https://raw.githubusercontent.com/$tteck_ver/create_lxc.sh |
      sudo VERBOSE=$VERBOSE \
        CTID=$CTID \
        PCT_HOST=$HOST \
        PCT_OSTYPE=$OSTYPE \
        PCT_OSVERSION=$OSVERSION \
        PCT_DISK_SIZE=$DISK \
        PCT_OPTIONS="${PCT_OPTIONS}" \
        bash -

    # If the data directory exists then add it to options at mp3
    [[ -d $DATA_PATH/$ROOT_DIR ]] &&
        local datadir=$(readlink -f $DATA_PATH/$ROOT_DIR)

    sudo pct set $ctid \
        --description "# ${OSTYPE} ${OSVERSION} ${APP} LXC" \
        --mp1 $ROOT_PATH/bin,mp=/usr/local/sbin,ro=1,backup=0 \
        --mp2 $ROOT_PATH/conf,mp=/usr/local/conf,ro=1,backup=0 \
         ${datadir:+--mp3 $datadir,mp=/usr/local/data,backup=0}

    popd >/dev/null
    [[ -n "$TEMP_DIR" ]] && rm -R $TEMP_DIR
  
}

function start_LXC {
    local -i ctid=${1:-$CTID}
    msg_info "First start of the LXC Container"
    sudo pct start $CTID
}

function bootstrap_LXC {
    local -i ctid=${1:-$CTID}
    msg_info "Initial Provision of the LXC Container"
    [[ -e $ROOT_PATH/.env ]] &&
        sudo pct push $ctid $ROOT_PATH/.env  /tmp/.env --user 0 --perms 755
    sudo pct exec  $ctid /usr/local/sbin/target-bootstrap.sh
    sudo pct reboot $ctid
    sleep 5
    local IP=$(sudo pct exec $ctid ip a s dev eth0 | awk '/inet / {print $2}' | cut -d/ -f1)
    msg_info "$APP Build for $HOST($ctid),IP=$IP completed successfully "
    return 0
}

# =================================== Effective Main Entry # ===================================

# Set up execution context

setupErrorHandling

groups | grep -q sudo || msg_error "Run from sudo account"

setRoot            "$1"
shift

setOptionDefaults

# Load the contain's .env and configSetting and do any Option overrides.  This will
# also establish any callback hooks specific to this container.

setEnvOptOverrides
setCommandLinevOptOverrides $*
fixupVariableDefaults

create_LXC    $CTID
map_UID       $CTID
start_LXC     $CTID
bootstrap_LXC $CTID

# vim: autoindent expandtab tabstop=4 shiftwidth=4
