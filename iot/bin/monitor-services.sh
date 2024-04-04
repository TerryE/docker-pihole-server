#!/bin/bash
# Started on Daily (2AM) Cron job  
declare -i i=1440
while [[ $i > 0 ]]; do
    ZPID=$(pgrep -G zigbee2mqtt)
    NPID=$(pgrep -G nodered)
    if [[ -z $ZPID ]]; then
        service zigbee2mqtt restart
    elif [[ -z $NPID ]]; then
        service $nodered restart
    else
        while [[ -d /proc/$ZPID ]] && [[ -d /proc/$NPID ]] && [[ $i > 0 ]]; do
            sleep 60
            ((i = i-1))
        done
    fi
done
