#!/bin/bash

# Invoke this script from project root folder
CONFIG_FILE=./config/config.cfg

# How many seconds before file is deemed "older"
OLDTIME=600

# Get current and file times
CURTIME=$(date +%s)
FILETIME=$(stat $CONFIG_FILE -c %Y)
TIMEDIFF=$(( CURTIME - FILETIME ))

# Check if file older
if [ $TIMEDIFF -gt $OLDTIME ]; then
    echo " WARNING: Old configuration file. ./config/config.cfg is older than $OLDTIME s"
    
    # 2>/dev/tty is needed to flush the line on the terminal
    #   otherwise it is not visible
    read -r -n2 -p " Are you sure you want to continue? (y/n) > " config_answer 2>/dev/tty  
    if [[ $config_answer == "y" || $config_answer == "Y" ]]; then
        return
    else
        echo " Exiting"
        exit 77
    fi
else
    echo " Configuration file was updated recently" 
    
fi