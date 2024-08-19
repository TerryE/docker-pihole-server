#! /bin/env -iS HOME=${HOME} PWD=${PWD} PATH="/usr/bin:/bin" TERM="minimal" bash --noprofile --norc
#
# This build script is written to be run at normal privilege from a sudo-enabled account.  Hence
# privileged functions are "sudoed", but this means than any environment must be explicitly passed
# to them.  This also means that it can't use direct piping to root-owned files, to append to them,
# and so sudo tee is used instead.
#
# Note that this build process is broken into funtion chunks, so variables are only global if
# there is a reason for this.
#
# See README.md for build documentation

declare -A var_list

function setupErrorHandling {
    # The -Ee options are really useful for trapping errors, but the downside it that the script
    # must explicitly handle cases where a 1 status is valid, e.g. by adding a "|| :" pipe.
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
    # This script is in the project bin directory, so paths are resolved relative to this
    SCRIPT_PATH="$(dirname $(realpath $0))"
    PROJECT_PATH="$(dirname $SCRIPT_PATH)"
    ROOT_DIR=$1
    ROOT_PATH="$PROJECT_PATH/$ROOT_DIR"
    DATA_PATH=$(realpath $PROJECT_PATH/.data)
    # Error if root path is invalid because it must include all mandatory files.
    [[ -f $ROOT_PATH/.env && -f $ROOT_PATH/configSettings && $ROOT_PATH/target-bootstrap.sh ]] ||
         msg_error "Usage is build-LXR.sh <LXC name> [<options>]"
}

function setLXCoptionDefaults {
    # The build proces uses a number of global parameters. The defaults for these are set
    # here, but note the convention that none include an underscore.  These parameters
    # can be subsequently overriden by .env, configSettings or a command line option.
    
    CORES=1 DISABLEIP6=1 MAP=0 ONBOOT=1 PRIVTYPE=1 RAM=128 REBUILD=0
    APP="" CHECKTEMPLATE="" CTID="" GATEWAY="" HOST="" MACADDR="" MTU=""
    VERBOSE="no"
    DISK="0.5" DISKSTORE="local-lvm" TEMPLATESTORE="local"
    BRIDGE="vmbr0" FEATURES="nesting=1" NET="dhcp"
    OSTYPE="alpine" OSVERSION="3.19"
    DOMAIN="home" HOST="$ROOT_DIR"
    CTID=$(sudo pvesh get /cluster/nextid)
    DNS=$(grep nameserver /etc/resolv.conf | head -1 |awk '{ print $2; }')
    SSHKEYS=$(realpath $HOME/.ssh/authorized_keys)
}

function setEnvOptOverrides {
    # The container's .env and configSettings file can override the above global parameters.
    # If the OPT_xxxx settings are used, then the parameters and updated values are logged.
    source $ROOT_PATH/.env
    source $ROOT_PATH/configSettings

    for _v in ${!OPT_*}; do
        local -n from=$_v to=${_v:4}
        [[ -v to ]] || msg_error "Unknown option $_v"
        [[ $to = $from ]] && continue
        msg_info "${_v:4} changed from default ($to) to $from"
        to=$from
    done
}

function setCommandLinevOptOverrides {
    # Command line options (e.g. --ram 256) can override the corresponding setup option
    while (( $# > 0 )) ; do
        local -u name=${1:2}
        local -n var=$name
        local    val="1"
        [[ ${1:0:2} = "--"  && -v var  ]] || msg_error "Unknown option $1"
        shift
        # if the value is omitted then it defaults to 1
        [[ $# -gt 0 && ${1:0:2} != "--" ]] && ( val=$1; shift )
        [[ $var = $val ]] && continue
        var=$val
        msg_info "$name changed from $var to $val"
    done
}

function runHook {
    # the configSettings script can define a number of callback hooks which can be invoked
    # during this build process, E.g. "runHook someHook fred" will run the function
    # HOOK_someHook if it has been defined in configSettings with parameter fred.
    local _v=HOOK_$1; local -F $_v &>/dev/null || return 0;
    shift; $_v $*
}

function map_UID {
    # Most LXCas have one UID:GID mapped to the same UID:GID on the host.
    # This function updates the suduid, subgid and lxc conf files if needed
    local -i ctid=${1:-$CTID} id=${2:-1000} base=${3:-100000}
    local -i idm1=id-1 idp1=id+1
    local -i base_idp1=base+id+1 baseres=0x10000-id-1

    grep -q ":$id:" /etc/subuid  || sudo sed -i "\$a root:$id:1" /etc/subgid
    grep -q ":$id:" /etc/subgid  || sudo sed -i "\$a root:$id:1" /etc/subgid
    sudo sed -i -f - /etc/pve/lxc/$CTID.conf <<END
        \$a lxc.idmap = u 0 $base $id
        \$a lxc.idmap = u $id $id 1
        \$a lxc.idmap = u $idp1 $base_idp1 $baseres
        \$a lxc.idmap = g 0 $base $id
        \$a lxc.idmap = g $id $id 1
        \$a lxc.idmap = g $idp1 $base_idp1 $baseres
END
}

function get_template {
    # Lookup the OS template name used for making the LXC.  If the command line
    # options --checktemplate is set, then udpate the refesh the template list
    # and download a new version if one exists.
    local os=$1
    if (( CHECKTEMPLATE==1 )); then
        # Refresh the template list and download new template if nec.
        sudo pveam update >/dev/null

        local template= $(sudo pveam available --section system |
                          awk '{print $2}' |  grep "^$os" | tail -1) ||
            msg_err "Unable to find template for $os"

        sudo pveam list $TEMPLATESTORE | grep -q $template || {
            sudo pveam download $TEMPLATESTORE $template >/dev/null ||
            msg_error "A problem occured while downloading the LXC template."
            }
    else
        # Retrieve the template name from local storage
        local template=$(sudo pveam list  $TEMPLATESTORE |
            awk -F '[/ ]' '{print $2}' |  grep "^$os" | tail -1) ||
                msg_err "Unable to find template for $os"
    fi
    echo "${TEMPLATESTORE}:vztmpl/$template"
}

function create_LXC {
    local -i ctid=${1:-$CTID}

    # If the --rebuild flag is set, then destroy the previous instance of the LXR
    if [[ -v REBUILD ]] && (( REBUILD == 1 )) && [[ -f "/etc/pve/lxc/$ctid.conf" ]]; then
        msg_info "Remove the old container version"
        sudo pct shutdown $ctid  || echo "$ctid not running"
        sudo pct destroy $ctid --force 1
    fi

    msg_info "Creating the LXC Container"
    
    # Net0 is complex so build up first

    local net0=$(echo "name=eth0,bridge=${BRIDGE},ip=${NET}" \
                "${MACADDR:+,hwaddr=$MACADDR}" \
                "${GATEWAY:+,gw=$GATEWAY}" \
                "${VLAN:+,tag=$VLAN}" \
                "${MTU:+,mtu=$MTU}"  | sed 's/  *,/,/' )
    
    # Add mount points that exist

    local mpb="$ROOT_PATH/bin,mp=/usr/local/sbin,ro=1,backup=0"
    local mpc="$ROOT_PATH/conf,mp=/usr/local/conf,ro=1,backup=0"
    local mpd="$(readlink -f $ROOT_PATH/data),mp=/usr/local/data,backup=0"

    [[ -d  $ROOT_PATH/bin ]]  && mps+=( "--mp${#mps[@]} $mpb")
    [[ -d  $ROOT_PATH/conf ]] && mps+=( "--mp${#mps[@]} $mpc")
    [[ -d  $ROOT_PATH/data ]] && mps+=( "--mp${#mps[@]} $mpd")
    
    runHook customMounts mps

    # Now create the LXC with options as per the 'pct create' man page.  Note root
    # access is via pct enter or certificated SSH, so password is a hidden random
    # string to prevent root+password login.

    [[ $FEATURES =~ keyctl= || $PRIVTYPE = "0" ]]  || FEATURES="${FEATURES},keyctl=1"

    sudo pct create $ctid $(get_template ${OSTYPE}-${OSVERSION:-}) \
        --description "# ${OSTYPE} ${OSVERSION} ${APP} LXC" \
        --hostname $HOST \
        --arch $(dpkg --print-architecture) \
        --rootfs ${DISKSTORE}:${DISK} \
        --features $FEATURES \
        --onboot $ONBOOT \
        --cores $CORES \
        --memory $RAM \
        --unprivileged $PRIVTYPE \
        --ostype $OSTYPE \
        --net0 $net0 \
        --password "$(head -c 128 /dev/urandom| tr -cd "[:alnum:]%&()*+,-.:<=")" \
        ${mps[@]} \
        ${DOMAIN:+--searchdomain $DOMAIN} \
        ${DNS:+--nameserver $DNS} \
        ${SSHKEYS:+--ssh-public-keys $SSHKEYS}

    msg_ok "LXC Container $ctid was successfully created."
}

function start_LXC {
    local -i ctid=${1:-$CTID}
    msg_info "First start of the LXC Container"
    sudo pct start $ctid
}

function bootstrap_LXC {
    local -i ctid=${1:-$CTID}
    msg_info "Initial Provision of the LXC Container"
    
    # Alpine doesn't have bash installed by default, so that GNU bash can be used
    # as the standard scripting engine across all platforms
    
    local isdebian=1
    if [[ $OSTYPE = "alpine" ]]; then
        isdebian=""
        sudo pct exec $ctid -- /bin/ash - <<< "
            /sbin/apk add --no-cache bash
            /bin/sed -i '/^root:/s!/ash!/bash!' /etc/passwd"
    fi

    (   echo "cd /usr/local; isdebian=$isdebian"
        # Context Variables
        for _v in "${!var_list[@]}"; do
            [[ "${var_list[$_v]}" == "skip" ]] && continue
            declare -p $_v | cut -d \  -f 3-
        done
        # Common Target Functions
        for _f in $(declare -F |cut -d \  -f 3| grep ^tgt_); do
            declare -f $_f|sed '1s/^tgt_//'; echo  ""
        done
        # The Bootstrap script
        cat $ROOT_PATH/target-bootstrap.sh
    ) > /tmp/$$.sh
    sudo pct exec $ctid hostname
    sudo pct push $ctid /tmp/$$.sh /tmp/$$.sh
    sudo pct exec $ctid -- /bin/bash /tmp/$$.sh
    sudo pct reboot $ctid

    local IP=''
    while [[ -z $IP ]]; do
        sleep 1  # Allow container to initialise
        IP=$(sudo pct exec $ctid ip a s dev eth0 | awk '/inet /{sub(/\/.*/,""); print $2}')
    done
    msg_info "$APP Build for $HOST($ctid), IP=$IP completed successfully in ${SECONDS} sec"
    return 0
}

function newVars {
    # Track any variables added by this scriot as these will be shared with build/-target,sh
    local list=$(declare -p|cut -d\  -f 3|cut -d= -f 1)
    for _v in $list; do
        [[ -v var_list["$_v"] ]] && continue
        [[ "$_v" =~ ^_.* ]] && continue
        var_list["$_v"]=$1
    done
}

# ================================= Common Target Functions ====================================

function tgt_package {
    # apt-get / apk neutral package installer
    local action=$1 ; shift
    case $action in
      common)
        package_list=(iputils logrotate nmap procps openssh-server rsync sudo tar tree util-linux xz)
        [[ -f /etc/debian_version ]] && package_list=(nmap rsync tree sudo xz-utils) ;;
      php)
        for _p in $@; do package_list+=("php81-$_p"); done ;;
      add)
        package_list+=($@) ;;
      install)
        if test $isdebian; then
            sed -i 's/deb.debian.org/ftp.uk.debian.org/g' /etc/apt/sources.list
            apt-get update; apt-get install -y ${package_list[@]}
            service ssdh stop
        else  # alpine
            apk add --no-cache  ${package_list[@]}
        fi ;;
    esac
}

function tgt_addAccount {
    # Add LXC user account inheriting authorized_keys from ~root.  Note that the
    # password by default is randomised, limiting use to certificated SSH or
    # 'su -l' from the root account
    
    local -u USER=$1
    local -n user="${USER}_USER" passwd="${USER}_PASSWORD" uid="${USER}_UID" gid="${USER}_GID"
    local    sshdir="/home/$user/.ssh"
    
    if test $isdebian; then
        addgroup -gid ${gid:-1000} $user
        adduser --shell /bin/bash --uid $uid --gid ${gid:-1000} \
                --gecos '' --disabled-password  $user
    else  # alpine
        [[ -v $passwd && -n $passwd ]] ||
            local passwd=$(head -c 64  </dev/urandom | tr -cd 'A-Za-z0-9#%&()*+,-.:<=>?@^_~')
        addgroup -g ${uid:-1000} $user
        echo -e "${passwd}\n${passwd}" | \
            adduser -h /home/$user -g '' -s /bin/bash -G $user -u ${uid:-1000} $user
    fi
    
    echo -e "$user ALL=(ALL:ALL) NOPASSWD: ALL\n" > /etc/sudoers
    mkdir -m 700 $sshdir
    cp -p /root/.ssh/authorized_keys $sshdir
    chown $user:$user -R $sshdir
}

function tgt_persist {
    # Copy $target to DATA subdir if it doesn't exist (first build), then
    # replace $target by a symlink to the DATA subdir
    local dataDir="/usr/local/data/$1" target="$2"
    [[ -d $dataDir ]] || cp -a $target $dataDir
    rm -Rf $target
    ln -s $dataDir $target
}

function tgt_enableService {
   IP=$(ip a s dev eth0 | awk '/inet /{sub(/\/.*/,""); print $2}')
   echo "$APP Build for $HOST (ctid:$CTID), IP=$IP" > /etc/motd
    # Enable the required services
    persist ssh /etc/ssh
    
    if test $isdebian; then return; fi
    for s in sshd $@; do
        rc-update add $s default
        service $s start
    done
}

# =================================== Effective Main Entry =====================================
function _main_ {
    
    setupErrorHandling
    groups | grep -q sudo || msg_error "Run from sudo account"
    
    newVars skip
    
    # Load the container's .env and configSettings and do any Option overrides.  This
    # will also establish any callback hooks specific to this container.

    setRoot "$1";  shift
    setLXCoptionDefaults
    setEnvOptOverrides
    setCommandLinevOptOverrides $*
    [[ $VERBOSE  =~ (1|yes|YES) ]] && set -x
    newVars print
    contextVars="$(newVars print)"
    echo $contextVars
    
    create_LXC    $CTID
    [[ -v MAP ]] && (( $MAP == 1 )) && map_UID $CTID
    runHook       customMapping
    start_LXC     $CTID
    bootstrap_LXC $CTID
}

_main_ $@

# vim: autoindent expandtab tabstop=4 shiftwidth=4
