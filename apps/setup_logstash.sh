#!/bin/bash
### Install function for logstash

### Input arguments 
#		$1=[0=is_to_install] 
#		$2=[installation path] 
# 		$3=[bind_address]
#		$4=[bind_port]
#		$5=[data path]
#		$6 "MONITORING"
### Output variables 
#   status=[0=installed 1=not_installed] 
#   service_label=[name_of_action/service]
function logstash {
	log "===================== LOGSTASH =====================" "both"
	local is_to_install=$1
	local logstashport=$4
	local auxdatapath=$5
	local auxinstallpath=$2
	service_label="logstash"
	
    cmessage $service_label
	
    archivediscover $service_label "" "rpm"

    if [ "$is_to_install" -ne 0 ]; then
		log "$err_inst_fail" "both"
		return 1
	fi

    ############################################
	#### Firewall
    _open_port "$logstashport/tcp"

    ############################################
	#### CHECK JAVA PRESENCE
    if [ -z "$javapath" ]; then
        setup_java 0 "$installationpath" "N/A" "N/A" $auxdatapath
    fi

    ############################################
	#### CHECK LOGSTASH INSTALLER PATH
    service_label="logstash"
    archivediscover $service_label "" "rpm"     # defines $path

    ############################################
	#### INSTALL
    log "$info_inst_start" "both"

    #### INSTALL RPM
    yum -y --quiet remove logstash 2>/dev/null
    yum -y --quiet install "$path" 

    ckcapsule=$(rpm --query logstash |wc -l)
    if [ "$ckcapsule" -lt 1 ] ; then
		log "$err_inst_fail" "both"
        return 1
	fi    
    log "$info_inst_done" "both"

    ############################################
	#### DIRS and OWNERSHIPS
    local target_path="$2/$service_label"
    local log_path="$logpath/$service_label"
    local data_path="$auxdatapath/$service_label"
    mkdir -p $log_path $data_path $target_path
    chown -R logstash. $log_path $data_path $target_path

    whereis logstash > "$target_path/info"
    echo "DATA: $data_path" >> "$target_path/info"
    echo "LOG: $log_path"   >> "$target_path/info"

    ############################################
	#### MAIN CONFIGURATIONS
    log "$info_conf_start" "both"

    #### EXTRA JAVA AND STARTUP OPTIONS
    mkdir -p /etc/logstash/
    # cp $runpath/config/logstash_java_opts /etc/logstash/
    # mv /etc/logstash/logstash_java_opts /etc/logstash/java_opts
    cp $runpath/config/logstash_startup.options /etc/logstash/startup.options
    
    logstash_startup_file="/etc/logstash/startup.options"    
    sed -i "s|#JAVACMD=.*|JAVACMD=$javapath|" $logstash_startup_file
    sed -i "s|LOG_PATH|$log_path|g" $logstash_startup_file
    #sed -i "s|LS_JAVA_OPTS=.*|LS_JAVA_OPTS=\"@/etc/logstash/java_opts\"|" $logstash_startup_file
    
    logstash_yml="/etc/logstash/logstash.yml"
    cp $runpath/config/logstash.yml     $logstash_yml
    sed -i "s|DATA_PATH|$data_path|g"   $logstash_yml
    sed -i "s|LOG_PATH|$log_path|g"     $logstash_yml
    
    sed -i "s|-Xms1g|-Xms4g|" /etc/logstash/jvm.options 
    sed -i "s|-Xmx1g|-Xmx4g|" /etc/logstash/jvm.options 

    chown -R logstash. /etc/logstash/

    #### 
    service_label="elk_stack_conf"
    archivediscover $service_label
    
    tarfolder "$path"
    tar xzf "$path" -C $temppath
    cd $temppath/logstash 	 || { log "ERROR | cd fail."; exit 77; }
    cp logstash.conf /etc/logstash/conf.d/
    chown -R logstash. /etc/logstash/

    # cd /etc/logstash/conf.d/ || { log "ERROR | cd fail."; exit 77; }
    # editline2 "3" "logstash.conf" "\    port => $logstashport"
    # editline2 "305" "logstash.conf" "\                        hosts => \[\"http://$elasticsearchmonitorhost:$elasticsearchmonitorport\"\]"
    # editline2 "310" "logstash.conf" "\                        hosts => \[\"http://$elasticsearchmonitorhost:$elasticsearchmonitorport\"\]"
    # editline2 "315" "logstash.conf" "\                        hosts => \[\"http://$elasticsearchmonitorhost:$elasticsearchmonitorport\"\]"
    # editline2 "320" "logstash.conf" "\                        hosts => \[\"http://$elasticsearchmonitorhost:$elasticsearchmonitorport\"\]"
    # editline2 "328" "logstash.conf" "\                        hosts => \[\"http://$elasticsearchmonitorhost:$elasticsearchmonitorport\"\]"
    # editline2 "333" "logstash.conf" "\                        hosts => \[\"http://$elasticsearchmonitorhost:$elasticsearchmonitorport\"\]"
    # fdateck "logstash.conf"
    
    
    #### GENERATE SERVICE
    #### https://discuss.elastic.co/t/logstash-service-unit-not-found-centos-7/138446
    /bin/bash /usr/share/logstash/bin/system-install /etc/logstash/startup.options systemd
    systemctl daemon-reload

    ### Logstash java_home patch
    sysdline=$(grep -n "ExecStart" /etc/systemd/system/logstash.service | cut -d ':' -f1)
    append="Environment=\"JAVA_HOME=$javahome\""; 
    sed -i "$sysdline a $append" /etc/systemd/system/logstash.service

    ############################################
	#### START
    systemctl enable logstash.service
    service_start "logstash"
    
    ### Patch to fix wrong label on service:info file
    service_label="logstash"
    
    ############################################
	#### uninstall commands
    _safe_append "systemctl disable --now logstash.service"  "$installationpath"/$unifile
    _safe_append "rpm -e \$(rpm -qa |grep -i $service_label)"  "$installationpath"/$unifile
    # _safe_append "cd $installationpath"  "$installationpath"/$unifile
    _safe_append "rm -rf /etc/logstash"  "$installationpath"/$unifile
    log "$info_conf_done" "both"

    return 0
}