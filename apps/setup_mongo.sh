#!/bin/bash
### Install function for MongoDB
### Input arguments 
#       $1=[0=is_to_install] 
#       $2=[installation path] 
#       $3=[bind_address] 
#       $4=[bind_port] 
#       $5=[data path]
### Output variables status=[0=installed 1=not_installed] service_label=[name_of_action/service] 
function mongo {
	
    log "===================== MONGO =====================" "both"
	is_to_install=$1
	mongoport=$4
	mongohost=$3
	auxdatapath=$5
	service_label="MongoDB"
	cmessage $service_label
	archivediscover "${service_label}*server*.rpm"

	if [ "$is_to_install" -ne 0 ]; then
		log "$err_inst_fail" "both"
		return 1
	fi	

	log "$info_inst_start" "both"

	############# ULIMIT #############
	# These limits are already defined in /usr/lib/systemd/system/mongod.service
	# https://docs.mongodb.com/v4.2/reference/ulimit/#linux-distributions-using-systemd
	#######################################

	## Install mongo-server from rpm
	rpm -ih "$path"
	ckcapsule=$(rpm -qa | grep -ic $service_label)

	if [ "$ckcapsule" -lt 1 ] ; then
		log "$err_inst_fail" "both"
		return 1
	fi

	## Install mongo-shell from rpm
	rpm -ih "$runpath/packages/mongodb-org-shell*.rpm"

	log "$info_inst_done" "both"
	log "$info_conf_start" "both"
	systemctl stop mongod.service || :
	
	############################################
	#### Firewall
	_open_port "$mongoport/tcp"

	############################################
	#### DIRS and OWNERSHIPS
	log "INFO | Creating folders required by $service_label" "both"

    local target_path="$2/$service_label"
    local log_path="$logpath/$service_label"
    local data_path="$auxdatapath/$service_label"
    mkdir -p $log_path $data_path $target_path
    chown -R mongod:mongod $log_path $data_path $target_path

    whereis mongo > "$target_path/info"
    echo "DATA: $data_path" >> "$target_path/info"
    echo "LOG: $log_path"   >> "$target_path/info"

	############################################
	#### Copy mongo template file in etc and replace values
	mv /etc/mongod.conf /etc/mongod.conf.BKP
	cp "$runpath/config/mongod.conf" /etc/  || exit 77
	cd /etc || exit 77
	sed -i "s|SYSTEM_LOG_PATH|$logpath/$service_label/mongod.log|" 	mongod.conf
	sed -i "s|STORAGE_DB_PATH|$auxdatapath/$service_label|" 		mongod.conf
	sed -i "s|NET_BIND_IP|0.0.0.0|" 								mongod.conf
	sed -i "s|TLS_CERTIFICATE|$cert_path/app-mongodb-cert-key.pem|"	mongod.conf
	
	if fdateck "mongod.conf"; 
	then log "$info_conf_done" "both"
	else log "$err_conf_fail" "both"
	fi
	#######################################################

	log "INFO | Setting owner on folder(s) and file(s) of $service_label" "both"
	chown -R mongod:mongod "$auxdatapath"/$service_label "$logpath"/$service_label
    chmod 775 "$logpath"/$service_label

	#######################################################
	## INITIALIZE USERS AND COLLECTIONS
	systemctl start mongod.service
	/usr/bin/mongo --quiet --host app-mongodb --port $mongoport --tls --tlsCAFile $cert_path/app-CA-cert.pem $runpath/lib/mongo_init.js
	mongo_tables_config=$?
	if [[ ! $mongo_tables_config ]]; then
		log "WARN | Mongo init script has failed!"
	fi
	sed -i "s|authorization: disabled|authorization: enabled|"	mongod.conf
	#######################################################
	## OPTIONAL OPTIMIZATIONS

	## NUMA CPU
	## https://linux.die.net/man/3/numa
	numa_info=$(lscpu |grep -i numa)
	if [ -n "$numa_info" ]; then
		log "INFO | Found NUMA CPU. Optimizing Mongo service.."
		cp -f /usr/lib/systemd/system/mongod.service /usr/lib/systemd/system/mongod.service.BKP
		sed -i "s|ExecStart=|ExecStart=/bin/numactl --interleave=all |" /usr/lib/systemd/system/mongod.service
		yum -y install numactl
		systemctl daemon-reload
	fi

	## DISABLE HUGE MEMORY PAGES 
	## https://docs.mongodb.com/manual/tutorial/transparent-huge-pages/
	cp -f $runpath/config/disable-transparent-huge-pages.service /etc/systemd/system/
	chmod +x /etc/systemd/system/disable-transparent-huge-pages.service
	systemctl daemon-reload
	systemctl enable --now disable-transparent-huge-pages

	mkdir -p /etc/tuned/virtual-guest-no-thp
	cp -f $runpath/config/tuned.conf /etc/tuned/virtual-guest-no-thp/
	tuned-adm profile virtual-guest-no-thp
	#######################################################

	systemctl enable mongod.service
	service_start mongod.service
	
	## --- uninstall commands
	_mongo_uninstall="systemctl disable --now mongod; sudo systemctl disable --now disable-transparent-huge-pages;  rpm -e \$(rpm -qa |grep -i $service_label);  cd $installationpath;  rm -rf $auxdatapath/$service_label /etc/tuned/virtual-guest-no-thp/tuned.conf;"
	_safe_append "$_mongo_uninstall" "$installationpath/$unifile"
	
	log "$info_conf_done" "both"
	return 0	
}
