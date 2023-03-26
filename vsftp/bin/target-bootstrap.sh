#! /bin/ash

# In-target initial provisioning of the Alpine vsFTPd LXC

cd /usr/local

# Alpine compontents needed in the FTP container
CORE='bash logrotate vsftpd strace mandoc vsftpd-doc'
GOODIES='iputils nmap procps tar tree util-linux xz'
apk add --no-cache ${CORE}  ${GOODIES}

source /tmp/.env

# Add 1000:1000 as $FTP_USER.  This will be mapped to the same UID:GID on the host.
addgroup -g $FTP_UID $FTP_USER
echo -e "${FTP_PASSWORD}\n${FTP_PASSWORD}" | \
  adduser -h /ftp -g '' -s /bin/bash -G $FTP_USER -H -u $FTP_UID $FTP_USER

# Change root shell to bash
sed -i '/^root:/s!/ash!/bash!' /etc/passwd

# Make sure the TLD /ftp hierarchy exists
ln -s /usr/local/data /ftp
mkdir -p /ftp/garden /ftp/drive /ftp/porch
chown -R $FTP_USER:$FTP_USER /ftp/garden /ftp/drive /ftp/porch

# Configure vsftpd and ensure it is started after a reboot

sed "/nopriv_user=/s/=.*/=$FTP_USER/" /usr/local/conf/vsftpd.conf > /etc/vsftpd/vsftpd.conf
echo "$FTP_USER" > /etc/vsftpd.user_list
chmod o-rwx  /etc/vsftpd/vsftpd.conf /etc/vsftpd.user_list

rc-update add vsftpd default

# Ensure that the FTP share is regularly trimed to avoid it filling

cp /usr/local/sbin/trimFTP.sh /etc/periodic/hourly/trimFTP
