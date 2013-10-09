#!/bin/bash
#
#   $File: launch-se-cluster.sh $
#   $Date: Wed Sep 04 12:50:33 2013 -0700 $
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
#	- cloud-init AMI's are required
#		- BUT, cloud-init AMI's with java pre-installed may fail when the
#			non-boot disks cannot be re-purposed to MapRFS
#	- the 'key name' in AWS should match the file name specified here 
#
#
# EXAMPLES (that have actually worked)
#		# With Vanilla CentOS AMI
#	 ./launch-class-cluster.sh \
#		--cluster dbt \
#		--mapr-version 3.0.1 \
#		--config-file class/5node.lst \
#		--region us-west-2
#		--key-file ~/.ssh/tucker-eng \
#		--image ami-72ce4642 \
#		--image-su ec2-user  \
#		--instance-type m1.large \
#		--data-disks 3 \
#		--nametag foobar \
#		--days-to-live 1
#
#		# With Ubuntu AMI
#	 ./launch-class-cluster.sh \
#		--cluster train \
#		--mapr-version 3.0.1 \
#		--config-file class/3node.lst \
#		--region us-west-2
#		--key-file ~/.ssh/tucker-eng \
#		--image ami-feb931ce \
#		--image-su ubuntu  \
#		--instance-type m1.large \
#		--data-disks 3 
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
NAT_CONFIG_SCRIPT=configure-pat.sh
VPC_CONFIG_SCRIPT=configure-vpc-cluster.sh

NODE_NAME_ROOT=node		# used in config file to define nodes for deployment

# Try to save off the output of ec2 commands ... /dev/null if we can't
ec2cmd_err=./ec2cmd.err
touch $ec2cmd_err
[ $? -ne 0 ] && ec2cmd_err="/dev/null"


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
       [ --sgroup ec2-security-group ]
       [ --license-file <license to be installed> ]
       [ --data-disks <# of ephemeral disks to FORCE into the AMI> ]
       [ --persistent-disks <# disks>x<disk_size> ]
       [ --nametag <uniquifying cluster tag> ]
       [ --days-to-live <max lifetime> ]
   "
  echo ""
  echo "EXAMPLES"
  echo "  $0 --cluster MyCluster --mapr-version 2.1.3 --config-file class/3node.lst --region us-west-2 --key-file ~/.ssh/ec2-private-key.pem  --image ami-72ce4642 --image-su ec2-user --instance-type m1.large"
}


check_ec2_env() {
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
}


# Generate the file "edi.out" that contains the key access details
# for our deployment (public/private hostnames, IP's, and the AMI index)
# We have to be careful if we're in a VPC, since there will be 
# no public addresses (and we'll have to add them later
#
gen_edi_file() {
		# Extract key hostname/ip_data from master nodes
	hosts_priv="" ; hosts_pub=""
	addrs_priv="" ; addrs_pub=""
	mlaunch_indexes=""

		# When a VPC is selected, there will NOT be any 
		# public address during the initial spin-up ... so we'll have
		# to fake it
	if [ -n "$vpcID" ] ; then
		ec2-describe-instances --region $region $instances | \
    		awk '/^INSTANCE/ {print $7" unknown_host"$7" "$4" uknown_ip "$13}' | \
			sort -n -k1 > edi.out
	else 
		ec2-describe-instances --region $region $instances | \
    		awk '/^INSTANCE/ {print $8" "$4" "$5" "$14" "$15}' | \
			sort -n -k1 > edi.out
	fi

	while read ami_index pub_name priv_name pub_ip priv_ip
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
}


# Function to generate the parameter file to be passed in to
# the nodes as "input" to the configure-mapr-instance.sh script.
# We can do this while the nodes are spinning up ... all we need
# are the private internal addresses.
#
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
#
# All references are to PRIVATE hostnames ... which should work
# for VPC and regular environments.
#
gen_param_file() {
	zknodes=`grep ^$NODE_NAME_ROOT $configFile | grep zookeeper | cut -f1 -d:`
	for zkh in `echo $zknodes` ; do
		zkidx=${zkh#${NODE_NAME_ROOT}}
	
			# We can do either hostname (without domain) or IP
		hn=`grep -e "^$zkidx " edi.out | awk '{print $3}'`
		hn=${hn%%.*}

		if [ -n "${zkhosts_priv:-}" ] ; then zkhosts_priv=$zkhosts_priv','$hn
		else zkhosts_priv=$hn
		fi
	done

	cldbnodes=`grep ^$NODE_NAME_ROOT $configFile | grep cldb | cut -f1 -d:`
	for cldbh in `echo $cldbnodes` ; do
		cldbidx=${cldbh#${NODE_NAME_ROOT}}
	
			# We can do either hostname (without domain) or IP
		hn=`grep -e "^$cldbidx " edi.out | awk '{print $3}'`
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
		hn=`grep -e "^$metricsidx " edi.out | awk '{print $3}'`
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

}

# Wait for instances to be allocated and then assign
# rational tags.  We'll exit out if the instances don't come
# live after 15 minutes
#
tag_pending_instances() {
		# ec2-describe-instances will show "pending" until the instance
		# has been allocated and launched.   The location of that string
		# varies depending on VPC ... so we'll grep the whole output.
	echo "Waiting for allocation of $nhosts nodes from Amazon"
	PTIME=10
	PWAIT=900		# wait no more than 15 minutes
	pending=$nhosts
	while [ $pending -gt 0  -a  $PWAIT -gt 0 ] ; do
		echo "$[nhosts-$pending] instances allocated; waiting $PTIME seconds"
		sleep $PTIME
		PWAIT=$[PWAIT - $PTIME]
		pending=`ec2-describe-instances --region $region $instances | \
			grep "^INSTANCE" | grep -c pending`
	done

	if [ $pending -gt 0 ] ; then
		echo "Failed to launch all $nhosts instances; aborting"
		exit 1
	fi

		# Now's the time to tag our instances with rational names.
		#	Again, start with 0 since the AMI indexes start with that
		#	The Training group likes the nametag FIRST; if there
		#	is no nametag, put the cluster name FIRST.
	idx=0
	for inst in $instances
	do
		#	mtag="${NODE_NAME_ROOT}${idx}-${cluster%%.*}${tagSuffix}"
		if [ -n "${nametag}" ] ; then
			mtag="${tagSuffix#-}-${cluster%%.*}-${NODE_NAME_ROOT}${idx}"
		else
			mtag="${cluster%%.*}${tagSuffix}-${NODE_NAME_ROOT}${idx}"
		fi
		ec2-create-tags --region $region $inst --tag Name=$mtag
		idx=$[idx+1]
	done

}

# When launching a new cluster, we wait for the mapr user to
# be visible on all public nodes ... since that means that we
# can proceed with the configuration operations.
#
wait_for_launch_complete() {
	echo "Waiting for mapr user to become configured on all public nodes" 

	npubhosts=0
	while read ami_index pub_name priv_name pub_ip priv_ip
	do
#		if [ $pub_name != "unknown_name" ] ; then
		if [ $pub_name = "${pub_name#unknown_}" ] ; then
			pub_hosts="${pub_hosts:-} $pub_name"
			npubhosts=$[npubhosts + 1]
		fi
	done < edi.out

	mapr_user_found=0
	while [ $mapr_user_found -ne $npubhosts ] ; do
		echo "$mapr_user_found systems found with MAPR_USER; waiting for $npubhosts"
		sleep $PTIME
		mapr_user_found=0
		for node in $pub_hosts
		do
			ssh $MY_SSH_OPTS $MAPR_USER@${node} \
				-n "ls ~${MAPR_USER}/${MAPR_LAUNCH_SCRIPT}" &> /dev/null
			[ $? -ne 0 ] && break
			mapr_user_found=$[mapr_user_found+1]
		done
	done

	echo "" 
}

# In VPC configs, we need to allocate an IP address
# and assign it to node 0
allocate_and_assign_eip() {

	while `true` ; do
		eaa_output=( $(ec2-allocate-address -region $region -d vpc) )
		addr=${eaa_output[1]}
		alloc_id=${eaa_output[3]}

			# No elaborate error checking for now
			# Most common error condition is "insufficient EIP's"
		if [ -z "${addr}" ] ; then
			echo "ec2-allocate-address failed to provide EIP"
			echo ""
			echo "Try again {Y/n} ? "
			read YoN
			YoN=${YoN:-Y}
			if [ -n "${YoN%[yY]*}" ] ; then
				echo "Abandoning deployment; be sure to clean up instances"
 				exit 1
			fi
		else
			echo "EIP address $addr created"
			break
		fi
	done

#		You'd think that eri.out would be consistent enough for
#		this to work, but you'd be WRONG !!!  We have to carefull
#		grep for the LAUNCH_INDEX surrounded by two tabs.
#		The alternative would be to issue another describe-instances
#		call with a filter for the index and the tag:Name field, 
#		but that may not be specific enough.
	instance=`grep ^INSTANCE eri.out | grep "	0	" | awk '{print $2}'` 

	if [ -n "$instance" ] ; then
		ec2-associate-address -region $region -i $instance \
			-a $alloc_id  --allow-reassociation &> $ec2cmd_err
		if [ $? -ne 0 ] ; then
			echo "ec2-associate-address failed"
			exit 1
		else
			echo "Address associated with instance $instance (node0)"
		fi
	else
		echo "Unable to determine instance id of node0; cannot associate EIP"
		echo "Associate address by hand and proceed ? "
		echo ""
		echo "Proceed {y/N} ? "
		read YoN
		if [ -z "${YoN:-}"  -o  -n "${YoN%[yY]*}" ] ; then
 			exit 1
		fi
	fi

		# Regenerate the edi entry for node 0
		# and recreate the edi file
	mv edi.out edi.out.orig

	ec2-describe-instances --region $region $instance | \
   		awk '/^INSTANCE/ {print $8" "$4" "$5" "$14" "$15}' > edi.out
	grep -v "^0 " edi.out.orig >> edi.out
}

# Initialize the gateway node (node 0) to be the NAT for
# the remaining instances.  See 
# http://docs.aws.amazon.com/AmazonVPC/latest/UserGuide/VPC_NAT_Instance.html
#
initialize_vpc_nat() {
	gateway=( $(grep "^0 " edi.out) )
	ami_index=${gateway[0]}
	pub_name=${gateway[1]}

	scp $MY_SSH_OPTS $NAT_CONFIG_SCRIPT ${ec2user}@${pub_name}:

	echo "Executing $NAT_CONFIG_SCRIPT on cluster node 0"
	if [ $ec2user = "root" ] ; then
		ssh $MY_SSH_OPTS ${ec2user}@${pub_name} \
			-n "~${ec2user}/$NAT_CONFIG_SCRIPT"
	else
		ssh $MY_SSH_OPTS ${ec2user}@${pub_name} \
			-n "sudo ~${ec2user}/$NAT_CONFIG_SCRIPT"
	fi

		# We know the gateway is instance 0, so we can break 
		# after the first execution of this (remember, the instances
		# list is sorted).
	for inst in $instances ; do
		ec2-modify-instance-attribute $inst --region $region \
			--source-dest-check false
		break
	done
}

# Configuring a VPC cluster is a little more complex.
# Basically, we use the gateway node (node 0) and 
# copy everything up there (including our private key)
# so that things can work at the other end
configure_vpc_cluster() {
	host_param_file=/tmp/mapr_0.parm
	gateway=( $(grep "^0 " edi.out) )
	ami_index=${gateway[0]}
	pub_name=${gateway[1]}
	hpkgs=`grep "^${NODE_NAME_ROOT}${ami_index}:" $configFile | cut -f2 -d:`
	sed "s/^MAPR_PACKAGES=.*$/MAPR_PACKAGES=${hpkgs}/" $MAPR_PARAM_FILE \
		> $host_param_file

	scp $MY_SSH_OPTS $MAPR_CONFIG_SCRIPT ${MAPR_USER}@${pub_name}:
	scp $MY_SSH_OPTS $host_param_file ${MAPR_USER}@${pub_name}:mapr.parm
	if [ -n "${licenseFile:-}" ] ; then
  		scp $MY_SSH_OPTS $licenseFile ${MAPR_USER}@${pub_name}:/tmp/.MapRLicense.txt
	fi

		# Copy the SSH key to the gateway user so we can 
		# do what we need to do from the gateway.
	scp $MY_SSH_OPTS $MAPR_CONFIG_SCRIPT ${ec2user}@${pub_name}:
	scp $MY_SSH_OPTS $MAPR_PARAM_FILE ${ec2user}@${pub_name}:
	scp $MY_SSH_OPTS $MY_SSH_KEY ${ec2user}@${pub_name}:.ssh/vpc_private_key

		# Then copy the other files we'll need
	scp $MY_SSH_OPTS $configFile          ${ec2user}@${pub_name}:mapr_roles.lst
	scp $MY_SSH_OPTS $MAPR_PARAM_FILE     ${ec2user}@${pub_name}:
	scp $MY_SSH_OPTS edi.out              ${ec2user}@${pub_name}:
	scp $MY_SSH_OPTS $VPC_CONFIG_SCRIPT   ${ec2user}@${pub_name}:

		# Everything is in place ... now we just remotely execute the 
		# VPC_CONFIG_SCRIPT to finish up the install.
		#
		# The logic here is to WAIT for the script to complete.
	echo "Time to run $VPC_CONFIG_SCRIPT"
	ssh $MY_SSH_OPTS ${ec2user}@${pub_name} \
		-n "~${ec2user}/$VPC_CONFIG_SCRIPT"

}


# Need to get smarter here about a few things: 
#	we should configure and start ZK nodes first
configure_public_cluster() {
	while read ami_index pub_name priv_name pub_ip priv_ip
	do
		hn=${pub_name%%.*}
		host_param_file=/tmp/mapr_${hn}.parm
		hpkgs=`grep "^${NODE_NAME_ROOT}${ami_index}:" $configFile | cut -f2 -d:`
		sed "s/^MAPR_PACKAGES=.*$/MAPR_PACKAGES=${hpkgs}/" $MAPR_PARAM_FILE \
			> $host_param_file
	
			# For VPC clusters, use the first node as the gateway
			# and indirectly do the same thing we do everywhere else
		scp $MY_SSH_OPTS $MAPR_CONFIG_SCRIPT ${MAPR_USER}@${pub_name}:
		scp $MY_SSH_OPTS $host_param_file ${MAPR_USER}@${pub_name}:mapr.parm
		if [ -n "${licenseFile:-}" ] ; then
  			scp $MY_SSH_OPTS $licenseFile ${MAPR_USER}@${pub_name}:/tmp/.MapRLicense.txt
		fi

		echo "Time to run $MAPR_CONFIG_SCRIPT"
		if [ $ec2user = "root" ] ; then
			ssh $MY_SSH_OPTS ${ec2user}@${pub_name} \
				-n "~${MAPR_USER}/$MAPR_CONFIG_SCRIPT" &
		else
			ssh $MY_SSH_OPTS ${ec2user}@${pub_name} \
				-n "sudo ~${MAPR_USER}/$MAPR_CONFIG_SCRIPT" &
		fi

	done < edi.out
	wait
}


# We'll assemble a hosts file (to aid in connecting to
# the cluster from outside.
#
# Additionally, we'll take this opportunity to set up 
# the clush configuration on node 0 to access all other nodes
# (as we do this ALL THE TIME) 
#
#	NOTE: the "ntag" value below should be computed the same
#	way we compute "mtag" in tag_pending_instnaces when using 
#	the EC2 routine to tag tie instances ... 
#	but it's not a big deal for now
#
finalize_public_cluster() {
	cluster_hosts_file=./hosts.${cluster%%.*}
	echo "" > $cluster_hosts_file

	while read ami_index pub_name priv_name pub_ip priv_ip
	do
		[ -z "${nodeZero}" ] && nodeZero=$pub_name
		if [ -z "${clist}" ] ; then
			clist=${priv_name%%.*}
		else
			clist="${clist},${priv_name%%.*}"
		fi

		ntag=${NODE_NAME_ROOT}${ami_index}-${cluster%%.*}${tagSuffix}

#		echo "    ${NODE_NAME_ROOT}${ami_index}: $pub_name (${priv_name%%.*})"
		echo "    $ntag: $pub_name (${priv_name%%.*})"
		echo "$pub_ip	${NODE_NAME_ROOT}${ami_index}  ${priv_name%%.*}  ${pub_name%%.*}  $ntag" >> $cluster_hosts_file

		if [ -n "${daysToLive:-}" -a $pub_ip = "${pub_ip#unknown_}" ] ; then
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

		# Copy the file into place on nodeZero, and then issue
		# a preliminary clush command to seed the known-hosts file
	if [ -f groups.clush ] ; then
		scp $MY_SSH_OPTS groups.clush ${ec2user}@${nodeZero}:/tmp 

		if [ $ec2user = "root" ] ; then
			ssh $MY_SSH_OPTS ${ec2user}@${nodeZero} \
				-n "[ -d /etc/clustershell ] && cp /tmp/groups.clush /etc/clustershell/groups" 
			ssh $MY_SSH_OPTS ${ec2user}@${nodeZero} \
				-n "clush -a -o '-oStrictHostKeyChecking=no' date" &> /dev/null
		else
			ssh $MY_SSH_OPTS ${ec2user}@${nodeZero} \
				-n "[ -d /etc/clustershell ] && sudo cp /tmp/groups.clush /etc/clustershell/groups" 
			ssh $MY_SSH_OPTS ${ec2user}@${nodeZero} \
				-n "sudo clush -a -o '-oStrictHostKeyChecking=no' date" &> /dev/null
		fi
	fi
}

# Open firewall holes for MapR ports in the security group into
# which we've deployed the cluster.
#
# All the instances will be in the same security group ... so we just
# do this once for the first instance in our known list.   The output
# from ec2-authorize is pretty verbose, so we'll just swallow it.  
#
# Lots of errors from describe-instance-attribute; no easy way to work
# around them, so just try all instances in case one works.
#	BIGGER PROBLEM : --group-id is broken in the interface
#		if we don't get an answer, just look for default security group
#		and update that one.
update_security_group() {
	for inst in $instances
	do
		sg=`ec2-describe-instance-attribute $inst --region $region --group-id 2> $ec2cmd_err | awk '{print $NF}'`
		[ -n "${sg}" ] && break
	done

		# If we specified a group, be sure to pick that one
	[ -z "${sg}"  -a  -n "${sgroup}" ] && sg=$sgroup

		# Otherwise, assume we're in the default group for this region
	if [ -z "${sg}" ] ; then
		sg=`ec2-describe-group --region $region --filter="group-name=default" 2> $ec2cmd_err | grep ^GROUP | awk '{print $2}'`
	fi

	if [ -n "${sg}" ] ; then
            # Main ports for web services
		for p in 8080 8443 7221 9001 50030 50060 ; do
			ec2-authorize $sg --region $region -P tcp -p $p -s 0.0.0.0/0 &> $ec2cmd_err
		done

            # NFS ports 
		for p in 111 2049 ; do
			ec2-authorize $sg --region $region -P tcp -p $p -s 0.0.0.0/0 &> $ec2cmd_err
		done
		ec2-authorize $sg --region $region -P udp -p 111 -s 0.0.0.0/0 &> $ec2cmd_err
	fi

}


###############  START HERE ##################

# Before we start, make sure the env is set up properly
check_ec2_env


# Parse and validate command line args 
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
  --sgroup)       sgroup=$2 ;;
  --data-disks)   dataDisks=$2 ;;
  --persistent-disks)   dataDisks=$2 ;;
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
maprversion=${maprversion:-"3.0.1"}
instancetype=${instancetype:-"m1.large"}
region=${region:-"us-west-2"}
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

# Sanity check key ... this is more complex than it should be
# At the end of this logic
#	MY_SSH_KEY is set to the file to use here on the client
#	ec2keypair is set to the TAG to use for Amazon ... not a full file
#
# Prepend $PWD or $HOME/.ssh if keyfile is not a full path
if [ "${ec2keyfile}" = "${ec2keyfile#/}" ] ; then
	if [ -f $PWD/${ec2keyfile} ] ; then
		MY_SSH_KEY=$PWD/${ec2keyfile}
	elif [ -f $PWD/${ec2keyfile}.pem ] ; then
		MY_SSH_KEY=$PWD/${ec2keyfile}.pem
	elif [ -f $HOME/.ssh/${ec2keyfile} ] ; then
		MY_SSH_KEY=$HOME/.ssh/${ec2keyfile}
	elif [ -f $HOME/.ssh/${ec2keyfile}.pem ] ; then
		MY_SSH_KEY=$HOME/.ssh/${ec2keyfile}.pem
	fi
else
	if [ -f ${ec2keyfile} ] ; then
		MY_SSH_KEY=${ec2keyfile}
	elif [ -f ${ec2keyfile}.pem ] ; then
		MY_SSH_KEY=${ec2keyfile}.pem
	fi
fi

if [ -z "${MY_SSH_KEY}" ] ; then
	echo "Error: SSH KeyFile not found"
	echo "    (script checks for ${ec2keyfile} and ${ec2keyfile}.pem)"
	exit 1
fi

	# We may need to strip off the file suffix ... so check for both
kp=`basename ${ec2keyfile}`
ec2-describe-keypairs --region $region 2> $ec2cmd_err | \
	grep -q -w -e $kp -e ${kp%.*}
if [ $? -ne 0 ] ; then
	echo "Error: AWS KeyPair ($kp) for keyfile not found in region $region"
	exit 1
fi
ec2keypair=`basename ${ec2keyfile}`
ec2keypair=${ec2keypair%.*}


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

ec2-describe-images --region $region $maprimage &> $ec2cmd_err  
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
echo "	key-file $MY_SSH_KEY ($ec2keypair)"
# echo "	key-file $ec2keyfile"
echo "	region ${region:-'default'}"
echo "OPTIONAL: ----- "
echo "	zone ${zone:-'unset'}"
echo "	security group ${sgroup:-'unset'}"
echo "	subnet ${subnet:-'unset'}"
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

startTime=$(date +"%H:%M:%S")
echo ""
echo "Proceeding with MapR cluster deployment at $startTime ..." 


# Handle very simply for now ... no more than 4 ephemeral disks per
# instance and no more than 12 persistent disks.
#
#	Remember that persistent disks are represented by "<n>x<size>"
#	in the dataDisks variable, while ephemeral disks are simply "<n>"
#
if [ -n "${dataDisks}"  ] ; then
	ndisk="${dataDisks%x*}"
	[ $ndisk != $dataDisks ] && dsize="${dataDisks#*x}"

	if [ -z "$dsize"  -a  "${ndisk:-0}" -gt 0 ] ; then
		[ ${ndisk} -gt 4 ] && ndisk=4

		AMI_DISK_CONFIG="-b /dev/sdb=ephemeral0"
		i=1
		dev=c
		while [ $i -lt $[ndisk-1] ] ; do
			AMI_DISK_CONFIG="$AMI_DISK_CONFIG -b /dev/sd${dev}=ephemeral${i}"
			i=$[i+1]
			dev=`echo $dev | tr 'a-y' 'b-z'`
		done
	elif [ ${dsize:-0} -gt 0  -a  ${ndisk:-0} -gt 0 ] ; then
		[ ${ndisk} -gt 8 ] && ndisk=8
		
		AMI_DISK_CONFIG="--ebs-optimized true"
		i=0
		dev=b
		while [ $i -lt ${ndisk} ] ; do
			AMI_DISK_CONFIG="$AMI_DISK_CONFIG -b /dev/sd${dev}=:${dsize}"
			i=$[i+1]
			dev=`echo $dev | tr 'a-y' 'b-z'`
		done
	fi

	if [ -n "${AMI_DISK_CONFIG}" ] ; then 
		echo "	AMI_DISK_CONFIG=${AMI_DISK_CONFIG}" 
		echo ""
	fi
fi

# If there is a security group and a subnet passed on the command line,
# pass them in to our create instance operation.  We need a subnet
# for all VPC groups, so grab one if we see a VPC group specified.
#	NOTE this is DANGEROUS, since we can't easily get the VPC id from
#	describe group.
#
#	NOTE: the vpcID value set in these lines is used in MULTIPLE places
#	throughout the script.
#
if [ -n "${sgroup}" ] ; then
	SG_ARG="--group $sgroup"

		# If a subnet was not specified explicitly, 
		# list all subnets for the group and grab the first one
	gline=`ec2-describe-group --region $region $sgroup | grep ^GROUP`
	if [ -n "$gline" ] ; then
		for gfield in $gline ; do
			[ ${gfield} != ${gfield#vpc-} ] && vpcID=$gfield
		done
	fi

		# Grab the first subnet in this VPC
	if [ -z "${subnet}" -a  -n "$vpcID" ] ; then 
		subnets=`ec2-describe-subnets --region $region --filter="vpc-id=$vpcID" | grep ^SUBNET | grep available | awk '{print $2}'`
		for snet in $subnets
		do
			subnet=$snet
			break
		done
	fi
	[ -n "${subnet}" ] && SG_ARG="$SG_ARG --subnet $subnet"
fi

# We want a specific Availability Zone  ONLY  if we don't 
# hava a subnet (since the subnets carry an availability zone by default)
if [ -z "$vpcID" ] ; then
	AZ_ARG="--availability-zone ${zone:-${region}b}"
fi

# Since we've divided the instantiation of MapR nodes
# into an initial "launch" phase and a "configure"
# phase, we'll bring the cluster as follows:
#	- launch all nodes
#	- configure master nodes
#	- configure slave nodes
#
# REMEMBER: the configure-mapr-instance.sh script is smart enough 
# to wait for HDFS to come alive when we launch it later.
#
ec2-run-instances $maprimage \
	  -n $nhosts \
	  --key $ec2keypair \
	  --user-data-file $MAPR_LAUNCH_SCRIPT \
	  --instance-type $instancetype \
	  ${AMI_DISK_CONFIG:-} \
	  --region $region \
	  ${SG_ARG:-} \
	  ${AZ_ARG:-} | tee eri.out

if [ $? -ne 0 ] ; then
	echo "Error spinning up nodes; cluster should be terminated"
	exit 1
elif [ $nhosts -ne `grep -c "^INSTANCE" eri.out` ] ; then
	echo "Error: ec2-run-instances did not return details for all $nhosts nodes"
	exit 1
fi


# The list is probably ordered, but let's make sure
#	Of course, the darn output has different fields when it
#	is inside a VPC or not.  INSANE !!!
# instances=`awk '/^INSTANCE/ {print $2}' eri.out | tr -s '\n' ' '`
ami_idx=6
[ -n "$vpcID" ] && ami_idx=$[ami_idx+1]
instances=`grep ^INSTANCE eri.out | sort -n -k $ami_idx | awk '{print $2}'`

sleep 10
gen_edi_file

gen_param_file

tag_pending_instances

if [ -n "$vpcID" ] ; then
	allocate_and_assign_eip
fi

# At this point, we want key-based ssh only (even if the server
# allows password authentication).  The BatchMode flag forces that.
MY_SSH_OPTS="-i $MY_SSH_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes"

wait_for_launch_complete

echo "Ready to configure MapR software with"
# cat $MAPR_PARAM_FILE
grep -v ^MAPR_PACKAGES  $MAPR_PARAM_FILE

echo ""
# echo "Proceed {y/N} ? "
# read YoN
if [ -z "${YoN:-}"  -o  -n "${YoN%[yY]*}" ] ; then
	echo ""
	echo " ... aborting installation; be sure to delete instances "
 	exit 1
fi

if [ -n "$vpcID" ] ; then
	initialize_vpc_nat
	configure_vpc_cluster
else
	configure_public_cluster
fi


echo "Cluster $cluster launched with $nhosts node(s)."

finalize_public_cluster


echo ""
echo "Opening MCS port in security group configuration for this cluster"

update_security_group


echo ""
echo "Check /tmp/*-mapr.log files on each node to confirm proper instantiation."
echo "The MCS console can be accessed via the following url(s): "
uinodes=`grep ^$NODE_NAME_ROOT $configFile | grep webserver | cut -f1 -d:`
for uih in `echo $uinodes`
do
	uiidx=${uih#${NODE_NAME_ROOT}}
	hn=`grep -e "^$uiidx " edi.out | awk '{print $2}'`
	echo "	https://$hn:8443"
done

endTime=$(date +"%H:%M:%S")
echo ""
echo "MapR cluster deployment began at  $startTime and finished at $endTime" 
