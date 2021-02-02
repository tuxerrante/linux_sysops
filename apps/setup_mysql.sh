#!/bin/bash
### Install function for MySQL
### Input arguments 
#        $1=[0=install] 
#        $2=[installation path] 
#        $3=[bind_address] 
#        $4=[bind_port] 
#        $5=[data path]
### Output variables status=[0=installed 1=not_installed] service_label=[name_of_action/service] 
function mysql {
	log "===================== MYSQL =====================" "both"
	local install=$1
	mysqlport=$4
	mysqlhost=$3
	local auxdatapath=$5
	service_label="mysql"
	cmessage $service_label
	archivediscover $service_label

    if [ "$install" -ne 0 ]; then
		log "$err_inst_fail" "both"
		return 1
	fi	

    log "$info_inst_start" "both"
    tar xf "$path" -C $temppath || log "WARN | Error whil extracting $path in $temppath" "both"
    rm -rf $temppath/mysql*minimal*.rpm
    
    ############################################
	#### MariaDB lib are installed by default in CentOs
    _maria_check=$(rpm -qa |grep -i mariadb)
    if [[ "$_maria_check" ]];then
        yum -y -q remove "$_maria_check" mariadb-libs
    fi

    ############################################
	#### Firewall
    _open_port "$mysqlport/tcp"

    ############################################
	#### DIRS and OWNERSHIPS
    local target_path="$installationpath/$service_label"
    local log_path="$logpath/$service_label"            # $log_path
    local data_path="$auxdatapath/mysql"                # $data_path
    
    rm -rf "$data_path/mysql/"*
    
    log "INFO | Creating folders required by $service_label > $target_path, $log_path, $data_path" "both"
    mkdir -p $log_path $data_path $target_path

    mkdir -p "$temppath/mysql"

    ############################################
	#### INSTALL
    ####    https://dev.mysql.com/doc/refman/5.7/en/linux-installation-rpm.html
    ####    https://dev.mysql.com/doc/relnotes/mysql/5.7/en/news-5-7-31.html
    yum -y -q remove mysql-community-{server,client,common,libs}-5.7.31* mysql*
    yum -y -q install perl-JSON.noarch perl-Data-Dumper.x86_64 libaio
    yum -y install $temppath/mysql-community-{server,client,common,libs}-5.7.31*

    ckcapsule=$(rpm -qa | grep -ic $service_label)
    if [ "$ckcapsule" -lt 1 ] ; then
		log "$err_inst_fail" "both"
		return 1
	fi

    log "$info_inst_done" "both"
    
    ############################################
    log "$info_conf_start" "both"
    chown -R mysql:mysql "$log_path" "$data_path" "$target_path"

    whereis mysql > "$target_path/info"
    echo "DATA: $data_path" >> "$target_path/info"
    echo "LOG: $log_path"   >> "$target_path/info"

    ############################################
	#### CONF FILE
    # cd /etc || { log "ERROR | cd /etc fail."; exit 1; }			## current dir /etc
    mysql_config_file="/etc/my.cnf"
    cp $runpath/config/mysqld.cnf $mysql_config_file
    sed -i "s|MYSQL_DATA_PATH|$data_path|g"   $mysql_config_file
    sed -i "s|MYSQL_LOG_PATH|$log_path|g"      $mysql_config_file
    sed -i "s|MYSQL_CERT_PATH|$cert_path|g"   $mysql_config_file
    ####

    fdateck "$mysql_config_file"
    if [ $? -eq  0 ]; then
        log "$info_conf_done" "both"
    else
        log "$err_conf_fail" "both"
    fi

    #### INIT SCRIPT
    cp $runpath/lib/mysql-init.sql $temppath/mysql
    mysql_init_script="$temppath/mysql/mysql-init.sql"
    chown mysql:mysql "$mysql_init_script"              # lib/mysql-init.sql

    #### SET USERS PSW IN INIT FILE ####
    sed -i "s|MYSQL_ROOT_PSW|$mysqlpassword|"    $mysql_init_script
    sed -i "s|MYSQL_APPUSER_PSW|$mysqlpassword|" $mysql_init_script

    #### REMOVE KEYS EXTRACTED FROM RPM AND OLD DATA
    rm -rf /var/lib/mysql/*
    #find "$data_path" -name "*.pem" -type f -delete

    #### FIRST START AND GENERATE ROOT USER
    systemctl stop mysqld

    rm -f $data_path/ib*; 
    echo "" > $log_path/mysqld.log 
    rm -rf $data_path/*

    chown -R mysql:mysql $log_path $data_path
    chmod 750 $log_path $data_path
    
    mysqld --initialize-insecure --datadir=$data_path --user=mysql

    # MYSQL_ROOT_TMP_PSW=$(grep 'temporary password' $log_path/mysqld.log |sed "s|.*: ||")
    # log "INFO | MySQL temp psw: $MYSQL_ROOT_TMP_PSW" "both"

    systemctl restart mysqld
    ln -s /var/run/mysqld/mysql.sock /var/lib/mysql/mysql.sock

    ## POPULATE SCHEMAS WITH ROOT USER
    # /usr/bin/mysql --socket=/var/run/mysqld/mysql.sock -u root -p"${MYSQL_ROOT_TMP_PSW}" --connect-expired-password < "$mysql_init_script"
    /usr/bin/mysql -u root --connect-expired-password < "$mysql_init_script"
    if [[ $? -ne 0 ]]; then
        log "WARN | MySQL's initialization failed!" "both"
        exit 77
    fi

    service_start "mysqld"
    
    #### CLEANING     
    rm -f $temppath/*.rpm # $mysql_init_script
    
    mysql_uninstall="systemctl disable --now mysqld;  rpm -e \$(rpm -qa |grep -i $service_label); rm -rf $auxdatapath/mysql /etc/my.cnf /etc/my.cnf.d"
    _safe_append "$mysql_uninstall" "$installationpath/$unifile"

    log "$info_conf_done" "both"
    return 0
}