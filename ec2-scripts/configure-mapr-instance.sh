#! /bin/bash
#
#   $File: configure-mapr-instance.sh $
#   $Date: Fri Sep 13 09:30:20 2013 -0700 $
#   $Author: dtucker $
#
# Script to be executed on top of a base MapR image ... an
# instance with the following stable configuration:
#	Java has been installed 
#	the MapR software repositories are configured
#	the MAPR_USER exists
#	
# NOTE: any or all of these phases could be handled by this script.
#
# Expectations:
#	- Script run as root user (hence no need for permission checks)
#	- Root user's home directory is /root (a few places we use that)
#	- Basic distro differences (APT-GET vs YUM, etc) can be handled
#	    There are so few differences, it seemed better to manage one script.
#
# Tested with MapR 2.0.x, 2.1.1, 3.0.x
#
# JAVA
#	This script default to OpenJDK; it would be a simple change to 
#	enable Oracle Java ... just be sure to handle the interactive
#	license agreement.
#

# Metadata for this installation ... pull out details that we'll need
# 
murl_top=http://169.254.169.254/latest/meta-data
murl_attr="${murl_top}/attributes"

THIS_FQDN=$(curl -f $murl_top/hostname)
[ -z "${THIS_FQDN}" ] && THIS_FQDN=`hostname --fqdn`
THIS_HOST=${THIS_FQDN%%.*}
AMI_IMAGE=$(curl -f $murl_top/ami-id)    # name of initial image loaded here
AMI_LAUNCH_INDEX=$(curl -f $murl_top/ami-launch-index) 

MAPR_VERSION=$(curl -f $murl_attr/maprversion)    # mapr version, eg. 1.2.3
MAPR_VERSION=${MAPR_VERSION:-3.0.1}

# A comma separated list of packages (without the "mapr-" prefix)
# to be installed.   This script assumes that NONE of them have 
# been installed.
MAPR_PACKAGES=$(curl -f $murl_attr/maprpackages)
MAPR_PACKAGES=${MAPR_PACKAGES:-"core,fileserver"}
MAPR_DISKS_PREREQS=fileserver

# Definitions for our installation
#	Long term, we should handle reconfiguration of
#	these values at cluster launch ... but it's difficult
#	without a clean way of passing meta-data to the script
MAPR_HOME=/opt/mapr
MAPR_UID=${MAPR_UID:-2000}
MAPR_USER=${MAPR_USER:-mapr}
MAPR_GROUP=`id -gn ${MAPR_USER}`
MAPR_PASSWD=${MAPR_PASSWD:-MapR}
MAPR_METRICS_DEFAULT=metrics


LOG=/tmp/configure-mapr.log

# Extend the PATH just in case ; probably not necessary
PATH=/sbin:/usr/sbin:/usr/bin:/bin:$PATH

# Helper utility to log the commands that are being run and
# save any errors to a log file
#	BE CAREFUL ... this function cannot handle command lines with
#	their own redirection.

c() {
    echo $* >> $LOG
    $* || {
	echo "============== $* failed at "`date` >> $LOG
	exit 1
    }
}

# Helper utility to update ENV settings in env.sh.
# Function WILL NOT override existing settings ... it looks
# for the default "#export <var>=" syntax and substitutes the new value

MAPR_ENV_FILE=$MAPR_HOME/conf/env.sh
function update-env-sh()
{
	[ -z "${1:-}" ] && return 1
	[ -z "${2:-}" ] && return 1

	AWK_FILE=/tmp/ues$$.awk
	cat > $AWK_FILE << EOF_ues
/^#export ${1}=/ {
	getline
	print "export ${1}=$2"
}
{ print }
EOF_ues

	cp -p $MAPR_ENV_FILE ${MAPR_ENV_FILE}.configure_save
	awk -f $AWK_FILE ${MAPR_ENV_FILE} > ${MAPR_ENV_FILE}.new
	[ $? -eq 0 ] && mv -f ${MAPR_ENV_FILE}.new ${MAPR_ENV_FILE}
}


function update_os_deb() {
	apt-get update
	apt-get upgrade -y --force-yes -o Dpkg::Options::="--force-confdef,confold"
	apt-get install -y nfs-common iputils-arping libsysfs2
	apt-get install -y ntp
	apt-get install -y unzip
	apt-get install -y realpath

	apt-get install -y syslinux sdparm
	apt-get install -y sysstat

	apt-get install -y clustershell pdsh
}

function update_os_rpm() {
	yum make-cache
	yum update -y
	yum install -y nfs-utils iputils libsysfs
	yum install -y ntp ntpdate
	yum install -y unzip
	yum install -y realpath

	yum install -y syslinux sdparm
	yum install -y sysstat

	yum install -y clustershell pdsh
}

# Make sure that NTP service is sync'ed and running
# Key Assumption: the /etc/ntp.conf file is reasonable for the 
#	hosting cloud platform.   We could shove our own NTP servers into
#	place, but that seems like a risk.
function update_ntp_config() {
	echo "  updating NTP configuration" >> $LOG

		# Make sure the service is enabled at boot-up
	if [ -x /etc/init.d/ntp ] ; then
		SERVICE_SCRIPT=/etc/init.d/ntp
		update-rc.d ntp enable
	elif [ -x /etc/init.d/ntpd ] ; then
		SERVICE_SCRIPT=/etc/init.d/ntpd
		chkconfig ntpd on
	else
		return 0
	fi

	$SERVICE_SCRIPT stop
	ntpdate pool.ntp.org
	$SERVICE_SCRIPT start

		# TBD: copy in /usr/share/zoneinfo file based on 
		# zone in which the instance is deployed
	zoneInfo=$(curl -f ${murl_top}/zone)
	curZone=`basename "${zoneInfo}"`
	curTZ=`date +"%Z"`
	echo "    Instance zone is $curZone; TZ setting is $curTZ" >> $LOG

		# Update the timezones we're sure of.
	TZ_HOME=/usr/share/zoneinfo/posix
	case $curZone in
		europe-west*)
			newTZ="CET"
			;;
		us-central*)
			newTZ="CST6CDT"
			;;
		us-east*)
			newTZ="EST5EDT"
			;;
		*)
			newTZ=${curTZ}
	esac

	if [ -n "${newTZ}"  -a  -f $TZ_HOME/$newTZ  -a  "${curTZ}" != "${newTZ}" ] 
	then
		echo "    Updating TZ to $newTZ" >> $LOG
		cp -p $TZ_HOME/$newTZ /etc/localtime
	fi
}

function update_ssh_config() {
	echo "  updating SSH configuration" >> $LOG

	# allow ssh via keys (some virtual environments disable this)
  sed -i 's/#AuthorizedKeysFile/AuthorizedKeysFile/' /etc/ssh/sshd_config

	# allow ssh password prompt (only for our dev clusters)
  sed -i 's/ChallengeResponseAuthentication .*no$/ChallengeResponseAuthentication yes/' /etc/ssh/sshd_config

	[ -x /etc/init.d/ssh ]   &&  /etc/init.d/ssh  restart
	[ -x /etc/init.d/sshd ]  &&  /etc/init.d/sshd restart
}

function update_os() {
  echo "Installing OS security updates" >> $LOG

  if which dpkg &> /dev/null; then
    update_os_deb
  elif which rpm &> /dev/null; then
    update_os_rpm
  fi

	# raise TCP rbuf size
  echo 4096 1048576 4194304 > /proc/sys/net/ipv4/tcp_rmem  
#  sysctl -w vm.overcommit_memory=1  # swap behavior

		# SElinux gets in the way of older MapR installs (1.2)
		# as well as MySQL (if we want a non-standard data directory)
		#	Be sure to disable it IMMEDIATELY for the rest of this 
		#	process; the change to SELINUX_CONFIG will ensure the 
		#	change across reboots.
	SELINUX_CONFIG=/etc/selinux/config
	if [ -f $SELINUX_CONFIG ] ; then
		sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' $SELINUX_CONFIG
		echo 0 > /selinux/enforce
	fi

	update_ntp_config
	update_ssh_config
}

function install_oraclejdk_deb() {
    echo "Installing Oracle JDK (for deb distros)" >> $LOG

	apt-get install -y python-software-properties
	add-apt-repository -y ppa:webupd8team/java
	apt-get update

	echo debconf shared/accepted-oracle-license-v1-1 select true | \
		debconf-set-selections
	echo debconf shared/accepted-oracle-license-v1-1 seen true | \
		debconf-set-selections

	apt-get install -y x11-utils
	apt-get install -y oracle-jdk7-installer

	JAVA_HOME=/usr/lib/jvm/java-7-oracle
	export JAVA_HOME
    echo "	JAVA_HOME=$JAVA_HOME"
}

function install_openjdk_deb() {
    echo "Installing OpenJDK packages (for deb distros)" >> $LOG

	apt-get install -y x11-utils
	apt-get install -y openjdk-7-jdk openjdk-7-doc 

	JAVA_HOME=/usr/lib/jvm/java-7-openjdk-amd64
	export JAVA_HOME
    echo "	JAVA_HOME=$JAVA_HOME"
}

function install_openjdk_rpm() {
    echo "Installing OpenJDK packages (for rpm distros)" >> $LOG

	yum install -y java-1.7.0-openjdk java-1.7.0-openjdk-devel 
	yum install -y java-1.7.0-openjdk-javadoc

	JAVA_HOME=/usr/lib/jvm/java-1.7.0-openjdk.x86_64
	export JAVA_HOME
    echo "	JAVA_HOME=$JAVA_HOME"
}

# This has GOT TO SUCCEED ... otherwise the node is useless for MapR
function install_java() {
  echo Installing JAVA >> $LOG

  let attempts=0
  while [ ${attempts} -lt 10 ] ; do
  	if which dpkg &> /dev/null; then
    	install_oraclejdk_deb
  	elif which rpm &> /dev/null; then
    	install_openjdk_rpm
  	fi

	if [ -x /usr/bin/java ] ; then
		echo Java installation complete >> $LOG

		if [ -n "${JAVA_HOME}" ] ; then
			echo updating /etc/profile.d/javahome.sh >> $LOG
			echo "JAVA_HOME=${JAVA_HOME}" >> /etc/profile.d/javahome.sh
			echo "export JAVA_HOME" >> /etc/profile.d/javahome.sh
		fi

		return 0
	fi

	sleep 10
	let attempts=${attempts}+1
  done 

  echo "!!! Java installation FAILED !!!  Node unusable !!!" >> $LOG
  return 1
}


# Takes the packages defined by MAPR_PACKAGES and makes sure
# that those (and only those) pieces of MapR software are installed.
# The idea is that a single image with EXTRA packages could still 
# be used, and the extraneous packages would just be removed.
#	NOTE: We expect MAPR_PACKAGES to be short-hand (cldb, nfs, etc.)
#		instead of the full "mapr-cldb" name.  But the logic handles
#		all cases cleanly just in case.
# 	NOTE: We're careful not to remove mapr-core or -internal packages.
#
#	Input: MAPR_PACKAGES  (global)
#
install_mapr_packages() {
	echo Installing MapR software components >> $LOG
	
	if which dpkg &> /dev/null; then
		MAPR_INSTALLED=`dpkg --list mapr-* | grep ^ii | awk '{print $2}'`
	elif which rpm &> /dev/null; then
		MAPR_INSTALLED=`rpm -q --all --qf "%{NAME}\n" | grep ^mapr `
	else
		return 1
	fi
	MAPR_REQUIRED=""
	for pkg in `echo ${MAPR_PACKAGES//,/ }`
	do
		MAPR_REQUIRED="$MAPR_REQUIRED mapr-${pkg#mapr-}"
	done

		# Be careful about removing -core or -internal packages
		# Never remove "core", and remove "-internal" only if we 
		# remove the parent as well (that logic is not yet implemented).
	MAPR_TO_REMOVE=""
	for pkg in $MAPR_INSTALLED
	do
		if [ ${pkg%-core} = $pkg  -a  ${pkg%-internal} = $pkg ] ; then
			echo $MAPR_REQUIRED | grep -q $pkg
			[ $? -ne 0 ] && MAPR_TO_REMOVE="$MAPR_TO_REMOVE $pkg"
		fi
	done

	MAPR_TO_INSTALL=""
	for pkg in $MAPR_REQUIRED
	do
		echo $MAPR_INSTALLED | grep -q "$pkg"
		[ $? -ne 0 ] && MAPR_TO_INSTALL="$MAPR_TO_INSTALL $pkg"
	done

	if [ -n "${MAPR_TO_REMOVE}" ] ; then
		if which dpkg &> /dev/null; then
			c apt-get purge -y --force-yes $MAPR_TO_REMOVE
		elif which rpm &> /dev/null; then
			c yum remove -y $MAPR_TO_REMOVE
		fi
	fi

	if [ -n "${MAPR_TO_INSTALL}" ] ; then
		if which dpkg &> /dev/null; then
			c apt-get install -y --force-yes $MAPR_TO_INSTALL
		elif which rpm &> /dev/null; then
			c yum install -y $MAPR_TO_INSTALL
		fi
	fi

	echo Configuring $MAPR_ENV_FILE  >> $LOG
	update-env-sh MAPR_HOME $MAPR_HOME
	update-env-sh JAVA_HOME $JAVA_HOME

	echo MapR software installation complete >> $LOG
}

function regenerate_mapr_hostid() {
	HOSTID=$($MAPR_HOME/server/mruuidgen)
	echo $HOSTID > $MAPR_HOME/hostid
	echo $HOSTID > $MAPR_HOME/conf/hostid.$$
	chmod 444 $MAPR_HOME/hostid

	HOSTNAME_FILE="$MAPR_HOME/hostname"
	if [ ! -f $HOSTNAME_FILE ]; then
		/bin/hostname --fqdn > $HOSTNAME_FILE
		chown $MAPR_USER:$MAPR_GROUP $HOSTNAME_FILE
		if [ $? -ne 0 ]; then
			rm -f $HOSTNAME_FILE
			echo "Cannot find valid hostname. Please check your DNS settings" >> $LOG
		fi
	fi

}

function remove_from_fstab() {
    mnt=${1}
    [ -z "${mnt}" ] && return

    FSTAB=/etc/fstab
    [ ! -w $FSTAB ] && return

		# BE VERY CAREFUL with sedOpt here ... tabs and spaces are included
    sedOpt="/[ 	]"`echo "$mnt" | sed -e 's/\//\\\\\//g'`"[ 	]/d"
    sed -i.mapr_save "$sedOpt" $FSTAB
    if [ $? -ne 0 ] ; then
        echo "[ERROR]: failed to remove $mnt from $FSTAB"
    fi
}

function unmount_unused() {
    [ -z "${1}" ] && return

	echo "Unmounting filesystems ($1)" >> $LOG

    fsToUnmount=${1:-}

    for fs in `echo ${fsToUnmount//,/ }`
    do
		echo -n "$fs in use by " | tee -a $LOG
        fuser $fs >> $LOG 2> /dev/null
        if [ $? -ne 0 ] ; then
			echo "<no_one>" >> $LOG
            umount $fs
            remove_from_fstab $fs
		else
			echo "" >> $LOG
			pids=`grep "^${fs} in use by " $LOG | cut -d' ' -f5-`
			for pid in $pids
			do
				ps --no-headers -p $pid >> $LOG
			done
        fi
    done
}

# Logic to search for unused disks and initialize the MAPR_DISKS
# parameter for use by the disksetup utility.
# As a first approximation, we simply look for any disks without
# a partition table and not mounted/used_for_swap/in_an_lvm and use them.
# This logic should be fine for any reasonable number of spindles.
#
find_mapr_disks() {
	disks=""
	for d in `fdisk -l 2>/dev/null | grep -e "^Disk .* bytes$" | awk '{print $2}' `
	do
		dev=${d%:}

		mount | grep -q -w -e $dev -e ${dev}1 -e ${dev}2
		[ $? -eq 0 ] && continue

		swapon -s | grep -q -w $dev
		[ $? -eq 0 ] && continue

		if which pvdisplay &> /dev/null; then
			pvdisplay $dev 2> /dev/null
			[ $? -eq 0 ] && continue
		fi

		disks="$disks $dev"
	done

	MAPR_DISKS="$disks"
	export MAPR_DISKS
}

# The Amazon images often mount one or more of the instance store
# disks ... just unmount it before looking for disks to be used by MapR.
#	BUT ONLY do that if we actually have the MAPR_DISKS_PREREQS packages !!!
provision_mapr_disks() {
	if [ -n "${MAPR_DISKS_PREREQS}" ] ; then
		pkgsToCheck=""
		for pkg in `echo ${MAPR_DISKS_PREREQS//,/ }`
		do
			pkgsToCheck="mapr-$pkg $pkgsToCheck"
		done

		abortProvisioning=0
		if which dpkg &> /dev/null; then
			dpkg --list $pkgsToCheck &> /dev/null
			[ $? -ne 0 ] && abortProvisioning=1
		elif which rpm &> /dev/null; then
			rpm -q $pkgsToCheck &> /dev/null
			[ $? -ne 0 ] && abortProvisioning=1
		fi
		if [ $abortProvisioning -ne 0 ] ; then
			echo "${MAPR_DISK_PREREQS} package(s) not found" >> $LOG
			echo "  local disks will not be configured for MapR" >> $LOG
			return 
		fi
	fi

	unmount_unused /mnt

	diskfile=/tmp/MapR.disks
	rm -f $diskfile
	find_mapr_disks
	if [ -n "$MAPR_DISKS" ] ; then
		for d in $MAPR_DISKS ; do echo $d ; done >> $diskfile
		c $MAPR_HOME/server/disksetup -M -F $diskfile
	else
		echo "No unused disks found" >> $LOG
		if [ -n "$MAPR_DISKS_PREREQS" ] ; then
			for pkg in `echo ${MAPR_DISKS_PREREQS//,/ }`
			do
				echo $MAPR_PACKAGES | grep -q $pkg
				if [ $? -eq 0 ] ; then 
					echo "MapR package{s} $MAPR_DISKS_PREREQS installed" >> $LOG
					echo "Those packages require physical disks for MFS" >> $LOG
					echo "Exiting startup script" >> $LOG
					exit 1
				fi
			done
		fi
	fi

}

# Initializes MySQL database if necessary.
#
#	Input: MAPR_METRICS_SERVER  (global)
#			MAPR_METRICS_DB		(global)
#			MAPR_METRICS_DEFAULT	(global)
#			MAPR_PACKAGES		(global)
#
# NOTE: It is simpler to use the hostname for mysql connections
#	even on the host running the mysql instance (probably because 
#	of mysql's strange handling of "localhost" when validating
#	login privileges).
#
# NOTE: The CentOS flavor of mapr-metrics depends on soci-mysql, which
#	is NOT in the base distro.  If the Extra Packages for Enterprise Linux
#	(epel) repository is not configured, we won't waste time with this
#	installation.

configure_mapr_metrics() {
	[ -z "${MAPR_METRICS_SERVER:-}" ] && return 0
	[ -z "${MAPR_METRICS_DB:-}" ] && return 0

	if which yum &> /dev/null; then
		yum list soci-mysql > /dev/null 2> /dev/null
		if [ $? -ne 0 ] ; then 
			echo "Skipping metrics configuration; missing dependencies" >> $LOG
			return 0
		fi
	fi

	echo "Configuring task metrics connection" >> $LOG

	# If the metrics server is specified, make sure the
	# metrics package is installed on every job tracker and 
	# webserver system ; otherwise, we'll just skip this step
	#
	#	NOTE: while it is unlikely that the METRICS_SERVER will
	#	have been specified WITHOUT the metrics package selected,
	#	we'll check for that case as well at this point.
	if [ ! -f $MAPR_HOME/roles/metrics ] ; then
		installMetrics=0
		[ $MAPR_METRICS_SERVER == $THIS_HOST ] && installMetrics=1
		[ -f $MAPR_HOME/roles/jobtracker ] && installMetrics=1
		[ -f $MAPR_HOME/roles/webserver ] && installMetrics=1

		[ $installMetrics -eq 0 ] && return 0

		if which dpkg &> /dev/null; then
			apt-get install -y --force-yes mapr-metrics
		elif which rpm &> /dev/null; then
			yum install -y mapr-metrics
		fi

		if [ $? -ne 0 ] ; then
			echo " ... installation of mapr-metrics failed" >> $LOG
			return 1
		fi
	fi

		# Don't exit the installation if this re-configuration fails
	echo "$MAPR_HOME/server/configure.sh -R -d ${MAPR_METRICS_SERVER}:3306 -du $MAPR_USER -dp $MAPR_PASSWD -ds $MAPR_METRICS_DB" >> $LOG
	$MAPR_HOME/server/configure.sh -R -d ${MAPR_METRICS_SERVER}:3306 \
		-du $MAPR_USER -dp $MAPR_PASSWD -ds $MAPR_METRICS_DB
	echo "   configure.sh returned $?" >> $LOG

		# Additional configuration required on WebServer nodes for MapR 1.x
		# Need to specify the connection metrics in the hibernate CFG file
		# Version 2 and beyond handles that configuration in configure.sh
	if [ -f $MAPR_HOME/roles/webserver  -a  ${MAPR_VERSION%%.*} = "1" ] ; then
		HIBCFG=$MAPR_HOME/conf/hibernate.cfg.xml
			# TO BE DONE ... fix database properties 
	fi
}


# Simple script to do any config file customization prior to 
# program launch
configure_mapr_services() {
	echo "Updating configuration for MapR services" >> $LOG

# Additional customizations ... to be customized based
# on instane type and other deployment details.   This is only
# necessary if the default configuration files from configure.sh
# are sub-optimal for Cloud deployments.  Some examples might be:
#	

	CLDB_CONF_FILE=${MAPR_HOME}/conf/cldb.conf
	MFS_CONF_FILE=${MAPR_HOME}/conf/mfs.conf
	WARDEN_CONF_FILE=${MAPR_HOME}/conf/warden.conf

# give MFS more memory -- only on slaves, not on masters
#sed -i 's/service.command.mfs.heapsize.percent=.*$/service.command.mfs.heapsize.percent=35/'

# give CLDB more threads 
# sed -i 's/cldb.numthreads=10/cldb.numthreads=40/' $MAPR_HOME/conf/cldb.conf

		# Disable central configuration (spinning up Java processes
		# every 5 minutes doesn't help; we'll run it on our own
	if [ -w $WARDEN_CONF_FILE ] ; then
		sed -i 's/centralconfig.enabled=true/centralconfig.enabled=false/' \
			${WARDEN_CONF_FILE}
	fi

		# Change mapr-warden initscript to create use "hostname"
		# instead of "hostname --fqdn".  Since the micro-dns
		# in the GCE environment does the right thing with
		# name resolution, it's OK to use short hostnames
	sed -i 's/ --fqdn//' $MAPR_HOME/initscripts/mapr-warden

}

#
#  Wait until DNS can find all the masters
#	Should put a timeout ont this ... it's really not well designed
#
function resolve_zknodes() {
	echo "WAITING FOR DNS RESOLUTION of zookeeper nodes {$zknodes}" >> $LOG
	zkready=0
	while [ $zkready -eq 0 ]
	do
		zkready=1
		echo testing DNS resolution for zknodes
		for i in ${zknodes//,/ }
		do
			[ -z "$(dig -t a +search +short $i)" ] && zkready=0
		done

		echo zkready is $zkready
		[ $zkready -eq 0 ] && sleep 5
	done
	echo "DNS has resolved all zknodes {$zknodes}" >> $LOG
	return 0
}


# MapR NFS services should be configured AFTER the cluster
# is running and the license is installed.
# 
# If the node is running NFS, then we default to a localhost
# mount; otherwise, we look for the spefication from our
# parameter file

MAPR_FSMOUNT=/mapr
MAPR_FSTAB=$MAPR_HOME/conf/mapr_fstab
SYSTEM_FSTAB=/etc/fstab

configure_mapr_nfs() {
	if [ -f $MAPR_HOME/roles/nfs ] ; then
		MAPR_NFS_SERVER=localhost
		MAPR_NFS_OPTIONS="hard,intr,nolock"
	else
		MAPR_NFS_OPTIONS="hard,intr"
	fi

		# Bail out now if there's not NFS server (either local or remote)
	[ -z "${MAPR_NFS_SERVER:-}" ] && return 0

		# For RedHat distros, we need to start up NFS services
	if which rpm &> /dev/null; then
		/etc/init.d/rpcbind restart
		/etc/init.d/nfslock restart
	fi

	echo "Mounting ${MAPR_NFS_SERVER}:/mapr/$cluster to $MAPR_FSMOUNT" >> $LOG
	mkdir $MAPR_FSMOUNT

	if [ $MAPR_NFS_SERVER = "localhost" ] ; then
		echo "${MAPR_NFS_SERVER}:/mapr/$cluster	$MAPR_FSMOUNT	$MAPR_NFS_OPTIONS" >> $MAPR_FSTAB

		maprcli node services -nfs restart -nodes `cat $MAPR_HOME/hostname`
	else
		echo "${MAPR_NFS_SERVER}:/mapr/$cluster	$MAPR_FSMOUNT	nfs	$MAPR_NFS_OPTIONS	0	0" >> $SYSTEM_FSTAB
		mount $MAPR_FSMOUNT
	fi
}

#
# Isolate the creation of the metrics database itself until
# LATE in the installation process, so that we can use the
# cluster database itself if we'd like.  Default to 
# using that resource, and fall back to local storage if
# the creation of the volume fails.
#
#	CAREFUL : this routine uses the MAPR_FSMOUNT variable defined just
#	above ... so don't rearrange this code without moving that as well
#
create_metrics_db() {
	[ -z "${MAPR_METRICS_SERVER:-}" ] && return
	[ $MAPR_METRICS_SERVER != $THIS_HOST ] && return

	echo "Creating MapR metrics database" >> $LOG

		# Install MySQL, update MySQL config and restart the server
	MYSQL_OK=1
	if  which dpkg &> /dev/null ; then
		apt-get install -y mysql-server mysql-client

		MYCNF=/etc/mysql/my.cnf
		sed -e "s/^bind-address.* 127.0.0.1$/bind-address = 0.0.0.0/g" \
			-i".localhost" $MYCNF 

		update-rc.d -f mysql enable
		service mysql stop
		MYSQL_OK=$?
	elif which rpm &> /dev/null  ; then 
		yum install -y mysql-server mysql

		MYCNF=/etc/my.cnf
		sed -e "s/^bind-address.* 127.0.0.1$/bind-address = 0.0.0.0/g" \
			-i".localhost" $MYCNF 

		chkconfig mysqld on
		service mysqld stop
		MYSQL_OK=$?
	fi

	if [ $MYSQL_OK -ne 0 ] ; then
		echo "Failed to install/configure MySQL" >> $LOG
		echo "Unable to create MapR metrics database" >> $LOG
		return 1
	fi

	echo "Initializing metrics database ($MAPR_METRICS_DB)" >> $LOG

		# If we have licensed NFS connectivity to the cluster, then 
		# we can create a MapRFS volume for the database and point there.
		# If the NFS mount point isn't visible, just leave the 
		# data directory as is and warn the user.
	useMFS=0
	maprcli license apps | grep -q -w "NFS" 
	if [ $? -eq 0 ] ; then
		[ -f $MAPR_HOME/roles/nfs ] && useMFS=1
		[ -n "${MAPR_NFS_SERVER}" ] && useMFS=1
	fi

		# SELINUX MUST be disabled in order for us to move the
		# MySQL data dir out from /var/lib/mysql.  This should
		# be established earlier in the system setup
		# Given that MySQL CANNOT use MFS if it is enabled, we default
		# to NOT using MFS unless we're SURE SELINUX is disabled.
	seState=`cat /selinux/enforce`
	[ -f /etc/selinux/config  -a  ${seState:-1} -eq 1 ] && useMFS=0

	if [ $useMFS -eq 1 ] ; then
#		MYSQL_DATA_DIR=/var/mapr/mysql
		MYSQL_DATA_DIR=/mysql

		dtKey="cldb.default.volume.topology"
		defTopology=`maprcli config load -keys $dtKey | grep -v $dtKey`

			# Create the volume and set ownership
			# We probably don't need both steps ... but just in case
		maprcli volume create -name mapr.mysql -user "mysql:fc root:fc" \
		  -path $MYSQL_DATA_DIR -createparent true -topology ${defTopology:-/} 
		maprcli acl edit -type volume -name mapr.mysql -user mysql:fc

		if [ $? -eq 0 ] ; then
				# Now we'll access the DATA_DIR via an NFS mount
			MYSQL_DATA_DIR=${MAPR_FSMOUNT}${MYSQL_DATA_DIR}

				# Short wait for NFS client to see newly created volume
			sleep 5
			find `dirname $MYSQL_DATA_DIR` &> /dev/null
			if [ -d ${MYSQL_DATA_DIR} ] ; then
				chown --reference=/var/lib/mysql $MYSQL_DATA_DIR

			    sedArg="`echo "$MYSQL_DATA_DIR" | sed -e 's/\//\\\\\//g'`"
				sed -e "s/^datadir[ 	=].*$/datadir = ${sedArg}/g" \
					-i".localdata" $MYCNF 

					# On Ubuntu, AppArmor gets in the way of
					# mysqld writing to the NFS directory; We'll 
					# unload the configuration here so we can safely
					# update the aliases file to enable the proper
					# access.  The profile will be reloaded when mysql 
					# is launched below
				if [ -f /etc/apparmor.d/usr.sbin.mysqld ] ; then
					echo "alias /var/lib/mysql/ -> ${MYSQL_DATA_DIR}/," >> \
						/etc/apparmor.d/tunables/alias

					apparmor_parser -R /etc/apparmor.d/usr.sbin.mysqld
				fi

					# Remember to initialize the new data directory !!!
					# If this fails, go back to the default datadir
				mysql_install_db --user=mysql
				if [ $? -ne 0 ] ; then
					echo "Failed to initialize MapRFS datadir ($MYSQL_DATA_DIR}" >> $LOG
					echo "Restoring localdata configuration" >> $LOG
					cp -p ${MYCNF}.localdata ${MYCNF}
				fi
			fi
		fi
	fi

		# Startup MySQL so the rest of this stuff will work
	[ -x /etc/init.d/mysql ]   &&  service mysql  start
	[ -x /etc/init.d/mysqld ]  &&  service mysqld start

		# At this point, we can customize the MySQL installation 
		# as needed.   For now, we'll just enable multiple connections
		# and create the database instance we need.
		#	WARNING: don't mess with the single quotes !!!
	mysql << metrics_EOF

create user '$MAPR_USER' identified by '$MAPR_PASSWD' ;
create user '$MAPR_USER'@'localhost' identified by '$MAPR_PASSWD' ;
grant all on $MAPR_METRICS_DB.* to '$MAPR_USER'@'%' ;
grant all on $MAPR_METRICS_DB.* to '$MAPR_USER'@'localhost' ;
quit

metrics_EOF

		# Update setup.sql in place, since we've picked
		# a new metrics db name.
	if [ !  $MAPR_METRICS_DB = $MAPR_METRICS_DEFAULT ] ; then
		sed -e "s/ $MAPR_METRICS_DEFAULT/ $MAPR_METRICS_DB/g" \
			-i".default" $MAPR_HOME/bin/setup.sql 
	fi
	mysql -e "source $MAPR_HOME/bin/setup.sql"

		# Lastly, we should set the root password to lock down MySQL
#	/usr/bin/mysqladmin -u root password "$MAPR_PASSWD"
}

function disable_mapr_services() 
{
	echo Disabling MapR services >> $LOG

	if which update-rc.d &> /dev/null; then
		[ -f $MAPR_HOME/conf/warden.conf ] && \
			c update-rc.d -f mapr-warden disable
		[ -f $MAPR_HOME/roles/zookeeper ] && \
			c update-rc.d -f mapr-zookeeper disable
	elif which chkconfig &> /dev/null; then
		[ -f $MAPR_HOME/conf/warden.conf ] && \
			c chkconfig mapr-warden off
		[ -f $MAPR_HOME/roles/zookeeper ] && \
			c chkconfig mapr-zookeeper off
	fi
}

function enable_mapr_services() 
{
	echo Enabling MapR services >> $LOG

	if which update-rc.d &> /dev/null; then
		[ -f $MAPR_HOME/conf/warden.conf ] && \
			c update-rc.d -f mapr-warden enable
		[ -f $MAPR_HOME/roles/zookeeper ] && \
			c update-rc.d -f mapr-zookeeper enable
	elif which chkconfig &> /dev/null; then
		[ -f $MAPR_HOME/conf/warden.conf ] && \
			c chkconfig mapr-warden on
		[ -f $MAPR_HOME/roles/zookeeper ] && \
			c chkconfig mapr-zookeeper on
	fi
}

function start_mapr_services() 
{
	echo "Starting MapR services" >> $LOG

	if [ -f $MAPR_HOME/roles/zookeeper ] ; then
		c service mapr-zookeeper start
	fi
	if [ -f $MAPR_HOME/conf/warden.conf ] ; then
		c service mapr-warden start
	fi

		# This is as logical a place as any to wait for HDFS to
		# come on line
	HDFS_ONLINE=0
	HDFS_MAX_WAIT=600
	echo "Waiting for hadoop file system to come on line" | tee -a $LOG
	i=0
	while [ $i -lt $HDFS_MAX_WAIT ] 
	do
		hadoop fs -stat /  2> /dev/null
		if [ $? -eq 0 ] ; then
			curTime=`date`
			echo " ... success at $curTime !!!" | tee -a $LOG
			HDFS_ONLINE=1
			i=9999
			break
		else
			echo " ... timeout in $[HDFS_MAX_WAIT - $i] seconds ($THIS_HOST)"
		fi

		sleep 3
		i=$[i+3]
	done

	if [ ${HDFS_ONLINE} -eq 0 ] ; then
		echo "ERROR: MapR File Services did not come on-line" >> $LOG
		exit 1
	fi
}

# Look to the cluster for shared ssh keys.  This function depends
# on the cluster being up and happy.  Don't worry about errors
# here, this is just a helper function
function retrieve_ssh_keys() 
{
	echo "Retrieving ssh keys for other cluster nodes" >> $LOG

	MAPR_USER_DIR=`eval "echo ~${MAPR_USER}"`
	clusterKeyDir=/cluster-info/keys

	hadoop fs -stat ${clusterKeyDir}
	[ $? -ne 0 ] && return 0

	kdir=$clusterKeyDir
		
		# Copy root keys FIRST ... since the MapR user keys are 
		# more important (and we want to give more time)
	akFile=/root/.ssh/authorized_keys
	for kf in `hadoop fs -ls ${kdir} | grep ${kdir} | grep _root | awk '{print $NF}' | sed "s_${kdir}/__g"`
	do
		echo "  found $kf"
		if [ ! -f /root/.ssh/$kf ] ; then
			hadoop fs -get ${kdir}/${kf} /root/.ssh/$kf
			cat /root/.ssh/$kf >> ${akFile}
		fi
	done

	akFile=${MAPR_USER_DIR}/.ssh/authorized_keys
	for kf in `hadoop fs -ls ${kdir} | grep ${kdir} | grep _${MAPR_USER} | awk '{print $NF}' | sed "s_${kdir}/__g"`
	do
		echo "  found $kf"
		if [ ! -f ${MAPR_USER_DIR}/.ssh/$kf ] ; then
			hadoop fs -get ${kdir}/${kf} ${MAPR_USER_DIR}/.ssh/$kf
			cat ${MAPR_USER_DIR}/.ssh/$kf >> ${akFile}
			chown --reference=${MAPR_USER_DIR}/.bashrc \
				${MAPR_USER_DIR}/.ssh/$kf ${akFile}
		fi
	done
}

# Enable FullControl for MAPR_USER and install license if we've been
# given one.  When this function is run, we KNOW that the cluster
# is up and running (we have access to the distributed file system)
function finalize_mapr_cluster() 
{
	echo "Entering finalize_mapr_cluster" >> $LOG

	which maprcli  &> /dev/null
	if [ $? -ne 0 ] ; then
		echo "maprcli command not found" >> $LOG
		echo "This is typical on a client-only install" >> $LOG
		return
	fi
																
	c maprcli acl edit -type cluster -user ${MAPR_USER}:fc

		# Archive the SSH keys into the cluster; we'll pull 
		# them down later.  When all nodes are spinning up at the
		# same time, this 'mostly' works to distribute keys ...
		# since everyone waited for the CLDB to come on line.
		#
		# Root keys for nodes 0 and 1 are distributed; MapR keys
		# for node 0 and all webserver nodes are distributed
	MAPR_USER_DIR=`eval "echo ~${MAPR_USER}"`
	clusterKeyDir=/cluster-info/keys
	rootKeyFile=/root/.ssh/id_rsa.pub
	maprKeyFile=${MAPR_USER_DIR}/.ssh/id_rsa.pub

	if [ ${AMI_LAUNCH_INDEX:-2} -le 1  -a  -f ${rootKeyFile} ] ; then 
		hadoop fs -put $rootKeyFile \
		  $clusterKeyDir/id_rsa_root.${AMI_LAUNCH_INDEX}
	fi
	if [ -f ${maprKeyFile} ] ; then
		if [ -${AMI_LAUNCH_INDEX:-1} -eq 0  -o  -f $MAPR_HOME/roles/webserver ]
		then
			hadoop fs -put $maprKeyFile \
			  $clusterKeyDir/id_rsa_${MAPR_USER}.${AMI_LAUNCH_INDEX}
		fi 
	fi

	license_installed=0
	if [ -n "${MAPR_LICENSE_FILE:-}"  -a  -f "${MAPR_LICENSE_FILE}" ] ; then
		for lic in `maprcli license list | grep hash: | cut -d" " -f 2 | tr -d "\""`
		do
			grep -q $lic $MAPR_LICENSE_FILE
			[ $? -eq 0 ] && license_installed=1
		done

		if [ $license_installed -eq 0 ] ; then 
			echo "maprcli license add -license $MAPR_LICENSE_FILE -is_file true" >> $LOG
			maprcli license add -license $MAPR_LICENSE_FILE -is_file true >> $LOG
			[ $? -eq 0 ] && license_installed=1
		fi

		[ $license_installed -eq 1 ] && rm -f $MAPR_LICENSE_FILE
	else
		echo $MAPR_PACKAGES | grep -q cldb
		if [ $? -eq 0 ] ; then
			echo "No license provided ... please install one at your earliest convenience" >> $LOG
		fi
	fi

	MAPR_LICENSE_INSTALLED="$license_installed"
	export MAPR_LICENSE_INSTALLED
}

#
# Disable starting of MAPR, and clean out the ID's that will be intialized
# with the full install. 
#	NOTE: the instantiation process from an image generated via
#	this script MUST recreate the hostid and hostname files
#
function deconfigure_mapr() 
{
	c mv -f $MAPR_HOME/hostid    $MAPR_HOME/conf/hostid.image
	c mv -f $MAPR_HOME/hostname  $MAPR_HOME/conf/hostname.image

	if which dpkg &> /dev/null; then
		if [ -f $MAPR_HOME/conf/warden.conf ] ; then
			c update-rc.d -f mapr-warden remove
		fi
		echo $MAPR_PACKAGES | grep -q zookeeper
		if [ $? -eq 0 ] ; then
			c update-rc.d -f mapr-zookeeper remove
		fi
	elif which rpm &> /dev/null; then
		if [ -f $MAPR_HOME/conf/warden.conf ] ; then
			c chkconfig mapr-warden off
		fi
		echo $MAPR_PACKAGES | grep -q zookeeper
		if [ $? -eq 0 ] ; then
			c chkconfig mapr-zookeeper off
		fi
	fi
}

function add_mapr_user() {
	echo Adding/configuring mapr user >> $LOG
	id $MAPR_USER &> /dev/null
	[ $? -eq 0 ] && return $? ;

	useradd -u $MAPR_UID -c "MapR" -m -s /bin/bash $MAPR_USER 2> /dev/null
	if [ $? -ne 0 ] ; then
			# Assume failure was dup uid; try with default uid assignment
		useradd -c "MapR" -m -s /bin/bash $MAPR_USER
	fi

	if [ $? -ne 0 ] ; then
		echo "Failed to create new user $MAPR_USER"
		return 1
	else
		passwd $MAPR_USER << passwdEOF
$MAPR_PASSWD
$MAPR_PASSWD
passwdEOF

	fi

		# Create sshkey for $MAPR_USER (must be done AS MAPR_USER)
	su $MAPR_USER -c "mkdir ~${MAPR_USER}/.ssh ; chmod 700 ~${MAPR_USER}/.ssh"
	su $MAPR_USER -c "ssh-keygen -q -t rsa -f ~${MAPR_USER}/.ssh/id_rsa -P '' "
	su $MAPR_USER -c "cp -p ~${MAPR_USER}/.ssh/id_rsa ~${MAPR_USER}/.ssh/id_launch"
	su $MAPR_USER -c "cp -p ~${MAPR_USER}/.ssh/id_rsa.pub ~${MAPR_USER}/.ssh/authorized_keys"
	su $MAPR_USER -c "chmod 600 ~${MAPR_USER}/.ssh/authorized_keys"
		
		# And copy the AWS key-pair into place ... which will
		# enable simple ssh commands from the launcher
	MAPR_USER_DIR=`eval "echo ~${MAPR_USER}"`
	LAUNCHER_SSH_KEY_FILE=$MAPR_USER_DIR/.ssh/id_launcher.pub
	curl ${murl_top}/public-keys/0/openssh-key > $LAUNCHER_SSH_KEY_FILE
	if [ $? -eq 0 ] ; then
		cat $LAUNCHER_SSH_KEY_FILE >> $MAPR_USER_DIR/.ssh/authorized_keys
	fi

		# Enhance the login with rational stuff
    cat >> $MAPR_USER_DIR/.bashrc << EOF_bashrc

CDPATH=.:$HOME
export CDPATH

# PATH updates based on settings in MapR env file
MAPR_HOME=${MAPR_HOME:-/opt/mapr}
MAPR_ENV=\${MAPR_HOME}/conf/env.sh
[ -f \${MAPR_ENV} ] && . \${MAPR_ENV} 
[ -n "\${JAVA_HOME}:-" ] && PATH=\$PATH:\$JAVA_HOME/bin
[ -n "\${MAPR_HOME}:-" ] && PATH=\$PATH:\$MAPR_HOME/bin

set -o vi

EOF_bashrc

	return 0
}

function update_root_user() {
  echo "Updating root user" >> $LOG
  
    cat >> /root/.bashrc << EOF_bashrc

CDPATH=.:$HOME
export CDPATH

set -o vi

EOF_bashrc

	# Amazon shoves our key into the root users authorized_keys
	# file, but disables it explicitly.  This logic removes those
	# constraints (provided our key is an rsa key; you might want
	# to expand this to support dsa keys as well.
  sed -i -e "s/^.*ssh-rsa /ssh-rsa /g" /root/.ssh/authorized_keys

  ssh-keygen -q -t rsa -P "" -f /root/.ssh/id_rsa

  # We could take this opportunity to copy the public key of 
  # the mapr user into root's authorized key file ... but let's not for now
  return 0
}

function setup_mapr_repo_deb() {
    MAPR_REPO_FILE=/etc/apt/sources.list.d/mapr.list
    MAPR_PKG="http://package.mapr.com/releases/v${MAPR_VERSION}/ubuntu"
    MAPR_ECO="http://package.mapr.com/releases/ecosystem/ubuntu"

   	echo Setting up repos in $MAPR_REPO_FILE
    if [ ! -f $MAPR_REPO_FILE ] ; then
    	cat > $MAPR_REPO_FILE << EOF_ubuntu
deb $MAPR_PKG mapr optional
deb $MAPR_ECO binary/
EOF_ubuntu
	else
  		sed -i "s|/releases/v.*/|/releases/v${MAPR_VERSION}/|" $MAPR_REPO_FILE
	fi

    apt-get update
}

function setup_mapr_repo_rpm() {
    MAPR_REPO_FILE=/etc/yum.repos.d/mapr.repo
    MAPR_PKG="http://package.mapr.com/releases/v${MAPR_VERSION}/redhat"
    MAPR_ECO="http://package.mapr.com/releases/ecosystem/redhat"

    if [ -f $MAPR_REPO_FILE ] ; then
  		sed -i "s|/releases/v.*/|/releases/v${MAPR_VERSION}/|" $MAPR_REPO_FILE
    	yum clean all
    	yum makecache
		return 
	fi

    echo Setting up repos in $MAPR_REPO_FILE
    cat > $MAPR_REPO_FILE << EOF_redhat
[MapR]
name=MapR Core Components
baseurl=$MAPR_PKG
${MAPR_PKG//package.mapr.com/archive.mapr.com}
enabled=1
gpgcheck=0
protected=1

[MapR_ecosystem]
name=MapR Ecosystem Components
baseurl=$MAPR_ECO
enabled=1
gpgcheck=0
protected=1
EOF_redhat

        # Metrics requires some packages in EPEL ... so we'll
        # add those repositories as well
        #   NOTE: this target will change FREQUENTLY !!!
    EPEL_RPM=/tmp/epel.rpm
    CVER=`lsb_release -r | awk '{print $2}'`
    if [ ${CVER%.*} -eq 5 ] ; then
        EPEL_LOC="epel/5/x86_64/epel-release-5-4.noarch.rpm"
    else
        EPEL_LOC="epel/6/x86_64/epel-release-6-8.noarch.rpm"
    fi

    wget -O $EPEL_RPM http://download.fedoraproject.org/pub/$EPEL_LOC
    [ $? -eq 0 ] && rpm --quiet -i $EPEL_RPM

	yum clean all
	yum makecache
}

function setup_mapr_repo() {
  if which dpkg &> /dev/null; then
    setup_mapr_repo_deb
  elif which rpm &> /dev/null; then
    setup_mapr_repo_rpm
  fi
}

function do_initial_install()
{
	update_os
	install_java

	setup_mapr_repo
	add_mapr_user
	update_root_user
	return $?
}

function main() 
{
	echo "$0 script started at "`date` >> $LOG

	if [ `id -u` -ne 0 ] ; then
		echo "	ERROR: script must be run as root" >> $LOG
		exit 1
	fi

	muser=`id -un $MAPR_USER 2> /dev/null`
	if [ $? -ne 0 ] ; then
		do_initial_install
		if [ $? -ne 0 ] ; then
			echo "incomplete system initialization" >> $LOG
			echo "$0 script exiting with error at "`date` >> $LOG
			exit 1
		fi

			# As a last act, copy this script into ~${MAPR_HOME} 
			# for later use when we actually spin-up the node
		MAPR_USER_DIR=`eval "echo ~${MAPR_USER}"`
		cp $0 $MAPR_USER_DIR/launch-mapr-instance.sh
		if [ $? -eq 0 ] ; then
			chown ${MAPR_USER}:`id -gn ${MAPR_USER}` \
				$MAPR_USER_DIR/launch-mapr-instance.sh
		fi

		echo "system initialization complete at "`date` >> $LOG
		echo "$0 script may pause at this point" >> $LOG
	fi

		# Bail out here if we don't have a MAPR_USER configured
	[ `id -un $MAPR_USER` != "${MAPR_USER}" ] && return 1

		# Look for the parameter file that will have the 
		# variables necessary to complete the installation
	MAPR_USER_DIR=`eval "echo ~${MAPR_USER}"`
	MAPR_PARM_FILE=$MAPR_USER_DIR/mapr.parm
	[ ! -f $MAPR_PARM_FILE ] && return 1

		# And finish up the installation (if we have rational parameters)
		# Be careful ... this script has some defaults for MAPR_USER
		# and MAPR_HOME that we should probably check for overrides here.
	[ -r /etc/profile.d/javahome.sh ] &&  . /etc/profile.d/javahome.sh
	. $MAPR_PARM_FILE
		
	if [ -z "${cluster}" -o  -z "${zknodes}"  -o  -z "${cldbnodes}" ] ; then
	    echo "Insufficient specification for MapR cluster ... terminating script" >> $LOG
		exit 1
	fi

		# The parameters MAY have given us a new MAPR_VERSION 
		# setting (in the case where the meta-data was not available).
		# Update the repo specification appropriately.
	setup_mapr_repo

		# If this instance came from an image with MapR software
		# pre-installed, we'll need to regenerate the ID files AFTER
		# the installation of our target packages (which may be different
		# than the onces from the image).
	test -f $MAPR_HOME/hostid && REGEN_MAPR_HOSTID="yes"
	install_mapr_packages
	[ "${REGEN_MAPR_HOSTID:-}" = "yes" ] && regenerate_mapr_hostid

	[ -n "${AMI_IMAGE}" ] && VMARG="--isvm"
	if [ ${MAPR_VERSION%%.*} -ge 3 ] ; then
		if [ ${MAPR_VERSION} -ne "3.0.0-GA" ] ; then
			echo $MAPR_PACKAGES | grep -q hbase
			[ $? -eq 0 ] && M7ARG="-M7"
		fi
	fi

		# Waiting for the nodes at this point SHOULD be unnecessary,
		# since we had to have the node alive to re-spawn this part
		# of the script.  So we can just do the configuration
	c $MAPR_HOME/server/configure.sh -N $cluster -C $cldbnodes -Z $zknodes \
	    -u $MAPR_USER -g $MAPR_GROUP $M7ARG $VMARG

	configure_mapr_metrics
	configure_mapr_services

	provision_mapr_disks

		# Most of the time in Amazon we DO NOT want to
		# auto-start ... so we'll control that here.
	if [ -z "${AMI_IMAGE}" ] ; then
		enable_mapr_services
	else
		disable_mapr_services
	fi

	resolve_zknodes
	if [ $? -eq 0 ] ; then
		start_mapr_services
		[ $? -ne 0 ] && return $?

		finalize_mapr_cluster

		configure_mapr_nfs

		create_metrics_db

		retrieve_ssh_keys
	fi

	echo "$0 script completed at "`date` >> $LOG
	echo IMAGE READY >> $LOG
	return 0
}

main $@
exitCode=$?

# Save log to ~${MAPR_USER} ... since Ubuntu images erase /tmp
MAPR_USER_DIR=`eval "echo ~${MAPR_USER}"`
if [ -n "${MAPR_USER_DIR}"  -a  -d ${MAPR_USER_DIR} ] ; then
		cp $LOG $MAPR_USER_DIR
		chmod a-w ${MAPR_USER_DIR}/`basename $LOG`
		chown $MAPR_USER:$MAPR_GROUP ${MAPR_USER_DIR}/`basename $LOG`
fi

exit $exitCode
