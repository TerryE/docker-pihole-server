#! /bin/bash

# In-target initial provisioning of the Alpine vsFTPd LXC

cd /usr/local

# Alpine compontents needed in the FTP container

package common
package add vsftpd
package install

addAccount FTP

# Make sure the TLD /ftp hierarchy exists
ln -s /usr/local/ftp /
mkdir -p /ftp/garden /ftp/drive /ftp/porch
chown  $FTP_USER:$FTP_GROUP /ftp/garden /ftp/drive /ftp/porch

# Configure vsftpd and ensure it is started after a reboot

sed "/nopriv_user=/s/=.*/=$FTP_USER/" /usr/local/conf/vsftpd.conf > /etc/vsftpd/vsftpd.conf
echo "$FTP_USER" > /etc/vsftpd.user_list
chmod o-rwx  /etc/vsftpd/vsftpd.conf /etc/vsftpd.user_list

# Ensure that the FTP share is regularly trimed to avoid it filling

cp /usr/local/sbin/trimFTP.sh /etc/periodic/hourly/trimFTP

enableService vsftpd