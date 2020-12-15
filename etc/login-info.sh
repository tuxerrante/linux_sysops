#! /usr/bin/env bash
#####################################
### /etc/profile.d/login-info.sh    #
#####################################

# Basic info
HOSTNAME=$(uname -n)
ROOT=$(df -Ph | grep "root " |awk '{print $4}' |tr -d '\n')

# System load
MEMORY1=$(free -t -m | grep Total | awk '{print $3" MB";}')
MEMORY2=$(free -t -m | grep "Mem" | awk '{print $2" MB";}')
LOAD1=$(awk '{print $1}'  < /proc/loadavg)
LOAD5=$(awk '{print $2}'  < /proc/loadavg)
LOAD15=$(awk '{print $3}' < /proc/loadavg)

echo "
===============================================
 - Hostname............: $HOSTNAME
 - Local IP ...........: $(hostname -i)
 - Disk Space..........: $ROOT remaining
===============================================
 - CPU usage...........: $LOAD1, $LOAD5, $LOAD15 (1, 5, 15 min)
 - Memory used.........: $MEMORY1 / $MEMORY2
 - Swap in use.........: $(free -m | tail -n 1 | awk '{print $3}') MB
===============================================
"
