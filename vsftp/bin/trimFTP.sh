#! /bin/sh

# Use du on /ftp to calculate free space in Mb, and loop until this at least 4096 Md

freeMbStart=$(df  -m  /ftp | tail -1 | awk '{print $3;}')
freeMb=$freeMbStart

while [ "$freeMb" -lt 4096 ] ; do
  #
  # Find three oldest /ftp/<camera>/YYYY/MM/DD directories abd remove them
  #
  oldDirs=$(find /ftp/*/20*/*/* -type d | sort  -t / -k 5,6 | head -3)
  [ -z "$oldDirs" ] && exit  # Make sure list isn't empty
  rm -R $oldDirs
  
  freeMb=$(df  -m  /ftp | tail -1 | awk '{print $3;}')  # recalculate freeMb
done

[ "$freeMbStart" -lt "$freeMb"  ] && \
  logger -t trimFTP "$((freeMbStart -freeMb))Mb trimmed from /ftp; ${freeMb} free"