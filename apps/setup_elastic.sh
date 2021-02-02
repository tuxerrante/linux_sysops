#!/bin/bash
### Input arguments 
#		$1=[0=is_to_install] 
#		$2=[installation path] 
# 		$3=[bind_address]
#		$4=[bind_port]
#		$5=[data path]
#		$6 "MONITORING"
### Output variables status=[0=installed 1=not_installed] service_label=[name_of_action/service]
### 	It can be usually found in /usr/share/elasticsearch
function elasticsearch {
	log "===================== ELASTICSEARCH $6 =====================" "both"
	is_to_install=$1
	installation_path=$2
	elasticport=$4
	elastichost=$3
	local auxdatapath=$5
	service_label="elasticsearch-7.9.1"
	cmessage $service_label

	nodeid=$(echo $localip | cut -d '.' -f4)

	archivediscover $service_label "" "rpm"
	count=0

    if [ "$is_to_install" -ne 0 ]; then
		log "$err_inst_fail" "both"
		return 1
	fi

    ############################################
	#### INSTALL
	log "$info_inst_start" "both"
    systemctl stop elasticsearch.service || :

    rpm -ih "$path"
    ckcapsule=$(rpm -qa | grep -ic $service_label)
    if [ "$ckcapsule" -lt 1 ] ; then
		log "$err_inst_fail" "both"
		return 1
	fi

    log "$info_inst_done" "both"
    
    ############################################
	####  Firewall
    _open_port "$elasticsearchport/tcp"

    ############################################
	#### DIRS and OWNERSHIPS
	log "INFO | Creating folders required by $service_label" "both"
    local target_path="$2/$service_label"
    local log_path="$logpath/$service_label"
    local data_path="$auxdatapath/$service_label"
    
    mkdir -p $log_path $data_path $target_path
    chown -R elasticsearch. $log_path $data_path $target_path
    chown -R elasticsearch:elasticsearch /var/lib/elasticsearch/

    whereis elasticsearch > "$target_path/info"
    echo "DATA: $data_path" >> "$target_path/info"
    echo "LOG:  $log_path"  >> "$target_path/info"

    ############################################
	####  ELASTICSEARCH.YML
    log "$info_conf_start" "both"

    elastic_conf_file="/etc/elasticsearch.yml"
    cp "$runpath/config/elasticsearch.yml" /etc/  || exit 77
    
    chown elasticsearch $elastic_conf_file

    local node_name="elasticsearch"
    if [[ -n "$6" ]]; then 
        node_name="elasticsearch-monitor"
    fi

    # sed -i "s|ELA_MON_PORT|$elasticsearchmonitorport|g" $elastic_conf_file
    # sed -i "s|KIBANA_PORT|$kibanaport|g"                $elastic_conf_file
    sed -i "s|DATA_PATH|$data_path|g"           $elastic_conf_file
    sed -i "s|LOG_PATH|$log_path|g"             $elastic_conf_file
    sed -i "s|CERT_PATH|$cert_path|g"           $elastic_conf_file
    sed -i "s|NODE_NAME|$node_name|g"           $elastic_conf_file

    ############################################
	####  Cluster management
    ## TODO: node_name should iterate over nodes: ["app-elasticsearch", "app-elasticsearch2", "app-elasticsearch3"]
    ##
    if [ "$cluster" -gt 1 ]; then
        log "INFO | Found an Elasticsearch cluster"
        for host in ${hostaddress[*]}; do
            if [ $count = 0 ]; then
                clusternode="\"$host\", "
            else
                clusternode="$clusternode\"$host\", "
            fi
            (( count=count+1 ))
        done
        clusternode="${clusternode::-2}"
        clusternode="[$clusternode]"
        _safe_append "discovery.seed_hosts: $clusternode" $elastic_conf_file
        _safe_append "cluster.initial_master_nodes: $clusternode" $elastic_conf_file

    elif $single_server_installation; then
        log "INFO | Single host configuration"
        _safe_append "discovery.seed_hosts: [ \"$elastichost\" ]" $elastic_conf_file
        _safe_append "cluster.initial_master_nodes: [ \"$elastichost\" ]" $elastic_conf_file
    fi
    fdateck "$elastic_conf_file"
    

    ############################################
	#### app PLUGIN
    systemctl enable elasticsearch.service
    if [ "$plugin" -eq 0 ]; then
        appplugin 0
    fi

    ############################################
	#### START SERVICE
    service_label="ElasticSearch-7.9.1-"
    service_start "elasticsearch"
    
    ############################################
	#### SET NEW PASSWORD
    /usr/share/elasticsearch/bin/elasticsearch-setup-passwords auto -u https://app-elasticsearch:9200

    ############################################
	#### Uninstall commands
    _safe_append "systemctl disable --now elasticsearch.service"  "$installationpath/$unifile"
    _safe_append "rpm -e \$(rpm -qa |grep -i elasticsearch)"  "$installationpath/$unifile"
    _safe_append "cd $installationpath"  "$installationpath/$unifile"
    _safe_append "rm -rf /etc/elasticsearch $auxdatapath/elasticsearch /etc/elastic.yml" "$installationpath/$unifile"
    log "$info_conf_done" "both"

    return 0	
}