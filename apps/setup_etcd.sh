#!/bin/bash
### Install function for etcd
### Input arguments 
#       $1=[0=is_to_install] 
#       $2=[installation path] 
#       $3=[bind_address] 
#       $4=[bind_port] 
#       $5=[data path]
### Output variables 
## 		status=[0=installed 1=not_installed] 
## 		service_label=[name_of_action/service] 
function etcd {
	log "===================== ETCD =====================" "both"
	is_to_install=$1
	etcdport=$4
	etcdhost=$3
	auxdatapath=$5
	
	service_label="Etcd"
	cmessage $service_label
	archivediscover $service_label

	if [[ ! $is_to_install ]]; then
		log "$err_inst_fail" "both"
		return 1
	fi

	############################################
	#### LOAD JAVA INSTALL FUNCTION
	if [ -z "$javapath" ]; then
        setup_java 0 "$installationpath" "N/A" "N/A" $auxdatapath
    fi

	############################################
	#### INSTALL ETCD
	service_label="etcd"
	cmessage $service_label
	archivediscover $service_label

	log "$info_inst_start" "both"
	rpm -ih "$path"
	ckcapsule=$(rpm -qa | grep -ic $service_label)
	
	if [ "$ckcapsule" -lt 1 ]; then
		log "$err_inst_fail" "both"
		return 1
	fi

	### This echo prevents automatic update of etcd
	yumexclude=$(grep -c exclude /etc/yum.conf)
	if [ "$yumexclude" -eq 0 ]; then
		_safe_append "exclude=etcd-3*" /etc/yum.conf
	elif [ "$yumexclude" -eq 1 ]; then
		yumexcludeline=$(grep -n exclude < /etc/yum.conf |cut -d ':' -f1)
		commandsed="s"
		sed -i "$yumexcludeline$commandsed/$/ etcd-3*/" /etc/yum.conf
	fi
	log "$info_inst_done" "both"
	log "$info_conf_start" "both"
	systemctl stop etcd.service || :
	
	############################################
	#### Firewall
	_open_port "$etcdport/tcp"

	############################################
	#### DIRS and OWNERSHIPS
    log "INFO | Creating folders required by $service_label" "both"
    local target_path="$2/$service_label"
    local log_path="$logpath/$service_label"
    local data_path="$auxdatapath/$service_label"
    mkdir -p $log_path $data_path $target_path
    chown -R etcd. $log_path $data_path $target_path

    whereis etcd > "$target_path/info"
    echo "DATA: $data_path" >> "$target_path/info"
    echo "LOG:  $log_path"  >> "$target_path/info"

	############################################
	#### CONF FILE
	cp "$runpath/config/etcd.conf" /etc/etcd/  || exit 77
    etcd_conf_file="/etc/etcd/etcd.conf"

	sed -i "s|DATA_PATH|$auxdatapath/etcd|" $etcd_conf_file
	sed -i "s|ETCD_HOST_IP|$etcdhost|g" 	$etcd_conf_file	
	sed -i "s|CERT_PATH|$cert_path|g" 		$etcd_conf_file	
	sed -i "s|LOG_PATH|$logpath/etcd|g" 	$etcd_conf_file	
	
	if fdateck "$etcd_conf_file"; 
		then log "$info_conf_done" "both"
		else log "$err_conf_fail" "both"
	fi

	############################################
	log "INFO | Creating folders required by $service_label > $auxdatapath/etcd/default.etcd" "both"
	mkdir -p "$auxdatapath/etcd/default.etcd"
	mkdir -p "$logpath/etcd"
	
	log "INFO | Setting owner on folders and files of $service_label" "both"
	chown -R etcd. "$auxdatapath/etcd"
	chown -R etcd. "$logpath/etcd"

	systemctl enable etcd.service
	service_start "etcd"
	
	############################################
	# aggiunge utente root e assegna ruolo root
	export ETCDCTL_API=3
	echo "export ETCDCTL_API=3" >> /etc/profile
	
	echo "ETCD: adding user root"
	echo $etcd_root_psw | etcdctl --endpoints "https://app-etcd:$etcdport" --cacert="$cert_path/app-CA-cert.pem" --cert="$cert_path/app-etcd-client-root-cert.pem" --key="$cert_path/app-etcd-client-root-key.pem" user add root --interactive=false
	etcdctl --endpoints "https://app-etcd:$etcdport" --cacert="$cert_path/app-CA-cert.pem" --cert="$cert_path/app-etcd-client-root-cert.pem" --key="$cert_path/app-etcd-client-root-key.pem" user grant-role root root

	# aggiunge utente xAdmin e ruolo xUserRole
	echo "ETCD: adding user xAdmin"
	echo $etcd_root_psw |etcdctl --endpoints "https://app-etcd:$etcdport" --cacert="$cert_path/app-CA-cert.pem" --cert="$cert_path/app-etcd-client-root-cert.pem" --key="$cert_path/app-etcd-client-root-key.pem" user add xAdmin --interactive=false
	etcdctl --endpoints "https://app-etcd:$etcdport" --cacert="$cert_path/app-CA-cert.pem" --cert="$cert_path/app-etcd-client-root-cert.pem" --key="$cert_path/app-etcd-client-root-key.pem" role add xUserRole
	etcdctl --endpoints "https://app-etcd:$etcdport" --cacert="$cert_path/app-CA-cert.pem" --cert="$cert_path/app-etcd-client-root-cert.pem" --key="$cert_path/app-etcd-client-root-key.pem" role grant-permission xUserRole --prefix=true readwrite "secret."
	etcdctl --endpoints "https://app-etcd:$etcdport" --cacert="$cert_path/app-CA-cert.pem" --cert="$cert_path/app-etcd-client-root-cert.pem" --key="$cert_path/app-etcd-client-root-key.pem" user grant-role xAdmin xUserRole

	# aggiunge utente appUser e ruolo appUserRole
	echo "ETCD: adding user appUser"
	echo $etcd_root_psw |etcdctl --endpoints "https://app-etcd:$etcdport" --cacert="$cert_path/app-CA-cert.pem" --cert="$cert_path/app-etcd-client-root-cert.pem" --key="$cert_path/app-etcd-client-root-key.pem" user add appUser --interactive=false
	etcdctl --endpoints "https://app-etcd:$etcdport" --cacert="$cert_path/app-CA-cert.pem" --cert="$cert_path/app-etcd-client-root-cert.pem" --key="$cert_path/app-etcd-client-root-key.pem" role add appUserRole
	etcdctl --endpoints "https://app-etcd:$etcdport" --cacert="$cert_path/app-CA-cert.pem" --cert="$cert_path/app-etcd-client-root-cert.pem" --key="$cert_path/app-etcd-client-root-key.pem" role grant-permission appUserRole --prefix=true readwrite "conf."
	etcdctl --endpoints "https://app-etcd:$etcdport" --cacert="$cert_path/app-CA-cert.pem" --cert="$cert_path/app-etcd-client-root-cert.pem" --key="$cert_path/app-etcd-client-root-key.pem" user grant-role appUser appUserRole

	# abilita autenticazione
	echo "ETCD: enabling authentication"
	etcdctl --endpoints "https://app-etcd:$etcdport" --cacert="$cert_path/app-CA-cert.pem" --cert="$cert_path/app-etcd-client-root-cert.pem" --key="$cert_path/app-etcd-client-root-key.pem" auth enable


	############################################
	#### PASSWORD MANAGER
	#### 	TODO: take passwords from config.cfg to keys.properties
	if [ -z "$javapath" ]; then
		setup_java 0 "$installationpath" "N/A" "N/A" $auxdatapath
	fi

	/usr/bin/java -jar "$runpath/packages/password_manager_tool-5.4.0.0.jar" -mode n -in "$runpath/config/etcd.keys.properties" -host app-etcd -port 2379 -protocol https -adminCert "$cert_path/app-etcd-client-admin-cert.pem" -caCert "$cert_path/app-CA-cert.pem"


	############################################
	#### UNINSTALL COMMANDS
	_etcd_uninstall="systemctl disable --now etcd.service;  rpm -e \$(rpm -qa |grep -i $service_label);  \
		cd $installationpath;  rm -rf /etc/etcd;  rm -rf $auxdatapath/etcd; sed -i 's|export ETCDCTL_API=3||' /etc/profile"
	_safe_append "$_etcd_uninstall" "$installationpath"/$unifile
	############################################

	log "$info_conf_done" "both"
	return 0
}