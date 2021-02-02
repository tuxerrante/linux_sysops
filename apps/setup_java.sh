#!/bin/bash
### Install function for Java
### Input arguments 
#       $1=[0=is_to_install] 
#       $2=[installation path] 
#       $3=[bind_address] 
#       $4=[bind_port] 
#       $5=[data path]
### Output variables 
#       status=[0=installed 1=not_installed] 
#       service_label=[name_of_action/service] 
function setup_java {
	log "===================== JAVA =====================" "both"
	is_to_install=$1
	auxdatapath=$5
	auxinstallpath=$2
	service_label="OpenJDK"
	cmessage $service_label
	archivediscover $service_label
	tarfolder $path

    ############################################
	#### CHECK IF INSTALLATION IS REQUIRED
	if [[ ! $is_to_install ]]; then
		log "$err_inst_fail" "both"
		return 1
	fi

    log "$info_inst_start" "both"
    var1=$auxinstallpath

    log "INFO | Creating folders required by $service_label > $var1" "both"
    mkdir -p $var1
    tar xzf $path -C $var1
    chown -R $runuser:$rungroup $var1/$tgzfolder
    javapath=$var1/$tgzfolder/bin/java
    javahome=$var1/$tgzfolder
    
    alternatives --install /usr/bin/java java "$javapath" 1
    alternatives --set java "$javapath"
    # echo "export JAVA_HOME=$javahome" >> /etc/profile
    JAVA_HOME=$javahome
    export JAVA_HOME

    log "$info_inst_done" "both"

    ############################################
	#### UNINSTALL COMMANDS
    _java_uninstall="rm -rf $var1/$tgzfolder; unset JAVA_HOME"
    _safe_append "${_java_uninstall}" "$installationpath/$unifile"

    sum $service_label 0 2
    return 0
}