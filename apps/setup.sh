#!/bin/bash
# To have a readable output in terminal is better to redirect
# the DEBUG info when calling the script, like:
#
#  bash -x setup.sh 2>/var/log/APP_$(date '+%Y%m%d_%H%M')_debug.log
#
#
## AUTHOR	"Alessandro Affinito" 
# 			https://www.linkedin.com/in/affinitoalessandro/
#
#################################################


history -r
# stty -echo
clear

# Exit from all subshells if the exit code is 77
set -E
trap '[ "$?" -ne 77 ] || exit 77' ERR

################################################
## --- GLOBAL VARIABLES INIT
APP_VERSION="5.4.1"
printlog=1   									# Enables the printout of setup's log 0=disabled 1=enabled

runpath=$(pwd)									 # Running path of this script
logfile="$(date '+%Y%m%d_%H%M')_APP_install.log" # Name of the logfile
logfile_path="$runpath/logs/$logfile"

unifile="APP_uninstall.sh"						# Name of the uninstall file

requireddataspace=20971520						# Required space for data folder in Kb (20 Gb - 20971520)
requiredlogspace=20971520 						# Required space for log folder in Kb (20Gb - 20971520)
requiredinstspace=8388608						# Required space for install folder in Kb (8Gb - 8388608)
availablespace=1								# Enables the space test on the isntallation disk 0=disabled 1=enabled
sourcepath="packages"							# Source directory for installation packages
configpath="config"

config_generator="$runpath/lib/configuration_generator.sh" #-- LIBRARIES

suffixname="_ES"								# Suffix for change folder/script name in case of system duplicate
auxconffile="global.descriptor.properties"		# Name of the overwriting configuration file

temppath="/tmp"

service_status=1 								# global var used by the sum() function to add the current service status
												# in the final array
												# TODO: in the component loop call directly sercicheck $component and use the return status



################################################
## LOAD MODULES FUNCTIONS
function load_modules {

	source ./lib/setup_elastic.sh
	source ./lib/setup_etcd.sh
	source ./lib/setup_hjm.sh
	source ./lib/setup_java.sh
	source ./lib/setup_kibana.sh
	source ./lib/setup_logstash.sh
	source ./lib/setup_mongo.sh
	source ./lib/setup_mysql.sh

}
load_modules
################################################
# Used to compute the script execution time
SECONDS=0

## Create installation log file if it doesn't exist
[[ ! -f $logfile_path ]] && touch "$logfile_path"

### --------------------------------
# Log function
# arguments === $1=message_text $2=stdout,log,both
## TODO: should not use sed but a log funcion with file descriptors!
function log {
	if [ $printlog -eq 1 ] && [ "$2" == "both" ]; then
		echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
		_logger "$1"

	elif [ $printlog -eq 1 ] && [ "$2" == "log" ]; then
		_logger "$1"

	elif [ $printlog -eq 0 ] && [ "$2" == "stdout" ]; then
		echo -e "$1"
	fi
}

#====================================================================
function _logger {
	echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" &>>"$logfile_path"  # 2>&1
}

#====================================================================
# Function for the emptying of the keyboard buffer
function flushkey {
	read -r -t 0.1 -N 255
}

#====================================================================
### Function for checking error on config.cfg file
### Arguments $1=[external_control_function] $2=[data_to_check]
function configcheck {
	
	$1 "$2"
	if [[ $? -eq 1 ]]; then
		log "ERROR | Detected incoerence on configuration file. Please check this field: $2" "both"
		exit 77
	fi
}

#====================================================================
### Function to validate boolean value
### input arguments $1=[boolean_to_check]
### output posx 0=valid 1=not_valid
function boolean {
        if [[ $1 == "0" || $1 == "1" || $1 == "true" || $1 == "false" ]]; then
                return 0
        else
                return 1
        fi
}

#====================================================================
### Function to validate port
### input arguments $1=[port]
### output posx 0=valid 1=not_valid
function portvalid {
        if [[ $1 -ge 0 ]] && [[ $1 -le 65535 ]]; then
                return 0
        else
                return 1
        fi
}

#====================================================================
### Function to check if variable is empty
### input arguments $1=[port]
### output posx 0=valid 1=not_valid
function varempty {
        if [ -z "$1" ]; then
                return 1
        else
                return 0
        fi
}

#====================================================================
### Space test (check if there is enough available disk space for selected path. if the check goes wrong the script terminates itself)
### Parameters === $1=[path_to_check] $2=[required_Kbytes]
### output posx 0=valid 1=not_valid 
function spacetest {
requiredspace=$2
pathtock=$1
if [ $availablespace -eq 1 ]; then
	availablespace=$(df -k "$pathtock" |tail -1 |head -3 |awk '{print $4}')
	availablespace=${availablespace/.*}
	availablespace=$(( availablespace / 1048576))
	requiredspace=$((  requiredspace / 1048576))
	if [ $availablespace -lt $requiredspace ]; then
		log "WARN | Space on path $pathtock is less than $requiredspace Gb" "both"
		return 1
	else
		log "INFO | Space on $pathtock is $availablespace Gb" "log"
		return 0
	fi	
fi
}

#====================================================================
### Root user test (check if the script is running with root user)
### output posx 0=not_valid 1=valid 
function roottest {
	user=$(id -u)
	if [ "$user" -ne 0 ]; then
		log "ERROR | Root user is required. Please run again the setup with the root user." "both"
		return 0
	else
		log "INFO | Setup is running with root user" "log"
		return 1
	fi
}

#====================================================================
function _read_config_var {
  config_value="$(grep "^$1" "$runpath/$configpath/config.cfg" |cut -d '=' -f2 |tr -d '"')"
  echo $config_value
}

## Read config.cfg file and initialize variables
function read_config_file {

	## DONT CHANGE THESE VARIABLE NAMES
	## they're statically accesed by tha main for cycle
	cert_path=$(_read_config_var "cert_path")

	single_server_installation=$(_read_config_var "single_server_installation")
	configcheck boolean "$single_server_installation"

	configure_firewall=$(_read_config_var "configure_firewall")
	configcheck boolean "$configure_firewall"

	installationpath=$(_read_config_var "install_path")
	configcheck varempty "$installationpath"

	logpath=$(_read_config_var "log_path")
	configcheck varempty "$logpath"
	
	datapath=$(_read_config_var "data_path")
	configcheck varempty "$datapath"
	
	runuser=$(_read_config_var "execuser")
	configcheck varempty "$runuser"
	
	rungroup=$(_read_config_var "execgroup")
	configcheck varempty "$rungroup"
	
	mysqlhost=$(_read_config_var "mysql_server")
	configcheck ipvalid "$mysqlhost"
	
	mysqlport=$(_read_config_var "mysql_port")
	configcheck portvalid "$mysqlport"
	
	mysqlusername=$(_read_config_var "mysql_user")
	configcheck varempty "$mysqlusername"
	
	mysqlpassword=$(_read_config_var "mysql_pass")
	configcheck varempty "$mysqlpassword"
	
	etcdhost=$(_read_config_var "etcd_server")
	configcheck ipvalid "$etcdhost"
	
	etcdport=$(_read_config_var "etcd_port")
	configcheck portvalid "$etcdport"
	
	etcd_root_psw=$(_read_config_var "etcd_root_psw")
	
	mongohost=$(_read_config_var "mongo_server")
	configcheck ipvalid "$mongohost"
	
	mongoport=$(_read_config_var "mongo_port")
	configcheck portvalid "$mongoport"
	
	mongodataspacehost=$(_read_config_var "mongodat_server")
	configcheck ipvalid "$mongodataspacehost"
	
	mongodataspaceport=$(_read_config_var "mongodat_port")
	configcheck portvalid "$mongodataspaceport"
	
	elasticsearchhost=$(_read_config_var "ela_server")
	configcheck ipvalid "$elasticsearchhost"
	
	elasticsearchport=$(_read_config_var "ela_port")
	configcheck portvalid "$elasticsearchport"
	
	elasticsearchmonitorhost=$(_read_config_var "ela_mon_server")
	configcheck ipvalid "$elasticsearchmonitorhost"
	
	elasticsearchmonitorport=$(_read_config_var "ela_mon_port")
	configcheck portvalid "$elasticsearchmonitorport"
	
	kibanahost=$(_read_config_var "kib_server")
	configcheck ipvalid "$kibanahost"
	
	kibanaport=$(_read_config_var "kib_port")
	configcheck portvalid "$kibanaport"
	
	logstashhost=$(_read_config_var "log_server")
	configcheck ipvalid "$logstashhost"
	
	logstashport=$(_read_config_var "log_port")
	configcheck portvalid "$logstashport"
	
	adminexpire=$(_read_config_var "adminexpire")
	configcheck boolean "$adminexpire"
}

#====================================================================
## Final table to recap services status
function recap_table {
	
	RED="\e[1;31m"
	GREEN="\e[1;32m"
	YELLOW="\e[1;33m"
	CYAN="\e[1;36m"
	BACK="\e[0m"

	printf "${CYAN}%-30s %-30s %-30s${BACK}\n"  "SERVICE" "INSTALL STATUS" "SERVICE STATUS" | tee "$logfile_path"

	listcount=0
	for word in ${summary1[*]}; do
			serv=${word}
			installst=${summary2[$listcount]}
			servicest=${summary3[$listcount]}
			if [ "$installst" == "installed" ]; then
					printf  "${GREEN}%-30s %-30s %-30s${BACK}\n" $serv $installst $servicest | tee "$logfile_path"
			elif [ "$installst" == "not_configured" ] || [ "$servicest" == "stopped" ]; then
					printf "${RED}%-30s %-30s %-30s${BACK}\n" $serv $installst $servicest    | tee "$logfile_path"
			elif [ "$installst" == "not_installed" ]; then
					printf "${YELLOW}%-30s %-30s %-30s${BACK}\n" $serv $installst $servicest | tee "$logfile_path"
			fi
			(( listcount=listcount+1 ))
	done
}

#====================================================================
### Function to test directory/file existence
### Parameters === $1=[path_to_check] $2=[name_of_file_for_log]
### output posx 0=valid 1=not_valid
function filepathcheck {
	if [[ -z "$1" ]] ; then
			log "WARN | $2 not exist" "both"
			return 1
	elif [[ -d "$1" ]] ; then
			# log "INFO |  $1 is a directory" "both"
			return 0
	elif [[ -e "$1" ]] ; then
			# log "INFO |  $1 is a file" "both"
			return 0
	else
			log "WARN | $2 not found" "both"
			return 1
	fi
}

#====================================================================
### Management of the required folders, after filepathcheck
### Input: 	$1 filepathcheck function return value
### 		$2 filepath
### 		$3 requested disk space
function _filepath_manage {
	if [ $1 -eq 1 ]; then
		log "INFO | Creating folder $2"
		mkdir -p "$2"
	fi
	spacetest "$2" $3
	if [ $? -eq 1 ]; then
		log "ERROR | Please check your configuration or create the required path ($2) for the setup." "both"
		stty echo
		rm -Ir $2
		exit 1
	fi
}

#====================================================================
### Common function
### Function for retrieve the name of the main folder of the app from the archive
### parameters === $1=archive_path/archive_name2
### TODO: return it as a echo, not as global var!
function tarfolder {
	tgzfolder=$(tar tf $1 |head -n1 | cut -d '/' -f1)
	echo $tgzfolder
}

#====================================================================
### Function for retrieve the name of the main folder of the app from the archive
### parameters === $1=archive_path/archive_name
function unzipfolder {
	zipfolder=$(unzip -l $1 |head -n4 |tail -n1 | awk '{print $4}' | cut -d '/' -f1)
}

#====================================================================
### Function for checking the date of last changes to a file
### parameters === $1=file_path/file_name $2=time_difference_in_sec
### output posx 0=valid 1=not_valid 
function fdateck {
	dchk=$(( $(date +%s) - $(stat -c %Y $1) ))
	if [ -z $2 ]; then
		time=300
	else
		time=$2
	fi
	if [ $dchk -lt $time ]; then
		log "INFO | Writing of file $1 done" "log"
		return 0
	else
		log "WARN | Writing of file $1 may be failed (Last modified $( stat -c %y $1 ) )" "log"
		return 1
	fi
}

function service_start {
	systemctl daemon-reload
	systemctl restart "$1"
	service_status_check "$1"
}

#====================================================================
### Function for checking service status
### Input arguments 
# 		$1=[service_name]
### output service_status 0=started 1=not_started 
function service_status_check {
	local counter=1
	local max_checks=3
	#service_status=1
	log "INFO | service_status_check| Checking $1 service status" "both"
	
	### If the check is made immediately it won't detect failures
	sleep 5

	while [[ $counter -le $max_checks ]]; do
		log "INFO | service_status_check | $counter try.." "both"
		servstatus="$(systemctl status "$1"| grep "(running)")"
		if [[ $servstatus ]]; then
			log "INFO | Service $1 started" "both"
			# counter=12
			service_status=0
			break
		elif [[ ! $servstatus ]] && [[ $counter -eq $max_checks ]]; then
			log "WARN | Service $1 not started" "both"
			service_status=1
			return 1
		else
			log "INFO | Retrying...." "both"
			(( counter= counter + 1 ))
			sleep 4
		fi
	done
	return $service_status
}


#====================================================================
## Declare services hosts in the configuration file
## Input
##		$1	ip of the host
## 		$2	hostname
## Example:	set_hosts_file 170.10.20.30 app-mysql
function set_hosts_file {
	if [[ "$1" == "0.0.0.0" ]]; then
		return
	fi
	_safe_append "$1 $2" "/etc/hosts"
}


#====================================================================
### Function for checking avalaibility of network ports
### Input arguments $1=[host_ip] $2=[host_port]
### output posx 0=open 1=closed 
function portcheck {
	_counter=1
	log "INFO | Checking TCP/IP port $1" "both"
	while [ "$_counter" -le "3" ]; do
		portstatus=$(nmap -Pn -p$2 $1 |grep open |wc -l)
		if [ $portstatus -eq 1 ]; then
			log "INFO | Port $2 on $1 is opened" "both"
			_counter=12
			return 0
		elif [ $portstatus -eq 0 ] && [ $_counter -eq 3 ]; then
			log "WARN | Port $2 on $1 is closed" "both"
			_counter=12
			return 1
		else
			log "INFO | Retrying...." "both"
			(( _counter=_counter+1 ))
			sleep 2
		fi
	done
}

#====================================================================
### Function for summary creation
### Input arguments 
# 		$1=[service_name] 
#		$2=[0 installed, 1 not installed, 2 not configured] 
#		$3=[0 Started, 1 Not Started]
function sum {
	if [ $2 -eq 0 ];then
		stat2="installed"
	elif [ $2 -eq 1 ];then
		stat2="not_installed"
	elif [ $2 -eq 2 ];then
		stat2="not_configured"
	fi
	if [ $3 -eq 0 ];then
		stat3="started"
	elif [ $3 -eq 1 ];then
		stat3="stopped"
	elif [ $3 -eq 2 ];then
		stat3="N/A"
	fi
	sum1="$sum1$1 "
	sum2="$sum2$stat2 "
	sum3="$sum3$stat3 "
}

#====================================================================
# 	$1 	install_status
#	$2	service_label 
function summary_creation {
	local component=$1
	local install_status=$2

	if [[ $install_status ]]; then
		_safe_append "$service_label $installationpath $datapath $logpath $host $port" "$installationpath/service_info"
	fi
	service_name="$(_service_name "$component")"
	if [[ -z $service_name ]];then
		service_status=2
	else 
		service_status_check "$service_name"
		service_status=$?
	fi
	sum "$component" "$install_status" $service_status
}

#====================================================================
### Function for line substitution for text file 
### Input arguments $1=[text_to_match] $2=[new_text] $3=[file_name] $4=[line number]
function editline {
        ttm=$1
        ttn=$2
        fln=$3
        line_to_edit=$4
        insline_to_edit=0
        tmpfile="tmp.0"
        prelinecheck=$(grep -n "$ttm" "$fln" | cut -f1 -d: )
        if [[ -n $prelinecheck ]] && [[ -n $line_to_edit ]]; then
                if [[ ${prelinecheck[*]} =~ ${line_to_edit} ]]; then
                        cp "$fln" $tmpfile
                        cmd="d"
						#cmd="s"
                        #substring="$line_to_edit,$line_to_edit$cmd/$ttm/$ttn/g|x"
                        #ex -s -c $substring $tmpfile
                        
                        if sed -i "$line_to_edit$cmd" $tmpfile; then
                                (( "insline_to_edit= $line_to_edit-1" ))
                                sed -i "$insline_to_edit a $ttn" $tmpfile
                                if [ $? -eq 0 ]; then
                                        log "INFO | Editing of $fln done" "both"
                                else
                                        log "ERROR | Editing of $fln failed: error during insert-line operation" "both"
                                fi
                        else
                                log "ERROR | Editing of $fln failed: error during delete-line operation" "both"
                        fi
                        postlinecheck=$(grep -n "$ttn" $tmpfile | cut -f1 -d: )
                        if [[ ${postlinecheck[*]} =~ ${line_to_edit} ]]; then
                                mv -f $tmpfile $fln; rm -rf $tmpfile
                        else
                                log "ERROR | Editing of $fln failed: unable to find the new text on line $line_to_edit inside $fln" "both"
                                rm -rf $tmpfile
                        fi
                else
                        log "ERROR | Editing of $fln failed: search for matching text on line $line_to_edit failed" "both"
                        rm -rf $tmpfile
                fi
        else
                log "ERROR | Editing of $fln failed, unable to find the entry point $ttn"
        fi
}
### Function for line substitution for text file 
### Input arguments $1=[line_number] $2=[file_name] $3=[new_text]
function editline2 {

	if grep "^\s*$3\s*$" "$2"; 	 	# if the exact new string is already there, 
	then return						# 	don't mess with the file
	fi

	ttn=$3
	fln=$2
	line_to_edit=$1
	previous_line_to_edit=0
	packages_required="d"
	sed -i "$line_to_edit$packages_required" $fln
	(( previous_line_to_edit=line_to_edit-1 ))
	sed -i "$previous_line_to_edit a $ttn" $fln
	#ckline=${ttn//\\}  # cutoff for escape character
	postlinecheck=$(grep -c "$ttn" "$fln")
	if [ $postlinecheck -eq 1 ] || [ $postlinecheck -eq 2 ] ; then
		log "INFO | Editing of $fln done" "both"
	else
		log "WARN | Editing of $fln could be failed during insert-line operation: unable to execute check due the lenght of string" "both"
	fi
}

### Function to chek ipaddress 
### output posx 0=valid 1=not_valid
function _ip_validator_helper()
{
    local  ip=$1
    local  stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
		# dont'use double quotes here, we want the expansion in ip is an array
        #ip=($ip)
		read -ra ip <<< "$ip"
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

function ipvalid {
  local _ip=${1}
  OLD_IFS=$IFS
  local IFS=' '
  read -ra addresses <<< "$_ip"

  for ip in "${addresses[@]}"; do
    echo " Validating $ip ..."
    _ip_validator_helper "$ip" || return 1
    echo " Validating $ip ... OK"
  done

  IFS=$OLD_IFS
  return 0
}

#====================================================================
### Open port with firewalld service 
function _open_port {

	if ! $configure_firewall; then 		# ignore if configure_firewall is false
		return 0
	fi

	portNumber="$(echo $1 |cut -d'/' -f1)"

	if ! portvalid "$portNumber"; then
		return
	fi

	log "INFO | Opening port $1 .." "both"
	firewall-cmd --add-port=$1 --zone=public --permanent
	sudo firewall-cmd --reload
}

#====================================================================
### Function to test command presence
### Input arguments $1=[command_to_test]
### output posx 0=valid 1=not_valid 
function testcommand {
	ckcomm=""
	ckcomm=$(command -v $1)
	if [ -z "$ckcomm" ]; then
		log "WARN | Command $1 not found." "both"
		return 1
	elif [[ -n $ckcomm ]]; then
		log "INFO | Command $1 found" "stdout"
		return 0
	fi
}

#====================================================================
### Function to retrieve server IP Address
### output variables localip=[local_address]
function ipdiscover {
	#testcommand ifconfig
	#if ! [ $(testcommand ifconfig) ]; then
		#localip=$(ip addr |grep inet | grep -v inet6 | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -n1)
	#else
		#localip=$(ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1')
	#fi
	localip=$(hostname -I |awk '{print $1}' |tr -d ' ')
	
}

#====================================================================
### Function to retrieve package name from name
### Input arguments 
### 	$1=[archive_name_to_check] 
### 	$2=[alternative_path_to_check]
### 	$3=[file extension]
### output variables path=[path/archive_name]
function archivediscover {
	if [[ -z "$2" ]]; then
		searchpath="$runpath/$sourcepath"
	else
		searchpath="$2"
	fi
	
	path=$(find $searchpath -iname "*$1*$3")

	filepathcheck "$path" "$1"
	if [ "$?" -eq 1  ]; then
			log "ERROR | Unable to find $1 installation archive" "both"
			return 1
	else
			log "INFO | Found $path" "both"
			return 0
	fi

	echo $path
}

## Function to append a string to a file 
## only if it not already exists
## $1 string to add
## $2 filename
function _safe_append {
	string=$1
	file=$2
	grep -F -- "$string" "$file" || echo "$string" >> "$file"
}

## Service names
## return service names based on component names
## INP:	$0	component name
## OUT: service name
function _service_name {

	case $1 in

		"elasticsearch")
		_svc_name="elasticsearch"
		;;
		"elasticsearchmonitor")
		_svc_name=""
		;;
		"etcd")
		_svc_name="etcd"
		;;
		"filebeat")
		_svc_name="filebeat"
		;;
		"hjm")
		_svc_name="harvestingjobservice_app"
		;;
		"kibana")
		_svc_name="kibana"
		;;
		"logstash")
		_svc_name="logstash"
		;;
		"mongo")
		_svc_name="mongod"
		;;
		"mongodataspace")
		_svc_name=""
		;;
		"mysql")
		_svc_name="mysqld"
		;;

		*)
		_svc_name=""
		;;
	esac
	echo "$_svc_name"
}

#====================================================================
### Function for common install messages
### Input arguments $1=[service_label]
function cmessage {
	info_inst_start="INFO | Installation of $1 started"
	info_inst_done="INFO | Installation of $1 done!"
	err_inst_fail="ERROR | Installation of $1 failed"
	info_conf_start="INFO | Configuration of $1 started"
	err_conf_fail="ERROR | Configuration of $1 failed"
	info_conf_done="INFO | Configuration of $1 done"
}


### Install function for mongodataspace (redirect to function mongo)
### Input arguments $1=[0=install] $2=[installation path] $3=[bind_address] $4=[bind_port] $5=[data path]
function mongodataspace {
	mongo $1 $2 $3 $4 $5
	
	# Firewall 
	_open_port "$mongodataspaceport/tcp"
}


### Install function for elasticseachmonitor (redirect to function elasticsearch)
### Input arguments $1=[0=install] $2=[installation path] $3=[bind_address] $4=[bind_port] $5=[data path]
function elasticsearchmonitor {
	plugin=1

	if $single_server_installation; then
		log "WARN | For single server installation, ELASTIC MONITORING will be skipped."
		return
	fi

	elasticsearch $1 $2 $3 $4 $5 "MONITORING"	
	## --- Open firewall ports
	_open_port "$elasticsearchmonitorport/tcp"
}


### Install function for filebeat
### Input arguments $1=[0=install] $2=[installation path] $3=[bind_address] $4=[bind_port] $5=[data path]
### Output variables 
# 			status=[0=installed 1=not_installed] 
#		 	service_label=[name_of_action/service] 
function filebeat {
	log "===================== FILEBEAT ===================== " "both"
	local is_to_install=$1
	service_label="filebeat"

	cmessage $service_label
	archivediscover $service_label

	if [ "$is_to_install" -ne 0 ]; then
		log "$err_inst_fail" "both"
		return 1
	fi

	log "$info_inst_start" "both"
	yum -y install "$path"
	
	ckcapsule=$(rpm -qa | grep -ic $service_label)
	if [[ "$ckcapsule" -lt  1 ]]; then
		log "$err_inst_fail" "both"
		return 1
	fi

	log "$info_inst_done" "both"
	
	systemctl stop filebeat.service

	############################################
	#### Firewall
	_open_port "$filebeatport/tcp"

	############################################
	#### DIRS and OWNERSHIPS
	log "$info_conf_start" "both"
    local target_path="$installationpath/$service_label"
    local log_path="$logpath/$service_label"            # $log_path
    
	echo "$service_label service" > "$target_path/info"
    echo "LOG: $log_path"   >> "$target_path/info"
	
	log "INFO | Creating folders required by $service_label > $target_path, $log_path" "both"
    mkdir -p $log_path $target_path

	############################################
	#### CONFIGURE YAML
	cd /etc/filebeat || { log "ERROR | cd fail." "both"; exit 77; }
	chmod 0644 filebeat.yml
	filebeat_yaml="/etc/filebeat/filebeat.yml"

	editline2 "24" $filebeat_yaml "\  enabled: true"
	editline2 "28" $filebeat_yaml "\    \- $log_path/*events.log"
	editline2 "117" $filebeat_yaml "#setup.kibana"

	sed -i "s|^output.elasticsearch|#output.elasticsearch|" $filebeat_yaml
	sed -i 's/  hosts: \["localhost:9200"\]/  # hosts: ["localhost:9200"]/' $filebeat_yaml

	sed -i "s|^#\s*output\.logstash:|output.logstash:|" $filebeat_yaml
	sed -i 's/#\s*hosts: \["localhost:5044"\]/hosts: ["app-logstash:5044"]/' $filebeat_yaml

	append="\    - $log_path/jsonlog/*.log"
	sed -i "28 a $append" /etc/filebeat/filebeat.yml
	
	fdateck $filebeat_yaml
	if [ $? -eq  0 ]; then
		log "$info_conf_done" "both"
	else
		log "$err_conf_fail" "both"
	fi
	
	systemctl enable --now filebeat.service
	service_status_check "filebeat"

	#--- Uninstall commands
	_safe_append "systemctl disable --now filebeat.service"  $installationpath/$unifile
	_safe_append "rpm -e \$(rpm -qa |grep -i $service_label)"  $installationpath/$unifile
	_safe_append "cd $installationpath"  $installationpath/$unifile
	_safe_append "rm -rf /etc/filebeat"  $installationpath/$unifile
	log "$info_conf_done" "both"

	return 0
}


#====================================================================
#
function check_for_new_inst_path {
	local auxinstallpath=$1
	local tgzfolder=$2
	local suffixname=$3

	if filepathcheck "$auxinstallpath" "$auxinstallpath"; then
			if filepathcheck "$auxinstallpath/$tgzfolder" "$auxinstallpath/$tgzfolder"; 
			then var1=$auxinstallpath$suffixname
			else var1=$auxinstallpath
			fi
		else
			var1=$auxinstallpath
	fi
	echo "$var1"
}

#====================================================================
### Install function for Node
### Input arguments 
#		$1=[0=install] 
#		$2=[installation path] 
# 		$3=[bind_address] 
# 		$4=[bind_port] 
# 		$5=[data path]
### Output variables 
#		status=[0=installed 1=not_installed] 2
#		local service_label=[name_of_action/service] 
function node {
	log "===================== NODE  " "both"
	install=$1
	local auxdatapath=$5
	local auxinstallpath=$2
	local service_label="Node"
	local var1
	cmessage $service_label
	archivediscover $service_label
	tarfolder $path

	if [ "$install" -eq 0 ]; then
		log "$info_inst_start" "both"
		
		# var1=$(check_for_new_inst_path $auxinstallpath $tgzfolder $suffixname)
		var1=$auxinstallpath
		log "INFO | Creating folders required by $service_label > $var1" "both"
		mkdir -p "$var1"
		tar xzf "$path" -C "$var1"
		chown -R root. $var1/$tgzfolder
		nodepath="$var1/$tgzfolder/bin/node"
		log "$info_inst_done" "both"
		# alternatives --install /usr/bin/node node $var1/$tgzfolder/bin/node 1
		# alternatives --install /usr/bin/npm npm $var1/$tgzfolder/bin/npm 1
		# alternatives --set node $var1/$tgzfolder/bin/node
		# alternatives --set npm $var1/$tgzfolder/bin/npm
		
		####### UNINSTALL COMMANDS
		tempvar="$tempvar cd $var1/..;  rm -rf $var1/$tgzfolder; "

		sum $service_label 0 2
		return 0
	else
		log "$err_inst_fail" "both"
		sum $service_label 1 2
		return 1
	fi
}



##########################################################################################
##########################################################################################
##########################################################################################
#####																				######
##### 			MAIN																######
#####																				######
##########################################################################################

log "===================================================" "both"
log "$(date '+%Y-%m-%d %H:%M:%S') - Script started." "both"


# Check last modification date of the config file
chmod +x ./lib/check_config_file.sh
source ./lib/check_config_file.sh

### Commands pre-check
packages_required=( "bash-completion" "bash-completion-extras" "unzip" "netstat" "alternatives" "dos2unix" "ex" "expect" "md5sum" "base64" "vim" "yum-config-manager" "nmap" "iptables" "firewalld")
yum update -y

for cmd in "${packages_required[@]}"; do
	testcommand $cmd
	if [ $? -eq 1 ]; then
		log "INFO | Trying to install command $cmd" "both"
		installcmd=$cmd
		if [[ "$cmd" == "netstat" ]]; then
			installcmd="net-tools"
		elif [[ "$cmd" == "yum-config-manager" ]]; then
			installcmd="yum-utils"
		elif [[ "$cmd" == "iptables" ]]; then
			installcmd="iptables-services"
		fi

		#### IF IT IS ALREADY PRESENT SKIP IT
		if rpm --quiet --query $installcmd; then
			continue
		fi

		yum install -y -q $installcmd
		testcommand $cmd
		if [ $? -eq 1 ]; then
			log "ERROR | Installation tentative for command $cmd failed" "both"
			log "INFO | The previous error isn't recoverable. The script terminate here." "both"
			stty echo
			exit 1
		fi
	fi
done


log "INFO | Current timeout value for ICMP connections $(cat /proc/sys/net/netfilter/nf_conntrack_icmp_timeout)"

### Preflight setup's folder check
filepathcheck "$runpath/$configpath" "$runpath/$configpath"
if [ $? -eq 1 ]; then
	log "ERROR | Missing path $runpath/$configpath" "both"
	stty echo
	exit 1
else 
	filepathcheck "$runpath/$configpath/config.cfg" "$runpath/$configpath/config.cfg"
	if [ $? -eq 1 ]; then
		# log "ERROR | Missing config file $runpath/$configpath/config.cfg" "both"
		# exit 1
		# printf $creatorcode64 | base64 --decode > creator_co.sh
		
		chmod +x $config_generator
		stty echo
		./$config_generator
		mv config.cfg $runpath/$configpath/
		stty -echo
	fi
fi
filepathcheck "$runpath/$sourcepath" "$runpath/$sourcepath"
if [ $? -eq 1 ]; then
	log "ERROR | Missing path $runpath/$sourcepath" "both"
	stty echo
	exit 1
fi

filepathcheck "$runpath/$sourcepath/LPP_$APP_VERSION" "$runpath/$sourcepath/LPP_$APP_VERSION"
if [ $? -eq 1 ]; then
	log "ERROR | Missing path $runpath/$sourcepath/LPP_$APP_VERSION" "both"
	stty echo
	exit 1
fi

roottest

## --- SE LINUX ---
selinuxstatus=$(getenforce)
if [[ "$selinuxstatus" == "Enforcing" ]]; then
	log "INFO | Disabling selinux" "both"
	setenforce 0
	editline2 "7" "/etc/selinux/config" "SELINUX=permissive"
else
	log "INFO | Selinux is already configured for app" "both"
fi

## --- TODO: Enable firewalld service
log "INFO | Enable firewalld service"
systemctl enable --now firewalld
firewall-cmd --reload
## ---

# Number of lines of the config.cfg
# numbercfg=$(grep -c . "$runpath/$configpath/config.cfg")

###########################################################
### Reading configuration file variables
read_config_file

###########################################################
### Creation of directories (data, installation, log)
filepathcheck "$logpath" "$logpath"
_filepath_manage $? "$logpath" $requiredlogspace

filepathcheck "$installationpath" "$installationpath" 
_filepath_manage $? "$installationpath" $requiredinstspace

filepathcheck "$datapath" "$datapath"
_filepath_manage $? "$datapath" $requireddataspace

filepathcheck "$temppath" "$temppath"
_filepath_manage $? "$datapath" 10000000 

# Create certificates folder
mkdir -p "${cert_path}"
cp ./certs/* "${cert_path}"

temppath="$temppath/ES_temp"
installationpath="$installationpath/APP"
mkdir -p $logpath
chown $runuser $logpath
mkdir -p $temppath
filepathcheck "$logpath" "$logpath"
if [ $? -eq 1 ]; then
	log "ERROR | Unable to create $logpath" "both"
fi
mkdir -p $installationpath ; chown $runuser $installationpath
filepathcheck "$installationpath" "$installationpath"
if [ $? -eq 1 ]; then
	log "ERROR | Unable to create $installationpath" "both"
fi

### Checking existence of runuser and rungroup
if (id -u $runuser) >/dev/null 2>&1; then
	log "INFO | Found user $runuser" "both"
else
	log "ERROR | User $runuser doesn't exist. Please create it or check your preferences on config.cfg" "both"
	stty echo
	exit 1
fi
if (getent group $rungroup) >/dev/null 2>&1; then
	log "INFO | Found group $rungroup" "both"
else
	log "ERROR | Group $rungroup doesn't exist. Please create it or check your preferences on config.cfg" "both"
	stty echo
	exit 1
fi

### Creation of uninstall file
echo "#!/bin/bash" > "$installationpath/$unifile"

### Creation of auxiliary file
echo "#Service information file" > 	"$installationpath/service_info"
_safe_append "#Ver $APP_VERSION" 	"$installationpath/service_info"

###############################################################################
### List of services to be installed
### Warning: Be sure to align these names with the variable names AND with srv/prt suffixes defined below in the component cycle
arrayinstallation="mongo etcd mongodataspace mysql elasticsearch elasticsearchmonitor filebeat logstash kibana"

arrayremove=""
countarray=0
plugin=0	# plugin variable init (do not touch)

## --- Removing from installation array unnecessary element
if [[ "$mongohost" == "$mongodataspacehost" ]]; then
	arrayremove="$arrayremove mongodataspace"
	(( countarray=countarray + 1 ))
fi

## --- If the Elastic host and the Elastic Monitoring host are the same, don't install the latter
if [[ "$elasticsearchhost" == "$elasticsearchmonitorhost" ]]; then
	arrayremove="$arrayremove elasticsearchmonitor"
	(( countarray=countarray + 1 ))
fi

### Do not add "" around array vars
if [[ -n $arrayremove && $countarray -gt 0 ]]; then
	for del in ${arrayremove[*]}; do
		arrayinstallation=( ${arrayinstallation[@]/$del} )
		log "DEBUG | Removig component $del from the list of installation." "log"
	done
fi

log "DEBUG | Components to install: ${arrayinstallation[*]}" "both"

#===============================================================================
### Installation loop start (it calls components installation functions and provides them the installation's variables)
for component in ${arrayinstallation[*]}; do
	ipdiscover
	srv="host"
	prt="port"
	hostip="$component$srv"
	hostport="$component$prt"
	
	### check if host variable is an array
	cluster=0
	hostaddress=${!hostip}
	address=""

	for address in ${hostaddress[*]}; do
		(( cluster=cluster+1 ))
	done

	cluster_index=0

	for host in ${hostaddress[*]}; do
		### Bypass for single server installation
		if ! $single_server_installation; then
			localip=$host		
		fi

		if [[ $cluster -gt 1 ]]; then
			set_hosts_file $host "app-${component}-${cluster_index}"
			(( cluster_index=cluster_index+1 ))
		else
			if [[ $component = "mongo" ]]; then
				## In the certs/app-mongodb-cert.pem the mongo host is named 'app-mongodb'
				set_hosts_file $host "app-${component}db"
			else
				set_hosts_file $host "app-${component}"
			fi
		fi

		if [[ "${localip[*]}" =~ ${host} ]]; then
			#### Patch for elasticsearch cluster configuration inside app (also usable for mongo)
			fixedhost=$address
			port=${!hostport}
			localip=$host
			if [ -z $port ]; then
				port="N/A"
			fi
			if [ -z $host ]; then
				host="N/A"
			fi
			# Run the slow SLOW installer in a cloned process
			if [[ $component = "SLOW" ]];
			then 
				$component 0 $installationpath $host $port $datapath &
				_SLOW_pid=$!
				log "INFO | SLOW installation will run in parallel. PID=$_SLOW_pid"
			else 
				$component 0 $installationpath $host $port $datapath
				_install_status=$?
				summary_creation "$component" $_install_status
			fi		
		fi
	done
done

#===============================================================================
# --- Wait for SLOW process to end, if it has been installed on this host
if [[ -n $_SLOW_pid ]];then 
	while ps -q $_SLOW_pid > /dev/null; do
		log "INFO | Waiting 5 seconds for SLOW to finish.."
		sleep 5
	done
	wait $_SLOW_pid
	_install_status=$?
else
	_install_status=1
fi
summary_creation "SLOW" $_install_status

#===============================================================================
# --- Extra unistall commands ---
_safe_append "kill $( ps -u root -o pid,cmd |awk '/APP/ {l=l" "$1} END{print l}' )" "$installationpath/$unifile"
_safe_append "$tempvar" "$installationpath/$unifile"
_safe_append "pkill -f " "$installationpath/$unifile"
_safe_append "cd /opt; rm -rvf $installationpath /CSPData /etc/elasticsearch/ /etc/init.d/* /var/APP" "$installationpath/$unifile"
# sed -i "s/alias app_services.*//"  /root/.bashrc
_safe_append "echo Cleaning /etc/hosts file.." 		"$installationpath/$unifile"
_safe_append "sed -i \"s/.*app.*//g\" /etc/hosts" 	"$installationpath/$unifile"
_safe_append "sed -i -e :a -e '/^\n*$/{\$d;N;ba' -e '}' /etc/hosts" "$installationpath/$unifile"
_safe_append "systemctl daemon-reload" "$installationpath/$unifile"
_safe_append "echo \" Please remove install script directory or at least config file for security reasons.\"" "$installationpath/$unifile"
_safe_append "echo \" Please reboot.\"" 			"$installationpath/$unifile"

chmod 740 "$installationpath/$unifile"
mv "$installationpath/$unifile" "$installationpath/.."
#===============================================================================


log "INFO | Setting the owner to $installationpath" "both"
chown -R "$runuser" "$installationpath"
if ! [ -z "$randompwd" ]; then
	log "INFO | ATTENTION!!! The random password for root user of MySQL is inside this log. Copy it in a safe place." "both"
fi
if [ -d /etc/kibana/dashboard/ ]; then
	log "INFO | BEFORE THE STARTUP!!! Import the Kibana dashboards using the the script importdash.sh inside the /etc/kibana/dashboard folder" "both"
fi
log "INFO | Installation sequence done! The setup terminates here" "both"

#===============================================================================
### Restart services
systemctl restart webapi_webapp APP_uing_c42ng       

#===============================================================================
### Installation summary
# clear
# summary1=( $sum1 ) 	# Don't use double quotes, needing an array expansion
# summary2=( $sum2 )
# summary3=( $sum3 )
read -ra summary1 <<< "$sum1"
read -ra summary2 <<< "$sum2"
read -ra summary3 <<< "$sum3"

recap_table
#===============================================================================
# Less important stuff from here on out, Ctrl-C allowed.
trap - SIGINT
stty echo

## --- Real final status ---
_safe_append "alias app_services=\"systemctl status elasticsearch etcd filebeat logstash mongod mysqld kibana |grep 'Active:' -B 3\"" /root/.bashrc


log "INFO | Please reload /root/.bashrc to have an awesome alias: app_services" "both"

date '+%Y%m%d %H:%M'
log "INFO | Execution time: $(( SECONDS/60 )):$((SECONDS%60)) min"
exit 0
#===============================================================================