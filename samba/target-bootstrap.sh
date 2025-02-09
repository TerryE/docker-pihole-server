#! /bin/bash

# In-target initial provisioning of the Alpine Samba LXC

persist samba     /var/lib/samba

package common
package add samba
package install

SMB_PASSWD="$SAMBA_PASSWORD"
unset SAMBA_PASSWORD     # Interactive account password is randomised
addAccount SAMBA
addgroup smbgroup
adduser $SAMBA_USER smbgroup

# Configure Samba  and ensure it is started after a reboot

sed "/force user /s/USER/$SAMBA_USER/" /usr/local/conf/smb.conf > /etc/samba/smb.conf
echo -e "$SMB_PASSWD\n$SMB_PASSWD\n" | smbpasswd -a $SAMBA_USER

enableService samba
