#! /bin/bash
#
#   $File: launch-mapr-instance.sh $
#   $Date: Wed Aug 28 09:47:15 2013 -0700 $
#   $Author: dtucker $
#
# Script to be executed on top of a newly created Linux instance 
# within a cloud environment to prepare an instance for later execution
# of configure-mapr-instance script.
#
# Expectations:
#	- Script run as root user (hence no need for permission checks)
#	- Basic distro differences (APT-GET vs YUM, etc) can be handled
#	    There are so few differences, it seemed better to manage one script.
#
# Tested with MapR 2.0.1, 2.1.x, 3.0.x
#

# What little meta-data Amazon passes in is available here
murl_top=http://169.254.169.254/latest/meta-data

# Definitions for our installation
#	Long term, we should handle reconfiguration of
#	these values at cluster launch ... but it's difficult
#	without a clean way of passing meta-data to the script
MAPR_VERSION=${MAPR_VERSION:-3.0.1}
MAPR_HOME=/opt/mapr
MAPR_UID=${MAPR_UID:-"2000"}
MAPR_USER=${MAPR_USER:-mapr}
MAPR_PASSWD=${MAPR_PASSWD:-MapR}

LOG=/tmp/launch-mapr.log

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

# For CentOS, add the EPEL repo
#
function add_epel_repo() {
    EPEL_RPM=/tmp/epel.rpm
    CVER=`lsb_release -r | awk '{print $2}'`
    if [ "${CVER%.*}" -eq 5 ] ; then
        EPEL_LOC="epel/5/x86_64/epel-release-5-4.noarch.rpm"
    else
        EPEL_LOC="epel/6/x86_64/epel-release-6-8.noarch.rpm"
    fi

    wget -O $EPEL_RPM http://download.fedoraproject.org/pub/$EPEL_LOC
    [ $? -eq 0 ] && rpm --quiet -i $EPEL_RPM
}

function update_os_deb() {
	apt-get update
#	apt-get upgrade -y --force-yes -o Dpkg::Options::="--force-confdef,confold"
	apt-get install -y nfs-common iputils-arping libsysfs2
	apt-get install -y ntp 
	apt-get install -y unzip
	apt-get install -y realpath

	apt-get install -y syslinux sdparm
	apt-get install -y sysstat

	apt-get install -y clustershell pdsh
}

function update_os_rpm() {
	add_epel_repo

	yum makecache
#	yum update -y
	yum install -y bind-utils
	yum install -y nfs-utils iputils libsysfs
	yum install -y ntpd ntpdate 
	yum install -y unzip
	yum install -y realpath

	yum install -y syslinux sdparm
	yum install -y nmap sysstat

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
	zoneInfo=$(curl -f ${murl_top}/placement/availability-zone)
	curZone=`basename "${zoneInfo}"`
	curTZ=`date +"%Z"`
	echo "    Instance zone is ${curZone:-UNKNOWN}; TZ setting is $curTZ" >> $LOG

		# Update the timezones we're sure of.
	TZ_HOME=/usr/share/zoneinfo/posix
	case $curZone in
		us-west*)
			newTZ="PST8PDT"
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

function update_sudo_config() {
	echo "  updating sudo configuration" >> $LOG

	# allow sudo with ssh (we'll need to later)
  sed -i 's/^Defaults .*requiretty$/# Defaults requiretty/' /etc/sudoers
}

function update_ssh_config() {
	echo "  updating SSH configuration" >> $LOG

	# allow ssh via keys (some virtual environments disable this)
  sed -i 's/#AuthorizedKeysFile/AuthorizedKeysFile/' /etc/ssh/sshd_config

	# allow ssh password prompt (only for our dev clusters)
  sed -i 's/ChallengeResponseAuthentication .*no$/ChallengeResponseAuthentication yes/' /etc/ssh/sshd_config
}

# Break out the restarting of ssh to avoid the situation where
# our external provisioning automation will get prompted for
# a password when trying to log in as the "mapr" user.
function restart_ssh() {
	echo "  restarting SSH service" >> $LOG

	[ -x /etc/init.d/ssh ]   &&  /etc/init.d/ssh  restart
	[ -x /etc/init.d/sshd ]  &&  /etc/init.d/sshd restart
}

function update_os() {
  echo "Installing OS security updates and useful packages" >> $LOG

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
#  restart_ssh		# delay till the end of the entire script

	# iptables is VERY disruptive to our installations.
	# The default ubuntu config is to allow everything ... so no
	# need to mess with it here.
  if which dpkg &> /dev/null; then
    service ufw status
#	update-rc.d ufw disable
  elif which rpm &> /dev/null; then
    service iptables stop
	chkconfig iptables off
  fi
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
    echo "	JAVA_HOME=$JAVA_HOME" | tee -a $LOG
}

function install_openjdk_rpm() {
    echo "Installing OpenJDK packages (for rpm distros)" >> $LOG

	yum install -y java-1.7.0-openjdk java-1.7.0-openjdk-devel 
	yum install -y java-1.7.0-openjdk-javadoc

	JAVA_HOME=/usr/lib/jvm/java-1.7.0-openjdk.x86_64
	export JAVA_HOME
    echo "	JAVA_HOME=$JAVA_HOME" | tee -a $LOG
}

# This has GOT TO SUCCEED ... otherwise the node is useless for MapR
function install_java() {
  echo Installing JAVA >> $LOG

	# If Java is already installed, simply make sure we know
	# the JAVA_HOME.   We should be smarter about checking for
	# a valid version, but since both 1.6 and 1.7 work, we should
	# be safe.
	#
  javacmd=`which java`
  if [ $? -eq 0 ] ;  then
	echo "Java already installed on this instance" >> $LOG
  	java -version 2>&1 | head -1 >> $LOG

		# We could be linked to the JRE or JDK version; we need
		# the REAL jdk, so look for javac in the directory we choose
	jcmd=`python -c "import os; print os.path.realpath('$javacmd')"`
	if [ -x ${jcmd%/jre/bin/java}/bin/javac ] ; then
		JAVA_HOME=${jcmd%/jre/bin/java}
	elif [ -x ${jcmd%/java}/javac ] ; then
		JAVA_HOME=${jcmd%/java}
	else
		JAVA_HOME=""
	fi

	if [ -n "${JAVA_HOME:-}" ] ; then
    	echo "	JAVA_HOME=$JAVA_HOME" | tee -a $LOG

		echo updating /etc/profile.d/javahome.sh >> $LOG
		echo "JAVA_HOME=${JAVA_HOME}" >> /etc/profile.d/javahome.sh
		echo "export JAVA_HOME" >> /etc/profile.d/javahome.sh

		return 0
	fi

	echo "Could not identify JAVA_HOME; will install Java ourselves" >> $LOG
  fi

  attempts=0
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
	attempts=$[attempts+1]
  done 

  echo "!!! Java installation FAILED !!!  Node unusable !!!" >> $LOG
  return 1
}


# We need to handle the case where the MapR user may
# alreay have some keys ... but we want the keys for THIS
# instantiation to be added
#
function update_mapr_ssh() {
	echo Configuring mapr ssh keys >> $LOG

	MAPR_USER_DIR=`eval "echo ~${MAPR_USER}"`

		# Create sshkey for $MAPR_USER (must be done AS MAPR_USER)
	if [ ! -d $MAPR_USER_DIR/.ssh ] ; then
		su $MAPR_USER -c "mkdir ${MAPR_USER_DIR}/.ssh"
		chmod 700 ${MAPR_USER_DIR}/.ssh
	fi
	if [ ! -f $MAPR_USER_DIR/.ssh/id_rsa ] ; then
		su $MAPR_USER -c "ssh-keygen -q -t rsa -f ${MAPR_USER_DIR}/.ssh/id_rsa -P '' "
		cp -p ${MAPR_USER_DIR}/.ssh/id_rsa ${MAPR_USER_DIR}/.ssh/id_launch
		cat ${MAPR_USER_DIR}/.ssh/id_rsa.pub >> \
			${MAPR_USER_DIR}/.ssh/authorized_keys
		chmod 600 ${MAPR_USER_DIR}/.ssh/authorized_keys
		chown --reference=${MAPR_USER_DIR}/.ssh/id_rsa \
			${MAPR_USER_DIR}/.ssh/authorized_keys
	fi
		
		# No matter what, copy the AWS key-pair into place ... 
		# which will enable simple ssh commands from the launcher
		# NOTE: we NEED this for the mechanics of cluster deployment !!!
	MAPR_USER_DIR=`eval "echo ~${MAPR_USER}"`
	LAUNCHER_SSH_KEY_FILE=$MAPR_USER_DIR/.ssh/id_launcher.pub
	curl -f ${murl_top}/public-keys/0/openssh-key > $LAUNCHER_SSH_KEY_FILE
	if [ $? -eq 0 ] ; then
		cat $LAUNCHER_SSH_KEY_FILE >> \
			${MAPR_USER_DIR}/.ssh/authorized_keys
		chmod 600 ${MAPR_USER_DIR}/.ssh/authorized_keys
		chown --reference=${MAPR_USER_DIR}/.ssh/id_rsa \
			$LAUNCHER_SSH_KEY_FILE \
			${MAPR_USER_DIR}/.ssh/authorized_keys
	fi
}

function add_mapr_user() {
	echo Adding/configuring mapr user >> $LOG
	id $MAPR_USER &> /dev/null
	if [ $? -eq 0 ] ; then
			# Force the password to what we expect from our scripts
		passwd $MAPR_USER << passwdEOF > /dev/null
$MAPR_PASSWD
$MAPR_PASSWD
passwdEOF

		return 0
	fi

	useradd -u $MAPR_UID -c "MapR" -m -s /bin/bash $MAPR_USER 2> /dev/null
	if [ $? -ne 0 ] ; then
			# Assume failure was dup uid; try with default uid assignment
		useradd -c "MapR" -m -s /bin/bash $MAPR_USER
	fi

	if [ $? -ne 0 ] ; then
		echo "Failed to create new user $MAPR_USER {error code $?}"
		return 1
	else
		passwd $MAPR_USER << passwdEOF
$MAPR_PASSWD
$MAPR_PASSWD
passwdEOF

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

  if [ ! -e /root/.ssh/id_rsa ] ; then
  	ssh-keygen -q -t rsa -P "" -f /root/.ssh/id_rsa
  fi

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
${MAPR_ECO//package.mapr.com/archive.mapr.com}
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
    [ $? -eq 0  -a  ! -f /etc/yum.repos.d/epel.repo ] && rpm --quiet -i $EPEL_RPM

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
		# In Amazon VPC configs, we need to execute some sudo operations
		# in order for the update processes to work .. so we need to
		# to disable the "requiretty" limitation immediately
	update_sudo_config

	update_os
	install_java

	setup_mapr_repo
	add_mapr_user
	update_mapr_ssh
	update_root_user
	retCode=$?

		# Last thing we do is restart ssh; no need to track
		# error status on this ... nothing we could do with the
		# error anyway.
	restart_ssh

	return $retCode
}

function main() 
{
	echo "$0 script started at "`date` >> $LOG
	echo "" >> $LOG
	env | sort >> $LOG
	echo "" >> $LOG

	muser=`id -u $MAPR_USER 2> /dev/null`
	if [ -z "${muser}"  -o  ${muser:-0} -gt 9999 ] ; then
		do_initial_install
		if [ $? -ne 0 ] ; then
			echo "incomplete system initialization" >> $LOG
			echo "$0 script exiting with error at "`date` >> $LOG
			exit 1
		fi

			# As a last act, copy this script into ~${MAPR_USER}.
			# We may re-use the script if an AMI is generated
			# after its execution ... and it's also just a 
			# good practice for keeping track of the activity.
		MAPR_USER_DIR=`eval "echo ~${MAPR_USER}"`
		cp $0 $MAPR_USER_DIR/launch-mapr-instance.sh
		if [ $? -eq 0 ] ; then
			chown ${MAPR_USER}:`id -gn ${MAPR_USER}` \
				$MAPR_USER_DIR/launch-mapr-instance.sh
		fi

		echo "system initialization complete at "`date` >> $LOG
		echo "$0 script may pause at this point" >> $LOG
	else
		setup_mapr_repo
	fi

	return 0
}

main $@
exitCode=$?

# Save log to ~${MAPR_USER} ... since Ubuntu images erase /tmp
MAPR_USER_DIR=`eval "echo ~${MAPR_USER}"`
if [ -n "${MAPR_USER_DIR}"  -a  -d ${MAPR_USER_DIR} ] ; then
		cp $LOG $MAPR_USER_DIR
		chmod a-w ${MAPR_USER_DIR}/`basename $LOG`
		chown ${MAPR_USER}:`id -gn ${MAPR_USER}` \
			${MAPR_USER_DIR}/`basename $LOG`
fi

exit $exitCode

