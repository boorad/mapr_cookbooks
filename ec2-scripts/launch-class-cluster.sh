#!/bin/bash
#
#   $File: launch-class-cluster.sh $
#   $Date: Tue Aug 06 14:41:57 2013 -0700 $
#   $Author: dtucker $
#
#  Script to launch a MapR M5 cluster in the Amazon Cloud for use
#	in sanctioned training courses.  Cluster configuration defined
#	in simple file of the form
#		${NODE_NAME_ROOT}<index>:<packages>
#	for all the nodes you desire.  The 'mapr-' prefix is not necessary
#	for the packages. Any line that does NOT start with ${NODE_NAME_ROOT}
#	is treated as a comment.
#
#	A sample config file is
#		node0:zookeeper,cldb,fileserver,tasktracker,nfs,webserver
#		node1:zookeeper,cldb,fileserver,tasktracker,nfs
#		node2:zookeeper,jobtracker,fileserver,tasktracker,nfs
#
# Assumptions:
#	ec2-run-instances tool is in the path
#	AWS/EC2 env variables set for target AWS account
#		EC2_HOME, AWS_USER, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
#
#	TBD : Be smarter about licensing (maybe in the config file)
#
# Things to remember:
#	- node numbering in config file should start at '0'
#	- AMI's are region-specific; verify that the AMI exists in target region
#	- the 'key name' in AWS should match the file name specified here
#
#
# EXAMPLES
#		# With Vanilla CentOS AMI
#	 ./launch-class-cluster.sh \
#		--cluster dbt \
#		--mapr-version 2.1.3 \
#		--config-file class/5node.lst \
#		--region us-west-2
#		--key-file ~/.ssh/tucker-eng \
#		--image ami-72ce4642 \
#		--image-su ec2-user  \
#		--instance-type m1.large \
#		--nametag foobar \
#		--days-to-live 1
#
#		# With MapR Custom AMI
#	 ./launch-class-cluster.sh \
#		--cluster train \
#		--mapr-version 2.1.3 \
#		--config-file class/3node.lst \
#		--region us-west-1
#		--key-file ~/.ssh/students07172012 \
#		--image ami-89ddf3cc \
#		--image-su ubuntu  \
#		--instance-type m1.xlarge \
#		--data-disks 2 \
#		--nametag foobar \
#		--days-to-live 1
#

THIS_SCRIPT=$0

# The LAUNCH script gets passed to the instances as user-data and
# then the CONFIG script is later invoked again to finish the
# configuration.
#	BOTH SCRIPTS should be here in the local directory.
#
MAPR_USER=mapr
MAPR_LAUNCH_SCRIPT=launch-mapr-instance.sh
MAPR_CONFIG_SCRIPT=configure-mapr-instance.sh

NODE_NAME_ROOT=node		# used in config file to define nodes for deployment


usage() {
  echo "
  Usage:
    $THIS_SCRIPT
       --cluster <clustername>
       --mapr-version <version, eg 1.2.3>
       --config-file <configuration file>
       --region <ec2-region>
       --image <AMI name>
       --image-su <sudo-user for image>
       --instance-type <instance-type>
	   --key-file <ec2-private-key-file>
       [ --zone ec2-availability-zone ]
	   [ --license-file <license to be installed> ]
	   [ --data-disks <# of ephemeral disks to FORCE into the AMI> ]
	   [ --nametag <uniquifying cluster tag> ]
	   [ --days-to-live <max lifetime> ]
   "
  echo ""
  echo "EXAMPLES"
  echo "  $0 --cluster MyCluster --mapr-version 2.1.3 --config-file class/10node.lst --region us-west-2 --key-file ~/.ssh/id_rsa --image ami-72ce4642 --image-su ec2-user --instance-type m1.large"
}



if [ -z "${AWS_USER}" -o -z "${AWS_SECRET_ACCESS_KEY}" -o -z "${AWS_ACCESS_KEY_ID}" ]
then
	echo "Error: AWS account environment variables missing"
	echo "    Please set AWS_USER, AWS_SECRET_ACCESS_KEY, and AWS_ACCESS_KEY_ID"
	echo "    in your environment before using this script"
	exit 1
fi

if [ -z "${EC2_HOME}" ]
then
	echo "Error: EC2_HOME environment variable missing"
	echo "    Please set EC2_HOME to the location of the EC2 utilities"
	echo "    before using this script"
	exit 1
fi

if [ -z "${EC2_DEFAULT_ARGS}" ] ; then
	EC2_DEFAULT_ARGS="-O $AWS_ACCESS_KEY_ID -W $AWS_SECRET_ACCESS_KEY"
	export EC2_DEFAULT_ARGS
fi


while [ $# -gt 0 ]
do
  case $1 in
  --cluster)      cluster=$2  ;;
  --instance-type) instancetype=$2  ;;
  --image)        image=$2 ;;
  --image-su)     ec2user=$2 ;;
  --mapr-version) maprversion=$2  ;;
  --config-file)  configFile=$2  ;;
  --key-file)     ec2keyfile=$2  ;;
  --region)       region=$2  ;;
  --zone)         zone=$2 ;;
  --data-disks)   dataDisks=$2 ;;
  --license-file) licenseFile=$2 ;;
  --nametag)      nametag=$2 ;;
  --days-to-live) daysToLive=$2 ;;
  *)
     echo "**** Bad argument: " $1
     usage
     exit  ;;
  esac
  shift 2
done

echo ""
echo "Validating command line arguments"
echo ""

# Defaults for simpler testing
maprversion=${maprversion:-"2.1.3"}
instancetype=${instancetype:-"m1.large"}
region=${region:-"us-west-1"}
ec2keyfile=${ec2keyfile:-"$HOME/.ssh/tucker-eng"}
if [ ${maprversion%%.*} -le 2 ] ; then
	licenseFile=${licenseFile:-"$HOME/Documents/MapR/licenses/LatestDemoLicense-M5.txt"}
else
    licenseFile=${licenseFile:-"$HOME/Documents/MapR/licenses/LatestDemoLicense-M7.txt"}
fi

# Don't deal with licensing if the file doesn't exist
[ ! -r ${licenseFile} ] && licenseFile=""

if [ -n "${nametag}" ] ; then
	tagSuffix="-${nametag}"
fi


# TO BE DONE
#	Error check paramters here !!!
#		Things to remember
#			- cluster must have at least 2 nodes (one of which is a master)
#			- availability zone must be within region
#

if [ -z "${configFile}" ] ; then
	echo "Error: no configuration file specified"
	usage
	exit 1
fi

if [ ! -r "${configFile}" ] ; then
	echo "Error: configuration file ($configFile) not found"
	usage
	exit 1
fi

nhosts=`grep -c ^$NODE_NAME_ROOT $configFile`
if [ $nhosts -lt 1 ] ; then
	echo "Error: configuration file $configFile does not specify any nodes"
	echo "   (nodes shoud be identified with $NODE_NAME_ROOT prefix)"
 	exit 1
fi

if [ -z "${ec2keyfile}" ] ; then
	echo "Error: no SSH KeyFile specified"
	usage
	exit 1
fi

if [ ! -r "${ec2keyfile}" -a  ! -r "${ec2keyfile}.pem" ] ; then
	echo "Error: SSH KeyFile not found"
	echo "    (script checks for ${ec2keyfile} and ${ec2keyfile}.pem)"
	exit 1
fi

kp=`basename ${ec2keyfile}`
ec2-describe-keypairs --region $region 2> /dev/null  | grep -q -w $kp
if [ $? -ne 0 ] ; then
	echo "Error: AWS KeyPair ($kp) for keyfile not found in region $region"
	exit 1
fi

# We'll eventually  have known images for the different versions,
# so we can pick it if users have specified the version.  This needs
# to be adjusted to run for ALL potential regions
#	TBD : we should probably check for the existance of the image
#

if [ -n "${image:-}" ] ; then
	maprimage=$image
else
	case $maprversion in
		*)
			echo "No image available for MapR version $maprversion; sorry"
			echo "Please specify a default AMI to use for this deployment"
			exit 1
			;;
	esac
fi

ec2-describe-images --region $region $maprimage &> /dev/null
if [ $? -ne 0 ] ; then
	echo "Error: AWS Image ($maprimage) not found in region $region"
	exit 1
fi


# TBD
#	Create a security group for the cluster (eg JClouds)

echo "CHECK: ----- "
echo "	cluster $cluster"
echo "	mapr-version $maprversion"
echo "	instance $instancetype"
echo "	image $maprimage"
echo "	image_su $ec2user"
echo "	config-file $configFile"
echo "	    (nhosts $nhosts)"
echo "	key-file $ec2keyfile"
echo "	region ${region:-'default'}"
echo "OPTIONAL: ----- "
echo "	zone ${zone:-'unset'}"
echo "	dataDisks ${dataDisks:-unset}"
echo "	licenseFile ${licenseFile:-unset}"
echo "	nametag ${nametag:-unset}"
echo "	daysToLive ${daysToLive:-unset}"
echo "----- "
echo "Proceed {y/N} ? "
read YoN
if [ -z "${YoN:-}"  -o  -n "${YoN%[yY]*}" ] ; then
 	exit 1
fi

echo ""
echo "Proceeding with MapR cluster deployment ..."

# MAJOR KLUDGE
#	The launch script creates the initial repository specification
#	Because we can't pass in meta data AND a cloud-init script,
#	the MapR software version from this script will not be known
#	as the instances are spun up UNLESS we update the launch
#	script RIGHT NOW.  We know the "default setting" for
#	the variable is in the form
#		MAPR_VERSION=${MAPR_VERSION:-3.0.0-GA}
#	in the script.  Remember, sed is your friend :)
#
#	NOTE: sed on the Mac is subtlly different from Linux, so we
# 	have to handle the two operating systems differently.
#
if [ `uname -s` = "Linux" ] ; then
    sed -i''  -e "s/^MAPR_VERSION=\${MAPR.*$/MAPR_VERSION=\${MAPR_VERSION:-$maprversion}/" $MAPR_LAUNCH_SCRIPT
else
    sed -i ""  -e "s/^MAPR_VERSION=\${MAPR.*$/MAPR_VERSION=\${MAPR_VERSION:-$maprversion}/" $MAPR_LAUNCH_SCRIPT
fi


# Handle very simply for now ... no more than 4 ephemeral disks per
# instance.
if [ -n "${dataDisks}"  -a  "${dataDisks:-0}" -gt 0 ] ; then
	AMI_DISK_CONFIG="-b /dev/sdb=ephemeral0"
	if [ $dataDisks -ge 2 ] ; then
		AMI_DISK_CONFIG="$AMI_DISK_CONFIG -b /dev/sdc=ephemeral1"
	fi
	if [ $dataDisks -ge 3 ] ; then
		AMI_DISK_CONFIG="$AMI_DISK_CONFIG -b /dev/sdd=ephemeral2"
	fi
	if [ $dataDisks -ge 4 ] ; then
		AMI_DISK_CONFIG="$AMI_DISK_CONFIG -b /dev/sde=ephemeral3"
	fi
fi


# Since we've divided the instantiation of MapR nodes
# into an initial "launch" phase and a "configure"
# phase, we'll bring the cluster as follows:
#	- launch all nodes
#	- configure master nodes
#	- configure slave nodes
#
# REMEMBER: the configure is smart enough to wait for
# HDFS to come alive.
ec2-run-instances $maprimage \
	  -n $nhosts \
	  --key `basename $ec2keyfile` \
	  --user-data-file $MAPR_LAUNCH_SCRIPT \
	  --instance-type $instancetype \
	  ${AMI_DISK_CONFIG:-} \
	  --region $region \
	  --availability-zone ${zone:-${region}b} | tee eri.out

if [ $? -ne 0 ] ; then
	echo "Error spinning up nodes; cluster should be terminated"
	exit 1
elif [ $nhosts -ne `grep -c "^INSTANCE" eri.out` ] ; then
	echo "Error: ec2-run-instances did not return details for all $nhosts nodes"
	exit 1
fi


# The list is probably ordered, but let's make sure
# instances=`awk '/^INSTANCE/ {print $2}' eri.out | tr -s '\n' ' '`
instances=`grep ^INSTANCE eri.out | sort -n -k 6 | awk '{print $2}'`

# Extract key hostname/ip_data from master nodes
hosts_priv="" ; hosts_pub=""
addrs_priv="" ; addrs_pub=""
mlaunch_indexes=""
sleep 10
ec2-describe-instances --region $region $instances | \
    awk '/^INSTANCE/ {print $4" "$5" "$8" "$14" "$15}' | sort -n -k3 > edi.out

while read pub_name priv_name ami_index pub_ip priv_ip
do
	hn=${priv_name/.*/}
	if [ -n "${hosts_priv:-}" ] ; then hosts_priv=$hosts_priv','$hn
	else hosts_priv=$hn
	fi

	if [ -n "${hosts_pub:-}" ] ; then hosts_pub=$hosts_pub','$pub_name
	else hosts_pub=$pub_name
	fi

	if [ -n "${addrs_pub:-}" ] ; then addrs_pub=$addrs_pub','$pub_ip
	else addrs_pub=$pub_ip
	fi

	if [ -n "${addrs_priv:-}" ] ; then addrs_priv=$addrs_priv','$priv_ip
	else addrs_priv=$priv_ip
	fi

	if [ -n "${mlaunch_indexes:-}" ] ; then mlaunch_indexes=$mlaunch_indexes','$ami_index
	else mlaunch_indexes=$ami_index
	fi

		# Keep track of private name of first master node; That will
		# be our metrics and NFS server for inside the cluster
		# we can make this smarter if we need to later
	if [ $ami_index = "0" ] ; then
		first_master=$hn
		first_master_pub=$pub_name
	fi

done < edi.out

#	Debug output ... not necessary most of the time
# echo $hosts_priv
# echo $hosts_pub
# echo $addrs_priv
# echo $addrs_pub
# echo $mlaunch_indexes


# Now we can create the env parameter file for the nodes
#		Do this now while nodes are spinning up
#	Things we need to complete the cluster configuration
#		MAPR_VERSION	[ actually specified already ]
#		MAPR_PACKAGES	[ default to "core"; we'll update this below]
#		MAPR_NFS_SERVER [ optional ]
#
#			Metrics DB information will be added later
#		MAPR_METRICS_DEFAULT=metrics
#		MAPR_METRICS_SERVER=$(curl -f $murl_attr/maprmetricsserver)
#		MAPR_METRICS_DB=$(curl -f $murl_attr/maprmetricsdb)
#		MAPR_METRICS_DB=${MAPR_METRICS_DB:-$MAPR_METRICS_DEFAULT}
#
#		MAPR_LICENSE=$(curl -f $murl_attr/maprlicense)     OR
#		MAPR_LICENSE_FILE=$(curl -f $murl_attr/maprlicensefile)

zknodes=`grep ^$NODE_NAME_ROOT $configFile | grep zookeeper | cut -f1 -d:`
for zkh in `echo $zknodes` ; do
	zkidx=${zkh#${NODE_NAME_ROOT}}

		# We can do either hostname (without domain) or IP
	hn=`grep -e " $zkidx " edi.out | awk '{print $2}'`
	hn=${hn%%.*}

	if [ -n "${zkhosts_priv:-}" ] ; then zkhosts_priv=$zkhosts_priv','$hn
	else zkhosts_priv=$hn
	fi
done

cldbnodes=`grep ^$NODE_NAME_ROOT $configFile | grep cldb | cut -f1 -d:`
for cldbh in `echo $cldbnodes` ; do
	cldbidx=${cldbh#${NODE_NAME_ROOT}}

		# We can do either hostname (without domain) or IP
	hn=`grep -e " $cldbidx " edi.out | awk '{print $2}'`
	hn=${hn%%.*}

	if [ -n "${cldbhosts_priv:-}" ] ; then cldbhosts_priv=$cldbhosts_priv','$hn
	else cldbhosts_priv=$hn
	fi
done

# Grab just one metrics node
metricsnode=`grep ^$NODE_NAME_ROOT $configFile | grep metrics | head -1 | cut -f1 -d:`
if [ -n "$metricsnode" ] ; then
	metricsidx=${metricsnode#${NODE_NAME_ROOT}}

		# We can do either hostname (without domain) or IP
	hn=`grep -e " $metricsidx " edi.out | awk '{print $2}'`
	hn=${hn%%.*}

	MAPR_METRICS_SERVER=$hn
fi

# Save our meta data to a file for transfer to the provisioned nodes.
# Make sure the MAPR_USER and MAPR_PASSWD are carried along from
# the launch script to the configure script (yes, this is a kludge).
MAPR_PARAM_FILE=mapr_class.parm
grep "^MAPR_USER=" $MAPR_LAUNCH_SCRIPT     > $MAPR_PARAM_FILE
grep "^MAPR_PASSWD=" $MAPR_LAUNCH_SCRIPT  >> $MAPR_PARAM_FILE
echo "MAPR_VERSION=$maprversion"          >> $MAPR_PARAM_FILE
echo "MAPR_PACKAGES=core"                 >> $MAPR_PARAM_FILE
echo "cluster=$cluster"                   >> $MAPR_PARAM_FILE
echo "zknodes=$zkhosts_priv"              >> $MAPR_PARAM_FILE
echo "cldbnodes=$cldbhosts_priv"          >> $MAPR_PARAM_FILE
if [ -n "$MAPR_METRICS_SERVER:-}" ] ; then
	echo "MAPR_METRICS_SERVER=$MAPR_METRICS_SERVER"  >> $MAPR_PARAM_FILE
	echo "MAPR_METRICS_DB=metrics"                   >> $MAPR_PARAM_FILE
fi

if [ -n "${licenseFile:-}"  -a  -f "${licenseFile:-/}" ] ; then
	echo "MAPR_LICENSE_FILE=/tmp/.MapRLicense.txt"   >> $MAPR_PARAM_FILE
fi

# To make the next step work, we need to have the
# key-file here on the local system for use with ssh.
# Assume it's just the key-file with a .pem extension in
# our home directory
if [ -f ${ec2keyfile} ] ; then
	MY_SSH_KEY=${ec2keyfile}
elif [ -f ${ec2keyfile}.pem ] ; then
	MY_SSH_KEY=${ec2keyfile}.pem
elif [ -f $HOME/.ssh/${ec2keyfile} ] ; then
	MY_SSH_KEY=$HOME/.ssh/${ec2keyfile}
else
	MY_SSH_KEY=$HOME/.ssh/${ec2keyfile}.pem
fi
if [ ! -r $MY_SSH_KEY ] ; then
	echo "Cannot continue configuration"
	echo "SSH_KEY {$MY_SSH_KEY} not found"
	exit 1
fi

# TBD: Need to fix these loops to have maximum iterations
echo "Waiting for allocation of $nhosts nodes from Amazon"
PTIME=10
pending=$nhosts
while [ $pending -gt 0 ] ; do
	echo "$[nhosts-$pending] instances allocated; waiting $PTIME seconds"
	sleep $PTIME
	pending=`ec2-describe-instances --region $region $instances | \
		awk '/^INSTANCE/ {print $6}' | \
		grep -c pending`
done

# Now's the time to tag our instances with rational names.
#	Again, start with 0 since the AMI indexes start with that
#	The Training group likes the nametag FIRST; if there
#	is no nametag, put the cluster name FIRST.
let mindex=0
for mstr in $instances
do
#	mtag="${NODE_NAME_ROOT}${mindex}-${cluster%%.*}${tagSuffix}"
	if [ -n "${nametag}" ] ; then
		mtag="${tagSuffix#-}-${cluster%%.*}-${NODE_NAME_ROOT}${mindex}"
	else
		mtag="${cluster%%.*}${tagSuffix}-${NODE_NAME_ROOT}${mindex}"
	fi
	ec2-create-tags --region $region $mstr --tag Name=$mtag
	let mindex=$mindex+1
done


# At this point, we want key-based ssh only (even if the server
# allows password authentication).  The BatchMode flag forces that.
MY_SSH_OPTS="-i $MY_SSH_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes"

echo "Waiting for mapr user to become configured on all nodes"
mapr_user_found=0
while [ $mapr_user_found -ne $nhosts ] ; do
	echo "$mapr_user_found systems found with MAPR_USER; waiting for $nhosts"
	sleep $PTIME
	let mapr_user_found=0
	for node in `echo ${hosts_pub//,/ }`
	do
		ssh $MY_SSH_OPTS $MAPR_USER@${node} \
			-n "ls ~${MAPR_USER}/${MAPR_LAUNCH_SCRIPT}" 2> /dev/null
		[ $? -ne 0 ] && break
		let mapr_user_found=$mapr_user_found+1
	done
done

echo "Ready to configure MapR software with"
cat $MAPR_PARAM_FILE
echo ""
# echo "Proceed {y/N} ? "
# read YoN
if [ -z "${YoN:-}"  -o  -n "${YoN%[yY]*}" ] ; then
	echo ""
	echo " ... aborting installation; be sure to delete instances "
 	exit 1
fi

# Need to get smarter here about a few things:
#	we should configure and start ZK nodes first
#	timing: when is the instance ready for scp and ssh
#	Ubuntu vs CentOS AMI's  (remote root access)
for node in `echo ${hosts_pub//,/ }`
do
	hidx=`grep ${node} edi.out | awk '{print $3}'`
	hn=${node%%.*}
	host_param_file=/tmp/mapr_${hn}.parm
	hpkgs=`grep "^${NODE_NAME_ROOT}${hidx}:" $configFile | cut -f2 -d:`
	sed "s/^MAPR_PACKAGES=.*$/MAPR_PACKAGES=${hpkgs}/" $MAPR_PARAM_FILE \
		> $host_param_file

	scp $MY_SSH_OPTS $MAPR_CONFIG_SCRIPT ${MAPR_USER}@${node}:
	scp $MY_SSH_OPTS $host_param_file ${MAPR_USER}@${node}:mapr.parm
	if [ -n "${licenseFile:-}" ] ; then
	  scp $MY_SSH_OPTS $licenseFile ${MAPR_USER}@${node}:/tmp/.MapRLicense.txt
	fi

	echo "Time to run $MAPR_CONFIG_SCRIPT"
	if [ $ec2user = "root" ] ; then
		ssh $MY_SSH_OPTS ${ec2user}@${node} \
			-n "~${MAPR_USER}/$MAPR_CONFIG_SCRIPT" &
	else
		ssh $MY_SSH_OPTS ${ec2user}@${node} \
			-n "sudo ~${MAPR_USER}/$MAPR_CONFIG_SCRIPT" &
	fi

done
wait


# We'll assemble a hosts file (to aid in connecting to
# the cluster from outside.
#
# Additionally, we'll take this opportunity to set up
# the clush configuration on node 0 to access all other nodes
# (as we do this ALL THE TIME)

cluster_hosts_file=./hosts.${cluster%%.*}
echo "" > $cluster_hosts_file

#	NOTE: the "ntag" value below should be computed the same
#	way we compute "mtag" above when using the EC2 routine to
#	tag tie instances ... but it's not a big deal for now
echo "Cluster $cluster launched with $nhosts node(s)."

while read pub_name priv_name ami_index pub_ip priv_ip
do
	[ -z "${nodeZero}" ] && nodeZero=$pub_name
	if [ -z "${clist}" ] ; then
		clist=${priv_name%%.*}
	else
		clist="${clist},${priv_name%%.*}"
	fi

	ntag=${NODE_NAME_ROOT}${ami_index}-${cluster%%.*}${tagSuffix}

#	echo "    ${NODE_NAME_ROOT}${ami_index}: $pub_name (${priv_name%%.*})"
	echo "    $ntag: $pub_name (${priv_name%%.*})"
	echo "$pub_ip	${NODE_NAME_ROOT}${ami_index}  ${priv_name%%.*}  ${pub_name%%.*}  $ntag" >> $cluster_hosts_file

	if [ -n "${daysToLive:-}" ] ; then
		if [ $ec2user = "root" ] ; then
			ssh $MY_SSH_OPTS ${ec2user}@${pub_ip} \
				-n "echo 'shutdown -Py now' | at now +$daysToLive days" &> /dev/null
		else
			ssh $MY_SSH_OPTS ${ec2user}@${pub_ip} \
				-n "echo 'shutdown -Py now' | sudo at now +$daysToLive days" &> /dev/null
		fi
	fi
done < edi.out

echo "	(details in $cluster_hosts_file)"

echo ""
echo "Configuring clush on $nodeZero"
cat > groups.clush << GCEOF
all: $clist
GCEOF

if [ -f groups.clush ] ; then
	scp $MY_SSH_OPTS groups.clush ${ec2user}@${nodeZero}:/tmp

	if [ $ec2user = "root" ] ; then
		ssh $MY_SSH_OPTS ${ec2user}@${nodeZero} \
			-n "[ -d /etc/clustershell ] && cp /tmp/groups.clush /etc/clustershell/groups"
	else
		ssh $MY_SSH_OPTS ${ec2user}@${nodeZero} \
			-n "[ -d /etc/clustershell ] && sudo cp /tmp/groups.clush /etc/clustershell/groups"
	fi
fi

echo ""
echo "Opening MCS port in security group configuration for this cluster"

# All the instances will be in the same security group ... so we just
# do this once for the first instance in our known list.   The output
# from ec2-authorize is pretty verbose, so we'll just swallow it.
#
# Lots of errors from describe-instance-attribute; no easy way to work
# around them, so just try all instances in case one works.
#	TBD : catch and report errors
for inst in $instances
do
	sg=`ec2-describe-instance-attribute $inst --region $region --group-id 2>/dev/null | awk '{print $3}'`
	if [ -n "${sg}" ] ; then
		ec2-authorize $sg --region $region -P tcp -p 8443 -s 0.0.0.0/0 &> /dev/null
		break
	fi
done

echo ""
echo "Check /tmp/*-mapr.log files on each node to confirm proper instantiation."
echo "The MCS console can be accessed via the following url(s): "
uinodes=`grep ^$NODE_NAME_ROOT $configFile | grep webserver | cut -f1 -d:`
for uih in `echo $uinodes`
do
	uiidx=${uih#${NODE_NAME_ROOT}}
	hn=`grep -e " $uiidx " edi.out | awk '{print $1}'`
	echo "	https://$hn:8443"
done
