#!/bin/bash
### Install function for kibana
### Input arguments 
#       $1=[0=is_to_install] 
#       $2=[installation path] 
#       $3=[bind_address] 
#       $4=[bind_port] 
#       $5=[data path]
### Output variables status=[0=installed 1=not_installed] service_label=[name_of_action/service] 
function kibana {
	log "===================== KIBANA =====================" "both"
	is_to_install=$1
	kibanaport=$4
	kibanahost=$3
    local auxdatapath=$5
	service_label="kibana"
	cmessage $service_label
	
    archivediscover $service_label "" "rpm"

    if [ "$is_to_install" -ne 0 ]; then
		log "$err_inst_fail" "both"
		return 1
	fi

    ############################################
	#### INSTALL RPM PACKAGE
	log "$info_inst_start" "both"
    mkdir -p /etc/kibana
    rpm -ih "$path"

    ckcapsule=$(rpm -qa | grep -ic $service_label)
    if [[ "$ckcapsule" -lt 1 ]]; then
        log "$err_inst_fail" "both"
        return 1
    fi

    log "$info_inst_done" "both"

    ############################################
	#### FIREWALL
    _open_port "$kibanaport/tcp"

    ############################################
	#### DIRS and OWNERSHIPS
    log "INFO | Creating folders required by $service_label" "both"
    local target_path="$2/$service_label"
    local log_path="$logpath/$service_label"
    local data_path="$auxdatapath/$service_label"
    mkdir -p $log_path $data_path $target_path
    chown -R kibana. $log_path $data_path $target_path

    whereis kibana > "$target_path/info"
    echo "DATA: $data_path" >> "$target_path/info"
    echo "LOG: $log_path"   >> "$target_path/info"

    ############################################
	#### CONFIGURATIONS
    log "$info_conf_start" "both"
    systemctl stop kibana.service

    kibana_conf_file="/etc/kibana/kibana.yml"
    cp "$runpath/config/kibana.yml" /etc/  || exit 77
    chown kibana. $kibana_conf_file

    sed -i "s|ELA_MON_PORT|$elasticsearchmonitorport|g" $kibana_conf_file
    sed -i "s|KIBANA_PORT|$kibanaport|g"                $kibana_conf_file
    sed -i "s|DATA_PATH|$data_path|g"                   $kibana_conf_file
    sed -i "s|LOG_PATH|$log_path|g"                     $kibana_conf_file
    sed -i "s|CERT_PATH|$cert_path|g"                   $kibana_conf_file

    if fdateck $kibana_conf_file; then
        log "$info_conf_done" "both"
    else
        log "$err_conf_fail" "both"
    fi

    ############################################
	#### START SERVICE
    systemctl enable kibana.service
    log "INFO | Creating folders required by $service_label" "both"
    exampleip="0.0.0.0"
    if [[ ${exampleip} =~ ${kibanahost} ]]; then
        kibanahost1="127.0.0.1"
    else
        kibanahost1=$kibanahost
    fi

    service_label="elk_stack_conf"
    archivediscover $service_label
    tarfolder $path
    tar xzf $path -C $temppath
    
    log "INFO | Starting up kibana" "both"
    service_start "kibana"
    
    if portcheck $elasticsearchmonitorhost $elasticsearchmonitorport; then
        log "INFO | Deploying Kibana dashboards" "both"
        cd "$temppath"/dashboard/api || { log "ERROR | cd fail."; exit 1; }
        
        jsonlist=$(ls ./*.json)
        for dash in ${jsonlist[*]}; do
            curl -s -X POST -H "Content-Type: application/json;charset=UTF-8" -H "accept: application/json" -H "kbn-xsrf: true" -d @"$dash" http://$kibanahost1:$kibanaport/api/kibana/dashboards/import?force=true > /dev/null
        done
        if [ $? -ne 0 ]; then
            log "ERROR | Unable to deploy dashboards during the setup execution"
            return 1
        fi
    fi
    if [ $? -eq 1 ]; then
        log "INFO | Creating dashboards upload's script on /etc/kibana/dashboard" "both"
        mkdir dashboard; 
        cd dashboard || exit
        echo "#!/bin/bash" > importdash.sh
        echo "
        jsonlist=\$(ls |grep json)
        for dash in \${jsonlist[*]}; do
            curl -s -X POST -H \"Content-Type: application/json;charset=UTF-8\" -H \"accept: application/json\" -H \"kbn-xsrf: true\" -d @\"$dash\" http://$kibanahost1:$kibanaport/api/kibana/dashboards/import?force=true
            echo
        done" >> importdash.sh
        
        chmod +x importdash.sh
        cd $temppath/dashboard/api || exit
        cp ./*.json /etc/kibana/dashboard/
    fi
    ### Patch to fix wrong label on service.info file
    service_label="Kibana"
    
    ####### UNINSTALL COMMANDS
    _kibana_uninstall="systemctl disable --now kibana.service; rpm -e \$(rpm -qa |grep -i $service_label); cd $installationpath; rm -rf /etc/kibana /etc/init.d/kibana /etc/kibana.yml /etc/systemd/system/kibana.service" 
    _safe_append "$_kibana_uninstall" "$installationpath"/$unifile

    log "$info_conf_done" "both"
    return 0
}
